# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial v1 implementation for WoW: Forever — main-hand, off-hand and ranged
  swing bars driven by LibClassicSwingTimerAPI (embedded), with cast-reset
  (clipped) feedback that mirrors the client's interrupted-cast treatment
  (red tint plus shake), paused tint, movement-cancel reschedules following the
  library's `UNIT_SWING_TIMER_UPDATE`, an optional main/off-hand delta text, and
  a one-time notice when the game's own swing timer bars are also enabled.
- Three visibility modes mirroring the client's native swing timer (While
  swinging / In combat / Always), a Native skin reusing the client's
  `ui-swingtimerbar-*` atlases plus a Flat skin, drain/fill bar direction,
  per-character settings via the 12.x Settings API, `/4everswingtimer`
  (alias `/everswing`) with `unlock`, `lock`, `test`, `reset` subcommands, and a
  test-bars button on the unlock overlay.
- Interrupt feedback modeled on the 12.x casting bar: a clipped swing (reset
  by a cast) tints the fill red and shakes the bar - the shake runs ~0.7 s with
  decaying amplitude, and the tint holds full for ~0.45 s then fades back over
  ~0.3 s; a movement-delayed ranged swing (Auto Shot pushed back by the
  engine) tints the bar amber so the reschedule is visible. The reset
  detection keys on library semantics verified in source: the cast-completion
  reset fires START only (its STOP is suppressed by the isReset path in
  Unit:SwingStart), so the feedback triggers on a START that arrives while a
  swing is still in flight, on an in-flight STOP, and on
  UNIT_SWING_TIMER_CLIPPED itself - covering cast resets, weapon swaps, death
  and the mid-cast clip.
- Parry-haste feedback: an early landing - an in-flight STOP followed by a
  START with the same weapon speed, the signature of the engine shortening
  the swing mid-flight (player parry; a mid-swing haste proc reads the
  same) - bounces the bar vertically with a green tint, distinct from the
  interrupt treatment. In-flight stops are classified after a short grace
  period: START with the same speed is an early landing, START with a new
  speed is a weapon swap, and no START at all (death, attack stopped) keeps
  the interrupted treatment.
