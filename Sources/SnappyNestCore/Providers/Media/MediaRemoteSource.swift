import Darwin
import Foundation

/// Browser / system media playback via the private MediaRemote framework.
/// All private-API access is isolated to this file. `dlopen`-loaded; nil
/// symbols leave the source in `.unknown`.
public final class MediaRemoteSource: MediaSource {
    public let identity = "browser"
    public private(set) var snapshot: MediaSnapshot = .unknown

    private typealias GetNowPlaying = @convention(c) (DispatchQueue, @escaping @convention(block) (CFDictionary?) -> Void) -> Void
    private typealias SendCommand   = @convention(c) (Int32, CFDictionary?) -> Bool
    private typealias RegisterNotif = @convention(c) (Bool) -> Void
    private typealias SetElapsed    = @convention(c) (Double) -> Void

    private let getFn: GetNowPlaying?
    private let sendFn: SendCommand?
    private let setElapsedFn: SetElapsed?

    /// MRCommand values, stable across the macOS versions we target.
    private enum Command: Int32 {
        case togglePlayPause = 2
        case nextTrack = 4
        case previousTrack = 5
    }

    private var pollTimer: Timer?
    private var handlers: [(MediaSnapshot) -> Void] = []

    public init() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        let handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL)
        if let handle = handle,
           let getSym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") {
            getFn = unsafeBitCast(getSym, to: GetNowPlaying.self)
        } else {
            getFn = nil
        }
        if let handle = handle,
           let sendSym = dlsym(handle, "MRMediaRemoteSendCommand") {
            sendFn = unsafeBitCast(sendSym, to: SendCommand.self)
        } else {
            sendFn = nil
        }
        if let handle = handle,
           let seekSym = dlsym(handle, "MRMediaRemoteSetElapsedTime") {
            setElapsedFn = unsafeBitCast(seekSym, to: SetElapsed.self)
        } else {
            setElapsedFn = nil
        }
        // Note: MRMediaRemoteRegisterForNowPlayingNotifications has changed
        // signature across OS versions and can crash if we call it wrong.
        // Polling at 1 Hz is more than enough for a Touch Bar progress bar,
        // and we still get NotificationCenter push events below.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        refresh()
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name(rawValue: "kMRMediaRemoteNowPlayingInfoDidChangeNotification"),
            object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name(rawValue: "kMRMediaRemoteNowPlayingApplicationDidChangeNotification"),
            object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
    }

    private func refresh() {
        guard let getFn = getFn else { return }
        getFn(DispatchQueue.main) { [weak self] info in
            guard let self = self else { return }
            let dict = info as? [String: Any] ?? [:]
            self.publish(self.build(from: dict))
        }
    }

    private func build(from dict: [String: Any]) -> MediaSnapshot {
        if dict.isEmpty {
            return MediaSnapshot(identity: identity, state: .unknown)
        }
        let title = dict["kMRMediaRemoteNowPlayingInfoTitle"] as? String
        let elapsed = dict["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double
        let duration = dict["kMRMediaRemoteNowPlayingInfoDuration"] as? Double
        let rate = dict["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0
        let elapsedAt: Date? = {
            if let ts = dict["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date { return ts }
            return Date()
        }()

        let state: MediaSnapshot.State = rate > 0 ? .playing : .paused
        return MediaSnapshot(
            identity: identity, state: state,
            elapsed: elapsed, duration: duration,
            elapsedAt: elapsedAt, rate: rate == 0 ? 1 : rate,
            title: title,
            canPlayPause: true,
            canReadPosition: elapsed != nil,
            canReadDuration: (duration ?? 0) > 0.5,
            canSeek: elapsed != nil && (duration ?? 0) > 0.5 && setElapsedFn != nil,
            canSkip: sendFn != nil
        )
    }

    private func publish(_ new: MediaSnapshot) {
        guard new != snapshot else { return }
        snapshot = new
        handlers.forEach { $0(new) }
    }

    public func togglePlayPause() { send(.togglePlayPause) }
    public func nextTrack() { send(.nextTrack) }
    public func previousTrack() { send(.previousTrack) }

    /// Whether a command may be sent at all: with no now-playing client,
    /// mediaremoted routes it to the default/last media app and launches it
    /// (like the F8 key opening Music). Only send when something is
    /// actually registered.
    private var hasNowPlayingClient: Bool {
        snapshot.state == .playing || snapshot.state == .paused
    }

    private func send(_ command: Command) {
        guard hasNowPlayingClient else { return }
        _ = sendFn?(command.rawValue, nil)
        refreshSoon()
    }

    public func seek(to seconds: TimeInterval) {
        guard hasNowPlayingClient, snapshot.canSeek, let setElapsedFn = setElapsedFn else { return }
        let duration = snapshot.duration ?? seconds
        setElapsedFn(min(duration, max(0, seconds)))
        refreshSoon()
    }

    private func refreshSoon() {
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
