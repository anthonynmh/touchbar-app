# Snappy Nest Engineering Notes

This file records hardware-specific findings and development decisions that
future agents must preserve. Add concise, dated entries when a change reveals
new behavior that is not obvious from the source.

`CLAUDE.md` imports this file (`@AGENTS.md`) so Claude Code sessions read the
same notes. Keep all content here; do not duplicate it in `CLAUDE.md`.

## Required verification environment

- Target hardware is a 13-inch `MacBookPro17,1` with a physical Touch Bar and
  physical Escape key.
- The verified development system is macOS 26.6.2 (Tahoe), build 25G83, on
  Apple Silicon.
- Touch Bar behavior must be verified from a real `.app` bundle. A plain Swift
  executable does not establish the activation and responder chain required by
  the public `NSTouchBar` path.
- Do not treat successful compilation or the enlarged preview as hardware
  verification. Use the probes under `Install/run-probe.sh` and record measured
  geometry or readback values.

## Touch Bar presentation findings

- The physical panel measures 1085 x 30 points at 2x backing scale
  (2170 x 60 pixels).
- The persistent private system-modal presentation currently receives a stable,
  visibly unclipped 1004 x 30-point custom region. macOS reserves the remaining
  81 points for its modal affordance; do not claim the custom view can reliably
  reclaim those points.
- A Control Strip tray item is only an anchor. Registering the renderer itself
  as that item produces a small item and does not prove full-width presentation.
  The working architecture retains a small tray anchor plus a separate
  full-width `NSTouchBar`, presented with the runtime-checked placement-aware
  system-modal selector.
- Keep the modal Touch Bar, tray item, custom item, and renderer alive for the
  complete presentation lifetime. Dismiss the modal bar before removing the
  tray item or Control Strip presence.
- Presentation is successful only after the renderer reaches a Touch Bar window
  with stable non-zero visible bounds. Selector or attachment failure must fall
  back to the app-frontmost public presenter.
- Custom Touch Bar views receive finger input through gesture recognizers whose
  `allowedTouchTypes` includes `.direct`. Mouse-oriented defaults alone can make
  a correctly rendered control appear non-interactive.
- Scene geometry must be recomputed from the measured attached width. Keep
  celestial sprites inside the middle region so they cannot overlap the battery
  health bar or the controls.

## Rendering findings

- A `CGImage` assigned to `CALayer.contents` is displayed as an ordinary
  picture (first row at the top) even though the renderer view is flipped.
  Draw sprites in a y-down context (`PetSprites.render`) so cell coordinates
  match the scene's flipped coordinates; the original placeholder pet drew in
  a bottom-origin context and therefore appeared upside down.
- `CALayer.render(in:)` on the flipped renderer applies the flip, so an
  offscreen capture must invert its context (see `SceneSnapshotTests`).
- The 30-point strip fits a 24-point pet cell with the feet on
  `middle.maxY - 4`; the four rows above the head hold accents. Keep every
  detail at 1 point (2 px) or larger.
- The sky image is regenerated only when the minute changes
  (`SkyPainter.Key`); everything else is a cached per-state glyph, so a frame
  costs only layer `contents` swaps.
- Day and night follow real sunrise/sunset, not the clock. `WorldTime`
  carries a `SolarSchedule` (sunrise/sunset in minutes of the local day);
  `isDaytime`, `dayProgress`, `nightProgress`, `daylight`, `twilight` and
  the `SkyPainter` colour keyframes are all expressed relative to it. The
  app resolves the schedule with `SolarScheduleCache`: the system zone's
  identifier (`TimeZone.current.identifier`, e.g. `Asia/Singapore`) is
  looked up in `/usr/share/zoneinfo/zone.tab` for the zone's reference-city
  coordinates and fed to a NOAA sunrise/sunset formula, cached per
  (zone, day). No CoreLocation, no permissions, no radios; the cost is one
  file read per zone and one trig pass per day. Fixed-offset zones
  (`GMT+8`, `UTC`) and polar day/night fall back to `.stylized`
  (06:00 / 18:00), which is also the default for every `WorldTime` so
  tests and snapshots stay deterministic. Accuracy is that of the zone's
  reference city: exact for Singapore (06:55 / 19:02 on 2026-09-20 versus
  the old 06:00 / 18:00), tens of minutes off at the far edges of wide
  zones such as `America/Chicago`. `PetScheduler`'s hour-of-day action
  weights deliberately stay on the wall clock.
- Paging is a camera: the world and controls containers are full-width
  `CALayer`s whose `position.x` follows an `NSPanGestureRecognizer`
  (`allowedTouchTypes = .direct`) and snaps with a `CABasicAnimation`. The
  same recognizer scrubs a slider when the drag starts on a live track, so
  hit-testing decides slider-vs-pan at `.began`, never mid-gesture. Verified
  on hardware 2026-09-18: the scene follows the finger, snaps cleanly, and
  the sliders still scrub.
- Users found a tap-to-toggle tab and a translucent control panel broke the
  immersion; the controls must sit in the same sky and terrain as the pet.
- The pet layer is a child of the root layer, above the three page
  containers, and `PetState.position` is always in strip coordinates. That
  is what lets the pet stay on screen while a page slides and then travel
  to its spot on the new page (`PetController.enter(_:now:)`); do not move
  it into a page container.
- A page change is a teleport, not a walk: `PetController.enter` runs a
  phase machine (`suitDown` if hatted → `teleportOut` at the old spot →
  position jump → `teleportIn` → the page's arrival action). The pet is
  frozen and ignores taps/scrubs for the whole transition
  (`transitionUntil`); a second `enter` mid-transition only retargets the
  queued page. The poof clips are pose-driven (`PetSprites.teleportPose`);
  `teleportIn` frame 3 must stay pixel-identical to `idle` frame 0 so the
  landing does not pop.
- Playback seeking is displayed through the pet only: after a scrub or trail
  tap the controller holds the pet at the target (`PetController.seekHold`)
  until the source's readback catches up. The time labels always come from
  the media snapshot, never from the pending seek.
- The playback page's left third (`LayoutEngine.titleBannerFraction`) is a
  hanging wooden sign (`TitleBannerGlyph`) carrying `MediaSnapshot.title`
  in a `CATextLayer`; the trail is what remains (≈ 425 pt at 1004). Short
  titles are centred, long ones start at the left and end in an ellipsis;
  the string is swapped only when it changes. The sign shows a title only
  while the snapshot is playing or paused.
- The pet body is decoupled from its behaviour: `PetSpecies` is a value on
  `PetState`, `PetSprites.pose(action:frame:)` is the one shared
  action→pose mapping, and a `PetSpeciesDrawer` (one file per species under
  `Renderer/Species/`) turns a pose into pixels. A drawer must be a pure
  function of the pose so `teleportIn` frame 3 equals `idle` frame 0 for
  every species (`SpriteRenderTests` checks all of them). Adding a pet is
  one enum case plus one drawer file. `PetController.setSpecies` reuses the
  teleport transition so the old body poofs out and the new one poofs in.
- The sprite bitmap's colour management shifts `Palette.cream` by a few
  values (0xFBE7C0 → 0xFCEBCB); pixel probes in tests must use a tolerance.

## Volume control findings

- Brightness and volume share the same renderer gesture routing; brightness
  working while volume fails points to the volume provider, not Touch Bar hit
  testing.
- The original Core Audio implementation checked only the main scalar and then
  element 1. A channel fallback must update the complete preferred stereo pair,
  not only the left channel.
- Core Audio volume state and mute state are separate. A successful scalar write
  can remain inaudible if the output is muted; moving above zero must clear a
  writable output mute control and verify the resulting state.
- The attempted synchronous `/usr/bin/osascript` fallback is not a valid runtime
  path. On the verified macOS 26 system, its `get volume settings` and
  `set volume ...` source fails to compile, and spawning a process for every pan
  event would block high-frequency Touch Bar interaction even where it parses.
- Never update the displayed volume optimistically. Check every Core Audio
  status and read the effective value back before notifying subscribers.
- Fixed-volume outputs such as some HDMI and digital passthrough devices must be
  reported as unavailable rather than pretending a write succeeded.

## Media control findings

- AppleScript `tell application "Spotify"` launches Spotify whenever an Apple
  event is delivered to a process that is absent or tearing down. Checking
  `System Events` process names inside the script is a race: during quit the
  process is still listed, the event is sent, and Spotify relaunches ("pops
  back"). An app-side `is running` check has the same window.
- Spotify posts `com.spotify.client.PlaybackStateChanged` with
  `Player State = "Stopped"` while quitting. Treat that notification as a
  quit signal: publish `.stopped` from the payload and send no Apple event
  for a quiesce window (`SpotifyMediaSource.quiesceInterval`), and gate every
  script on `NSRunningApplication` (running and not `isTerminated`). Poll only
  between `NSWorkspace` launch/terminate notifications.
- The pet must never launch a media app. Spotify play/pause is a no-op when
  Spotify is not running, and `MRMediaRemoteSendCommand` is only sent when a
  now-playing client exists; otherwise mediaremoted launches the default media
  app, as the F8 key does.
- `MRMediaRemoteGetNowPlayingInfo`, Core Audio, and DisplayServices reads are
  passive and cannot launch other applications.
- Since macOS 15.4 mediaremoted answers `MRMediaRemoteGetNowPlayingInfo` only
  for Apple-signed processes; a third-party app (signed or not — Developer ID
  does not carry the private entitlement) always receives an empty
  dictionary. Measured 2026-09-19 with YouTube playing in Firefox: Probe 05b
  (in-process) `none`, Probe 05c (same call inside `/usr/bin/perl`) `ok`
  with title, elapsed, duration and rate. The MediaRemote calls therefore
  live in `libSnappyMediaRemoteHost.dylib` (`Sources/SnappyMediaRemoteHost`),
  which `MediaRemoteSource` loads into perl via `DynaLoader`
  (`PerlMediaRemoteHost`). The child streams one JSON line per change on
  stdout, takes `toggle|next|previous|seek <s>|get|quit` on stdin, applies
  the same no-client gate before any command, and exits when stdin closes.
  The dylib ships in `Contents/Frameworks` (`wrap-as-app.sh` 5th argument);
  without it or perl the source stays `.unknown` and logs why.
- `MediaRemoteSource` is not browser-specific: it mirrors whatever
  mediaremoted currently calls the now-playing client, and Spotify becomes
  that client the moment it launches, even paused. The perl host therefore
  emits the client's bundle id (`MRMediaRemoteGetNowPlayingApplicationPID`,
  a passive read) as `bundle`, every snapshot carries `sourceApp`, and
  `MediaArbiter` decides the auto source: a MediaRemote snapshot tagged with
  Spotify's bundle is a duplicate and ignored, the playing source wins, and
  ties keep the previous choice instead of defaulting to Spotify. Probe 05
  `--watch` (05d) streams the host so the bundle can be observed while
  Spotify launches. Not yet measured on hardware whether mediaremoted keeps
  reporting Firefox after Spotify registers; if it does not, the page can
  only show Spotify because nothing else is readable.
- Seek and skip use the same gates: Spotify `set player position` /
  `next track` / `previous track` only pass `shouldScript()`; MediaRemote
  `MRMediaRemoteSetElapsedTime` and commands 4/5 (next/previous) are only
  sent while a now-playing client is registered. Browser players may ignore
  `SetElapsedTime`; the 1 Hz readback is the truth (not yet measured on
  hardware per player).

## Development log

- 2026-09-18 — Replaced the tray-item-only presenter with a retained tray
  anchor and separate system-modal bar (`e552f0f`, `0c9968c`). Hardware probing
  established 1085-point physical width and 1004-point usable modal width
  (`809549d`, `42e61dd`).
- 2026-09-18 — Enabled direct Touch Bar gesture input (`64467f3`) and constrained
  celestial rendering away from the left health bar (`c306af8`).
- 2026-09-18 — Added virtual-main and AppleScript volume fallbacks (`bdb849b`,
  `f49acb9`), but hardware use showed the slider still did not control audible
  volume. Subsequent diagnosis found incomplete channel handling, no Core Audio
  mute integration, optimistic writes, and an AppleScript fallback that does not
  compile on the target system. Treat these commits as investigation, not a
  verified fix.
- 2026-09-18 — Replaced the failed volume path with an injectable Core Audio
  bridge and transactional provider (`a6af578`). The provider prefers a writable
  virtual-main control, otherwise writes the complete preferred stereo pair,
  clears every relevant writable mute control above zero, verifies readback, and
  rolls back partial failures. Thirteen isolated provider tests pass. Revised
  Probe 04 passed on hardware using device 97 and `virtual-main`: it changed
  `0.0253` to `0.0753`, confirmed volume/mute, and restored the original state
  with all statuses equal to `noErr`.
- 2026-09-18 — Hardened cleanup, private app/probe staging, and atomic install
  replacement. Probes 03/04 are now read-only by default; hardware writes require
  `--write`, and Probe 04 requires `--allow-unmute` before exercising mute.
  Brightness and volume providers verify every write and rollback readback, and
  become unavailable after an incomplete rollback rather than reporting success.
- 2026-09-18 — Fixed Spotify relaunching on quit while the app ran. Every
  Spotify Apple event now passes one Swift-side gate (installed, running, not
  terminated, outside the quit quiesce window), polling runs only while Spotify
  is running, the compiled script is cached and serialized, and play/pause
  never launches Spotify or (via MediaRemote) the default media app. The bridge
  is injectable and nine isolated `SpotifyMediaSourceTests` cover the policy.
  Probe 05 uses the same guards.
- 2026-09-18 — Replaced the placeholder art and the 24-hour panorama on
  `feat/pet-scene-polish`: procedural 24-point cat-like pet with per-action
  expressions, free-roam movement, tap reactions and walk-to-tap; live sky
  keyed to the clock with stars, hills, and grass; sun/moon rise at the left
  and set at the right of the middle region; tap-to-reveal clock; battery
  glyph with percentage; filled sliders with icons. Progress-follow remains the
  top-priority pet mode. Snapshot tests (`SNAPPY_SNAPSHOT_DIR`) render review
  PNGs. Verified on hardware: pet, taps, clock reveal, sliders, battery.
- 2026-09-18 — Replaced the fixed left/right UI columns with a two-page camera
  (world ↔ controls) panned by dragging the scene; a first tab-toggle version
  was rejected as "collapsible", and a translucent panel behind the controls
  was rejected for breaking immersion. The final controls page is a compact
  centered cluster over continuous terrain. Verified on hardware.
- 2026-09-18 — Added the playback page on `feat/playback-scene`: three pages
  (playback ← world → controls), the pet drawn above the pages so it follows
  the camera, `PetController.Mode` per page (roam / playback / workshop),
  1-tap walk / 2-tap sprint, trail scrubbing and signposts for seek/skip,
  hard-hat `suitUp`/`tinker`/`suitDown` clips, and seek/skip on both media
  sources behind the existing launch gates. Play/pause moved off the
  controls page. 130 tests. Hardware verification pending.
- 2026-09-19 — `feat/teleport-and-mediaremote-host`: page changes teleport
  the pet (poof out, poof in at the playhead / workshop / a seeded roam spot,
  then the hat clip on the controls page). Fixed YouTube-in-Firefox tracking:
  MediaRemote is now read and commanded from a perl-hosted dylib because
  macOS 15.4+ ignores unentitled callers (Probe 05b/05c pair recorded above).
  Also fixed `run-probe.sh` aborting under bash 3.2 `set -u` when no flags
  are given. 144 tests. Hardware verification pending.
- 2026-09-19 — `feat/title-banner-and-pet-species`: fixed auto media
  selection following Spotify after it launched while Firefox played
  (`MediaArbiter`, bundle-tagged snapshots, Probe 05d). Added the track
  title on a hanging sign over the left third of the playback page. Split
  `PetSprites` into a shared pose model plus per-species drawers with the
  cat extracted byte-identically, and added three species — Mecha, Cactus,
  Eldritch Eye — chosen from a 🐾 → Pet submenu and persisted with the
  media source choice. 157 tests (154 + 3 snapshot writers). Hardware
  verification pending.
- 2026-09-20 — `feat/solar-schedule`: the sun/moon, sky and terrain now
  follow real sunrise/sunset derived from the system time zone (zone.tab
  reference coordinates + NOAA formula, cached per day) with the stylized
  06:00 / 18:00 day as the default and fallback. The app logs
  `[SnappyNest] solar tz=… coords=… sunrise=… sunset=…` at launch for
  readback. 184 tests (181 + 3 snapshot writers). Hardware verification pending.
