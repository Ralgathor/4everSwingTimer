# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- The addon now ships an icon: `Textures/icon.png` (the logo's icon variant),
  referenced from the TOC's new `## IconTexture`, so the addon list and the
  Settings AddOns tab show the project logo instead of a blank tile. The
  logo sources remain in `docs/`, which is not shipped.

### Changed

- Effect test previews (`/4everswingtimer test interrupt|haste|delay|queued`
  and the unlocked overlay's effect buttons) now reproduce the full event
  signature on a fake swing instead of painting the treatment on the bars'
  current state. With no swing in flight the same fake 2.0 s swing as the
  plain test command starts first, scoped to the effect's own hands, and the
  effect lands through the real detection paths: the interrupt restarts the
  swing mid-flight like a cast reset, the haste shortens the melee swings
  like the parry UPDATE (the bar re-anchors at the early landing), the delay
  replays the movement-cancel retry at the ranged swing's own landing - the
  bar completes, cannot fire, pulls back and lands ~0.5 s later - and the
  queued highlight rides a swinging main-hand bar until the swing lands and
  consumes it. On a live combat swing the plain treatment fires, as before -
  test data never rewrites live state. The queued-state poll no longer resets
  the fake preview within 0.2 s - it is held off until the preview clears -
  and `test effects` spaces the four previews one swing apart. Also fixed
  the first effect trigger after a reload: a bar the library leaves active
  with a landed swing at login no longer reads as a live swing, so the
  preview starts its fake swing over the stale state instead of firing the
  plain treatment on it (previously the effect triggers only worked after a
  plain Swing test had overwritten the stale bar).
- The event trace (`/4everswingtimer trace`) now records all seven
  `UNIT_SWING_TIMER_*` callbacks instead of only UPDATE, so a full session's
  library behavior is capturable from the SavedVariables trace file - e.g. a
  START or seeded info at login whose landing never produces a STOP. The
  upstream report for that library issue and the record of its library-side
  resolution (fixed by a parked login seed, riding the library's unreleased
  LibStub MINOR 35) both live in `docs/` (not shipped).

### Fixed

- After a login or `/reload` a bar could sit stuck at its swing's end - the
  tick parked at the fill's edge and the time reading 0.0 - until the next
  real swing. The shipped library build (v2.2.0-beta3, LibStub MINOR 34)
  seeds an "in flight" swing at login that the engine can never complete
  (auto-attack does not survive a reload), so its expiration passes without
  the STOP that parks a bar; the library-side fix rides its unreleased
  MINOR 35 (see docs/upstream-stale-swing-report.md). The addon now
  converges such a bar to the parked state itself once the landing is stale
  - the expiration has been in the past for over 1 s, a grace that outlasts
  the ranged movement retry (~0.5 s, so a moving Auto Shot still fires its
  amber delay burst at the library's re-anchor) and the engine-vs-timer
  race at a natural landing (whose STOP parks the bar long before the
  grace elapses). No interrupt feedback fires on the convergence; the bar
  simply reaches the parked state the missing STOP owed it.
- The parked tick sat at the far left of the bar after a login or `/reload`
  until the first swing. `ApplyAll` applied the parked fill value (full in
  fill mode) but never repositioned the tick afterwards - the last
  `UpdateTickPosition` ran inside `ApplySkin`, before `ApplyLayout` had
  sized the bar (zero width, early return) and before the value change -
  so the tick stayed at its creation-time LEFT-edge anchor instead of the
  fill's edge at the "ready" position. `SwingStop` already paired its
  parked value with a reposition, which is why a normally landed swing
  looked right and only the fresh-login bar was wrong. `ApplyAll` now
  repositions the tick for every bar it re-parks.

## [1.0.0-beta2] - 2026-10-01

### Changed

- Embedded LibClassicSwingTimerAPI bumped from v2.2.0-beta2 to v2.2.0-beta3:
  the library's Forever parry fix (ApplyParryHaste) is now in the shipped build,
  so the real-time parry-haste path - the library's mid-swing
  UNIT_SWING_TIMER_UPDATE at the player's parry - is active instead of the
  early-landing fallback. Also picks up the library's dynamic-haste rescale on
  successful dynamic-family casts and its restricted-content (secret
  GUID/spell ID) error fixes.

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

