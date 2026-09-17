// Probe 03 — built-in display brightness via DisplayServices (private).
//
// dlopens /System/Library/PrivateFrameworks/DisplayServices.framework,
// resolves DisplayServicesGetBrightness / DisplayServicesSetBrightness,
// reads the current value, nudges it +2 %, waits 400 ms, restores.
//
// Success line:
//   BRIGHTNESS ok read=<0..1> setResult=<0=OK, nonzero=err> setBackResult=<...>
// Failure lines:
//   BRIGHTNESS fail reason=<...>

import CoreGraphics
import Darwin
import Foundation

typealias DisplayServicesGetBrightness_t = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
typealias DisplayServicesSetBrightness_t = @convention(c) (CGDirectDisplayID, Float) -> Int32

let frameworkPath = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"

guard let handle = dlopen(frameworkPath, RTLD_LAZY | RTLD_LOCAL) else {
    print("BRIGHTNESS fail reason=dlopen_displayservices")
    exit(1)
}

func sym<T>(_ name: String, as type: T.Type) -> T? {
    guard let s = dlsym(handle, name) else { return nil }
    return unsafeBitCast(s, to: T.self)
}

guard let getFn = sym("DisplayServicesGetBrightness", as: DisplayServicesGetBrightness_t.self) else {
    print("BRIGHTNESS fail reason=dlsym_get")
    exit(1)
}
guard let setFn = sym("DisplayServicesSetBrightness", as: DisplayServicesSetBrightness_t.self) else {
    print("BRIGHTNESS fail reason=dlsym_set")
    exit(1)
}

let display = CGMainDisplayID()
var current: Float = -1
let getResult = getFn(display, &current)
guard getResult == 0, current.isFinite, current >= 0, current <= 1 else {
    print("BRIGHTNESS fail reason=get_returned rc=\(getResult) value=\(current)")
    exit(1)
}

let target = min(1.0, current + 0.02)
let setResult = setFn(display, target)

Thread.sleep(forTimeInterval: 0.4)

let setBackResult = setFn(display, current)

print(String(format: "BRIGHTNESS ok read=%.4f setTarget=%.4f setResult=%d setBackResult=%d",
             current, target, setResult, setBackResult))
