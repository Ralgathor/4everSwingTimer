-- 4everSwingTimer — Options: the Settings category (the client's Settings
-- vertical layout API, 12.x; Forever has no InterfaceOptions_AddCategory).
--
-- The configuration follows Blizzard's own patterns, as 4everActionTimeline
-- does (its ADR-0008): the frame's own settings - position, scale, opacity,
-- width, height, visibility and the feedback features, all per hand - live in the Edit Mode panel
-- (EditModeDialog.lua), reached by clicking a hand's bar in Edit Mode; this
-- category holds the rest: the bar style, flat colors and direction (the same
-- for every hand) and the text readouts, under
-- section headers.
--
-- Build 70338+ has section headers
-- (CreateSettingsListSectionHeaderInitializer) and button rows
-- (CreateSettingsButtonInitializer), added through the layout — the
-- category call's second return; both are nil-guarded so the category still
-- builds without them.
--
-- Proxy settings are used (getValue/setValue) so every change applies live
-- without depending on commit timing.
--
-- Dropdown contract on this client (verified against the shipped
-- Blizzard_Settings.lua): CreateDropdown's `options` argument is passed to
-- Settings.CreateDropdownOptionInserter as `optionsFunc` and is CALLED
-- (ipairs(optionsFunc())) — it must be a function returning the entry list,
-- never the list itself. Each entry needs controlType = Settings.ControlType.Radio.

local Addon = FourEverSwingTimer

local Options = {}
Addon.Options = Options

local category, layout
local VAR_PREFIX = "4everSwingTimer."

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function ProxyBoolean(variable, name, defaultValue, getValue, setValue)
	return Settings.RegisterProxySetting(category, variable, Settings.VarType.Boolean, name,
		defaultValue, getValue, setValue)
end

-- A section header; the layout's AddInitializer and the header initializer
-- are nil-guarded (the category still builds without them).
local function Header(text, tooltip)
	if layout and layout.AddInitializer and CreateSettingsListSectionHeaderInitializer then
		layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text, tooltip))
	end
end

-- Radio dropdown options from a list of { value, label } entries.
local function DropdownOptions(entries)
	local container = Settings.CreateControlTextContainer()
	for i = 1, #entries do
		container:Add(entries[i][1], entries[i][2], nil, Settings.ControlType.Radio)
	end
	return container:GetData()
end

-- A string dropdown on Addon.db[variable], applied live through onSet.
local function StringDropdown(variable, name, entries, tooltip, onSet)
	local setting = Settings.RegisterProxySetting(category, VAR_PREFIX .. variable, Settings.VarType.String, name,
		Addon.db[variable],
		function()
			return Addon.db[variable]
		end,
		function(value)
			Addon.db[variable] = value
			onSet()
		end)
	Settings.CreateDropdown(category, setting, function()
		return DropdownOptions(entries)
	end, tooltip)
end

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------

function Options:Init()
	if category then
		return
	end
	local db = Addon.db
	category, layout = Settings.RegisterVerticalLayoutCategory(Addon.name)
	Settings.RegisterAddOnCategory(category)

	Header("Position and size",
		"Open Edit Mode (Esc, then Edit Mode) and click a bar: the panel beside it holds that hand's position (with a Reset position button), scale, opacity, width, height, visibility (always, in combat, while swinging or hidden), range feedback and (main hand) the queued-attack highlight - plus the swing and effect test previews.")

	Header("Style", "How the bars look, the same for every hand.")
	StringDropdown("skin", "Bar style", {
		{ "native", "Native (like the game's own)" },
		{ "flat", "Flat" },
	}, "Native reuses the game's swing timer art. Flat uses plain colored bars, styled by the Flat bar colors option below.",
		function() Addon.Bars:ApplySkin() end)

	local paletteEntries = {}
	for i = 1, #Addon.FLAT_PALETTE_ORDER do
		local key = Addon.FLAT_PALETTE_ORDER[i]
		paletteEntries[#paletteEntries + 1] = { key, Addon.FLAT_PALETTES[key].label }
	end
	StringDropdown("flatPalette", "Flat bar colors", paletteEntries,
		"Only applies to the Flat bar style (native uses the game's own art). Every palette stays clear of the effect colors (queued yellow, interrupt red, delay amber, haste teal) so the effects always read.",
		function() Addon.Bars:ApplyAll() end)

	StringDropdown("fill", "Bar direction", {
		{ "drain", "Drain (full to empty)" },
		{ "fill", "Fill (empty to full)" },
	}, "Drain matches classic swing timer addons; Fill matches the game's own bar.",
		function() Addon.Bars:ApplyAll() end)

	Header("Text", "The readouts on each bar.")
	Settings.CreateCheckbox(category,
		ProxyBoolean(VAR_PREFIX .. "showTime", "Show remaining time", db.showTime,
			function() return db.showTime end,
			function(value)
				db.showTime = value
				Addon.Bars:ApplyText()
			end),
		"Remaining swing time with one decimal.")

	Settings.CreateCheckbox(category,
		ProxyBoolean(VAR_PREFIX .. "showSpeed", "Show weapon speed", db.showSpeed,
			function() return db.showSpeed end,
			function(value)
				db.showSpeed = value
				Addon.Bars:ApplyText()
			end),
		"Show the weapon swing speed next to the time.")

	Settings.CreateCheckbox(category,
		ProxyBoolean(VAR_PREFIX .. "showLabel", "Show hand label", db.showLabel,
			function() return db.showLabel end,
			function(value)
				db.showLabel = value
				Addon.Bars:ApplyText()
			end),
		"Main Hand / Off Hand / Ranged label on the left of each bar.")

	Settings.CreateCheckbox(category,
		ProxyBoolean(VAR_PREFIX .. "showDelta", "Show main/off-hand delta", db.showDelta,
			function() return db.showDelta end,
			function(value)
				db.showDelta = value
				Addon.Bars:ApplyText()
			end),
		"Off-hand bar only: the swing delta between hands, useful for dual wielders.")
end

function Options:Open()
	if not category then
		return
	end
	-- OpenToCategory takes the category's numeric id on this client (it
	-- hands it to C_SettingsUtil.OpenSettingsPanel). Passing the category
	-- object first failed there on 4everActionTimeline after opening the
	-- panel on Blizzard's own pages under addon taint, so their Social page
	-- called a protected function. The id goes first; the object only on a
	-- build without one.
	local id = category.GetID and category:GetID() or category.ID
	if id then
		pcall(Settings.OpenToCategory, id)
	else
		pcall(Settings.OpenToCategory, category)
	end
end
