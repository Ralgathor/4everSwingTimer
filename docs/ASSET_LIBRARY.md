# 4everSwingTimer — Asset Library (curated pick list)

Status: reference catalog of client-side assets this addon can draw on —
Blizzard UI art referenced by atlas name, `Interface\` path, or FileDataID,
plus the client fonts. Nothing here is shipped in the package (the packager
ignores `docs`); every entry is referenced in-game, which keeps the addon
policy-clean: the Blizzard Add-On Development Policy forbids *redistributing*
game art and audio, not referencing it.

Companion documents: `SPEC.md` (design), `BENCHMARK.md` (timing). Sources for
this catalog: the addon's own `Bars.lua`, the Forever-client addons in `ref/`
(ForeverSwing, AppelSwingsForever), and the research summary in the session
scratchpad (`asset-research/report.md`).

Verification legend:

- **in use** — already used by `Bars.lua` / the TOC; verified in play on the
  Forever beta client.
- **ref** — verified on Forever by a `ref/` addon that runs there
  (ForeverSwing or AppelSwingsForever, both in `ref/`).
- **research** — documented or widely used retail-wide; run an
  `AtlasOK()` check before first use (see section 9).

## 1. How these are addressed

- Atlas name — `tex:SetAtlas(name, useAtlasSize)`; introspect with
  `C_Texture.GetAtlasInfo(name)`. Names are the *fragile* identifier: they can
  be renamed or dropped between client builds, so guard every lookup.
- `Interface\` path — `tex:SetTexture("Interface\\...")`; legacy but stable for
  files that predate the FileDataID switchover (patch 7.0.3).
- FileDataID — `tex:SetTexture(136235)`; permanent identifier, preferred for
  anything you expect to outlive atlas renames. Resolve an Interface path at
  runtime with `GetFileIDFromPath("Interface\\...")`.
- Icons arrive as FDIDs from APIs (`C_Spell.GetSpellTexture`,
  `C_Item.GetItemIconByID`) — no asset knowledge needed at all.

## 2. Bar fills (statusbar textures)

| Asset | Kind | Status | Notes |
|---|---|---|---|
| `ui-swingtimerbar-filling-mainhand` / `-offhand` / `-ranged` | atlas | in use | The native swing timer's own fills; the Native skin's fill source (`FILL_ATLAS` in Bars.lua). AppelSwingsForever presets confirm all three names. |
| `ui-castingbar-filling-standard` | atlas | ref | The standard cast bar fill (AppelSwingsForever "Castbar" preset). Matches the cast-bar look the effect feedback already borrows. |
| `UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health` | atlas | ref | Modern unit-frame health fill (AppelSwingsForever "Retail" preset); clean flat gradient that vertex-tints well. |
| `Interface\TargetingFrame\UI-StatusBar` | path | in use | The classic flat fill (`FLAT_TEXTURE`); the flat skin's base and LibSharedMedia's canonical "Blizzard" statusbar. |
| `Interface\Buttons\WHITE8X8` | path | ref | Pure white 8x8 — a solid fill of any color via `SetVertexColor`, or a tintable glow square. Zero-art fallback of last resort. |
| `Interface\TargetingFrame\UI-TargetingFrame-BarFill` | path | ref | Target-frame fill, slightly warmer gradient than UI-StatusBar (ForeverSwing "Target frame"). |
| `Interface\RaidFrame\Raid-Bar-Hp-Fill` | path | ref | Flat raid-bar fill (ForeverSwing "Raid"). |
| `Interface\PaperDollInfoFrame\UI-Character-Skills-Bar` | path | ref | Skills-panel fill (ForeverSwing "Skills"); LibSharedMedia ships it as "Blizzard Character Skills Bar". |

## 3. Bar chrome — backgrounds, borders, panels

| Asset | Kind | Status | Notes |
|---|---|---|---|
| `ui-swingtimerbar-background` / `ui-swingtimerbar-frame` | atlas | in use | The native swing timer's own backing and border — the Native skin already pairs them. |
| `ui-castingbar-background` | atlas | ref | Cast-bar backing (AppelSwingsForever "Castbar stone" preset) — pairs with the cast-bar fills above. |
| `common-insideframe` | atlas | ref | Modern "inside frame" panel chrome (AppelSwingsForever uses it for list/panel dressing). |
| `UI-Character-Info-General-BG` | atlas | ref | Character-info panel background (AppelSwingsForever popovers/panels). |
| `Interface\Tooltips\UI-Tooltip-Background` | path | ref | Dark tileable backdrop (ForeverSwing "Tooltip"). |
| `Interface\Tooltips\UI-Tooltip-Border` | path | ref | 32px edge file; standard `SetBackdrop` edge (`fit ~0.30` per ForeverSwing). |
| `Interface\DialogFrame\UI-DialogBox-Background` | path | ref | Dark translucent dialog backdrop (ForeverSwing "Dialog"). |
| `Interface\DialogFrame\UI-DialogBox-Border` | path | ref | Stone dialog border (`fit ~0.34`). |
| `Interface\DialogFrame\UI-DialogBox-Gold-Border` | path | ref | Gold ornate variant (`fit ~0.34`). |
| `Interface\FriendsFrame\UI-Toast-Border` | path | ref | Rounded toast border (`fit ~0.40`). |
| `Interface\CastingBar\UI-CastingBar-Border` | path | ref | The cast bar's own border — visually consistent with the cast-bar fills/glows. |
| `Interface\Tooltips\ChatBubble-Backdrop` | path | ref | Rounded chat-bubble frame (`fit ~0.35`). |
| `Interface\FrameGeneral\UI-Background-Marble` / `UI-Background-Rock` | path | ref | Full-page decorative backdrops (ForeverSwing backgrounds list). |

## 4. Ticks, sparks, glows (position markers and feedback)

| Asset | Kind | Status | Notes |
|---|---|---|---|
| `ui-swingtimerbar-pip` | atlas | in use | The swing timer's own tick pip — the standard tick everywhere in the addon. |
| `ui-castingbar-pip-red` | atlas | in use | Red interrupted-cast pip — the clip/interrupt tick treatment. |
| `cast_standard_pipglow` | atlas | in use | Pip glow — the queued-glow and streak source (`ADD` blend). |
| `cast_interrupt_outerglow` | atlas | in use | Interrupt outer glow — the clip halo (`ADD` blend, atlas-sized at half scale). |
| `Interface\CastingBar\UI-CastingBar-Spark` | path | ref | The classic cast-bar spark (ForeverSwing "Blizzard spark"); wide directional spark in `ADD` blend — the obvious pick if the flat skin ever wants a leading-edge spark instead of a pip. |

## 5. Fonts

| Asset | Kind | Status | Notes |
|---|---|---|---|
| `STANDARD_TEXT_FONT` (resolves to `Fonts\FRIZQT__.TTF`) | font path / global | in use | Main UI font; the addon's `BASE_FONT` with a hardcoded fallback. |
| `Fonts\ARIALN.TTF` | font path | ref | Arial Narrow — chat/number face; good alternative for the numeric time/delta texts. |
| `Fonts\MORPHEUS.TTF` | font path | ref | Morpheus — mail/quest display face (ForeverSwing offers it). |
| `Fonts\SKURRI.TTF` | font path | ref | Skurri — unit-frame combat-text face (ForeverSwing offers it). |

`SetFont(path, size, flags)` takes any of these; the four client fonts need no
shipped files. If a non-Blizzard face is ever wanted, ship an open-license
.ttf with its LICENSE file (ForeverSwing's `Media\Fonts` DejaVu/Liberation
setup in `ref/` is the model).

## 6. Settings-panel and small UI bits

For hand-dressed panels or bar-overlay dressing — the 12.x vertical-layout
Settings API has no button control, so any chrome is drawn by the addon.

| Asset | Kind | Status | Notes |
|---|---|---|---|
| `checkmark-minimal` | atlas | ref | Minimal checkmark (AppelSwingsForever checkboxes). |
| `common-search-border-left` / `-middle` / `-right` | atlas | ref | Search-box border trio (AppelSwingsForever). |
| `spellbook-divider` | atlas | ref | Horizontal divider line (AppelSwingsForever, `useAtlasSize`). |
| `common-stat-bar-red` | atlas | ref | Red stat-bar segment (AppelSwingsForever list rows). |
| `Options_List_Hover` | atlas | ref | Row hover highlight (AppelSwingsForever). |
| `common-button-list-collapseExpand` | atlas | ref | List bar texture (AppelSwingsForever `LIST_BAR_ATLAS`). |

## 7. Icons

- Spell icons: `C_Spell.GetSpellTexture(spellIdentifier)` — returns
  `iconID, originalIconID` as FileDataIDs; pass straight to `SetTexture`.
- Item icons: `C_Item.GetItemIconByID(itemInfo)` — FileDataID.
- TOC addon icon: keep the full-path `## IconTexture`
  (`Interface\AddOns\4everSwingTimer\Textures\icon.png`); `## IconAtlas` is
  the atlas alternative. A bare FDID in `IconTexture` does not work — TOC
  metadata is text, so the digits reach `SetTexture` as a string path.

## 8. Sounds (mechanism — no IDs curated)

Referencing client sounds is policy-clean; bundling game audio is not. If a
swing-ready or clip cue is ever wanted:

- `PlaySound(soundKitID)` — numeric SoundKit IDs; the human-readable constants
  Blizzard's own code uses live in the FrameXML `SOUNDKIT` table (get it from
  `exportInterfaceFiles code` or a FrameXML mirror). Browse IDs at
  `wowhead.com/sounds`.
- `PlaySoundFile(fdidOrPath)` — any client sound by FileDataID, or an
  addon-local `.ogg`/`.mp3` (must exist before client start; textures are
  `/reload`-fresh, sounds are not).

Curate specific Kit IDs only when a sound feature is actually planned — IDs
are easy to verify lazily with `PlaySound` in-game.

## 9. Paste-ready Lua table

Not wired into the TOC — a pick list to copy from when a feature needs one.

```lua
-- Curated client-side assets (see docs/ASSET_LIBRARY.md for provenance).
-- Every atlas lookup goes through AtlasOK: atlas names can be renamed or
-- dropped between client builds, and a missing name must degrade to
-- fallback art, not error the OnUpdate path.
local AssetLibrary = {
	fills = {
		native_mainhand = { atlas = "ui-swingtimerbar-filling-mainhand" },
		native_offhand  = { atlas = "ui-swingtimerbar-filling-offhand" },
		native_ranged   = { atlas = "ui-swingtimerbar-filling-ranged" },
		castbar         = { atlas = "ui-castingbar-filling-standard" },
		unitframe       = { atlas = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health" },
		statusbar       = { path  = "Interface\\TargetingFrame\\UI-StatusBar" },
		solid           = { path  = "Interface\\Buttons\\WHITE8X8" },
		target          = { path  = "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill" },
		raid            = { path  = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
		skills          = { path  = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" },
	},
	chrome = {
		native_bg      = { atlas = "ui-swingtimerbar-background" },
		native_border  = { atlas = "ui-swingtimerbar-frame" },
		castbar_bg     = { atlas = "ui-castingbar-background" },
		inside_frame   = { atlas = "common-insideframe" },
		char_info_bg   = { atlas = "UI-Character-Info-General-BG" },
		tooltip_bg     = { path  = "Interface\\Tooltips\\UI-Tooltip-Background" },
		tooltip_border = { path  = "Interface\\Tooltips\\UI-Tooltip-Border" },
		dialog_bg      = { path  = "Interface\\DialogFrame\\UI-DialogBox-Background" },
		dialog_border  = { path  = "Interface\\DialogFrame\\UI-DialogBox-Border" },
		gold_border    = { path  = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border" },
		toast_border   = { path  = "Interface\\FriendsFrame\\UI-Toast-Border" },
		castbar_border = { path  = "Interface\\CastingBar\\UI-CastingBar-Border" },
		bubble         = { path  = "Interface\\Tooltips\\ChatBubble-Backdrop" },
		marble         = { path  = "Interface\\FrameGeneral\\UI-Background-Marble" },
		rock           = { path  = "Interface\\FrameGeneral\\UI-Background-Rock" },
	},
	ticks = {
		pip            = { atlas = "ui-swingtimerbar-pip" },
		pip_red        = { atlas = "ui-castingbar-pip-red" },
		pip_glow       = { atlas = "cast_standard_pipglow" },
		interrupt_glow = { atlas = "cast_interrupt_outerglow" },
		spark          = { path  = "Interface\\CastingBar\\UI-CastingBar-Spark" },
	},
	fonts = {
		base       = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",
		arial      = "Fonts\\ARIALN.TTF",
		morpheus   = "Fonts\\MORPHEUS.TTF",
		skurri     = "Fonts\\SKURRI.TTF",
	},
	panel_bits = {
		checkmark    = { atlas = "checkmark-minimal" },
		search_left  = { atlas = "common-search-border-left" },
		search_mid   = { atlas = "common-search-border-middle" },
		search_right = { atlas = "common-search-border-right" },
		divider      = { atlas = "spellbook-divider" },
		stat_bar_red = { atlas = "common-stat-bar-red" },
		hover        = { atlas = "Options_List_Hover" },
		list_bar     = { atlas = "common-button-list-collapseExpand" },
	},
}

-- Atlas existence preflight (C_Texture is nil-guarded for the same reason
-- every global is: a missing namespace must not blow up the file's setup).
local function AtlasOK(name)
	if not name or not C_Texture then return false end
	return C_Texture.GetAtlasInfo(name) ~= nil
end

-- Apply one entry with the pcall guard ref/ addons use on Forever: a missing
-- atlas either errors or returns false depending on client build, so both
-- are treated as failure and the caller falls back (e.g. FLAT_TEXTURE).
local function ApplyAsset(texture, asset, useAtlasSize)
	if not texture or not asset then return false end
	if asset.atlas then
		if not AtlasOK(asset.atlas) then return false end
		local ok = pcall(texture.SetAtlas, texture, asset.atlas, useAtlasSize or false)
		return ok and texture:GetAtlas() ~= nil
	elseif asset.path then
		return texture:SetTexture(asset.path)
	end
	return false
end
```

## 10. Expanding the catalog

- In-game: TextureAtlasViewer (CurseForge) browses every atlas on a sheet
  with copyable names; `exportInterfaceFiles art` dumps all UI art to
  `BlizzardInterfaceArt\`; `/run print(C_Texture.GetAtlasInfo("name"))`
  preflights a single name.
- Out-of-game: wago.tools/files (search + preview by FDID/path),
  wow.tools.local (full TACT browser), Gethe/wow-ui-source (FrameXML
  mirror, also the `SOUNDKIT` table).
- Anything added to the table must carry a status from the legend above —
  a research-tier entry gets an in-game `AtlasOK` verification note before
  it is promoted.
