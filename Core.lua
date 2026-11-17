-- ---------------------------------------------------------------------------
-- TagariaSoundFX
-- Play your own .mp3/.wav sounds when combat events happen: killing blows,
-- critical kills, your own death, procs, kill streaks and more.
--
-- Designed for the WoW Forever client (modern engine, interface 16001):
-- addons there have no combat log, so kills are detected through Blizzard's
-- PARTY_KILL event and honorable-kill credit instead. On clients that still
-- have a combat log (Classic family) the addon uses it for full kill and
-- crit detection. All combat data is read through secret-value guards.
-- ---------------------------------------------------------------------------

local ADDON_NAME, ns = ...
ns.ADDON_NAME = ADDON_NAME
ns.VERSION = "1.0.0"

local VERSION = ns.VERSION

-- ---------------------------------------------------------------------------
-- Client detection
-- ---------------------------------------------------------------------------

local INTERFACE = 0
do
	local ok, _, _, toc = pcall(GetBuildInfo)
	if ok then INTERFACE = tonumber(toc) or 0 end
end

-- Modern engine clients: retail Midnight (12.x) and WoW Forever (1.60.x,
-- interface 16001). These have no addon combat log and use secret values.
local IS_MODERN = INTERFACE >= 120000 or (INTERFACE >= 16000 and INTERFACE < 20000)
ns.IS_MODERN = IS_MODERN
ns.INTERFACE = INTERFACE

local SOUND_FOLDER = "Interface\\AddOns\\" .. ADDON_NAME .. "\\sounds\\"
ns.SOUND_FOLDER = SOUND_FOLDER

-- ---------------------------------------------------------------------------
-- Event definitions
-- ---------------------------------------------------------------------------

-- def  : enabled by default
-- tips : options tooltip
ns.EVENTS = {
	{ key = "KillPlayer",     label = "Killing Blow on a Player",         def = true,
	  tip = "Plays when you land a killing blow on an enemy player. Uses Blizzard's kill credit (honorable kills) and the PARTY_KILL event. Kills that give no honor (gray enemies) are only detected when the client can tell who you killed." },
	{ key = "KillPlayerCrit", label = "Killing Blow on a Player (Crit)",  def = true,
	  tip = "A killing blow on a player that was also a critical hit. Needs crit detection (combat log, or the experimental 'Watch my target' option); otherwise the normal killing blow sound plays." },
	{ key = "KillNPC",        label = "Killing Blow on a Mob",            def = false,
	  tip = "You or your pet landed the killing blow on a creature, pet or totem. Usually left off: it plays for every mob you kill." },
	{ key = "Death",          label = "You Died",                         def = true,
	  tip = "Plays when you die." },
	{ key = "Proc",           label = "Proc / Buff Trigger",              def = true,
	  tip = "One of the spells on the Proc list (see below) was just applied to you. Add spells by name (e.g. Crusader, Berserking) or spell ID." },
	{ key = "CritPlayer",     label = "Critical Hit on a Player",         def = false,
	  tip = "You critically hit an enemy player without killing them. Needs crit detection (combat log, or the experimental 'Watch my target' option)." },
	{ key = "Streak2",        label = "Double Kill",                      def = false,
	  tip = "A second player kill within the streak window. Plays in addition to the kill sound." },
	{ key = "Streak3",        label = "Triple Kill",                      def = false,
	  tip = "A third player kill within the streak window." },
	{ key = "Streak4",        label = "Quad Kill",                        def = false,
	  tip = "A fourth player kill within the streak window." },
	{ key = "Streak5",        label = "Multi Kill (5 or more)",            def = false,
	  tip = "A fifth (or more) player kill within the streak window." },
	{ key = "CombatIn",       label = "Entering Combat",                   def = false,
	  tip = "You entered combat." },
	{ key = "CombatOut",      label = "Leaving Combat",                    def = false,
	  tip = "You left combat." },
}

ns.EVENT_BY_KEY = {}
for _, event in ipairs(ns.EVENTS) do ns.EVENT_BY_KEY[event.key] = event end

-- Minimum seconds between two plays of the same (spammy) event.
local MIN_INTERVAL = {
	KillNPC     = 0.4,
	CritPlayer  = 1.0,
	Proc        = 0.75,
	CombatIn    = 1.0,
	CombatOut   = 1.0,
}

-- Seconds after which combat text crits / kill attributions are considered stale.
local CRIT_WINDOW       = 0.8   -- recent crit that can upgrade a kill to a crit kill
local KILL_DEDUPE       = 2.5   -- several signals for the same kill collapse into one sound
local KB_WINDOW         = 2.5   -- killing blow and honor credit may arrive in either order
local WARMUP            = 5     -- ignore kill credit right after login / loading screens
local STREAK_DELAY      = 0.3   -- small pause between the kill sound and the streak sound
local STREAK_MAX_WINDOW = 30

-- ---------------------------------------------------------------------------
-- Defaults and saved variables
-- ---------------------------------------------------------------------------

local defaults = {
	enabled         = true,
	channel         = "Master",   -- PlaySoundFile channel: "Master" or "SFX"
	streakWindow    = 8,          -- seconds for double/triple/... kill streaks
	onlyMyKills     = true,       -- in a group, require that I landed the killing blow
	watchTargetText = false,      -- experimental: watch target's combat text for crits
	debug           = false,
	showWelcome     = true,
	procSpells      = {},         -- spell names or IDs whose application counts as a proc
	events          = {},
}

local db

local function MergeDefaults()
	TagariaSoundFXDB = TagariaSoundFXDB or {}
	db = TagariaSoundFXDB

	for key, value in pairs(defaults) do
		if db[key] == nil then
			if type(value) == "table" then
				db[key] = {}
				for k, v in pairs(value) do db[key][k] = v end
			else
				db[key] = value
			end
		end
	end

	if type(db.events) ~= "table" then db.events = {} end
	for _, event in ipairs(ns.EVENTS) do
		local ev = db.events[event.key]
		if type(ev) ~= "table" then
			ev = {}
			db.events[event.key] = ev
		end
		if ev.enabled == nil then ev.enabled = event.def end
		if type(ev.sounds) ~= "table" then ev.sounds = {} end
	end

	if type(db.procSpells) ~= "table" then db.procSpells = {} end
	ns.db = db
end

-- ---------------------------------------------------------------------------
-- Chat / debug helpers
-- ---------------------------------------------------------------------------

local function Print(msg)
	(DEFAULT_CHAT_FRAME or ChatFrame1):AddMessage("|cffff8800Tagaria|r|cffffd100Sound|r|cffff8800FX|r: " .. msg)
end
ns.Print = Print

local function IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value) or false
end

local function SafeTostring(value)
	if IsSecret(value) then return "<secret>" end
	return tostring(value)
end

local function Debug(msg, ...)
	if not (db and db.debug) then return end
	local n = select("#", ...)
	local args = {}
	for i = 1, n do args[i] = SafeTostring((select(i, ...))) end
	Print("|cff999999[debug]|r " .. msg:format(unpack(args, 1, n)))
end
ns.Debug = Debug

-- ---------------------------------------------------------------------------
-- Sound engine
-- ---------------------------------------------------------------------------

local lastPlayed = {}

-- Turn a stored entry into a playable path. Plain file names are looked up in
-- the addon's sounds folder; anything containing a path separator is used as-is
-- (so built-in game sounds can be used too).
function ns.ResolveSoundPath(entry)
	local s = tostring(entry or "")
	s = s:gsub("/", "\\"):gsub("^%s+", ""):gsub("%s+$", "")
	if s == "" then return nil end
	if s:find("\\", 1, true) then return s end
	return SOUND_FOLDER .. s
end

function ns.PlaySoundPath(path)
	if not path then return end
	-- The channel argument is not supported everywhere; fall back gracefully.
	local ok = pcall(PlaySoundFile, path, db and db.channel or "Master")
	if not ok then pcall(PlaySoundFile, path) end
end

-- Play one random sound from the event's list (single entry = that one).
-- Returns true when a sound was actually played.
function ns.PlayEvent(eventKey, forceIndex)
	if not (db and db.enabled) then return false end
	local ev = db.events[eventKey]
	if not (ev and ev.enabled) then return false end
	local sounds = ev.sounds
	if not sounds or #sounds == 0 then return false end

	local index
	if forceIndex then
		index = forceIndex
	else
		local n = #sounds
		index = (n == 1) and 1 or math.random(n)
	end

	ns.PlaySoundPath(ns.ResolveSoundPath(sounds[index]))
	lastPlayed[eventKey] = GetTime()
	Debug("play %s #%d (%s)", eventKey, index, sounds[index])
	return true
end

-- Natural trigger: PlayEvent with the event's spam throttle applied.
function ns.TriggerEvent(eventKey)
	local min = MIN_INTERVAL[eventKey] or 0
	if min > 0 then
		local last = lastPlayed[eventKey]
		if last and (GetTime() - last) < min then
			Debug("%s throttled", eventKey)
			return false
		end
	end
	return ns.PlayEvent(eventKey)
end

-- ---------------------------------------------------------------------------
-- Secret-safe helpers
-- ---------------------------------------------------------------------------

local playerGUID

local function UnitGuid(unit)
	local ok, guid = pcall(UnitGUID, unit)
	if ok and guid and not IsSecret(guid) then return guid end
end

local function IsMyGUID(guid)
	if not guid or IsSecret(guid) then return false end
	if guid == playerGUID then return true end
	-- Permanent pets and vehicles you control count as "you".
	if UnitExists("pet") then
		local petGUID = UnitGuid("pet")
		if petGUID and guid == petGUID then return true end
	end
	if UnitExists("vehicle") then
		local vehGUID = UnitGuid("vehicle")
		if vehGUID and guid == vehGUID then return true end
	end
	return false
end

-- Player name from a unit token, if the client allows reading it.
local function SafeUnitName(unit)
	local ok, name, realm = pcall(UnitName, unit)
	if ok and name and not IsSecret(name) and name ~= "" then
		if realm and not IsSecret(realm) and realm ~= "" then
			return name .. "-" .. realm
		end
		return name
	end
end

local function IsInGroup()
	local ok, inGroup = pcall(IsInGroup)
	return ok and inGroup and true or false
end

-- nil means "the client hides who died".
local function VictimIsPlayer(guid)
	if not guid or IsSecret(guid) then return nil end
	if guid:find("^Player%-") then return true end
	if guid:find("^Creature%-") or guid:find("^Pet%-") or guid:find("^Vehicle%-")
		or guid:find("^Totem%-") or guid:find("^GameObject%-") then
		return false
	end
	-- Old-style numeric GUIDs: the first hex digit after 0x is the type
	-- (0 = player, 3 = NPC, 4 = pet, F = vehicle...).
	local typeNibble = tonumber(guid:match("^0x(%x)") or "", 16)
	if typeNibble ~= nil then
		return typeNibble == 0
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Proc list
-- ---------------------------------------------------------------------------

local procById, procByName = {}, {}
local lastProcAt = {}

local function RebuildProcLookups()
	procById, procByName = {}, {}
	for _, entry in ipairs(db.procSpells) do
		local id = tonumber(entry)
		if id then
			procById[id] = true
		else
			procByName[strtrim(tostring(entry)):lower()] = true
		end
	end
end
ns.RebuildProcLookups = RebuildProcLookups

local function MatchesProcSpell(spellId, name)
	if spellId and not IsSecret(spellId) then
		if procById[tonumber(spellId) or -1] then return true end
	end
	if name and not IsSecret(name) then
		if procByName[strtrim(tostring(name)):lower()] then return true end
	end
	return false
end

local function OnProcSpell(spellId, name)
	local key = tostring(spellId or "") .. "|" .. tostring(name or "")
	local now = GetTime()
	if lastProcAt[key] and (now - lastProcAt[key]) < 1 then return end
	lastProcAt[key] = now
	Debug("proc: %s (%s)", name, spellId)
	ns.TriggerEvent("Proc")
end

-- Full aura scan (fallback for clients without UNIT_AURA update info).
local function ScanAuras()
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
	local seen = {}
	local i = 1
	while true do
		local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
		if not ok or not aura then break end
		local spellId, name = aura.spellId, aura.name
		if not IsSecret(spellId) then seen[tonumber(spellId) or -1] = true end
		if ns.lastAuraIds and not ns.lastAuraIds[tonumber(spellId) or -1] then
			if MatchesProcSpell(spellId, name) then OnProcSpell(spellId, name) end
		end
		i = i + 1
	end
	ns.lastAuraIds = seen
end

-- ---------------------------------------------------------------------------
-- Kill detection
-- ---------------------------------------------------------------------------

local sessionHK          -- honorable kills this session (baseline)
local readyAt = math.huge
local pendingKill        -- my killing blow awaiting honor credit: { at, isPlayer, name }
local lastKillAt = -math.huge
local recentCritAt = -math.huge -- last crit seen through target combat text
local streakTimes = {}

local function GetSessionHK()
	if not GetPVPSessionStats then return nil end
	local ok, hk = pcall(GetPVPSessionStats)
	if ok and type(hk) == "number" and not IsSecret(hk) then return hk end
end

local function SessionHKIncreased()
	local hk = GetSessionHK()
	if hk == nil then return nil end
	local increased = sessionHK ~= nil and hk > sessionHK
	sessionHK = hk
	return increased
end

local function RegisterStreak()
	local now = GetTime()
	local window = math.min(math.max(tonumber(db.streakWindow) or 8, 2), STREAK_MAX_WINDOW)
	for i = #streakTimes, 1, -1 do
		if (now - streakTimes[i]) > window then
			table.remove(streakTimes, i)
		end
	end
	streakTimes[#streakTimes + 1] = now
	local count = #streakTimes
	if count >= 2 then
		local key = (count >= 5) and "Streak5" or ("Streak" .. count)
		-- Small pause so the streak sound does not overlap the kill sound.
		pcall(function()
			C_Timer.After(STREAK_DELAY, function()
				if db and db.enabled then ns.PlayEvent(key) end
			end)
		end)
	end
end

-- Crit info is best-effort everywhere; crit == nil means "unknown".
local function RecentCrit()
	local now = GetTime()
	if (now - recentCritAt) <= CRIT_WINDOW then
		return true
	end
	return nil
end

local function ConfirmPlayerKill(crit)
	local now = GetTime()
	if (now - lastKillAt) < KILL_DEDUPE then
		Debug("kill already sounded")
		return
	end
	lastKillAt = now
	pendingKill = nil

	if crit and ns.PlayEvent("KillPlayerCrit") then
		Debug("kill confirmed (crit)")
	else
		ns.PlayEvent("KillPlayer")
		Debug("kill confirmed")
	end
	RegisterStreak()
end

local function OnHonorableKillCredit(name)
	local now = GetTime()
	if now < readyAt then
		sessionHK = GetSessionHK()
		return
	end
	Debug("honorable kill credit: %s", name or "?")

	local kill = pendingKill
	if kill and (now - kill.at) <= KB_WINDOW then
		-- My killing blow was pending: this credit confirms it was a player.
		ConfirmPlayerKill(RecentCrit())
	else
		-- No killing blow of ours on record. In a group with "only my killing
		-- blows" on, this was someone else's kill. If the client simply can't
		-- tell (secrets), count it anyway.
		if db.onlyMyKills and IsInGroup() then
			Debug("group kill (not mine) - skipped")
		else
			ConfirmPlayerKill(RecentCrit())
		end
	end
end

-- Killing blow by me or my pet (PARTY_KILL event on modern clients).
local function OnMyKillingBlow(isPlayer, name)
	local now = GetTime()
	Debug("my killing blow: %s (player: %s)", name or "?", SafeTostring(isPlayer))

	if isPlayer == false then
		ns.TriggerEvent("KillNPC")
		return
	end

	-- isPlayer == true: certainly a player, play right away.
	-- isPlayer == nil:  wait briefly for honor credit to confirm.
	if isPlayer then
		ConfirmPlayerKill(RecentCrit())
	else
		pendingKill = { at = now, name = name }
		pcall(function()
			C_Timer.After(KB_WINDOW, function()
				if pendingKill and (GetTime() - pendingKill.at) >= KB_WINDOW then
					-- No honor credit arrived: most likely a mob after all.
					pendingKill = nil
					ns.TriggerEvent("KillNPC")
				end
			end)
		end)
	end
end

-- ---------------------------------------------------------------------------
-- Combat-log detection (Classic family clients)
-- ---------------------------------------------------------------------------

local usesCombatLog = false
local recentCritByVictim = {}   -- victim GUID -> time of my last critical hit
local pendingCritByVictim = {}  -- victim GUID -> time (for non-fatal crit sounds)

-- Position of the "critical" flag inside the suffix of damage subevents.
local DAMAGE_SUBEVENTS = {
	SWING_DAMAGE           = 7,
	RANGE_DAMAGE           = 10,
	SPELL_DAMAGE           = 10,
	SPELL_PERIODIC_DAMAGE  = 10,
	SPELL_BUILDING_DAMAGE  = 10,
	DAMAGE_SHIELD          = 10,
	DAMAGE_SPLIT           = 10,
}

local function ParseCLEU()
	if not CombatLogGetCurrentEventInfo then return end
	local _, subevent, arg3 = CombatLogGetCurrentEventInfo()
	if not subevent then return end
	local isDamage = DAMAGE_SUBEVENTS[subevent]
	if subevent ~= "PARTY_KILL" and not isDamage then return end

	-- Modern layouts pass hideCaster (a boolean) as the 3rd value; very old
	-- layouts start with the source GUID there instead.
	local prefix = (type(arg3) == "boolean") and 11 or 8
	local srcGUID, srcFlags, dstGUID, dstName, dstFlags
	if prefix == 11 then
		_, _, _, srcGUID, _, srcFlags, _, dstGUID, dstName, dstFlags = CombatLogGetCurrentEventInfo()
	else
		_, _, srcGUID, _, srcFlags, dstGUID, dstName, dstFlags = CombatLogGetCurrentEventInfo()
	end

	if subevent == "PARTY_KILL" then
		if not IsMyGUID(srcGUID) then return end
		local isPlayer = VictimIsPlayer(dstGUID)
		if isPlayer == nil then
			local flagPlayer = COMBATLOG_OBJECT_TYPE_PLAYER or 0x00000400
			if type(dstFlags) == "number" then
				isPlayer = (bit.band(dstFlags, flagPlayer) ~= 0) or nil
			end
		end
		-- Was the killing blow a crit?
		local crit
		local at = recentCritByVictim[dstGUID or ""]
		if at and (GetTime() - at) <= CRIT_WINDOW then crit = true end
		pendingCritByVictim[dstGUID or ""] = nil

		if isPlayer == false then
			ns.TriggerEvent("KillNPC")
			return
		end
		-- Player or unknown: play the player kill (dedupe handles double credit).
		local now = GetTime()
		if (now - lastKillAt) < KILL_DEDUPE then return end
		lastKillAt = now
		if crit and ns.PlayEvent("KillPlayerCrit") then
			-- crit kill sound played
		else
			ns.PlayEvent("KillPlayer")
		end
		RegisterStreak()
		return
	end

	-- Damage event: track my critical hits.
	if not IsMyGUID(srcGUID) then return end
	local critical = select(prefix + isDamage, CombatLogGetCurrentEventInfo())
	if type(critical) == "number" then critical = critical == 1 end
	if not critical then return end

	local victim = dstGUID or ""
	recentCritByVictim[victim] = GetTime()
	if VictimIsPlayer(dstGUID) then
		local at = GetTime()
		if not pendingCritByVictim[victim] then
			pendingCritByVictim[victim] = at
			pcall(function()
				C_Timer.After(0.35, function()
					if pendingCritByVictim[victim] == at then
						pendingCritByVictim[victim] = nil
						-- Victim did not die in the meantime: a non-fatal crit.
						if db and db.enabled then ns.TriggerEvent("CritPlayer") end
					end
				end)
			end)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Combat text watching (experimental crit detection on modern clients)
-- ---------------------------------------------------------------------------

local function SetWatchedUnit(unit)
	if C_CombatText and C_CombatText.SetActiveUnit then
		pcall(C_CombatText.SetActiveUnit, unit)
		Debug("combat text now watches: %s", unit)
	end
end
ns.SetWatchedUnit = SetWatchedUnit

local function ApplyWatchTarget()
	if db.watchTargetText then
		SetWatchedUnit("target")
	else
		-- Return control to Blizzard's own combat text.
		SetWatchedUnit(UnitExists("vehicle") and "vehicle" or "player")
	end
end
ns.ApplyWatchTarget = ApplyWatchTarget

local function OnCombatText(messageType)
	-- Only meaningful when we deliberately watch the target's combat text;
	-- with the default (watching yourself) DAMAGE_CRIT means YOU were crit.
	if not (db and db.watchTargetText) then return end
	if messageType ~= "DAMAGE_CRIT" and messageType ~= "SPELL_DAMAGE_CRIT" then return end
	recentCritAt = GetTime()

	local ok, isPlayer = pcall(UnitIsPlayer, "target")
	if ok and type(isPlayer) == "boolean" and not IsSecret(isPlayer) then
		if isPlayer then
			ns.TriggerEvent("CritPlayer")
		end
	else
		-- Can't tell what the target is: still refresh the crit marker for
		-- critical-kill detection, but don't play the crit hit sound.
		Debug("target type hidden (secret)")
	end
end

-- ---------------------------------------------------------------------------
-- Event handling
-- ---------------------------------------------------------------------------

local F = CreateFrame("Frame")
ns.frame = F

local handlers = {}

function handlers.ADDON_LOADED(name)
	if name ~= ADDON_NAME then return end
	MergeDefaults()
	RebuildProcLookups()
	ApplyWatchTarget()
	F:UnregisterEvent("ADDON_LOADED")

	-- Options.lua is loaded by now; build the settings panel.
	if ns.CreateOptions then ns.CreateOptions() end

	if db.showWelcome then
		db.showWelcome = false
		Print("loaded. Drop your sounds into |cff00ff00" .. SOUND_FOLDER .. "|r and type |cffffff00/tsfx|r to assign them to events.")
	end
end

function handlers.PLAYER_ENTERING_WORLD()
	playerGUID = UnitGuid("player")
	readyAt = GetTime() + WARMUP
	sessionHK = GetSessionHK()
	pendingKill = nil
	streakTimes = {}
	recentCritByVictim, pendingCritByVictim = {}, {}
	if db then ApplyWatchTarget() end
end

function handlers.PLAYER_DEAD()
	Debug("player died")
	ns.TriggerEvent("Death")
end

function handlers.PARTY_KILL(attackerGUID, targetGUID)
	if GetTime() < readyAt then return end
	if IsMyGUID(attackerGUID) then
		local isPlayer = VictimIsPlayer(targetGUID)
		local name
		if isPlayer and targetGUID and GetPlayerInfoByGUID then
			local ok, _, _, _, _, _, playerName = pcall(GetPlayerInfoByGUID, targetGUID)
			if ok and playerName and not IsSecret(playerName) and playerName ~= "" then
				name = playerName
			end
		end
		OnMyKillingBlow(isPlayer, name)
	else
		-- A group member's kill: interesting only for the KillNPC event, which
		-- is only about our own kills, so just note it in debug mode.
		Debug("party kill by someone else")
	end
end

function handlers.PLAYER_PVP_KILLS_CHANGED(unitTarget)
	if GetTime() < readyAt then
		sessionHK = GetSessionHK()
		return
	end
	local increased = SessionHKIncreased()
	Debug("PVP_KILLS_CHANGED (unit: %s, counter up: %s)", SafeTostring(unitTarget), SafeTostring(increased))
	-- unitTarget is only passed for an actual kill; otherwise trust the counter.
	local hasUnit = unitTarget and not IsSecret(unitTarget)
	if hasUnit or increased == true or increased == nil then
		local name
		if hasUnit then name = SafeUnitName(unitTarget) end
		OnHonorableKillCredit(name)
	end
end

function handlers.CHAT_MSG_COMBAT_HONOR_GAIN()
	if GetTime() < readyAt then return end
	-- Backup signal: some clients send the honor message before the counter.
	pcall(function()
		C_Timer.After(0.3, function()
			if SessionHKIncreased() then
				OnHonorableKillCredit()
			end
		end)
	end)
end

function handlers.UNIT_AURA(unit, updateInfo)
	if unit ~= "player" or not db or not db.enabled then return end
	if not next(db.procSpells) then return end

	-- New-or-refreshed auras are handed to us directly on modern clients.
	if type(updateInfo) == "table" and type(updateInfo.addedAuras) == "table" then
		for _, aura in ipairs(updateInfo.addedAuras) do
			local ok, err = pcall(function()
				if aura.isHarmful and not IsSecret(aura.isHarmful) then return end
				if MatchesProcSpell(aura.spellId, aura.name) then
					OnProcSpell(aura.spellId, aura.name)
				end
			end)
			if not ok then Debug("aura error: %s", err) end
		end
	else
		ScanAuras()
	end
end

function handlers.COMBAT_TEXT_UPDATE(messageType)
	OnCombatText(messageType)
end

function handlers.PLAYER_REGEN_DISABLED()
	ns.TriggerEvent("CombatIn")
end

function handlers.PLAYER_REGEN_ENABLED()
	ns.TriggerEvent("CombatOut")
end

function handlers.COMBAT_LOG_EVENT_UNFILTERED()
	ParseCLEU()
end

F:SetScript("OnEvent", function(_, event, ...)
	local handler = handlers[event]
	if handler then
		local ok, err = pcall(handler, ...)
		if not ok then
			Print("|cffff4040error in " .. event .. ":|r " .. tostring(err))
		end
	end
end)

local function TryRegister(event)
	local ok = pcall(F.RegisterEvent, F, event)
	if not ok then Debug("cannot register %s on this client", event) end
	return ok
end

local function TryRegisterUnitEvent(event, unit)
	local ok = pcall(F.RegisterUnitEvent, F, event, unit)
	if not ok then ok = pcall(F.RegisterEvent, F, event) end
	if not ok then Debug("cannot register %s on this client", event) end
	return ok
end

for _, event in ipairs({
	"ADDON_LOADED",
	"PLAYER_ENTERING_WORLD",
	"PLAYER_DEAD",
	"CHAT_MSG_COMBAT_HONOR_GAIN",
	"PLAYER_REGEN_DISABLED",
	"PLAYER_REGEN_ENABLED",
	"COMBAT_TEXT_UPDATE",
}) do
	TryRegister(event)
end

-- Auras are only interesting on the player: use the unit-scoped registration
-- when the client offers it.
TryRegisterUnitEvent("UNIT_AURA", "player")

-- Client-dependent signals. Registration itself is the capability check:
-- the modern client forbids the combat log, classic clients have no
-- PARTY_KILL UI event.
ns.canPartyKill = TryRegister("PARTY_KILL")
if IS_MODERN then
	ns.canPartyKill = ns.canPartyKill == true
	usesCombatLog = false
else
	ns.canPartyKill = false
	usesCombatLog = TryRegister("COMBAT_LOG_EVENT_UNFILTERED")
end
ns.canCombatLog = usesCombatLog
ns.canHKCredit = TryRegister("PLAYER_PVP_KILLS_CHANGED")

-- ---------------------------------------------------------------------------
-- Public helpers used by the options panel and slash commands
-- ---------------------------------------------------------------------------

local function KillSoundsAvailable(eventKey)
	if eventKey == "KillPlayer" or eventKey == "KillNPC" then
		return ns.canPartyKill or ns.canCombatLog or ns.canHKCredit
	elseif eventKey == "KillPlayerCrit" or eventKey == "CritPlayer" then
		if ns.canCombatLog then return true, "combat log" end
		if db and db.watchTargetText then return true, "watch target (experimental)" end
		return false, "needs 'Watch my target' or a combat-log client"
	elseif eventKey == "Death" or eventKey == "CombatIn" or eventKey == "CombatOut" then
		return true
	elseif eventKey == "Proc" then
		return true
	elseif eventKey == "Streak2" or eventKey == "Streak3" or eventKey == "Streak4" or eventKey == "Streak5" then
		return ns.canPartyKill or ns.canCombatLog or ns.canHKCredit
	end
	return true
end
ns.KillSoundsAvailable = KillSoundsAvailable

local function FindEventKey(partial)
	partial = (partial or ""):lower()
	for _, event in ipairs(ns.EVENTS) do
		if event.key:lower() == partial then return event.key end
	end
	for _, event in ipairs(ns.EVENTS) do
		if event.key:lower():find(partial, 1, true) or event.label:lower():find(partial, 1, true) then
			return event.key
		end
	end
end

local function DescribeCapabilities()
	local lines = {}
	table.insert(lines, ("Client interface: |cff00ff00%d|r%s"):format(INTERFACE,
		IS_MODERN and " (modern engine - WoW Forever / Midnight rules)" or " (classic engine - combat log available)"))
	table.insert(lines, "Combat log: " .. (ns.canCombatLog and "|cff00ff00available|r (full kill + crit detection)" or "|cffff8040not available to addons|r"))
	table.insert(lines, "PARTY_KILL event: " .. (ns.canPartyKill and "|cff00ff00available|r" or "|cffff8040unavailable|r"))
	table.insert(lines, "Honorable kill credit: " .. (ns.canHKCredit and "|cff00ff00available|r" or "|cffff8040unavailable|r"))
	local ok, how = KillSoundsAvailable("KillPlayerCrit")
	table.insert(lines, "Crit detection: " .. (ok and ("|cff00ff00" .. how .. "|r") or ("|cffff8040" .. how .. "|r")))
	return lines
end

local function PrintStatus()
	Print(("|cff%s%s|r is %s"):format(db.enabled and "00ff00" or "ff4040", "TagariaSoundFX", db.enabled and "enabled" or "disabled"))
	for _, event in ipairs(ns.EVENTS) do
		local ev = db.events[event.key]
		local count = ev.sounds and #ev.sounds or 0
		Print(("  %s %s - %d sound%s"):format(
			ev.enabled and "|cff00ff00[on] |r" or "|cffff4040[off]|r",
			event.label, count, count == 1 and "" or "s"))
	end
	Print("Sound channel: " .. tostring(db.channel) .. " - streak window: " .. tostring(db.streakWindow) .. "s")
	for _, line in ipairs(DescribeCapabilities()) do Print(line) end
end

local function SetEnabled(value)
	db.enabled = value and true or false
	if ns.RefreshOptions then ns.RefreshOptions() end
end
ns.SetEnabled = SetEnabled

SLASH_TAGARIASOUNDFX1 = "/tsfx"
SLASH_TAGARIASOUNDFX2 = "/tagaria"
SlashCmdList.TAGARIASOUNDFX = function(input)
	local cmd, arg = (strtrim(input or "")):lower():match("^(%S*)%s*(.-)$")
	if cmd == "" or cmd == "options" or cmd == "config" then
		if ns.OpenOptions then ns.OpenOptions() end
	elseif cmd == "on" or cmd == "enable" then
		SetEnabled(true)
		Print("enabled.")
	elseif cmd == "off" or cmd == "disable" then
		SetEnabled(false)
		Print("disabled.")
	elseif cmd == "toggle" then
		SetEnabled(not db.enabled)
		Print(db.enabled and "enabled." or "disabled.")
	elseif cmd == "debug" then
		db.debug = not db.debug
		Print("debug mode " .. (db.debug and "on" or "off") .. ".")
	elseif cmd == "watchtarget" then
		if arg == "on" or arg == "off" then
			db.watchTargetText = (arg == "on")
		else
			db.watchTargetText = not db.watchTargetText
		end
		ApplyWatchTarget()
		if ns.RefreshOptions then ns.RefreshOptions() end
		Print("watch my target's combat text: " .. (db.watchTargetText and "on" or "off"))
	elseif cmd == "status" then
		PrintStatus()
	elseif cmd == "test" then
		if arg == "" then
			Print("usage: |cffffff00/tsfx test <event>|r, e.g. /tsfx test kill")
			for _, event in ipairs(ns.EVENTS) do
				Print("  " .. event.key .. " - " .. event.label)
			end
		else
			local key = FindEventKey(arg)
			if not key then
				Print("no event matches '" .. arg .. "'.")
			elseif ns.PlayEvent(key) then
				Print("testing " .. ns.EVENT_BY_KEY[key].label .. ".")
			else
				Print(ns.EVENT_BY_KEY[key].label .. " has no sounds yet - add some in the options (/tsfx).")
			end
		end
	elseif cmd == "help" then
		Print("commands: |cffffff00/tsfx|r options | on | off | toggle | status | test <event> | watchtarget | debug|r")
	else
		Print("unknown command '" .. cmd .. "'. Type |cffffff00/tsfx help|r.")
	end
end
