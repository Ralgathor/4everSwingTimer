# AGENTS.md

Guidance for AI coding agents working in this repository.

## Project overview

4everSwingTimer is a standalone addon for **WoW: Forever only** (interface
16000+, currently `## Interface: 16001`) that renders the player's swing timers
as bars. All swing state comes from **LibClassicSwingTimerAPI** (embedded via
`.pkgmeta` externals, currently pinned to tag `v2.3.0`, LibStub MINOR 39
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
- `EditMode.lua` — placement in Edit Mode: EventRegistry callbacks,
  Blizzard's selection art, drag, snap and preview lines, one position per hand and
  Edit Mode layout (schema 3). Never calls into the Edit Mode manager —
  every code path there taints the raid frames' updates on this client.
- `EditModeDialog.lua` — the panel that opens when a hand's bar is clicked
  in Edit Mode: that hand's own settings (scale, opacity, size, visibility,
  range feedback; the queued highlight on the main hand)
  and the test previews, built from generic templates only.
- `Options.lua` — the Settings category: the bar style, flat colors and direction and the
  text readouts, under section headers, via the
  12.x Settings (vertical layout) API.
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
- **Anchor rule:** always `ClearAllPoints()` before `SetPoint` unless the new
  anchor reuses the same anchor *name*. WoW anchors with different names
  coexist on a region — they do not replace each other — and two horizontal
  anchors (or an inverted pair) stretch or collapse the region. Three bugs in
  this repo came from exactly that (pip initial anchor, glow side flip).
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
- Build 70338+ has section headers
  (`CreateSettingsListSectionHeaderInitializer`) and button rows
  (`CreateSettingsButtonInitializer`), added through the layout — the
  category call's second return; both are nil-guarded in Options.lua.
- `Settings.OpenToCategory` takes the category's numeric id on this client;
  the category-object path failed on 4everActionTimeline under addon taint.
- Configuration follows 4everActionTimeline's ADR-0008: the frame's own
  settings (position, scale, opacity, size, visibility, feedback; all per
  hand, each bar being its own frame) live in the
  Edit Mode panel; Options holds the rest; nothing dynamic registers there.
  Never call Blizzard's Edit Mode manager from addon code (opening Edit Mode,
  clearing its selection, stepping it aside) — it taints the raid frames'
  updates (timeline probes E3/E6, in game). The bars are not a registered
  Edit Mode system and write nothing into Blizzard's layout tables.
- `Settings.VarType` on this client has no Color — no color pickers; the flat
  style uses curated palettes (see FLAT_PALETTES in Bars.lua) chosen for
  distance from the effect colors. If a settings value must match a validator
  type, the declared type string must equal Lua's `type()` of the value.

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
