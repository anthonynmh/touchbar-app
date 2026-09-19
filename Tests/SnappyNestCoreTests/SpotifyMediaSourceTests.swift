import XCTest
@testable import SnappyNestCore

private final class FakeSpotifyScriptingBridge: SpotifyScriptingBridge {
    var installed = true
    var running = true
    var terminated = false
    /// Value returned by the next script run; nil simulates an AppleScript error.
    var scriptResult: String? = "playing|30|300|Song"
    private(set) var readCount = 0
    private(set) var playPauseCount = 0
    private(set) var seeks: [TimeInterval] = []
    private(set) var nextCount = 0
    private(set) var previousCount = 0

    private var launch: (() -> Void)?
    private var terminate: (() -> Void)?
    private var playback: (([AnyHashable: Any]?) -> Void)?

    func isInstalled() -> Bool { installed }
    func runningApplication() -> (isRunning: Bool, isTerminated: Bool) { (running, terminated) }
    func readPlayerState() -> String? { readCount += 1; return scriptResult }
    func sendPlayPause() { playPauseCount += 1 }
    func sendSeek(to seconds: TimeInterval) { seeks.append(seconds) }
    func sendNextTrack() { nextCount += 1 }
    func sendPreviousTrack() { previousCount += 1 }
    func observeWorkspace(launch: @escaping () -> Void, terminate: @escaping () -> Void) {
        self.launch = launch
        self.terminate = terminate
    }
    func observePlaybackStateChanged(_ handler: @escaping ([AnyHashable: Any]?) -> Void) {
        playback = handler
    }

    func fireLaunch() { running = true; terminated = false; launch?() }
    func fireTerminate() { running = false; terminated = false; terminate?() }
    func firePlayback(state: String) { playback?(["Player State": state]) }
}

final class SpotifyMediaSourceTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private var clock = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeSource(_ bridge: FakeSpotifyScriptingBridge) -> SpotifyMediaSource {
        SpotifyMediaSource(bridge: bridge, now: { self.clock })
    }

    func testNotRunningNeverScriptsAndDoesNotPoll() {
        let bridge = FakeSpotifyScriptingBridge()
        bridge.running = false
        let source = makeSource(bridge)

        XCTAssertEqual(bridge.readCount, 0)
        XCTAssertFalse(source.isPolling)
        XCTAssertEqual(source.snapshot.state, .stopped)
        XCTAssertTrue(source.snapshot.canPlayPause)
        XCTAssertEqual(source.snapshot.sourceApp, SpotifyMediaSource.bundleID)
        source.pollTick()
        XCTAssertEqual(bridge.readCount, 0)
    }

    func testRunningParsesPlayerState() {
        let bridge = FakeSpotifyScriptingBridge()
        let source = makeSource(bridge)

        XCTAssertTrue(source.isPolling)
        XCTAssertEqual(bridge.readCount, 1)
        XCTAssertEqual(source.snapshot.state, .playing)
        XCTAssertEqual(source.snapshot.elapsed, 30)
        XCTAssertEqual(source.snapshot.duration, 300)
        XCTAssertEqual(source.snapshot.title, "Song")
        XCTAssertEqual(source.snapshot.sourceApp, SpotifyMediaSource.bundleID)
        XCTAssertTrue(source.snapshot.canFollowProgress)
    }

    func testStoppedNotificationSuppressesScriptingForQuiesceWindow() {
        let bridge = FakeSpotifyScriptingBridge()
        let source = makeSource(bridge)
        XCTAssertEqual(bridge.readCount, 1)

        bridge.firePlayback(state: "Stopped")
        XCTAssertEqual(bridge.readCount, 1, "Stopped must not trigger a script")
        XCTAssertEqual(source.snapshot.state, .stopped)

        clock = base.addingTimeInterval(SpotifyMediaSource.quiesceInterval - 0.5)
        source.pollTick()
        bridge.firePlayback(state: "Playing")
        source.togglePlayPause()
        XCTAssertEqual(bridge.readCount, 1, "no scripting inside the quiesce window")
        XCTAssertEqual(bridge.playPauseCount, 0)

        clock = base.addingTimeInterval(SpotifyMediaSource.quiesceInterval)
        source.pollTick()
        XCTAssertEqual(bridge.readCount, 2, "scripting resumes after the window")
    }

    func testTerminateStopsPollingAndLaunchResumesIt() {
        let bridge = FakeSpotifyScriptingBridge()
        let source = makeSource(bridge)

        bridge.fireTerminate()
        XCTAssertFalse(source.isPolling)
        XCTAssertEqual(source.snapshot.state, .stopped)
        source.pollTick()
        XCTAssertEqual(bridge.readCount, 1)

        bridge.fireLaunch()
        XCTAssertTrue(source.isPolling)
        XCTAssertEqual(bridge.readCount, 2)
        source.pollTick()
        XCTAssertEqual(bridge.readCount, 3)
    }

    func testTogglePlayPauseIsNoOpWhenNotRunningOrTerminated() {
        let bridge = FakeSpotifyScriptingBridge()
        bridge.running = false
        let source = makeSource(bridge)
        source.togglePlayPause()
        XCTAssertEqual(bridge.playPauseCount, 0)

        bridge.running = true
        bridge.terminated = true
        source.togglePlayPause()
        XCTAssertEqual(bridge.playPauseCount, 0)

        bridge.terminated = false
        source.togglePlayPause()
        XCTAssertEqual(bridge.playPauseCount, 1)
    }

    func testSeekAndSkipPassTheSameLaunchGateAsPlayPause() {
        let bridge = FakeSpotifyScriptingBridge()
        bridge.running = false
        let source = makeSource(bridge)
        source.seek(to: 42)
        source.nextTrack()
        source.previousTrack()
        XCTAssertEqual(bridge.seeks, [])
        XCTAssertEqual(bridge.nextCount, 0)
        XCTAssertEqual(bridge.previousCount, 0)

        bridge.fireLaunch()
        let readsBefore = bridge.readCount
        source.seek(to: 42)
        source.nextTrack()
        source.previousTrack()
        XCTAssertEqual(bridge.seeks, [42])
        XCTAssertEqual(bridge.nextCount, 1)
        XCTAssertEqual(bridge.previousCount, 1)
        XCTAssertEqual(bridge.readCount, readsBefore + 3, "each command reads the state back")
        XCTAssertTrue(source.snapshot.canSeek)
        XCTAssertTrue(source.snapshot.canSkip)
    }

    func testPlayingNotificationTriggersRefresh() {
        let bridge = FakeSpotifyScriptingBridge()
        let source = makeSource(bridge)
        bridge.scriptResult = "paused|10|200|Other"
        bridge.firePlayback(state: "Paused")
        XCTAssertEqual(bridge.readCount, 2)
        XCTAssertEqual(source.snapshot.state, .paused)
        XCTAssertEqual(source.snapshot.title, "Other")
    }

    func testScriptErrorEntersQuiesceWindow() {
        let bridge = FakeSpotifyScriptingBridge()
        bridge.scriptResult = nil
        let source = makeSource(bridge)
        XCTAssertEqual(bridge.readCount, 1)
        XCTAssertEqual(source.snapshot.state, .unknown)

        source.pollTick()
        XCTAssertEqual(bridge.readCount, 1)

        clock = base.addingTimeInterval(SpotifyMediaSource.quiesceInterval)
        bridge.scriptResult = "playing|1|2|X"
        source.pollTick()
        XCTAssertEqual(bridge.readCount, 2)
        XCTAssertEqual(source.snapshot.state, .playing)
    }

    func testNotInstalledNeverScripts() {
        let bridge = FakeSpotifyScriptingBridge()
        bridge.installed = false
        let source = makeSource(bridge)
        source.pollTick()
        source.togglePlayPause()
        XCTAssertEqual(bridge.readCount, 0)
        XCTAssertEqual(bridge.playPauseCount, 0)
    }

    func testParse() {
        let s = SpotifyMediaSource.parse("paused|12.5|240|A | B", identity: "spotify", at: base)
        XCTAssertEqual(s?.state, .paused)
        XCTAssertEqual(s?.elapsed, 12.5)
        XCTAssertEqual(s?.duration, 240)
        XCTAssertEqual(s?.title, "A | B")
        XCTAssertEqual(s?.elapsedAt, base)

        let missing = SpotifyMediaSource.parse("stopped|-1|-1|", identity: "spotify", at: base)
        XCTAssertEqual(missing?.state, .stopped)
        XCTAssertNil(missing?.elapsed)
        XCTAssertNil(missing?.duration)
        XCTAssertNil(missing?.title)
        XCTAssertFalse(missing?.canReadPosition ?? true)

        XCTAssertNil(SpotifyMediaSource.parse("garbage", identity: "spotify"))
    }
}
