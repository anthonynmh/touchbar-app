// Probe 03 — built-in display brightness via DisplayServices (private).
//
// The default invocation is read-only. Pass --write to nudge brightness by
// two percent, verify it, and restore the exact captured value.

import CoreGraphics
import Darwin
import Foundation

typealias DisplayServicesGetBrightness = @convention(c)
    (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
typealias DisplayServicesSetBrightness = @convention(c)
    (CGDirectDisplayID, Float) -> Int32

let arguments = Array(CommandLine.arguments.dropFirst())
let shouldWrite: Bool
switch arguments {
case []:
    shouldWrite = false
case ["--write"]:
    shouldWrite = true
default:
    print("BRIGHTNESS fail reason=usage expected=[--write]")
    exit(2)
}

let frameworkPath = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
guard let handle = dlopen(frameworkPath, RTLD_LAZY | RTLD_LOCAL) else {
    print("BRIGHTNESS fail reason=dlopen_displayservices")
    exit(1)
}

func symbol<T>(_ name: String, as type: T.Type) -> T? {
    guard let address = dlsym(handle, name) else { return nil }
    return unsafeBitCast(address, to: T.self)
}

guard let getBrightness = symbol(
    "DisplayServicesGetBrightness",
    as: DisplayServicesGetBrightness.self
) else {
    print("BRIGHTNESS fail reason=dlsym_get")
    exit(1)
}
let setBrightness = symbol(
    "DisplayServicesSetBrightness",
    as: DisplayServicesSetBrightness.self
)

let display = CGMainDisplayID()
func readBrightness() -> (status: Int32, value: Float) {
    var value: Float = -1
    let status = getBrightness(display, &value)
    guard status == 0, value.isFinite, value >= 0, value <= 1 else {
        return (status == 0 ? -1 : status, value)
    }
    return (0, value)
}

let original = readBrightness()
guard original.status == 0 else {
    print("BRIGHTNESS fail reason=initial_read status=\(original.status) value=\(original.value)")
    exit(1)
}

guard shouldWrite else {
    print(String(
        format: "BRIGHTNESS ok mode=read-only read=%.4f writeAvailable=%d",
        original.value,
        setBrightness == nil ? 0 : 1
    ))
    exit(0)
}

guard let setBrightness else {
    print("BRIGHTNESS fail mode=write reason=dlsym_set")
    exit(1)
}

let target = original.value >= 0.98
    ? max(0, original.value - 0.02)
    : min(1, original.value + 0.02)
let setStatus = setBrightness(display, target)
Thread.sleep(forTimeInterval: 0.4)
let changed = readBrightness()

// Restoration is unconditional after the snapshot has been captured, even if
// the exercise write or readback fails.
let restoreStatus = setBrightness(display, original.value)
Thread.sleep(forTimeInterval: 0.4)
let restored = readBrightness()

let exerciseOK = setStatus == 0
    && changed.status == 0
    && abs(changed.value - target) <= 0.001
let restoredOK = restoreStatus == 0
    && restored.status == 0
    && abs(restored.value - original.value) <= 0.001
let outcome = exerciseOK && restoredOK ? "ok" : "fail"

print(String(
    format: "BRIGHTNESS %@ mode=write original=%.4f target=%.4f setStatus=%d changed=%.4f changedStatus=%d restoreStatus=%d restored=%.4f restoredStatus=%d restoredOK=%d",
    outcome,
    original.value,
    target,
    setStatus,
    changed.value,
    changed.status,
    restoreStatus,
    restored.value,
    restored.status,
    restoredOK ? 1 : 0
))
if outcome == "fail" { exit(1) }
