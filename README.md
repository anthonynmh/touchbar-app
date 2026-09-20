# Snappy Nest — a native Touch Bar world for the M1 13" MacBook Pro

A pixel-art world that lives on the Touch Bar: a live sky that follows the local
time of day (dawn glow, blue noon, starry night) with the sun and moon crossing the
strip, and an orange cat-like pet that roams, reacts to taps, and walks where you
tap (tap twice to make it sprint). Tap the sun or moon to see the time. The strip
is three scenes side by side and the pet follows you between them: drag the scene
right to reach the **playback** page, where the pet becomes the playhead on a dirt
trail (drag it to seek; wooden signposts skip and play/pause), or drag left to
the **controls** page — brightness, volume and battery in the same landscape —
where the pet puts on a hard hat and tinkers until you leave.

Local-only. No cloud, no telemetry, no microphone, and no network code. Works
fully offline. The current local build is not App-Sandboxed.

On the playback page the pet doubles as a playback progress indicator for Spotify
and, when the browser publishes Now Playing info, for YouTube in Firefox.

## Contents

- [Compatibility snapshot](#compatibility-snapshot)
- [Probe results](#probe-results)
- [What's built](#whats-built)
- [Repository layout](#repository-layout)
- [Permissions requested](#permissions-requested)
- [Build steps](#build-steps)
- [Installation](#installation)
- [Asset replacement](#asset-replacement)
- [Escape hatch](#escape-hatch)
- [Private-API risk register](#private-api-risk-register)
- [Preferences](#preferences)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)
- [Non-goals](#non-goals)
- [License](#license)

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
Re-run any probe with `./Install/run-probe.sh 0N` after building. Probes 03 and
04 are read-only unless `--write` is passed explicitly.

- **01 · Touch Bar render (bounds + backing scale):** ✅ ok · Touch Bar window
  app-control region is **685.0 × 30.0 pt @ 2.00× backing** (= 1370 × 60
  physical px). This is not the end-to-end panel width. Custom
  `NSCustomTouchBarItem` + layer-backed `NSView` renders end-to-end.
  `NSTouchBar` responder chain resolves the item ~7 ms after `window.touchBar`
  is assigned to the key window, once the Touch Bar service is warm; cold-start
  is up to ~6 s so the app must wait patiently on first launch. Public API path
  requires a proper `.app` bundle + `open` — plain command-line executables
  don't activate.
- **02 · Persistent presenter (DFRFoundation + system-modal Touch Bar):** ✅ ok ·
  an end-to-end 1085-point renderer request attached with **1004.0 × 30.0 pt
  visibly unclipped @ 2.00×** (= 2008 × 60 physical px), remained attached
  after switching applications, and cleaned up normally. The physical panel is
  1085 × 30 points (2170 × 60 pixels); macOS 26 reserves the remaining 81
  points for its system-modal affordance, which this private modal path cannot
  reclaim reliably.
  The former green-square result was **insufficient**: it proved only that a
  small Control Strip tray item could be registered, not that a full-width
  renderer was presented. The revised probe registers a retained 🐾 tray anchor,
  presents a separate recognizable bar through the placement-aware system-modal
  selector (`placement: 1` for full width). Its custom view requests the physical
  1085 × 30 size (an unconstrained view settles at only 445 points on this macOS
  build), and the probe reports stable, visibly unclipped geometry and post-Cmd-Tab
  persistence as separate results.
- **03 · Brightness read/write (DisplayServices):** ✅ ok · Read `0.4814`,
  wrote `0.5014` (return `0` = success), restored `0.4814` (return `0`). Uses
  private `DisplayServicesGetBrightness` / `DisplayServicesSetBrightness` from
  `/System/Library/PrivateFrameworks/DisplayServices.framework` — the only
  brightness path that works on Apple Silicon internal panels.
- **04 · Volume read/write (Core Audio):** ✅ ok · On device `97`, the revised
  probe selected the writable virtual-main control, changed `0.0253` to
  `0.0753`, verified the effective value and unmuted state, then restored the
  original volume and mute with every operation returning `noErr` (0). The app
  falls back to the device's complete preferred stereo pair when no writable
  virtual-main or main control exists; it never writes only the left channel.
- **05a · Spotify AppleScript adapter:** ✅ ok · `player state=paused`,
  `player position=150.22 s`, `duration=218.173 s`, `name of current track="Mother"`.
  First run of the bundled app will trigger the Automation permission prompt.
- **05b · Browser MediaRemote adapter, in-process:** ⛔ `none` even with a
  YouTube video playing in Firefox. Since macOS 15.4 mediaremoted only answers
  Apple-signed processes, so this path is kept as the negative control.
- **05c · Browser MediaRemote adapter, perl-hosted (Firefox / YouTube):** ✅ ok ·
  the same call made inside `/usr/bin/perl` (which loads
  `libSnappyMediaRemoteHost.dylib` through `DynaLoader`) returned
  `title`, `elapsed=5.05 s`, `duration=234.4 s`, `rate=1` for the playing
  tab. This is the path the app uses.

## What's built

Current build (`v0.1.0-dev`), verified on this Mac on 2026-09-18:

- ✅ Live sky keyed to the day's real sunrise and sunset: vertical
  zenith→horizon gradient interpolated between keyframes anchored to
  sunrise, noon and sunset, stars that fade with daylight, a warm
  horizon glow at dawn/dusk, hills and grass across the middle region, and
  translucent panels behind the battery and controls (`SkyPainter`, cached per
  minute).
- ✅ Sun rises at the left of the middle region at local sunrise, peaks at
  solar noon, sets at the right at sunset; the moon does the same overnight.
  Sunrise/sunset come from the system time zone's reference city
  (`/usr/share/zoneinfo/zone.tab`) and a NOAA formula — no location
  permission, no network — and fall back to a stylized 06:00 / 18:00 day for
  fixed-offset zones such as `GMT+8`. Tapping either body reveals a
  localized clock for three seconds.
- ✅ Procedural cat-like pet (`PetSprites`, 24-point cell) with a pose and
  expression for every action, real walking/dashing between seeded
  destinations, a happy/surprised reaction when tapped, walk-to-tap on the
  ground and a sprint on a quick second tap. On the world page media is
  ignored; the pet follows playback only on the playback page.
- ✅ Layer-backed `SceneRenderer` at nearest-neighbor filtering,
  measured-bounds pixel-alignment (2× on this Mac).
- ✅ Three-page strip — playback, world, controls — over the same sky and
  continuous terrain. A horizontal drag anywhere that is not a live slider or
  the playback pet pans the camera with the finger; release snaps to the
  nearest page and a flick moves one page. The controls page pans back to the
  world after ten idle seconds (`AppDelegate.controlsIdleTimeout`). The pet
  is drawn above the pages, so it stays on screen while the scenery slides
  and then dashes to its place on the new page.
- ✅ Playback page: a dirt trail the pet walks as the track plays, `m:ss`
  elapsed/duration labels, and wooden signposts for previous / play-pause /
  next. Drag the pet along the trail or tap the trail to seek; Spotify seeks
  and skips via AppleScript behind the same never-launch gate as play/pause,
  the browser via MediaRemote (`MRMediaRemoteSetElapsedTime`; some players
  ignore it, in which case the readback simply steers the pet back).
- ✅ Controls page: the pet dashes in beside the cluster, a hard hat drops onto
  its head (`suitUp`), and it idles with a spanner (`tinker`) until it leaves
  (`suitDown`).
- ✅ Battery glyph with proportional fill (green / amber / red), a drawn charging
  bolt, and a percentage label at the far right of the controls page, fed from
  IOPS.
- ✅ Directly-draggable brightness (`DisplayServices`) and volume (Core Audio),
  including preferred-stereo fallback, mute handling, confirmed readback, and
  rollback after partial write failure. Sliders show a filled track, a large
  knob, and sun/speaker icons whose arcs follow the level; mute shows a slash.
- ✅ Keep-away on the world page: tap the stone nook and the ball rolls out;
  the pet chases it and you tap anywhere on the ground to kick the ball
  toward that side. A rolling ball can't be kicked again until it slows (it
  glows when ready). Survive the 10 s round and the pet gets faster; if it
  reaches the ball it wins and celebrates. A pill above the nook shows the round and timer, and
  the best score persists. Tap the nook again at any time to stop; swiping to
  another page also ends the game.
- ✅ `LayoutEngine.Page` models the pages; `PetController.Mode` (roam,
  playback, workshop) follows the page the camera settled on.
- ✅ Pet state machine (17 actions) with seeded, hour-of-day-weighted
  free-roam scheduler; progress-follow mode on the playback page when
  duration+position are known; **battery is not a scheduler input**
  (enforced by types + test).
- ✅ Spotify AppleScript adapter, MediaRemote adapter for the browser.
- ✅ Persistent Touch Bar presenter with a small retained tray anchor and a
  separate maximum-width system-modal bar. Installation becomes `visible` only
  after the renderer reaches a non-zero Touch Bar window; selector failure or
  attachment timeout automatically selects the app-frontmost fallback.
- ✅ Public fallback activates the accessory app and uses a key-capable hidden
  window to establish the responder chain.
- ✅ Menu bar 🐾, escape hatch (menu command with an `Opt+Cmd+\` key
  equivalent while the app receives menu events), enlarged 6× preview.
- ✅ XCTest coverage for scene behavior, UI/presentation, and isolated
  brightness/Core Audio bridges, including status checks, readback,
  transactional rollback, device availability, rebinding, and cleanup.
- ✅ `install.sh` / `uninstall.sh` / `Makefile` including `dmg` +
  `notarize` opt-in targets.

Deferred / follow-up:

- Full Preferences window with SMAppService launch-at-login, Reduce Motion
  override, escape-hatch shortcut recorder, debug simulation panel.
- Optional PNG sprite atlases. The pet is drawn procedurally by `PetSprites`;
  an atlas loader would replace `PetSprites.image(action:frame:facing:scale:)`
  without touching the renderer or controller.
- Additional media adapters beyond Spotify + browser.

## Repository layout

```
touchbar-pet/
  Package.swift                # SwiftPM: library + app + 5 probe executables
  Sources/
    SnappyNestCore/            # AppKit-free: scene, layout, pet SM, providers
      Scene/     Layout/  Pet/  Support/
      Providers/
        Clock/  Battery/  Brightness/  Volume/  Media/
    SnappyNestUI/              # AppKit: renderer, presenter, preview
      Renderer/  Presenter/  Preview/
    TouchbarPet/               # main app: AppDelegate + main.swift
    Probe01TouchBar/           # Touch Bar bounds + backing scale
    Probe02Presenter/          # DFRFoundation persistent-presenter probe
    Probe03Brightness/         # DisplayServices roundtrip
    Probe04Volume/             # Core Audio roundtrip
    Probe05Media/              # Spotify + MediaRemote adapters (in-process and perl-hosted)
    SnappyMediaRemoteHost/     # dylib loaded into /usr/bin/perl to reach MediaRemote
  Tests/
    SnappyNestCoreTests/       # 100 model/provider XCTest cases
    SnappyNestUITests/         # 30 renderer/presenter/snapshot XCTest cases
  Install/
    install.sh   uninstall.sh   clean.sh   wrap-as-app.sh   run-probe.sh
  Makefile
  README.md   LICENSE
```

## Permissions requested

- **Automation → Spotify.** Required to read `player position` / `duration` / `player state`
  and to send `play` / `pause`. The macOS Automation permission dialog appears the first
  time we ask; deny it and the Spotify adapter reports `.unavailable`.
- No microphone.
- No accessibility.
- No network code. The current locally built app is not App-Sandboxed, so this
  is an implementation property rather than an entitlement-enforced boundary.

## Build steps

This repository is a Swift Package; it does not contain an `.xcodeproj`.

```sh
swift build --product TouchbarPet
swift test
```

You can also open `Package.swift` in Xcode and use the SwiftPM-generated
schemes, but the documented build and installation paths use `swift build`.

## Installation

Local, offline, unsigned build for your own machine:

```sh
./Install/install.sh
```

The script verifies macOS ≥ 26 + arm64, runs `swift build -c release`, wraps the
executable in a private staging directory beside the destination, and atomically
installs it as `/Applications/TouchbarPet.app`. It refuses to run as root, never
touches `/System` or `/Library`, does not launch the app after installation, and
does not enable launch-at-login.

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

Ways to reclaim the default macOS Touch Bar:

1. **Menu bar → Snappy Nest → Hide Touch Bar Overlay.** The menu item has an
   `⌥⌘\` key equivalent, but the app does not register a global hotkey and the
   key equivalent is not guaranteed while another application is active.
2. **Menu bar → Snappy Nest → Quit.** Full teardown; the default Control Strip returns
   immediately.

## Private-API risk register

Private framework symbols are resolved at runtime and private AppKit selectors
are checked before use. Failure is user-visible but never fatal: persistent
presentation degrades to the public app-frontmost path, and a first-launch
diagnostic points to the enlarged preview and Probe 02 if neither path attaches.

| Symbol | Framework | Purpose | Failure behavior |
| --- | --- | --- | --- |
| `DFRElementSetControlStripPresenceForIdentifier` | DFRFoundation | Control Strip anchor presence | Falls back to app-frontmost presenter automatically |
| `addSystemTrayItem:`, `removeSystemTrayItem:`, `presentSystemModalTouchBar:placement:systemTrayItemIdentifier:`, `dismissSystemModalTouchBar:` | AppKit runtime selectors | Retained tray anchor and placement-1 maximum-width system-modal bar | Falls back if any selector is absent; attachment timeout is also treated as failure |
| `DisplayServicesGetBrightness` / `DisplayServicesSetBrightness` | DisplayServices | Built-in display brightness on Apple Silicon | Brightness slot renders `.unavailable` (hatched sun) |
| `MRMediaRemoteGetNowPlayingInfo`, `MRMediaRemoteSendCommand`, `MRMediaRemoteSetElapsedTime` (called inside a `/usr/bin/perl` child via `libSnappyMediaRemoteHost.dylib`, because macOS 15.4+ answers only Apple-signed processes) | MediaRemote | Browser (Firefox/YouTube) playback tracking, play/pause, skip, seek | Browser source reports `.unknown`; pet stays in free-roam |

## Preferences

The current release exposes preferences from the 🐾 menu bar item — a
full Preferences window is a follow-up.

- **Hide / Show Touch Bar Overlay** — the escape hatch (`Opt+Cmd+\`).
- **Enlarged Preview…** — opens the 6× nearest-neighbor preview window.
- **Media source** submenu — `Auto` (most-recently-playing), `Spotify`, `Browser`.
- **Quit Snappy Nest** — full teardown; the default Control Strip returns.

Follow-ups tracked for the next release: launch-at-login via `SMAppService`,
Reduce Motion override, escape-hatch shortcut recorder, and a debug
simulation panel for clock / battery / playback. All state will persist to
`~/Library/Preferences/com.local.snappy-nest.plist`; no cloud sync.

## Testing

- `swift test` runs 130 tests: 100 core/provider tests and 30 UI/presenter tests
  (three snapshot tests are skipped unless `SNAPPY_SNAPSHOT_DIR` is set).
- `SNAPPY_SNAPSHOT_DIR=/some/dir swift test --filter SceneSnapshotTests` writes
  PNGs of the pet clip sheet, the battery/control glyphs, and the full strip at
  several hours, for reviewing artwork without hardware.
- `./Install/run-probe.sh 0N` (N = 1…5) rebuilds and runs a specific probe.
- `./Install/run-probe.sh 03` and `04` perform read-only diagnostics by default.
  Add `--write` for a small verified round trip with mute preserved. Probe 04
  changes mute only with the additional explicit `--allow-unmute` flag. Every
  write mode verifies restoration and exits nonzero if readback differs.
- Battery-independence acceptance test in `PetControllerBatteryIndependenceTests`:
  600 ticks × 3 battery states (dying / full / charging) produce a
  byte-identical `PetAction` log for a fixed seed + clock + media.
- DST safety: `WorldTime` is computed from `Calendar.dateComponents(...)`
  rather than seconds-since-epoch, so a repeated wall-clock hour (fall-back)
  genuinely repeats its panorama position and a skipped hour (spring-forward)
  is genuinely skipped.
- Renderer smoke test: launch the app, open **Enlarged Preview…**, verify
  the pet, celestial body, and controls render at 6×. On hardware, tap the pet
  (reaction), tap the ground (walk-to), tap the sun/moon (clock), and swipe
  left/right to pan between the world and the controls.

## Troubleshooting

- **Spotify slider does nothing.** Check System Settings → Privacy & Security →
  Automation and enable Snappy Nest → Spotify. If Spotify isn't installed, the adapter
  reports unavailable and the browser adapter is used instead.
- **YouTube tracking not working.** The app reads Now Playing through a
  `/usr/bin/perl` child that loads `Contents/Frameworks/libSnappyMediaRemoteHost.dylib`
  (macOS 15.4+ refuses the call from third-party processes). Check the log for
  `mediaremote host unavailable` / `mediaremote host exited`, confirm the dylib is in the
  bundle and perl exists, then run `./Install/run-probe.sh 05` with the video playing:
  05c must report `ok`. Firefox must also publish MediaSession info:
  `about:config` → `media.hardwaremediakeys.enabled = true` (default).
- **Brightness slider is greyed.** `DisplayServicesGetBrightness` returned no value.
  This is the honest `.unavailable` state — no fallback (per design; simulating F1/F2
  key events is out of scope).
- **Volume slider is greyed.** The current output device is absent or exposes no
  writable virtual-main, main, or complete stereo volume pair (common with
  HDMI/S-PDIF passthrough). Snappy Nest re-binds automatically when the default
  output changes. Run `./Install/run-probe.sh 04` to see the selected strategy,
  channels, mute controls, and current readback without changing them. Use
  `./Install/run-probe.sh 04 --write` only when a verified round trip is wanted.
- **Menu bar says “App-frontmost.”** The private persistent path was unavailable
  or failed to attach, so Snappy Nest activated its public fallback. That bar is
  expected only while Snappy Nest is frontmost.
- **Menu bar says “Not visible.”** Neither presenter attached. Open **Enlarged
  Preview…** from the 🐾 menu, then run `./Install/run-probe.sh 02` and inspect
  the `attachment=` and `persistence=` lines.

## Non-goals

- No microphone / audio recording.
- No network code (the current app is not App-Sandboxed).
- No sleep prevention, no SIP disabling, no privileged helpers, no input simulation.
- No location services — sunrise/sunset are computed for the time zone's
  reference city, so they are only as accurate as your distance from it
  (exact for small zones like Singapore, tens of minutes off at the edges of
  wide zones like `America/Chicago`).
- No Music.app adapter in the first release. First-release media sources are Spotify
  and the browser (via MediaRemote).
- No weather, no ChatGPT, no cloud accounts.

## License

MIT. See `LICENSE`.
