# Addon benchmark: swing timer addons (ref/)

Deep review of every addon under `ref/`, benchmarked against
4everSwingTimer. Reviewed 2026-10-01, claims re-verified against the code
and `docs/SPEC.md` the same day. The references are research copies, not
shipped with our package. Two shipped Forever competitors from SPEC 10.2 -
EllesmereUI's swing module and Bogarne's Minimalistic Weapon swing timer -
are not in `ref/` and are not covered here.

| Addon | Version | Interface | Lines (own code) | Data source | Scope |
|---|---|---|---|---|---|
| ForeverSwing | 2.0.5 | 16001 | ~3,300 | Raw `PLAYER_SWING` | Swing bars, profiles, Paladin seals |
| AppelSwingsForever | 1.1.0 | 11601, 11600 | ~7,500 | Raw `PLAYER_SWING` | Swing bars, range bands, castbar, hunter tools |
| BetterSwingTimer | 0.1.10 | 16001 | ~2,650 | Native frame mirroring | Swing bars, range strip, action cooldowns |
| LaryIsland's Swing Timer | 1.3.0 | 16001 | ~2,000 | Raw `PLAYER_SWING` + `UNIT_COMBAT` inference | Swing bars, enemy swing bars, profiles |
| WeaponSwingTimer (SixxFix) | 6.7.4 | 20505 | ~4,850 in TOC (+1,080 untracked `Range.lua`, +1,145 loc) | Combat log reconstruction | Swing bars, target bars, hunter, castbar |
| 4everSwingTimer | 1.0.0-beta3 | 16001 | ~2,200 | LibClassicSwingTimerAPI | Swing bars |

AppelSwingsForever's TOC declares `11601, 11600`, not the Forever client's
16001, while its code comments claim payloads "verified on Forever
1.60.1.69913" (`Swing.lua:14`). Unresolved: either the copy in `ref/` is
an older build or the addon loads on Forever as out of date.

## 1. The five data-source models

Every addon in this space answers the same question - "where does swing
truth come from?" - differently. This is the most important axis of
comparison, because each model inherits a different failure surface. The
axis that differentiates 4everSwingTimer (SPEC 10.2) is a second one:
what happens *between* two swings (section 7, first rows).

1. **Library** (4everSwingTimer). All state from LibClassicSwingTimerAPI
   (currently v2.2.0-beta4, LibStub MINOR 36). The library reconstructs
   the swing mid-cycle - cast resets, pauses, clips, FAILED_QUIET
   reschedules - and the addon holds no swing math. Failure surface is the
   library's, which we also own and fix. The library's own model also
   creates failure modes the simpler models cannot have: the stale active
   swing at login came from the library's login seed (fixed by the parked
   seed in beta4), and a never-landing swing needs the addon's stale sweep.
2. **Raw event** (ForeverSwing, AppelSwingsForever, LaryIsland). Consume
   `PLAYER_SWING(duration, swingType)` and re-anchor the bar on every
   event. They never seed a swing and every one of them ends a bar when its
   computed time runs out (ForeverSwing `Bars.lua:644`-`647`, LaryIsland's
   `OnUpdate` -> `Stop`, AppelSwingsForever's `Progress` clearing at p >= 1),
   so the stale/parked problems above do not arise for them. What they lack
   is everything between swings: a cast reset, pause or clip shows only
   when the next `PLAYER_SWING` re-anchors the bar. Speed reads
   (`UnitAttackSpeed`/`UnitRangedDamage`) are guarded by `issecretvalue()`
   (ForeverSwing, LaryIsland) or `pcall` (AppelSwingsForever).
   They differ on the `PLAYER_SWING` *duration*: ForeverSwing handles a
   secret duration (`Bars.lua:607`-`631`); AppelSwingsForever
   (`dur <= 0`, `Swing.lua:149`) and LaryIsland (`duration <= 0`,
   `LaryIsland_SwingTimer.lua:282`) compare it directly. Settled by the
   library: the payload is probe-verified as a plain number even in
   restricted content, and the library guards it anyway
   (`LibClassicSwingTimerAPI.lua:579`-`596` at v2.2.0-beta4), so the
   unguarded comparisons are safe in practice.
3. **Native frame mirroring** (BetterSwingTimer). `hooksecurefunc` on
   Blizzard_SwingTimer's own statusbars and labels, native frames set to
   alpha 0, `showSwingTimer` CVar force-enabled. Inherits Blizzard's swing
   state machine by construction - per-swing re-anchoring only (SPEC
   10.1), including any engine bugs - with zero swing math of its own.
4. **Combat log reconstruction** (WeaponSwingTimer). `SWING_DAMAGE` resets
   the timer, `PARRY` applies the 40%/20% parry-haste rule,
   `SPELL_EXTRA_ATTACKS` suppresses the reset from windfury/sword-spec
   procs, per-class spell tables reset the swing. The classic
   pre-`PLAYER_SWING` model. Dead on Forever: the combat log is hidden
   from addons there (LaryIsland `EnemySwing.lua:3`, AppelSwingsForever
   `Castbar.lua:7`).
5. **Inference** (LaryIsland enemy module). The target's swings inferred
   from `UNIT_COMBAT` hits the player receives - swing actions only
   (WOUND/BLOCK/ABSORB/MISS/DODGE/PARRY/DEFLECT), interval learning,
   dual-wield and parry-haste modeling. Forever's only route to enemy
   swings. The library's own findings (`FOREVER_API_FINDINGS.md` section 8,
   reopened 2026-09-25) already concluded the heuristic is implementable;
   what LST adds is a shipped set of mitigations (section 8, item 1).

## 2. ForeverSwing (v2.0.5)

Library-free: raw `PLAYER_SWING`, bar routing by name-matching
`Enum.PlayerSwingType` (`Core.lua:11`-`27`), `issecretvalue()` guards
everywhere, cached last-known answers for combat-hidden values.

**Interesting functionality**

- **Engine-timer animation** (`Bars.lua:203`-`205` create, `610`-`620`
  start, `666`-`668` capability probe). `C_DurationUtil.CreateDuration` +
  `SetTimerDuration(f.timer, Interpolation, Direction)` lets the WoW
  engine animate the fill off its own clock, and a secret duration passes
  straight through without ever being read. Capability probe (`timerOK`)
  with a manual `SetValue` fallback. Only the fill is engine-driven: an
  `OnUpdate` driver still runs every frame for the countdown text
  (`Core.lua:146`-`155`), and with a secret duration the text is blanked
  (`Bars.lua:627`-`631`).
- **`/fswing probe` diagnostics** (`Core.lua:204`-`240`). Prints
  `C_SwingTimer` presence, the enum dump, up to 25 globals containing
  "swing", and whether `UnitAttackSpeed` returns secrets. Instant,
  pasteable support output. Also `/fswing debug` (swing events to chat)
  and `/fswing assets` (atlas check).
- **Profile export/import as base64 codes** (`Profiles.lua:176`-`315`).
  Hand-rolled serializer (depth-capped at 8, no `loadstring`, no code
  execution) in an `FS1:` envelope.
- **Paladin seal icon** (`Class.lua`). 7 seals beside the main-hand bar
  (Righteousness, Crusader, Fury, Command, Light, Wisdom, Justice), with a
  remaining-time readout. Three-tier read (`Class.lua:51`-`162`):
  1. `C_UnitAuras.GetAuraDataBySpellName("player", name, "HELPFUL")` per
     seal - the comment claims it "still works when the game hides the
     names of individual buffs in combat"; expiration/duration are kept
     only when not secret;
  2. an index scan (`GetAuraDataByIndex`, pcall-wrapped; a throw or a
     secret name marks the auras "unreadable");
  3. while unreadable, the seal it saw cast (`UNIT_SPELLCAST_SUCCEEDED`
     spell ID -> name) plus a duration learned from the last readable
     aura (fallback 30 s).

  Caveats: the library's probes found no aura channel mid-combat on
  Forever (`GetPlayerAuraBySpellID` returns nil, `GetAuraDataByIndex`
  throws - library HASTE_APPLICATION_FINDINGS, 2026-09-30), but the
  by-name call FS leans on was never probed, so FS's claim is open, not
  refuted. If tier 1 is also dark, the in-combat display is tier 3 alone,
  which cannot see a seal ending early (a Judgement consuming it, under the
  classic rule) and dies wherever the player's cast spell IDs go secret
  (library open item 5). Seal names are matched as English strings
  (`SEAL_LIST`), so non-enUS clients never match.
- **Fraction-preserving mid-swing haste rescale** (`Bars.lua:698`-`731`):
  recomputes start/duration keeping `(now-start)/duration` constant.
  Caveat: it only runs on readable speeds - `GetSpeed` returns nil for a
  secret value (`Bars.lua:59`-`70`) and the rescale is skipped - so in
  combat, where haste procs happen, it is a no-op on Forever.
- **Cancel/reset event coverage** (`Core.lua:101`-`132`): death, druid
  forms, mounting, interrupted auto shot/wand; stuns deliberately keep
  the timer running.
- **Atlas art reuse** (`Bars.lua:268`-`285`): `ui-swingtimerbar-*` fills
  per hand with `GetAtlasInfo` pcall checks and fallbacks.
- **Lightning spark** (`Bars.lua:379`-`470`): `Frame:CreateLine` bolts
  re-rolled ~22x/sec trailing the fill edge. Attached-stack dragging,
  LibDBIcon minimap icon (used if present, not embedded) with handmade
  fallback.

**Weaknesses.** Restart-on-every-PLAYER_SWING (no update-vs-new-swing
distinction, nothing between swings); haste rescale dead in combat; no
effect feedback, speed/delta text, test mode beyond a preview, trace tool,
or native-timer CVar warning; coarse visibility model; 1,230-line custom
options window as maintenance surface.

## 3. AppelSwingsForever (v1.1.0)

The heavyweight (~7,500 lines), a hunter-focused port of the classic
AppelSwings. Raw `PLAYER_SWING` with `Enum.PlayerSwingType` plus a
verified fallback map (`Swing.lua:14`-`17`: 0 = main hand, 2 = ranged,
payload verified on Forever 1.60.1.69913; type 1 off hand by convention,
unobserved). Shares its range-band code with BetterSwingTimer (same item
ladder minus BST's missing MELEE rung, identical colors and labels,
same melee-spell table); which copied which is not established, and
AppelSwingsForever credits LibRangeCheck-3.0's Era tables and a
classic-hunter WeakAura as its own sources (`Bands.lua:6`-`8`, `52`-`54`).

**Interesting functionality**

- **`/asf log` swing-truth diagnostic** (`Swing.lua:29`-`100`). Prints
  every swing with how far it landed from where its bar said it was due,
  tags casts within 0.15 s of a swing, and logs your parries with the
  main-hand bar's remaining time - the same engine-vs-model comparison
  our `trace` tool makes, in chat, live.
- **Learned ranged reload, persisted per bow** (`Swing.lua:102`-`145`).
  The slowest reload seen per bow (so never a haste proc) is saved at
  logout; "any" as fallback. Feeds the melee-resets-ranged-reload model:
  **every melee swing restarts the ranged reload with no ranged event for
  it** (`Swing.lua:159`-`170`). This is the addon's own claim about
  Forever, not verified by us; no other addon in this review models it.
- **Auto Shot clip timer** (`Swing.lua:188`-`285`). After each shot, how
  much later than one reload after the previous shot it fired, as
  "+0.00" in three threshold colors (0.25 s / 0.50 s); measured from the
  previous shot so a melee-restarted reload counts as a clip; a gap of
  five reloads counts as a new fight; survives hiding the ranged bar
  (parented to UIParent).
- **Auto Shot windup line** (`Swing.lua:1336`-`1415` model, `1416`-`1650`
  drawing). The 0.5 s windup (scaled by ranged haste, bow base speed
  parsed from the tooltip via `C_TooltipInfo.GetInventoryItem` with a
  0.5 s retry) drawn as a line on the bar at the stop-moving point; static
  (share of the reload) or moving (bow-scale) variants, and
  `ShapeProgress` bends the fill's progress so it reaches the line exactly
  when to stop moving.
- **Hold-at-line modeling** (`Swing.lua:1806`-`1840`). Movement or Auto
  Shot switched off holds the ranged bar at the windup line - the
  "waiting to fire" state, modeled. `SHOT_GRACE` (0.25 s) absorbs the
  reload-runs-out-~0.08 s-early jitter; `HOLD_WAKE` (5 s) is how long
  after the reload ran out a finished bar can still wake at the line.
- **Pixel-perfect rendering layer** (`Core.lua:58`-`88`, throughout
  `Swing.lua`). One physical-pixel grid (`PixelSize`/`QuantizePx`,
  invalidated on `UI_SCALE_CHANGED`/`DISPLAY_SIZE_CHANGED`); every fill,
  pip, border and position snaps to it; pixel snapping selectively
  disabled (`SetSnapToPixelGrid`, `SetTexelSnappingBias`) where sub-pixel
  glide is wanted. Fill art is *cropped*, never squeezed, and atlas tints
  are doubled by an additive "boost" copy (`Swing.lua:1074`+) because a
  desaturated tint always comes out darker than the color.
- **Range bands via item ladder** (`Bands.lua`). 8 bands (melee-35 yd +
  dead zone) from `C_Item.IsItemInRange` with vanilla-era item IDs
  verified on Forever; melee = class melee ability reaches AND Auto Shot
  does not; preloads item data at login; band color with pop animation.
  Unverified: mainline restricts `IsItemInRange` against hostile targets
  in combat; whether the ladder still answers in combat on Forever is not
  established.
- **Castbar with Quartz-style latency bar, pushback, and Blizzard
  castbar hiding** (`Castbar.lua`); 4,316-line custom config window with
  profiles, account backup restore, and text-string settings sharing
  (`ASF2:` base64 + checksum, only values that differ from defaults,
  `Config.lua:1094`+).

**Weaknesses.** Raw-event model, so nothing between swings beyond its
own melee-resets-ranged rule; per-frame Lua for all three bars (no
engine-timer animation); compares the `PLAYER_SWING` duration with no
secret guard; hunter-centric range model (melee fallback is one
deliberately chosen item, per comment); TOC interface does not match the
Forever client. The custom config panel is the largest single
maintenance surface in the review.

## 4. BetterSwingTimer (v0.1.10)

The only addon in the review that solves the data problem by delegation:
it does not consume `PLAYER_SWING` at all. Instead it binds to the
client's own `SwingTimerMainHandFrame`/`OffHandFrame`/`RangedFrame` and
mirrors them (`BlizzardTimer.lua`):

- `hooksecurefunc` on the native statusbar's `SetValue`, the time label's
  `SetText`/`SetFormattedText`, and the frame's `ResetSwingTimer`/
  `ClearSwingTimer`; native frames set to alpha 0 (never hidden - comment
  notes writing visibility fields can taint later native events);
  `showSwingTimer` CVar force-enabled and re-checked on `CVAR_UPDATE`.
- Swing state is read off the native frames on each reset/clear hook:
  `frame.swingDuration` / `frame.swingEndTime`
  (`BlizzardTimer.lua:67`-`68`). These are Blizzard_SwingTimer's
  internal fields, already known from the source read in SPEC 10.1, and
  they hold only what the native bar holds: the last `PLAYER_SWING`
  re-anchor, with no cast reset, pause, clip or parry haste. They exist
  only with the CVar on and Blizzard_SwingTimer loaded, and Blizzard gates
  its `PLAYER_SWING` registration on weapon presence and visibility mode.
  Whether they are secret in combat is unverified; BST compares them with
  `> 0` (`BlizzardTimer.lua:69`), weak evidence they are plain numbers.
- Its own OnUpdate runs for test mode and the range ticker
  (`RangeBands.lua:234`); live bars update through the hooks.

**Interesting functionality**

- `C_SwingTimer.IsTargetWithinSwingRange(swingType)` +
  `PLAYER_SWING_RANGE_UPDATE` (`Bars.lua:9`-`31`, `Core.lua:237`). Already
  in SPEC 10.1, and dead on this beta build: the 2026-09-28 probe found
  the query returns nil both in and out of range and the event broken.
  BST's `GetTargetRangeState` therefore always returns nil today; only its
  item-ladder strip works.
- **Action-button swing cooldown overlays** (`ActionCooldown.lua`): a
  `CooldownFrameTemplate` overlay on every action button whose spell is
  Attack (6603) or Auto Shot (75), driven by the swing timers - and it
  parses macro bodies (including `/startattack`) to map macro buttons to
  the right timer.
- Ranged windup marker at a fixed 0.5 s (`Bars.lua:7`), the same
  range-ladder strip as AppelSwingsForever, per-bar sizes/positions and
  gradient fills, minimap button, animated test mode with staggered
  three-bar cycles, `/bst inspect` integration dump.

**Weaknesses.** Fully dependent on the native frames existing and
behaving (bluntly force-enables a CVar our addon only warns about);
mirroring means inheriting the native bar's per-swing-only model and
every native bug with no layer to fix it in; no secret-value handling
needed only because it never reads speeds; the mirrored text path
bypasses its own formatting entirely; the native range path it ships is
dead on this build.

## 5. LaryIsland's Swing Timer (v1.3.0)

Raw `PLAYER_SWING` + the only working **enemy swing timer** on Forever.
Uses the same 12.x Settings vertical-layout API as we do, plus embedded
AceDB/AceDBOptions/AceConfig/AceGUI (`embeds.xml`), LibSharedMedia for
fonts/textures when present, and `CreateFont` objects to survive the
font-swap text-loss bug (`LaryIsland_SwingTimer.lua:193`-`213`).

**Interesting functionality**

- **Enemy swing inference from `UNIT_COMBAT`** (`EnemySwing.lua`, 677
  lines). The target's swings are inferred from the hits/misses the
  *player receives* (Forever hides the combat log): swing actions only,
  interval learning (median of last 5, capped at 6 s), expected-speed
  sanity gating (min 75% of expected, min 0.2 s gap), NPC floor of
  1.0 s, and speed snapping to learned values within 0.02 s.
- **Enemy dual-wield detection** (`EnemySwing.lua:327`-`540`): off-hand
  candidates from alternating short-gap hits, evidence expiry, damage-
  strength heuristics (off-hand ratio 0.7; crits x2, crush x1.5; player
  crits skipped - Forever's 150% melee-crit bug is documented in a
  comment), hand swap and hand-drop rules with sample-count gates.
- **Enemy parry haste** (`EnemySwing.lua:561`): when the *target* parries,
  its next swing is pulled in by the classic 40%/20% rule, applied to the
  learned interval.
- **Queued-attack recolor** (`LaryIsland_SwingTimer.lua:100`-`103`,
  `617`): bars recolor while a queued attack (Heroic Strike/Raptor
  Strike/Maul/Cleave, every rank listed explicitly, via
  `C_Spell.IsCurrentSpell` + `ACTIONBAR_UPDATE_STATE`) is up - the same
  "queued" state our effect stack highlights. We pass base IDs only on the
  assumption that ranks resolve through the base (`Bars.lua:181`-`188`);
  one of the two approaches is redundant, and only a probe with a
  high-rank Heroic Strike queued tells which.
- **Ranged cast window** (`LaryIsland_SwingTimer.lua:310`-`318`): the
  0.5 s Auto Shot/wind-up shown as a fill-then-drain phase change with a
  separate cast color, for HUNTER/MAGE/PRIEST/WARLOCK (wands).
- **Alpha model** (`UpdateAlpha`, `:434`): ooc alpha, mounted alpha,
  barber-shop hide, druid travel-form detection, and target-conditional
  overrides ("show full alpha when an enemy/friendly target exists").
- **Simulation modes** for the options preview (melee / ranged /
  autoshot, including simulated enemy swings) - a richer cousin of our
  test mode, wired to the settings panel live (`Options.lua:167`).
- **Native-encoding profile export** (`Profiles.lua:43`-`53`): only
  non-default values, through the client's own
  `C_EncodingUtil.SerializeCBOR` + `CompressString` + `EncodeBase64`. No
  serializer code to write or maintain.
- **`/lst debug` and `/lst probe`** (`Diagnostics.lua`): full state dump
  (per-bar shown/last-swing/label metrics, queued spell, enemy state) and
  a live probe log of hits on you and queued-attack changes.

**Weaknesses.** Enemy model is single-target and only swings *at the
player* (documented); melee speed text only (no countdown); no effect
feedback beyond queued recolor; player-side truth is raw-event, so
nothing between swings, and it compares the `PLAYER_SWING` duration with
no secret guard.

## 6. WeaponSwingTimer (v6.7.4, WatchYourSixx fork)

The classic combat-log addon, built for Burning Crusade Classic
(`## Interface: 20505`), included here as the pre-`PLAYER_SWING` model and
the ancestor most of the hunter tooling descends from
(AppelSwingsForever's comments cite "WeaponSwingTimer SixxFix" for the
Auto Shot windup).

**Interesting functionality**

- **Combat-log swing reconstruction** (`Core.lua:580`-`660`,
  `Player.lua:129`-`142`): `SWING_DAMAGE` resets the running timer
  (off-hand flag routes to the off timer), `SPELL_EXTRA_ATTACKS` sets a
  flag so windfury/sword-spec extra attacks do not reset it, `PARRY`
  applies the 40%/20% parry-haste floor to the *parrying* unit's own next
  swing - for both player and target.
- **Per-class swing-reset spell tables** (`Core.lua:25`+,
  `SpellHandler`): which casts reset the swing (Slam and the like), per
  class. The classic reference for the Slam probe in SPEC 11 (M1).
- **Speed-change rescaling in flight** (`Player.lua:80`-`102`): polls
  `UnitAttackSpeed` per frame; when the speed changes mid-swing the
  remaining time is multiplied by the speed ratio - the same
  fraction-preserving idea ForeverSwing implements, discovered
  independently, and equally unable to read a secret speed in combat on
  Forever.
- **Ranged base speed from tooltip parsing**
  (`WeaponSwingTimer_ranged_base_speed.lua`): a hidden `GameTooltip` +
  `SetItemByID`, matching the localized `SPEED` pattern, cached per item
  id - the technique AppelSwingsForever modernized with
  `C_TooltipInfo`. Quiver haste enters as `base + 0.15` (`Hunter.lua:151`);
  Auto Shot windup fixed at 0.52 s (`Hunter.lua:82`).
- **Multishot clip bar** (`Hunter.lua:394`-`509`): a second bar showing
  where a Multi-Shot cast would clip the next Auto Shot, sized by cast
  time against reload.
- **Paladin seal-twist marker** (`Player.lua:241`, `747`-`752`): an
  optional 0.4 s marker before the swing lands, for applying a seal after
  it.
- **Castbar with `GetNetStats` latency band** (`WeaponSwingTimer_Castbar
  .lua:146`-`447`), pushback-adjusted; target swing bars; 11-locale
  localization; AceDB profiles; options through
  `Settings.RegisterCanvasLayoutCategory` with subcategories
  (`Config.lua:28`-`76`); an experimental `WeaponSwingTimer_Range.lua`
  (spellbook-based range probes per class, using
  `C_SpellBook.IsSpellBookItemInRange`) present on disk but not listed
  in the TOC.

**Weaknesses (on Forever specifically).** The entire model rests on
`COMBAT_LOG_EVENT_UNFILTERED`, which Forever hides from addons - the
core, player, target, hunter and castbar swing logic all go dark. Its
options registration is already on the modern Settings API
(`InterfaceOptionsFrame_OpenToCategory` is only a guarded fallback,
`Core.lua:887`-`893`), but it calls the removed global `GetSpellInfo`
unguarded (`Castbar.lua:122`, `224`; `Hunter.lua:103`; `Player.lua:146`,
`242`; `Target.lua:138`), which fails at call time on this client. Its
value to us is the classic swing mechanics reference (parry haste, extra
attacks, swing-reset spells, quiver bonus, clip model) and the
localization/profile scaffolding.

## 7. Feature matrix

| Feature | FS | ASF | BST | LST | WST | 4eST |
|---|---|---|---|---|---|---|
| Main / off / ranged bars | Yes | Yes | Yes | Yes | Yes | Yes |
| Mid-cycle reconstruction (cast reset / pause / clip / reschedule) | - | Melee-resets-ranged only | - (native: per-swing only) | - | Combat log: reset spells, parry (dead on Forever) | Yes (library) |
| Correctness net for the library's stale/parked swings | n/a | n/a | n/a | n/a | n/a | Yes |
| Secret `PLAYER_SWING` duration handled | Yes | - | n/a | - | n/a | Library |
| Swing effect feedback (interrupt/haste/delay/queued) | - | - | - | Queued recolor | - | Yes |
| Speed / delta text | - | - | - | Speed | - | Speed + delta |
| Countdown text | Yes | Yes | Yes | - | Yes | Yes |
| Ranged windup line / cast window | - | Yes (both) | Fixed 0.5 s line | Cast-window phase | 0.52 s + multishot clip | - |
| Auto Shot clip readout | - | Yes | - | - | Multishot only | - |
| Melee-resets-ranged-reload model | - | Yes | - | - | - | - |
| Enemy / target swing bars | - | - | - | Yes (UNIT_COMBAT) | Yes (combat log) | - |
| Parry-haste modeling | Restart only | Logged only | (native) | Enemy side | Both sides | Library (verified, player side only) |
| Mid-swing haste rescale | Readable speeds only | - | (native) | - | Readable speeds only | Library: Slice and Dice rank 1 only, others at next swing |
| Range strip / bands | - | Yes (8 bands) | Item strip (native API path dead) | - | On disk, not in TOC | - |
| Native swing-timer art reuse | Yes | Yes (3-slice, cropped fills) | Mirrors native | - | - | Native-styled |
| Engine-timer animation | Fill only | - | Native mirror | - | - | - |
| Test / simulation mode | Preview | Preview | Animated test | Simulation modes | - | Test + per-effect tests |
| Profiles | 18 + base64 codes | Yes + text sharing | - | AceDB + strings | AceDB | - |
| Export / import | Base64 (hand-rolled) | Base64 delta + checksum | - | Native CBOR + compress, delta | - | - |
| Minimap icon | Yes | - | Yes | - | - | - |
| Class-specific feature | Paladin seals | Hunter suite | Action cooldowns | (hunter/wand cast window) | Hunter module, Paladin seal-twist marker | - |
| Diagnostics command | probe, debug, assets | log (swing truth) | inspect | debug + probe | - | debug + trace |
| Options surface | Custom window + stub | Custom window (4.3k lines) | Custom window | Settings API + AceConfig | Settings API (canvas) | Settings API |
| Localization | - | - | - | - | 11 locales | - |

(FS = ForeverSwing, ASF = AppelSwingsForever, BST = BetterSwingTimer,
LST = LaryIsland, WST = WeaponSwingTimer, 4eST = 4everSwingTimer.
"n/a" in the correctness-net row: the problem comes from the library's
seed and cannot arise in that model.)

## 8. Consolidated: functionality worth flagging for us

Ranked by relevance to 4everSwingTimer's roadmap:

1. **Enemy swing inference from `UNIT_COMBAT`** (LST). SPEC section 2's
   "Forever has no data source" was already superseded by the library's
   findings (section 8, reopened 2026-09-25: a heuristic is implementable,
   with documented failure modes - multiple attackers, the player's
   instant melee abilities, mob ranged attacks - and blocked on the
   never-run `PLAYER_SWING` player-only isolation test, open item 10). LST
   is the first shipped implementation and a reference for the
   mitigations the library plan lacks: attacker counting from nameplates,
   tanking/threat checks, damage-strength hand assignment. Library scope
   if ever built (it already has a target unit and registers
   `UNIT_COMBAT`).
2. **Queued-attack rank coverage** (LST lists every rank; we pass base
   IDs). Probe `C_Spell.IsCurrentSpell(78)` with a high-rank Heroic Strike
   queued; if it returns false, our queued highlight misses at higher
   levels; the fallback is the library's full rank list
   (`next_melee_spells`, `LibClassicSwingTimerAPI.lua:1167`-`1197`).
3. **Live swing-truth logging** (ASF `/asf log`, LST `/lst probe`).
   Landing-vs-due deltas, cast tags, parry logging - complements our
   SavedVariables `trace` with an instant in-chat variant for user
   reports.
4. **Melee-swing-resets-ranged-reload and hold-at-line** (ASF). Forever-
   specific engine behaviors claimed by ASF and modeled by nobody else -
   the library anchors ranged only on `PLAYER_SWING` type 2; belongs in
   the library's model if confirmed in-game, not in the addon.
5. **Swing-reset spell tables** (WST). Nothing to import: on Forever the
   library resets the swing on any completed cast not in its no-reset
   table, and its Classic tables share WST's lineage. Slam is tracked
   separately (library IMPROVEMENT_PLAN 6a, the M1 probe).
6. **Profile export/import** (LST native CBOR, FS base64, ASF
   delta-text). If profiles ever enter scope (SPEC 2 non-goal today),
   LST's `C_EncodingUtil` route needs no serializer code at all.
7. **Engine-timer animation via `C_DurationUtil`** (FS). Engine-driven
   fills with the `timerOK` probe + fallback; it removes per-frame fill
   work but not the text update, so the gain for us is small.
8. **Enemy/own parry-haste 40%/20% rule** (LST, WST). Already in the
   library for the player's own parries, verified against the engine on
   build 70124 with a 0.65 s event-skew correction
   (`LibClassicSwingTimerAPI.lua:413`-`476`); target-side parry haste
   would come with an enemy model.
9. **Pixel-perfect grid layer** (ASF). `PixelSize`/`QuantizePx` with UI-
   scale invalidation, cropped (never squeezed) fill art, additive boost
   for tinted atlas fills - the techniques matter if our native skin
   ever shows seams.
10. **Paladin seal tracking** (FS seal icon, WST seal-twist marker). Two
    parts worth separating. The *API lead*: FS claims
    `C_UnitAuras.GetAuraDataBySpellName` answers in combat where the
    library found every other aura call dark. One `/run` probe settles
    it, and a yes reopens aura presence as a library signal (Flurry and
    other proc hastes, Maelstrom Weapon, Seal of the Crusader expiry).
    The *feature*: a seal icon is aura display, outside this addon's
    purpose (render the library's swing state); WST's 0.4 s seal-twist
    marker is the swing-relative variant and needs only the library's
    expiration time, no aura data.

Triage of these items into addon and library scope: SPEC 10.5.

Not new, already covered by SPEC 10.1: the native frames' `swingDuration`/
`swingEndTime` fields (per-swing re-anchoring only, so weaker than the
library's state and no use as a cross-check) and
`C_SwingTimer.IsTargetWithinSwingRange` / `PLAYER_SWING_RANGE_UPDATE`
(both dead on this beta build).

## 9. Bottom line

The review splits cleanly along the data-source axis, but the axis that
matters for us is what happens between swings. Every reference that runs
on Forever re-anchors on `PLAYER_SWING` (or mirrors the native bar that
does), so none shows a cast reset, pause, clip or reschedule until the
next swing arrives; WST's combat-log reconstruction did, and is dead on
Forever. That is the SPEC 10.2 positioning, and nothing here changes it.
The stale/parked-swing handling is not a differentiator: it guards
against failure modes of the library's own model that the simpler models
never have.

The client-side leads in competitors' code mostly confirm what SPEC 10.1
already recorded - the native fields and the range API are known, and the
range API is dead on this build. Enemy-swing inference is not new either:
the library's findings had already reopened it as an implementable
heuristic; LST contributes the first shipped implementation and its
mitigations. Feature-wise, the fields nobody covers but us remain
mid-cycle reconstruction, effect feedback, speed/delta text, and the
trace tool; the fields covered by others but not us are enemy swings
(deferred; SPEC 2's "no data source" rationale is superseded, the
deferral stands on scope and on library open item 10), range readouts
(out-of-range dimming is a deferred v1.1 candidate, SPEC 10.1/11, blocked
upstream) and profiles (a SPEC 2 non-goal).

Library claims checked against LibClassicSwingTimerAPI v2.2.0-beta4
(MINOR 36, the version this addon pins): `PLAYER_SWING` duration secrecy,
player parry haste and the haste-rescale scope (all above). Open items
this review could not settle from code: whether AppelSwingsForever's
`11601` TOC loads on Forever, whether the native frame fields can be
secret in combat, and whether `C_Item.IsItemInRange` answers in combat.
