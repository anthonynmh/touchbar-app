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
