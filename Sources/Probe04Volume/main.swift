// Probe 04 — verify the exact Core Audio volume controls used by the app.
//
// The probe changes every selected volume control, verifies the effective
// volume and mute state, then restores and verifies every captured control.

import AudioToolbox
import CoreAudio
import Foundation

struct VolumeControl {
    let address: AudioObjectPropertyAddress
    let channel: UInt32
}

struct MuteControl {
    let address: AudioObjectPropertyAddress
    let channel: UInt32
    let settable: Bool
}

func defaultOutputDevice() -> AudioDeviceID? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var device = AudioDeviceID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                            0, nil, &size, &device)
    return status == noErr && device != kAudioObjectUnknown ? device : nil
}

func volumeAddress(_ channel: UInt32) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                               mScope: kAudioDevicePropertyScopeOutput,
                               mElement: channel)
}

func muteAddress(_ channel: UInt32) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                               mScope: kAudioDevicePropertyScopeOutput,
                               mElement: channel)
}

func isVirtualMain(_ address: AudioObjectPropertyAddress) -> Bool {
    address.mSelector == kAudioHardwareServiceDeviceProperty_VirtualMainVolume
}

func hasProperty(_ device: AudioDeviceID, _ address: AudioObjectPropertyAddress) -> Bool {
    var address = address
    if isVirtualMain(address) {
        return AudioHardwareServiceHasProperty(device, &address)
    }
    return AudioObjectHasProperty(device, &address)
}

func isSettable(_ device: AudioDeviceID, _ address: AudioObjectPropertyAddress) -> Bool {
    var address = address
    var settable = DarwinBoolean(false)
    let status = isVirtualMain(address)
        ? AudioHardwareServiceIsPropertySettable(device, &address, &settable)
        : AudioObjectIsPropertySettable(device, &address, &settable)
    return status == noErr && settable.boolValue
}

func preferredStereoChannels(_ device: AudioDeviceID) -> [UInt32] {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyPreferredChannelsForStereo,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)
    guard AudioObjectHasProperty(device, &address) else { return [] }
    var channels: [UInt32] = [0, 0]
    var size = UInt32(MemoryLayout<UInt32>.size * channels.count)
    let status = channels.withUnsafeMutableBytes {
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0.baseAddress!)
    }
    guard status == noErr else { return [] }
    var seen: Set<UInt32> = []
    return channels.prefix(Int(size) / MemoryLayout<UInt32>.size)
        .filter { $0 != kAudioObjectPropertyElementMain && seen.insert($0).inserted }
}

func getVolume(_ device: AudioDeviceID, _ address: AudioObjectPropertyAddress) -> (OSStatus, Float32) {
    var address = address
    var value: Float32 = 0
    var size = UInt32(MemoryLayout<Float32>.size)
    let status = isVirtualMain(address)
        ? AudioHardwareServiceGetPropertyData(device, &address, 0, nil, &size, &value)
        : AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
    return (status, value)
}

func setVolume(_ device: AudioDeviceID, _ address: AudioObjectPropertyAddress,
               _ value: Float32) -> OSStatus {
    var address = address
    var value = value
    let size = UInt32(MemoryLayout<Float32>.size)
    return isVirtualMain(address)
        ? AudioHardwareServiceSetPropertyData(device, &address, 0, nil, size, &value)
        : AudioObjectSetPropertyData(device, &address, 0, nil, size, &value)
}

func getMute(_ device: AudioDeviceID, _ address: AudioObjectPropertyAddress) -> (OSStatus, Bool) {
    var address = address
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
    return (status, value != 0)
}

func setMute(_ device: AudioDeviceID, _ address: AudioObjectPropertyAddress,
             _ muted: Bool) -> OSStatus {
    var address = address
    var value: UInt32 = muted ? 1 : 0
    return AudioObjectSetPropertyData(device, &address, 0, nil,
                                      UInt32(MemoryLayout<UInt32>.size), &value)
}

func discoverVolumes(_ device: AudioDeviceID) -> (strategy: String, controls: [VolumeControl]) {
    let virtual = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)
    if hasProperty(device, virtual), isSettable(device, virtual) {
        return ("virtual-main", [VolumeControl(address: virtual,
                                                channel: kAudioObjectPropertyElementMain)])
    }

    let main = volumeAddress(kAudioObjectPropertyElementMain)
    if hasProperty(device, main), isSettable(device, main) {
        return ("main", [VolumeControl(address: main,
                                       channel: kAudioObjectPropertyElementMain)])
    }

    let preferred = preferredStereoChannels(device)
    if preferred.count == 2 {
        let controls = preferred.map { VolumeControl(address: volumeAddress($0), channel: $0) }
        if controls.allSatisfy({ hasProperty(device, $0.address) && isSettable(device, $0.address) }) {
            return ("preferred-stereo", controls)
        }
    }

    let fallback = [UInt32(1), UInt32(2)].map {
        VolumeControl(address: volumeAddress($0), channel: $0)
    }
    if fallback.allSatisfy({ hasProperty(device, $0.address) && isSettable(device, $0.address) }) {
        return ("stereo-1-2", fallback)
    }
    return ("none", [])
}

func readableMute(_ device: AudioDeviceID, _ address: AudioObjectPropertyAddress) -> MuteControl? {
    guard hasProperty(device, address), getMute(device, address).0 == noErr else { return nil }
    return MuteControl(address: address, channel: address.mElement,
                       settable: isSettable(device, address))
}

func discoverMutes(_ device: AudioDeviceID, volumes: [VolumeControl]) -> [MuteControl] {
    let main = readableMute(device, muteAddress(kAudioObjectPropertyElementMain))
    if let main, main.settable {
        return [main]
    }
    let channels = volumes
        .filter { $0.channel != kAudioObjectPropertyElementMain }
        .compactMap { readableMute(device, muteAddress($0.channel)) }
    if !channels.isEmpty { return channels }
    return main.map { [$0] } ?? []
}

func readVolumes(_ device: AudioDeviceID, _ controls: [VolumeControl])
    -> (status: OSStatus, values: [Float32]) {
    var values: [Float32] = []
    for control in controls {
        let result = getVolume(device, control.address)
        guard result.0 == noErr, result.1.isFinite, result.1 >= 0, result.1 <= 1 else {
            return (result.0 == noErr ? kAudioHardwareUnspecifiedError : result.0, values)
        }
        values.append(result.1)
    }
    return (noErr, values)
}

func readMutes(_ device: AudioDeviceID, _ controls: [MuteControl])
    -> (status: OSStatus, values: [Bool]) {
    var values: [Bool] = []
    for control in controls {
        let result = getMute(device, control.address)
        guard result.0 == noErr else { return (result.0, values) }
        values.append(result.1)
    }
    return (noErr, values)
}

guard let device = defaultOutputDevice() else {
    print("VOLUME fail reason=no_default_output_device")
    exit(1)
}

let discovery = discoverVolumes(device)
let volumes = discovery.controls
guard !volumes.isEmpty else {
    print("VOLUME fail device=\(device) reason=no_writable_volume_property")
    exit(1)
}
let mutes = discoverMutes(device, volumes: volumes)

let originalVolumeRead = readVolumes(device, volumes)
let originalMuteRead = readMutes(device, mutes)
guard originalVolumeRead.status == noErr, originalMuteRead.status == noErr else {
    print("VOLUME fail device=\(device) strategy=\(discovery.strategy) reason=initial_read volumeStatus=\(originalVolumeRead.status) muteStatus=\(originalMuteRead.status)")
    exit(1)
}
let originalVolumes = originalVolumeRead.values
let originalMutes = originalMuteRead.values
let originalAverage = originalVolumes.map(Double.init).reduce(0, +) / Double(originalVolumes.count)
let target = originalAverage >= 0.5
    ? max(0, originalAverage - 0.05)
    : min(1, originalAverage + 0.05)

var exerciseStatuses: [OSStatus] = []
var exerciseOK = abs(target - originalAverage) > 0.001
for control in volumes {
    let status = setVolume(device, control.address, Float32(target))
    exerciseStatuses.append(status)
    exerciseOK = exerciseOK && status == noErr
}
if exerciseOK, target > 0 {
    for control in mutes where control.settable {
        let status = setMute(device, control.address, false)
        exerciseStatuses.append(status)
        exerciseOK = exerciseOK && status == noErr
    }
}

let changedVolumeRead = readVolumes(device, volumes)
let changedMuteRead = readMutes(device, mutes)
exerciseOK = exerciseOK
    && changedVolumeRead.status == noErr
    && changedMuteRead.status == noErr
    && changedVolumeRead.values.allSatisfy { abs(Double($0) - target) <= 0.01 }
    && (target == 0 || changedMuteRead.values.allSatisfy { !$0 })

// Restoration is deliberately unconditional after the original snapshots exist.
var restoreStatuses: [OSStatus] = []
for (control, original) in zip(volumes, originalVolumes) {
    restoreStatuses.append(setVolume(device, control.address, original))
}
for (control, original) in zip(mutes, originalMutes) where control.settable {
    restoreStatuses.append(setMute(device, control.address, original))
}

let restoredVolumeRead = readVolumes(device, volumes)
let restoredMuteRead = readMutes(device, mutes)
let restoredOK = restoreStatuses.allSatisfy { $0 == noErr }
    && restoredVolumeRead.status == noErr
    && restoredMuteRead.status == noErr
    && zip(restoredVolumeRead.values, originalVolumes).allSatisfy {
        abs(Double($0.0) - Double($0.1)) <= 0.01
    }
    && restoredMuteRead.values == originalMutes

let volumeChannels = volumes.map { String($0.channel) }.joined(separator: ",")
let muteDescription = mutes.map { "\($0.channel):\($0.settable ? "rw" : "ro")" }
    .joined(separator: ",")
let exerciseStatusText = exerciseStatuses.map(String.init).joined(separator: ",")
let restoreStatusText = restoreStatuses.map(String.init).joined(separator: ",")
let originalMuteText = originalMutes.map { $0 ? "1" : "0" }.joined(separator: ",")
let changedMuteText = changedMuteRead.values.map { $0 ? "1" : "0" }.joined(separator: ",")
let outcome = exerciseOK && restoredOK ? "ok" : "fail"
print(String(format: "VOLUME %@ device=%u strategy=%@ channels=%@ mute=%@ original=%.4f target=%.4f originalMutes=%@ changedMutes=%@ exerciseStatuses=%@ exerciseRead=%d restoreStatuses=%@ restoreRead=%d restored=%d",
             outcome, device, discovery.strategy, volumeChannels, muteDescription,
             originalAverage, target, originalMuteText, changedMuteText,
             exerciseStatusText, changedVolumeRead.status,
             restoreStatusText, restoredVolumeRead.status, restoredOK ? 1 : 0))
if outcome == "fail" { exit(1) }
