import AppKit
import Foundation

/// The OS surface `SpotifyMediaSource` touches. Kept behind a bridge so the
/// launch-avoidance policy can be tested without Spotify installed.
internal protocol SpotifyScriptingBridge: AnyObject {
    func isInstalled() -> Bool
    /// `isRunning` is true when a Spotify process exists; `isTerminated` is
    /// true once that process has exited but is still tracked.
    func runningApplication() -> (isRunning: Bool, isTerminated: Bool)
    /// Executes the player-state script. Returns the raw `"state|pos|dur|name"`
    /// string, `"not_running"`, or nil on any AppleScript error.
    func readPlayerState() -> String?
    func sendPlayPause()
    func sendSeek(to seconds: TimeInterval)
    func sendNextTrack()
    func sendPreviousTrack()
    func observeWorkspace(launch: @escaping () -> Void, terminate: @escaping () -> Void)
    func observePlaybackStateChanged(_ handler: @escaping ([AnyHashable: Any]?) -> Void)
}

/// How the source hops between the script thread and the main thread. Tests
/// substitute synchronous closures.
internal struct SpotifyDispatch {
    var background: (@escaping () -> Void) -> Void
    var main: (@escaping () -> Void) -> Void

    static let immediate = SpotifyDispatch(background: { $0() }, main: { $0() })
}

/// Real bridge. `tell application "Spotify"` launches the app whenever an
/// Apple event is delivered to a process that is absent or tearing down, so
/// nothing here sends an event unless the source's policy says Spotify is
/// alive. The script's own `is running` guard is only a second line of defence.
private final class SystemSpotifyScriptingBridge: SpotifyScriptingBridge {
    static let bundleID = SpotifyMediaSource.bundleID

    private static let scriptSource = """
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

    private static let playPauseSource = """
    if application "Spotify" is running then
        tell application "Spotify" to playpause
    end if
    """

    private static let nextSource = """
    if application "Spotify" is running then
        tell application "Spotify" to next track
    end if
    """

    private static let previousSource = """
    if application "Spotify" is running then
        tell application "Spotify" to previous track
    end if
    """

    /// The position is substituted per call; the script is compiled each
    /// time but only after the source's launch gate has passed.
    private static func seekSource(seconds: TimeInterval) -> String {
        let clamped = max(0, seconds.isFinite ? seconds : 0)
        return """
        if application "Spotify" is running then
            tell application "Spotify" to set player position to \(String(format: "%.2f", clamped))
        end if
        """
    }

    // Compiled once; NSAppleScript is only ever used from the source's serial queue.
    private lazy var stateScript = NSAppleScript(source: Self.scriptSource)
    private lazy var playPauseScript = NSAppleScript(source: Self.playPauseSource)
    private lazy var nextScript = NSAppleScript(source: Self.nextSource)
    private lazy var previousScript = NSAppleScript(source: Self.previousSource)
    private var observers: [NSObjectProtocol] = []

    func isInstalled() -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) != nil
    }

    func runningApplication() -> (isRunning: Bool, isTerminated: Bool) {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID)
        guard !apps.isEmpty else { return (false, false) }
        return (true, apps.allSatisfy { $0.isTerminated })
    }

    func readPlayerState() -> String? {
        guard let script = stateScript else { return nil }
        var err: NSDictionary?
        let result = script.executeAndReturnError(&err)
        if err != nil { return nil }
        return result.stringValue
    }

    func sendPlayPause() {
        var err: NSDictionary?
        _ = playPauseScript?.executeAndReturnError(&err)
    }

    func sendSeek(to seconds: TimeInterval) {
        var err: NSDictionary?
        _ = NSAppleScript(source: Self.seekSource(seconds: seconds))?.executeAndReturnError(&err)
    }

    func sendNextTrack() {
        var err: NSDictionary?
        _ = nextScript?.executeAndReturnError(&err)
    }

    func sendPreviousTrack() {
        var err: NSDictionary?
        _ = previousScript?.executeAndReturnError(&err)
    }

    func observeWorkspace(launch: @escaping () -> Void, terminate: @escaping () -> Void) {
        let center = NSWorkspace.shared.notificationCenter
        func isSpotify(_ note: Notification) -> Bool {
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            return app?.bundleIdentifier == Self.bundleID
        }
        observers.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { note in if isSpotify(note) { launch() } })
        observers.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { note in if isSpotify(note) { terminate() } })
    }

    func observePlaybackStateChanged(_ handler: @escaping ([AnyHashable: Any]?) -> Void) {
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil, queue: .main
        ) { note in handler(note.userInfo) })
    }
}

/// AppleScript-driven adapter for the Spotify.app player. Requires Automation
/// permission (macOS asks the user on first execute; deny → the adapter
/// stays in `.unknown` forever).
///
/// Policy: an Apple event is only sent when Spotify is installed, has a live
/// non-terminated process, and no quit is suspected. Spotify posts a
/// `PlaybackStateChanged` with `Player State = Stopped` while quitting;
/// scripting during that window relaunches it, so the source goes quiet for
/// `quiesceInterval` instead. Polling only runs while Spotify is running.
public final class SpotifyMediaSource: MediaSource {
    public let identity = "spotify"
    /// Every snapshot carries this as `sourceApp` so `MediaArbiter` can
    /// recognise Spotify when mediaremoted reports it through the
    /// MediaRemote source as well.
    public static let bundleID = "com.spotify.client"
    public private(set) var snapshot: MediaSnapshot = .unknown

    internal static let quiesceInterval: TimeInterval = 3.0

    private let bridge: SpotifyScriptingBridge
    private let now: () -> Date
    private let dispatch: SpotifyDispatch
    private var pollTimer: Timer?
    private var handlers: [(MediaSnapshot) -> Void] = []
    private var scriptingSuppressedUntil: Date = .distantPast
    private var inFlight = false

    public convenience init() {
        let queue = DispatchQueue(label: "snappy-nest.spotify-script", qos: .utility)
        self.init(
            bridge: SystemSpotifyScriptingBridge(),
            now: Date.init,
            dispatch: SpotifyDispatch(
                background: { queue.async(execute: $0) },
                main: { DispatchQueue.main.async(execute: $0) }
            ),
            usesTimer: true
        )
    }

    internal init(bridge: SpotifyScriptingBridge,
                  now: @escaping () -> Date = Date.init,
                  dispatch: SpotifyDispatch = .immediate,
                  usesTimer: Bool = false) {
        self.bridge = bridge
        self.now = now
        self.dispatch = dispatch
        self.usesTimer = usesTimer

        bridge.observeWorkspace(
            launch: { [weak self] in self?.spotifyDidLaunch() },
            terminate: { [weak self] in self?.spotifyDidTerminate() }
        )
        bridge.observePlaybackStateChanged { [weak self] info in
            self?.playbackStateDidChange(info)
        }

        if bridge.runningApplication().isRunning {
            startPolling()
            refresh()
        } else {
            publish(Self.notRunningSnapshot(identity: identity))
        }
    }

    deinit { pollTimer?.invalidate() }

    // MARK: Polling lifecycle

    private let usesTimer: Bool
    /// True while the 1 Hz poll is active (only when Spotify is running).
    internal private(set) var isPolling = false

    private func startPolling() {
        guard !isPolling else { return }
        isPolling = true
        if usesTimer {
            pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.pollTick()
            }
        }
    }

    private func stopPolling() {
        isPolling = false
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// One poll-timer firing. Exposed so tests can drive it without a run loop.
    internal func pollTick() {
        guard isPolling else { return }
        refresh()
    }

    private func spotifyDidLaunch() {
        scriptingSuppressedUntil = .distantPast
        startPolling()
        refresh()
    }

    private func spotifyDidTerminate() {
        stopPolling()
        scriptingSuppressedUntil = .distantPast
        publish(Self.notRunningSnapshot(identity: identity))
    }

    private func playbackStateDidChange(_ info: [AnyHashable: Any]?) {
        let playerState = info?["Player State"] as? String
        if playerState == "Stopped" {
            // Spotify posts this while quitting. Any Apple event now relaunches it.
            suppressScripting()
            publish(MediaSnapshot(identity: identity, state: .stopped, sourceApp: Self.bundleID, canPlayPause: true))
            return
        }
        refresh()
    }

    private func suppressScripting() {
        scriptingSuppressedUntil = now().addingTimeInterval(Self.quiesceInterval)
    }

    /// The single gate in front of every Apple event.
    private func shouldScript() -> Bool {
        guard bridge.isInstalled() else { return false }
        let app = bridge.runningApplication()
        guard app.isRunning, !app.isTerminated else { return false }
        return now() >= scriptingSuppressedUntil
    }

    // MARK: Reading state

    private func refresh() {
        guard shouldScript(), !inFlight else { return }
        inFlight = true
        dispatch.background { [weak self] in
            guard let self = self else { return }
            let raw = self.bridge.readPlayerState()
            self.dispatch.main {
                self.inFlight = false
                self.handleScriptResult(raw)
            }
        }
    }

    private func handleScriptResult(_ raw: String?) {
        guard let raw = raw else {
            // An AppleScript error mid-poll usually means the process is going
            // away; back off rather than retry into a launch.
            suppressScripting()
            publish(MediaSnapshot(identity: identity, state: .unknown, sourceApp: Self.bundleID))
            return
        }
        if raw == "not_running" {
            publish(Self.notRunningSnapshot(identity: identity))
            return
        }
        publish(Self.parse(raw, identity: identity) ?? .unknown)
    }

    internal static func notRunningSnapshot(identity: String) -> MediaSnapshot {
        MediaSnapshot(identity: identity, state: .stopped, sourceApp: bundleID, canPlayPause: true,
                      canReadPosition: false, canReadDuration: false)
    }

    /// Parses `"state|pos|dur|name"` as returned by the player-state script.
    internal static func parse(_ raw: String, identity: String, at date: Date = Date()) -> MediaSnapshot? {
        let parts = raw.components(separatedBy: "|")
        guard parts.count >= 4 else { return nil }
        let pos = Double(parts[1]) ?? -1
        let dur = Double(parts[2]) ?? -1
        // Track names may themselves contain "|".
        let name = parts[3...].joined(separator: "|")

        let state: MediaSnapshot.State
        switch parts[0] {
        case "playing": state = .playing
        case "paused":  state = .paused
        default:        state = .stopped
        }
        return MediaSnapshot(
            identity: identity, state: state,
            elapsed: pos >= 0 ? pos : nil,
            duration: dur > 0 ? dur : nil,
            elapsedAt: date,
            rate: 1,
            title: name.isEmpty ? nil : name,
            sourceApp: bundleID,
            canPlayPause: true,
            canReadPosition: pos >= 0,
            canReadDuration: dur > 0,
            canSeek: pos >= 0 && dur > 0,
            canSkip: true
        )
    }

    private func publish(_ new: MediaSnapshot) {
        guard new != snapshot else { return }
        snapshot = new
        handlers.forEach { $0(new) }
    }

    // MARK: MediaSource

    /// No-op unless Spotify is running: the pet must never launch Spotify.
    public func togglePlayPause() {
        send { $0.sendPlayPause() }
    }

    public func seek(to seconds: TimeInterval) {
        send { $0.sendSeek(to: seconds) }
    }

    public func nextTrack() {
        send { $0.sendNextTrack() }
    }

    public func previousTrack() {
        send { $0.sendPreviousTrack() }
    }

    /// Every command passes the same gate as reads, then refreshes sooner
    /// than the next poll so the readback confirms the change.
    private func send(_ command: @escaping (SpotifyScriptingBridge) -> Void) {
        guard shouldScript() else { return }
        dispatch.background { [weak self] in
            guard let self = self else { return }
            command(self.bridge)
            self.dispatch.main { [weak self] in
                self?.refresh()
            }
        }
    }

    public func subscribe(_ handler: @escaping (MediaSnapshot) -> Void) {
        handlers.append(handler)
        handler(snapshot)
    }

    public func unsubscribeAll() { handlers.removeAll() }
}
