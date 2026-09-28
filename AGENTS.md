# AGENTS.md

Guidance for AI coding agents working in this repository.

## Project overview

4everSwingTimer is a standalone addon for **WoW: Forever only** (interface
16000+, currently `## Interface: 16001`) that renders the player's swing timers
as bars. All swing state comes from **LibClassicSwingTimerAPI** (embedded via
`.pkgmeta` externals, currently pinned to tag `v2.2.0-beta2`, LibStub MINOR 34
— bump `REQUIRED_LIB_MINOR` in `Core.lua` when the library releases).

The addon deliberately holds **no swing math**: it consumes the library's
`UNIT_SWING_TIMER_*` events and `UnitSwingTimerInfo`, and its update loop only
computes `expirationTime - now`. Do not read `UnitAttackSpeed` or
`UnitRangedDamage` here — on Forever they return secret values in combat, and
the library owns that problem.

Design spec, Forever API constraints, verification checklist and roadmap:
`docs/SPEC.md`. Read it before changing behavior.

## Repository layout

- `Core.lua` — bootstrap, saved variables (`ForeverSwingTimerDB`), library
  gate, event dispatch, slash commands.
- `Bars.lua` — bar frames, library callback wiring, visual states, test mode.
- `Options.lua` — settings via the 12.x Settings (vertical layout) API.
- `4everSwingTimer.toc` — manifest. The addon name starts with a digit on
  purpose; the saved-variable global is `ForeverSwingTimerDB` (valid Lua
  identifier requirement).
- `.pkgmeta` — BigWigs packager externals (LibStub, CallbackHandler-1.0, the
  library) and package ignores.
- `docs/SPEC.md` — the design spec; not shipped in the package.

Do not commit `Libs/` or `.release/` — generated and gitignored.

## Conventions

- Tabs for indentation; CRLF line endings.
- Declare every variable `local` — the WoW environment is shared.
- WoW API calls in hot paths are localized into upvalues at the top of the
  file (`local GetTime = GetTime` etc.).
- This client (mainline 12.x-era) has **removed many old global functions** —
  `GetSpellCooldown`, `GetItemInfo`, `InterfaceOptions_AddCategory` among them.
  Use the `C_*` namespaces (`C_Spell`, `C_Item`, the `Settings` system) with a
  nil-guarded fallback to the old global, and verify the function exists before
  caching it into an upvalue — a removed global upvalues to nil and only fails
  at call time.
- The addon name `4everSwingTimer` cannot be used as a Lua identifier; the
  cross-file namespace is the global `FourEverSwingTimer`.

## Settings API constraints (12.x)

- `InterfaceOptions_AddCategory` does not exist on this client. Use
  `Settings.RegisterVerticalLayoutCategory` + `Settings.RegisterAddOnCategory`
  with proxy settings (`Settings.RegisterProxySetting`).
- The vertical layout has **no button control** — buttons go on the bar overlay
  or slash commands, not the settings panel.
- `Settings.VarType` on this client has no Color — no color pickers in v1
  (flat skin uses preset per-hand colors).

## Verification

No test suite; verification is in-game on the Forever beta client. Before an
in-game pass: syntax check with `luajit -e "assert(loadfile('file.lua'))"`
(or `luac -p` where available). The full checklist is `docs/SPEC.md` section 7.

## Versioning and release

- `## Version` in the `.toc` bumps at release preparation only, not during
  development. Changelog entries are written with the change, under
  `[Unreleased]` in `CHANGELOG.md`.
- Publishing goes through CurseForge and Wago: add the `X-Wago-ID` /
  `X-Curse-Project-ID` TOC lines and the repo secrets before the first tagged
  release, and check that the name `4everSwingTimer` is free on both platforms.
- Agents must not push tags or releases without explicit instruction — a tag
  triggers a public release via `.github/workflows/package_and_release.yml`.
