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
  same) - pops the bar (brief 15% scale-up) with a green glow overlay and
  fill tint, distinct from the interrupt treatment. The glow is a separate
  overlay because a vertex tint modulates the native atlas fill's own
  colors and reads muddy. In-flight stops are classified after a short
  grace period: START with the same speed is an early landing, START with
  a new speed is a weapon swap, and no START at all (death, attack
  stopped) keeps the interrupted treatment.
- Queued next-melee highlight: while a next-melee ability (Heroic Strike,
  Cleave, Raptor Strike, Maul - base spell IDs) is queued, the main-hand
  fill takes the cast bar's classic yellow as a tint over the skin's own fill
  art - the swing bar keeps its identity (the full cast-bar fill atlas swap
  was tested in play and rejected) - and the tick swaps to the cast bar's
  pip (ui-castingbar-pip) with its glow streak (cast_standard_pipglow, ADD
  blend, anchored 2px to the pip's left), both working in the native and flat
  bar styles. Polled every 0.2 s via C_Spell.IsCurrentSpell (probe-verified
  on the beta: plain booleans, true with Heroic Strike queued). On by
  default, with a settings toggle.
- Interrupt fidelity with the cast bar, from the forever-branch source: the
  tick swaps to the cast bar's interrupted spark atlas (ui-castingbar-pip-red)
  for the duration of the interrupt tint, restoring with the fade, and the
  shake respects the ShakeStrengthUI CVar (enabled by default when the CVar
  is absent). Blizzard's exact InterruptShakeAnim recipe (1-2 px jitter,
  ~0.3 s) was tested in play and read as too subtle on a peripheral swing bar,
  so the shake keeps the stronger decaying ~0.7 s motion.
- The cast bar's pip and glow art (8x20 pip, 37x12 glow) is drawn for a 13 px
  bar; its size here is an explicit setting, Tick size (8-40 px, default 14) -
  several in-play rounds could not converge on a fixed rule (the cast bar's
  own overhang and linear scaling read too big, statusbar-flush and a 16 px
  cap read too small). The glow keeps the cast bar's proportions relative to
  the pip. Applies to the queued state and the red interrupt pip.
- Fixed bars staying hidden in the Always visibility mode after entering the
  world: the initial visibility pass runs at PLAYER_LOGIN, before the client
  populates the player's inventory, so every weapon-presence read returned
  nil. Visibility now refreshes on PLAYER_ENTERING_WORLD (login, teleport,
  hearthstone) with a 1 s retry, and on UNIT_INVENTORY_CHANGED for the player -
  the signal that equipment data has actually arrived, which on a first login
  happens after the loading screen completes.
- Fixed degenerate low bar heights: the height slider's floor was 8px, below
  the statusbar's 4px top and bottom insets, so the fill collapsed to a
  0-4px sliver with the text floating over it. The floor is now 14px (fill
  never below 6px, text always fits inside the bar), and saved values under
  the old floor migrate up on load.
- Fixed the tick and glow hanging outside the bar in drain mode: the pip was
  anchored to the fill texture's edge, and a parked drain bar sits at value 0,
  where the zero-width fill's edge left the tick and glow dangling off the
  bar. The tick is now positioned manually like the cast bar's spark
  (value * width from the statusbar's left), clamped inside the bar, and the
  glow trails behind the tick per fill direction (left in fill mode, right in
  drain).
