import Foundation

/// A media playback snapshot. `elapsed` and `duration` are in seconds. If
/// `duration` is nil the source is a live stream or hasn't reported one yet
/// — the pet must not fabricate progress in that case.
public struct MediaSnapshot: Equatable {
    public enum State: Equatable { case playing, paused, stopped, unknown }
    public let identity: String
    public let state: State
    public let elapsed: TimeInterval?
    public let duration: TimeInterval?
    public let elapsedAt: Date?
    public let rate: Double
    public let title: String?
    public let canPlayPause: Bool
    public let canReadPosition: Bool
    public let canReadDuration: Bool
    /// The source can move the playhead (`MediaSource.seek(to:)`).
    public let canSeek: Bool
    /// The source can skip tracks (`nextTrack` / `previousTrack`).
    public let canSkip: Bool

    public init(
        identity: String,
        state: State,
        elapsed: TimeInterval? = nil,
        duration: TimeInterval? = nil,
        elapsedAt: Date? = nil,
        rate: Double = 1,
        title: String? = nil,
        canPlayPause: Bool = false,
        canReadPosition: Bool = false,
        canReadDuration: Bool = false,
        canSeek: Bool = false,
        canSkip: Bool = false
    ) {
        self.identity = identity
        self.state = state
        self.elapsed = elapsed
        self.duration = duration
        self.elapsedAt = elapsedAt
        self.rate = rate
        self.title = title
        self.canPlayPause = canPlayPause
        self.canReadPosition = canReadPosition
        self.canReadDuration = canReadDuration
        self.canSeek = canSeek
        self.canSkip = canSkip
    }

    public static let unknown = MediaSnapshot(identity: "none", state: .unknown)

    /// True when both a valid position and a valid duration are available
    /// and the pet should follow progress.
    public var canFollowProgress: Bool {
        guard state == .playing || state == .paused else { return false }
        guard canReadPosition, canReadDuration else { return false }
        guard let d = duration, d > 0.5 else { return false }
        guard let e = elapsed, e.isFinite, e >= 0 else { return false }
        return true
    }

    /// Interpolate the position forward from `elapsedAt` at `rate`, clamped
    /// to `[0, duration]`. When the state is paused we hold `elapsed` still.
    public func positionAt(_ now: Date) -> TimeInterval? {
        guard let elapsed = elapsed else { return nil }
        guard let duration = duration else { return elapsed }
        let base: TimeInterval
        if state == .playing, let elapsedAt = elapsedAt {
            let dt = now.timeIntervalSince(elapsedAt)
            base = elapsed + dt * rate
        } else {
            base = elapsed
        }
        return min(duration, max(0, base))
    }

    /// Fractional position for the progress trail. Nil if we shouldn't draw one.
    public func progressFraction(at now: Date) -> Double? {
        guard canFollowProgress else { return nil }
        guard let pos = positionAt(now), let d = duration, d > 0 else { return nil }
        return min(1.0, max(0.0, pos / d))
    }
}

public protocol MediaSource: AnyObject {
    var identity: String { get }
    var snapshot: MediaSnapshot { get }
    func togglePlayPause()
    /// Move the playhead to `seconds`. Implementations must never launch
    /// the media app; when nothing is playing this is a no-op.
    func seek(to seconds: TimeInterval)
    func nextTrack()
    func previousTrack()
    func subscribe(_ handler: @escaping (MediaSnapshot) -> Void)
    func unsubscribeAll()
}

public final class FakeMediaSource: MediaSource {
    public var identity: String
    public private(set) var snapshot: MediaSnapshot {
        didSet {
            guard oldValue != snapshot else { return }
            handlers.forEach { $0(snapshot) }
        }
    }
    public var onTogglePlayPause: () -> Void = {}
    public private(set) var seekCalls: [TimeInterval] = []
    public private(set) var nextCalls = 0
    public private(set) var previousCalls = 0
    private var handlers: [(MediaSnapshot) -> Void] = []

    public init(identity: String = "fake", snapshot: MediaSnapshot = .unknown) {
        self.identity = identity
        self.snapshot = snapshot
    }

    public func set(_ snapshot: MediaSnapshot) { self.snapshot = snapshot }

    public func togglePlayPause() { onTogglePlayPause() }
    public func seek(to seconds: TimeInterval) { seekCalls.append(seconds) }
    public func nextTrack() { nextCalls += 1 }
    public func previousTrack() { previousCalls += 1 }

    public func subscribe(_ handler: @escaping (MediaSnapshot) -> Void) {
        handlers.append(handler)
        handler(snapshot)
    }

    public func unsubscribeAll() { handlers.removeAll() }
}
