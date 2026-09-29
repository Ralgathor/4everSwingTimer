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
local IsCurrentSpell = C_Spell and C_Spell.IsCurrentSpell
local GetCVar = GetCVar
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
-- a movement-delayed ranged swing tints amber. The tint holds full for
-- TINT_HOLD seconds, then fades back to the skin's normal fill over TINT_FADE
-- seconds; the shake is a decaying ~0.7 s sway (Blizzard's exact recipe was
-- tested in play and read as too subtle on a peripheral bar), gated on the
-- ShakeStrengthUI CVar.
local CLIP_TINT = { 1.0, 0.25, 0.20 }
local DELAY_TINT = { 1.0, 0.60, 0.10 }
local TINT_HOLD = 0.45
local TINT_FADE = 0.30
local TINT_STEPS = 8
local SHAKE_STEP = 0.04
-- Early-landing (parry haste) feedback: the bar pops (scales up briefly)
-- with a green glow overlay and fill tint. The glow is a separate overlay
-- because the vertex tint modulates the native atlas fill's own colors -
-- green over amber reads muddy - while a plain overlay shows the intended
-- color regardless of skin. A STOP is followed by its START within one
-- library call, so the stop cannot be classified until a short grace period
-- shows whether a START follows and with which weapon speed.
local HASTE_TINT = { 0.30, 1.00, 0.40 }
local HASTE_GLOW = { 0.25, 1.00, 0.35 }
local HASTE_GLOW_ALPHA = 0.5
local HASTE_GLOW_TIME = 0.5
local HASTE_POP_SCALE = 1.15
local STOP_GRACE = 0.10
-- Queued next-melee highlight: while a next-melee ability is queued (base IDs;
-- ranks resolve through the base), the main-hand fill takes the queue color
-- and the pip - the tick riding the fill edge - gets an additive glow,
-- matching the casting bar's lit fill and spark treatment. C_Spell.
-- IsCurrentSpell probe-verified on the beta: plain booleans, true with
-- Heroic Strike queued. The fill swaps to the plain texture while queued
-- because a vertex tint would modulate the native atlas fill's own colors.
local QUEUED_SPELLS = { 78, 845, 2973, 6807 } -- Heroic Strike, Cleave, Raptor Strike, Maul
-- The cast bar's own assets (verified in Blizzard_UIPanels_Game on the
-- forever branch): the fill gradient is baked into the ui-castingbar-filling-
-- standard atlas, the tick is ui-castingbar-pip, and the glow behind the tick
-- is cast_standard_pipglow in ADD blend - a streak anchored to the pip's left.
-- The queued fill keeps the swing bar's own art and takes the cast bar's
-- classic yellow as a vertex tint (the cast bar's fill atlas swap was tested
-- in play and rejected - the swing bar should keep its identity).
local QUEUED_TINT = { 1.00, 0.82, 0.20 }
local CASTBAR_PIP_RED_ATLAS = "ui-castingbar-pip-red"
local CASTBAR_PIP_GLOW_ATLAS = "cast_standard_pipglow"
-- The statusbar is inset within the bar frame (5px sides, 4px top/bottom):
-- the cast art scales to the STATUSBAR's height, not the frame's.
local STATUS_INSET_X = 5
local STATUS_INSET_Y = 4
-- Tick art sizing: automatic, proportional to the statusbar with a slight
-- overhang (1.1x), calibrated against the in-play choices made at both
-- extremes of the height range (10px at the default bar, 36px at the
-- maximum - both equal to their statusbar height x ~1.1). No manual setting:
-- the tick follows the bar, with a floor so tiny bars still show one. One
-- tick identity everywhere: the swing bar's own pip atlas, height-scaled via
-- its own aspect. The glow keeps the cast bar's proportions relative to the
-- tick (37x12 glow vs 8x20 pip).
local TICK_STATUSBAR_RATIO = 1.1
local CASTBAR_GLOW_RATIO_W = 37 / 20
local CASTBAR_GLOW_RATIO_H = 12 / 20

-- Shared tick height across all tick variants.
local function TickHeight()
	return math.max((Addon.db.height - STATUS_INSET_Y * 2) * TICK_STATUSBAR_RATIO, 8)
end

local function GlowSize()
	local tickHeight = TickHeight()
	return tickHeight * CASTBAR_GLOW_RATIO_W, tickHeight * CASTBAR_GLOW_RATIO_H
end

-- The swing bar's own pip at the automatic tick height, aspect preserved.
local function ApplyPipSize(bar)
	bar.pip:SetAtlas(PIP_ATLAS, true)
	local nativeW, nativeH = bar.pip:GetSize()
	local tickHeight = TickHeight()
	if nativeH and nativeH > 0 then
		bar.pip:SetSize(tickHeight * (nativeW / nativeH), tickHeight)
	end
end
local QUEUE_POLL = 0.20

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

-- Interrupted-cast shake: alternating horizontal translation keyframes with
-- decaying amplitude (~0.7 s). Blizzard's exact InterruptShakeAnim was tested
-- in play (1-2 px jitter, ~0.3 s) and read as too subtle on a swing bar that
-- lives in peripheral vision. Defined before CreateBar, which calls it - Lua
-- locals are lexically scoped.
local function CreateShakeAnimation(bar)
	local group = bar:CreateAnimationGroup()
	-- Decaying amplitude: strongest jolt first, easing to rest, ~0.7 s total.
	local offsets = { -6, 6, -5, 5, -4, 4, -3, 3, -2, 2, -1.5, 1.5, -1, 1, -0.5, 0.5, 0 }
	for i = 1, #offsets do
		local anim = group:CreateAnimation("Translation")
		anim:SetOffset(offsets[i], 0)
		anim:SetDuration(SHAKE_STEP)
		anim:SetOrder(i)
	end
	return group
end

-- Early-landing feedback: the bar scales up briefly and settles - far more
-- visible than a small offset wiggle, and distinct from the interrupt's
-- horizontal shake.
local function CreatePopAnimation(bar)
	local group = bar:CreateAnimationGroup()
	local grow = group:CreateAnimation("Scale")
	grow:SetScale(HASTE_POP_SCALE, HASTE_POP_SCALE)
	grow:SetOrigin("CENTER", 0, 0)
	grow:SetDuration(0.07)
	grow:SetOrder(1)
	local shrink = group:CreateAnimation("Scale")
	shrink:SetScale(1 / HASTE_POP_SCALE, 1 / HASTE_POP_SCALE)
	shrink:SetOrigin("CENTER", 0, 0)
	shrink:SetDuration(0.15)
	shrink:SetOrder(2)
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
	bar.status:SetPoint("TOPLEFT", bar, "TOPLEFT", STATUS_INSET_X, -STATUS_INSET_Y)
	bar.status:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -STATUS_INSET_X, STATUS_INSET_Y)
	bar.status:SetMinMaxValues(0, 1)
	bar.status:SetValue(0)
	bar.status:SetStatusBarTexture(FLAT_TEXTURE)

	bar.pip = bar.status:CreateTexture(nil, "OVERLAY")
	bar.pip:SetAtlas(PIP_ATLAS, true)
	-- Initial anchor matches UpdateTickPosition's form (a second, differently
	-- named anchor would coexist with it and conflict).
	bar.pip:SetPoint("CENTER", bar.status, "LEFT", 0, 0)

	-- Queued-state spark glow, exactly the cast bar's StandardGlow: the
	-- cast_standard_pipglow atlas in ADD blend, a streak to the left of the
	-- pip (its RIGHT edge anchors to the pip's LEFT, +2px like the XML).
	bar.queuedGlow = bar.status:CreateTexture(nil, "OVERLAY")
	bar.queuedGlow:SetAtlas(CASTBAR_PIP_GLOW_ATLAS)
	bar.queuedGlow:SetBlendMode("ADD")
	bar.queuedGlow:SetSize(37, 12)
	bar.queuedGlow:SetPoint("RIGHT", bar.pip, "LEFT", 2, 0)
	bar.queuedGlow:Hide()
	bar.glowWanted = false

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
	-- Early-landing (parry haste) pop and glow overlay.
	bar.pop = CreatePopAnimation(bar)
	bar.hasteGlow = bar.status:CreateTexture(nil, "OVERLAY")
	bar.hasteGlow:SetAllPoints(bar.status)
	bar.hasteGlow:SetColorTexture(HASTE_GLOW[1], HASTE_GLOW[2], HASTE_GLOW[3], HASTE_GLOW_ALPHA)
	bar.hasteGlow:SetAlpha(0)
	bar.hasteGlow:Hide()
	bar.hasteGlowFade = bar.hasteGlow:CreateAnimationGroup()
	local hasteFade = bar.hasteGlowFade:CreateAnimation("Alpha")
	hasteFade:SetFromAlpha(HASTE_GLOW_ALPHA)
	hasteFade:SetToAlpha(0)
	hasteFade:SetDuration(HASTE_GLOW_TIME)
	bar.hasteGlowFade:SetScript("OnFinished", function()
		bar.hasteGlow:Hide()
	end)

	bar.active = false
	bar.paused = false
	bar.queued = false
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

local function Lerp(a, b, t)
	return a + (b - a) * t
end

-- Temporarily tints the fill, holds it full for TINT_HOLD seconds, then fades
-- back to the skin's normal color over TINT_FADE seconds in stepped lerps.
-- Works for both skins: the atlas fill of the native skin and the colored
-- plain fill of the flat skin are both tinted via the statusbar texture's
-- vertex color. A generation counter invalidates scheduled steps when a new
-- tint supersedes an unfinished one.
function Bars:SetFillTint(bar, tint)
	bar.tintGen = (bar.tintGen or 0) + 1
	local gen = bar.tintGen
	local texture = bar.status:GetStatusBarTexture()
	if texture then
		texture:SetVertexColor(tint[1], tint[2], tint[3])
	end
	C_Timer.NewTimer(TINT_HOLD, function()
		Bars:FadeFillBack(bar, tint, gen)
	end)
end

function Bars:FadeFillBack(bar, tint, gen)
	if (bar.tintGen or 0) ~= gen then
		return
	end
	local texture = bar.status:GetStatusBarTexture()
	if not texture then
		return
	end
	local targetR, targetG, targetB = self:GetBaseFillColor(bar)
	local stepDuration = TINT_FADE / TINT_STEPS
	for step = 1, TINT_STEPS do
		C_Timer.NewTimer(step * stepDuration, function()
			if (bar.tintGen or 0) ~= gen then
				return
			end
			if step == TINT_STEPS then
				-- Fade complete: restore the whole base appearance, including
				-- the pip the interrupt swapped to the red cast-bar pip.
				self:ApplyFillStyle(bar)
				return
			end
			local t = step / TINT_STEPS
			texture:SetVertexColor(
				Lerp(tint[1], targetR, t),
				Lerp(tint[2], targetG, t),
				Lerp(tint[3], targetB, t)
			)
		end)
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

-- Position the tick manually, the way the cast bar positions its spark
-- (value * width from the statusbar's left), instead of anchoring to the
-- fill texture's edge: in drain mode a parked bar sits at value 0, where the
-- zero-width fill's edge left the tick and glow dangling outside the bar.
-- Clamped inside so the tick stays visible at the extremes. The glow trails
-- to the tick's left and is hidden when it would extend outside the bar
-- frame (e.g. the tick sitting at the left edge on an empty drain bar).
function Bars:UpdateTickPosition(bar)
	local statusWidth = bar.status:GetWidth()
	if statusWidth <= 0 then
		return
	end
	local pipWidth = bar.pip:GetWidth()
	local x = bar.status:GetValue() * statusWidth
	x = math.max(pipWidth / 2, math.min(x, statusWidth - pipWidth / 2))
	bar.pip:SetPoint("CENTER", bar.status, "LEFT", x, 0)
	if bar.glowWanted then
		local glowWidth = bar.queuedGlow:GetWidth()
		local glowLeft = x - pipWidth / 2 - 2 - glowWidth
		bar.queuedGlow:SetShown(glowLeft >= -STATUS_INSET_X)
	else
		bar.queuedGlow:Hide()
	end
end

-- The fill appearance: the skin's own fill art always; the queued state is a
-- color change (the cast bar's yellow), while the tick swaps to the cast
-- bar's pip with its glow streak. Flash tints layer on top of this base as
-- vertex color.
function Bars:ApplyFillStyle(bar)
	local db = Addon.db
	local queued = db.highlightQueued and bar.queued
	if db.skin == "native" then
		bar.status:SetStatusBarTexture(FILL_ATLAS[bar.hand])
	else
		bar.status:SetStatusBarTexture(FLAT_TEXTURE)
	end
	local texture = bar.status:GetStatusBarTexture()
	if texture then
		if queued then
			texture:SetVertexColor(QUEUED_TINT[1], QUEUED_TINT[2], QUEUED_TINT[3])
		elseif db.skin == "native" then
			texture:SetVertexColor(1, 1, 1)
		else
			local color = FLAT_COLORS[bar.hand]
			texture:SetVertexColor(color[1], color[2], color[3])
		end
	end
	-- The glow trails to the tick's left (the cast bar's own anchor, +2px) -
	-- no direction flip. UpdateTickPosition hides it when it would extend
	-- outside the bar frame instead. ClearAllPoints first: differently named
	-- anchors coexist in WoW, and conflicting anchors collapse regions.
	bar.queuedGlow:ClearAllPoints()
	bar.queuedGlow:SetPoint("RIGHT", bar.pip, "LEFT", 2, 0)
	-- One tick identity everywhere: the swing bar's own pip, height-scaled;
	-- the queued state adds the fill tint and the glow, not a different tick.
	ApplyPipSize(bar)
	local glowW, glowH = GlowSize()
	bar.queuedGlow:SetSize(glowW, glowH)
	bar.pip:SetVertexColor(1, 1, 1)
	if queued then
		bar.pip:Show()
		bar.glowWanted = true
	else
		bar.glowWanted = false
		if db.skin == "native" then
			bar.pip:Show()
		else
			bar.pip:Hide()
		end
	end
	self:UpdateTickPosition(bar)
end

-- The base fill color an interrupt/delay tint fades back to.
function Bars:GetBaseFillColor(bar)
	local db = Addon.db
	if db.highlightQueued and bar.queued then
		return QUEUED_TINT[1], QUEUED_TINT[2], QUEUED_TINT[3]
	end
	if db.skin == "native" then
		return 1, 1, 1
	end
	local color = FLAT_COLORS[bar.hand]
	return color[1], color[2], color[3]
end

-- Polled at QUEUE_POLL: no event exists for queued-state changes, and
-- IsCurrentSpell is a cheap client-side call (four lookups per tick).
function Bars:UpdateQueued()
	local db = Addon.db
	if not db.highlightQueued or not IsCurrentSpell then
		return
	end
	local bar = self.bars and self.bars.mainhand
	if not bar then
		return
	end
	local queued = false
	for i = 1, #QUEUED_SPELLS do
		if IsCurrentSpell(QUEUED_SPELLS[i]) then
			queued = true
			break
		end
	end
	if queued ~= bar.queued then
		bar.queued = queued
		self:ApplyFillStyle(bar)
	end
end

function Bars:SetHighlightQueued(enabled)
	if not self.bars then
		return
	end
	local bar = self.bars.mainhand
	if not bar then
		return
	end
	if not enabled then
		-- Clear the indicator immediately; enabling needs no action - the
		-- poll picks it up within QUEUE_POLL.
		bar.queued = false
		self:ApplyFillStyle(bar)
	end
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
		else
			bar.bg:SetColorTexture(0, 0, 0, 0.55)
			bar.border:SetColorTexture(0, 0, 0, 0.85)
		end
		-- The fill and pip follow the queued state first, the skin second.
		self:ApplyFillStyle(bar)
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
			self:UpdateTickPosition(bar)
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
	if not isUpdate then
		local now = GetTime()
		if bar.active and bar.expiration and bar.expiration > now + 0.05 then
			-- A START while a swing is still in flight is the cast-completion
			-- swing reset: the library restarts the swing with isReset=true,
			-- which SUPPRESSES the STOP event (Unit:SwingStart), so no stop and
			-- no CLIPPED ever reaches the addon on that path.
			self:InterruptFeedback(bar)
		elseif bar.stoppedInFlight and now - (bar.stoppedAt or 0) <= STOP_GRACE + 0.05 then
			-- A START right after an in-flight stop: classify by weapon speed.
			bar.stoppedInFlight = nil
			local speedAtStop = bar.speedAtStop
			local sameSpeed = speedAtStop and speed and math.abs(speed - speedAtStop) <= math.max(speedAtStop * 0.02, 0.01)
			if sameSpeed then
				-- Early landing with the same weapon: the engine shortened the
				-- swing mid-flight. On WoW: Forever that is parry haste (no
				-- addon-facing parry API exists; the library re-anchors and the
				-- hastened swing simply lands early - a mid-swing haste proc
				-- produces the same signature).
				self:SetFillTint(bar, HASTE_TINT)
				if bar.pop then
					bar.pop:Stop()
					bar.pop:Play()
				end
				if bar.hasteGlow and bar.hasteGlowFade then
					bar.hasteGlow:Show()
					bar.hasteGlowFade:Stop()
					bar.hasteGlowFade:Play()
				end
			else
				-- Different weapon speed: a weapon swap restart; the old swing
				-- was cut short.
				self:InterruptFeedback(bar)
			end
		end
	elseif hand == "ranged" and bar.active
		and expirationTime > (bar.expiration or 0) + 0.05 then
		-- On WoW: Forever a mid-swing ranged UPDATE is the movement-cancelled
		-- Auto Shot reschedule: the engine pushed the shot back. Show the delay.
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
	-- A stop while the swing is still in flight means the swing was cut short
	-- or landed early; WHICH of the two is only knowable after a short grace
	-- period, because the library fires a restart as STOP+START inside one
	-- call. Record the facts and let the grace timer (or the START that beats
	-- it) decide the feedback.
	bar.stoppedInFlight = (bar.active and bar.expiration and bar.expiration > GetTime() + 0.05) or nil
	bar.stoppedAt = GetTime()
	bar.speedAtStop = bar.speed
	bar.stopGen = (bar.stopGen or 0) + 1
	local gen = bar.stopGen
	C_Timer.NewTimer(STOP_GRACE, function()
		Bars:FinishStopFeedback(bar, gen)
	end)
	bar.active = false
	bar.expiration = nil
	self:SetPaused(bar, false)
	bar.status:SetValue(ParkedValue())
	self:UpdateTickPosition(bar)
	self:SetParkedText(bar)
	bar.delta:SetText("")
	self:UpdateVisibility()
end

-- Fires STOP_GRACE seconds after an in-flight stop, unless a START already
-- classified it: nothing followed, so the swing was simply cut short (death,
-- auto-attack stopped, unequipped mid-combat).
function Bars:FinishStopFeedback(bar, gen)
	if (bar.stopGen or 0) ~= gen or not bar.stoppedInFlight then
		return
	end
	bar.stoppedInFlight = nil
	self:InterruptFeedback(bar)
end

function Bars:SwingPaused(hand)
	local bar = self.bars[hand]
	if bar then
		self:SetPaused(bar, true)
	end
end

-- The interrupted-cast treatment (red tint + red pip + shake), shared by the
-- clip event and in-flight stops.
function Bars:InterruptFeedback(bar)
	self:SetFillTint(bar, CLIP_TINT)
	-- The cast bar's interrupted spark: the tick swaps to the red pip atlas,
	-- height-scaled like the normal tick via its own aspect.
	bar.pip:SetAtlas(CASTBAR_PIP_RED_ATLAS, true)
	local redW, redH = bar.pip:GetSize()
	local tickHeight = TickHeight()
	if redH and redH > 0 then
		bar.pip:SetSize(tickHeight * (redW / redH), tickHeight)
	end
	if bar.shake then
		-- Blizzard gates the shake on the ShakeStrengthUI CVar; an absent CVar
		-- (client without the setting) defaults to enabled.
		local strength = tonumber(GetCVar("ShakeStrengthUI"))
		if strength == nil or strength > 0 then
			bar.shake:Stop()
			bar.shake:Play()
		end
	end
end

-- A swing reset by a cast: the interrupted-cast treatment - the fill turns
-- red and the bar shakes, decaying back to normal while the new swing runs.
function Bars:SwingClipped(hand)
	local bar = self.bars[hand]
	if not bar then
		return
	end
	self:InterruptFeedback(bar)
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

-- Diagnostic dump for the tick system: run /4everswingtimer debug while the
-- symptom is on screen and read the actual runtime values.
function Bars:Debug()
	if not self.bars then
		Addon:Print("Bars not enabled (library missing).")
		return
	end
	local db = Addon.db
	print("|cff33ccff" .. Addon.name .. "|r debug: fill=" .. db.fill .. " skin=" .. db.skin
		.. " height=" .. tostring(db.height) .. " scale=" .. tostring(db.scale))
	for i = 1, #HAND_ORDER do
		local hand = HAND_ORDER[i]
		local bar = self.bars[hand]
		local value = bar.status:GetValue()
		local statusWidth = bar.status:GetWidth()
		local pipWidth = bar.pip:GetWidth()
		local pipLeft = bar.pip:GetLeft() or -1
		local statusLeft = bar.status:GetLeft() or -1
		print(format("%s: active=%s value=%.3f statusW=%.1f pipW=%.1f pipShown=%s glowShown=%s queued=%s pipOffsetFromBar=%.1f",
			hand, tostring(bar.active), value, statusWidth, pipWidth,
			tostring(bar.pip:IsShown()), tostring(bar.queuedGlow:IsShown()), tostring(bar.queued),
			pipLeft - statusLeft))
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

	-- Queued next-melee highlight poll.
	self.queueTicker = C_Timer.NewTicker(QUEUE_POLL, function()
		Bars:UpdateQueued()
	end)

	self:ApplyAll()
end
