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
ns.VERSION = "1.5.6"

local VERSION = ns.VERSION

-- ---------------------------------------------------------------------------
-- Client detection
-- ---------------------------------------------------------------------------

-- GetBuildInfo() returns version, build, date, tocversion; pcall prepends its
-- own "ok", so the interface number is the FIFTH value.
local INTERFACE = 0
do
	local ok, _, _, _, toc = pcall(GetBuildInfo)
	if ok then INTERFACE = tonumber(toc) or 0 end
end

-- Modern engine clients: retail Midnight (12.x) and WoW Forever (1.60.x,
-- interface 16001). These have no addon combat log and use secret values.
local IS_MODERN = INTERFACE >= 120000 or (INTERFACE >= 16000 and INTERFACE < 20000)

-- Hard evidence of the restricted modern engine (12.x / WoW Forever): these
-- exist there and not on Classic-family clients. Registering the combat log
-- event is a FORBIDDEN action on the modern engine (the "blocked from an
-- action only available to the Blizzard UI" popup), so it must never be
-- attempted when this evidence is present, whatever the interface number says.
local HAS_RESTRICTED_ENGINE = (C_CombatLog ~= nil) or (issecretvalue ~= nil)

ns.IS_MODERN = IS_MODERN
ns.INTERFACE = INTERFACE

local SOUND_FOLDER = "Interface\\AddOns\\" .. ADDON_NAME .. "\\sounds\\"
ns.SOUND_FOLDER = SOUND_FOLDER

-- ---------------------------------------------------------------------------
-- Event definitions
-- ---------------------------------------------------------------------------

-- def          : enabled by default
-- defaultSound : seeded into the sound list on first run (once)
-- tip          : options tooltip
ns.EVENTS = {
	{ key = "KillPlayer",     label = "Killing Blow on a Player",         def = true,
	  defaultSound = "etsi-kopio.mp3",
	  tip = "Plays when you land a killing blow on an enemy player. Uses Blizzard's kill credit (honorable kills) and the PARTY_KILL event. Kills that give no honor (gray enemies) are only detected when the client can tell who you killed." },
	{ key = "KillNPC",        label = "Killing Blow on a Mob",            def = false,
	  tip = "You or your pet landed the killing blow on a creature, pet or totem. Usually left off: it plays for every mob you kill." },
	{ key = "Death",          label = "You Died",                         def = true,
	  tip = "Plays when you die." },
	{ key = "DeathByPlayer",  label = "You Died to a Player (PvP Death)", def = true,
	  defaultSound = "poutanas-vasana.mp3",
	  tip = "You died to an enemy player, or died within the PvP death window of being damaged by one. " ..
		"With a combat log every hit from an enemy player counts; on WoW Forever the death recap and active battlegrounds are used." },
	{ key = "Proc",           label = "Proc / Buff Trigger",              def = true,
	  defaultSound = "1-6.mp3",
	  tip = "A proc just applied to you, your target, or one of your allies. " ..
		"The current Forever proc talents are detected by default: Bloodthrill, Weaponmaster, Enrage, Flurry, " ..
		"Blood Craze, Gore Drinker, Unbridled Wrath, Redoubt, Reckoning, Vengeance, Unsealed Wrath, Deadly Aspects, " ..
		"Frenzy, Expose Prey, Remorseless Attacks, Quick Getaway, Spirit Tap, Elemental Focus, Maelstrom Weapon, " ..
		"Fingers of Frost, Frostbite, Missile Barrage, Heating Up, Nightfall, Oomen of Clarity, Nature's Grace, " ..
		"Eclipse, and the weapon enchants (Crusader, Revelation, Insight, Recovery, Lifestealing, Fiery Weapon, " ..
		"Unholy Weapon, Icy Chill). Procs with no aura (extra attacks, instant energy, free casts, " ..
		"Seal of Command's bonus hit) cannot be detected this way. Add more in the options (PROC SPELLS) by name or spell ID." },
	{ key = "CritPlayer",     label = "Critical Hit on a Player",         def = true,
	  defaultSound = "kopio.mp3",
	  tip = "You critically hit an enemy player without killing them. Needs crit detection (combat log, or the experimental 'Watch my target' option on WoW Forever); without it this event never fires." },
	{ key = "Interrupt",      label = "Interrupt or Silence",            def = true,
	  defaultSound = "poniros.mp3",
	  tip = "You successfully interrupted your target's spellcast, or landed a silence on your target. " ..
		"Interrupts are detected directly (the client reports who interrupted); silences are recognized from the spell list below " ..
		"(built-in: Kick, Pummel, Shield Bash, Counterspell, Earth Shock, Spell Lock, Silence - add your own too)." },
	{ key = "CrowdControl",   label = "You Got Crowd Controlled",        def = true,
	  defaultSound = "germaniki.mp3",
	  tip = "Plays when you are crowd controlled: feared, rooted, stunned, polymorphed, slept, sapped, " ..
		"charmed or mind controlled, dazed or paralysed. Detected from the CC effect that lands on you " ..
		"(by its effect type and name). Silence and snares are not crowd control." },
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
	KillNPC      = 0.4,
	CritPlayer   = 1.0,
	Proc         = 0.75,
	Interrupt    = 0.5,
	CrowdControl = 1.0,
	CombatIn     = 1.0,
	CombatOut    = 1.0,
}

-- Seconds after which combat text crits / kill attributions are considered stale.
local KILL_DEDUPE       = 2.5   -- several signals for the same kill collapse into one sound
local KB_WINDOW         = 2.5   -- killing blow and honor credit may arrive in either order
local WARMUP            = 5     -- ignore kill credit right after login / loading screens
local STREAK_DELAY      = 0.3   -- small pause between the kill sound and the streak sound
local STREAK_MAX_WINDOW = 30
local INTERRUPT_WINDOW  = 1.5   -- my interrupt spell and the confirmed interrupt may be this far apart
local DEATH_RECAP_DELAY = 0.5   -- the death recap needs a moment to arrive

-- ---------------------------------------------------------------------------
-- Defaults and saved variables
-- ---------------------------------------------------------------------------

local defaults = {
	enabled         = true,
	channel         = "Master",   -- PlaySoundFile channel: "Master" or "SFX"
	streakWindow    = 8,          -- seconds for double/triple/... kill streaks
	pvpDeathWindow  = 15,         -- seconds: damaged by an enemy player before dying counts as a PvP death
	onlyMyKills     = true,       -- in a group, require that I landed the killing blow
	watchTargetText = false,      -- experimental: watch target's combat text for crits
	debug           = false,
	showWelcome     = true,
	procSpells      = {},         -- spell names or IDs whose application counts as a proc
	interruptSpells = {},         -- extra interrupt/silence spell names or IDs beyond the built-ins
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

	-- Seed built-in default sounds into events that have one, exactly once
	-- per event: if the user later removes it, it stays removed.
	if type(db.seededDefaults) ~= "table" then db.seededDefaults = {} end
	for _, event in ipairs(ns.EVENTS) do
		if event.defaultSound and not db.seededDefaults[event.key] then
			db.seededDefaults[event.key] = true
			local ev = db.events[event.key]
			if type(ev.sounds) == "table" and #ev.sounds == 0 then
				ev.sounds[1] = event.defaultSound
			end
		end
	end

	-- One-time migration: the built-in default for KillPlayer changed from
	-- kopio.mp3 to etsi-kopio.mp3. Swap any already-seeded copy so existing
	-- characters pick up the new default. Idempotent - once swapped there is
	-- nothing left to replace, so this is a no-op on later loads.
	local killPlayer = db.events["KillPlayer"]
	if type(killPlayer) == "table" and type(killPlayer.sounds) == "table" then
		for i, name in ipairs(killPlayer.sounds) do
			if name == "kopio.mp3" then killPlayer.sounds[i] = "etsi-kopio.mp3" end
		end
	end

	if type(db.procSpells) ~= "table" then db.procSpells = {} end
	if type(db.interruptSpells) ~= "table" then db.interruptSpells = {} end
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

-- Cheap check used for the frequent early-exit paths: is this event enabled
-- and does it actually have sounds to play?
local function EventHasSounds(eventKey)
	if not db then return false end
	local ev = db.events[eventKey]
	if not (ev and ev.enabled) then return false end
	return ev.sounds ~= nil and #ev.sounds > 0
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
-- Proc detection
-- ---------------------------------------------------------------------------

-- Famous procs, built in: their spell IDs are matched on your own auras, and
-- their names cover renamed / localized / re-ID'd variants (Forever gives
-- new content its own spell IDs). The user's own Proc spell list
-- (db.procSpells) is merged on top of these.
local BUILTIN_PROC_IDS = {
	2068,    -- Enrage
	28251,   -- Fingers of Frost (Mage, classic buff)
	34428,   -- Flurry
	17941,   -- Shadow Trance, Nightfall's proc (Warlock)
	1900,    -- Crusader weapon enchant proc
	31072,   -- Holy Strength (Crusader buff)
	8217,    -- Revelation weapon enchant proc (Forever)
	16870,   -- Clearcasting, Oomen of Clarity's proc (Druid)
	1898,    -- Lifestealing weapon enchant proc
	803,     -- Fiery Weapon enchant proc
}

-- The list follows the current Forever talent trees (verified against the
-- client data, build 1.60.1.x). Many procs (extra attacks, instant energy,
-- free casts) have no aura at all; the names are kept because a name that
-- never matches costs nothing.
local BUILTIN_PROC_NAMES = {
	-- Warrior
	"bloodthrill", "enrage", "flurry", "blood craze", "gore drinker",
	"weaponmaster", "unbridled wrath",
	-- Paladin
	"redoubt", "reckoning", "vengeance", "unsealed wrath",
	-- Hunter
	"deadly aspects", "frenzy", "expose prey", "mongoose bite",
	-- Rogue
	"remorseless attacks", "quick getaway", "seal fate", "hack and slash",
	"setup", "puncturing wounds", "relentless strikes",
	-- Priest
	"spirit tap", "searing light",
	-- Shaman
	"elemental focus", "lightning overload", "maelstrom weapon",
	-- Mage
	"fingers of frost", "missile barrage", "heating up", "clearcasting",
	-- Warlock
	"nightfall", "shadow trance",
	-- Druid
	"nature's grace", "eclipse", "natural reaction",
	-- Racial
	"berserking", "blood fury",
	-- Weapon enchants (the complete set in Forever)
	"crusader", "holy strength", "revelation", "insight", "recovery",
	"lifestealing", "fiery weapon",
}

-- Procs that land on someone else instead of on you (harmful effects from me:
-- Frostbite's root, CC procs, weapon enchant procs).
local BUILTIN_PROC_TARGET_IDS = {
	12494,   -- Frostbite (Mage) - the root on your target
	1899,    -- Unholy Weapon enchant - the curse on the target
	1894,    -- Icy Chill enchant - the slow on the target
}

local BUILTIN_PROC_TARGET_NAMES = {
	"frostbite",
	"concussive shot",  -- Hunter: stun on the target
	"entrapment",       -- Hunter: immobilize from traps
	"blackout",         -- Priest: stun on the target
	"icy chill", "icy weapon",
	"unholy", "unholy weapon",
}

local procById, procByName = {}, {}
local procTargetById, procTargetByName = {}, {}
local lastProcAt = {}

-- ---------------------------------------------------------------------------
-- Interrupt / silence spell matching
-- ---------------------------------------------------------------------------

-- Classic-era interrupt and silence spells (rank 1 IDs; higher ranks are
-- caught through their localized names, which are the same across ranks).
local BUILTIN_INTERRUPT_IDS = {
	2973,  -- Kick (Rogue)
	6554,  -- Pummel (Warrior)
	72,    -- Shield Bash (Warrior)
	2139,  -- Counterspell (Mage)
	8042,  -- Earth Shock (Shaman)
	24259, -- Spell Lock (Felhunter)
	15487, -- Silence (Priest)
}

local interruptIds, interruptNames = {}, {}
local spellNameCache = {}

local function SpellNameById(spellId)
	spellId = tonumber(spellId)
	if not spellId then return end
	local cached = spellNameCache[spellId]
	if cached ~= nil then return cached end
	local name
	if C_Spell and C_Spell.GetSpellName then
		local ok, n = pcall(C_Spell.GetSpellName, spellId)
		if ok and n and not IsSecret(n) then name = n end
	end
	if not name and GetSpellInfo then
		local ok, n = pcall(GetSpellInfo, spellId)
		if ok and n and not IsSecret(n) then name = n end
	end
	spellNameCache[spellId] = name or false
	return name
end

local function RebuildInterruptLookups()
	interruptIds, interruptNames = {}, {}
	for _, id in ipairs(BUILTIN_INTERRUPT_IDS) do
		interruptIds[id] = true
		local name = SpellNameById(id)
		if name then interruptNames[strtrim(name):lower()] = true end
	end
	for _, entry in ipairs(db.interruptSpells or {}) do
		local id = tonumber(entry)
		if id then
			interruptIds[id] = true
		else
			interruptNames[strtrim(tostring(entry)):lower()] = true
		end
	end
end
ns.RebuildInterruptLookups = RebuildInterruptLookups

local function IsInterruptOrSilenceSpell(spellId, name)
	if spellId and not IsSecret(spellId) then
		if interruptIds[tonumber(spellId) or -1] then return true end
		-- Resolve the cast spell's name so other ranks are recognized too.
		local resolved = SpellNameById(spellId)
		if resolved and interruptNames[resolved:lower()] then return true end
	end
	if name and not IsSecret(name) then
		if interruptNames[strtrim(tostring(name)):lower()] then return true end
	end
	return false
end

-- ---------------------------------------------------------------------------
-- Crowd control detection
-- ---------------------------------------------------------------------------

-- CC effects that count as being crowd controlled. The mechanic IDs are the
-- robust path (every rank and localization shares them); the names are a
-- fallback for clients that hide mechanic data. Silence and snares are NOT
-- crowd control (you can still act / move).
local CC_MECHANICS = {
	[4]  = true,  -- Disorient
	[6]  = true,  -- Feared
	[16] = true,  -- Mind Control (charm, dominate)
	[19] = true,  -- Paralysis
	[21] = true,  -- Polymorph
	[22] = true,  -- Rooted
	[23] = true,  -- Sap
	[28] = true,  -- Stunned
	[40] = true,  -- Dazed
}

-- Fallback names (lowercased, exact) for clients without mechanic data.
local CC_NAMES = {
	"fear", "dazzling fear", "terror", "panic", "psychic scream",
	"root", "frostbite", "entangling roots", "web", "entrapment",
	"stun", "concussive shot", "hex", "hexed",
	"sleep", "sap", "mind control", "charm", "seduction", "dominate",
	"dazed",
}
-- "polymorph" is matched as a prefix so "Polymorph (Chicken)" and the other
-- rank variants are covered as well.
local CC_NAME_PREFIXES = {
	"polymorph",
}

local ccByName = {}
for _, name in ipairs(CC_NAMES) do ccByName[name] = true end
local lastCCAt = {}

local function IsCrowdControlSpell(spellId, name, mechanics)
	if name and not IsSecret(name) then
		local n = strtrim(tostring(name)):lower()
		if ccByName[n] then return true end
		for _, p in ipairs(CC_NAME_PREFIXES) do
			if n:sub(1, #p) == p then return true end
		end
	end
	if mechanics and not IsSecret(mechanics) and type(mechanics) == "table" then
		for i = 1, #mechanics do
			local m = mechanics[i]
			if m and not IsSecret(m) and CC_MECHANICS[m] then return true end
		end
	end
	return false
end

local function OnCrowdControl(spellId, name)
	local key = tostring(spellId or "") .. "|" .. tostring(name or "")
	local now = GetTime()
	if lastCCAt[key] and (now - lastCCAt[key]) < 1 then return end
	lastCCAt[key] = now
	Debug("crowd controlled: %s (%s)", name, spellId)
	ns.TriggerEvent("CrowdControl")
end

local function RebuildProcLookups()
	procById, procByName = {}, {}
	procTargetById, procTargetByName = {}, {}
	for _, id in ipairs(BUILTIN_PROC_IDS) do
		procById[id] = true
		local name = SpellNameById(id)
		if name then procByName[strtrim(name):lower()] = true end
	end
	for _, name in ipairs(BUILTIN_PROC_NAMES) do
		procByName[name] = true
	end
	for _, id in ipairs(BUILTIN_PROC_TARGET_IDS) do
		procTargetById[id] = true
		local name = SpellNameById(id)
		if name then procTargetByName[strtrim(name):lower()] = true end
	end
	for _, name in ipairs(BUILTIN_PROC_TARGET_NAMES) do
		procTargetByName[name] = true
	end
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

-- Procs that land on the target (e.g. a mage's Frostbite root).
local function MatchesProcTarget(spellId, name)
	if spellId and not IsSecret(spellId) then
		if procTargetById[tonumber(spellId) or -1] then return true end
	end
	if name and not IsSecret(name) then
		if procTargetByName[strtrim(tostring(name)):lower()] then return true end
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

-- Full aura scan (fallback for clients without UNIT_AURA update info, or
-- when the client hides the update's aura list as a secret).
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

	-- Harmful auras: CC effects (fear, root, stun, ...) on me.
	local seenHarmful = {}
	i = 1
	while true do
		local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HARMFUL")
		if not ok or not aura then break end
		local spellId, name = aura.spellId, aura.name
		if not IsSecret(spellId) then seenHarmful[tonumber(spellId) or -1] = true end
		if ns.lastAuraHarmfulIds and not ns.lastAuraHarmfulIds[tonumber(spellId) or -1] then
			if EventHasSounds("CrowdControl")
				and IsCrowdControlSpell(spellId, name, aura.mechanics) then
				OnCrowdControl(spellId, name)
			end
		end
		i = i + 1
	end
	ns.lastAuraHarmfulIds = seenHarmful
end

-- ---------------------------------------------------------------------------
-- Kill detection
-- ---------------------------------------------------------------------------

local sessionHK          -- honorable kills this session (baseline)
local readyAt = math.huge
local pendingKill        -- my killing blow awaiting honor credit: { at, isPlayer, name }
local lastKillAt = -math.huge
local streakTimes = {}
local lastPlayerDamageAt = -math.huge -- last damage I took from an enemy player

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

local function ConfirmPlayerKill()
	local now = GetTime()
	if (now - lastKillAt) < KILL_DEDUPE then
		Debug("kill already sounded")
		return
	end
	lastKillAt = now
	pendingKill = nil

	ns.PlayEvent("KillPlayer")
	Debug("kill confirmed")
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
		ConfirmPlayerKill()
	else
		-- No killing blow of ours on record. In a group with "only my killing
		-- blows" on, this was someone else's kill. If the client simply can't
		-- tell (secrets), count it anyway.
		if db.onlyMyKills and IsInGroup() then
			Debug("group kill (not mine) - skipped")
		else
			ConfirmPlayerKill()
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
		ConfirmPlayerKill()
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
-- Death resolution: was it a PvP death?
-- ---------------------------------------------------------------------------

local function IsInActiveBattlefield()
	local ok, inBg = pcall(UnitInBattleground, "player")
	if ok and inBg then return true end
	local okArena, arena = pcall(IsActiveBattlefieldArena)
	if okArena and arena then return true end
	if C_PvP then
		local okMap, isPvPMap = pcall(function()
			return (C_PvP.IsPVPMap and C_PvP.IsPVPMap())
				or (C_PvP.IsInBrawl and C_PvP.IsInBrawl())
		end)
		if okMap and isPvPMap then return true end
	end
	-- Covers world battlefields (Wintergrasp, Tol Barad) while the battle is on.
	if GetMaxBattlefieldID and GetBattlefieldStatus then
		for i = 1, GetMaxBattlefieldID() do
			local okStatus, status = pcall(GetBattlefieldStatus, i)
			if okStatus and status == "active" then return true end
		end
	end
	return false
end

-- true  = a player is among the recorded killing blows,
-- false = recap readable, no player involved,
-- nil   = recap unavailable or hidden.
local function DeathRecapHasPlayer()
	if not (C_DeathRecap and C_DeathRecap.GetRecapEvents) then return nil end
	local ok, found = pcall(function()
		local recap = C_DeathRecap.GetRecapEvents()
		if type(recap) ~= "table" then return nil end
		for _, hit in ipairs(recap) do
			if type(hit) == "table" then
				local guid = hit.sourceGUID
				if guid and type(guid) == "string" and not IsSecret(guid) then
					if guid:find("^Player%-") then return true end
				end
			end
		end
		return false
	end)
	if ok then return found end
	return nil
end

-- "Died to an enemy player, or damaged by one shortly before dying."
-- Returns true when the PvP death event was played.
local function TryPvPDeath()
	if not EventHasSounds("DeathByPlayer") then return false end

	if ns.canCombatLog then
		-- Full knowledge: any enemy player damage inside the window counts.
		local window = math.min(math.max(tonumber(db.pvpDeathWindow) or 15, 2), 60)
		if (GetTime() - lastPlayerDamageAt) <= window then
			return ns.PlayEvent("DeathByPlayer")
		end
		return false
	end

	-- Modern client: battleground deaths are PvP deaths; in the open world the
	-- death recap tells us who (or what) landed the killing blows.
	if IsInActiveBattlefield() then
		Debug("pvp death: active battlefield")
		return ns.PlayEvent("DeathByPlayer")
	end
	local recap = DeathRecapHasPlayer()
	if recap == true then
		Debug("pvp death: death recap shows a player")
		return ns.PlayEvent("DeathByPlayer")
	end
	return false
end

local function ResolveDeath()
	if TryPvPDeath() then return end
	ns.TriggerEvent("Death")
end

-- ---------------------------------------------------------------------------
-- Combat-log detection (Classic family clients)
-- ---------------------------------------------------------------------------

local usesCombatLog = false
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

-- Aura subevents whose 4th suffix argument is the aura type ("BUFF"/"DEBUFF").
local SILENCE_AURA_EVENTS = {
	SPELL_AURA_APPLIED      = true,
	SPELL_AURA_REFRESH      = true,
	SPELL_AURA_APPLIED_DOSE = true,
}

local function ParseCLEU()
	if not CombatLogGetCurrentEventInfo then return end
	local _, subevent, arg3 = CombatLogGetCurrentEventInfo()
	if not subevent then return end
	local isDamage = DAMAGE_SUBEVENTS[subevent]
	local isSilence = SILENCE_AURA_EVENTS[subevent]
	if subevent ~= "PARTY_KILL" and subevent ~= "SPELL_INTERRUPT" and not isDamage and not isSilence then return end

	-- Modern layouts pass hideCaster (a boolean) as the 3rd value; very old
	-- layouts start with the source GUID there instead.
	local prefix = (type(arg3) == "boolean") and 11 or 8
	local srcGUID, srcFlags, dstGUID, dstName, dstFlags
	if prefix == 11 then
		_, _, _, srcGUID, _, srcFlags, _, dstGUID, dstName, dstFlags = CombatLogGetCurrentEventInfo()
	else
		_, _, srcGUID, _, srcFlags, dstGUID, dstName, dstFlags = CombatLogGetCurrentEventInfo()
	end

	if subevent == "SPELL_INTERRUPT" then
		-- Any interrupt spell I (or my pet) landed on someone.
		if IsMyGUID(srcGUID) then
			Debug("interrupt landed (combat log)")
			ns.TriggerEvent("Interrupt")
		end
		return
	end

	if isSilence then
		local spellId, spellName, _, auraType = select(prefix + 1, CombatLogGetCurrentEventInfo())
		if IsMyGUID(srcGUID) then
			-- A debuff I applied: is it one of the interrupt/silence spells?
			if auraType == "DEBUFF" and dstGUID ~= playerGUID then
				if IsInterruptOrSilenceSpell(spellId, spellName) then
					Debug("silence landed (combat log): %s", spellName)
					ns.TriggerEvent("Interrupt")
				end
			end
			-- Procs I applied: on myself (self buffs) or on someone else
			-- (Frostbite's root, weapon enchants).
			if EventHasSounds("Proc") and GetTime() >= readyAt then
				if dstGUID == playerGUID then
					if MatchesProcSpell(spellId, spellName) then OnProcSpell(spellId, spellName) end
				elseif MatchesProcTarget(spellId, spellName) then
					OnProcSpell(spellId, spellName)
				end
			end
		end
		-- A CC effect (fear, root, stun, ...) that landed on me.
		if dstGUID == playerGUID and GetTime() >= readyAt
			and EventHasSounds("CrowdControl") and IsCrowdControlSpell(spellId, spellName) then
			OnCrowdControl(spellId, spellName)
		end
		return
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
		-- The victim died: cancel any pending non-fatal crit sound for it.
		pendingCritByVictim[dstGUID or ""] = nil

		if isPlayer == false then
			ns.TriggerEvent("KillNPC")
			return
		end
		-- Player or unknown: play the player kill (dedupe handles double credit).
		local now = GetTime()
		if (now - lastKillAt) < KILL_DEDUPE then return end
		lastKillAt = now
		ns.PlayEvent("KillPlayer")
		RegisterStreak()
		return
	end

	-- Damage event: remember hits I take from enemy players (PvP death window).
	if dstGUID == playerGUID and srcGUID ~= playerGUID and VictimIsPlayer(srcGUID) then
		lastPlayerDamageAt = GetTime()
	end

	-- Damage event: track my critical hits.
	if not IsMyGUID(srcGUID) then return end
	local critical = select(prefix + isDamage, CombatLogGetCurrentEventInfo())
	if type(critical) == "number" then critical = critical == 1 end
	if not critical then return end

	local victim = dstGUID or ""
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
	Debug("combat text: crit on target (%s)", messageType)
	local ok, isPlayer = pcall(UnitIsPlayer, "target")
	if ok and type(isPlayer) == "boolean" and not IsSecret(isPlayer) then
		if isPlayer then
			ns.TriggerEvent("CritPlayer")
		end
	else
		-- Can't tell what the target is: don't play the crit hit sound.
		Debug("target type hidden (secret)")
	end
end

-- ---------------------------------------------------------------------------
-- Event handling
-- ---------------------------------------------------------------------------

local F = CreateFrame("Frame")
ns.frame = F

-- Interrupt detection state (modern clients).
local pendingInterruptAt = -math.huge -- I cast an interrupt/silence spell just now
local pendingChannelAt = nil         -- my target was channeling when I cast it
local lastInterruptedCastGUID = nil  -- dedupe repeated events for the same cast

local handlers = {}

function handlers.ADDON_LOADED(name)
	if name ~= ADDON_NAME then return end
	MergeDefaults()
	RebuildProcLookups()
	RebuildInterruptLookups()
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
	pendingCritByVictim = {}
	lastPlayerDamageAt = -math.huge
	pendingInterruptAt = -math.huge
	pendingChannelAt = nil
	lastInterruptedCastGUID = nil
	if db then ApplyWatchTarget() end
end

function handlers.PLAYER_DEAD()
	Debug("player died")
	if ns.canCombatLog then
		ResolveDeath()
	else
		-- The death recap needs a moment to arrive on modern clients.
		pcall(function()
			C_Timer.After(DEATH_RECAP_DELAY, ResolveDeath)
		end)
	end
end

function handlers.PARTY_KILL(attackerGUID, targetGUID)
	if ns.canCombatLog then return end -- the combat-log path owns kill detection there
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

-- The added-aura list of a UNIT_AURA update is a plain table on normal
-- clients, but on restricted engines it can be a SECRET value when the
-- update contains restricted data. type() reports the underlying type for
-- secrets, so IsSecret must be checked before the list is usable.
local function AddedAuras(updateInfo)
	local ok, added = pcall(function()
		if type(updateInfo) ~= "table" then return nil end
		local a = updateInfo.addedAuras
		if a and not IsSecret(a) and type(a) == "table" then return a end
		return nil
	end)
	if ok and added then return added end
	return nil
end

function handlers.UNIT_AURA(unit, updateInfo)
	if not db or not db.enabled then return end

	if unit == "player" then
		-- Procs: tracked buffs applied to me. Crowd control: fears, roots,
		-- stuns, polymorphs etc. applied to me.
		local checkProc = EventHasSounds("Proc")
		local checkCC = EventHasSounds("CrowdControl")
		if not (checkProc or checkCC) then return end
		-- Ignore auras already present at login (passives and the like);
		-- only newly gained auras count.
		if GetTime() < readyAt then return end

		-- New-or-refreshed auras are handed to us directly on modern clients;
		-- when the client hides them, fall back to a full aura scan.
		local added = AddedAuras(updateInfo)
		if added then
			for _, aura in ipairs(added) do
				local ok, err = pcall(function()
					-- Check IsSecret BEFORE any truthiness test: boolean secrets
					-- may not be tested directly.
					if IsSecret(aura.isHarmful) then return end
					if aura.isHarmful then
						if checkCC and IsCrowdControlSpell(aura.spellId, aura.name, aura.mechanics) then
							OnCrowdControl(aura.spellId, aura.name)
						end
					elseif checkProc and MatchesProcSpell(aura.spellId, aura.name) then
						OnProcSpell(aura.spellId, aura.name)
					end
				end)
				if not ok then Debug("aura error: %s", err) end
			end
		else
			ScanAuras()
		end
		return
	end

	if unit == "target" then
		-- Silences I applied to my target, plus target-side procs
		-- (modern clients without a combat log).
		if ns.canCombatLog or (not EventHasSounds("Interrupt") and not EventHasSounds("Proc")) then return end
		local added = AddedAuras(updateInfo)
		if not added then return end
		for _, aura in ipairs(added) do
			local ok, err = pcall(function()
				if IsSecret(aura.isHarmful) then return end
				local source = aura.sourceUnit
				local mine = source and not IsSecret(source)
					and (source == "player" or source == "pet" or source == "vehicle")
				if not mine and aura.sourceGUID then
					mine = IsMyGUID(aura.sourceGUID)
				end
				if mine then
					if aura.isHarmful and EventHasSounds("Interrupt")
						and IsInterruptOrSilenceSpell(aura.spellId, aura.name) then
						Debug("silence landed: %s", aura.name)
						ns.TriggerEvent("Interrupt")
					end
					-- Procs that land on the target: harmful ones (Frostbite's
					-- root, CC procs, weapon enchant procs) and helpful ones.
					if EventHasSounds("Proc") and GetTime() >= readyAt
						and MatchesProcTarget(aura.spellId, aura.name) then
						OnProcSpell(aura.spellId, aura.name)
					end
				end
			end)
			if not ok then Debug("target aura error: %s", err) end
		end
		return
	end

	-- Friendly units: helpful procs I applied to them (helpful target procs
	-- land on the spell's recipient, who is usually not the current target).
	-- (Combat-log clients handle this in ParseCLEU.)
	if ns.canCombatLog then return end
	if not EventHasSounds("Proc") then return end
	if GetTime() < readyAt then return end
	local added = AddedAuras(updateInfo)
	if not added then return end
	-- Only friendly unit IDs can carry helpful auras from me; skip enemy
	-- NPCs and world objects before doing any work.
	if unit ~= "pet" and unit ~= "vehicle" and unit ~= "focus"
		and not unit:find("^party%d+$", 1) and not unit:find("^raid%d+$", 1)
		and not unit:find("^friend%d+$", 1) then return end
	for _, aura in ipairs(added) do
		local ok, err = pcall(function()
			if IsSecret(aura.isHarmful) then return end
			if aura.isHarmful then return end
			local source = aura.sourceUnit
			local mine = source and not IsSecret(source)
				and (source == "player" or source == "pet" or source == "vehicle")
			if not mine and aura.sourceGUID then
				mine = IsMyGUID(aura.sourceGUID)
			end
			if mine and MatchesProcTarget(aura.spellId, aura.name) then
				OnProcSpell(aura.spellId, aura.name)
			end
		end)
		if not ok then Debug("aura error: %s", err) end
	end
end

-- My interrupt/silence spell was cast successfully (modern clients).
function handlers.UNIT_SPELLCAST_SUCCEEDED(unit, castGUID, spellID)
	if ns.canCombatLog or (unit ~= "player" and unit ~= "pet") then return end
	if not EventHasSounds("Interrupt") then return end
	if not spellID or IsSecret(spellID) then return end
	if not IsInterruptOrSilenceSpell(spellID) then return end
	pendingInterruptAt = GetTime()
	-- If the target is channeling right now, an interrupt would stop it.
	local ok, channel = pcall(UnitChannelInfo, "target")
	pendingChannelAt = (ok and channel) and pendingInterruptAt or nil
	Debug("interrupt spell cast (%s)", spellID)
end

-- A target's cast got interrupted; the modern client reports who did it.
function handlers.UNIT_SPELLCAST_INTERRUPTED(unit, castGUID, spellID, interruptedBy)
	if ns.canCombatLog or not EventHasSounds("Interrupt") then return end
	if castGUID and not IsSecret(castGUID) then
		if castGUID == lastInterruptedCastGUID then return end
		lastInterruptedCastGUID = castGUID
	end

	local mine
	if interruptedBy and not IsSecret(interruptedBy) then
		mine = IsMyGUID(interruptedBy)
	else
		-- Attribution hidden: fall back to "I just cast an interrupt spell".
		mine = (GetTime() - pendingInterruptAt) <= INTERRUPT_WINDOW
	end
	if mine then
		Debug("interrupt landed (interruptedBy: %s)", SafeTostring(interruptedBy))
		ns.TriggerEvent("Interrupt")
	end
end

-- Kicking a channeled spell stops the channel; correlate with my recent cast.
function handlers.UNIT_SPELLCAST_CHANNEL_STOPPED(unit)
	if ns.canCombatLog or not EventHasSounds("Interrupt") then return end
	if not pendingChannelAt then return end
	if (GetTime() - pendingInterruptAt) <= INTERRUPT_WINDOW then
		Debug("interrupt landed (channel stopped)")
		ns.TriggerEvent("Interrupt")
	end
	pendingChannelAt = nil
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

-- Auras: procs on the player, silences and target-side procs on the target,
-- and friendly procs (like the Priest's Inspiration) on party, raid, focus
-- and friend units. A global registration covers all of them; clients that
-- only offer per-unit registration get the player and the target.
if not pcall(F.RegisterEvent, F, "UNIT_AURA") then
	TryRegisterUnitEvent("UNIT_AURA", "player")
	TryRegisterUnitEvent("UNIT_AURA", "target")
end

-- Client-dependent signals. On the modern engine the combat log is forbidden
-- to addons (registering it triggers the protected-action popup) but Blizzard's
-- dedicated PARTY_KILL event is available; Classic-family clients are the
-- other way around.
ns.canPartyKill = false
usesCombatLog = false
if IS_MODERN then
	ns.canPartyKill = TryRegister("PARTY_KILL")
else
	-- Never attempt the combat log registration on a restricted engine, even
	-- if the interface number was not what we expected.
	if not HAS_RESTRICTED_ENGINE then
		usesCombatLog = TryRegister("COMBAT_LOG_EVENT_UNFILTERED")
	end
end
ns.canCombatLog = usesCombatLog
ns.canHKCredit = TryRegister("PLAYER_PVP_KILLS_CHANGED")

-- Spellcast signals for interrupt/silence detection (modern clients; the
-- classic path uses the combat log registered above).
ns.canCastSucceeded = not usesCombatLog and TryRegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "pet") or false
ns.canCastEvents = not usesCombatLog and TryRegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "target", "focus") or false
if not usesCombatLog then
	TryRegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOPPED", "target")
end

-- ---------------------------------------------------------------------------
-- Public helpers used by the options panel and slash commands
-- ---------------------------------------------------------------------------

local function KillSoundsAvailable(eventKey)
	if eventKey == "KillPlayer" or eventKey == "KillNPC" then
		return ns.canPartyKill or ns.canCombatLog or ns.canHKCredit
	elseif eventKey == "CritPlayer" then
		if ns.canCombatLog then return true, "combat log" end
		if db and db.watchTargetText then return true, "watch target (experimental)" end
		return false, "needs 'Watch my target' or a combat-log client"
	elseif eventKey == "Death" or eventKey == "CombatIn" or eventKey == "CombatOut" then
		return true
	elseif eventKey == "DeathByPlayer" then
		if ns.canCombatLog then return true, "any enemy player damage in the window counts" end
		return true, "death recap and active battlegrounds"
	elseif eventKey == "Interrupt" then
		if ns.canCombatLog then return true, "combat log (all interrupt spells)" end
		if ns.canCastEvents then return true, "your target's interrupted casts and the silences you land" end
		return false, "no interrupt signal on this client"
	elseif eventKey == "Proc" then
		return true
	elseif eventKey == "CrowdControl" then
		return true, "aura data (CC effect type and name)"
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
	local ok, how = KillSoundsAvailable("CritPlayer")
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
	-- The master switch drives every event's enabled state as well.
	if type(db.events) == "table" then
		for _, event in ipairs(ns.EVENTS) do
			local ev = db.events[event.key]
			if type(ev) == "table" then ev.enabled = db.enabled end
		end
	end
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
