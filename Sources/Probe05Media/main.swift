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
//
// 05c  MediaRemote through an Apple-signed host. Since macOS 15.4 mediaremoted
//      answers only Apple-signed processes, so 05b is expected to be empty
//      while 05c (the same call made inside /usr/bin/perl, which loads
//      libSnappyMediaRemoteHost.dylib via DynaLoader) reports the track.
//      Needs SNAPPY_MEDIAREMOTE_HOST=<path to the dylib> (run-probe.sh sets it).
//      Success:  MEDIAREMOTE_HOST ok <json line>
//      Empty:    MEDIAREMOTE_HOST none no_now_playing_info
//      Failure:  MEDIAREMOTE_HOST fail reason=<...>

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
// 05c — MediaRemote hosted in perl

func probeMediaRemoteHost() {
    guard let dylib = ProcessInfo.processInfo.environment["SNAPPY_MEDIAREMOTE_HOST"], !dylib.isEmpty else {
        print("MEDIAREMOTE_HOST fail reason=SNAPPY_MEDIAREMOTE_HOST_unset")
        return
    }
    guard FileManager.default.isExecutableFile(atPath: "/usr/bin/perl") else {
        print("MEDIAREMOTE_HOST fail reason=no_perl")
        return
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
    process.arguments = ["-e", MediaRemoteHostLauncher.perlScript, dylib]
    var env = ProcessInfo.processInfo.environment
    env["SNAPPY_MEDIAREMOTE_ONCE"] = "1"
    process.environment = env
    let out = Pipe()
    process.standardOutput = out
    process.standardInput = FileHandle.nullDevice
    do { try process.run() } catch {
        print("MEDIAREMOTE_HOST fail reason=spawn error=\(error)")
        return
    }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let line = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if process.terminationStatus != 0 {
        print("MEDIAREMOTE_HOST fail reason=exit_\(process.terminationStatus) output=\(line)")
    } else if line == "{}" || line.isEmpty {
        print("MEDIAREMOTE_HOST none no_now_playing_info")
    } else {
        print("MEDIAREMOTE_HOST ok \(line)")
    }
}

/// Same fixed perl program the app uses (`PerlMediaRemoteHost.perlScript`);
/// duplicated so the probe stays dependency-free.
enum MediaRemoteHostLauncher {
    static let perlScript = """
    use DynaLoader;
    my $lib = DynaLoader::dl_load_file($ARGV[0], 1) or die DynaLoader::dl_error();
    my $sym = DynaLoader::dl_find_symbol($lib, "snappy_mediaremote_host") or die "snappy_mediaremote_host not found";
    DynaLoader::dl_install_xsub("main::run", $sym);
    main::run();
    """
}

// -----------------------------------------------------------------------------

probeSpotify()
probeMediaRemote()
probeMediaRemoteHost()
