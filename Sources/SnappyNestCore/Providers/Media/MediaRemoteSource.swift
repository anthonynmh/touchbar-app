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

    private let getFn: GetNowPlaying?
    private let sendFn: SendCommand?

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
            canReadDuration: (duration ?? 0) > 0.5
        )
    }

    private func publish(_ new: MediaSnapshot) {
        guard new != snapshot else { return }
        snapshot = new
        handlers.forEach { $0(new) }
    }

    public func togglePlayPause() {
        // MRCommand 2 = togglePlayPause on most macOS versions.
        _ = sendFn?(2, nil)
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
