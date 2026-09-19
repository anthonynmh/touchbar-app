import XCTest
@testable import SnappyNestCore

/// `MediaRemoteSource` is a client of the perl-hosted MediaRemote child:
/// JSON lines in, commands out, and never a command without a client.
final class MediaRemoteSourceTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func make(_ host: FakeMediaRemoteHost = FakeMediaRemoteHost()) -> (MediaRemoteSource, FakeMediaRemoteHost) {
        let source = MediaRemoteSource(bridge: host, now: { [t0] in t0 })
        return (source, host)
    }

    func testStartsTheHostAndBeginsUnknown() {
        let (source, host) = make()
        XCTAssertEqual(host.startCount, 1)
        XCTAssertTrue(source.isHostRunning)
        XCTAssertEqual(source.snapshot.state, .unknown)
    }

    func testPlayingLineMapsToASeekableSnapshot() {
        let (source, host) = make()
        var received: [MediaSnapshot] = []
        source.subscribe { received.append($0) }
        host.emit(#"{"bundle":"org.mozilla.firefox","duration":226.5,"elapsed":83.25,"rate":1,"timestamp":1700000000,"title":"Song"}"#)
        let s = source.snapshot
        XCTAssertEqual(s.identity, "browser")
        XCTAssertEqual(s.sourceApp, "org.mozilla.firefox")
        XCTAssertEqual(s.state, .playing)
        XCTAssertEqual(s.elapsed, 83.25)
        XCTAssertEqual(s.duration, 226.5)
        XCTAssertEqual(s.title, "Song")
        XCTAssertEqual(s.elapsedAt, t0)
        XCTAssertTrue(s.canSeek)
        XCTAssertTrue(s.canSkip)
        XCTAssertTrue(s.canReadPosition)
        XCTAssertEqual(received.count, 2, "initial unknown, then the playing snapshot")
    }

    func testZeroRateIsPausedAndEmptyObjectIsUnknown() {
        let (source, host) = make()
        host.emit(#"{"duration":100,"elapsed":10,"rate":0,"timestamp":1700000000}"#)
        XCTAssertEqual(source.snapshot.state, .paused)
        XCTAssertEqual(source.snapshot.rate, 1, "a paused snapshot still projects at 1x once it resumes")
        host.emit("{}")
        XCTAssertEqual(source.snapshot.state, .unknown)
    }

    func testGarbageLinesAreIgnored() {
        let (source, host) = make()
        host.emit(#"{"duration":100,"elapsed":10,"rate":1,"timestamp":1700000000}"#)
        host.emit("not json")
        host.emit("")
        XCTAssertEqual(source.snapshot.state, .playing)
    }

    func testNoCommandWithoutANowPlayingClient() {
        let (source, host) = make()
        source.togglePlayPause()
        source.nextTrack()
        source.previousTrack()
        source.seek(to: 10)
        XCTAssertEqual(host.sent, [], "without a client mediaremoted would launch the default media app")

        host.emit(#"{"duration":100,"elapsed":10,"rate":1,"timestamp":1700000000}"#)
        source.togglePlayPause()
        source.nextTrack()
        source.previousTrack()
        XCTAssertEqual(host.sent, ["toggle", "next", "previous"])
    }

    func testSeekIsClampedToTheTrack() {
        let (source, host) = make()
        host.emit(#"{"duration":100,"elapsed":10,"rate":1,"timestamp":1700000000}"#)
        source.seek(to: 250)
        source.seek(to: -5)
        source.seek(to: 42.5)
        XCTAssertEqual(host.sent, ["seek 100.000", "seek 0.000", "seek 42.500"])
    }

    func testSeekNeedsAKnownPositionAndDuration() {
        let (source, host) = make()
        host.emit(#"{"rate":1,"timestamp":1700000000,"title":"Live"}"#)
        XCTAssertFalse(source.snapshot.canSeek)
        source.seek(to: 10)
        XCTAssertEqual(host.sent, [])
    }

    func testHostCrashDropsToUnknownAndBlocksCommands() {
        let (source, host) = make()
        host.emit(#"{"duration":100,"elapsed":10,"rate":1,"timestamp":1700000000}"#)
        host.crash()
        XCTAssertFalse(source.isHostRunning)
        XCTAssertEqual(source.snapshot.state, .unknown)
        source.togglePlayPause()
        XCTAssertEqual(host.sent, [])
    }

    func testFailedStartIsUnknownAndNotRunning() {
        let host = FakeMediaRemoteHost()
        host.startResult = .failure(MediaRemoteHostError("no perl"))
        let (source, _) = make(host)
        XCTAssertFalse(source.isHostRunning)
        XCTAssertEqual(source.snapshot.state, .unknown)
        XCTAssertEqual(host.startCount, 1)
    }

    func testShutdownStopsTheHost() {
        let (source, host) = make()
        source.shutdown()
        XCTAssertTrue(host.stopped)
        XCTAssertFalse(source.isHostRunning)
    }
}
