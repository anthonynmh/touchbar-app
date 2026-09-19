import Foundation

/// Decides which media source the playback page follows when the user has
/// not pinned one ("auto").
///
/// The MediaRemote source is not browser-specific: it mirrors whatever
/// mediaremoted currently calls the now-playing client, and Spotify becomes
/// that client the moment it launches, even paused. Without care both
/// sources then describe Spotify and a paused Spotify wins over a browser
/// that is still playing. The rules here are deliberately simple and
/// order-dependent so they can be read as a policy:
///
/// 1. A MediaRemote snapshot tagged with Spotify's bundle id is a duplicate
///    of the Spotify source and is ignored.
/// 2. Exactly one source playing → that one.
/// 3. Both playing, or both paused → keep the previous choice while it is
///    still live; otherwise the one whose position was reported most
///    recently.
/// 4. One paused, nothing playing → the paused one.
/// 5. Nothing live → `.none`.
public enum MediaArbiter {
    public enum Choice: Equatable { case spotify, remote, none }

    public static func choose(spotify: MediaSnapshot, remote: MediaSnapshot, previous: Choice?) -> Choice {
        let remote = remote.sourceApp == SpotifyMediaSource.bundleID ? MediaSnapshot.unknown : remote
        let s = spotify.state, r = remote.state

        if s == .playing && r != .playing { return .spotify }
        if r == .playing && s != .playing { return .remote }

        let sLive = s == .playing || s == .paused
        let rLive = r == .playing || r == .paused
        switch (sLive, rLive) {
        case (true, true):
            if previous == .spotify || previous == .remote { return previous! }
            let sAt = spotify.elapsedAt ?? .distantPast
            let rAt = remote.elapsedAt ?? .distantPast
            return rAt > sAt ? .remote : .spotify
        case (true, false):  return .spotify
        case (false, true):  return .remote
        case (false, false): return .none
        }
    }
}
