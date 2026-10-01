# Back report — library-side resolution of the stale login swing

For 4everSwingTimer's implementation and packaging. Records how
LibClassicSwingTimerAPI resolved the issue this addon surfaced (the
stale "active" swing after `/reload`, `docs/upstream-stale-swing-report.md`),
the live verification, and what this repo does and does not need to change.
Not shipped in the package (`docs/` is a packager ignore).

## What changed in the library

`PLAYER_ENTERING_WORLD` (`LibClassicSwingTimerAPI.lua`) no longer
manufactures a swing at login. The old seed set
`expirationTime = lastSwing + weaponSpeed` on all three hands — a synthetic
"in flight" swing with no timer behind it, so its expiry passed without a
`UNIT_SWING_TIMER_STOP` and consumers held a stale active bar until the
next real swing. The seed now lands parked
(`expirationTime = lastSwing`), matching the `PLAYER_TARGET_CHANGED`
seed that has always parked the target. No event, method, or signature
changes; the fix is client-agnostic and rides LibStub MINOR 35 (beta3
shipped MINOR 34; MINOR 35 is unreleased at the time of writing).

## Live verification (WoW: Forever beta, build 70124, 2026-10-01)

Captured with SwingLoginProbe (a temporary probe addon that records the
login window from frame one — this addon's own trace cannot: its
recording flag resets on load, so login-instant events precede the re-arm).

### Scenario 1 — mid-swing `/reload` (auto-attack on before the reload)

| Time (s) | Event | Reading |
|---|---|---|
| 5394.086 | `PLAYER_ENTERING_WORLD` + `PLAYER_REGEN_DISABLED` | Reload done mid-combat |
| 5394.086 | `INFO_INITIALIZED` only | Parked seed: no `START`, no `UPDATE` |
| 5394.086–5396.944 | 2.9 s in combat, zero swing events | Auto-attack does not survive `/reload` |
| 5396.944 | attack toggle (6603) re-pressed | Player input |
| 5397.061 | `PLAYER_SWING` → `START 2.4 s` | Real swing, 117 ms after the toggle |

### Scenario 2 — pull without auto-attack, `/reload`, toggle on after login

| Time (s) | Event | Reading |
|---|---|---|
| 5616.950 | `PLAYER_ENTERING_WORLD` + `PLAYER_REGEN_DISABLED` | Reload done, mob aggro'd, not attacking |
| 5616.950 | `INFO_INITIALIZED` only | No `START`/`UPDATE`; `PLAYER_ENTER_COMBAT` does not fire at login |
| 5618.830 | attack toggle (6603) | Player input, ~1.9 s after login |
| 5618.946 | `PLAYER_SWING` → `START 3.4 s` | Real swing, 116 ms after the toggle |
| 5619.789 / 5625.690 / 5627.692 | three defensive parries → `UPDATE` | Parry-haste shortening, live-verified |

Conclusions, both captures:

- The library surfaces **no swing state at login** in either scenario; the
  first `START` follows the re-pressed attack toggle by ~120 ms.
- The previously reported "in-flight swing triggered at login" (the test
  that read as inconclusive) was the **re-pressed attack toggle producing
  a real swing**, not library state. The PEW reset is not a producer.
- Auto-attack does not survive `/reload` (combat state does:
  `PLAYER_REGEN_DISABLED` fires at login) — the report's premise, now
  directly evidenced.
- Bonus verification: the Forever parry-haste back-date landed within
  4–14 ms of the predicted shortened expiry on all three parries
  (5620.986→5620.990, 5626.426→5626.440, 5628.480→5628.476), and the
  un-parried full-speed cadence held to ~4 ms. This lifts beta3's
  "known unverified" caveat for the parry path in the library's notes.

## What this repo needs to do

- **One convergence change, added after the live repro on the shipped
  build.** The `expirationTime > now` guard in `Bars:SeedFromLibrary`
  kept parked seeds out (correct with MINOR 35), but on the shipped
  MINOR 34 the login seed manufactures a synthetic in-flight swing whose
  expiration is in the future - the guard passes, the bar drains to its
  end and then sits stuck (tick at the fill's edge, 0.0 remaining, shown
  in "while swinging" mode) until the next real swing, repro'd in play.
  `Bars:OnUpdate` now parks a bar whose expiration has been in the past
  for over 1 s (STALE_LANDING_GRACE - sized above the ranged movement
  retry's ~0.5 s re-anchor window and the engine-vs-timer race at a
  natural landing, so neither feedback path is disturbed). With MINOR 35
  embedded the branch never triggers; keep it anyway.
- **Keep the expiration-passed workaround** (the "live" gate in
  `Bars:TestEffect`, and the swing-visibility handling). It is a cheap,
  correct defense against any swing that ends without a `STOP` on any
  path or client, and it predates this fix. Do not rip it out.
- **Comments describing the old behavior** (`Bars:TestEffect`'s "a bar can
  sit active with a landed swing right after a reload" block,
  `docs/SPEC.md`'s reload repro) describe the pre-fix library. Leave them
  until the fixed library ships embedded; then reword to history in the
  same pass as the repin.
- **Packaging, once the library releases (MINOR 35+):** bump the
  `.pkgmeta` external tag off `v2.2.0-beta3` and bump
  `REQUIRED_LIB_MINOR` in `Core.lua` (currently 34). Note: this repo's
  AGENTS.md still says the pin is `v2.2.0-beta2` — stale, the pkgmeta is
  already at beta3; worth fixing in the same pass.
- The local test install (`_classic_beta_`) runs the fixed MINOR 35 by
  hand-copy; users get the fix only via the consumer release above.

## Open items

- Classic-flavor regression pass for the seed change (library-side; the
  seed code is shared across all clients, verified only on Forever).
- The attack toggle fired as **6603** (classic ID) in both captures; the
  library's `isAttackToggle` comment claims 6803 was "verified in-game"
  on Forever. The handler accepts both, so nothing misbehaves — recorded
  for the library repo to reconcile.
- SwingLoginProbe (`Interface/AddOns/SwingLoginProbe/`, Forever-only TOC)
  is still installed; delete the folder when done with it.

## Evidence

- Raw probe log: `WTF/Account/.../SavedVariables/SwingLoginProbe.lua`
  (overwritten each logout; the two captures above are summarized from it).
- Library repo: the seed fix in `LibClassicSwingTimerAPI.lua`
  (`PLAYER_ENTERING_WORLD`) and the changelog entry under `[Unreleased]`
  carrying the verification note.
