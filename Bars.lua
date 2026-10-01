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
local BASE_FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
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
local LABEL_SHADOW_ATLAS = "ui-swingtimerbar-textshadow-left"
local FLAT_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
-- Flat style palettes: curated trios only, no free color pickers. In the
-- flat style the effects REPLACE the bar color wholesale, so a base near an
-- effect color makes that effect invisible (the original gold main hand
-- swallowed the queued yellow; crimson swallowed the interrupt red). Every
-- palette is chosen for distance from the effect colors - yellow (queued),
-- red (interrupt), amber (delay), green (haste) - so the constraint is
-- satisfied by construction rather than left to the user.
local FLAT_PALETTES = {
	silver = {
		label = "Silver, Blue, Violet",
		colors = {
			mainhand = { 0.92, 0.92, 0.95 },
			offhand = { 0.36, 0.60, 1.00 },
			ranged = { 0.70, 0.40, 0.90 },
		},
	},
	steel = {
		label = "Steel, Sky, Indigo",
		colors = {
			mainhand = { 0.80, 0.85, 0.90 },
			offhand = { 0.45, 0.75, 1.00 },
			ranged = { 0.45, 0.45, 0.85 },
		},
	},
	graphite = {
		label = "Graphite (shades of gray)",
		colors = {
			mainhand = { 0.95, 0.95, 0.95 },
			offhand = { 0.70, 0.70, 0.70 },
			ranged = { 0.45, 0.45, 0.45 },
		},
	},
	rose = {
		label = "Rose, Ocean, Plum",
		colors = {
			mainhand = { 0.98, 0.55, 0.70 },
			offhand = { 0.30, 0.65, 0.95 },
			ranged = { 0.55, 0.35, 0.75 },
		},
	},
}
local FLAT_PALETTE_ORDER = { "silver", "steel", "graphite", "rose" }
local FLAT_PALETTE_DEFAULT = "silver"
Addon.FLAT_PALETTES = FLAT_PALETTES
Addon.FLAT_PALETTE_ORDER = FLAT_PALETTE_ORDER
Addon.FLAT_PALETTE_DEFAULT = FLAT_PALETTE_DEFAULT

local function FlatColor(hand)
	local palette = FLAT_PALETTES[Addon.db.flatPalette] or FLAT_PALETTES[FLAT_PALETTE_DEFAULT]
	local color = palette.colors[hand]
	return color[1], color[2], color[3]
end
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
local DELAY_GLOW_ALPHA = 0.5
local DELAY_GLOW_TIME = 0.5
-- Movement-delay retriggers: a stuttering Auto Shot can reschedule several
-- times within a second, and every UPDATE is a genuine reschedule - but the
-- burst must not refire while the previous one is still running: Stop/Play
-- mid-flight snaps the recoil back to rest and teleports the streak to its
-- launch point. One burst per window; the window outlasts every animation
-- in the treatment, so a permitted retrigger always starts from rest.
local DELAY_RETRIGGER_WINDOW = 0.5
local TINT_HOLD = 0.45
local TINT_FADE = 0.30
local TINT_STEPS = 8
local SHAKE_STEP = 0.04
-- Parry-haste feedback: the bar pops (scales up briefly) with a green glow
-- overlay and fill tint. With the library's parry fix (ApplyParryHaste) the
-- stack fires in real time off the mid-swing melee UPDATE; on library builds
-- without it, the fallback infers the haste from an early landing - a STOP is
-- followed by its START within one library call, so the stop cannot be
-- classified until a short grace period shows whether a START follows and with
-- which weapon speed. The glow is a separate overlay because the vertex tint
-- modulates the native atlas fill's own colors - green over amber reads muddy
-- - while a plain overlay shows the intended color regardless of skin.
local HASTE_TINT = { 0.30, 1.00, 0.40 }
local HASTE_GLOW = { 0.25, 1.00, 0.35 }
local HASTE_GLOW_ALPHA = 0.5
local HASTE_GLOW_TIME = 0.5
local BURST_SCALE = 1.06
local BURST_OUT = 0.06
local BURST_BACK = 0.20
local STREAK_TIME = 0.25
local STOP_GRACE = 0.10
-- A swing stopping with less than this remaining is a natural completion,
-- not an early landing: the engine's PLAYER_SWING and the library's own
-- expiration timer race by up to a frame at every swing, and that jitter
-- must not read as parry haste. Genuine parry haste lands the swing at
-- least ~40% of the weapon speed early (floored at 20% remaining), far
-- above this threshold.
local EARLY_LANDING_EPSILON = 0.2
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
local CASTBAR_INTERRUPT_GLOW_ATLAS = "cast_interrupt_outerglow"
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
-- its own aspect.
local TICK_STATUSBAR_RATIO = 1.1

-- Shared tick height across all tick variants.
local function TickHeight()
	return math.max((Addon.db.height - STATUS_INSET_Y * 2) * TICK_STATUSBAR_RATIO, 8)
end

-- The glow uses the cast bar's own proportions, scaled to the fill: 12px on
-- a 13px bar (~92% of the fill height - full height read too tall, 85% left
-- the glow shorter than the tick's overhang) and 37 wide on the same bar.
local CASTBAR_GLOW_WIDTH_RATIO = 37 / 13
local CASTBAR_GLOW_HEIGHT_RATIO = 12 / 13

local function GlowSize()
	local fillHeight = Addon.db.height - STATUS_INSET_Y * 2
	return math.max(fillHeight * CASTBAR_GLOW_WIDTH_RATIO, 8),
		math.max(fillHeight * CASTBAR_GLOW_HEIGHT_RATIO, 4)
end

-- The pip at the automatic tick height, aspect preserved. Without an
-- atlas argument this is the swing bar's own pip; the interrupt treatment
-- passes the cast bar's red pip.
local function ApplyPipSize(bar, atlas)
	bar.pip:SetAtlas(atlas or PIP_ATLAS, true)
	local nativeW, nativeH = bar.pip:GetSize()
	local tickHeight = TickHeight()
	if nativeH and nativeH > 0 then
		bar.pip:SetSize(tickHeight * (nativeW / nativeH), tickHeight)
	end
end

-- Fires a contained streak flight across the fill: rightward flights use the
-- plain streak, leftward flights the mirrored one, and in both directions
-- the head launches at the fill's leading edge and travels to the far end.
-- The launch shifts inside when the fill edge is too close to the near end
-- for the tail to fit, so the whole flight stays inside the bar.
local function FireStreak(bar, streak, shot, group, reverse)
	if group:IsPlaying() then
		-- A flight is already running: restarting would snap it back to its
		-- launch point mid-air. Let it finish; the tint still carries the
		-- new event.
		return
	end
	local statusWidth = bar.status:GetWidth()
	local fillHeight = Addon.db.height - STATUS_INSET_Y * 2
	local edge = bar.status:GetValue() * statusWidth
	local streakWidth = math.min(math.max(statusWidth * 0.3, 40), statusWidth)
	streak:SetSize(streakWidth, math.max(fillHeight * CASTBAR_GLOW_HEIGHT_RATIO, 4))
	if reverse then
		-- The head is the LEFT edge: launch at the fill edge unless the tail
		-- would pass the right end - then from just inside it.
		local start = math.min(edge, statusWidth - streakWidth)
		streak:SetPoint("LEFT", bar.status, "LEFT", start, 0)
		shot:SetOffset(-start, 0)
	else
		-- The head is the RIGHT edge: launch at the fill edge unless the tail
		-- would pass the left end - then from just inside it.
		local start = math.max(edge, streakWidth)
		streak:SetPoint("RIGHT", bar.status, "LEFT", start, 0)
		shot:SetOffset(statusWidth - start, 0)
	end
	group:Stop()
	streak:Show()
	group:Play()
end

-- "Forward" is the direction the fill's leading edge travels as the swing
-- progresses - rightward in fill mode, leftward in drain mode. Haste pulls
-- the landing forward, delay pushes it back, so each effect's burst inverts
-- when the fill mode inverts.
local function ForwardIsLeft()
	return Addon.db.fill ~= "fill"
end

-- The burst core shared by haste and delay: the directional bar stretch plus
-- the streak flight, in the effect's color. Leftward bursts pair the
-- RIGHT-origin stretch (bar.recoil) with the mirrored streak; rightward
-- bursts pair the LEFT-origin stretch (bar.pop) with the plain streak. Both
-- streak textures are desaturated, so the vertex color set here fully
-- controls their tint.
local function FireBurst(bar, color, leftward)
	local stretch, streak, shot, group
	if leftward then
		stretch, streak, shot, group = bar.recoil, bar.delayStreak, bar.delayStreakShot, bar.delayStreakFX
	else
		stretch, streak, shot, group = bar.pop, bar.streak, bar.streakShot, bar.streakFX
	end
	if stretch and not stretch:IsPlaying() then
		stretch:Play()
	end
	if streak and group then
		streak:SetVertexColor(color[1], color[2], color[3])
		FireStreak(bar, streak, shot, group, leftward)
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

-- Test buttons under the bars (shown while unlocked): the swing animation
-- and each effect treatment, all through the same handlers as the
-- /4everswingtimer test commands.
local function CreateOverlayButton(overlay, text, onClick)
	local button = CreateFrame("Button", nil, overlay, "UIPanelButtonTemplate")
	button:SetSize(74, 20)
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	return button
end

overlay.testButton = CreateOverlayButton(overlay, "Swing", function()
	Bars:Test()
end)
overlay.testButton:SetPoint("TOPLEFT", overlay, "BOTTOMLEFT", 0, -2)
local previous = overlay.testButton
local effectButtons = {
	{ label = "Interrupt", effect = "interrupt" },
	{ label = "Haste", effect = "haste" },
	{ label = "Delay", effect = "delay" },
	{ label = "Queued", effect = "queued" },
}
for i = 1, #effectButtons do
	local def = effectButtons[i]
	local button = CreateOverlayButton(overlay, def.label, function()
		Bars:TestEffect(def.effect)
	end)
	button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
	previous = button
end

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

-- Burst feedback, mirrored by direction: an X-only Scale whose origin sits on
-- the bar edge OPPOSITE the travel, so the bar extends only toward its motion.
-- Haste ("LEFT") lunges rightward - a speed burst in the direction of swing
-- progress; delay ("RIGHT") recoils leftward - time pushed back. The attack
-- uses OUT smoothing (instant velocity, decelerating in) and settles with
-- IN_OUT, so the burst reads snappy without a hard stop.
local function CreatePopAnimation(bar, origin)
	local group = bar:CreateAnimationGroup()
	local lunge = group:CreateAnimation("Scale")
	lunge:SetScale(BURST_SCALE, 1)
	lunge:SetOrigin(origin, 0, 0)
	lunge:SetDuration(BURST_OUT)
	lunge:SetSmoothing("OUT")
	lunge:SetOrder(1)
	local settle = group:CreateAnimation("Scale")
	settle:SetScale(1 / BURST_SCALE, 1)
	settle:SetOrigin(origin, 0, 0)
	settle:SetDuration(BURST_BACK)
	settle:SetSmoothing("IN_OUT")
	settle:SetOrder(2)
	return group
end

-- The cast bar's interrupt outer glow as a reusable halo: the
-- cast_interrupt_outerglow atlas in ADD blend, atlas-sized at half scale
-- (useAtlasSize + scale 0.5 in CastingBarFrame.xml, fixed size regardless of
-- bar size), centered on the bar; flashed to fromAlpha and faded to zero over
-- fadeDuration, hidden when the fade finishes. BACKGROUND draw layer on the
-- bar frame, sublevel -1 - below the skin's bg and border regions (default
-- sublevel 0) like the native InterruptGlow, which CastingBarFrameBaseTemplate
-- puts in BACKGROUND textureSubLevel 1, under its own Background (sublevel
-- 2): the halo fringes outside the bar's silhouette instead of washing over
-- the fill, text or border.
local function CreateCenterGlow(bar, fromAlpha, fadeDuration)
	local glow = bar:CreateTexture(nil, "BACKGROUND")
	glow:SetDrawLayer("BACKGROUND", -1)
	glow:SetAtlas(CASTBAR_INTERRUPT_GLOW_ATLAS, true)
	local width, height = glow:GetSize()
	glow:SetSize(width * 0.5, height * 0.5)
	glow:SetPoint("CENTER", bar.status, "CENTER", 0, 0)
	glow:SetBlendMode("ADD")
	glow:SetAlpha(0)
	glow:Hide()
	local fade = glow:CreateAnimationGroup()
	local anim = fade:CreateAnimation("Alpha")
	anim:SetFromAlpha(fromAlpha)
	anim:SetToAlpha(0)
	anim:SetDuration(fadeDuration)
	fade:SetScript("OnFinished", function()
		glow:Hide()
	end)
	return glow, fade
end

-- The flight streak shared by the haste and delay bursts: the cast bar's
-- pip-glow streak (cast_standard_pipglow), desaturated so the play-time
-- vertex color fully controls the tint, with the OUT-eased translation and
-- the fade on one animation group. MIRRORED horizontally for the leftward
-- flight, so the bright end leads either direction. Returns the texture,
-- its group and the translation anim; FireStreak sets anchor, size and
-- travel at play time.
local function CreateStreak(bar, mirrored)
	local streak = bar.status:CreateTexture(nil, "OVERLAY")
	streak:SetAtlas(CASTBAR_PIP_GLOW_ATLAS, true)
	if mirrored then
		local ulx, uly, llx, lly, urx, ury, lrx, lry = streak:GetTexCoord()
		if lrx then
			-- Eight-value texcoords (atlas textures): UL<->UR, LL<->LR.
			streak:SetTexCoord(urx, ury, lrx, lry, ulx, uly, llx, lly)
		else
			-- Four-value form: ULx,ULy and LRx,LRy swap.
			streak:SetTexCoord(llx, lly, ulx, uly)
		end
	end
	streak:SetDesaturated(true)
	streak:SetBlendMode("ADD")
	streak:Hide()
	local group = streak:CreateAnimationGroup()
	local shot = group:CreateAnimation("Translation")
	shot:SetDuration(STREAK_TIME)
	shot:SetSmoothing("OUT")
	shot:SetOrder(1)
	local fade = group:CreateAnimation("Alpha")
	fade:SetFromAlpha(0.9)
	fade:SetToAlpha(0)
	fade:SetDuration(STREAK_TIME)
	fade:SetOrder(1)
	group:SetScript("OnFinished", function()
		streak:Hide()
	end)
	return streak, group, shot
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
	-- The label shadow matches the native bar's TypeLabelShadow (171px wide,
	-- left-anchored, full statusbar height) and is created before the text so
	-- it draws under it.
	bar.labelShadow = bar.status:CreateTexture(nil, "OVERLAY")
	bar.labelShadow:SetAtlas(LABEL_SHADOW_ATLAS)
	bar.labelShadow:SetWidth(171)
	bar.labelShadow:SetPoint("TOPLEFT", bar.status, "TOPLEFT", 0, 0)
	bar.labelShadow:SetPoint("BOTTOMLEFT", bar.status, "BOTTOMLEFT", 0, 0)

	bar.label = bar.status:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.label:SetPoint("LEFT", bar.status, "LEFT", 10, 0)
	bar.label:SetText(HAND_LABEL[hand])

	bar.delta = bar.status:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.delta:SetPoint("LEFT", bar.label, "RIGHT", 8, 0)

	bar.time = bar.status:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.time:SetPoint("RIGHT", bar.status, "RIGHT", -10, 0)
	bar.time:SetText("0.0")

	-- The cast bar's interrupted outer glow, flashed to full and faded to
	-- zero over exactly 1.0 s (InterruptGlowAnim). BACKGROUND sublevel -1 on
	-- the bar frame, so the glow stays behind the bg, border, fill and text -
	-- the native glow never covers anything either.
	bar.interruptGlow, bar.interruptGlowFade = CreateCenterGlow(bar, 1.0, 1.0)

	-- Interrupted-cast shake: alternating horizontal translation keyframes,
	-- the same mechanism the 12.x casting bar uses (InterruptShakeAnim).
	bar.shake = CreateShakeAnimation(bar)
	-- Early-landing (parry haste) pop and outer glow. The glow reuses the
	-- cast bar's interrupt outer-glow ATLAS (no green glow art exists in the
	-- client), DESATURATED so the green vertex tint renders it as pure green
	-- shades instead of multiplying with the art's red - same soft halo shape
	-- as the interrupt, properly green.
	-- Directional burst stretches, shared by the haste and delay bursts and
	-- picked per direction by FireBurst: the LEFT-origin stretch extends the
	-- bar rightward (fill-mode haste, drain-mode delay), the RIGHT-origin
	-- stretch leftward (fill-mode delay, drain-mode haste).
	bar.pop = CreatePopAnimation(bar, "LEFT")
	bar.recoil = CreatePopAnimation(bar, "RIGHT")
	bar.hasteGlow, bar.hasteGlowFade = CreateCenterGlow(bar, HASTE_GLOW_ALPHA, HASTE_GLOW_TIME)
	bar.hasteGlow:SetDesaturated(true)
	bar.hasteGlow:SetVertexColor(HASTE_GLOW[1], HASTE_GLOW[2], HASTE_GLOW[3])
	-- The two flight streaks, one per direction: the rightward one plain
	-- (its tail trails left, the right shape for rightward motion), the
	-- leftward one mirrored so its bright end leads. FireBurst recolors and
	-- fires the matching streak for the effect and fill mode.
	bar.streak, bar.streakFX, bar.streakShot = CreateStreak(bar, false)
	bar.delayStreak, bar.delayStreakFX, bar.delayStreakShot = CreateStreak(bar, true)
	-- The delay halo, directionless like the haste halo.
	bar.delayGlow, bar.delayGlowFade = CreateCenterGlow(bar, DELAY_GLOW_ALPHA, DELAY_GLOW_TIME)
	bar.delayGlow:SetDesaturated(true)
	bar.delayGlow:SetVertexColor(DELAY_TINT[1], DELAY_TINT[2], DELAY_TINT[3])

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
	local textDim = paused and 0.6 or 1.0
	bar.time:SetVertexColor(textDim, textDim, textDim)
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
			texture:SetVertexColor(FlatColor(bar.hand))
		end
	end
	-- The glow trails to the tick's left (the cast bar's own anchor, +2px) -
	-- no direction flip. UpdateTickPosition hides it when it would extend
	-- outside the bar frame instead. ClearAllPoints first: differently named
	-- anchors coexist in WoW, and conflicting anchors collapse regions.
	bar.queuedGlow:ClearAllPoints()
	bar.queuedGlow:SetPoint("RIGHT", bar.pip, "LEFT", 2, 0)
	-- One tick identity everywhere: the swing bar's own pip, height-scaled;
	-- the queued state adds the fill tint, the yellow tick and the glow, not
	-- a different tick.
	ApplyPipSize(bar)
	local glowW, glowH = GlowSize()
	bar.queuedGlow:SetSize(glowW, glowH)
	if queued then
		-- The tick joins the queued color language.
		bar.pip:SetVertexColor(QUEUED_TINT[1], QUEUED_TINT[2], QUEUED_TINT[3])
		bar.pip:Show()
		bar.glowWanted = true
	else
		bar.pip:SetVertexColor(1, 1, 1)
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
	return FlatColor(bar.hand)
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
			bar.labelShadow:Show()
		else
			bar.bg:SetColorTexture(0, 0, 0, 0.55)
			bar.border:SetColorTexture(0, 0, 0, 0.85)
			bar.labelShadow:Hide()
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

-- Text height tracks the bar height (in-play feedback: the fixed small font
-- read shrunken on tall bars), clamped to sane bounds and capped so large
-- fonts cannot collide across narrow bars.
local function BarFontHeight()
	-- 0.66x keeps the default 18px bar at the original small-font size; the
	-- cap was lowered 18 -> 14 after in-play feedback that 18px read far too
	-- large on tall bars.
	return math.min(math.max(Addon.db.height * 0.66, 9), 14)
end

function Bars:ApplyText()
	local db = Addon.db
	local fontHeight = BarFontHeight()
	for i = 1, #HAND_ORDER do
		local hand = HAND_ORDER[i]
		local bar = self.bars[hand]
		bar.label:SetFont(BASE_FONT, fontHeight, "")
		bar.time:SetFont(BASE_FONT, fontHeight, "")
		bar.delta:SetFont(BASE_FONT, fontHeight, "")
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
				-- swing mid-flight. Library builds without the parry fix
				-- re-anchor only at the next swing, so the hastened swing lands
				-- early; a mid-swing haste proc produces the same signature. With
				-- the fix the UPDATE fires the feedback before the landing and
				-- this path stays quiet.
				self:HasteFeedback(bar)
		else
				-- Different weapon speed: a weapon swap restart; the old swing
				-- was cut short.
				self:InterruptFeedback(bar)
			end
		end
	elseif hand == "ranged" then
		if bar.active then
			-- On WoW: Forever a mid-swing ranged UPDATE is the movement-cancelled
			-- Auto Shot reschedule: the engine re-attempts the shot and the
			-- library predicts the next landing at now + ~0.5 s (measured recasts
			-- 0.43-0.56 s). Detect that signature directly - comparing the new
			-- expiration against the old one misses fails early in the cast
			-- window, where the reschedule lands close to the original time and
			-- the push is below the threshold.
			local recast = expirationTime - GetTime()
			if recast > 0.3 and recast < 0.7 then
				self:DelayFeedback(bar)
			end
		end
	elseif bar.active then
		-- A mid-swing melee UPDATE is the library's parry haste: the library
		-- (ApplyParryHaste) fires UNIT_SWING_TIMER_UPDATE at the player's
		-- defensive parry with the same weapon speed and a shortened expiry, and
		-- on WoW: Forever nothing else produces a melee UPDATE (the attack-speed
		-- rescale is gated off there and the pause spell list is empty). The
		-- green stack fires in real time at the parry; the early-landing
		-- detection above remains the fallback for library builds without the
		-- parry fix, where the hastened swing lands early and the stop-grace
		-- logic classifies it.
		self:HasteFeedback(bar)
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
	-- A stop while the swing is still in flight means the swing was cut
	-- short or landed early; WHICH of the two is only knowable after a short
	-- grace period, because the library fires a restart as STOP+START inside
	-- one call. The epsilon must exceed the frame race between the engine's
	-- PLAYER_SWING anchor and the library's expiration timer (see
	-- EARLY_LANDING_EPSILON) - a bare "anything remaining" check popped the
	-- haste feedback on ordinary swings whenever the engine won the race.
	bar.stoppedInFlight = (bar.active and bar.expiration and bar.expiration > GetTime() + EARLY_LANDING_EPSILON) or nil
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
-- The parry-haste treatment: fill tint, green spark, the forward burst
-- (rightward in fill mode, leftward in drain) and the outer glow. Shared by
-- the early-landing detection and the test command, so the test path
-- exercises exactly the combat code.
function Bars:HasteFeedback(bar)
	self:SetFillTint(bar, HASTE_TINT)
	-- Spark: the tick joins the haste color, restored with the fade
	-- (FadeFillBack's final step re-applies the fill style).
	bar.pip:SetVertexColor(HASTE_TINT[1], HASTE_TINT[2], HASTE_TINT[3])
	-- The burst fires forward: with the fill's direction of travel.
	FireBurst(bar, HASTE_GLOW, ForwardIsLeft())
	if bar.hasteGlow and bar.hasteGlowFade and not bar.hasteGlowFade:IsPlaying() then
		bar.hasteGlow:Show()
		bar.hasteGlowFade:Play()
	end
end

-- The movement-delay treatment, the haste burst mirrored: the amber fill
-- tint, the amber spark and the backward burst (leftward in fill mode,
-- rightward in drain) - time pushed back instead of pulled forward. Shared
-- by the ranged reschedule detection and the test command, so the test path
-- exercises exactly the combat code.
function Bars:DelayFeedback(bar)
	-- One burst per window: a reschedule while the previous burst is still
	-- running must not restart it mid-flight.
	local now = GetTime()
	if now - (bar.delayAt or 0) < DELAY_RETRIGGER_WINDOW then
		return
	end
	bar.delayAt = now
	self:SetFillTint(bar, DELAY_TINT)
	-- Spark: the tick joins the delay color, restored with the fade
	-- (FadeFillBack's final step re-applies the fill style).
	bar.pip:SetVertexColor(DELAY_TINT[1], DELAY_TINT[2], DELAY_TINT[3])
	-- The burst fires backward: against the fill's direction of travel.
	FireBurst(bar, DELAY_TINT, not ForwardIsLeft())
	if bar.delayGlow and bar.delayGlowFade and not bar.delayGlowFade:IsPlaying() then
		bar.delayGlow:Show()
		bar.delayGlowFade:Play()
	end
end
function Bars:InterruptFeedback(bar)
	self:SetFillTint(bar, CLIP_TINT)
	-- The cast bar's interrupted spark: the tick swaps to the red pip atlas,
	-- height-scaled like the normal tick via its own aspect.
	ApplyPipSize(bar, CASTBAR_PIP_RED_ATLAS)
	-- The cast bar's interrupted outer glow: flash to full, fade over 1.0 s.
	if bar.interruptGlow and bar.interruptGlowFade and not bar.interruptGlowFade:IsPlaying() then
		-- Like the burst animations: a clip landing mid-fade lets the halo
		-- finish instead of popping back to full alpha.
		bar.interruptGlow:Show()
		bar.interruptGlowFade:Play()
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

-- Effect test modes, so visual feedback changes can be verified without
-- waiting for combat events: each triggers the real treatment code path on
-- the enabled bars. Used by "/4everswingtimer test <effect>".
local TEST_QUEUED_TIME = 3.0

function Bars:TestEffect(effect)
	if not self.bars then
		return
	end
	local db = Addon.db
	local function ForEnabled(func)
		for i = 1, #HAND_ORDER do
			local hand = HAND_ORDER[i]
			local bar = self.bars[hand]
			if db.enabled[hand] then
				func(bar)
			end
		end
	end
	if effect == "interrupt" then
		ForEnabled(function(bar)
			self:InterruptFeedback(bar)
		end)
	elseif effect == "haste" then
		ForEnabled(function(bar)
			self:HasteFeedback(bar)
		end)
	elseif effect == "delay" then
		ForEnabled(function(bar)
			self:DelayFeedback(bar)
		end)
	elseif effect == "queued" then
		local bar = self.bars.mainhand
		if db.enabled.mainhand and bar then
			bar.queued = true
			self:ApplyFillStyle(bar)
			if self.queuedTestTimer then
				self.queuedTestTimer:Cancel()
			end
			self.queuedTestTimer = C_Timer.NewTimer(TEST_QUEUED_TIME, function()
				bar.queued = false
				self:ApplyFillStyle(bar)
			end)
		end
	elseif effect == "all" then
		self:TestEffect("interrupt")
		C_Timer.After(1.5, function()
			self:TestEffect("haste")
		end)
		C_Timer.After(3.0, function()
			self:TestEffect("delay")
		end)
		C_Timer.After(4.5, function()
			self:TestEffect("queued")
		end)
	else
		Addon:Print("Unknown test effect: " .. tostring(effect))
	end
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
