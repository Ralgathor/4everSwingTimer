-- 4everSwingTimer — Bars: bar frames, library callback wiring, visual states.
--
-- Rendering contract: every swing state comes from LibClassicSwingTimerAPI
-- events; the update loop only computes (expirationTime - now) against the
-- event-provided speed. The library owns the model; the bars mirror it.

local Addon = FourEverSwingTimer

local format = format
local GetTime = GetTime
local GetInventoryItemID = GetInventoryItemID
-- Mainline 12.x removed the GetItemInfo global (same namespace migration as
-- GetSpellCooldown -> C_Spell on this client); use C_Item.GetItemInfo when
-- present. The library does the same for the cooldown global.
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
-- Off-hand weapon check, two layers: the localized item-class name when
-- GetItemClassInfo exists, plus the locale-independent numeric item classID
-- (Weapon = 2) from GetItemInfo's extended returns as a fallback.
local WEAPON_CLASS = (GetItemClassInfo and Enum and Enum.ItemClass and GetItemClassInfo(Enum.ItemClass.Weapon)) or "Weapon"
local WEAPON_CLASS_ID = (Enum and Enum.ItemClass and Enum.ItemClass.Weapon) or 2

local HAND_ORDER = { "mainhand", "offhand", "ranged" }
local INVENTORY_SLOT = { mainhand = 16, offhand = 17, ranged = 18 }
local HAND_LABEL = {
	mainhand = SWING_TIMER_MAIN_HAND or "Main Hand",
	offhand = SWING_TIMER_OFF_HAND or "Off Hand",
	ranged = SWING_TIMER_RANGED or "Ranged",
}
-- The client's own native swing timer uses this atlas set; the "native" skin
-- reuses it for zero shipping cost and instant familiarity.
local FILL_ATLAS = {
	mainhand = "ui-swingtimerbar-filling-mainhand",
	offhand = "ui-swingtimerbar-filling-offhand",
	ranged = "ui-swingtimerbar-filling-ranged",
}
local BACKGROUND_ATLAS = "ui-swingtimerbar-background"
local BORDER_ATLAS = "ui-swingtimerbar-frame"
local PIP_ATLAS = "ui-swingtimerbar-pip"
local FLAT_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local FLAT_COLORS = {
	mainhand = { 1.00, 0.82, 0.00 },
	offhand = { 0.36, 0.60, 1.00 },
	ranged = { 0.90, 0.30, 0.36 },
}
local LIB_EVENTS = {
	"UNIT_SWING_TIMER_INFO_INITIALIZED",
	"UNIT_SWING_TIMER_START",
	"UNIT_SWING_TIMER_UPDATE",
	"UNIT_SWING_TIMER_CLIPPED",
	"UNIT_SWING_TIMER_PAUSED",
	"UNIT_SWING_TIMER_STOP",
	"UNIT_SWING_TIMER_DELTA",
}
local TEST_SPEED = 2.0
-- Interrupt feedback, modeled on the 12.x casting bar's interrupted treatment
-- (InterruptShakeAnim + InterruptGlow): a clipped swing tints red and shakes;
-- a movement-delayed ranged swing tints amber. Tints decay back to the skin's
-- normal fill after TINT_TIME seconds.
local CLIP_TINT = { 1.0, 0.25, 0.20 }
local DELAY_TINT = { 1.0, 0.60, 0.10 }
local TINT_TIME = 0.30
local SHAKE_STEP = 0.03

local Bars = {}
Addon.Bars = Bars

-- Exported for Options.lua (hand toggles in the settings panel).
Addon.HAND_ORDER = HAND_ORDER
Addon.HAND_SETTING_NAME = {
	mainhand = "Main-hand bar",
	offhand = "Off-hand bar",
	ranged = "Ranged bar",
}
Addon.HAND_SETTING_TOOLTIP = {
	mainhand = "Show the main-hand swing bar.",
	offhand = "Show the off-hand swing bar (dual wield only).",
	ranged = "Show the ranged swing bar (Auto Shot, wand).",
}

-- ---------------------------------------------------------------------------
-- Frames
-- ---------------------------------------------------------------------------

local anchor = CreateFrame("Frame", "FourEverSwingTimerAnchor", UIParent)
Bars.anchor = anchor
anchor:SetFrameStrata("LOW")
anchor:SetClampedToScreen(true)
anchor:SetMovable(true)
anchor:Hide()

anchor:SetScript("OnDragStart", function(self)
	self:StartMoving()
end)

anchor:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local db = Addon.db
	local point, relativeTo, relativePoint, x, y = self:GetPoint()
	db.point = point
	db.relativeTo = (relativeTo and relativeTo.GetName and relativeTo:GetName()) or "UIParent"
	db.relativePoint = relativePoint
	db.x = x
	db.y = y
end)

-- Unlock overlay: drag hint, test button. Only shown while unlocked.
local overlay = CreateFrame("Frame", nil, anchor)
Bars.overlay = overlay
overlay:SetAllPoints(anchor)
overlay:EnableMouse(false)

overlay.bg = overlay:CreateTexture(nil, "BACKGROUND")
overlay.bg:SetAllPoints(overlay)
overlay.bg:SetColorTexture(0.05, 0.05, 0.05, 0.35)

overlay.label = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
overlay.label:SetPoint("BOTTOM", overlay, "TOP", 0, 2)
overlay.label:SetText("4everSwingTimer - drag to move")

overlay.testButton = CreateFrame("Button", nil, overlay, "UIPanelButtonTemplate")
overlay.testButton:SetSize(96, 22)
overlay.testButton:SetPoint("TOP", overlay, "BOTTOM", 0, -2)
overlay.testButton:SetText("Test bars")
overlay.testButton:SetScript("OnClick", function()
	Bars:Test()
end)

-- Interrupted-cast shake: alternating horizontal translation keyframes, the
-- same mechanism the 12.x casting bar uses (InterruptShakeAnim). Defined before
-- CreateBar, which calls it - Lua locals are lexically scoped.
local function CreateShakeAnimation(bar)
	local group = bar:CreateAnimationGroup()
	local offsets = { -5, 5, -4, 4, -3, 3, -2, 2, -1, 1, 0 }
	for i = 1, #offsets do
		local anim = group:CreateAnimation("Translation")
		anim:SetOffset(offsets[i], 0)
		anim:SetDuration(SHAKE_STEP)
		anim:SetOrder(i)
	end
	return group
end

local function CreateBar(hand)
	local bar = CreateFrame("Frame", "FourEverSwingTimerBar" .. hand, anchor)
	bar.hand = hand

	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints(bar)
	bar.border = bar:CreateTexture(nil, "BACKGROUND")
	bar.border:SetAllPoints(bar)

	bar.status = CreateFrame("StatusBar", nil, bar)
	bar.status:SetPoint("TOPLEFT", bar, "TOPLEFT", 5, -4)
	bar.status:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -5, 4)
	bar.status:SetMinMaxValues(0, 1)
	bar.status:SetValue(0)
	bar.status:SetStatusBarTexture(FLAT_TEXTURE)

	bar.pip = bar.status:CreateTexture(nil, "OVERLAY")
	bar.pip:SetAtlas(PIP_ATLAS, true)
	bar.pip:SetPoint("RIGHT", bar.status:GetStatusBarTexture(), "RIGHT", 0, 0)

	-- Text lives on the StatusBar, not the bar frame: the StatusBar is
	-- a child frame and child frames draw on top of all their parent's regions,
	-- so parented text would be hidden behind the fill texture. (The native
	-- Blizzard bar parents its labels to the StatusBar for the same reason.)
	bar.label = bar.status:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.label:SetPoint("LEFT", bar.status, "LEFT", 5, 0)
	bar.label:SetText(HAND_LABEL[hand])

	bar.delta = bar.status:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.delta:SetPoint("LEFT", bar.label, "RIGHT", 8, 0)

	bar.time = bar.status:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.time:SetPoint("RIGHT", bar.status, "RIGHT", -5, 0)
	bar.time:SetText("0.0")

	-- Interrupted-cast shake: alternating horizontal translation keyframes,
	-- the same mechanism the 12.x casting bar uses (InterruptShakeAnim).
	bar.shake = CreateShakeAnimation(bar)

	bar.active = false
	bar.paused = false
	bar.speed = nil
	bar.expiration = nil
	bar:Hide()
	return bar
end

-- ---------------------------------------------------------------------------
-- Visual state
-- ---------------------------------------------------------------------------

-- A parked bar (no active swing) sits at "ready": full in fill mode,
-- empty in drain mode.
local function ParkedValue()
	return Addon.db.fill == "fill" and 1 or 0
end

-- Temporarily tints the fill, then restores the skin's normal color. Works for
-- both skins: the atlas fill of the native skin and the colored plain fill of
-- the flat skin are both tinted via the statusbar texture's vertex color.
function Bars:SetFillTint(bar, tint)
	local texture = bar.status:GetStatusBarTexture()
	if texture then
		texture:SetVertexColor(tint[1], tint[2], tint[3])
	end
	if bar.tintTimer then
		bar.tintTimer:Cancel()
	end
	bar.tintTimer = C_Timer.NewTimer(TINT_TIME, function()
		Bars:RestoreFill(bar)
	end)
end

function Bars:RestoreFill(bar)
	if not bar then
		return
	end
	local texture = bar.status:GetStatusBarTexture()
	if not texture then
		return
	end
	if Addon.db.skin == "native" then
		texture:SetVertexColor(1, 1, 1)
	else
		local color = FLAT_COLORS[bar.hand]
		bar.status:SetStatusBarColor(color[1], color[2], color[3])
	end
end

function Bars:SetPaused(bar, paused)
	bar.paused = paused
	local texture = bar.status:GetStatusBarTexture()
	if texture then
		texture:SetDesaturated(paused)
	end
	bar.status:SetAlpha(paused and 0.55 or 1.0)
	bar.time:SetVertexColor(paused and 0.6 or 1.0, paused and 0.6 or 1.0, paused and 0.6 or 1.0)
end

function Bars:ApplySkin()
	local db = Addon.db
	local native = db.skin == "native"
	for i = 1, #HAND_ORDER do
		local hand = HAND_ORDER[i]
		local bar = self.bars[hand]
		if native then
			bar.bg:SetAtlas(BACKGROUND_ATLAS)
			bar.border:SetAtlas(BORDER_ATLAS)
			bar.status:SetStatusBarTexture(FILL_ATLAS[hand])
			bar.pip:Show()
		else
			bar.bg:SetColorTexture(0, 0, 0, 0.55)
			bar.border:SetColorTexture(0, 0, 0, 0.85)
			bar.status:SetStatusBarTexture(FLAT_TEXTURE)
			local color = FLAT_COLORS[hand]
			bar.status:SetStatusBarColor(color[1], color[2], color[3])
			bar.pip:Hide()
		end
		bar.pip:SetPoint("RIGHT", bar.status:GetStatusBarTexture(), "RIGHT", 0, 0)
	end
end

-- Parked ("swing ready") text: with the speed option on, the time label keeps
-- showing the weapon speed; the remaining-time readout is 0.0. The speed comes
-- from the last swing's event payload (the addon never reads weapon-speed APIs
-- directly), so before the very first swing it is unknown and only the time
-- readout is shown.
function Bars:SetParkedText(bar)
	local db = Addon.db
	if db.showSpeed then
		if bar.speed then
			if db.showTime then
				bar.time:SetText(format("0.0 / %.2f", bar.speed))
			else
				bar.time:SetText(format("%.2f", bar.speed))
			end
		elseif db.showTime then
			bar.time:SetText("0.0")
		else
			bar.time:SetText("")
		end
	elseif db.showTime then
		bar.time:SetText("0.0")
	end
end

function Bars:ApplyText()
	local db = Addon.db
	for i = 1, #HAND_ORDER do
		local hand = HAND_ORDER[i]
		local bar = self.bars[hand]
		bar.label:SetShown(db.showLabel)
		bar.time:SetShown(db.showTime or db.showSpeed)
		bar.delta:SetShown(db.showDelta and hand == "offhand")
		if not bar.active then
			self:SetParkedText(bar)
		end
	end
end

function Bars:ApplyLayout()
	local db = Addon.db
	anchor:SetScale(db.scale)
	for i = 1, #HAND_ORDER do
		self.bars[HAND_ORDER[i]]:SetSize(db.width, db.height)
	end
	self:RestorePosition()
	self:UpdateVisibility()
end

function Bars:RestorePosition()
	local db = Addon.db
	anchor:ClearAllPoints()
	local relativeTo = db.relativeTo and _G[db.relativeTo] or UIParent
	anchor:SetPoint(db.point or "BOTTOM", relativeTo, db.relativePoint or "BOTTOM", db.x or 0, db.y or 0)
end

function Bars:HasWeapon(hand)
	local itemID = GetInventoryItemID("player", INVENTORY_SLOT[hand])
	if not itemID then
		return false
	end
	if hand == "offhand" then
		-- Shields and holds sit in the off-hand slot but never swing; only a
		-- real weapon there drives an off-hand swing timer.
		local _, _, _, _, _, itemClass, _, _, _, _, _, classID = GetItemInfo(itemID)
		if itemClass == nil and classID == nil then
			return true -- item data not cached; do not hide the bar on missing data
		end
		return itemClass == WEAPON_CLASS or classID == WEAPON_CLASS_ID
	end
	return true
end

function Bars:Relayout(visible)
	local db = Addon.db
	local offset = 0
	local count = 0
	for i = 1, #HAND_ORDER do
		local hand = HAND_ORDER[i]
		local bar = self.bars[hand]
		if visible[hand] then
			bar:ClearAllPoints()
			bar:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -offset)
			offset = offset + db.height + db.gap
			count = count + 1
		end
	end
	if count > 0 then
		offset = offset - db.gap
	end
	anchor:SetSize(db.width, math.max(offset, 1))
end

function Bars:UpdateVisibility()
	local db = Addon.db
	if not db or not self.bars then
		return
	end
	local mode = db.visibility
	local visible = {}
	local any = false
	for i = 1, #HAND_ORDER do
		local hand = HAND_ORDER[i]
		local bar = self.bars[hand]
		local show = db.enabled[hand]
		if show then
			if self.testing then
				show = true
			elseif mode == "always" then
				show = self:HasWeapon(hand)
			elseif mode == "combat" then
				show = Addon.inCombat and self:HasWeapon(hand)
			else -- "swinging"
				show = bar.active
			end
		end
		bar:SetShown(show)
		visible[hand] = show
		any = any or show
	end
	anchor:SetShown(any or not db.locked)
	overlay:SetShown(not db.locked)
	self:Relayout(visible)
end

function Bars:SetLocked(locked)
	if not self.bars then
		return
	end
	anchor:EnableMouse(not locked)
	if not locked then
		anchor:RegisterForDrag("LeftButton")
	end
	self:UpdateVisibility()
end

-- ---------------------------------------------------------------------------
-- Update loop
-- ---------------------------------------------------------------------------

anchor:SetScript("OnUpdate", function()
	Bars:OnUpdate()
end)

function Bars:OnUpdate()
	if not self.bars then
		return
	end
	local db = Addon.db
	local now = GetTime()
	local draining = db.fill ~= "fill"
	for i = 1, #HAND_ORDER do
		local bar = self.bars[HAND_ORDER[i]]
		if bar.active and bar.speed and bar.speed > 0 then
			local remaining = bar.expiration - now
			if remaining < 0 then
				remaining = 0
			end
			if draining then
				bar.status:SetValue(remaining / bar.speed)
			else
				bar.status:SetValue(1 - remaining / bar.speed)
			end
			if db.showTime then
				if db.showSpeed then
					bar.time:SetText(format("%.1f / %.2f", remaining, bar.speed))
				else
					bar.time:SetText(format("%.1f", remaining))
				end
			elseif db.showSpeed then
				bar.time:SetText(format("%.2f", bar.speed))
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Library events
-- ---------------------------------------------------------------------------

function Bars:SwingStart(hand, speed, expirationTime, isUpdate)
	local bar = self.bars[hand]
	if not bar then
		return
	end
	-- On WoW: Forever a mid-swing ranged UPDATE is the movement-cancelled
	-- Auto Shot reschedule: the engine pushed the shot back. Show the delay.
	if isUpdate and hand == "ranged" and bar.active
		and expirationTime > (bar.expiration or 0) + 0.05 then
		self:SetFillTint(bar, DELAY_TINT)
	end
	bar.speed = speed
	bar.expiration = expirationTime
	bar.active = true
	self:SetPaused(bar, false)
	self:UpdateVisibility()
end

function Bars:SwingStop(hand)
	local bar = self.bars[hand]
	if not bar then
		return
	end
	bar.active = false
	bar.expiration = nil
	self:SetPaused(bar, false)
	bar.status:SetValue(ParkedValue())
	self:SetParkedText(bar)
	bar.delta:SetText("")
	self:UpdateVisibility()
end

function Bars:SwingPaused(hand)
	local bar = self.bars[hand]
	if bar then
		self:SetPaused(bar, true)
	end
end

-- A swing reset by a cast: the interrupted-cast treatment - the fill turns
-- red and the bar shakes, decaying back to normal while the new swing runs.
function Bars:SwingClipped(hand)
	local bar = self.bars[hand]
	if not bar then
		return
	end
	self:SetFillTint(bar, CLIP_TINT)
	if bar.shake then
		bar.shake:Stop()
		bar.shake:Play()
	end
end

function Bars:SwingDelta(swingDelta)
	local db = Addon.db
	if not db.showDelta then
		return
	end
	local bar = self.bars.offhand
	if bar and bar:IsShown() then
		bar.delta:SetText(format("%+.2fs", swingDelta))
	end
end

function Bars:SeedFromLibrary()
	local lib = Addon.lib
	local now = GetTime()
	for i = 1, #HAND_ORDER do
		local hand = HAND_ORDER[i]
		local speed, expirationTime = lib:UnitSwingTimerInfo("player", hand)
		if speed and expirationTime and expirationTime > now then
			self:SwingStart(hand, speed, expirationTime)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Test mode and enable
-- ---------------------------------------------------------------------------

function Bars:Test()
	if not self.bars then
		return
	end
	local db = Addon.db
	local now = GetTime()
	self.testing = true
	for i = 1, #HAND_ORDER do
		local hand = HAND_ORDER[i]
		local bar = self.bars[hand]
		if db.enabled[hand] then
			self:SwingStart(hand, TEST_SPEED, now + TEST_SPEED)
		end
	end
	if self.testTimer then
		self.testTimer:Cancel()
	end
	self.testTimer = C_Timer.NewTimer(TEST_SPEED, function()
		self.testing = false
		for i = 1, #HAND_ORDER do
			self:SwingStop(HAND_ORDER[i])
		end
	end)
end

function Bars:ApplyAll()
	self:ApplySkin()
	self:ApplyText()
	self:SetLocked(Addon.db.locked)
	self:ApplyLayout()
	-- Re-park inactive bars so a fill/drain switch is reflected immediately.
	local parked = ParkedValue()
	for i = 1, #HAND_ORDER do
		local bar = self.bars[HAND_ORDER[i]]
		if not bar.active then
			bar.status:SetValue(parked)
		end
	end
end

function Bars:Enable(lib)
	if self.bars then
		return
	end
	self.bars = {}
	for i = 1, #HAND_ORDER do
		local hand = HAND_ORDER[i]
		self.bars[hand] = CreateBar(hand)
	end

	-- Library wiring, following the pattern from the library's own README:
	-- one handler function per registered event, receiving (event, ...).
	local function Handle(event, unitId, a, b, c)
		if unitId ~= "player" then
			return
		end
		if event == "UNIT_SWING_TIMER_START" or event == "UNIT_SWING_TIMER_UPDATE" then
			-- a = speed, b = expirationTime, c = hand
			Bars:SwingStart(c, a, b, event == "UNIT_SWING_TIMER_UPDATE")
		elseif event == "UNIT_SWING_TIMER_STOP" then
			Bars:SwingStop(a)
		elseif event == "UNIT_SWING_TIMER_PAUSED" then
			Bars:SwingPaused(a)
		elseif event == "UNIT_SWING_TIMER_CLIPPED" then
			Bars:SwingClipped(a)
		elseif event == "UNIT_SWING_TIMER_DELTA" then
			Bars:SwingDelta(a)
		elseif event == "UNIT_SWING_TIMER_INFO_INITIALIZED" then
			Bars:SeedFromLibrary()
		end
	end

	for i = 1, #LIB_EVENTS do
		lib.RegisterCallback(Bars, LIB_EVENTS[i], Handle)
	end

	self:ApplyAll()
end
