import XCTest
@testable import SnappyNestCore

final class MediaSnapshotTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    func testUnknownDoesNotFollowProgress() {
        XCTAssertFalse(MediaSnapshot.unknown.canFollowProgress)
    }

    func testLiveStreamMissingDurationCannotFollow() {
        let s = MediaSnapshot(identity: "browser", state: .playing, elapsed: 10, duration: nil, elapsedAt: base, rate: 1, canPlayPause: true, canReadPosition: true, canReadDuration: false)
        XCTAssertFalse(s.canFollowProgress)
        XCTAssertNil(s.progressFraction(at: base.addingTimeInterval(5)))
    }

    func testPlayingInterpolatesForward() {
        let s = MediaSnapshot(identity: "spotify", state: .playing, elapsed: 30, duration: 300, elapsedAt: base, rate: 1, canPlayPause: true, canReadPosition: true, canReadDuration: true)
        XCTAssertEqual(s.positionAt(base) ?? -1, 30, accuracy: 1e-6)
        XCTAssertEqual(s.positionAt(base.addingTimeInterval(15)) ?? -1, 45, accuracy: 1e-6)
        XCTAssertEqual(s.progressFraction(at: base.addingTimeInterval(15)) ?? -1, 0.15, accuracy: 1e-6)
    }

    func testPausedDoesNotAdvance() {
        let s = MediaSnapshot(identity: "spotify", state: .paused, elapsed: 60, duration: 300, elapsedAt: base, rate: 1, canPlayPause: true, canReadPosition: true, canReadDuration: true)
        XCTAssertEqual(s.positionAt(base.addingTimeInterval(50)) ?? -1, 60, accuracy: 1e-6)
        XCTAssertEqual(s.progressFraction(at: base.addingTimeInterval(50)) ?? -1, 0.2, accuracy: 1e-6)
    }

    func testPositionClampsAtEnd() {
        let s = MediaSnapshot(identity: "spotify", state: .playing, elapsed: 290, duration: 300, elapsedAt: base, rate: 1, canPlayPause: true, canReadPosition: true, canReadDuration: true)
        XCTAssertEqual(s.positionAt(base.addingTimeInterval(30)) ?? -1, 300, accuracy: 1e-6)
    }

    func testDoubleSpeedInterpolation() {
        let s = MediaSnapshot(identity: "spotify", state: .playing, elapsed: 0, duration: 100, elapsedAt: base, rate: 2, canPlayPause: true, canReadPosition: true, canReadDuration: true)
        XCTAssertEqual(s.positionAt(base.addingTimeInterval(10)) ?? -1, 20, accuracy: 1e-6)
    }

    func testSeekResync() {
        let a = MediaSnapshot(identity: "spotify", state: .playing, elapsed: 10, duration: 100, elapsedAt: base, rate: 1, canPlayPause: true, canReadPosition: true, canReadDuration: true)
        // 20s later a fresh snapshot arrives with position=80 (user seeked forward).
        let b = MediaSnapshot(identity: "spotify", state: .playing, elapsed: 80, duration: 100, elapsedAt: base.addingTimeInterval(20), rate: 1, canPlayPause: true, canReadPosition: true, canReadDuration: true)
        XCTAssertEqual(a.positionAt(base.addingTimeInterval(20)) ?? -1, 30, accuracy: 1e-6)
        XCTAssertEqual(b.positionAt(base.addingTimeInterval(20)) ?? -1, 80, accuracy: 1e-6)
    }
}
