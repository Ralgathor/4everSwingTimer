-- 4everSwingTimer — player swing timer bars for WoW: Forever.
-- Core: bootstrap, saved variables, library gate, event dispatch, slash commands.
-- Bar rendering lives in Bars.lua; settings registration lives in Options.lua.
--
-- The addon holds no swing math of its own: all state comes from
-- LibClassicSwingTimerAPI events; nothing here reads UnitAttackSpeed or
-- UnitRangedDamage directly.

local ADDON_NAME = "4everSwingTimer"
local LIB_MAJOR = "LibClassicSwingTimerAPI"
-- The Forever swing path shipped with the library's 2.2.0 beta line; the
-- embedded pin is the v2.3.0 stable release (LibStub MINOR 39: the event
-- reason argument, the single-frame dispatch with the shared frame, and
-- the Forever fixes - no target swings, Multi-Shot/Aimed no-reset, Rapid
-- Fire rescale, and the swing-timer cancellation at world enter/target
-- change). The library verified the reason argument, the dispatch and
-- the duplicate-dispatch two-copy test in game on this release.
local REQUIRED_LIB_MINOR = 39

FourEverSwingTimer = {}
local Addon = FourEverSwingTimer
Addon.name = ADDON_NAME

local GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
Addon.version = GetAddOnMetadata and GetAddOnMetadata(ADDON_NAME, "Version") or UNKNOWN or "?"

-- ---------------------------------------------------------------------------
-- Saved variables
-- ---------------------------------------------------------------------------

-- Schema 3: the frame's settings and position are per hand. Positions are
-- db.positions[<Edit Mode layout>][hand] (UIParent top-center units, stored
-- by EditMode.lua); settings are db.hands[hand] (see DEFAULTS). Schema 2 had
-- one position per layout for the whole stack, schema 1 a single
-- point/relativeTo/relativePoint/x/y anchor; both are migrated at load.
local SCHEMA_VERSION = 3

-- One hand's settings: all of the frame's own look, size and visibility.
local function HandDefaults(hand)
	local defaults = {
		visibility = "combat", -- "always" | "combat" | "swinging" | "hidden"
		scale = 1.0,
		opacity = 1.0,
		width = 260,
		height = 18,
		rangeFeedback = true,  -- too far / too close tint on this hand's bar
	}
	-- The queued next-melee highlight is the main hand's alone.
	if hand == "mainhand" then
		defaults.highlightQueued = true
	end
	return defaults
end

local DEFAULTS = {
	hands = {
		mainhand = HandDefaults("mainhand"),
		offhand = HandDefaults("offhand"),
		ranged = HandDefaults("ranged"),
	},
	skin = "native",         -- "native" | "flat": one look for all bars (Settings)
	flatPalette = "silver",  -- key into Bars.FLAT_PALETTES (flat style)
	fill = "drain",          -- "drain" | "fill"
	showTime = true,
	showSpeed = false,
	showLabel = true,
	showDelta = false,
	notifiedNativeTimer = false,
}

function Addon.ApplyDefaults(db, defaults)
	for key, value in pairs(defaults) do
		if type(value) == "table" then
			if type(db[key]) ~= "table" then
				db[key] = {}
			end
			Addon.ApplyDefaults(db[key], value)
		elseif db[key] == nil then
			db[key] = value
		end
	end
end

Addon.DEFAULTS = DEFAULTS
Addon.SCHEMA_VERSION = SCHEMA_VERSION

-- Saved values are trusted by the dropdowns and sliders, so anything out of
-- range (a hand-edited file, a removed option) is put back before use: a
-- string outside its list, a number outside its slider, a non-boolean flag.
local CHOICES = {
	visibility = { always = true, combat = true, swinging = true, hidden = true },
	skin = { native = true, flat = true },
	fill = { drain = true, fill = true },
}
local RANGES = {
	scale = { 0.5, 2.0 }, opacity = { 0.1, 1.0 },
	width = { 120, 400 }, height = { 14, 40 },
}

local function Sanitize(value, key, default)
	if CHOICES[key] then
		if CHOICES[key][value] then
			return value
		end
		return default
	elseif RANGES[key] then
		if type(value) ~= "number" then
			return default
		end
		return math.min(math.max(value, RANGES[key][1]), RANGES[key][2])
	elseif type(default) == "boolean" then
		if type(value) == "boolean" then
			return value
		end
		return default
	end
	return value
end

function Addon.SanitizeDB(db)
	for key, default in pairs(DEFAULTS) do
		if type(default) ~= "table" then
			db[key] = Sanitize(db[key], key, default)
		end
	end
	for hand, defaults in pairs(DEFAULTS.hands) do
		local cfg = db.hands[hand]
		for key, default in pairs(defaults) do
			cfg[key] = Sanitize(cfg[key], key, default)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Event dispatch
-- ---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
Addon.frame = frame

-- Refresh bar visibility after any state change that can affect it; a no-op
-- before the bars exist (library missing or not yet enabled).
local function RefreshBars()
	if Addon.Bars then
		Addon.Bars:UpdateVisibility()
	end
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("UNIT_INVENTORY_CHANGED")

frame:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == ADDON_NAME then
			ForeverSwingTimerDB = ForeverSwingTimerDB or {}
			-- Schema 3: every setting of the frame itself is per hand, like the
			-- native bars (db.hands[hand]). Older DBs carried them once, at the top
			-- level, with a global visibility mode and per-hand on/off toggles; a
			-- disabled hand becomes "hidden". (gap stays for EditMode.lua's position
			-- migration, which reads and clears it.)
			local saved = ForeverSwingTimerDB
			if saved.hands == nil then
				saved.hands = {}
				for _, hand in ipairs(Addon.HAND_ORDER) do
					local visibility = saved.handVisibility and saved.handVisibility[hand]
					if visibility == nil then
						visibility = (saved.enabled and saved.enabled[hand] == false) and "hidden" or saved.visibility
					end
					saved.hands[hand] = {
						visibility = visibility, scale = saved.scale, opacity = saved.opacity,
						width = saved.width, height = saved.height,
					}
				end
			end
			saved.handVisibility, saved.visibility, saved.enabled = nil, nil, nil
			saved.scale, saved.opacity, saved.width, saved.height = nil, nil, nil, nil
			-- Bar style, flat colors and direction are global again (Settings): a
			-- build that had them per hand hands its main hand's choice over.
			local first = saved.hands.mainhand or {}
			for _, key in ipairs({ "skin", "flatPalette", "fill" }) do
				if saved[key] == nil then
					saved[key] = first[key]
				end
				for _, hand in ipairs(Addon.HAND_ORDER) do
					if saved.hands[hand] then
						saved.hands[hand][key] = nil
					end
				end
			end
			-- Feedback is per hand now (Edit Mode panel): the old global queued
			-- highlight goes to the main hand, the old range feedback to every hand.
			if saved.highlightQueued ~= nil then
				saved.hands.mainhand.highlightQueued = saved.highlightQueued
			end
			if saved.rangeFeedback ~= nil then
				for _, hand in ipairs(Addon.HAND_ORDER) do
					saved.hands[hand].rangeFeedback = saved.rangeFeedback
				end
			end
			saved.highlightQueued, saved.rangeFeedback = nil, nil
			Addon.ApplyDefaults(ForeverSwingTimerDB, DEFAULTS)
			Addon.SanitizeDB(saved)
			-- Migrate palette keys saved by earlier builds (preset/custom pickers)
			-- to the curated palette set.
			if not (Addon.FLAT_PALETTES and Addon.FLAT_PALETTES[saved.flatPalette]) then
				saved.flatPalette = Addon.FLAT_PALETTE_DEFAULT
			end
			Addon.db = ForeverSwingTimerDB
			-- The trace's recording flag persists in SavedVariables; reset it
			-- on load so a stale true cannot desync the first toggle of a
			-- session (the command always means "start recording" when fresh).
			if FourEverSwingTimerTrace then
				FourEverSwingTimerTrace.recording = false
			end
			Addon.Options:Init()
		end
	elseif event == "PLAYER_LOGIN" then
		Addon:OnEnable()
	elseif event == "PLAYER_REGEN_DISABLED" then
		Addon.inCombat = true
		RefreshBars()
	elseif event == "PLAYER_REGEN_ENABLED" then
		Addon.inCombat = false
		RefreshBars()
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- The initial visibility pass runs at PLAYER_LOGIN, when the client has
		-- often not populated the player's inventory yet - every HasWeapon read
		-- returns nil and the Always visibility mode hides all bars until some
		-- other event fires. Entering the world (login, teleport, hearthstone)
		-- triggers a refresh - and on a FIRST login the equipment data is
		-- still streaming even here, so retry shortly and let
		-- UNIT_INVENTORY_CHANGED below catch the moment it arrives.
		RefreshBars()
		C_Timer.After(1.0, RefreshBars)
	elseif event == "UNIT_INVENTORY_CHANGED" then
		-- The signal that the client has populated or changed the player's
		-- equipment; at first login this is when weapon data actually exists.
		if arg1 == "player" then
			RefreshBars()
		end
	elseif event == "PLAYER_EQUIPMENT_CHANGED" then
		-- Equipping a shield in the off hand (or swapping weapons) changes
		-- whether a hand can swing; refresh bar visibility immediately.
		RefreshBars()
	end
end)

function Addon:OnEnable()
	self.inCombat = UnitAffectingCombat("player")
	local lib, minor = LibStub:GetLibrary(LIB_MAJOR, true)
	if not lib then
		self:Print("LibClassicSwingTimerAPI is missing. Bars are disabled; the library ships embedded, so a reinstall should fix this.")
		return
	elseif minor < REQUIRED_LIB_MINOR then
		self:Print("LibClassicSwingTimerAPI is too old (needs the 2.3.0 build). Bars are disabled until the library updates.")
		return
	end
	self.lib = lib
	self.libMinor = minor
	self:CheckNativeTimer()
	self.Bars:Enable(lib)
end

-- Every setting back to its default (positions are EditMode.lua's; the
-- one-time native-timer notice stays acknowledged).
function Addon:ResetSettings()
	local db = Addon.db
	local notified = db.notifiedNativeTimer
	for key in pairs(DEFAULTS) do
		db[key] = nil
	end
	Addon.ApplyDefaults(db, DEFAULTS)
	db.notifiedNativeTimer = notified
	if Addon.Bars and Addon.Bars.bars then
		Addon.Bars:ApplyAll()
		Addon.Bars:UpdateRangeFeedback()
	end
	if Addon.EditModeDialog then
		Addon.EditModeDialog:Refresh()
	end
end

function Addon:Print(message)
	print("|cff33ccff" .. ADDON_NAME .. "|r: " .. message)
end

-- The game's own swing timer bars coexist with ours and would double up.
-- Point it out once; never change the CVar silently.
function Addon:CheckNativeTimer()
	local db = self.db
	if not db.notifiedNativeTimer and GetCVarBool("showSwingTimer") then
		self:Print("The game's built-in swing timer bars are enabled. To show only these bars instead, run: |cffdddddd/console showSwingTimer 0|r")
		db.notifiedNativeTimer = true
	end
end

-- ---------------------------------------------------------------------------
-- Slash commands: /4everswingtimer (alias /everswing)
-- ---------------------------------------------------------------------------

-- Verbatim event trace (/4everswingtimer trace). The beta client has no
-- /chatlog and screenshot transcription has documented digit noise; this
-- records raw engine events (PLAYER_SWING, UNIT_COMBAT, the player's
-- spellcasts) and the library's applied timer updates into the SavedVariables
-- table FourEverSwingTimerTrace, written by the client at logout or /reload
-- (read the file in WTF\Account\...\SavedVariables straight from disk after
-- the session). One line per event in dispatch order: "EVENT GetTime ...".
-- Same-frame events share a GetTime stamp, and their file order is the
-- engine's dispatch order.
local function TraceRecord(prefix, ...)
	local t = FourEverSwingTimerTrace
	if not t or not t.recording then
		return
	end
	local n = (t.n or 0) + 1
	t.n = n
	local parts = { prefix, string.format("%.3f", GetTime()) }
	for i = 1, select("#", ...) do
		parts[#parts + 1] = tostring((select(i, ...)))
	end
	t[n] = table.concat(parts, " ")
end

function Addon:ToggleTrace()
	FourEverSwingTimerTrace = FourEverSwingTimerTrace or {}
	local trace = FourEverSwingTimerTrace
	trace.recording = not trace.recording
	if trace.recording and not self.traceFrame then
		self.traceFrame = CreateFrame("Frame")
		self.traceFrame:RegisterEvent("PLAYER_SWING")
		self.traceFrame:RegisterEvent("UNIT_COMBAT")
		-- Player spellcasts: the engine holds a swing during a cast and resets
		-- it at completion, so cast activity contextualizes every cycle anomaly.
		self.traceFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
		self.traceFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
		self.traceFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED_QUIET", "player")
		self.traceFrame:SetScript("OnEvent", function(_, event, ...)
			TraceRecord(event, ...)
		end)
		if self.lib then
			trace.weaponSpeed = self.lib:SwingTimerInfo("mainhand")
			-- All seven library callbacks, not just UPDATE: a full session's
			-- library behavior is needed for model-vs-engine comparison -
			-- e.g. a START or seeded info at login whose landing never
			-- produces a STOP (the stale-swing upstream report).
			for i = 1, #Addon.LIB_EVENTS do
				self.lib.RegisterCallback(self.traceFrame, Addon.LIB_EVENTS[i], function(event, ...)
					TraceRecord("LIB_" .. event, ...)
				end)
			end
		end
	end
	if trace.recording then
		trace.build, trace.buildNumber = GetBuildInfo()
		-- Session marker: GetTime resets each session, so anchor the trace to
		-- wall-clock time; sessions in the file can be told apart.
		TraceRecord("SESSION", trace.build, trace.buildNumber, date("%Y-%m-%d %H:%M:%S"))
	end
	self:Print(trace.recording
		and "Trace ON - recorded to SavedVariables (persists at logout or /reload)."
		or "Trace OFF.")
end

-- ---------------------------------------------------------------------------
-- Range probe (/4everswingtimer proberange)
-- ---------------------------------------------------------------------------

-- Polls every candidate range signal against the current target once per
-- second while on, printing one sample line per tick, so walking in and out
-- of melee/ranged shows exactly which signals flip on this build:
-- - the native C_SwingTimer subsystem: IsTargetWithinSwingRange for the
--   main-hand and ranged hands, plus PLAYER_SWING_RANGE_UPDATE fires
--   (EnableRangeCheck is armed for both hands at probe start; on the broken
--   builds - 70009/70205, RANGE_API_BUG_REPORT.md in the library repo - it
--   produced only the single initial push and the query read nil forever
--   after);
-- - the fallback signals the ref addons read on this client:
--   C_Spell.IsSpellInRange on a melee-band ability and on Auto Shot,
--   C_Item.IsItemInRange on vanilla range-band items, and
--   CheckInteractDistance's duel distance.
-- Missing APIs sample as "gone"/"none", so the probe is also a census of
-- what exists. Every signal CHANGE records a RANGEPROBE line into the
-- trace table (no recording gate - the probe owns its evidence), and each
-- PLAYER_SWING_RANGE_UPDATE fire prints and records with its payload.
local RANGE_PROBE_ITEMS = { 17626, 4559, 10645, 7734 } -- 10/15/20/30 yd bands
local RANGE_PROBE_ITEM_YD = { 10, 15, 20, 30 }
local RANGE_PROBE_TICK = 1.0

local function ProbeValue(value)
	if value == nil then
		return "nil"
	elseif value then
		return "1"
	end
	return "0"
end

-- TraceRecord without the recording gate: the probe writes its own lines
-- (changes and events only) whenever it runs.
local function ProbeRecord(...)
	local t = FourEverSwingTimerTrace
	if not t then
		return
	end
	local n = (t.n or 0) + 1
	t.n = n
	local parts = { "RANGEPROBE", string.format("%.3f", GetTime()) }
	for i = 1, select("#", ...) do
		parts[#parts + 1] = tostring((select(i, ...)))
	end
	t[n] = table.concat(parts, " ")
end

function Addon:RangeProbeSample()
	local parts = {}
	if not UnitExists("target") then
		parts[#parts + 1] = "tgt:none"
	else
		-- The API may be absent on some clients: "?" keeps the probe a
		-- census instead of erroring.
		local status = "?"
		if UnitIsDeadOrGhost then
			status = UnitIsDeadOrGhost("target") and "dead" or "alive"
		end
		parts[#parts + 1] = "tgt:" .. status
		if C_SwingTimer and C_SwingTimer.IsTargetWithinSwingRange then
			parts[#parts + 1] = "MH:" .. ProbeValue(C_SwingTimer.IsTargetWithinSwingRange(0))
			parts[#parts + 1] = "RGD:" .. ProbeValue(C_SwingTimer.IsTargetWithinSwingRange(2))
		else
			parts[#parts + 1] = "native:gone"
		end
		if C_Spell and C_Spell.IsSpellInRange then
			if self.rangeProbeSpell then
				local ok, value = pcall(C_Spell.IsSpellInRange, self.rangeProbeSpell, "target")
				parts[#parts + 1] = "melee(" .. self.rangeProbeSpell .. "):" .. ProbeValue(ok and value or nil)
			else
				parts[#parts + 1] = "melee:none"
			end
			local ok, value = pcall(C_Spell.IsSpellInRange, "Auto Shot", "target")
			parts[#parts + 1] = "autoshot:" .. ProbeValue(ok and value or nil)
		else
			parts[#parts + 1] = "spells:gone"
		end
		if C_Item and C_Item.IsItemInRange then
			for i = 1, #RANGE_PROBE_ITEMS do
				local ok, value = pcall(C_Item.IsItemInRange, RANGE_PROBE_ITEMS[i], "target")
				parts[#parts + 1] = "i" .. RANGE_PROBE_ITEM_YD[i] .. ":" .. ProbeValue(ok and value or nil)
			end
		else
			parts[#parts + 1] = "items:gone"
		end
		if CheckInteractDistance then
			parts[#parts + 1] = "duel:" .. ProbeValue(CheckInteractDistance("target", 2))
		end
	end
	parts[#parts + 1] = "ev:" .. (self.rangeProbeEvents or 0)
	local line = table.concat(parts, " ")
	self:Print(line)
	if line ~= self.rangeProbeLast then
		ProbeRecord(line)
		self.rangeProbeLast = line
	end
end

function Addon:ToggleRangeProbe()
	self.rangeProbeOn = not self.rangeProbeOn
	if self.rangeProbeOn then
		FourEverSwingTimerTrace = FourEverSwingTimerTrace or {}
		local _, class = UnitClass("player")
		self.rangeProbeSpell = Addon.RANGE_MELEE_SPELLS and Addon.RANGE_MELEE_SPELLS[strlower(class or "")]
		self.rangeProbeEvents = 0
		self.rangeProbeLast = nil
		if C_SwingTimer and C_SwingTimer.EnableRangeCheck then
			-- Arm both hands first, mirroring the bug-report repro: the
			-- initial state push (if wired) lands on the event below.
			C_SwingTimer.EnableRangeCheck(0, true)
			C_SwingTimer.EnableRangeCheck(2, true)
			ProbeRecord("ARMED", "EnableRangeCheck", 0, 2)
		else
			ProbeRecord("ARMED", "C_SwingTimer", "gone")
		end
		if not self.rangeProbeFrame then
			self.rangeProbeFrame = CreateFrame("Frame")
			self.rangeProbeFrame:SetScript("OnEvent", function(_, event, ...)
				Addon.rangeProbeEvents = (Addon.rangeProbeEvents or 0) + 1
				local a, b, c = ...
				ProbeRecord("EVENT", event, a, b, c)
				Addon:Print("PLAYER_SWING_RANGE_UPDATE fired: " .. tostring(a) .. " " .. tostring(b) .. " " .. tostring(c))
			end)
		end
		self.rangeProbeFrame:RegisterEvent("PLAYER_SWING_RANGE_UPDATE")
		self.rangeProbeTicker = C_Timer.NewTicker(RANGE_PROBE_TICK, function()
			Addon:RangeProbeSample()
		end)
		ProbeRecord("SESSION", GetBuildInfo())
		self:Print("Range probe ON - target a hostile, walk in/out of melee and ranged range, read the sample lines. Same command stops it.")
	else
		if self.rangeProbeTicker then
			self.rangeProbeTicker:Cancel()
			self.rangeProbeTicker = nil
		end
		if self.rangeProbeFrame then
			self.rangeProbeFrame:UnregisterEvent("PLAYER_SWING_RANGE_UPDATE")
		end
		ProbeRecord("OFF", "events", self.rangeProbeEvents or 0)
		self:Print("Range probe OFF - " .. (self.rangeProbeEvents or 0) .. " PLAYER_SWING_RANGE_UPDATE fire(s) this run.")
	end
end


SLASH_4EVERSWINGTIMER1 = "/4everswingtimer"
SLASH_4EVERSWINGTIMER2 = "/everswing"

SlashCmdList["4EVERSWINGTIMER"] = function(msg)
	local command, arg = strtrim(msg or ""):lower():match("^(%S+)%s*(.-)$")
	if command == "" or command == "config" or command == "options" then
		Addon.Options:Open()
	elseif command == "lock" or command == "unlock" then
		Addon:Print("Bars are placed in Edit Mode now: open Edit Mode (Esc) and drag them there.")
	elseif command == "test" then
		if arg == "" then
			Addon.Bars:Test()
		elseif arg == "interrupt" or arg == "clip" then
			Addon.Bars:TestEffect("interrupt")
		elseif arg == "haste" or arg == "parry" then
			Addon.Bars:TestEffect("haste")
		elseif arg == "delay" or arg == "ranged" then
			Addon.Bars:TestEffect("delay")
		elseif arg == "queued" or arg == "queue" then
			Addon.Bars:TestEffect("queued")
		elseif arg == "effects" or arg == "all" then
			Addon.Bars:TestEffect("all")
		else
			Addon:Print("Unknown test: " .. arg .. ". Try |cffddddddtest interrupt|haste|delay|queued|effects|r")
		end
	elseif command == "debug" then
		Addon.Bars:Debug()
	elseif command == "trace" then
		Addon:ToggleTrace()
	elseif command == "proberange" then
		Addon:ToggleRangeProbe()
	elseif command == "reset" then
		if arg == "settings" or arg == "all" then
			Addon:ResetSettings()
			Addon:Print("Settings reset.")
		end
		if arg ~= "settings" then
			Addon.EditMode:ResetPosition()
			Addon:Print("Position reset.")
		end
	elseif command == "help" then
		Addon:Print("Commands: |cffdddddd/4everswingtimer|r (settings), test [interrupt|haste|delay|queued|effects], debug, trace, proberange, reset [settings|all], help. Bars are placed in Edit Mode (Esc): click them there for the panel.")
	else
		Addon:Print("Unknown command: " .. command .. ". Try |cffdddddd/4everswingtimer help|r")
	end
end
