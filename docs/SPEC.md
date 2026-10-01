# 4everSwingTimer — Addon Specification (v1 draft, decisions applied 2026-09-28)

Status: spec for 4everSwingTimer, now living in the addon repo it belongs to.
Implemented: v1 scaffold (2026-09-28, see CHANGELOG.md). Scope amendment the
same day, at implementation time: **Forever only** — classic-flavor support was
dropped to halve the verification surface and keep the TOC single-flavor; the
earlier all-flavors decisions below are kept for the record.

Companion documents: `FOREVER_API_FINDINGS.md` (API investigation, referenced
as §N) and `IMPROVEMENT_PLAN.md`.

Decisions applied in this revision:

- Name: **4everSwingTimer** (TOC/distribution name; saved-variable global named
  separately, see section 5).
- Scope: all flavors the library supports. **Superseded 2026-09-28: Forever
  only** — see the status note above.
- Library dependency: **embedded via packager externals** (`.pkgmeta`), pinned to a
  tag.
- Options UI: **hand-rolled Interface Options panel** for v1; revisit Ace3 if the
  options surface grows (see section 9).

## 1. Purpose and motivation

LibClassicSwingTimerAPI `2.2.0-beta2` provides verified swing state on WoW: Forever,
but it is a library — it renders nothing. On other flavors, WeakAuras covers the
display gap (see README aura examples). On Forever that path is closed:

- WeakAuras halted development before Midnight; it does not run on Forever.
- The native Blizzard swing timer (`C_SwingTimer`, `showSwingTimer` CVar) exists on
  Forever/mainline but offers only its fixed EditMode styling.

The addon's job: render the library's player swing state as configurable bars on
WoW: Forever. It is the reference consumer of the library's Forever path and the
first-party end-user product the library currently lacks. (Classic flavors are
out of scope — WeakAuras covers them there, and a Forever-only TOC halves the
verification surface; see the status note.)

## 2. Goals and non-goals

### Goals (v1)

- Show main-hand, off-hand and ranged swing bars driven exclusively by the library's
  `UNIT_SWING_TIMER_*` events and `UnitSwingTimerInfo`.
- Bars only for hands that actually swing: no off-hand bar without dual wield, no
  ranged bar without a ranged weapon, nothing outside combat when idle.
- Clear visual language for the library's extra states: clipped and paused swings.
- Draggable, scalable, lockable; text options (remaining time, speed, hand label).
- Configuration via a standard Interface Options panel and a slash command.
- Zero Lua errors across the library's Forever caveats (secret values, death
  reset, movement-cancelled Auto Shot).

### Non-goals (v1)

- **Target swing bars.** Forever has no data source (§1, §4.4), and v1 stays
  player-only. A target-bar feature would require the classic-flavor support
  the Forever-only scope dropped; revisit only if the addon ever re-expands.
- Parry-haste prediction, mid-swing rescale, or any second-guessing of the library's
  state. The bar mirrors the library; the library owns the model.
- WeakAuras emulation, combat log reconstruction, or direct `PLAYER_SWING` handling.
  The addon talks only to the library API.
- Profiles, import/export of layouts, theming skins.

## 3. Target platform

**WoW: Forever only** (amended 2026-09-28 at implementation time):

```
## Interface: 16001
```

The build number bumps per client, exactly as the library's TOC does. With the
Forever-only scope there is no flavor-gated addon code at all: the native-timer
notice (section 4.5) always applies, and the `ui-swingtimerbar-*` atlases are
guaranteed present on the target client.

- Dependency: LibClassicSwingTimerAPI >= 2.2.0 (embed the latest beta while the
  library's Forever support is in beta; track the stable release when cut). The
  library's LibStub MINOR is the real gate: require the minor that contains the
  Forever path, via LibStub's minor-version resolution at load.
- LibStub and CallbackHandler-1.0 pulled by the packager (`.pkgmeta` externals),
  same pattern as the library repo.
- Flavor behavior comes from the library; the addon contains no per-flavor swing
  logic.

## 4. Feature specification (v1)

### 4.1 Bars

Three bar types, one frame each, stacked under a single anchor:

| Bar | Shown when | Data source |
|---|---|---|
| Main-hand | main-hand swing active | `UnitSwingTimerInfo("player", "mainhand")` |
| Off-hand | dual wield, off-hand swing active | `UnitSwingTimerInfo("player", "offhand")` |
| Ranged | ranged swing active (Auto Shot, wand) | `UnitSwingTimerInfo("player", "ranged")` |

Bar behavior:

- Fill direction drains from full to empty as the swing completes (classic swing
  timer convention; configurable to fill-up in options).
- Remaining-time text with one decimal, optional speed display, optional hand label.
- Smooth per-frame update from `expirationTime` and `speed` (OnUpdate or a shared
  ticker); no arithmetic beyond `expirationTime - now` — both values are plain
  numbers by the library's verified contract (§4.5).
- `UNIT_SWING_TIMER_START` shows and starts a bar; `UNIT_SWING_TIMER_STOP` empties
  and hides it (or parks it, per a "keep visible while in combat" option).
- `UNIT_SWING_TIMER_UPDATE` re-anchors the bar mid-flight (movement-cancelled Auto
  Shot reschedules on Forever, §8.9; weapon-speed changes on classic flavors).
- `UNIT_SWING_TIMER_PAUSED` tints the bar (e.g. desaturate + pause icon/text);
  `UNIT_SWING_TIMER_STOP` on the paused hand restores the default tint.
- `UNIT_SWING_TIMER_CLIPPED` flashes the bar once and restarts it from the new
  swing.
- Death: the library fires STOP per active hand on every client; bars follow, no
  special handling.
- Parry haste: the library shortens the bar mid-swing once it includes the
  parry fix (UNIT_COMBAT, library section 8.10); the bar re-anchors at the
  UPDATE and the teal stack fires at the parry. Library builds without the
  fix apply the haste only at the next swing - the addon's early-landing
  detection covers those, so no flavor or version branch is needed.
- Ranged dynamic haste: a successful dynamic-family cast (Rapid Fire-class)
  rescales the in-flight shot (library 2.2.0-beta3+); the ranged UPDATE's
  shortened landing fires the same teal stack. The movement-reschedule
  window keeps precedence - a ~0.5 s recast still reads as the amber delay,
  so a rescale late in a short remaining swing can land inside it and read
  as a reschedule.

### 4.2 Visibility model

Mirrors the native bar's EditMode visibility modes (section 10.1) — standard
semantics and naming users already know from the client:

- **In combat** (default): bars follow `UnitAffectingCombat("player")`; empty bars
  stay parked and visible between swings within a fight, hidden outside combat.
- **While swinging**: bars appear on START, hide on STOP (the pre-research model).
- **Always**: bars visible whenever the hand has state (weapon equipped), even empty.

### 4.3 Delta indicator (optional, minimal)

`UNIT_SWING_TIMER_DELTA` provides the MH/OH swing delta in seconds. v1 renders it
as an optional text field on the off-hand bar (e.g. `+0.21s`), default off. Dual
wielders are the only audience; keep it one font string, no alignment tooling.

### 4.4 Configuration

- Hand-rolled Interface Options panel plus a slash command `/4everswingtimer`
  (slash command names may start with a digit; verify in client) with a
  `/everswing` alias. Note: `/wst`, `/st` and `/fst` are all taken by existing
  swing timer addons — do not reuse them (section 10.2).
- Settings: enable per-hand bars, anchor position (drag while unlocked), scale, bar
  width/height, fill direction, texture (small shipped set; the game's shared
  media where available), text toggles, show/hide rules, lock toggle.
- Saved per-character. The saved-variable global must be a valid Lua identifier:
  declare `## SavedVariables: ForeverSwingTimerDB` — the addon name (TOC) stays
  `4everSwingTimer`, but `4everSwingTimerDB` is not a valid Lua identifier, so the
  DB global is accessed via a name that is.
- "Test bars" button: animates a fake 2.0s swing on all three bars for layout work
  without combat.
- Effect previews (`test interrupt|haste|delay|queued`, overlay effect buttons):
  each reproduces its real event signature on a fake swing scoped to the
  effect's hands - the interrupt restarts the swing (cast reset), the haste
  shortens the swings on all hands (parry UPDATE on melee, dynamic-haste
  rescale on ranged, early landing), the delay replays
  the movement-cancel retry at the ranged swing's landing (the bar
  completes, cannot fire, pulls back ~0.5 s and lands at the retry), the
  queued highlight rides a swinging main-hand bar and clears when the swing
  lands - the landing swing consumes the queue (the queued-state poll is
  held off while it runs). On a live swing the plain treatment fires
  directly; test data never rewrites live state.

### 4.5 Coexistence with the native swing timer

The native bars (`showSwingTimer` CVar / `C_SwingTimer`) exist on Forever. v1
behavior:

- Do not silently change the CVar.
- One-time chat notice when the addon first loads with the native timer enabled:
  native bars detected, command hint to disable them
  (`/console showSwingTimer 0`) or hide the addon bars instead.

## 5. Architecture

```
4everSwingTimer/
├── 4everSwingTimer.toc       multi-flavor Interface lines (section 3), SavedVariables:
│                             ForeverSwingTimerDB, X-Wago/Curse IDs
├── Core.lua                  bootstrap, LibStub acquisition, callback wiring, state
├── Bars.lua                  bar frames, update loop, visual states
├── Options.lua               hand-rolled options panel + slash command
├── Defaults.lua (or table in Core)  default settings + saved-variable migration
├── .pkgmeta                  externals: LibStub, CallbackHandler-1.0,
│                             LibClassicSwingTimerAPI (git tag pin)
├── .github/workflows/release.yml  BigWigs packager v2, tag-triggered
└── LICENSE
```

- Event wiring exactly as the library README prescribes: register the seven
  `UNIT_SWING_TIMER_*` callbacks on one handler frame; a missing library
  (`LibStub("LibClassicSwingTimerAPI", true)` returns nil, or a MINOR below the
  Forever path) makes the addon load inert with a chat message — never an error.
- The addon holds no swing math of its own. All state reads come from
  `UnitSwingTimerInfo("player", hand)` at render time.
- CRLF + tabs, `local` everywhere — match the library repo's conventions.
- Keep the package dependency-free beyond the three externals (LibStub,
  CallbackHandler, the library).

## 6. Flavor-specific constraint handling (UX-facing summary)

Library-level facts the addon must present honestly, not hide:

| Constraint (verified) | Addon behavior |
|---|---|
| Library builds without the parry fix apply parry haste at the next swing, not mid-swing | Bar may overshoot after a player parry on those builds; self-corrects at next START. With the fix the bar re-anchors mid-swing and the teal stack fires at the parry. |
| Weapon-speed changes never rescale an in-flight swing (dynamic-haste rescales do, library beta3+, on successful dynamic-family casts) | UPDATE mid-swing is rare by design; the reschedule window classifies the ~0.5 s retry as the amber delay, a shortened landing outside it fires the teal haste pop, and the bar follows the new expiry either way. |
| Target tracking unsupported | No target UI at all (non-goal in v1). |
| Secret values in combat | Library-owned concern; the addon never reads `UnitAttackSpeed`/`UnitRangedDamage` directly, so nothing to guard. |
| Off-hand dual-wield anchoring unverified in lib beta | The addon is the natural test rig: if OH never fires on a dual wielder, file upstream; the addon needs no change. |
| Wand users assumed covered by the lib | Addon-agnostic; test with a wand anyway. |

## 7. Verification checklist (in-game)

Forever beta:

1. Fresh login: no bars, no errors, native-timer notice only if CVar enabled.
2. Melee dummy: MH bar appears per swing, drains, disappears; cadence matches
   weapon speed; no drift over 20+ swings.
3. Dual wield: both bars, correct labels, delta text optional field sane.
4. Hunter: ranged bar per Auto Shot; strafe mid-shot reschedules once (UPDATE);
   no double-drain; a mid-swing Rapid Fire rescales the shot with the
   teal haste pop (the shortened landing outside the reschedule window).
5. Cast mid-swing (any reset spell, e.g. Flash of Light): CLIPPED flash + restart.
6. Channel/pause-class spells: PAUSED tint, resume or STOP per library.
7. Weapon swap mid-combat: current bar finishes, next START uses new speed.
8. Death + in-place resurrection: bars stop cleanly, next swing starts fresh.
9. Dungeon mid-fight (restricted content): no Lua errors; bars stay accurate
   (the library's payload is plain — §4.5 — so this should be uneventful).
10. Options: every toggle applies live; test-bars button works; reload keeps
    position and settings (SavedVariables).
11. Library missing/disabled: addon loads inert with its chat notice, no error.
12. Effect previews out of combat: `test interrupt` restarts the fake swing
    (red flash, bar back at the top for a fresh duration), `test haste`
    shortens the swings on all three hands (teal flash, bars re-anchor
    and park at the early landing), `test delay` replays the retry on the ranged bar only
    (amber flash at the swing's landing, bar completes, pulls back and
    lands ~0.5 s later), `test queued` lights mid-swing and clears when the
    swing lands (the landing swing consumes the queue); mid-combat the
    effects fire on the live bar without rewriting its state; `test
    effects` plays one effect per swing window with no double feedback at
    any swing's end. Repro the reload case: reload while a swing is in
    flight, then trigger any effect before a Swing test - the preview must
    still start its fake swing rather than firing on the stale
    active-but-landed bar that pre-beta4 library builds left behind.
13. Stale landing convergence: with a library build older than 2.2.0-beta4
    (whose login seed manufactured an in-flight swing the engine can never
    complete; beta4 parks the seed, and the convergence stays as the
    defense), reload mid-swing - the bar must drain to its end, hold briefly (the
    ranged movement retry needs that window), then park itself within ~1 s
    of the landing: parked fill position, parked text, hidden in the
    "while swinging" visibility mode, no stuck tick at the fill's edge and
    no interrupt flash. A moving Auto Shot must still fire its amber delay
    burst at the re-anchor inside that window. The convergence must also
    happen with nothing on screen - a first login out of combat with the UI
    locked hides the anchor, and a hidden frame receives no OnUpdate, so the
    convergence runs on a C_Timer ticker (SweepStaleLandings), not only the
    update loop: log in fresh, wait, then enter combat - the bars must
    appear already parked correctly.
14. Parked tick at login: log in (or `/reload`) without swinging - in fill
    mode the parked bar sits at "ready" (full) with its tick at the fill's
    right edge, not at the far left; in drain mode it sits empty with the
    tick at the left, matching a normally landed swing's parked state. The
    first swing must find the tick at the correct parked position. Verify on
    a first-time login too (fresh client start, not just `/reload`), and
    with the UI locked from the previous session. The parked pair is
    re-applied on every visibility pass, so the tick must also converge
    after equipment streaming or world entry, not only at the init pass.

(Classic Era and retail 12.x checklist items were dropped with the Forever-only
scope amendment.)

## 8. Distribution

- GitHub repo, tag-triggered BigWigs packager releases to CurseForge and Wago
  (mirror of the library repo's pipeline). License: same as the library.
- Versioning: 1.0.0 at first release if the library's Forever support has gone
  stable by then; 1.0.0-beta1 if shipping against the library beta.
- README: end-user facing, with the constraint table from section 6 as an FAQ.

## 9. Decisions and remaining open items

Resolved (2026-09-28):

| Decision | Outcome |
|---|---|
| Name | `4everSwingTimer`; saved-variable global `ForeverSwingTimerDB` |
| Flavor scope | All flavors (superseded 2026-09-28: **Forever only**, see status note) |
| Library dependency | Embedded via `.pkgmeta` externals, pinned to a tag |
| Options UI | Hand-rolled panel; switch to AceConfig-3.0 only if the panel exceeds ~15 controls or needs search/profiles |

Remaining open (advisory, none block repo creation):

1. CurseForge/Wago name-uniqueness check for `4everSwingTimer` — do before
   publishing, not before coding. Known: "ForeverSwingTimer" is taken on GitHub
   (RevoltLive85, single-commit backup repo, no releases — section 10.2);
   `4everSwingTimer` is distinct from it and every listed addon.
2. Bar default style (drain-down recommended) and shipped texture set — decide
   during implementation, both are options anyway.
3. Delta feature in or out of v1: recommendation in, minimal form (one optional
   text field), since dual wielders are the core audience of any swing timer.
4. Slash-command acceptance of a leading digit (`/4everswingtimer`) — verify in
   client; `/everswing` is the fallback alias. `/fst` was withdrawn: it belongs to
   "Minimalistic Weapon swing timer Forever" (section 10.2).

## 10. Design research (2026-09-28): native bar and shipped addons

Sources read from primary material: Blizzard `Blizzard_SwingTimer.lua` + `.xml`
(Gethe/wow-ui-source, `forever` branch, build 1.60.1 / 70009 — the exact code
shipped in the Forever beta client); addon pages/repos as cited. Cross-checked
against the existing analysis in `IMPROVEMENT_PLAN.md` section 5.

### 10.1 Blizzard `Blizzard_SwingTimer` — the actual shipped build

Architecture (from source):

- `SwingTimerManagerFrame` + three per-hand frames (`SwingTimerMainHandFrame`,
  `SwingTimerOffHandFrame`, `SwingTimerRangedFrame`) on
  `EditModeSwingTimerSystemTemplate` + `BottomManagedFrameTemplate` — anchored
  and sized by Edit Mode, parked above the action bar (layoutIndex 9–11).
- Everything is gated on the `showSwingTimer` CVar via `CVarCallbackRegistry`;
  `PLAYER_SWING` itself is registered only when the CVar is on AND a frame is
  actually handling swings — Blizzard does event registration gating by
  weapon-presence + visibility mode.
- Visibility modes (EditMode enum): **Always / InCombat / Hidden**, combat via
  `UnitAffectingCombat("player")`.
- Weapon gating: off-hand frame requires `UnitAttackSpeed` second return > 0;
  ranged frame requires the third return > 0 — the same third-return source the
  library now reads (IMPROVEMENT_PLAN §2), confirmed here in Blizzard's own code.

Visual language (from XML):

- Atlas set `ui-swingtimerbar-*`: `background`, `frame` (border), `pip`, and
  **per-hand fill textures** `filling-mainhand`, `filling-offhand`,
  `filling-ranged` — each hand is a different color in the native bar.
- The bar **fills up** over the swing: `SetValue((swingDuration - remaining) /
  swingDuration)` from 0 at swing start to 1 at impact; a small Pip texture rides
  the leading edge of the fill.
- `TypeLabel` (localized hand name, left) + `TimeLabel` (remaining, `%.1f`,
  right), both `GameFontHighlightSmall`.
- Out-of-range presentation: whole bar alpha 0.4 + red font color, driven by
  `PLAYER_SWING_RANGE_UPDATE` with `C_SwingTimer.IsTargetWithinSwingRange` as
  fallback query on target change. (The event is broken on the beta — §4.4 — so
  today the native out-of-range visual only updates via the query path.)

Behavioral gaps, confirmed from source (matches IMPROVEMENT_PLAN §5): per-swing
re-anchoring only. No cast-reset, no pause, no clip, no parry haste, no
movement-cancel retry, no death handling. **This is the differentiation axis for
4everSwingTimer**: everything the library reconstructs between two swings — cast
resets, pauses, clips, FAILED_QUIET reschedules — the native bar structurally
cannot show. A Blizzard forum thread already asks for native bar customization;
the native bar answers none of it.

Design borrowings for the addon:

- Ship a **"native style" skin** using the client's own `ui-swingtimerbar-*`
  atlases — zero texture shipping cost, guaranteed present on the Forever
  client, instant familiarity. Custom flat styles remain as alternatives.
- **Visibility model = the native three modes** (section 4.2, amended).
- Optional **out-of-range dimming** as a v1.1 candidate: mirror the native
  approach (query on `PLAYER_TARGET_CHANGED`, `EnableRangeCheck`), beta-flagged
  since the event is broken; degrade to query-only. Probe 2026-09-28: the query returns nil with a target in melee range and out of range after EnableRangeCheck - blocked upstream entirely, event and query both dead on this beta build; revisit with the Blizzard report.
- Fill direction stays configurable: default **drain** (classic addon
  convention, what the target audience is used to), with the native-style skin
  defaulting to fill-up to match the client's look.

### 10.2 Market landscape (CurseForge/Wago, download counts as displayed 2026-09-28)

| Addon | Where | Downloads | Key features | Runs on Forever? |
|---|---|---|---|---|
| WeaponSwingTimer (LeftHandedGlove) | CF | 2.2M | Player+target MH/OH, Slam resets, parry haste, hunter YaHT/OneBar shot bars, wand, `/wst` | No — CLEU-based, classic clients |
| WST SixxFix (watchyoursixx) | CF | 4.0M | Hunter-focused: white movement window, retry-timer display, haste-on-next-shot, FD resets, Aimed/Multi cast bars | No |
| WST WarriorQueuing | CF | 107K | HS/Cleave queued coloring, GCD spark 1.5s ahead, off-hand partial progress when not queued | No |
| SwedgeTimer (hypernormalisation) | CF/Wago | 93.4K | WotLK; per-class implementations, latency, GCD, buff/proc tracking, `/st` | No |
| My Swing Timer (Netha) | CF | 80.8K | Classic/SoD/TBC; MH/OH/wand/ranged, options, reset-settings button, updated Sep 2026 | No |
| SuperSwingTimer-WoW | (studied in IMPROVEMENT_PLAN §5) | — | Auto Shot cooldown anchor, latency cache, resync polls, autorepeat guards | No |
| **EllesmereUI v9.2.1** | CF | — | **Forever swing timer module** (the studied PR #2128, shipped): PLAYER_SWING + duration bindings, MH/OH/ranged, queued-attack highlight, Unlock Mode placement, off by default — inside a full UI suite | **Yes** |
| **AppelSwingsForever** | CF | 1.3K | **Skins the native bars**: 4 styles (Retail/Retail Grey/Forever/Vanilla), range checker, melee restarts ranged bar, off-hand only with a real weapon | **Yes** |
| **Minimalistic Weapon swing timer Forever** (Bogarne) | CF | 711 | **Skins the default bars**, `/fst` commands | **Yes** |
| **BetterSwingTimer** (MrGank) | CF | 460 | Standalone Forever bars: gradients, test mode, action-bar swipes, minimap controls, updated Sep 25 2026 | **Yes** |
| ForeverSwingTimer (RevoltLive85) | GitHub | 0 stars, 1 commit | Single-file backup, no release | Yes (negligible) |

Market reading:

- Swing timer demand is proven at scale on classic clients (the two WST lines
  alone exceed 6M downloads) — but none of the incumbents can run on Forever;
  they are CLEU-based classic clients' code.
- The Forever niche already has four shipped competitors, all young and small.
  None is driven by a swing-state reconstruction: AppelSwingsForever and
  Bogarne's addon are native-bar skins, BetterSwingTimer is a fresh standalone,
  EllesmereUI bundles one module inside a full UI replacement.
- Community signals: native swing timers arrived mid-beta (Reddit setup guides),
  CurseForge has a dedicated "forever" flavor tag, and a Blizzard forum thread
  requests bar customization the native UI does not offer.

**Positioning statement for 4everSwingTimer**: the only dedicated, standalone
Forever swing timer driven by mid-cycle swing reconstruction (cast resets,
pauses, clips, FAILED_QUIET reschedules) rather than per-swing re-anchoring —
accurate *between* swings, where the native bar and every current competitor are
wrong by design.

### 10.3 Feature-exchange matrix → design decisions

| Incumbent feature | In 4everSwingTimer? | Rationale |
|---|---|---|
| MH/OH/ranged bars with weapon gating | v1 (already spec'd) | Universal across all incumbents and the native bar. |
| Target swing bars | Deferred | Proven demand (WST's headline feature), but no Forever data source and the classic-flavor scope was dropped. |
| Hunter "white window" (YaHT) movement state | v1.1 candidate | On Forever a mid-swing ranged UPDATE is the FAILED_QUIET reschedule — a "delayed/retry" tint is derivable addon-side with no library change; the full white-window model needs cast-window data the library does not expose yet. |
| Queued-attack coloring (HS/Cleave) | v1.1 candidate, probe-gated | `C_Spell.IsCurrentSpell` addon-side (EllesmereUI precedent, base IDs 78/845/6807); unprobed on Forever, may be restriction-affected. |
| GCD spark (1.5s ahead of swing) | Rejected on Forever; not v1 anywhere | Cooldown timings are secret values in restricted content (§4.2); on classic flavors WeakAuras covers this. |
| Latency compensation (SuperSwingTimer, SwedgeTimer) | Rejected | The library's PLAYER_SWING anchoring is event-accurate; latency math adds complexity for no accuracy gain. |
| Per-class implementations (SwedgeTimer) | Rejected | The library centralizes swing mechanics; class logic in the addon would duplicate it and drift. |
| Minimap button (BetterSwingTimer) | Rejected for v1 | Options panel + slash command suffice. |
| Native-style skin via shipped atlases | Yes — new default skin | Section 10.1. |
| Visibility modes Always/InCombat/Hidden | Yes — section 4.2 amended | Native naming and semantics. |
| Off-hand "real weapon in slot" gating | v1 via library events | The lib only fires off-hand events when dual wielding; AppelSwingsForever discovered the same edge independently. |

## 11. Roadmap and sequencing (decided 2026-09-28)

Two tracks, one dependency: the addon embeds the library, so the library's
stability gates the addon's GA — but not its development.

| # | Milestone | Blocks / parallel | Exit criteria |
|---|---|---|---|
| M1 | **One combined in-game session** — library §8.9 remainders (Forever dual-wield off-hand, wand, Classic Era regression + Era death-reset) AND IMPROVEMENT_PLAN §6 probes (Slam cast events with/without Improved Slam, Maelstrom Weapon aura ID) | Needs play time only; no code first | All four lib checklist items green; Slam/Maelstrom verdicts recorded; if verified, table changes applied as `2.2.0-beta3` |
| M2 | **Library 2.2.0 stable** — release prep (MINOR + `## Version` bump, `[Unreleased]` → versioned), tag, three-platform release | After M1 | Tag pushed, CurseForge/Wago/GitHub live; downstream consumers unblocked |
| M3 | **Addon scaffold + v1** — repo, TOC/pkgmeta, Core/Bars/Options per section 5, v1 features per section 4 | Parallel with M1/M2 — pure code, no game needed; embed lib pinned to the newest tag available | Loads inert with library missing; `luac -p` clean; test-bars button works on any client |
| M4 | **Addon beta on Forever** — spec §7 items 1–11; doubles as the rig for any lib remainder | After M3; benefits from M1's session learnings | Checklist green, no Lua errors; ship `1.0.0-beta1` to CurseForge/Wago beta channels |
| M5 | **Addon 1.0.0 GA** — name-uniqueness check, README + FAQ (constraint table), stable lib pin, tag/release | After M2 + M4 | `4everSwingTimer 1.0.0` on CurseForge/Wago against lib 2.2.0 stable |

Sequencing rationale:

- **The session (M1) is the scarce resource** — it needs the beta client and play
  time, so everything probe-dependent is bundled into it: the four remaining
  library checklist items and the two Classic+ spell candidates (Slam matters
  most: it is a Forever-warrior core spell, and a wrong reset there undercuts the
  addon's entire mid-cycle-accuracy positioning).
- **Ship the library stable before the addon GA.** The library has real
  downstream consumers on the tag pipeline, and the addon's packaging pins a
  library tag — a stable pin at GA beats a beta pin.
- **Develop the addon now anyway** (M3). Nothing in the scaffold needs the game,
  and the lib beta is sufficient to build against. Shipping the addon as
  `1.0.0-beta1` before lib stable is accepted — beta channel, small audience,
  and it is the fastest route to real Forever feedback (including the
  dual-wield and wand data the library still wants).
- **Forever timing pressure**: four competitors already shipped and the client
  is in live beta — the window where "the accurate swing timer" is unclaimed is
  open but not indefinite. M1–M4 should complete inside the beta period.

Explicitly deferred past this cycle (no re-litigating): library Phase 3 (classic
ranged accuracy via Auto Shot cooldown), the BCC divergence-guard probe, and the
addon v1.1 candidates (ranged delayed/retry tint, queued-attack coloring,
out-of-range dimming) plus target bars (deferred, section 10.3).
