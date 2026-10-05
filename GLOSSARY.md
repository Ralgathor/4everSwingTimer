# GLOSSARY.md — the ubiquitous language

Canonical for both repos (4everSwingTimer and LibClassicSwingTimerAPI). The
library's investigation docs coined most terms; this file is the shared record.
If a second glossary ever appears (e.g., the library repo grows its own), add a
`GLOSSARY-MAP.md` here to route to the right one.

## Swing model

- **hand** — one swing source: main-hand, off-hand, ranged. Library IDs:
  `mainhand`, `offhand`, `ranged`.
- **swingType** — `PLAYER_SWING`'s hand marker: 0 = main-hand, 1 = off-hand,
  2 = ranged.
- **anchor** (`PLAYER_SWING` anchor) — the engine event that reports a swing
  with its true duration. The library restarts its state at each anchor
  ("re-anchor"). The anchor duration is the one speed value verified plain
  even in restricted content.
- **landing** — the instant the current swing completes.
- **expiry** (`expirationTime`) — the time the current swing lands.
- **one-swing lag** (expiry lag) — the error window when the library learns a
  speed change only at the next anchor.
- **rescale** — recompute an in-flight swing's remaining time after a haste
  change (mid-swing), as opposed to next-swing correction.
- **parked** — a stopped hand's resting state (expiration = lastSwing). Tool
  states: PARKED / IN-FLIGHT / LANDED.
- **stale swing** — a swing whose expiry passed with no STOP; the sweep parks
  it.
- **cast reset** — a completed cast that restarts the swing (the bar renders
  CLIPPED).
- **parry haste** — the shortened swing after the player parries (classic
  40%/20% rule, engine-verified).
- **delta** — the MH/OH timing offset (`UNIT_SWING_TIMER_DELTA`).

## Secrecy

- **secret** — a value the client hides. `issecretvalue(v)` returns true; you
  may store and pass it, never compare it or do math on it.
- **plain** — a readable value.
- **secrecy rule** (§4.2) — the established fact: speed reads are secret in
  combat, plain out of combat. Re-verified 2026-10-05 on build 70205.
- **restriction flip** — the state change that turns reads secret. It lands a
  moment AFTER the combat enter event (the enter instant still reads plain).
- **restricted content** — instanced content (dungeons) with the same or
  stricter limits.
- **ContextuallySecret / NeverSecret** — aura-secrecy classes
  (`Enum.SecrecyLevel` 2 / 0). Every aura probed is ContextuallySecret;
  classifying swing-relevant auras NeverSecret is the Blizzard API ask.

## Events and signals

- **edge** — an anonymous event that says "something changed" and carries no
  usable data (`UNIT_AURA` edge, `UNIT_ATTACK_SPEED` edge).
- **gain edge / fade edge** — an aura's applied / removed instant, as seen in
  `UNIT_AURA` (mid-combat fade edges landed at 0/+49/+2 ms of expected expiry).
- **fire / double-fire** — an event's dispatch. `UNIT_ATTACK_SPEED` fires
  twice per change; any consumer must dedupe.
- **Layer 0 / Layer 1 / Layer 2** — the haste design layers: anchor
  self-correction / the universal stale-invalidation edge (`UNIT_ATTACK_SPEED`
  → mark in-flight expiries stale, pre-arm the landing sweep) / per-family
  factors.
- **candidate** — a tentative inference pending confirmation (e.g., a proc
  application).
- **anchor-settler** — the next `PLAYER_SWING`'s plain duration, which
  confirms or rejects a candidate within one swing.
- **factor** — a haste multiplier (SnD rank 1 = 1.2, from the library table).
- **cast-class / deterministic proc / probabilistic proc** — the haste
  application taxonomy: identified by cast (`SUCCEEDED`) / crit always
  triggers (Flurry) / chance per attack (Deadly Aspects, 10%).
- **snapshot family** — haste that applies at the next swing only (SotC);
  never rescaled mid-swing.
- **time-fixed expiry / charge-count expiry** — duration classes: fixed
  duration (SnD 9+3(n-1); Quick Shots 12 s) vs swings consumed (Flurry, 3).

## Capture rig

- **capture** — a recorded play session (SwingTestLog's SavedVariables file).
- **probe** — a one-line in-game test with a recorded verdict.
- **verdict** — the recorded result of a probe.
- **trace** — the addon's event capture (`/4everswingtimer trace`,
  `FourEverSwingTimerTrace`).
- **watch list** — SwingTestLog's watched aura names (`/stl watch`;
  `SwingTestLogDB.watch`).
- **line kinds** — the tool's log lines: SESSION, WORLD, CLIENT, CAPS, INIT,
  STATE, SWING, START/UPDATE/STOP/CLIPPED/PAUSED, DELTA, AUTOATK, COMBAT,
  CAST, CASTSTART, CASTSTOP, CP, AURA, COUNT, SCAN, ATKSPEED, SPEED, QUEUE,
  PARRY, EQUIP, DEAD/ALIVE/UNGHOST, NOTE, ERROR.
- **evidence** — the archived captures in the library repo (`docs/evidence/`).

## Project

- **the addon** — 4everSwingTimer: Forever-only, renders the library's swing
  state; holds no swing math.
- **the library** — LibClassicSwingTimerAPI: owns all swing state and math.
- **Forever** — the target WoW flavor (12.x-era client, interface 16001+).
- **M1 script** — the library's consolidated in-game checklist
  (`docs/M1_SESSION_SCRIPT.md`); probe items B1-B6.
- **secrecy** — shorthand for the whole Midnight restriction system
  (`issecretvalue`, `C_Secrets`).
