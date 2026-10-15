-- 4everSwingTimer — placement in Blizzard's Edit Mode, after
-- 4everActionTimeline's pattern (its ADR-0008; probes E3/E6 in game): the
-- bars are NOT registered Edit Mode systems and nothing here writes into
-- Blizzard's layout tables — every code path into the Edit Mode manager
-- taints the raid frames' updates on this client. Instead the addon listens
-- for the EventRegistry's EditMode.Enter / Exit; while Edit Mode is open each
-- hand's bar is its own selectable frame, as the native swing timers are: it
-- wears Blizzard's own selection art (blue while idle, yellow once clicked, a
-- label), drags and snaps to nearby Edit Mode frames, the other bars and the
-- grid when Edit Mode's snap is on, drawing Blizzard's red snap preview lines
-- while it drags. (No arrow-key nudge: capturing the keyboard needs
-- SetPropagateKeyboardInput, protected on this client.) Clicking a bar opens
-- the settings panel for that hand (EditModeDialog.lua). Each position is
-- stored UIParent-relative, one per hand and Edit Mode layout (schema 3; the
-- older single-stack forms are migrated at init). Outside Edit Mode the bars
-- stay click-through.

local Addon = FourEverSwingTimer

local SNAP_DISTANCE = 10
-- Blizzard's snap preview line (MagnetismPreviewLineTemplate): red, 1.5
-- screen pixels.
local PREVIEW_COLOR, PREVIEW_WIDTH = { 1, 0, 0 }, 1.5
-- The bars' default stack: the main hand's top edge, then each further hand
-- one bar height plus this gap lower.
local DEFAULT_TOP, DEFAULT_GAP = 260, 4

-- Blizzard's selection frame (EditModeSystemTemplates.lua), applied with
-- NineSliceUtil to our own frames - never inherited, whose mouse handler
-- selects a system in Edit Mode's own manager.
local KITS = { highlight = "editmode-actionbar-highlight", selected = "editmode-actionbar-selected" }
-- The plain band shown where the client lacks the selection atlases.
local BAND_COLORS = {
	[KITS.highlight] = { 0.82, 0.38, 0.12, 0.25 },
	[KITS.selected] = { 1, 0.82, 0, 0.4 },
}
local SELECTION = {
	TopRightCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = 8 },
	TopLeftCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = 8 },
	BottomLeftCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = -8 },
	BottomRightCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = -8 },
	TopEdge = { atlas = "_%s-NineSlice-EdgeTop" },
	BottomEdge = { atlas = "_%s-NineSlice-EdgeBottom" },
	LeftEdge = { atlas = "!%s-NineSlice-EdgeLeft" },
	RightEdge = { atlas = "!%s-NineSlice-EdgeRight" },
	Center = { atlas = "%s-NineSlice-Center", x = -8, y = 8, x1 = 8, y1 = -8 },
}

local EditMode = {}
Addon.EditMode = EditMode

local HAND_ORDER = Addon.HAND_ORDER

local bars, handles, preview
local selectedHand

-- ---------------------------------------------------------------------------
-- Local Blizzard-API guards (this client removes old globals; a removed
-- global upvalues to nil and only fails at call time - verify before
-- caching, nil-check at use).
-- ---------------------------------------------------------------------------

-- Forever hands out secret values where plain ones are expected; never do
-- math on one (4everActionTimeline's Util.IsSecret, same client).
local function IsSecret(value)
	if issecretvalue == nil or value == nil then
		return false
	end
	return issecretvalue(value) and true or false
end

local function Plain(value)
	return type(value) == "number" and not IsSecret(value)
end

local function AtlasExists(name)
	if not (C_Texture and C_Texture.GetAtlasInfo) then
		return false
	end
	return C_Texture.GetAtlasInfo(name) ~= nil
end

-- A thin line's thickness rounded to whole screen pixels, at least one
-- (Blizzard's PixelUtil, nil-guarded).
local function PixelSize(region, units)
	if PixelUtil and PixelUtil.GetNearestPixelSize and GetPhysicalScreenSize then
		return PixelUtil.GetNearestPixelSize(units, region:GetEffectiveScale(), 1)
	end
	return units
end

-- ---------------------------------------------------------------------------
-- The positions: one per hand and Edit Mode layout
-- ---------------------------------------------------------------------------

-- The active Edit Mode layout's key, or "default" without one.
local function LayoutKey()
	local manager = EditModeManagerFrame
	local info = manager and manager.GetActiveLayoutInfo and manager:GetActiveLayoutInfo()
	if not info then
		return "default"
	end
	local name = info.layoutName
	if name == nil or name == "" then
		name = manager.layoutInfo and manager.layoutInfo.activeLayout or "?"
	end
	return (info.layoutType or 0) .. ":" .. name
end

local function Positions()
	local db = Addon.db
	db.positions = db.positions or {}
	return db.positions
end

-- Positions are kept in UIParent units, so a bar's own scale never moves it:
-- an anchor offset is in the frame's scale, a stored position is not. A
-- position is the bar's top-center point.
local function ScaleToParent(bar)
	return bar:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

local function Place(bar, position)
	local scale = ScaleToParent(bar)
	bar:ClearAllPoints()
	bar:SetPoint("TOP", UIParent, "BOTTOMLEFT", position.x / scale, position.y / scale)
end

-- The default stack: just above the screen's bottom edge, where the bars
-- always started, each hand under the one before.
local function DefaultPosition(hand)
	local y = DEFAULT_TOP
	for i = 1, #HAND_ORDER do
		local other = HAND_ORDER[i]
		if other == hand then
			break
		end
		local cfg = Addon.db.hands[other]
		y = y - (cfg.height + DEFAULT_GAP) * cfg.scale
	end
	return { x = (UIParent:GetWidth() or 0) / 2, y = y }
end

-- Schema 2 stored one top-center position per layout for the whole stack;
-- each hand takes its place in it (visible hands first, as the stack was laid
-- out, hidden ones below). db.gap was the stack's spacing.
local function SplitStack(entry)
	local db = Addon.db
	local gap = db.gap or DEFAULT_GAP
	local split, y = {}, entry.y
	for pass = 1, 2 do
		for i = 1, #HAND_ORDER do
			local hand = HAND_ORDER[i]
			local cfg = db.hands[hand]
			if (cfg.visibility == "hidden") == (pass == 2) then
				split[hand] = { x = entry.x, y = y }
				y = y - (cfg.height + gap) * cfg.scale
			end
		end
	end
	return split
end

-- One-time move of the older forms: schema 1's single point/relativeTo/
-- relativePoint/x/y anchor (saved by dragging while unlocked) becomes
-- positions.default, then schema 2's per-layout stack positions are split per
-- hand. Runs before the first Restore; the legacy fields are wiped so it
-- never runs twice.
local function Migrate()
	local db = Addon.db
	if db.schemaVersion == Addon.SCHEMA_VERSION then
		return
	end
	local positions = db.positions
	if not positions then
		positions = {}
		db.positions = positions
		if db.point ~= nil or db.x ~= nil then
			-- The old anchor was one frame as wide as a bar and as tall as the
			-- stack: rebuild it to read the top edge where the bars sat.
			local count = 0
			for _, hand in ipairs(HAND_ORDER) do
				if db.hands[hand].visibility ~= "hidden" then
					count = count + 1
				end
			end
			count = math.max(count, 1)
			local cfg = db.hands.mainhand
			local legacy = CreateFrame("Frame", nil, UIParent)
			legacy:SetScale(cfg.scale)
			legacy:SetSize(cfg.width, count * cfg.height + (count - 1) * (db.gap or DEFAULT_GAP))
			local relativeTo = db.relativeTo and _G[db.relativeTo] or UIParent
			legacy:SetPoint(db.point or "BOTTOM", relativeTo, db.relativePoint or "BOTTOM", db.x or 0, db.y or 0)
			local x, top = legacy:GetCenter(), legacy:GetTop()
			if x and top then
				local scale = ScaleToParent(legacy)
				positions.default = { x = x * scale, y = top * scale }
			end
			legacy:Hide()
		end
		db.point, db.relativeTo, db.relativePoint, db.x, db.y, db.locked = nil, nil, nil, nil, nil, nil
	end
	for key, entry in pairs(positions) do
		if entry.x ~= nil then
			positions[key] = SplitStack(entry)
		end
	end
	db.gap = nil
	db.schemaVersion = Addon.SCHEMA_VERSION
end

-- The stored position of a hand in the active layout, else the migrated
-- default entry, else the built-in default.
local function PositionOf(hand)
	local positions = Positions()
	local set = positions[LayoutKey()]
	local default = positions.default
	return (set and set[hand]) or (default and default[hand]) or DefaultPosition(hand)
end

-- A deleted Edit Mode layout would leave its positions behind for good. When
-- the manager's list of the player's own layouts is readable and holds the
-- active one (a sanity check on its shape), entries of user layouts (types 1
-- and 2) that are no longer in it are dropped; presets, "default" and
-- anything unreadable are left alone. Read-only on Blizzard's side.
local function PruneLayouts()
	local manager = EditModeManagerFrame
	local layouts = manager and manager.layoutInfo and manager.layoutInfo.layouts
	if type(layouts) ~= "table" then
		return
	end
	local present = {}
	for _, layout in ipairs(layouts) do
		if type(layout) == "table" and layout.layoutType and layout.layoutName then
			present[layout.layoutType .. ":" .. layout.layoutName] = true
		end
	end
	local active = LayoutKey()
	if not active:find("^[12]:") or not present[active] then
		return
	end
	local positions = Positions()
	for key in pairs(positions) do
		if key:find("^[12]:") and not present[key] then
			positions[key] = nil
		end
	end
end

function EditMode:Restore(hand)
	if not bars then
		return
	end
	if hand then
		Place(bars[hand], PositionOf(hand))
		return
	end
	for i = 1, #HAND_ORDER do
		self:Restore(HAND_ORDER[i])
	end
end

-- A frame's edges in UIParent units, or nil when unreadable. `anyhow` reads
-- a hidden frame's geometry too (a bar can be placed while hidden); the
-- visible path also drops secret values, which Forever hands out where plain
-- ones are expected.
local function Rect(frame, anyhow)
	-- Declared at function scope: both branches write them, the shared tail
	-- below reads them (branch-local declarations would leave the tail
	-- reading globals - nil - and erroring on the arithmetic).
	local left, bottom, width, height
	if anyhow then
		local ok = pcall(function()
			left, bottom = frame:GetLeft(), frame:GetBottom()
			width, height = frame:GetWidth(), frame:GetHeight()
		end)
		if not ok then
			return nil
		end
	else
		local ok, visible = pcall(frame.IsVisible, frame)
		if not ok or IsSecret(visible) or not visible then
			return nil
		end
		local okL, l, b, w, h = pcall(frame.GetRect, frame)
		if not okL then
			return nil
		end
		left, bottom, width, height = l, b, w, h
	end
	if not (Plain(left) and Plain(bottom) and Plain(width) and Plain(height)) then
		return nil
	end
	local scale = ScaleToParent(frame)
	return left * scale, bottom * scale, (left + width) * scale, (bottom + height) * scale
end

-- The smallest shift (within SNAP_DISTANCE) lining one of ours up with one of
-- theirs (edges and centers), and the line it lines up on.
local function Nearest(shift, at, ours, theirs)
	for _, a in ipairs(ours) do
		for _, b in ipairs(theirs) do
			local delta = b - a
			if math.abs(delta) <= SNAP_DISTANCE and (not shift or math.abs(delta) < math.abs(shift)) then
				shift, at = delta, b
			end
		end
	end
	return shift, at
end

-- The same, putting one of ours on a line of a grid `spacing` apart through
-- `center`.
local function NearestLine(shift, at, ours, center, spacing)
	local lines = {}
	for i, a in ipairs(ours) do
		lines[i] = center + math.floor((a - center) / spacing + 0.5) * spacing
	end
	return Nearest(shift, at, ours, lines)
end

-- With Edit Mode's snap on: the shift (UIParent units, either may be nil)
-- aligning `bar` to nearby Edit Mode frames, the other bars and, while it
-- shows, to Edit Mode's grid (lines `gridSpacing` apart through its center,
-- as EditModeGridMixin:UpdateGrid draws them), then the x and y of the lines
-- it lines up on. Only reads Blizzard's frames.
local function Snap(bar)
	local manager = EditModeManagerFrame
	if not (manager and manager.IsSnapEnabled and manager:IsSnapEnabled()) then
		return
	end
	local left, bottom, right, top = Rect(bar, true)
	if not left then
		return
	end
	local dx, dy, atX, atY
	local xs, ys = { left, right, (left + right) / 2 }, { bottom, top, (bottom + top) / 2 }
	local others = {}
	for _, other in ipairs(manager.registeredSystemFrames or {}) do
		others[#others + 1] = other
	end
	for i = 1, #HAND_ORDER do
		local other = bars[HAND_ORDER[i]]
		if other ~= bar then
			others[#others + 1] = other
		end
	end
	for _, other in ipairs(others) do
		local oLeft, oBottom, oRight, oTop = Rect(other)
		if oLeft then
			dx, atX = Nearest(dx, atX, xs, { oLeft, oRight, (oLeft + oRight) / 2 })
			dy, atY = Nearest(dy, atY, ys, { oBottom, oTop, (oBottom + oTop) / 2 })
		end
	end
	local grid = manager.Grid
	local spacing = grid and grid.gridSpacing
	local gLeft, gBottom, gRight, gTop
	if Plain(spacing) and spacing > 0 then
		gLeft, gBottom, gRight, gTop = Rect(grid)
	end
	if gLeft then
		spacing = spacing * ScaleToParent(grid)
		dx, atX = NearestLine(dx, atX, xs, (gLeft + gRight) / 2, spacing)
		dy, atY = NearestLine(dy, atY, ys, (gBottom + gTop) / 2, spacing)
	end
	return dx, dy, atX, atY
end

-- ---------------------------------------------------------------------------
-- The snap preview: Blizzard's red lines, drawn by us
-- ---------------------------------------------------------------------------

-- While a bar drags, a line across the screen where each axis would snap,
-- as Edit Mode draws for its own frames (MagnetismPreviewLineMixin). Our own
-- lines: asking Edit Mode's manager to draw them would taint.
local function NewPreviewLine()
	local line = preview:CreateLine(nil, "OVERLAY")
	line:SetColorTexture(PREVIEW_COLOR[1], PREVIEW_COLOR[2], PREVIEW_COLOR[3], 1)
	line:Hide()
	return line
end

local function ShowPreviewLine(line, at, vertical)
	if not at then
		line:Hide()
		return
	end
	line:SetThickness(PixelSize(preview, PREVIEW_WIDTH))
	if vertical then
		line:SetStartPoint("BOTTOMLEFT", UIParent, at, 0)
		line:SetEndPoint("TOPLEFT", UIParent, at, 0)
	else
		line:SetStartPoint("BOTTOMLEFT", UIParent, 0, at)
		line:SetEndPoint("BOTTOMRIGHT", UIParent, 0, at)
	end
	line:Show()
end

local function StartPreview(bar)
	if not preview then
		preview = CreateFrame("Frame", nil, UIParent)
		preview:SetAllPoints(UIParent)
		preview:SetFrameStrata("HIGH")
		if not preview.CreateLine then
			return
		end
		preview.vertical, preview.horizontal = NewPreviewLine(), NewPreviewLine()
	end
	if preview.vertical then
		preview:SetScript("OnUpdate", function()
			local _, _, atX, atY = Snap(bar)
			ShowPreviewLine(preview.vertical, atX, true)
			ShowPreviewLine(preview.horizontal, atY, false)
		end)
		preview:Show()
	end
end

local function StopPreview()
	if preview then
		preview:SetScript("OnUpdate", nil)
		preview:Hide()
	end
end

-- The active layout's per-hand positions, created on first write with every
-- hand seeded at the place it currently has (so editing one hand never moves
-- the others).
local function LayoutSet()
	local positions = Positions()
	local key = LayoutKey()
	local set = positions[key]
	if not set then
		set = {}
		for i = 1, #HAND_ORDER do
			set[HAND_ORDER[i]] = PositionOf(HAND_ORDER[i])
		end
		positions[key] = set
	end
	return set
end

-- Stores the top-center point of a hand's bar (shifted by dx, dy UIParent
-- units) at the active layout and re-anchors to UIParent whatever StartMoving
-- left. The layout's other hands keep their (possibly default) places.
local function Store(hand, dx, dy)
	local bar = bars[hand]
	local x, top = bar:GetCenter(), bar:GetTop()
	if not (x and top) then
		return
	end
	local set = LayoutSet()
	local scale = ScaleToParent(bar)
	set[hand] = { x = x * scale + (dx or 0), y = top * scale + (dy or 0) }
	EditMode:Restore(hand)
end

-- Back to the default spot: this layout gets the built-in default for the
-- hand (all of them without an argument), not the "default" entry (which may
-- hold a migrated old position).
function EditMode:ResetPosition(hand)
	local set = LayoutSet()
	for i = 1, #HAND_ORDER do
		local each = HAND_ORDER[i]
		if hand == nil or hand == each then
			set[each] = DefaultPosition(each)
		end
	end
	self:Restore(hand)
end

-- ---------------------------------------------------------------------------
-- The selection
-- ---------------------------------------------------------------------------

-- Blizzard's art when the client has it, else a plain band.
local function ShowKit(handle, kit)
	if handle.kit == kit then
		return
	end
	handle.kit = kit
	local ready = NineSliceUtil and NineSliceUtil.ApplyLayout and AtlasExists(kit .. "-NineSlice-Corner")
	if ready then
		NineSliceUtil.ApplyLayout(handle, SELECTION, kit)
		handle.band:Hide()
	else
		local c = BAND_COLORS[kit]
		handle.band:SetColorTexture(c[1], c[2], c[3], c[4])
		handle.band:Show()
	end
end

local function UpdateLabel(handle)
	handle.label:SetShown(selectedHand == handle.hand or handle.hover)
end

-- Selects a hand's bar (nil: none): its handle turns yellow and its panel
-- opens; the previous one goes back to blue.
local function Select(hand)
	if selectedHand == hand then
		return
	end
	local previous = selectedHand and handles[selectedHand]
	selectedHand = hand
	if previous then
		previous:SetFrameLevel(1)
		ShowKit(previous, KITS.highlight)
		UpdateLabel(previous)
	end
	if hand then
		local handle = handles[hand]
		handle:SetFrameLevel(10)
		ShowKit(handle, KITS.selected)
		UpdateLabel(handle)
		Addon.EditModeDialog:Show(hand, handle)
	else
		Addon.EditModeDialog:Hide()
	end
end

-- Our panel closes: its close button, or Edit Mode itself exiting. Nothing
-- of Blizzard's is touched from here (calling its Edit Mode manager from our
-- handlers taints the raid frames' updates - 4everActionTimeline's M10
-- probes E3 and E6, in game on this same client).
function EditMode:Deselect()
	Select(nil)
end

-- While a test preview plays, the selection art fades so the bar's animation
-- is not buried under the blue/yellow overlay; Bars.lua flips it with its
-- testing state.
function EditMode:SetPreviewing(on)
	if not handles then
		return
	end
	for i = 1, #HAND_ORDER do
		handles[HAND_ORDER[i]]:SetAlpha(on and 0.15 or 1)
	end
end

local function SetActive(active)
	Addon.editMode = active
	if not active then
		Select(nil)
		StopPreview()
	end
	for i = 1, #HAND_ORDER do
		handles[HAND_ORDER[i]]:SetShown(active)
	end
	-- Every bar shows while Edit Mode is open, even with nothing swinging
	-- (dragging needs live geometry), and the range look is suppressed (as
	-- Blizzard's own bars do).
	Addon.Bars:UpdateVisibility()
	Addon.Bars:UpdateRangeFeedback()
end

local function BuildHandle(hand)
	local bar = bars[hand]
	local handle = CreateFrame("Frame", nil, UIParent)
	handle.hand = hand
	handle:SetAllPoints(bar)
	handle:SetFrameStrata("HIGH")
	handle:SetFrameLevel(1)
	handle:EnableMouse(true)
	handle:RegisterForDrag("LeftButton")
	handle.band = handle:CreateTexture(nil, "BACKGROUND")
	handle.band:SetAllPoints()
	handle.band:Hide()
	handle.label = handle:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	handle.label:SetPoint("CENTER")
	handle.label:SetText(Addon.HAND_LABEL[hand])
	handle.label:Hide()
	handle:SetScript("OnMouseDown", function()
		Select(hand)
	end)
	handle:SetScript("OnEnter", function(self)
		self.hover = true
		UpdateLabel(self)
	end)
	handle:SetScript("OnLeave", function(self)
		self.hover = false
		UpdateLabel(self)
	end)
	handle:SetScript("OnDragStart", function()
		Select(hand)
		bar:StartMoving()
		StartPreview(bar)
	end)
	handle:SetScript("OnDragStop", function()
		bar:StopMovingOrSizing()
		StopPreview()
		-- On drop: snap, then store.
		Store(hand, Snap(bar))
	end)
	ShowKit(handle, KITS.highlight)
	handle:Hide()
	return handle
end

function EditMode:Init(frames)
	if bars then
		return
	end
	bars = frames
	Migrate()
	handles = {}
	for i = 1, #HAND_ORDER do
		local hand = HAND_ORDER[i]
		local bar = bars[hand]
		bar:SetMovable(true)
		bar:SetClampedToScreen(true)
		handles[hand] = BuildHandle(hand)
		-- A new scale re-anchors the stored position (the anchor offset is in
		-- the frame's scale), so scaling never moves the bar.
		if hooksecurefunc then
			local scale
			hooksecurefunc(bar, "SetScale", function(_, new)
				if new ~= scale then
					scale = new
					EditMode:Restore(hand)
				end
			end)
		end
	end
	self:Restore()
	if EventRegistry and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("EditMode.Enter", function()
			EditMode:Restore()
			SetActive(true)
		end, EditMode)
		EventRegistry:RegisterCallback("EditMode.Exit", function()
			SetActive(false)
		end, EditMode)
	end
	-- A switch of the active Edit Mode layout moves the bars to that
	-- layout's own positions.
	if EventRegistry and EventRegistry.RegisterFrameEventAndCallback then
		EventRegistry:RegisterFrameEventAndCallback("EDIT_MODE_LAYOUTS_UPDATED", function()
			PruneLayouts()
			EditMode:Restore()
		end, EditMode)
	end
	-- Blizzard selecting a system (or clearing its selection) deselects
	-- ours.
	local manager = EditModeManagerFrame
	if manager and hooksecurefunc then
		for _, method in ipairs({ "SelectSystem", "ClearSelectedSystem" }) do
			if manager[method] then
				hooksecurefunc(manager, method, function()
					Select(nil)
				end)
			end
		end
	end
	if manager and manager.IsEditModeActive and manager:IsEditModeActive() then
		SetActive(true)
	end
end
