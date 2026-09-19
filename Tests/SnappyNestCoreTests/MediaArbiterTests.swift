import XCTest
@testable import SnappyNestCore

/// Auto-mode source selection. The regression that motivated this: YouTube
/// playing in Firefox, Spotify launched (paused) and mediaremoted switched
/// its now-playing client to Spotify, so both sources described Spotify and
/// the playback page stopped tracking Firefox.
final class MediaArbiterTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func spotify(_ state: MediaSnapshot.State, at: TimeInterval = 0) -> MediaSnapshot {
        MediaSnapshot(identity: "spotify", state: state, elapsed: 10, duration: 200,
                      elapsedAt: t0.addingTimeInterval(at), sourceApp: SpotifyMediaSource.bundleID,
                      canPlayPause: true, canReadPosition: true, canReadDuration: true)
    }

    private func remote(_ state: MediaSnapshot.State, app: String? = "org.mozilla.firefox", at: TimeInterval = 0) -> MediaSnapshot {
        MediaSnapshot(identity: "browser", state: state, elapsed: 10, duration: 200,
                      elapsedAt: t0.addingTimeInterval(at), sourceApp: app,
                      canPlayPause: true, canReadPosition: true, canReadDuration: true)
    }

    func testThePlayingSourceWinsOverAPausedOne() {
        XCTAssertEqual(MediaArbiter.choose(spotify: spotify(.paused), remote: remote(.playing), previous: .spotify), .remote)
        XCTAssertEqual(MediaArbiter.choose(spotify: spotify(.playing), remote: remote(.paused), previous: .remote), .spotify)
    }

    func testARemoteSnapshotThatIsReallySpotifyIsIgnored() {
        // mediaremoted now reports Spotify; the Spotify source is the truth.
        let mirrored = remote(.paused, app: SpotifyMediaSource.bundleID)
        XCTAssertEqual(MediaArbiter.choose(spotify: spotify(.paused), remote: mirrored, previous: .remote), .spotify)
        XCTAssertEqual(MediaArbiter.choose(spotify: spotify(.stopped), remote: mirrored, previous: .remote), .none,
                       "a mirrored Spotify never counts as a browser")
        XCTAssertEqual(MediaArbiter.choose(spotify: spotify(.paused), remote: remote(.playing, app: SpotifyMediaSource.bundleID), previous: nil), .spotify)
    }

    func testTiesKeepThePreviousChoice() {
        XCTAssertEqual(MediaArbiter.choose(spotify: spotify(.paused), remote: remote(.paused), previous: .remote), .remote)
        XCTAssertEqual(MediaArbiter.choose(spotify: spotify(.paused), remote: remote(.paused), previous: .spotify), .spotify)
        XCTAssertEqual(MediaArbiter.choose(spotify: spotify(.playing), remote: remote(.playing), previous: .remote), .remote)
    }

    func testTiesWithoutAPreviousChoicePreferTheMostRecentReport() {
        XCTAssertEqual(MediaArbiter.choose(spotify: spotify(.paused, at: 0), remote: remote(.paused, at: 5), previous: nil), .remote)
        XCTAssertEqual(MediaArbiter.choose(spotify: spotify(.paused, at: 5), remote: remote(.paused, at: 0), previous: .none), .spotify)
    }

    func testOnlyLiveSourcesAreChosen() {
        XCTAssertEqual(MediaArbiter.choose(spotify: spotify(.stopped), remote: remote(.paused), previous: .spotify), .remote)
        XCTAssertEqual(MediaArbiter.choose(spotify: spotify(.paused), remote: .unknown, previous: .remote), .spotify)
        XCTAssertEqual(MediaArbiter.choose(spotify: spotify(.stopped), remote: .unknown, previous: .remote), .none)
    }

    func testSpotifyLaunchWhileFirefoxPlaysDoesNotStealThePage() {
        // Before: Firefox alone.
        var choice = MediaArbiter.choose(spotify: spotify(.stopped), remote: remote(.playing), previous: nil)
        XCTAssertEqual(choice, .remote)
        // Spotify launches paused and mediaremoted still reports Firefox.
        choice = MediaArbiter.choose(spotify: spotify(.paused), remote: remote(.playing), previous: choice)
        XCTAssertEqual(choice, .remote)
        // mediaremoted flips its client to Spotify: the mirrored snapshot is
        // deduplicated and nothing else is readable, so Spotify shows only
        // because Firefox is no longer reported at all.
        choice = MediaArbiter.choose(spotify: spotify(.paused), remote: remote(.paused, app: SpotifyMediaSource.bundleID), previous: choice)
        XCTAssertEqual(choice, .spotify)
        // Firefox is reported again (paused, then playing): the page returns to it.
        choice = MediaArbiter.choose(spotify: spotify(.paused), remote: remote(.playing), previous: choice)
        XCTAssertEqual(choice, .remote)
    }
}
