# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0-beta1] - 2026-10-01

### Added

- Initial v1 for WoW: Forever: main-hand, off-hand and ranged swing bars driven
  by the embedded LibClassicSwingTimerAPI, with combat feedback modeled on the
  12.x casting bar - a cast clip tints the fill red, shakes the bar and flashes
  an outer glow; a parry-haste shortening bursts the bar forward - with the
  fill's direction of travel, so the burst inverts in drain mode - a green
  speed streak fired from the fill's edge plus a green halo behind the bar;
  a
  movement-delayed Auto Shot fires the same burst backward in amber - an
  amber streak and halo; a paused
  swing gets a paused
  tint; a queued next-melee ability (Heroic Strike, Cleave, Raptor Strike,
  Maul) tints the main-hand fill the cast bar's yellow. Plus an optional
  main/off-hand delta text and a one-time notice when the game's own swing
  timer bars are also enabled.
- Parry-haste detection: fires in real time at the parry from the library's
  mid-swing UNIT_SWING_TIMER_UPDATE when the embedded library includes the
  parry fix; falls back to early-landing detection (an in-flight STOP followed
  by a same-speed START) for library builds without it. In-flight stops are
  classified after a short grace period into early landings, weapon swaps or
  interrupted swings.
- Bar configuration: three visibility modes mirroring the native timer (While
  swinging / In combat / Always), a Native skin reusing the client's
  ui-swingtimerbar-* atlases (label text-shadow and insets match the game's
  own swing timer) plus a Flat skin with curated color palettes, fill/drain
  direction, bar height (14 px floor, so the fill and text never collapse),
  and label/time text that scales with the bar. Per-character settings via
  the 12.x Settings API.
- Slash commands and test tooling: /4everswingtimer (alias /everswing) with
  unlock, lock, reset and test subcommands - "test interrupt|haste|delay|
  queued" triggers each treatment without waiting for combat and "test
  effects" plays them all - plus a test-bars button and a row of effect
  buttons on the unlock overlay.
- /4everswingtimer trace: verbatim beta-probe capture recording PLAYER_SWING,
  UNIT_COMBAT, the player's spellcasts and the library's
  UNIT_SWING_TIMER_UPDATE with millisecond timestamps into SavedVariables
  (persisted at logout or /reload), with session markers and the client build
  number so captures can be read from disk and attributed to a build. Design
  decisions and the verification checklist: docs/SPEC.md.

### Changed

- Internal cleanup, no behavior change: deduplicated the bar-visibility
  refresh in the event dispatch (Core.lua), extracted the shared center-glow
  overlay and pip sizing in the bars (Bars.lua), and dropped the settings
  proxy helper's unused slider-bounds arguments, which duplicated the bounds
  already passed to CreateSliderOptions (Options.lua).

