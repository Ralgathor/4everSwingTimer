-- 4everSwingTimer — Options: settings registration via the client's
-- Settings (vertical layout) API, plus the open-settings entry point.
--
-- Forever runs the mainline 12.x settings system: InterfaceOptions_AddCategory
-- no longer exists there. Proxy settings are used (getValue/setValue) so every
-- change applies live without depending on commit timing.
--
-- Dropdown contract on this client (verified against the shipped
-- Blizzard_Settings.lua): CreateDropdown's `options` argument is passed to
-- Settings.CreateDropdownOptionInserter as `optionsFunc` and is CALLED
-- (ipairs(optionsFunc())) — it must be a function returning the entry list,
-- never the list itself. Each entry needs controlType = Settings.ControlType.Radio.
--
-- The vertical layout supports checkbox, slider and dropdown controls only —
-- there is no button control, which is why "Test bars" lives on the unlocked
-- bar overlay and on the slash command instead of this panel.

local Addon = FourEverSwingTimer

local Options = {}
Addon.Options = Options

local category
local VAR_PREFIX = "4everSwingTimer."

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function ApplyAll()
	if Addon.Bars and Addon.Bars.bars then
		Addon.Bars:ApplyAll()
	end
end

local function ProxyBoolean(variable, name, defaultValue, getValue, setValue)
	return Settings.RegisterProxySetting(category, variable, Settings.VarType.Boolean, name,
		defaultValue, getValue, setValue)
end

local function ProxyNumber(variable, name, defaultValue, minValue, maxValue, rate, onSet)
	return Settings.RegisterProxySetting(category, VAR_PREFIX .. variable, Settings.VarType.Number, name,
		defaultValue,
		function()
			return Addon.db[variable]
		end,
		function(value)
			Addon.db[variable] = value
			if onSet then
				onSet(value)
			end
		end)
end

local function ProxyString(variable, name, defaultValue, entries, onSet)
	local setting = Settings.RegisterProxySetting(category, VAR_PREFIX .. variable, Settings.VarType.String, name,
		defaultValue,
		function()
			return Addon.db[variable]
		end,
		function(value)
			Addon.db[variable] = value
			if onSet then
				onSet(value)
			end
		end)
	local function GetOptions()
		local container = Settings.CreateControlTextContainer()
		for i = 1, #entries do
			container:Add(entries[i].value, entries[i].label, entries[i].tooltip, Settings.ControlType.Radio)
		end
		return container:GetData()
	end
	return setting, GetOptions
end

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------

function Options:Init()
	if category then
		return
	end
	local db = Addon.db
	category = Settings.RegisterVerticalLayoutCategory(Addon.name)
	Settings.RegisterAddOnCategory(category)

	-- Bar visibility and look
	local visibility, visibilityOptions = ProxyString("visibility", "Show bars", db.visibility, {
		{ value = "swinging", label = "While swinging" },
		{ value = "combat",   label = "In combat" },
		{ value = "always",   label = "Always (weapon equipped)" },
	}, function() Addon.Bars:UpdateVisibility() end)
	Settings.CreateDropdown(category, visibility, visibilityOptions,
		"While swinging: bars appear on each swing. In combat: bars stay parked and visible for the whole fight. Always: bars show whenever the hand has a weapon.")

	local skin, skinOptions = ProxyString("skin", "Bar style", db.skin, {
		{ value = "native", label = "Native (like the game's own)" },
		{ value = "flat",   label = "Flat" },
	}, function() Addon.Bars:ApplySkin() end)
	Settings.CreateDropdown(category, skin, skinOptions,
		"Native reuses the game's swing timer art. Flat uses plain colored bars.")

	local paletteEntries = {}
	for i = 1, #Addon.FLAT_PALETTE_ORDER do
		local key = Addon.FLAT_PALETTE_ORDER[i]
		paletteEntries[#paletteEntries + 1] = { value = key, label = Addon.FLAT_PALETTES[key].label }
	end
	local palette, paletteOptions = ProxyString("flatPalette", "Bar colors", db.flatPalette, paletteEntries, ApplyAll)
	Settings.CreateDropdown(category, palette, paletteOptions,
		"Flat bar style colors. Every palette stays clear of the effect colors (queued yellow, interrupt red, delay amber, haste green) so the effects always read.")

	local fill, fillOptions = ProxyString("fill", "Bar direction", db.fill, {
		{ value = "drain", label = "Drain (full to empty)" },
		{ value = "fill",  label = "Fill (empty to full)" },
	}, ApplyAll)
	Settings.CreateDropdown(category, fill, fillOptions,
		"Drain matches classic swing timer addons; Fill matches the game's own bar.")

	Settings.CreateCheckbox(category,
		ProxyBoolean(VAR_PREFIX .. "highlightQueued", "Highlight queued attacks", db.highlightQueued,
			function() return db.highlightQueued end,
			function(value)
				db.highlightQueued = value
				Addon.Bars:SetHighlightQueued(value)
			end),
		"While a next-melee ability (Heroic Strike, Cleave, Raptor Strike, Maul) is queued, the main-hand bar's fill takes the cast bar's yellow and the tick lights up with a glow. Works in both bar styles.")

	Settings.CreateCheckbox(category,
		ProxyBoolean(VAR_PREFIX .. "locked", "Locked", db.locked,
			function() return db.locked end,
			function(value)
				db.locked = value
				Addon.Bars:SetLocked(value)
			end),
		"Uncheck to drag the bars around. The unlock overlay has a Test bars button.")

	-- Layout
	local width = ProxyNumber("width", "Width", db.width, 120, 400, 10, ApplyAll)
	Settings.CreateSlider(category, width, Settings.CreateSliderOptions(120, 400, 10), "Bar width in pixels.")

	local height = ProxyNumber("height", "Height", db.height, 14, 40, 1, ApplyAll)
	Settings.CreateSlider(category, height, Settings.CreateSliderOptions(14, 40, 1),
		"Bar height in pixels. The minimum is 14: the fill is inset 4px top and bottom, and the text needs the remaining room.")

	local gap = ProxyNumber("gap", "Spacing", db.gap, 0, 16, 1, ApplyAll)
	Settings.CreateSlider(category, gap, Settings.CreateSliderOptions(0, 16, 1), "Space between bars in pixels.")

	local scale = ProxyNumber("scale", "Scale", db.scale, 0.5, 2.0, 0.05, ApplyAll)
	Settings.CreateSlider(category, scale, Settings.CreateSliderOptions(0.5, 2.0, 0.05), "Overall bar scale.")

	-- Text
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

	-- Hands
	for i = 1, #Addon.HAND_ORDER do
		local hand = Addon.HAND_ORDER[i]
		Settings.CreateCheckbox(category,
			ProxyBoolean(VAR_PREFIX .. "enabled." .. hand, Addon.HAND_SETTING_NAME[hand], db.enabled[hand],
				function() return db.enabled[hand] end,
				function(value)
					db.enabled[hand] = value
					Addon.Bars:UpdateVisibility()
				end),
			Addon.HAND_SETTING_TOOLTIP[hand])
	end
end

function Options:Open()
	if not category then
		return
	end
	-- OpenToCategory's argument has shifted between client builds; try the
	-- category object first and its numeric id as a fallback.
	if not pcall(Settings.OpenToCategory, category) then
		pcall(Settings.OpenToCategory, category.GetID and category:GetID() or nil)
	end
end
