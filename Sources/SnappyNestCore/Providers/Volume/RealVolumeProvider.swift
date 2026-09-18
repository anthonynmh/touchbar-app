import AudioToolbox
import CoreAudio
import Foundation

/// The small Core Audio surface used by `RealVolumeProvider`.
/// Keeping this behind a bridge makes volume behavior testable without changing
/// the machine's output volume.
internal protocol VolumeAudioBridge: AnyObject {
    func defaultOutputDevice() -> AudioDeviceID?
    func addDefaultDeviceListener(_ handler: @escaping () -> Void) -> Int
    func addPropertyListener(device: AudioDeviceID, address: AudioObjectPropertyAddress,
                             handler: @escaping () -> Void) -> Int
    func removeListener(_ token: Int)
    func hasProperty(device: AudioDeviceID, address: AudioObjectPropertyAddress) -> Bool
    func isPropertySettable(device: AudioDeviceID, address: AudioObjectPropertyAddress) -> Bool
    func preferredStereoChannels(device: AudioDeviceID) -> (OSStatus, [UInt32])
    func getVolume(device: AudioDeviceID, address: AudioObjectPropertyAddress) -> (OSStatus, Float32)
    func setVolume(device: AudioDeviceID, address: AudioObjectPropertyAddress, value: Float32) -> OSStatus
    func getMute(device: AudioDeviceID, address: AudioObjectPropertyAddress) -> (OSStatus, Bool)
    func setMute(device: AudioDeviceID, address: AudioObjectPropertyAddress, muted: Bool) -> OSStatus
}

private final class VolumeListenerBox {
    let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
}

/// Public Core Audio implementation. Virtual main volume is preferred when it
/// is present and writable; otherwise the device's preferred stereo scalar
/// controls are used. No AppleScript or synchronous shell process is involved
/// in a drag.
private final class SystemVolumeAudioBridge: VolumeAudioBridge {
    private typealias ListenerProc = @convention(c) (AudioObjectID, UInt32,
                                                       UnsafePointer<AudioObjectPropertyAddress>,
                                                       UnsafeMutableRawPointer?) -> OSStatus
    private static let listenerProc: ListenerProc = { _, _, _, context in
        guard let context else { return noErr }
        Unmanaged<VolumeListenerBox>.fromOpaque(context).takeUnretainedValue().handler()
        return noErr
    }

    private var nextToken = 1
    private var registrations: [Int: (objectID: AudioObjectID,
                                       address: AudioObjectPropertyAddress,
                                       context: UnsafeMutableRawPointer)] = [:]

    func defaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    @discardableResult
    func addDefaultDeviceListener(_ handler: @escaping () -> Void) -> Int {
        addListener(objectID: AudioObjectID(kAudioObjectSystemObject), address: AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain), handler: handler)
    }

    @discardableResult
    func addPropertyListener(device: AudioDeviceID, address: AudioObjectPropertyAddress,
                             handler: @escaping () -> Void) -> Int {
        addListener(objectID: device, address: address, handler: handler)
    }

    private func addListener(objectID: AudioObjectID, address: AudioObjectPropertyAddress,
                             handler: @escaping () -> Void) -> Int {
        let token = nextToken
        nextToken += 1
        let box = Unmanaged.passRetained(VolumeListenerBox(handler))
        let context = box.toOpaque()
        var address = address
        let status = AudioObjectAddPropertyListener(objectID, &address, Self.listenerProc, context)
        guard status == noErr else {
            box.release()
            return 0
        }
        registrations[token] = (objectID, address, context)
        return token
    }

    func removeListener(_ token: Int) {
        guard let registration = registrations[token] else { return }
        var address = registration.address
        let status = AudioObjectRemovePropertyListener(
            registration.objectID, &address, Self.listenerProc, registration.context)
        // A failed removal means Core Audio may still invoke this context. Keep
        // both the registration and retained box alive rather than dangling it.
        guard status == noErr else { return }
        registrations.removeValue(forKey: token)
        Unmanaged<VolumeListenerBox>.fromOpaque(registration.context).release()
    }

    func hasProperty(device: AudioDeviceID, address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        if isVirtualMain(address) {
            return AudioHardwareServiceHasProperty(device, &address)
        }
        return AudioObjectHasProperty(device, &address)
    }

    private func isVirtualMain(_ address: AudioObjectPropertyAddress) -> Bool {
        address.mSelector == kAudioHardwareServiceDeviceProperty_VirtualMainVolume
    }

    func isPropertySettable(device: AudioDeviceID, address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        var settable = DarwinBoolean(false)
        let status: OSStatus
        if isVirtualMain(address) {
            status = AudioHardwareServiceIsPropertySettable(device, &address, &settable)
        } else {
            status = AudioObjectIsPropertySettable(device, &address, &settable)
        }
        return status == noErr && settable.boolValue
    }

    func preferredStereoChannels(device: AudioDeviceID) -> (OSStatus, [UInt32]) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyPreferredChannelsForStereo,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var channels: [UInt32] = [0, 0]
        var size = UInt32(MemoryLayout<UInt32>.size * channels.count)
        let status = channels.withUnsafeMutableBytes { bytes in
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, bytes.baseAddress!)
        }
        guard status == noErr else { return (status, []) }
        return (noErr, Array(channels.prefix(Int(size) / MemoryLayout<UInt32>.size)))
    }

    func getVolume(device: AudioDeviceID, address: AudioObjectPropertyAddress) -> (OSStatus, Float32) {
        var address = address
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let status: OSStatus
        if isVirtualMain(address) {
            status = AudioHardwareServiceGetPropertyData(device, &address, 0, nil, &size, &value)
        } else {
            status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        }
        return (status, value)
    }

    func setVolume(device: AudioDeviceID, address: AudioObjectPropertyAddress, value: Float32) -> OSStatus {
        var address = address
        var value = value
        let size = UInt32(MemoryLayout<Float32>.size)
        if isVirtualMain(address) {
            return AudioHardwareServiceSetPropertyData(device, &address, 0, nil, size, &value)
        }
        return AudioObjectSetPropertyData(device, &address, 0, nil, size, &value)
    }

    func getMute(device: AudioDeviceID, address: AudioObjectPropertyAddress) -> (OSStatus, Bool) {
        var address = address
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return (status, value != 0)
    }

    func setMute(device: AudioDeviceID, address: AudioObjectPropertyAddress, muted: Bool) -> OSStatus {
        var address = address
        var value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(device, &address, 0, nil,
                                          UInt32(MemoryLayout<UInt32>.size), &value)
    }

    deinit {
        for token in Array(registrations.keys) { removeListener(token) }
    }
}

public final class RealVolumeProvider: VolumeProvider {
    private typealias MuteControl = (address: AudioObjectPropertyAddress, settable: Bool)
    private struct StateSnapshot {
        let volumes: [(address: AudioObjectPropertyAddress, value: Float32)]
        let mutes: [(control: MuteControl, value: Bool)]
    }

    public private(set) var capability: ProviderCapability = .unavailable(reason: "unbound")
    public private(set) var value: Double = 0
    public private(set) var isMuted: Bool = false

    private let bridge: VolumeAudioBridge
    private var handlers: [(Double, Bool) -> Void] = []
    private var currentDevice: AudioDeviceID = kAudioObjectUnknown
    private var volumeAddresses: [AudioObjectPropertyAddress] = []
    private var muteControls: [MuteControl] = []
    private var listenerTokens: [Int] = []
    private var defaultDeviceListenerToken: Int = 0
    private var isRebinding = false

    public init() {
        bridge = SystemVolumeAudioBridge()
        installDefaultDeviceListener()
        bindDefaultDevice()
    }

    internal init(bridge: VolumeAudioBridge) {
        self.bridge = bridge
        installDefaultDeviceListener()
        bindDefaultDevice()
    }

    deinit {
        removeListeners()
        if defaultDeviceListenerToken != 0 {
            bridge.removeListener(defaultDeviceListenerToken)
        }
    }

    private func installDefaultDeviceListener() {
        defaultDeviceListenerToken = bridge.addDefaultDeviceListener { [weak self] in
            DispatchQueue.main.async { self?.bindDefaultDevice() }
        }
    }

    private func bindDefaultDevice() {
        guard !isRebinding else { return }
        isRebinding = true
        defer { isRebinding = false }
        removeListeners()
        volumeAddresses = []
        muteControls = []

        guard let device = bridge.defaultOutputDevice() else {
            currentDevice = kAudioObjectUnknown
            capability = .unavailable(reason: "no_default_output_device")
            notify()
            return
        }
        currentDevice = device

        let virtual = virtualMasterAddress()
        if bridge.hasProperty(device: device, address: virtual),
           bridge.isPropertySettable(device: device, address: virtual) {
            volumeAddresses = [virtual]
        } else {
            let main = volumeAddress(element: kAudioObjectPropertyElementMain)
            if bridge.hasProperty(device: device, address: main),
               bridge.isPropertySettable(device: device, address: main) {
                volumeAddresses = [main]
            } else {
                volumeAddresses = discoverStereoVolumeAddresses(device: device)
            }
        }

        guard !volumeAddresses.isEmpty else {
            capability = .unavailable(reason: "no_writable_volume_property")
            notify()
            return
        }

        discoverMuteControls(device: device)
        guard let state = readState(device: device) else {
            capability = .unavailable(reason: "volume_read_failed")
            notify()
            return
        }
        capability = .supported
        value = state.value
        isMuted = state.muted
        addListeners(device: device)
        notify()
    }

    private func discoverStereoVolumeAddresses(device: AudioDeviceID) -> [AudioObjectPropertyAddress] {
        let preferredResult = bridge.preferredStereoChannels(device: device)
        let preferred = deduplicatedChannels(preferredResult.0 == noErr ? preferredResult.1 : [])
        if preferred.count == 2 {
            let addresses = preferred.map(volumeAddress)
            if addresses.allSatisfy({ bridge.hasProperty(device: device, address: $0)
                && bridge.isPropertySettable(device: device, address: $0) }) {
                return addresses
            }
        }

        let fallback = [UInt32(1), UInt32(2)].map(volumeAddress)
        return fallback.allSatisfy({ bridge.hasProperty(device: device, address: $0)
            && bridge.isPropertySettable(device: device, address: $0) }) ? fallback : []
    }

    private func deduplicatedChannels(_ channels: [UInt32]) -> [UInt32] {
        var seen: Set<UInt32> = []
        return channels.filter { $0 != kAudioObjectPropertyElementMain && seen.insert($0).inserted }
    }

    private func discoverMuteControls(device: AudioDeviceID) {
        let main = mutePropertyAddress(element: kAudioObjectPropertyElementMain)
        let mainControl = readableMuteControl(device: device, address: main)
        if let mainControl, mainControl.settable {
            muteControls = [mainControl]
            return
        }

        let channelControls = volumeAddresses
            .filter { $0.mElement != kAudioObjectPropertyElementMain }
            .compactMap {
                readableMuteControl(device: device, address: mutePropertyAddress(element: $0.mElement))
            }
        if !channelControls.isEmpty {
            muteControls = channelControls
        } else if let mainControl {
            // A read-only main mute still contributes accurate display state.
            muteControls = [mainControl]
        } else {
            muteControls = []
        }
    }

    private func readableMuteControl(device: AudioDeviceID, address: AudioObjectPropertyAddress)
        -> (address: AudioObjectPropertyAddress, settable: Bool)? {
        guard bridge.hasProperty(device: device, address: address),
              bridge.getMute(device: device, address: address).0 == noErr else { return nil }
        return (address, bridge.isPropertySettable(device: device, address: address))
    }

    private func addListeners(device: AudioDeviceID) {
        for address in volumeAddresses {
            let token = bridge.addPropertyListener(device: device, address: address) { [weak self] in
                DispatchQueue.main.async { self?.readExternalState() }
            }
            if token != 0 { listenerTokens.append(token) }
        }
        for control in muteControls {
            let token = bridge.addPropertyListener(device: device, address: control.address) { [weak self] in
                DispatchQueue.main.async { self?.readExternalState() }
            }
            if token != 0 { listenerTokens.append(token) }
        }
    }

    private func removeListeners() {
        for token in listenerTokens { bridge.removeListener(token) }
        listenerTokens.removeAll()
    }

    private func readExternalState() {
        guard currentDevice != kAudioObjectUnknown,
              let state = readState(device: currentDevice),
              state.value != value || state.muted != isMuted else { return }
        value = state.value
        isMuted = state.muted
        notify()
    }

    private func readState(device: AudioDeviceID) -> (value: Double, muted: Bool)? {
        guard !volumeAddresses.isEmpty else { return nil }
        var total = 0.0
        for address in volumeAddresses {
            let result = bridge.getVolume(device: device, address: address)
            guard result.0 == noErr, result.1.isFinite, result.1 >= 0, result.1 <= 1 else { return nil }
            total += Double(result.1)
        }
        var muted = false
        for control in muteControls {
            let result = bridge.getMute(device: device, address: control.address)
            guard result.0 == noErr else { return nil }
            muted = muted || result.1
        }
        return (total / Double(volumeAddresses.count), muted)
    }

    public func set(_ newValue: Double) {
        guard case .supported = capability, currentDevice != kAudioObjectUnknown else { return }
        let target = min(1.0, max(0.0, newValue))
        guard let snapshot = captureSnapshot() else { return }
        let targetValue = Float32(target)

        var succeeded = true
        for address in volumeAddresses {
            if bridge.setVolume(device: currentDevice, address: address, value: targetValue) != noErr {
                succeeded = false
                break
            }
        }

        if succeeded, target > 0 {
            for control in muteControls where control.settable {
                if bridge.setMute(device: currentDevice, address: control.address, muted: false) != noErr {
                    succeeded = false
                }
            }
        }

        if succeeded, validateVolumeTarget(target), let confirmed = readState(device: currentDevice) {
            updateAndNotify(confirmed)
        } else {
            restore(snapshot)
            publishActualState()
        }
    }

    public func setMuted(_ muted: Bool) {
        guard case .supported = capability, currentDevice != kAudioObjectUnknown,
              !muteControls.isEmpty, let snapshot = captureSnapshot() else { return }

        var succeeded = true
        for control in muteControls where control.settable {
            if bridge.setMute(device: currentDevice, address: control.address, muted: muted) != noErr {
                succeeded = false
            }
        }

        if succeeded, validateMuteTarget(muted), let confirmed = readState(device: currentDevice) {
            updateAndNotify(confirmed)
        } else {
            restore(snapshot)
            publishActualState()
        }
    }

    private func captureSnapshot() -> StateSnapshot? {
        var volumes: [(AudioObjectPropertyAddress, Float32)] = []
        for address in volumeAddresses {
            let result = bridge.getVolume(device: currentDevice, address: address)
            guard result.0 == noErr, result.1.isFinite, result.1 >= 0, result.1 <= 1 else { return nil }
            volumes.append((address, result.1))
        }

        var mutes: [(MuteControl, Bool)] = []
        for control in muteControls {
            let result = bridge.getMute(device: currentDevice, address: control.address)
            guard result.0 == noErr else { return nil }
            mutes.append((control, result.1))
        }
        return StateSnapshot(volumes: volumes, mutes: mutes)
    }

    private func validateVolumeTarget(_ target: Double) -> Bool {
        for address in volumeAddresses {
            let result = bridge.getVolume(device: currentDevice, address: address)
            guard result.0 == noErr, abs(Double(result.1) - target) <= 0.01 else { return false }
        }
        if target > 0 {
            for control in muteControls {
                let result = bridge.getMute(device: currentDevice, address: control.address)
                guard result.0 == noErr, !result.1 else { return false }
            }
        }
        return true
    }

    private func validateMuteTarget(_ muted: Bool) -> Bool {
        for control in muteControls {
            let result = bridge.getMute(device: currentDevice, address: control.address)
            guard result.0 == noErr, result.1 == muted else { return false }
        }
        return true
    }

    private func restore(_ snapshot: StateSnapshot) {
        for entry in snapshot.volumes {
            _ = bridge.setVolume(device: currentDevice, address: entry.address, value: entry.value)
        }
        for entry in snapshot.mutes where entry.control.settable {
            _ = bridge.setMute(device: currentDevice, address: entry.control.address, muted: entry.value)
        }
    }

    private func publishActualState() {
        guard let state = readState(device: currentDevice) else { return }
        updateAndNotify(state)
    }

    private func updateAndNotify(_ state: (value: Double, muted: Bool)) {
        guard value != state.value || isMuted != state.muted else { return }
        value = state.value
        isMuted = state.muted
        notify()
    }

    private func notify() { handlers.forEach { $0(value, isMuted) } }

    public func subscribe(_ handler: @escaping (Double, Bool) -> Void) {
        handlers.append(handler)
        handler(value, isMuted)
    }

    public func unsubscribeAll() { handlers.removeAll() }

    private func volumeAddress(element: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                   mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: element)
    }

    private func mutePropertyAddress(element: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                   mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: element)
    }

    private func virtualMasterAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                   mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }
}
