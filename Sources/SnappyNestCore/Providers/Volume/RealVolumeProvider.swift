import CoreAudio
import AudioToolbox
import Foundation

/// Core Audio backed volume provider. Public-API only; no private symbols.
///
/// * Reads the default output device's master `kAudioDevicePropertyVolumeScalar`.
/// * Falls back to left-channel (element 1) if master is not present.
/// * Re-binds on `kAudioHardwarePropertyDefaultOutputDevice` change.
/// * Surfaces `.unavailable` for fixed-volume devices (HDMI / S-PDIF).
/// * Suppresses the ~100 ms echo after our own write.
public final class RealVolumeProvider: VolumeProvider {
    public private(set) var capability: ProviderCapability = .unavailable(reason: "unbound")
    public private(set) var value: Double = 0
    public private(set) var isMuted: Bool = false

    private var handlers: [(Double, Bool) -> Void] = []
    private var currentDevice: AudioDeviceID = kAudioObjectUnknown
    private var currentChannel: UInt32 = kAudioObjectPropertyElementMain
    private var usesVirtualMaster = false
    private var usesSystemVolumeScript = false
    private var writeInFlightUntil: Date = .distantPast

    public init() {
        bindDefaultDevice()
        var defaultAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let self_ = Unmanaged.passUnretained(self).toOpaque()
        AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject), &defaultAddr,
            { _, _, _, ctx -> OSStatus in
                if let ctx = ctx {
                    let s = Unmanaged<RealVolumeProvider>.fromOpaque(ctx).takeUnretainedValue()
                    DispatchQueue.main.async { s.bindDefaultDevice() }
                }
                return noErr
            },
            self_
        )
    }

    private func bindDefaultDevice() {
        removeVolumeListenerIfNeeded()
        guard let device = defaultOutputDevice() else {
            capability = .unavailable(reason: "no_default_output_device")
            notify()
            return
        }
        currentDevice = device
        usesSystemVolumeScript = false
        // The virtual master is the system-level control and works for modern
        // aggregate/Bluetooth outputs that do not expose scalar channels.
        var virtualAddr = virtualMasterAddress()
        if AudioHardwareServiceHasProperty(device, &virtualAddr) {
            var isSettable: DarwinBoolean = false
            _ = AudioHardwareServiceIsPropertySettable(device, &virtualAddr, &isSettable)
            guard isSettable.boolValue else {
                capability = .unavailable(reason: "fixed_volume_device")
                readOnce()
                notify(); return
            }
            usesVirtualMaster = true
            usesSystemVolumeScript = false
            currentChannel = kAudioObjectPropertyElementMain
            capability = .supported
            readOnce()
            addVolumeListener()
            return
        }

        // Fall back to a device's scalar master/channel controls.
        usesVirtualMaster = false
        var addr = volumeAddress(element: kAudioObjectPropertyElementMain)
        if !AudioObjectHasProperty(device, &addr) {
            addr = volumeAddress(element: 1)
            if !AudioObjectHasProperty(device, &addr) {
                usesSystemVolumeScript = true
                capability = readSystemVolume() == nil
                    ? .unavailable(reason: "no_volume_property")
                    : .supported
                notify(); return
            }
            currentChannel = 1
        } else {
            currentChannel = kAudioObjectPropertyElementMain
        }
        var isSettable: DarwinBoolean = false
        _ = AudioObjectIsPropertySettable(device, &addr, &isSettable)
        if !isSettable.boolValue {
            capability = .unavailable(reason: "fixed_volume_device")
            readOnce()
            notify(); return
        }
        capability = .supported
        readOnce()
        addVolumeListener()
    }

    private func addVolumeListener() {
        var addr = usesVirtualMaster
            ? virtualMasterAddress()
            : volumeAddress(element: currentChannel)
        let self_ = Unmanaged.passUnretained(self).toOpaque()
        AudioObjectAddPropertyListener(
            currentDevice, &addr,
            { _, _, _, ctx -> OSStatus in
                if let ctx = ctx {
                    let s = Unmanaged<RealVolumeProvider>.fromOpaque(ctx).takeUnretainedValue()
                    DispatchQueue.main.async { s.readExternalChange() }
                }
                return noErr
            },
            self_
        )
    }

    private func removeVolumeListenerIfNeeded() {
        // For simplicity, we let the process-level teardown release these.
    }

    private func readOnce() {
        if usesSystemVolumeScript {
            _ = readSystemVolume()
            return
        }
        var v: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let result: OSStatus
        if usesVirtualMaster {
            var addr = virtualMasterAddress()
            result = AudioHardwareServiceGetPropertyData(currentDevice, &addr, 0, nil, &size, &v)
        } else {
            var addr = volumeAddress(element: currentChannel)
            result = AudioObjectGetPropertyData(currentDevice, &addr, 0, nil, &size, &v)
        }
        if result == noErr {
            value = Double(v)
        }
    }

    private func readExternalChange() {
        guard Date() > writeInFlightUntil else { return }
        let oldVal = value
        readOnce()
        if oldVal != value { notify() }
    }

    private func notify() {
        handlers.forEach { $0(value, isMuted) }
    }

    public func set(_ newValue: Double) {
        guard case .supported = capability else { return }
        let clamped = min(1.0, max(0.0, newValue))
        if usesSystemVolumeScript {
            guard runSystemVolumeScript("set volume output volume \(Int((clamped * 100).rounded())) without output muted") != nil else { return }
            value = clamped
            isMuted = false
            notify()
            return
        }
        var target = Float32(clamped)
        writeInFlightUntil = Date().addingTimeInterval(0.1)
        if usesVirtualMaster {
            var addr = virtualMasterAddress()
            _ = AudioHardwareServiceSetPropertyData(
                currentDevice, &addr, 0, nil,
                UInt32(MemoryLayout<Float32>.size), &target
            )
        } else {
            var addr = volumeAddress(element: currentChannel)
            _ = AudioObjectSetPropertyData(
                currentDevice, &addr, 0, nil,
                UInt32(MemoryLayout<Float32>.size), &target
            )
        }
        value = clamped
        notify()
    }

    public func setMuted(_ muted: Bool) {
        // Optional public path; a fully-fledged mute wire would use
        // kAudioDevicePropertyMute. Left as a follow-up.
        isMuted = muted
        notify()
    }

    @discardableResult
    private func readSystemVolume() -> Double? {
        guard let output = runSystemVolumeScript("get volume settings") else { return nil }
        let pattern = #"output volume:(\d+)"#
        guard let match = output.range(of: pattern, options: .regularExpression),
              let number = Int(output[match].split(separator: ":").last ?? "") else { return nil }
        value = Double(number) / 100.0
        isMuted = output.contains("output muted:true")
        return value
    }

    private func runSystemVolumeScript(_ script: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        } catch {
            return nil
        }
    }

    public func subscribe(_ handler: @escaping (Double, Bool) -> Void) {
        handlers.append(handler)
        handler(value, isMuted)
    }

    public func unsubscribeAll() { handlers.removeAll() }

    // MARK: - Helpers

    private func defaultOutputDevice() -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dev: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let rc = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev)
        return rc == noErr ? dev : nil
    }

    private func volumeAddress(element: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: element
        )
    }

    private func virtualMasterAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}
