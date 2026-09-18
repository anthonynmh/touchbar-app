import AudioToolbox
import CoreAudio
import XCTest
@testable import SnappyNestCore

final class RealVolumeProviderTests: XCTestCase {
    func testPrefersWritableVirtualMainVolume() {
        let bridge = FakeVolumeAudioBridge()
        bridge.virtualVolume = 0.35
        bridge.virtualSettable = true
        let provider = RealVolumeProvider(bridge: bridge)

        XCTAssertEqual(provider.capability, .supported)
        XCTAssertEqual(provider.value, 0.35, accuracy: 0.001)
        provider.set(0.72)
        XCTAssertEqual(provider.value, 0.72, accuracy: 0.001)
        XCTAssertEqual(bridge.setVolumeChannels, [kAudioObjectPropertyElementMain])
    }

    func testUsesDeduplicatedPreferredStereoChannels() {
        let bridge = FakeVolumeAudioBridge()
        bridge.preferredChannels = [4, 4, 6]
        bridge.scalarVolumes = [4: 0.2, 6: 0.4]
        bridge.scalarSettableChannels = [4, 6]
        bridge.mutes = [:]
        let provider = RealVolumeProvider(bridge: bridge)

        XCTAssertEqual(provider.capability, .supported)
        XCTAssertEqual(provider.value, 0.3, accuracy: 0.001)
        provider.set(0.65)

        XCTAssertEqual(bridge.setVolumeChannels, [4, 6])
        XCTAssertEqual(bridge.scalarVolumes[4] ?? -1, 0.65, accuracy: 0.001)
        XCTAssertEqual(bridge.scalarVolumes[6] ?? -1, 0.65, accuracy: 0.001)
    }

    func testFallsBackToChannelsOneAndTwoOnlyWhenBothAreWritable() {
        let bridge = FakeVolumeAudioBridge()
        bridge.preferredChannels = [7] // incomplete preferred stereo result
        bridge.scalarVolumes = [1: 0.2, 2: 0.4, 7: 0.8]
        bridge.mutes = [:]
        let provider = RealVolumeProvider(bridge: bridge)

        provider.set(0.6)

        XCTAssertEqual(bridge.setVolumeChannels, [1, 2])
        XCTAssertEqual(bridge.scalarVolumes[7], 0.8)

        let incomplete = FakeVolumeAudioBridge()
        incomplete.preferredChannels = [7]
        incomplete.scalarVolumes = [1: 0.2, 7: 0.8]
        incomplete.mutes = [:]
        XCTAssertEqual(RealVolumeProvider(bridge: incomplete).capability,
                       .unavailable(reason: "no_writable_volume_property"))
    }

    func testPerChannelMuteStateIsAggregatedAndEveryWritableMuteIsCleared() {
        let bridge = FakeVolumeAudioBridge()
        bridge.mutes = [1: true, 2: false]
        bridge.muteSettableChannels = [1, 2]
        let provider = RealVolumeProvider(bridge: bridge)

        XCTAssertTrue(provider.isMuted)
        provider.set(0.4)

        XCTAssertFalse(provider.isMuted)
        XCTAssertEqual(bridge.mutes, [1: false, 2: false])
        XCTAssertEqual(bridge.setMuteOperations.map(\.channel), [1, 2])
        XCTAssertEqual(provider.value, 0.4, accuracy: 0.001)
    }

    func testReadOnlyMasterMuteDoesNotMaskWritableChannelMutes() {
        let bridge = FakeVolumeAudioBridge()
        bridge.mutes = [kAudioObjectPropertyElementMain: true, 1: true, 2: false]
        bridge.muteSettableChannels = [1, 2]
        let provider = RealVolumeProvider(bridge: bridge)

        XCTAssertTrue(provider.isMuted)
        provider.set(0.4)

        XCTAssertFalse(provider.isMuted)
        XCTAssertEqual(bridge.mutes[kAudioObjectPropertyElementMain], true)
        XCTAssertEqual(bridge.mutes[1], false)
        XCTAssertEqual(bridge.mutes[2], false)
        XCTAssertEqual(bridge.setMuteOperations.map(\.channel), [1, 2])
        XCTAssertEqual(provider.value, 0.4, accuracy: 0.001)
    }

    func testReadOnlyMutePreventsFalseUnmuteClaimAndRollsBackVolume() {
        let bridge = FakeVolumeAudioBridge()
        bridge.scalarVolumes = [1: 0.2, 2: 0.3]
        bridge.mutes = [1: true, 2: false]
        bridge.muteSettableChannels = [2]
        let provider = RealVolumeProvider(bridge: bridge)

        provider.set(0.8)

        XCTAssertEqual(bridge.scalarVolumes[1] ?? -1, 0.2, accuracy: 0.001)
        XCTAssertEqual(bridge.scalarVolumes[2] ?? -1, 0.3, accuracy: 0.001)
        XCTAssertTrue(provider.isMuted)
        XCTAssertEqual(provider.value, 0.25, accuracy: 0.001)
    }

    func testFailedChannelWriteRollsBackEveryChangedVolume() {
        let bridge = FakeVolumeAudioBridge()
        bridge.scalarVolumes = [1: 0.2, 2: 0.3]
        bridge.failVolumeWritesForChannels = [2]
        let provider = RealVolumeProvider(bridge: bridge)

        provider.set(0.8)

        XCTAssertEqual(bridge.scalarVolumes[1] ?? -1, 0.2, accuracy: 0.001)
        XCTAssertEqual(bridge.scalarVolumes[2] ?? -1, 0.3, accuracy: 0.001)
        XCTAssertEqual(provider.value, 0.25, accuracy: 0.001)
    }

    func testMuteWriteFailureRollsBackVolumesAndPreviouslyChangedMutes() {
        let bridge = FakeVolumeAudioBridge()
        bridge.scalarVolumes = [1: 0.2, 2: 0.3]
        bridge.mutes = [1: true, 2: true]
        bridge.muteSettableChannels = [1, 2]
        bridge.failMuteWritesForChannels = [2]
        let provider = RealVolumeProvider(bridge: bridge)

        provider.set(0.8)

        XCTAssertEqual(bridge.scalarVolumes[1] ?? -1, 0.2, accuracy: 0.001)
        XCTAssertEqual(bridge.scalarVolumes[2] ?? -1, 0.3, accuracy: 0.001)
        XCTAssertEqual(bridge.mutes, [1: true, 2: true])
        XCTAssertEqual(provider.value, 0.25, accuracy: 0.001)
        XCTAssertTrue(provider.isMuted)
    }

    func testSetMutedUpdatesAllChannelControls() {
        let bridge = FakeVolumeAudioBridge()
        bridge.mutes = [1: false, 2: false]
        bridge.muteSettableChannels = [1, 2]
        let provider = RealVolumeProvider(bridge: bridge)

        provider.setMuted(true)

        XCTAssertEqual(bridge.mutes, [1: true, 2: true])
        XCTAssertTrue(provider.isMuted)
    }

    func testZeroVolumeDoesNotForceUnmute() {
        let bridge = FakeVolumeAudioBridge()
        bridge.mutes = [kAudioObjectPropertyElementMain: true]
        let provider = RealVolumeProvider(bridge: bridge)

        provider.set(0)

        XCTAssertTrue(provider.isMuted)
        XCTAssertEqual(provider.value, 0, accuracy: 0.001)
        XCTAssertTrue(bridge.setMuteOperations.isEmpty)
    }

    func testMissingAndFixedVolumeAreUnavailable() {
        let missing = FakeVolumeAudioBridge()
        missing.scalarVolumes = [:]
        let missingProvider = RealVolumeProvider(bridge: missing)
        XCTAssertEqual(missingProvider.capability, .unavailable(reason: "no_writable_volume_property"))

        let fixed = FakeVolumeAudioBridge()
        fixed.scalarSettableChannels = []
        let fixedProvider = RealVolumeProvider(bridge: fixed)
        XCTAssertEqual(fixedProvider.capability, .unavailable(reason: "no_writable_volume_property"))
    }

    func testNoDefaultOutputDeviceIsUnavailable() {
        let bridge = FakeVolumeAudioBridge()
        bridge.device = nil

        let provider = RealVolumeProvider(bridge: bridge)

        XCTAssertEqual(provider.capability, .unavailable(reason: "no_default_output_device"))
    }

    func testListenersAreRemovedOnRebindAndDeinit() {
        let bridge = FakeVolumeAudioBridge()
        var provider: RealVolumeProvider? = RealVolumeProvider(bridge: bridge)
        XCTAssertNotNil(provider)
        XCTAssertEqual(bridge.activeListenerCount, 4) // default + 2 volume + master mute

        bridge.scalarVolumes = [1: 0.5, 2: 0.5]
        bridge.triggerDefaultDeviceChange()
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        XCTAssertEqual(bridge.removedListenerCount, 3)
        XCTAssertEqual(bridge.activeListenerCount, 4)

        provider = nil
        XCTAssertEqual(bridge.activeListenerCount, 0)
        XCTAssertGreaterThanOrEqual(bridge.removedListenerCount, 6)
    }
}

private final class FakeVolumeAudioBridge: VolumeAudioBridge {
    var device: AudioDeviceID? = 42
    var virtualVolume: Float32 = 0.5
    var virtualSettable = false
    var preferredStatus: OSStatus = noErr
    var preferredChannels: [UInt32] = [1, 2]
    var scalarVolumes: [UInt32: Float32] = [1: 0.3, 2: 0.3]
    var scalarSettableChannels: Set<UInt32> = [1, 2]
    var mutes: [UInt32: Bool] = [kAudioObjectPropertyElementMain: false]
    var muteSettableChannels: Set<UInt32> = [kAudioObjectPropertyElementMain]
    var failVolumeWritesForChannels: Set<UInt32> = []
    var failMuteWritesForChannels: Set<UInt32> = []
    var setVolumeChannels: [UInt32] = []
    var setMuteOperations: [(channel: UInt32, muted: Bool)] = []
    var activeListenerCount = 0
    var removedListenerCount = 0

    private var nextToken = 1
    private var listeners: [Int: () -> Void] = [:]
    private var defaultListener: (() -> Void)?

    func defaultOutputDevice() -> AudioDeviceID? { device }

    func addDefaultDeviceListener(_ handler: @escaping () -> Void) -> Int {
        let token = nextToken
        nextToken += 1
        defaultListener = handler
        listeners[token] = handler
        activeListenerCount += 1
        return token
    }

    func addPropertyListener(device: AudioDeviceID, address: AudioObjectPropertyAddress,
                             handler: @escaping () -> Void) -> Int {
        let token = nextToken
        nextToken += 1
        listeners[token] = handler
        activeListenerCount += 1
        return token
    }

    func removeListener(_ token: Int) {
        guard listeners.removeValue(forKey: token) != nil else { return }
        activeListenerCount -= 1
        removedListenerCount += 1
    }

    func hasProperty(device: AudioDeviceID, address: AudioObjectPropertyAddress) -> Bool {
        switch address.mSelector {
        case kAudioHardwareServiceDeviceProperty_VirtualMainVolume:
            return true
        case kAudioDevicePropertyVolumeScalar:
            return scalarVolumes[address.mElement] != nil
        case kAudioDevicePropertyMute:
            return mutes[address.mElement] != nil
        default:
            return false
        }
    }

    func isPropertySettable(device: AudioDeviceID, address: AudioObjectPropertyAddress) -> Bool {
        switch address.mSelector {
        case kAudioHardwareServiceDeviceProperty_VirtualMainVolume:
            return virtualSettable
        case kAudioDevicePropertyVolumeScalar:
            return scalarSettableChannels.contains(address.mElement)
        case kAudioDevicePropertyMute:
            return muteSettableChannels.contains(address.mElement)
        default:
            return false
        }
    }

    func preferredStereoChannels(device: AudioDeviceID) -> (OSStatus, [UInt32]) {
        (preferredStatus, preferredChannels)
    }

    func getVolume(device: AudioDeviceID, address: AudioObjectPropertyAddress) -> (OSStatus, Float32) {
        if address.mSelector == kAudioHardwareServiceDeviceProperty_VirtualMainVolume {
            return (noErr, virtualVolume)
        }
        guard let volume = scalarVolumes[address.mElement] else {
            return (kAudioHardwareUnspecifiedError, 0)
        }
        return (noErr, volume)
    }

    func setVolume(device: AudioDeviceID, address: AudioObjectPropertyAddress, value: Float32) -> OSStatus {
        let channel = address.mSelector == kAudioHardwareServiceDeviceProperty_VirtualMainVolume
            ? kAudioObjectPropertyElementMain : address.mElement
        setVolumeChannels.append(channel)
        if failVolumeWritesForChannels.contains(channel) { return kAudioHardwareUnspecifiedError }
        if address.mSelector == kAudioHardwareServiceDeviceProperty_VirtualMainVolume {
            virtualVolume = value
        } else {
            scalarVolumes[channel] = value
        }
        return noErr
    }

    func getMute(device: AudioDeviceID, address: AudioObjectPropertyAddress) -> (OSStatus, Bool) {
        guard let muted = mutes[address.mElement] else { return (kAudioHardwareUnspecifiedError, false) }
        return (noErr, muted)
    }

    func setMute(device: AudioDeviceID, address: AudioObjectPropertyAddress, muted: Bool) -> OSStatus {
        setMuteOperations.append((address.mElement, muted))
        if failMuteWritesForChannels.contains(address.mElement) { return kAudioHardwareUnspecifiedError }
        mutes[address.mElement] = muted
        return noErr
    }

    func triggerDefaultDeviceChange() { defaultListener?() }
}
