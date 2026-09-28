# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial v1 implementation for WoW: Forever — main-hand, off-hand and ranged
  swing bars driven by LibClassicSwingTimerAPI (embedded), with cast-reset
  (clipped) flash, paused tint, movement-cancel reschedules following the
  library's `UNIT_SWING_TIMER_UPDATE`, an optional main/off-hand delta text, and
  a one-time notice when the game's own swing timer bars are also enabled.
- Three visibility modes mirroring the client's native swing timer (While
  swinging / In combat / Always), a Native skin reusing the client's
  `ui-swingtimerbar-*` atlases plus a Flat skin, drain/fill bar direction,
  per-character settings via the 12.x Settings API, `/4everswingtimer`
  (alias `/everswing`) with `unlock`, `lock`, `test`, `reset` subcommands, and a
  test-bars button on the unlock overlay.
