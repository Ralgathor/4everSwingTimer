# Swing timers on WoW: Forever — consolidated findings and API requests

Status: draft for the Blizzard beta forum / WoW UI Dev Discord, 2026-10-05.
Compiled from two community projects:

- **LibClassicSwingTimerAPI** (library): it reconstructs the swing state of the
  player and exposes it as addon events.
- **4everSwingTimer** (addon): it renders the swing state as bars.

The library owns all swing math. The addon renders only. Both projects run on
the WoW: Forever beta only. All findings below were verified live on the beta
client. Each finding names the build that verified it.

Test environment:

| Item | Value |
|---|---|
| Client | WoW: Forever beta |
| Builds verified | 70009, 70124, 70170, 70205 |
| Interface | `16001` |
| Ruleset | Classic; UI architecture: mainline 12.x |
| Restriction system | Midnight "Secret Values" (`issecretvalue`, `C_Secrets`) |
| Method | In-game probes, verbatim SavedVariables traces, the client's own `/combatlog` |

Terms used in this report:

- **swing** — one auto-attack cycle of one hand (main-hand, off-hand, ranged).
- **anchor** — the `PLAYER_SWING` event. It reports a swing with its true
  duration. The library restarts its state at each anchor.
- **landing** — the instant the current swing completes.
- **expiry** — the time the current swing lands.
- **one-swing lag** — the error window when an addon learns a speed change only
  at the next anchor.
- **secret / plain** — a value the client hides / a readable value.
- **edge** — an event that says "something changed" and carries no usable data.

## 1. Summary

WoW: Forever gives addons one good channel: `PLAYER_SWING`. The event is
accurate, complete, and plain. Everything else a swing timer needs is closed,
broken, or undocumented:

1. Speed reads (`UnitAttackSpeed`, `UnitRangedDamage`) go **secret in all
   combat**. An addon can store the values, but it cannot compare or compute
   with them.
2. Aura data is **hidden mid-combat** for every aura probed. All probed auras
   are classified `ContextuallySecret`. The `NeverSecret` whitelist exists in
   the client, but no swing-relevant aura populates it.
3. **No API surfaces a mid-swing attack-speed change.** The engine rescales
   the in-flight swing; no event reports it.
4. The `C_SwingTimer` **range subsystem is dead**: the event fires once and the
   query returns nil. The built-in swing timer cannot show out-of-range state.
5. `PLAYER_SWING` **fires ~0.45 s before the swing resolves**. The API browser
   does not say what the event marks.
6. `UNIT_COMBAT` **PARRY dispatch lags** the combat-log record by 0.10–0.30 s.
7. The combat log is **refused for addons**, silently, on the whole beta.

Items 1–3 have one shared consequence: **every swing bar — the built-in bar
included — is wrong for up to one full swing after each haste gain and each
haste expiry.** Section 4 gives the one-minute reproduction.

Each issue has a small, evidence-backed ask. Section 8 lists them in priority
order. The cheapest ask (aura classification) needs no client code change.

## 2. What the API already gives (keep this)

These facts are verified. They are the base a swing timer can stand on, and we
ask that they stay as they are:

| Fact | Evidence |
|---|---|
| `PLAYER_SWING` fires once per swing attempt, for main-hand (`swingType` 0), off-hand (1), and ranged (2). It also fires for a swing that consumes a queued next-melee ability. It fires on miss, dodge, and parry too. | Traces on builds 70009–70205; Raptor Strike capture 2026-09-28; miss/dodge/parry capture 2026-09-25 |
| The payload is `(swingDuration, swingType)`: a plain number plus the hand. It stays **plain mid-fight in a dungeon**, while `UnitAttackSpeed` reads secret at the same moment. | Build 70009 dungeon probe; re-verified build 70205 |
| The `swingDuration` field reports the speed at swing completion. The next cycle needs exactly this value. | SotC trial, 2026-09-25 |
| Player `UNIT_SPELLCAST_SUCCEEDED` carries **plain, classic-era spell IDs** in open-world combat (19/19 casts recorded readable). | Slice and Dice session, build 70124 |
| `UNIT_ATTACK_SPEED` fires at real attack-speed transitions: application of dynamic haste, expiry of dynamic haste, weapon swap. It does not fire on a refresh that changes no speed value. It fires twice per change (a long-standing quirk; every consumer must dedupe). | Builds 70124, 70205 |
| The engine implements the **classic parry-haste rule exactly**: more than 60% of the swing remaining cuts the remainder by 40% of the weapon speed; 20–60% floors the swing at 20% remaining; under 20% has no effect. | Combat-log-only read, 96 of 98 single-parry cycles, builds 70124 |
| The engine implements the **cast reset** (a completed cast restarts the swing) and the swing **hold during a cast**. | 2026-09-25 trial: swing landed at cast completion + weapon speed (predicted within 0.05 s) |
| The engine applies haste in **two families**. Dynamic family (Slice and Dice): the in-flight swing is rescaled, in both directions — measured periods match proportional-remaining math within event jitter (13 gain windows, 5 expiry windows). Snapshot family (Seal of the Crusader, druid forms): the in-flight swing completes on its old speed; the new speed applies from the next swing (7 control windows). | Same-day captures, build 70124 |
| `GetComboPoints("player","target")` reads **plain positive values mid-combat** at the cast instants. | Build 70205, `CP at-snd` probes |
| The combat-enter instant still reads **plain** speeds. The restriction flip lands a moment after `PLAYER_REGEN_DISABLED`. | Build 70205 morning session |
| `PLAYER_SWING` is player-only. No target variant exists, so a target swing timer is impossible on this client. | `/api search swing`, build 70009 |

### 2.1 Open anomalies (single occurrences, recorded for completeness)

- One Slice and Dice expiry window overshot the new full speed by +0.085 s
  (single occurrence, build 70124, unexplained).
- One capture recorded five `PLAYER_SWING` events ~0.2 s apart, each with the
  player's weapon speed — not auto-attack cadence; the trigger is unknown
  (2026-09-28 hunter capture).

## 3. Issues, with evidence and asks

### 3.1 Weapon-speed reads go secret in all combat

**Finding.** `UnitAttackSpeed` and `UnitRangedDamage` return secret values in
**all combat** — open world and instanced. Out of combat the same reads are
plain, including live hasted values at the combat-leave instant. The combat-enter
instant still reads plain; the flip lands after the event.

Consequence: an addon cannot compare a fresh speed read against a cached one,
and it cannot compute `lastSwing + speed`, at any time while fighting. The
classic rescale math (`timeLeft = remaining * newSpeed / oldSpeed`) has no data
source in combat on this client.

**Ask.** Any one of:

1. Keep `PLAYER_SWING`'s plain duration as a documented contract (it already
   holds mid-fight in restricted content), and confirm it will stay plain; or
2. Expose a sanctioned secret-safe path for attack speed (a duration object
   under `C_DurationUtil`, or a plain speed field on a speed-change event —
   see 3.3); or
3. Scope the stat secrets to restricted content only, as announced for retail
   Midnight, instead of all combat.

**Evidence.** Build 70009 probe matrix (FOREVER_API_FINDINGS 4.2); re-verified
build 70205 (SPEED lines in `SwingTestLog-forever-2026-10-04.lua`).

### 3.2 Aura data is hidden mid-combat; the NeverSecret whitelist is empty for swing-relevant auras

**Finding.** With a haste aura active on the player, mid-combat:

- `C_UnitAuras.GetPlayerAuraBySpellID(5171)` returns nil.
- `C_UnitAuras.GetAuraDataByIndex` throws "Auras cannot be accessed when
  secret".
- `C_UnitAuras.GetAuraDataBySpellName` returns nil — including at the aura's
  own application instant.
- `C_UnitAuras.GetAuraCount` does not exist on this client.
- `UNIT_AURA` itself fires correctly at every application and removal instant.

The same calls return full plain data (spell ID, applications, plain duration
and expiration) the instant combat ends. The channel is complete; only the
classification switches it off. Every aura probed answers
`C_Secrets.GetSpellAuraSecrecy` with `Enum.SecrecyLevel.ContextuallySecret` (2):
Slice and Dice (5171), Seal of the Crusader (20162), Redoubt (20128), Devotion
Aura (10290), Retribution Aura (7294), Well Fed (1248406).

Consequence: an addon cannot know that a haste aura is present, and it cannot
know when the aura expires. Expiry timing is the single largest accuracy gap a
swing timer has on this client (see 3.3).

**Ask.** Classify the player's own self-haste auras
`Enum.SecrecyLevel.NeverSecret`: Slice and Dice, Flurry, Quick Shots ("Deadly
Aspects" on Forever). Retail already runs this process by community request —
Maelstrom Weapon received an exemption. The API path is fully functional on
this exact build; the classification alone would make these auras readable
mid-combat, with no other client change. This is the cheapest ask in the
report.

**Evidence.** Build 70124 probes; build 70205 by-name capture
(`SwingTestLog-forever-2026-10-04.lua`, the 19:38 rogue sessions);
`HASTE_APPLICATION_FINDINGS` section 7.1.

### 3.3 No API surfaces a mid-swing attack-speed change — the built-in bar is wrong too

**Finding.** The engine rescales the in-flight swing when dynamic-family haste
is applied or expires (section 2, verified). No API reports the change:

- `PLAYER_SWING` carries only the duration the swing started with. There is no
  update event. `PLAYER_SWING_UPDATE` does not exist (registration throws
  "unknown event").
- `UNIT_ATTACK_SPEED` fires at the change instants, but its payload carries
  only the unit token — no hand, no value. The values behind the event are
  secret in combat (3.1). The event is an edge, not a data source.
- The combat log is refused (3.8).
- Proc auras fire no `UNIT_SPELLCAST_SUCCEEDED` (verified with a Redoubt proxy
  capture: four applications, zero SUCCEEDED events on any spell ID), and aura
  data is hidden (3.2) — so proc haste has no signal at all.

The built-in swing timer has the same hole. `Blizzard_SwingTimer.lua` anchors
on `PLAYER_SWING` with `ResetSwingTimer(duration)` and never rescales a running
bar; its `UNIT_ATTACK_SPEED` handler only updates range-check registration and
shown state. Reproduced on a training dummy:

- Cast Slice and Dice mid-swing: the built-in bar runs long; the swing lands
  early while the bar is still draining.
- Let Slice and Dice expire mid-swing: the bar reaches zero and clears while
  the swing is still resolving.

**Ask.** Any one of these closes the gap:

1. A speed-change event for swing timers (for example the nonexistent
   `PLAYER_SWING_UPDATE`, or a mid-swing re-fire of `PLAYER_SWING`) that
   carries the new duration and the change instant; or
2. The NeverSecret classification of 3.2 — presence plus expiry timing then
   read directly from the aura; or
3. Add the hand and the new speed value to the `UNIT_ATTACK_SPEED` payload
   (even a secret-safe duration object would do; widgets already accept those).

**Evidence.** `HASTE_API_BUG_REPORT.md` (filed draft);
`HASTE_APPLICATION_FINDINGS` sections 2 and 7.1; the same captures as 3.1.

### 3.4 The C_SwingTimer range subsystem is dead

**Finding.** Both channels of the range subsystem are non-functional:

- `PLAYER_SWING_RANGE_UPDATE` fires exactly once, at the
  `C_SwingTimer.EnableRangeCheck(swingType, true)` call, with the initial state
  `(0, false, false)`. It never fires again. Walking in and out of melee range
  produces no events.
- `C_SwingTimer.IsTargetWithinSwingRange(swingType)` returns nil with a target
  selected, in melee range, and out of range, after the enable call.

`PLAYER_SWING` works reliably on the same build, so the swing event wiring is
fine; the range subsystem alone appears unwired after the initial push.

Impact: `Blizzard_SwingTimer` implements its out-of-range presentation through
this subsystem (alpha 0.4, red label). With the event dead and the query nil,
the built-in swing timer cannot show out-of-range state on this build. Every
addon implementation is equally blocked.

**Ask.** Is the range subsystem intended to work in the beta? If the event is
the intended channel, its wiring looks missing after the enable call. If the
query is the intended fallback, it must return range state instead of nil.

**Evidence.** Builds 70009 and 70205; `RANGE_API_BUG_REPORT.md` (filed draft).

### 3.5 PLAYER_SWING fires before the swing resolves

**Finding.** Same-channel measurement (the trace only, no clock join): the
swing's own `UNIT_COMBAT` damage event arrives a median 0.451 s (2.4 s weapon)
and 0.486 s (3.4 s weapon) after `PLAYER_SWING`. The lead is roughly constant,
not weapon-proportional. The combat log records the attempt a further
0.13–0.23 s later. Total: ~0.65 s from the event to the logged attempt.

The generated API documentation declares the event `SynchronousEvent = true`
and gives no description of what it marks. Blizzard's own bar treats it as the
swing instant and adds no lead compensation.

Consequence: an addon that anchors on `PLAYER_SWING` and expects the landing at
`eventTime + duration` is systematically ~0.45 s late against the damage
record. Author-side correction today needs an undocumented ~0.65 s constant.

**Ask.** Document what `PLAYER_SWING` is supposed to mark. If the early fire is
intended, say so in the API browser entry. If not, align it with the swing
instant.

**Evidence.** 753 swing attempts, both weapon speeds, build 70124;
`PARRY_HASTE_BUG_REPORT.md` (filed draft, second edition).

### 3.6 UNIT_COMBAT PARRY dispatch lags; no first-class parry event exists

**Finding.** The `UNIT_COMBAT` PARRY dispatch trails the combat-log record of
the same parry by 0.10 and 0.25–0.30 s (two clusters). Relative to the
`PLAYER_SWING` anchor, a `UNIT_COMBAT` parry stamp sits ~0.55–0.72 s after the
engine's parry instant. Consequence: on a 2.4 s weapon, a floor-band parry's
`UNIT_COMBAT` event can arrive after the already-hasted `PLAYER_SWING`.

`COMBAT_TEXT_UPDATE` fires with `combatTextType == "PARRY"` (independently of
floating-combat-text settings), but:

- `GetCurrentCombatTextEventInfo()` returns nil on this build — no payload.
- The `CombatText` system exposes zero functions; `/api dump CombatText` fails.
- No field discriminates the parry direction (the player parried vs the
  player's attack parried). Parry haste belongs to the parrying unit only, so
  an addon must filter the direction.

An author who combines `PLAYER_SWING` with combat events for mid-swing
adjustments needs an undocumented ~0.65 s correction (0.45 s lead + 0.10–0.30 s
lag) and a direction heuristic.

**Ask.**

1. Say whether the `UNIT_COMBAT` dispatch latency is intended.
2. Populate `GetCurrentCombatTextEventInfo()`, or ship a first-class
   `PLAYER_PARRY` event with direction. This removes the need to reconstruct
   parry timing from skewed streams.

**Evidence.** 108 player parries, both weapon speeds, build 70124;
`PARRY_HASTE_BUG_REPORT.md` (filed draft and amendment, both filed).

### 3.7 The combat log is refused silently, and the restriction is always on

**Finding.**

- `RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")` returns `false` from addon
  code, with no error. On this beta, `C_CombatLog.IsCombatLogRestricted()`
  returns `true` for the whole session — out of combat, in the open world. The
  announced retail scoping (boss encounters and Mythic+) is narrower than what
  the beta enforces.
- The two refusal modes are distinguishable only by experiment: an unknown
  event throws "Attempt to register unknown event"; a restricted event silently
  returns false. `COMBAT_LOG_EVENT_BASIC` is confirmed nonexistent (it throws).

**Ask.**

1. Confirm the always-on combat-log restriction is the beta intent, or scope it
   as announced.
2. Document the refusal modes (silent false vs throw) so addons can tell a
   typo from a restriction.

**Evidence.** Build 70009 probes; re-checked 2026-09-25 and 70205 sessions.

### 3.8 Forever identifies itself as mainline

**Finding.** Forever reports `WOW_PROJECT_ID = 1` (`WOW_PROJECT_MAINLINE`)
while it runs a classic ruleset. `LE_EXPANSION_LEVEL_CURRENT` does not separate
it either. An addon can distinguish Forever only through `GetBuildInfo()`
("1.6.0.x").

Related identity issues:

- The auto-attack toggle fires `UNIT_SPELLCAST_SUCCEEDED` with spell ID
  **6803** on Forever; classic uses 6603. The difference is undocumented.
- Classic-era aura spell IDs are renumbered (Devotion Aura 10290 vs 465,
  Retribution 7294 vs 7291). Classic+ additions use new 7-digit ranges
  (~1222xxx–131xxxx). No published reference lists them.

Consequence: an addon that keys on project ID loads retail behavior into a
classic-ruleset game. Ours did exactly that before we patched it.

**Ask.**

1. Give Forever its own project identifier, or document a supported detection.
2. Publish the Classic+ spell ID ranges, or route them through the existing
   community data channels.

**Evidence.** Build 70009 probes; 2026-09-28 toggle capture; datamine
cross-checks (FOREVER_API_FINDINGS section 9 item 5).

### 3.9 Payload secrecy is inconsistent between spellcast events

**Finding.** Mid-fight in a dungeon, the target's `UNIT_SPELLCAST_START` spell
ID came back **secret**; the handler's spell-ID table lookup raised "attempted
to index a table that cannot be indexed with secret keys". In the same period,
player `UNIT_SPELLCAST_SUCCEEDED` IDs read plain in open-world combat. Which
event/unit pairs go secret mid-fight is not documented.

**Ask.** Document which spellcast payload fields are secret, per event and per
unit, and when.

**Evidence.** Live Lua error, 2026-09-29 (BugSack locals: `spell=<secret
number>`); FOREVER_API_FINDINGS section 4.3 correction.

### 3.10 The built-in swing timer models only the anchor

Context, not a defect by itself: `Blizzard_SwingTimer.lua` re-anchors on each
`PLAYER_SWING` and renders the countdown. It has no cast reset, no pause, no
clip, no parry haste, no movement retry, and no death handling. The engine rules
it does not model are live (section 2). This is why swing-timer addons exist,
and why the API gaps above have no first-party workaround: the first party's
own bar is a per-anchor renderer, not a swing model.

## 4. One-minute reproduction (for the triager)

Rogue on a training dummy, built-in swing timer enabled (Edit Mode):

1. Auto-attack. Note the bar cadence.
2. Cast Slice and Dice mid-swing. Expected: the bar shortens. Actual: the bar
   does not move; the swing lands early while the bar is still draining.
3. Let Slice and Dice expire mid-swing. Expected: the bar lengthens. Actual:
   the bar reaches zero and clears while the swing is still resolving.

Range subsystem:

1. `/run C_SwingTimer.EnableRangeCheck(0, true)`; register
   `PLAYER_SWING_RANGE_UPDATE` and print its payload.
2. Walk in and out of melee range. Actual: one initial fire at the enable
   call, then nothing.
3. `/run print(C_SwingTimer.IsTargetWithinSwingRange(0))` in and out of range.
   Actual: nil both times.

## 5. What the two projects had to build to compensate

This section shows the cost of the gaps, in shipped code. None of this would
be needed if any one ask in section 6 lands:

- A per-spell dynamic-haste table, learned by capture (Slice and Dice rank 1
  = factor 1.2, measured both hands). Every new haste source needs a capture
  before the bar can mirror it.
- A cast-based rescale: the library applies the factor at the
  `UNIT_SPELLCAST_SUCCEEDED` instant of a table spell.
- A transition-parity state machine on the `UNIT_ATTACK_SPEED` edge: on an
  unexplained fire while a dynamic source is tracked, the library un-hastens
  immediately with progress-preserving lengthening, because no expiry signal
  exists (the event carries no hand and no value; the classification windows
  do the attribution).
- A combo-point chain for Slice and Dice expiry: duration is a known function
  of the points at cast (9 + 3(n-1), engine-verified), the fade edge is
  watched inside a ±0.25 s window, and the next anchor settles any
  misattribution.
- A candidate/settler design for probabilistic procs ("Deadly Aspects", 10%
  per ranged attack): the edge arms a tentative factor; the next anchor's
  plain duration confirms or reverts it.
- A parked-tick convergence sweep, because a swing seeded at login can never
  land (auto-attack does not survive a reload), and the one-swing lag hides
  stale state at the parked position.
- Secrecy guards on every legacy speed read, plus secret-safe spell-ID
  routing on all `UNIT_SPELLCAST_*` handlers.

## 6. Consolidated asks, in priority order

| # | Ask | Effort for Blizzard | Closes |
|---|---|---|---|
| 1 | Classify the player's self-haste auras `NeverSecret` (Slice and Dice, Flurry, Quick Shots). Precedent: Maelstrom Weapon on retail. | Data only; no code change | 3.2, most of 3.3 |
| 2 | A speed-change event for swing timers: new duration + change instant (`PLAYER_SWING_UPDATE`, a mid-swing re-fire, or hand+value fields on `UNIT_ATTACK_SPEED`). | One event | 3.1, 3.3 |
| 3 | Fix the `C_SwingTimer` range subsystem (the event after the enable call; the query's nil return). | Bug fix | 3.4, the built-in bar's out-of-range state |
| 4 | Document `PLAYER_SWING` semantics (the ~0.45 s pre-resolution lead) and the `UNIT_COMBAT` dispatch latency; state whether they are intended. | Documentation | 3.5, 3.6 |
| 5 | Populate `GetCurrentCombatTextEventInfo()`, or ship a `PLAYER_PARRY` event with direction. | Event/payload | 3.6 |
| 6 | Confirm the always-on combat-log restriction for the beta; document the silent-false refusal mode. | Statement | 3.7 |
| 7 | Give Forever its own project identifier or a documented detection; publish the Classic+ spell ID ranges. | Data/flag | 3.8 |
| 8 | Document which spellcast payload fields go secret, per event and unit. | Documentation | 3.9 |
| 9 | Confirm `PLAYER_SWING`'s plain payload is a contract, and keep it plain. | Statement | Protects section 2 |

## 7. Evidence and method

All captures are verbatim copies from the live beta client. No transcription,
no screenshots as data. The archive lives in the library repository under
`docs/evidence/`:

- `WoWCombatLog-2026-09-30.txt` (4.2 MB) — the client's own advanced combat log;
  753 player swing attempts, 108 player parries, two weapon speeds.
- `trace-2026-09-30.lua` / `4everSwingTimer-2026-09-30.lua` — SavedVariables
  event traces: `PLAYER_SWING`, `UNIT_COMBAT`, spellcasts, library callbacks,
  millisecond timestamps; 19,564 events.
- `WoWCombatLog-093026_154137.txt` — the Slice and Dice and Seal of the
  Crusader sessions (227 + 13 swing attempts).
- `SwingTestLog-forever-2026-10-02.lua`, `SwingTestLog-forever-2026-10-04.lua`
  — the harness captures: dual-wield off-hand, death parking, the by-name aura
  probe, the combo-point chain, the `UNIT_ATTACK_SPEED` instrumentation.
- `SwingTestLog-classic-era-2026-10-02.lua` — the Classic Era regression pass
  (10 sessions, warrior and hunter), which confirms the library behavior is
  unchanged on classic clients.

Method notes:

- The decisive parry analysis reads swings and parries from the combat log
  alone — one file, one clock, no cross-stream join.
- The haste analysis reads anchor-to-anchor `PLAYER_SWING` periods from a
  single trace channel, so the dispatch lead cancels.
- Parry dispatch offset and the `PLAYER_SWING` lead are documented per capture
  session, so the streams are never mixed when an engine rule is measured.

We can walk through any capture on the WoW UI Dev Discord.
