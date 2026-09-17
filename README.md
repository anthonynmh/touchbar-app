# Snappy Nest — a native Touch Bar world for the M1 13" MacBook Pro

A single-screen pixel-art world that lives on the Touch Bar: a fixed 24-hour panorama
(midnight → noon → next midnight) with a sun/moon showing the current local time, an
orange fantasy pet roaming the middle third, a segmented battery meter on the left,
and directly-draggable brightness + volume + contextual play/pause on the right.

Local-only. No cloud, no telemetry, no microphone, no network. Works fully offline.

The pet doubles as a playback progress indicator for Spotify and, when the browser
publishes Now Playing info, for YouTube in Firefox.

## Compatibility snapshot

Populated from the initial target-machine validation on 2026-09-17.

| Item | Value |
| --- | --- |
| Hardware | MacBookPro17,1 (M1, 8-core, 8 GB) — 13" MacBook Pro with physical Touch Bar and physical Escape key |
| macOS | 26.6.2 (Tahoe), build 25G83 |
| Xcode | 27.0 (27A266a) |
| Swift | 6.4 (swiftlang-6.4.0.34.1) |
| SDK | macOS 27.0 (`/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk`) |
| Architecture | arm64 |
| Deployment target | macOS 26.0 |
| Touch Bar service | `TouchBarServer` running |

## Probe results

Measured on this Mac on 2026-09-18 (macOS 26.6.2, `MacBookPro17,1`, `TouchBarServer` pid varies).
Re-run any probe with `./Install/run-probe.sh 0N` after building.

- **01 · Touch Bar render (bounds + backing scale):** ✅ ok · Touch Bar window
  is **685.0 × 30.0 pt @ 2.00× backing** (= 1370 × 60 physical px). Custom
  `NSCustomTouchBarItem` + layer-backed `NSView` renders end-to-end.
  `NSTouchBar` responder chain resolves the item ~7 ms after `window.touchBar`
  is assigned to the key window, once the Touch Bar service is warm; cold-start
  is up to ~6 s so the app must wait patiently on first launch. Public API path
  requires a proper `.app` bundle + `open` — plain command-line executables
  don't activate.
- **02 · Persistent presenter (DFRFoundation):** ✅ ok · `dlopen`
  `/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation`
  succeeds, `DFRSetStatus(2)` returns, `DFRElementSetControlStripPresenceForIdentifier`
  returns, `+[NSTouchBarItem addSystemTrayItem:]` accepts the item. Visual
  confirmation that the strip persists across app switches requires the human
  eye — run `./Install/run-probe.sh 02` and Cmd-Tab away for 12 s.
- **03 · Brightness read/write (DisplayServices):** ✅ ok · Read `0.4814`,
  wrote `0.5014` (return `0` = success), restored `0.4814` (return `0`). Uses
  private `DisplayServicesGetBrightness` / `DisplayServicesSetBrightness` from
  `/System/Library/PrivateFrameworks/DisplayServices.framework` — the only
  brightness path that works on Apple Silicon internal panels.
- **04 · Volume read/write (Core Audio):** ✅ ok · Default output device
  master channel is settable. Read `0.0000`, wrote `0.02`, restored `0.0000`
  — both `AudioObjectSetPropertyData` calls returned `noErr` (0). Public API,
  no private symbols.
- **05a · Spotify AppleScript adapter:** ✅ ok · `player state=paused`,
  `player position=150.22 s`, `duration=218.173 s`, `name of current track="Mother"`.
  First run of the bundled app will trigger the Automation permission prompt.
- **05b · Browser MediaRemote adapter (Firefox / YouTube):** ✅ ok · `dlopen`
  `/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote` +
  `dlsym MRMediaRemoteGetNowPlayingInfo` succeed; callback fires within the
  3-second wait. During the probe run no browser tab was actively playing, so
  the returned dictionary was empty — this correctly maps to `.unknown` in
  the runtime adapter. To verify positive-case behavior, start a YouTube video
  in Firefox with `media.hardwaremediakeys.enabled = true` (default) and
  rerun.

## Permissions requested

- **Automation → Spotify.** Required to read `player position` / `duration` / `player state`
  and to send `play` / `pause`. The macOS Automation permission dialog appears the first
  time we ask; deny it and the Spotify adapter reports `.unavailable`.
- No microphone.
- No accessibility.
- No network. The app's sandbox has `com.apple.security.network.client = false`.

## Build steps

Xcode is the primary build path.

```sh
open TouchbarPet.xcodeproj      # then ⌘R the TouchbarPet scheme
```

Command line:

```sh
xcodebuild \
  -project TouchbarPet.xcodeproj \
  -scheme TouchbarPet \
  -configuration Release \
  -destination 'platform=macOS' \
  build
```

## Installation

Local, offline, unsigned build for your own machine:

```sh
./Install/install.sh
```

The script verifies macOS ≥ 26 + arm64, runs `xcodebuild`, copies the resulting
`.app` to `/Applications/TouchbarPet.app`, and prints the escape-hatch shortcut. It
refuses to run as root and never touches `/System` or `/Library`. Launch-at-login
is opt-in from Preferences after first launch — the installer never enables it silently.

To uninstall:

```sh
./Install/uninstall.sh
```

Optional signed `.dmg` build for distribution (requires Developer ID):

```sh
make dmg           # archive + export with Developer ID
make notarize      # requires ASC_API_KEY_ID / ASC_API_KEY_ISSUER_ID / ASC_API_KEY_PATH in env
```

## Asset replacement

All sprites and scenery live under `Assets/Sprites/` and `Assets/Scenery/`. Each atlas
has a sibling `atlas.json`:

```json
{
  "cellSize": [32, 32],
  "anchor":   [16, 30],
  "fps":      { "idle": 4, "walk": 8, "dash": 12 },
  "clips":    { "idle": { "frames": [0,1,2,1], "loop": true }, "...": "..." },
  "placeholder": true
}
```

Swap the PNG + `atlas.json` pair. No Swift code changes. Remove the `placeholder: true`
key when final art ships so the debug badge stops rendering.

## Escape hatch

Three ways to reclaim the default macOS Touch Bar:

1. **Global shortcut:** `⌥⌘\` (configurable in Preferences → General). Toggles the
   overlay off and on without quitting.
2. **Menu bar → Snappy Nest → Hide Touch Bar Overlay.** Same effect as the shortcut.
3. **Menu bar → Snappy Nest → Quit.** Full teardown; the default Control Strip returns
   immediately.

## Private-API risk register

Every private symbol is `dlopen`-loaded through a bridge file. Failure is user-visible
but never fatal: the feature degrades to a documented unavailable state.

| Symbol | Framework | Purpose | Failure behavior |
| --- | --- | --- | --- |
| `DFRSetStatus`, `DFRElementSetControlStripPresenceForIdentifier` | DFRFoundation | Persistent presenter across app switches | Falls back to app-frontmost presenter automatically |
| `DisplayServicesGetBrightness` / `DisplayServicesSetBrightness` | DisplayServices | Built-in display brightness on Apple Silicon | Brightness slot renders `.unavailable` (hatched sun) |
| `MRMediaRemoteGetNowPlayingInfo`, `MRMediaRemoteSendCommand`, `MRMediaRemoteRegister…` | MediaRemote | Browser (Firefox/YouTube) playback tracking | Browser source reports `.unknown`; pet stays in free-roam |

## Preferences

Menu bar → Snappy Nest → Preferences.

- Launch at login (`SMAppService.mainApp`).
- Persistent presentation toggle, with a live capability badge.
- Reduce Motion override.
- Preferred media source: `Spotify` | `Browser` | `Auto` (most-recently-playing).
- Escape-hatch shortcut recorder.
- Debug simulation: fake clock, fake battery + charging, fake playback state, seed input.
- Enlarged preview window (6× nearest-neighbor).

All settings are stored in `~/Library/Preferences/com.local.snappy-nest.plist`.

## Troubleshooting

- **Spotify slider does nothing.** Check System Settings → Privacy & Security →
  Automation and enable Snappy Nest → Spotify. If Spotify isn't installed, the adapter
  reports unavailable and the browser adapter is used instead.
- **YouTube tracking not working.** Firefox must publish MediaSession info. Check
  `about:config` → `media.hardwaremediakeys.enabled = true` (default on recent versions)
  and confirm the tab has an active `<video>` element with the MediaSession API set.
- **Brightness slider is greyed.** `DisplayServicesGetBrightness` returned no value.
  This is the honest `.unavailable` state — no fallback (per design; simulating F1/F2
  key events is out of scope).
- **Volume slider is greyed.** The current output device is fixed-volume (HDMI/S-PDIF
  passthrough). Snappy Nest re-binds automatically when you switch to a settable device.
- **Persistent presentation toggle is disabled.** Startup probe couldn't verify that
  the strip stayed visible under another app. Fall back to app-frontmost mode.

## Non-goals

- No microphone / audio recording.
- No network of any kind.
- No sleep prevention, no SIP disabling, no privileged helpers, no input simulation.
- No astronomical sunrise/sunset — sun/moon uses a fixed stylized 06:00 / 18:00.
- No Music.app adapter in the first release. First-release media sources are Spotify
  and the browser (via MediaRemote).
- No weather, no ChatGPT, no cloud accounts.

## License

MIT. See `LICENSE`.
