// SnappyMediaRemoteHost — MediaRemote reads and commands, hosted in an
// Apple-signed process.
//
// Since macOS 15.4 mediaremoted answers `MRMediaRemoteGetNowPlayingInfo`
// only for processes carrying an Apple platform signature (or a private
// entitlement that third parties cannot obtain), so the app itself always
// receives an empty dictionary. `/usr/bin/perl` is Apple-signed and can load
// this dylib through `DynaLoader`; the app spawns it and talks to this code
// over pipes:
//
//   stdout, one JSON object per line whenever the now-playing info changes:
//     {"title":"…","elapsed":83.2,"duration":212.0,"rate":1.0,"timestamp":…,
//      "bundle":"org.mozilla.firefox"}
//     {}                                   (no now-playing client)
//   `bundle` is the now-playing client's bundle identifier (from
//   `MRMediaRemoteGetNowPlayingApplicationPID`); it is omitted when the pid
//   cannot be resolved. The app uses it to tell a Spotify snapshot mirrored
//   by mediaremoted apart from a browser one.
//   stdin, one command per line:
//     toggle | next | previous | seek <seconds> | get | quit
//
// The process exits when stdin closes, so it never outlives the app. Commands
// are only forwarded while a now-playing client is registered; otherwise
// mediaremoted would launch the default media app.

import AppKit
import Darwin
import Foundation

private typealias GetNowPlaying = @convention(c) (DispatchQueue, @escaping @convention(block) (CFDictionary?) -> Void) -> Void
private typealias SendCommand   = @convention(c) (Int32, CFDictionary?) -> Bool
private typealias SetElapsed    = @convention(c) (Double) -> Void
private typealias GetNowPlayingPID = @convention(c) (DispatchQueue, @escaping @convention(block) (Int32) -> Void) -> Void

private final class Host {
    private let getFn: GetNowPlaying?
    private let sendFn: SendCommand?
    private let setElapsedFn: SetElapsed?
    private let getPIDFn: GetNowPlayingPID?
    private var lastLine = ""
    private var hasClient = false
    private var stdinBuffer = Data()
    private var pollTimer: Timer?

    init() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        let handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL)
        func symbol<T>(_ name: String, as: T.Type) -> T? {
            guard let handle, let sym = dlsym(handle, name) else { return nil }
            return unsafeBitCast(sym, to: T.self)
        }
        getFn = symbol("MRMediaRemoteGetNowPlayingInfo", as: GetNowPlaying.self)
        sendFn = symbol("MRMediaRemoteSendCommand", as: SendCommand.self)
        setElapsedFn = symbol("MRMediaRemoteSetElapsedTime", as: SetElapsed.self)
        getPIDFn = symbol("MRMediaRemoteGetNowPlayingApplicationPID", as: GetNowPlayingPID.self)
    }

    func run(once: Bool) {
        guard getFn != nil else {
            emit("{\"error\":\"mediaremote_unavailable\"}", force: true)
            exit(2)
        }
        if once {
            refresh { exit(0) }
            RunLoop.main.run()
            return
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        for name in ["kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                     "kMRMediaRemoteNowPlayingApplicationDidChangeNotification"] {
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name(rawValue: name), object: nil, queue: .main
            ) { [weak self] _ in self?.refresh() }
        }
        refresh()
        FileHandle.standardInput.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async {
                guard let self else { return }
                if data.isEmpty {
                    // stdin closed: the app is gone.
                    exit(0)
                }
                self.consume(data)
            }
        }
        RunLoop.main.run()
    }

    // MARK: - Reads

    private func refresh(then completion: (() -> Void)? = nil) {
        guard let getFn else { return }
        getFn(DispatchQueue.main) { [weak self] info in
            guard let self else { return }
            let dict = info as? [String: Any] ?? [:]
            self.hasClient = !dict.isEmpty
            guard !dict.isEmpty, let getPIDFn = self.getPIDFn else {
                self.emit(Self.line(from: dict, bundle: nil))
                completion?()
                return
            }
            // A passive read like the info itself: resolving the pid never
            // sends a command, so it cannot launch anything.
            getPIDFn(DispatchQueue.main) { [weak self] pid in
                guard let self else { return }
                let bundle = pid > 0 ? NSRunningApplication(processIdentifier: pid)?.bundleIdentifier : nil
                self.emit(Self.line(from: dict, bundle: bundle))
                completion?()
            }
        }
    }

    private static func line(from dict: [String: Any], bundle: String?) -> String {
        guard !dict.isEmpty else { return "{}" }
        var out: [String: Any] = [:]
        if let bundle { out["bundle"] = bundle }
        if let title = dict["kMRMediaRemoteNowPlayingInfoTitle"] as? String { out["title"] = title }
        if let elapsed = dict["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double { out["elapsed"] = elapsed }
        if let duration = dict["kMRMediaRemoteNowPlayingInfoDuration"] as? Double { out["duration"] = duration }
        out["rate"] = dict["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0
        let timestamp = dict["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date ?? Date()
        out["timestamp"] = timestamp.timeIntervalSince1970
        guard let data = try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    private func emit(_ line: String, force: Bool = false) {
        guard force || line != lastLine else { return }
        lastLine = line
        FileHandle.standardOutput.write((line + "\n").data(using: .utf8)!)
    }

    // MARK: - Commands

    private func consume(_ data: Data) {
        stdinBuffer.append(data)
        while let newline = stdinBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = stdinBuffer[stdinBuffer.startIndex..<newline]
            stdinBuffer.removeSubrange(stdinBuffer.startIndex...newline)
            if let line = String(data: lineData, encoding: .utf8) {
                handle(command: line.trimmingCharacters(in: .whitespaces))
            }
        }
    }

    private func handle(command: String) {
        let parts = command.split(separator: " ", maxSplits: 1).map(String.init)
        guard let verb = parts.first else { return }
        switch verb {
        case "get":
            lastLine = ""
            refresh()
        case "quit":
            exit(0)
        case "toggle":   send(2)
        case "next":     send(4)
        case "previous": send(5)
        case "seek":
            guard hasClient, let setElapsedFn, let seconds = parts.dropFirst().first.flatMap(Double.init) else { return }
            setElapsedFn(max(0, seconds))
            refreshSoon()
        default:
            break
        }
    }

    private func send(_ command: Int32) {
        guard hasClient, let sendFn else { return }
        _ = sendFn(command, nil)
        refreshSoon()
    }

    private func refreshSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.lastLine = ""
            self?.refresh()
        }
    }
}

/// Entry point called from perl through `DynaLoader::dl_install_xsub`. The
/// XSUB arguments are ignored. `SNAPPY_MEDIAREMOTE_ONCE=1` prints one line
/// and exits (used by Probe 05c); otherwise the host streams until stdin
/// closes. Never returns.
@_cdecl("snappy_mediaremote_host")
public func snappyMediaRemoteHost() {
    setvbuf(stdout, nil, _IOLBF, 0)
    let once = ProcessInfo.processInfo.environment["SNAPPY_MEDIAREMOTE_ONCE"] == "1"
    let host = Host()
    host.run(once: once)
    exit(0)
}
