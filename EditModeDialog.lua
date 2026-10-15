-- 4everSwingTimer — the Edit Mode settings panel, after 4everActionTimeline's
-- pattern (its ADR-0008). Click a hand's bar in Edit Mode and this panel opens
-- beside it, like a Blizzard system's: that bar's own look, size and
-- visibility - every setting is per hand, as each native swing timer is its own
-- frame. The bars are not registered Edit Mode systems (see EditMode.lua), so
-- the panel is built from generic templates - the slider and dropdown
-- Blizzard's panel uses, never the EditModeSetting* templates whose mixins
-- report to Edit Mode's manager. The settings are declared as data, like
-- Blizzard_EditMode's EditModeSettingDisplayInfo, and written straight into
-- the saved variables, then re-applied live. Its buttons lead to the other
-- places: Reset position and the test previews.

local Addon = FourEverSwingTimer

local format = format

local NAME = "FourEverSwingTimerEditDialog"
local WIDTH, LABEL_WIDTH, ROW_HEIGHT = 380, 110, 32

local EditModeDialog = {}
Addon.EditModeDialog = EditModeDialog

local function Percent(value)
	return format("%d%%", value)
end

local function Pixels(value)
	return format("%d px", value)
end

-- The native bars' visibility modes ("Hidden" is the hand's off
-- switch).
local VISIBILITY_OPTIONS = {
	{ "always", "Always (weapon equipped)" }, { "combat", "In combat" },
	{ "swinging", "While swinging" }, { "hidden", "Hidden" },
}

-- One entry per setting: a slider (shown as `min`..`max` in steps of `step`,
-- stored through toStored / fromStored), a dropdown or a checkbox. `hands`
-- limits a row to those hands. Slider values are what the panel shows
-- (percent for scale and opacity).
local SETTINGS = {
	{ key = "scale", type = "slider", name = "Scale", min = 50, max = 200, step = 5, format = Percent,
		fromStored = function(v) return v * 100 end, toStored = function(v) return v / 100 end },
	{ key = "opacity", type = "slider", name = "Opacity", min = 10, max = 100, step = 5, format = Percent,
		fromStored = function(v) return v * 100 end, toStored = function(v) return v / 100 end },
	{ key = "width", type = "slider", name = "Width", min = 120, max = 400, step = 10, format = Pixels },
	{ key = "height", type = "slider", name = "Height", min = 14, max = 40, step = 1, format = Pixels },
	{ key = "visibility", type = "dropdown", name = "Visibility", options = VISIBILITY_OPTIONS },
	-- Feedback: the queued next-melee highlight is the main hand's alone; range
	-- feedback is every hand's own.
	{ key = "highlightQueued", type = "checkbox", name = "Queued attack", hands = { mainhand = true },
		tooltip = "While a next-melee ability (Heroic Strike, Cleave, Raptor Strike, Maul) is queued, the bar's fill takes the cast bar's yellow and the tick lights up with a glow.",
		onWrite = function(_, value) Addon.Bars:SetHighlightQueued(value) end },
	{ key = "rangeFeedback", type = "checkbox", name = "Range feedback",
		tooltip = "Too far from your target, or inside the ranged dead zone: the bar's fill turns amber, a state word appears and a one-shot shake plays.",
		onWrite = function(hand, value) Addon.Bars:SetRangeFeedback(hand, value) end },
}

local dialog
local rows = {}

-- The hand the panel edits (set by Show): every setting is per hand, in
-- db.hands[hand].
local currentHand

local function Get(setting)
	return Addon.db.hands[currentHand][setting.key]
end

-- Every write lands in the saved variables, then one full apply pass
-- refreshes the bars (skin, text, layout, visibility - all of it).
local function Write(setting, value)
	Addon.db.hands[currentHand][setting.key] = setting.toStored and setting.toStored(value) or value
	if setting.onWrite then
		setting.onWrite(currentHand, Addon.db.hands[currentHand][setting.key])
	end
	if Addon.Bars and Addon.Bars.bars then
		Addon.Bars:ApplyAll()
	end
end

-- A slider row on Blizzard's minimal slider (nil without the template, like
-- the dropdown: the row is then a label only).
local function BuildSlider(row, setting)
	local ok, slider = pcall(CreateFrame, "Frame", nil, row, "MinimalSliderWithSteppersTemplate")
	if not (ok and slider.Init and MinimalSliderWithSteppersMixin) then
		return
	end
	slider:SetPoint("LEFT", row, "LEFT", LABEL_WIDTH, 0)
	slider:SetWidth(200)
	slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
		if not row.initializing then
			Write(setting, value)
		end
	end, row)
	return slider
end

local function BuildDropdown(row, setting)
	local ok, dropdown = pcall(CreateFrame, "DropdownButton", nil, row, "WowStyle1DropdownTemplate")
	if not (ok and dropdown.SetupMenu) then
		return
	end
	dropdown:SetPoint("LEFT", row, "LEFT", LABEL_WIDTH, 0)
	dropdown:SetWidth(200)
	dropdown:SetupMenu(function(_, root)
		for _, option in ipairs(setting.options) do
			root:CreateRadio(option[2], function()
				return Get(setting) == option[1]
			end, function()
				Write(setting, option[1])
			end)
		end
	end)
	return dropdown
end

local function BuildCheckbox(row, setting)
	local ok, check = pcall(CreateFrame, "CheckButton", nil, row, "UICheckButtonTemplate")
	if not ok then
		return
	end
	check:SetPoint("LEFT", row, "LEFT", LABEL_WIDTH + 12, 0)
	check:SetScript("OnClick", function(self)
		Write(setting, self:GetChecked() and true or false)
	end)
	check:SetScript("OnEnter", function(self)
		if setting.tooltip and GameTooltip then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(setting.name)
			GameTooltip:AddLine(setting.tooltip, 1, 1, 1, true)
			GameTooltip:Show()
		end
	end)
	check:SetScript("OnLeave", function()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)
	return check
end

local function RefreshSlider(row, control)
	local setting = row.setting
	local value = Get(setting)
	value = setting.fromStored and setting.fromStored(value) or value
	local formatters = {}
	if setting.format and CreateMinimalSliderFormatter then
		formatters[MinimalSliderWithSteppersMixin.Label.Right] = CreateMinimalSliderFormatter(MinimalSliderWithSteppersMixin.Label.Right, setting.format)
	end
	row.initializing = true
	control:Init(value, setting.min, setting.max, (setting.max - setting.min) / setting.step, formatters)
	row.initializing = false
end

-- How each row type is built and read back.
local ROW_TYPES = {
	slider = { build = BuildSlider, refresh = RefreshSlider },
	dropdown = { build = BuildDropdown, refresh = function(_, control) control:GenerateMenu() end },
	checkbox = { build = BuildCheckbox, refresh = function(_, control) control:SetChecked(Get(control.setting) and true or false) end },
}

local function BuildRow(setting)
	local row = CreateFrame("Frame", nil, dialog)
	row:SetSize(WIDTH - 40, ROW_HEIGHT)
	row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
	row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.label:SetText(setting.name)
	row.setting = setting
	row.control = ROW_TYPES[setting.type].build(row, setting)
	if row.control then
		row.control.setting = setting
	end
	return row
end

-- Whether a row or a test button (an entry with an optional `hands` set) is
-- shown for the hand being edited.
local function AppliesToHand(entry)
	local sets = entry.hands
	return sets == nil or sets[currentHand] == true
end

-- Reads every setting back into its control.
function EditModeDialog:Refresh()
	if not dialog then
		return
	end
	-- Rows stack from the top; one that does not apply to this hand (the
	-- queued highlight off the main hand) drops out and the rest close up.
	local y = 48
	for _, row in ipairs(rows) do
		local applies = AppliesToHand(row.setting)
		row:SetShown(applies)
		if applies then
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", dialog, "TOPLEFT", 20, -y)
			y = y + ROW_HEIGHT
		end
		if row.control then
			ROW_TYPES[row.setting.type].refresh(row, row.control)
		end
	end
	-- The test previews that fit this hand, centered: Delay is the ranged
	-- hand's, Queued the main hand's.
	local shown = {}
	for _, button in ipairs(dialog.testButtons) do
		local applies = AppliesToHand(button.def)
		button:SetShown(applies)
		if applies then
			shown[#shown + 1] = button
		end
	end
	local span = #shown * 64 + (#shown - 1) * 4
	for index, button in ipairs(shown) do
		button:ClearAllPoints()
		if index == 1 then
			button:SetPoint("LEFT", dialog.testRow, "LEFT", (dialog.testRow:GetWidth() - span) / 2, 0)
		else
			button:SetPoint("LEFT", shown[index - 1], "RIGHT", 4, 0)
		end
	end
	dialog.reset:ClearAllPoints()
	dialog.reset:SetPoint("TOP", dialog, "TOP", 0, -(y + 8))
	dialog:SetSize(WIDTH, y + 8 + 2 * 32 + 46)
end

local function Button(text, onClick, width)
	local button = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	button:SetSize(width or (WIDTH - 80), 24)
	button:SetNormalFontObject("GameFontNormal") -- gold, like Blizzard's panel buttons
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	return button
end

local function Build()
	dialog = CreateFrame("Frame", NAME, UIParent)
	dialog:SetFrameStrata("DIALOG")
	dialog:SetFrameLevel(200)
	dialog:SetClampedToScreen(true)
	dialog:SetMovable(true)
	dialog:EnableMouse(true)
	dialog:RegisterForDrag("LeftButton")
	dialog:SetScript("OnDragStart", dialog.StartMoving)
	dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
	local ok, border = pcall(CreateFrame, "Frame", nil, dialog, "DialogBorderTranslucentTemplate")
	if ok then
		border:SetAllPoints()
	else
		local back = dialog:CreateTexture(nil, "BACKGROUND")
		back:SetAllPoints()
		back:SetColorTexture(0, 0, 0, 0.8)
	end
	dialog.title = dialog:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
	dialog.title:SetPoint("TOP", 0, -15)
	local close = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT")
	close:SetScript("OnClick", function()
		Addon.EditMode:Deselect()
	end)
	for index, setting in ipairs(SETTINGS) do
		rows[index] = BuildRow(setting)
	end
	local reset = Button("Reset position", function()
		Addon.EditMode:ResetPosition(currentHand)
	end)
	dialog.reset = reset
	-- The test previews that used to sit under the unlocked bars: the
	-- swing animation and each effect treatment, through the same handlers
	-- as the /4everswingtimer test commands.
	local tests = {
		{ label = "Swing" },
		{ label = "Interrupt", effect = "interrupt" },
		{ label = "Haste", effect = "haste" },
		{ label = "Delay", effect = "delay", hands = { ranged = true } },
		{ label = "Queued", effect = "queued", hands = { mainhand = true } },
	}
	local testRow = CreateFrame("Frame", nil, dialog)
	testRow:SetSize(WIDTH - 80, 24)
	-- A header says what the buttons are: they play the swing and each effect
	-- on the selected bar, so the look can be tuned without a fight.
	local previewHeader = dialog:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	previewHeader:SetPoint("TOP", reset, "BOTTOM", 0, -14)
	previewHeader:SetText("Preview on this bar")
	testRow:SetPoint("TOP", previewHeader, "BOTTOM", 0, -6)
	dialog.testRow = testRow
	dialog.testButtons = {}
	for i = 1, #tests do
		local def = tests[i]
		local button = Button(def.label, function()
			if def.effect then
				Addon.Bars:TestEffect(def.effect, currentHand)
			else
				Addon.Bars:Test(currentHand)
			end
		end, 64)
		button.def = def
		dialog.testButtons[#dialog.testButtons + 1] = button
	end
	-- No Options button: opening the Settings panel from here needs Edit
	-- Mode stepped aside, and every way our code can do that taints the raid
	-- frames (4everActionTimeline's probe E6, same client).
	local note = dialog:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	note:SetPoint("TOP", testRow, "BOTTOM", 0, -10)
	note:SetText("More settings: /4everswingtimer options")
	dialog:Hide()
end

-- Opens for a hand beside its selected bar (the handle): under it, or over it
-- when there is no room below.
function EditModeDialog:Show(hand, anchor)
	currentHand = hand
	if not dialog then
		Build()
	end
	dialog.title:SetText("4everSwingTimer - " .. Addon.HAND_LABEL[hand])
	self:Refresh()
	dialog:ClearAllPoints()
	local bottom = anchor:GetBottom()
	if bottom and bottom > dialog:GetHeight() + 40 then
		dialog:SetPoint("TOP", anchor, "BOTTOM", 0, -30)
	else
		dialog:SetPoint("BOTTOM", anchor, "TOP", 0, 30)
	end
	-- Pin it where it landed: the bars resize under the sliders and the
	-- panel must not follow them. It stays draggable.
	local left, top = dialog:GetLeft(), dialog:GetTop()
	if left and top then
		dialog:ClearAllPoints()
		dialog:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
	end
	dialog:Show()
end

function EditModeDialog:Hide()
	if dialog then
		dialog:Hide()
	end
end
