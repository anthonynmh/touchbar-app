// Probe 04 — output volume read/write via Core Audio (public API).
//
// Locates the default output device, reads kAudioDevicePropertyVolumeScalar
// on the master (element 0) channel, nudges +0.02, waits, restores. Also
// checks whether the device is fixed-volume (settable = false).
//
// Success line:
//   VOLUME ok read=<0..1> settable=<0|1> setResult=<osstatus> setBackResult=<osstatus>
// Failure lines:
//   VOLUME fail reason=<...>

import CoreAudio
import Foundation

func getDefaultOutputDevice() -> AudioDeviceID? {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var deviceID: AudioDeviceID = 0
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    let rc = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID)
    return rc == noErr ? deviceID : nil
}

func volumeAddress(channel: UInt32) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyVolumeScalar,
        mScope: kAudioObjectPropertyScopeOutput,
        mElement: channel)
}

guard let device = getDefaultOutputDevice() else {
    print("VOLUME fail reason=no_default_output_device")
    exit(1)
}

// Try master channel first; fall back to left channel if not supported.
let masterAddr = volumeAddress(channel: kAudioObjectPropertyElementMain)
var addr = masterAddr

var isSettable: DarwinBoolean = false
var hasProperty = AudioObjectHasProperty(device, &addr)
if !hasProperty {
    // fall back to per-channel
    var leftAddr = volumeAddress(channel: 1)
    hasProperty = AudioObjectHasProperty(device, &leftAddr)
    if hasProperty {
        addr = leftAddr
    } else {
        print("VOLUME fail reason=no_volume_property")
        exit(1)
    }
}
_ = AudioObjectIsPropertySettable(device, &addr, &isSettable)

var value: Float32 = 0
var size = UInt32(MemoryLayout<Float32>.size)
let getResult = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value)
guard getResult == noErr else {
    print("VOLUME fail reason=get_property rc=\(getResult)")
    exit(1)
}

if !isSettable.boolValue {
    print(String(format: "VOLUME ok read=%.4f settable=0 setResult=n/a setBackResult=n/a", value))
    exit(0)
}

let target = min(1.0, value + 0.02)
var targetVar = Float32(target)
let setResult = AudioObjectSetPropertyData(device, &addr, 0, nil, size, &targetVar)

Thread.sleep(forTimeInterval: 0.4)

var restoreVar = Float32(value)
let setBackResult = AudioObjectSetPropertyData(device, &addr, 0, nil, size, &restoreVar)

print(String(format: "VOLUME ok read=%.4f settable=1 setResult=%d setBackResult=%d",
             value, setResult, setBackResult))
