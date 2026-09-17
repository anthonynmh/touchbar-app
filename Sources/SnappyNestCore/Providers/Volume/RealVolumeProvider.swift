import CoreAudio
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
        // Try master first.
        var addr = volumeAddress(element: kAudioObjectPropertyElementMain)
        if !AudioObjectHasProperty(device, &addr) {
            addr = volumeAddress(element: 1)
            if !AudioObjectHasProperty(device, &addr) {
                capability = .unavailable(reason: "no_volume_property")
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
        var addr = volumeAddress(element: currentChannel)
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
        var addr = volumeAddress(element: currentChannel)
        var v: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        if AudioObjectGetPropertyData(currentDevice, &addr, 0, nil, &size, &v) == noErr {
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
        var addr = volumeAddress(element: currentChannel)
        var target = Float32(clamped)
        writeInFlightUntil = Date().addingTimeInterval(0.1)
        _ = AudioObjectSetPropertyData(
            currentDevice, &addr, 0, nil,
            UInt32(MemoryLayout<Float32>.size), &target
        )
        value = clamped
        notify()
    }

    public func setMuted(_ muted: Bool) {
        // Optional public path; a fully-fledged mute wire would use
        // kAudioDevicePropertyMute. Left as a follow-up.
        isMuted = muted
        notify()
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
}
