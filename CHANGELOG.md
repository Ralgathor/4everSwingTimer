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
- The tick is the swing bar's own pip atlas everywhere - one identity across
  the normal, queued and interrupted states - height-scaled automatically
  (1.1x the statusbar, floored at 8 px) via the atlas's own aspect, per
  in-play feedback: the queued state differentiates by the cast-bar yellow
  fill, the yellow-tinted tick and the glow, not by swapping tick art. The
  interrupted state keeps the cast bar's red pip (ui-castingbar-pip-red),
  scaled the same way.
- The glow height uses the cast bar's own ratio (12px on a 13px bar, ~92% of
  the fill) instead of the cast bar's pip-relative band, which floated
  mid-fill with visible margins (in-play feedback; full fill height read too
  tall and 85% left the glow shorter than the tick's overhang); its width
  keeps the cast bar's streak ratio relative to the bar (37 wide on a 13px
  cast bar).
- Fixed bars staying hidden in the Always visibility mode after entering the
  world: the initial visibility pass runs at PLAYER_LOGIN, before the client
  populates the player's inventory, so every weapon-presence read returned
  nil. Visibility now refreshes on PLAYER_ENTERING_WORLD (login, teleport,
  hearthstone) with a 1 s retry, and on UNIT_INVENTORY_CHANGED for the player -
  the signal that equipment data has actually arrived, which on a first login
  happens after the loading screen completes.
- Fixed the ranged delay feedback not firing on movement-cancelled Auto
  Shots: the detection compared the new expiration against the old one, but a
  fail early in the cast window reschedules to nearly the original landing
  time (recast ~0.5 s), so the push was below the threshold. The detection now
  keys on the library's reschedule signature itself - a ranged UPDATE landing
  at now + ~0.5 s (measured recasts 0.43-0.56 s, window 0.3-0.7) - which is
  the only ranged UPDATE source on WoW: Forever.
- Fixed degenerate low bar heights: the height slider's floor was 8px, below
  the statusbar's 4px top and bottom insets, so the fill collapsed to a
  0-4px sliver with the text floating over it. The floor is now 14px (fill
  never below 6px, text always fits inside the bar), and saved values under
  the old floor migrate up on load.
- Flat style palette retuned away from the effect palette: the old gold main
  hand swallowed the queued yellow tint and the crimson ranged bar swallowed
  the interrupt red (in the flat style the effects replace the bar color
  wholesale, so a base near an effect color makes that effect invisible).
  The Bar colors dropdown now offers curated palettes only - Silver/Blue/
  Violet (default), Steel/Sky/Indigo, Graphite shades of gray, Rose/Ocean/
  Plum - each chosen for distance from the effect colors, satisfying the
  constraint by construction instead of leaving it to the user; free
  per-hand color pickers were tried and removed for exactly that reason.
  Palette keys saved by earlier builds migrate to the default.
- Native skin parity with the game's own swing timer, from a source diff of
  Blizzard_SwingTimer: the label now sits on the native bar's text shadow
  (ui-swingtimerbar-textshadow-left, 171px, left-anchored, full statusbar
  height - the native bar's distinctive left-side darkening), shown only in
  the native style, and the label/time insets match the native x=10 / x=-10
  (we were 5px too close to each edge).
- Fixed the parry-haste feedback popping on ordinary swings: a stop counted as
  "in flight" with only 0.05 s remaining, but the engine's PLAYER_SWING
  anchor and the library's expiration timer race by up to a frame at every
  swing - whenever the engine won, a normal completion read as an early
  landing. The in-flight threshold is now 0.2 s, far above frame jitter and
  far below a genuine parry-haste landing (~40% of weapon speed early).
- Text scaling: the hand label, time and delta font height now tracks the
  bar height (0.66x, clamped to 9-14 px - the 18px cap read far too large in play) instead of the fixed small font,
  which read shrunken on tall bars. The font stays the game's standard text
  face; the drag-hint overlay keeps the fixed small font as UI chrome.
- Fixed the tick and glow positioning in drain mode: the pip was anchored to
  the fill texture's edge, and a parked drain bar sits at value 0, where the
  zero-width fill's edge left the tick and glow dangling off the bar. The tick
  is now positioned manually like the cast bar's spark (value * width from
  the statusbar's left), clamped inside the bar; the glow keeps the cast bar's
  own anchor (trailing the tick's left, no direction flip) and is hidden when
  it would extend outside the bar frame - e.g. the tick sitting at the left
  edge of an empty drain bar.
- Interrupt outer glow from the cast bar source (the one gap in a full review
  of the interrupted treatment): the native bar flashes the
  cast_interrupt_outerglow atlas in ADD blend, atlas-sized at half scale and
  centered on the bar regardless of bar size, fading over exactly 1.0 s
  (InterruptGlowAnim). The interrupt treatment now layers the red fill tint
  (native-consistent: the cast bar switches to the ui-castingbar-interrupted
  atlas / CASTBAR_CLASSIC_RED), the red pip, the tuned shake and this outer
  glow. The parry-haste and ranged-delay effects have no native analogs and
  stand as designed.
- Parry-haste effect restructured onto the interrupt pattern (spark + outer
  glow): the tick tints green for the duration of the effect (restored by the
  fade's style re-apply), and the old full-fill green wash becomes an additive
  green outer halo extending 6px past the bar's frame, matching how the cast
  bar's interrupt glow spans its bar. The scale pop stays as the haste motion.
  No green glow atlas exists in the client, hence the plain-color halo.
