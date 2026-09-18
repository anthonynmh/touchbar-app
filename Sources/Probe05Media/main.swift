// Probe 05 — media adapters. Two independent halves:
//
// 05a  Spotify AppleScript adapter. Runs a small `tell application "Spotify"`
//      script fetching player state / position / duration / track name.
//      Requests Automation permission the first time (System Settings prompt).
//      Success:  SPOTIFY ok state=<...> position=<sec> duration=<sec> track=<...>
//      Skipped:  SPOTIFY skip reason=not_installed|not_running|terminating
//      Failure:  SPOTIFY fail reason=<...>
//
// 05b  MediaRemote adapter for browser (Firefox/YouTube). dlopens
//      /System/Library/PrivateFrameworks/MediaRemote.framework, resolves
//      MRMediaRemoteGetNowPlayingInfo, and dumps the returned dictionary.
//      Success:  MEDIAREMOTE ok bundle=<...> title=<...> elapsed=<sec> duration=<sec> rate=<...>
//      Empty:    MEDIAREMOTE none no_now_playing_info
//      Failure:  MEDIAREMOTE fail reason=<...>

import AppKit
import Darwin
import Foundation

// -----------------------------------------------------------------------------
// 05a — Spotify

func probeSpotify() {
    let checkURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client")
    guard checkURL != nil else {
        print("SPOTIFY skip reason=not_installed")
        return
    }

    // Never send an Apple event to a process that is absent or tearing down:
    // that relaunches Spotify. Check from Swift first, then guard in-script.
    let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client")
    if apps.isEmpty {
        print("SPOTIFY skip reason=not_running")
        return
    }
    if apps.allSatisfy({ $0.isTerminated }) {
        print("SPOTIFY skip reason=terminating")
        return
    }

    let source = """
    if application "Spotify" is not running then
        return "not_running"
    end if
    tell application "Spotify"
        set stateValue to player state
        if stateValue is playing then
            set stateText to "playing"
        else if stateValue is paused then
            set stateText to "paused"
        else
            set stateText to "stopped"
        end if
        try
            set posValue to player position
        on error
            set posValue to -1
        end try
        try
            set durValue to (duration of current track) / 1000
        on error
            set durValue to -1
        end try
        try
            set nameValue to (name of current track)
        on error
            set nameValue to ""
        end try
        return stateText & "|" & posValue & "|" & durValue & "|" & nameValue
    end tell
    """

    var errInfo: NSDictionary?
    guard let script = NSAppleScript(source: source) else {
        print("SPOTIFY fail reason=script_compile")
        return
    }
    let result = script.executeAndReturnError(&errInfo)

    if let err = errInfo {
        let code = err[NSAppleScript.errorNumber] as? Int ?? 0
        let msg  = err[NSAppleScript.errorMessage] as? String ?? "?"
        print("SPOTIFY fail reason=applescript_error code=\(code) message=\(msg)")
        return
    }

    guard let output = result.stringValue else {
        print("SPOTIFY fail reason=no_result")
        return
    }
    if output == "not_running" {
        print("SPOTIFY skip reason=not_running")
        return
    }

    let parts = output.components(separatedBy: "|")
    guard parts.count >= 4 else {
        print("SPOTIFY fail reason=parse output=\(output)")
        return
    }
    print("SPOTIFY ok state=\(parts[0]) position=\(parts[1]) duration=\(parts[2]) track=\(parts[3])")
}

// -----------------------------------------------------------------------------
// 05b — MediaRemote

typealias MRGetNowPlayingInfo_t = @convention(c) (DispatchQueue, @escaping @convention(block) (CFDictionary?) -> Void) -> Void

func probeMediaRemote() {
    let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
    guard let handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL) else {
        print("MEDIAREMOTE fail reason=dlopen")
        return
    }
    guard let symPtr = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") else {
        print("MEDIAREMOTE fail reason=dlsym_get_now_playing")
        return
    }
    let fn = unsafeBitCast(symPtr, to: MRGetNowPlayingInfo_t.self)

    let sema = DispatchSemaphore(value: 0)
    var captured: [String: Any] = [:]

    fn(DispatchQueue.main) { info in
        if let dict = info as? [String: Any] {
            captured = dict
        }
        sema.signal()
    }

    // Pump the runloop while waiting.
    let deadline = Date().addingTimeInterval(3.0)
    while Date() < deadline {
        if sema.wait(timeout: .now() + .milliseconds(50)) == .success { break }
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }

    if captured.isEmpty {
        print("MEDIAREMOTE none no_now_playing_info")
        return
    }

    let bundle   = captured["kMRMediaRemoteNowPlayingInfoClientPropertiesData"] != nil ? "opaque" :
                   (captured["kMRMediaRemoteNowPlayingInfoContentItemIdentifier"] as? String ?? "unknown")
    let title    = captured["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
    let elapsed  = captured["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double ?? -1
    let duration = captured["kMRMediaRemoteNowPlayingInfoDuration"]    as? Double ?? -1
    let rate     = captured["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? -1

    print("MEDIAREMOTE ok bundle=\(bundle) title=\"\(title)\" elapsed=\(elapsed) duration=\(duration) rate=\(rate)")
}

// -----------------------------------------------------------------------------

probeSpotify()
probeMediaRemote()
