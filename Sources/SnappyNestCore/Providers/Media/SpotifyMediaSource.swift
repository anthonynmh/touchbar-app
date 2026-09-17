import AppKit
import Foundation

/// AppleScript-driven adapter for the Spotify.app player. Requires Automation
/// permission (macOS asks the user on first execute; deny → the adapter
/// stays in `.unknown` forever).
public final class SpotifyMediaSource: MediaSource {
    public let identity = "spotify"
    public private(set) var snapshot: MediaSnapshot = .unknown

    private var pollTimer: Timer?
    private var handlers: [(MediaSnapshot) -> Void] = []

    public init() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
        refresh()
    }

    private static let scriptSource = """
    tell application "System Events"
        set isRunning to (name of processes) contains "Spotify"
    end tell
    if isRunning is false then
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

    private func refresh() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let snapshot = self.runScript()
            DispatchQueue.main.async {
                self.publish(snapshot)
            }
        }
    }

    private func runScript() -> MediaSnapshot {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") != nil else {
            return MediaSnapshot(identity: identity, state: .unknown)
        }
        var err: NSDictionary?
        guard let script = NSAppleScript(source: Self.scriptSource) else {
            return MediaSnapshot(identity: identity, state: .unknown)
        }
        let result = script.executeAndReturnError(&err)
        if err != nil {
            return MediaSnapshot(identity: identity, state: .unknown)
        }
        guard let out = result.stringValue else {
            return MediaSnapshot(identity: identity, state: .unknown)
        }
        if out == "not_running" {
            return MediaSnapshot(identity: identity, state: .stopped, canPlayPause: true, canReadPosition: false, canReadDuration: false)
        }
        let parts = out.components(separatedBy: "|")
        guard parts.count >= 4 else { return .unknown }
        let stateText = parts[0]
        let pos = Double(parts[1]) ?? -1
        let dur = Double(parts[2]) ?? -1
        let name = parts[3]

        let state: MediaSnapshot.State
        switch stateText {
        case "playing": state = .playing
        case "paused":  state = .paused
        default:        state = .stopped
        }
        return MediaSnapshot(
            identity: identity, state: state,
            elapsed: pos >= 0 ? pos : nil,
            duration: dur > 0 ? dur : nil,
            elapsedAt: Date(),
            rate: 1,
            title: name.isEmpty ? nil : name,
            canPlayPause: true,
            canReadPosition: pos >= 0,
            canReadDuration: dur > 0
        )
    }

    private func publish(_ new: MediaSnapshot) {
        guard new != snapshot else { return }
        snapshot = new
        handlers.forEach { $0(new) }
    }

    public func togglePlayPause() {
        let source = """
        tell application "Spotify" to playpause
        """
        DispatchQueue.global(qos: .utility).async {
            if let s = NSAppleScript(source: source) {
                var err: NSDictionary?
                _ = s.executeAndReturnError(&err)
            }
        }
        // Refresh sooner than the next poll.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.refresh()
        }
    }

    public func subscribe(_ handler: @escaping (MediaSnapshot) -> Void) {
        handlers.append(handler)
        handler(snapshot)
    }

    public func unsubscribeAll() { handlers.removeAll() }
}
