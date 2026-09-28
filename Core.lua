-- 4everSwingTimer — player swing timer bars for WoW: Forever.
-- Core: bootstrap, saved variables, library gate, event dispatch, slash commands.
-- Bar rendering lives in Bars.lua; settings registration lives in Options.lua.
--
-- The addon holds no swing math of its own: all state comes from
-- LibClassicSwingTimerAPI events; nothing here reads UnitAttackSpeed or
-- UnitRangedDamage directly.

local ADDON_NAME = "4everSwingTimer"
local LIB_MAJOR = "LibClassicSwingTimerAPI"
-- The Forever swing path shipped with the library's 2.2.0 beta line (MINOR 34).
local REQUIRED_LIB_MINOR = 34

FourEverSwingTimer = {}
local Addon = FourEverSwingTimer
Addon.name = ADDON_NAME

local GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
Addon.version = GetAddOnMetadata and GetAddOnMetadata(ADDON_NAME, "Version") or UNKNOWN or "?"

-- ---------------------------------------------------------------------------
-- Saved variables
-- ---------------------------------------------------------------------------

local DEFAULTS = {
	point = "BOTTOM",
	relativeTo = "UIParent",
	relativePoint = "BOTTOM",
	x = 0,
	y = 220,
	locked = false,
	scale = 1.0,
	width = 260,
	height = 18,
	gap = 4,
	visibility = "combat", -- "swinging" | "combat" | "always"
	skin = "native",       -- "native" | "flat"
	fill = "drain",        -- "drain" | "fill"
	showTime = true,
	showSpeed = false,
	showLabel = true,
	showDelta = false,
	enabled = {
		mainhand = true,
		offhand = true,
		ranged = true,
	},
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

-- ---------------------------------------------------------------------------
-- Event dispatch
-- ---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
Addon.frame = frame

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")

frame:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == ADDON_NAME then
			ForeverSwingTimerDB = ForeverSwingTimerDB or {}
			Addon.ApplyDefaults(ForeverSwingTimerDB, DEFAULTS)
			Addon.db = ForeverSwingTimerDB
			Addon.Options:Init()
		end
	elseif event == "PLAYER_LOGIN" then
		Addon:OnEnable()
	elseif event == "PLAYER_REGEN_DISABLED" then
		Addon.inCombat = true
		if Addon.Bars then
			Addon.Bars:UpdateVisibility()
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		Addon.inCombat = false
		if Addon.Bars then
			Addon.Bars:UpdateVisibility()
		end
	end
end)

function Addon:OnEnable()
	self.inCombat = UnitAffectingCombat("player")
	local lib, minor = LibStub:GetLibrary(LIB_MAJOR, true)
	if not lib then
		self:Print("LibClassicSwingTimerAPI is missing. Bars are disabled; the library ships embedded, so a reinstall should fix this.")
		return
	elseif minor < REQUIRED_LIB_MINOR then
		self:Print("LibClassicSwingTimerAPI is too old (needs the 2.2.0 Forever support). Bars are disabled until the library updates.")
		return
	end
	self.lib = lib
	self.libMinor = minor
	self:CheckNativeTimer()
	self.Bars:Enable(lib)
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

SLASH_4EVERSWINGTIMER1 = "/4everswingtimer"
SLASH_4EVERSWINGTIMER2 = "/everswing"

SlashCmdList["4EVERSWINGTIMER"] = function(msg)
	local command = strtrim(msg or ""):lower()
	if command == "" or command == "config" or command == "options" then
		Addon.Options:Open()
	elseif command == "lock" then
		Addon.db.locked = true
		Addon.Bars:SetLocked(true)
		Addon:Print("Bars locked.")
	elseif command == "unlock" then
		Addon.db.locked = false
		Addon.Bars:SetLocked(false)
		Addon:Print("Bars unlocked - drag them to move. Lock with |cffdddddd/4everswingtimer lock|r or in settings.")
	elseif command == "test" then
		Addon.Bars:Test()
	elseif command == "reset" then
		local defaults = Addon.DEFAULTS
		Addon.db.point = defaults.point
		Addon.db.relativeTo = defaults.relativeTo
		Addon.db.relativePoint = defaults.relativePoint
		Addon.db.x = defaults.x
		Addon.db.y = defaults.y
		Addon.Bars:RestorePosition()
		Addon:Print("Position reset.")
	elseif command == "help" then
		Addon:Print("Commands: |cffdddddd/4everswingtimer|r (settings), unlock, lock, test, reset, help")
	else
		Addon:Print("Unknown command: " .. command .. ". Try |cffdddddd/4everswingtimer help|r")
	end
end
