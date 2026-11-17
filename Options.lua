-- ---------------------------------------------------------------------------
-- TagariaSoundFX options panel
--
-- One settings page: general options on top, then an event picker with its
-- sound list. Sounds are added by file name (WoW addons cannot list folder
-- contents), with Test and Remove buttons for each entry.
-- ---------------------------------------------------------------------------

local ADDON_NAME, ns = ...

local controls = {}
local panel, category
local selectedEventKey = "KillPlayer"

local function AddControl(control)
	controls[#controls + 1] = control
	return control
end

local function ShowTooltip(owner, title, text)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(title, 1, 1, 1)
	GameTooltip:AddLine(text, nil, nil, nil, true)
	GameTooltip:Show()
end

-- ---------------------------------------------------------------------------
-- Small control factory helpers
-- ---------------------------------------------------------------------------

local function CreateCheckbox(parent, label, tooltip, onClick)
	local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check:SetSize(26, 26)

	local text = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	text:SetPoint("LEFT", check, "RIGHT", 4, 1)

	check:SetScript("OnClick", function(self)
		onClick(self:GetChecked() and true or false)
	end)
	check:SetScript("OnEnter", function(self)
		local custom = self.GetTooltip and self:GetTooltip()
		ShowTooltip(self, label, custom or tooltip or label)
	end)
	check:SetScript("OnLeave", GameTooltip_Hide)

	function check:Refresh()
		text:SetText(label)
		self:SetHitRectInsets(0, -text:GetStringWidth() - 8, 0, 0)
	end
	return check
end

local function CreateSmallButton(parent, label, width)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width or 70, 22)
	button:SetText(label)
	return button
end

-- "[label] [<] value [>]" control anchored below `anchor`.
local function CreateStepper(parent, anchor, label, getText, onPrev, onNext)
	local labelFS = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	labelFS:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -16)
	labelFS:SetText(label)

	local prev = CreateSmallButton(parent, "<", 24)
	prev:SetPoint("TOPLEFT", labelFS, "BOTTOMLEFT", 0, -6)
	prev:SetScript("OnClick", onPrev)

	local value = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	value:SetPoint("LEFT", prev, "RIGHT", 6, 0)
	value:SetWidth(50)

	local nextBtn = CreateSmallButton(parent, ">", 24)
	nextBtn:SetPoint("LEFT", value, "RIGHT", 6, 0)
	nextBtn:SetScript("OnClick", onNext)

	function prev:Refresh()
		value:SetText(getText())
	end
	return prev
end

local function CreateEditBox(parent, width)
	local ok, box = pcall(CreateFrame, "EditBox", nil, parent, "InputBoxTemplate")
	if not ok or not box then
		box = CreateFrame("EditBox", nil, parent)
		box:SetFontObject("GameFontHighlight")
	end
	box:SetSize(width or 240, 20)
	box:SetAutoFocus(false)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	return box
end

-- Dropdown: modern menu system (WowStyle1DropdownTemplate) with the old
-- UIDropDownMenuTemplate as a fallback for older clients.
-- getEntries() -> { {value=..., text=...}, ... }
local function CreateDropdown(parent, getEntries, isSelected, onSelect, getText)
	local ok, dropdown = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	if ok and dropdown and dropdown.SetupMenu then
		dropdown:SetWidth(240)
		dropdown:SetupMenu(function(_, root)
			for _, entry in ipairs(getEntries()) do
				root:CreateRadio(entry.text, isSelected, onSelect, entry.value)
			end
		end)
		function dropdown:Refresh()
			if dropdown.GenerateMenu then dropdown:GenerateMenu() end
		end
		return dropdown
	end

	dropdown = CreateFrame("Frame", "TagariaSoundFXDropdown", parent, "UIDropDownMenuTemplate")
	pcall(UIDropDownMenu_SetWidth, dropdown, 200)
	UIDropDownMenu_Initialize(dropdown, function()
		for _, entry in ipairs(getEntries()) do
			local info = UIDropDownMenu_CreateInfo()
			info.text = entry.text
			info.arg1 = entry.value
			info.checked = isSelected(entry.value) or nil
			info.func = function(_, value) onSelect(value) end
			UIDropDownMenu_AddButton(info)
		end
	end)
	function dropdown:Refresh()
		pcall(UIDropDownMenu_SetText, dropdown, getText())
	end
	return dropdown
end

-- ---------------------------------------------------------------------------
-- Sound list
-- ---------------------------------------------------------------------------

local ROW_HEIGHT = 24
local MAX_SOUNDS = 40

local soundScroll, soundContent
local soundRows = {}

local function LayoutSoundRows()
	local sounds = ns.db.events[selectedEventKey].sounds
	for i, row in ipairs(soundRows) do
		if i <= #sounds then
			row.text:SetText(sounds[i])
			row.index = i
			row:Show()
		else
			row:Hide()
		end
	end
	soundContent:SetHeight(math.max(#sounds * ROW_HEIGHT, 2))
end

local function CreateSoundRows(parent)
	soundScroll = CreateFrame("ScrollFrame", "TagariaSoundFXSoundScroll", parent, "UIPanelScrollFrameTemplate")
	soundScroll:SetSize(560, 7 * ROW_HEIGHT)

	soundContent = CreateFrame("Frame", nil, soundScroll)
	soundContent:SetWidth(540)
	soundScroll:SetScrollChild(soundContent)

	for i = 1, MAX_SOUNDS do
		local row = CreateFrame("Frame", nil, soundContent)
		row:SetWidth(540)
		row:SetPoint("TOPLEFT", soundContent, "TOPLEFT", 0, -((i - 1) * ROW_HEIGHT))

		local text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		text:SetPoint("LEFT", 6, 0)
		text:SetWidth(400)
		text:SetJustifyH("LEFT")

		local test = CreateSmallButton(row, "Test", 54)
		test:SetPoint("RIGHT", -64, 0)
		test:SetScript("OnClick", function()
			if row.index then
				ns.PlaySoundPath(ns.ResolveSoundPath(ns.db.events[selectedEventKey].sounds[row.index]))
			end
		end)

		local remove = CreateSmallButton(row, "X", 24)
		remove:SetPoint("RIGHT", -2, 0)
		remove:SetScript("OnClick", function()
			if row.index then
				table.remove(ns.db.events[selectedEventKey].sounds, row.index)
				LayoutSoundRows()
			end
		end)

		row.text = text
		row:Hide()
		soundRows[i] = row
	end
end

-- ---------------------------------------------------------------------------
-- Proc spell list
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Per-event spell lists (shown for events that use one)
-- ---------------------------------------------------------------------------

local SPELL_LIST_META = {
	Proc = {
		dbKey    = "procSpells",
		header   = "Proc spells (buffs on you that trigger the sound)",
		addLabel = "Spell name (e.g. Crusader) or spell ID, then press Enter",
		note     = "Procs are read from your own auras. In content where the client hides aura data, some procs may not be detected.",
	},
	Interrupt = {
		dbKey    = "interruptSpells",
		header   = "Interrupt / silence spells (extra entries beyond the built-ins)",
		addLabel = "Spell name (e.g. Silence) or spell ID, then press Enter",
		note     = "Built-in: Kick, Pummel, Shield Bash, Counterspell, Earth Shock, Spell Lock, Silence (all ranks). " ..
			"Interrupts are detected directly; silences are detected when you land them on your target.",
	},
}

local function CurrentSpellList()
	local meta = SPELL_LIST_META[selectedEventKey]
	if not meta then return nil, nil end
	return ns.db[meta.dbKey], meta
end

local procScroll, procContent
local procRows = {}

local function SpellDisplay(entry)
	local id = tonumber(entry)
	if id then
		local name
		if C_Spell and C_Spell.GetSpellName then
			local ok, n = pcall(C_Spell.GetSpellName, id)
			if ok and n then name = n end
		elseif GetSpellInfo then
			local ok, n = pcall(GetSpellInfo, id)
			if ok and n then name = n end
		end
		if name then return ("%d - %s"):format(id, name) end
		return tostring(id)
	end
	return tostring(entry)
end

local function LayoutProcRows()
	local spells = select(1, CurrentSpellList()) or {}
	for i, row in ipairs(procRows) do
		if i <= #spells then
			row.text:SetText(SpellDisplay(spells[i]))
			row.index = i
			row:Show()
		else
			row:Hide()
		end
	end
	procContent:SetHeight(math.max(#spells * ROW_HEIGHT, 2))
end

local function CreateProcRows(parent)
	procScroll = CreateFrame("ScrollFrame", "TagariaSoundFXProcScroll", parent, "UIPanelScrollFrameTemplate")
	procScroll:SetSize(560, 4 * ROW_HEIGHT)

	procContent = CreateFrame("Frame", nil, procScroll)
	procContent:SetWidth(540)
	procScroll:SetScrollChild(procContent)

	for i = 1, 20 do
		local row = CreateFrame("Frame", nil, procContent)
		row:SetWidth(540)
		row:SetPoint("TOPLEFT", procContent, "TOPLEFT", 0, -((i - 1) * ROW_HEIGHT))

		local text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		text:SetPoint("LEFT", 6, 0)
		text:SetWidth(500)
		text:SetJustifyH("LEFT")

		local remove = CreateSmallButton(row, "X", 24)
		remove:SetPoint("RIGHT", -2, 0)
		remove:SetScript("OnClick", function()
			local spells = select(1, CurrentSpellList())
			if row.index and spells then
				table.remove(spells, row.index)
				ns.RebuildProcLookups()
				ns.RebuildInterruptLookups()
				LayoutProcRows()
			end
		end)

		row.text = text
		row:Hide()
		procRows[i] = row
	end
end

-- ---------------------------------------------------------------------------
-- Add entries
-- ---------------------------------------------------------------------------

local function AddSoundEntry(name)
	local sounds = ns.db.events[selectedEventKey].sounds
	if #sounds >= MAX_SOUNDS then
		ns.Print("that event already has the maximum of " .. MAX_SOUNDS .. " sounds.")
		return false
	end
	name = strtrim(tostring(name or ""))
	if name == "" then return false end

	local lower = name:lower()
	if not (lower:find("%.mp3$") or lower:find("%.wav$") or lower:find("%.ogg$")) then
		ns.Print("|cffff8040note:|r '" .. name .. "' does not end in .mp3, .wav or .ogg. " ..
			"Make sure the extension matches the real file.")
	end
	sounds[#sounds + 1] = name
	LayoutSoundRows()
	-- Immediate feedback: play it once.
	ns.PlaySoundPath(ns.ResolveSoundPath(name))
	if ns.RefreshOptions then ns.RefreshOptions() end
	return true
end

local function AddProcEntry(value)
	local spells = select(1, CurrentSpellList())
	if not spells then return false end
	if #spells >= 20 then
		ns.Print("that spell list is full (20 entries).")
		return false
	end
	value = strtrim(tostring(value or ""))
	if value == "" then return false end
	spells[#spells + 1] = tonumber(value) or value
	ns.RebuildProcLookups()
	ns.RebuildInterruptLookups()
	LayoutProcRows()
	if ns.RefreshOptions then ns.RefreshOptions() end
	return true
end

-- ---------------------------------------------------------------------------
-- Panel
-- ---------------------------------------------------------------------------

local function EventEntries()
	local entries = {}
	for _, event in ipairs(ns.EVENTS) do
		local ev = ns.db.events[event.key]
		local count = ev.sounds and #ev.sounds or 0
		entries[#entries + 1] = {
			value = event.key,
			text = ("%s (%d sound%s)"):format(event.label, count, count == 1 and "" or "s"),
		}
	end
	return entries
end

local function SelectedEvent()
	return ns.EVENT_BY_KEY[selectedEventKey]
end

local function BuildPanel()
	panel = CreateFrame("Frame")
	panel.name = "Tagaria SoundFX"

	-- Header --------------------------------------------------------------

	local icon = panel:CreateTexture(nil, "ARTWORK")
	icon:SetSize(36, 36)
	icon:SetPoint("TOPLEFT", 16, -16)
	icon:SetTexture("Interface\\Icons\\INV_Misc_Drum_01")

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("LEFT", icon, "RIGHT", 10, 0)
	title:SetText("|cffff8800Tagaria|r|cffffd100Sound|r|cffff8800FX|r")

	local version = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	version:SetPoint("LEFT", title, "RIGHT", 8, 0)
	version:SetText("v" .. ns.VERSION)

	local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	subtitle:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -8)
	subtitle:SetPoint("RIGHT", panel, "RIGHT", -24, 0)
	subtitle:SetJustifyH("LEFT")
	subtitle:SetText("Drop your sound files into Interface\\AddOns\\TagariaSoundFX\\sounds\\, then add their names to the events below. One sound per event always plays that sound; several sounds are picked at random.")

	-- General -------------------------------------------------------------

	local general = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	general:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -14)
	general:SetText("General")

	local enableCheck = CreateCheckbox(panel, "Enabled", "Master switch for all sounds.", function(value)
		ns.SetEnabled(value)
	end)
	enableCheck:SetPoint("TOPLEFT", general, "BOTTOMLEFT", -2, -6)
	function enableCheck:Refresh()
		self:SetChecked(ns.db.enabled)
	end
	AddControl(enableCheck)

	local onlyMineCheck = CreateCheckbox(panel, "Only my killing blows",
		"In a group, only play kill sounds for players that you or your pet finished off yourself. " ..
		"When the client cannot tell who struck the final blow, the kill still counts.",
		function(value)
			ns.db.onlyMyKills = value
		end)
	onlyMineCheck:SetPoint("TOPLEFT", enableCheck, "BOTTOMLEFT", 0, -2)
	function onlyMineCheck:Refresh()
		self:SetChecked(ns.db.onlyMyKills)
	end
	AddControl(onlyMineCheck)

	local watchCheck = CreateCheckbox(panel, "Watch my target's combat text",
		"EXPERIMENTAL: this client does not give addons your outgoing critical hits. " ..
		"With this option the addon tells the game to watch your TARGET for floating combat text; " ..
		"when your target takes a critical hit - usually from you - Critical Hit and Critical Killing Blow " ..
		"sounds can play. Your own floating combat text then shows your target's damage taken instead, " ..
		"so leave this off if you use the built-in floating combat text.",
		function(value)
			ns.db.watchTargetText = value
			ns.ApplyWatchTarget()
		end)
	watchCheck:SetPoint("TOPLEFT", onlyMineCheck, "BOTTOMLEFT", 0, -2)
	function watchCheck:Refresh()
		self:SetChecked(ns.db.watchTargetText)
	end
	AddControl(watchCheck)

	local channelLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	channelLabel:SetPoint("TOPLEFT", watchCheck, "BOTTOMLEFT", 4, -16)
	channelLabel:SetText("Sound channel")

	local channelDropdown = CreateDropdown(panel,
		function()
			return {
				{ value = "Master", text = "Master volume (plays even with SFX muted)" },
				{ value = "SFX",    text = "Sound Effects volume" },
			}
		end,
		function(value) return ns.db.channel == value end,
		function(value)
			ns.db.channel = value
			if ns.RefreshOptions then ns.RefreshOptions() end
		end,
		function()
			return (ns.db.channel == "SFX") and "Sound Effects volume" or "Master volume"
		end)
	channelDropdown:SetPoint("LEFT", channelLabel, "RIGHT", 24, -1)
	AddControl(channelDropdown)

	local streakStepper = CreateStepper(panel, channelLabel, "Kill streak window (Double Kill, Triple Kill...)",
		function() return tostring(ns.db.streakWindow) .. "s" end,
		function() ns.db.streakWindow = math.max(2, (tonumber(ns.db.streakWindow) or 8) - 1) end,
		function() ns.db.streakWindow = math.min(30, (tonumber(ns.db.streakWindow) or 8) + 1) end)
	AddControl(streakStepper)

	local pvpDeathStepper = CreateStepper(panel, streakStepper, "PvP death window (player damage before dying counts)",
		function() return tostring(ns.db.pvpDeathWindow) .. "s" end,
		function() ns.db.pvpDeathWindow = math.max(2, (tonumber(ns.db.pvpDeathWindow) or 15) - 1) end,
		function() ns.db.pvpDeathWindow = math.min(60, (tonumber(ns.db.pvpDeathWindow) or 15) + 1) end)
	AddControl(pvpDeathStepper)

	-- Event setup -----------------------------------------------------------

	local setup = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	setup:SetPoint("TOPLEFT", pvpDeathStepper, "BOTTOMLEFT", -2, -10)
	setup:SetText("Event setup")

	local eventLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	eventLabel:SetPoint("TOPLEFT", setup, "BOTTOMLEFT", 0, -10)
	eventLabel:SetText("Event")

	local eventDropdown = CreateDropdown(panel, EventEntries,
		function(value) return selectedEventKey == value end,
		function(value)
			selectedEventKey = value
			if ns.RefreshOptions then ns.RefreshOptions() end
		end,
		function()
			local event = SelectedEvent()
			local ev = ns.db.events[selectedEventKey]
			return ("%s (%d sound%s)"):format(event.label, #ev.sounds, #ev.sounds == 1 and "" or "s")
		end)
	eventDropdown:SetPoint("LEFT", eventLabel, "RIGHT", 24, -1)
	AddControl(eventDropdown)

	local eventEnableCheck = CreateCheckbox(panel, "Event enabled", nil, function(value)
		ns.db.events[selectedEventKey].enabled = value
	end)
	eventEnableCheck:SetPoint("TOPLEFT", eventDropdown, "BOTTOMLEFT", -2, -4)
	function eventEnableCheck:Refresh()
		self:SetChecked(ns.db.events[selectedEventKey].enabled)
	end
	AddControl(eventEnableCheck)

	local eventStatusLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	eventStatusLabel:SetPoint("LEFT", eventEnableCheck, "RIGHT", 6, 1)

	-- Sound list -------------------------------------------------------------

	local soundHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	soundHeader:SetPoint("TOPLEFT", eventEnableCheck, "BOTTOMLEFT", 0, -12)

	CreateSoundRows(panel)
	soundScroll:SetPoint("TOPLEFT", soundHeader, "BOTTOMLEFT", 0, -6)

	local addBox = CreateEditBox(panel, 240)
	addBox:SetPoint("TOPLEFT", soundScroll, "BOTTOMLEFT", 6, -12)
	addBox:SetScript("OnEnterPressed", function(self)
		if AddSoundEntry(self:GetText()) then
			self:SetText("")
			self:ClearFocus()
		end
	end)

	local addLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	addLabel:SetPoint("BOTTOM", addBox, "TOP", 2, 3)
	addLabel:SetText("File name, e.g. kill1.mp3 - files live in the addon's sounds folder")

	local addBtn = CreateSmallButton(panel, "Add", 60)
	addBtn:SetPoint("LEFT", addBox, "RIGHT", 6, 0)
	addBtn:SetScript("OnClick", function()
		if AddSoundEntry(addBox:GetText()) then addBox:SetText("") end
	end)

	local testEventBtn = CreateSmallButton(panel, "Test", 60)
	testEventBtn:SetPoint("LEFT", addBtn, "RIGHT", 6, 0)
	testEventBtn:SetScript("OnClick", function()
		ns.PlayEvent(selectedEventKey)
	end)

	-- Footer (client capabilities) -------------------------------------------

	local footerLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	footerLabel:SetPoint("TOPLEFT", addBox, "BOTTOMLEFT", -6, -16)
	footerLabel:SetPoint("RIGHT", panel, "RIGHT", -24, 0)
	footerLabel:SetJustifyH("LEFT")

	-- Proc spells (shown only for the Proc event) ------------------------------

	local procHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	procHeader:SetPoint("TOPLEFT", footerLabel, "BOTTOMLEFT", 0, -22)
	procHeader:SetText("Proc spells (buffs on you that trigger the sound)")

	CreateProcRows(panel)
	procScroll:SetPoint("TOPLEFT", procHeader, "BOTTOMLEFT", 0, -6)

	local procAddBox = CreateEditBox(panel, 240)
	procAddBox:SetPoint("TOPLEFT", procScroll, "BOTTOMLEFT", 6, -12)
	procAddBox:SetScript("OnEnterPressed", function(self)
		if AddProcEntry(self:GetText()) then
			self:SetText("")
			self:ClearFocus()
		end
	end)

	local procAddLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	procAddLabel:SetPoint("BOTTOM", procAddBox, "TOP", 2, 3)
	procAddLabel:SetText("Spell name (e.g. Crusader) or spell ID, then press Enter")

	local procAddBtn = CreateSmallButton(panel, "Add", 60)
	procAddBtn:SetPoint("LEFT", procAddBox, "RIGHT", 6, 0)
	procAddBtn:SetScript("OnClick", function()
		if AddProcEntry(procAddBox:GetText()) then procAddBox:SetText("") end
	end)

	local procStatusLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	procStatusLabel:SetPoint("TOPLEFT", procAddBox, "BOTTOMLEFT", 0, -8)
	procStatusLabel:SetText("Procs are read from your own auras. In content where the client hides aura data, some procs may not be detected.")

	-- Refresh ------------------------------------------------------------------

	local function RefreshEventSection()
		local ev = ns.db.events[selectedEventKey]
		eventEnableCheck:SetChecked(ev.enabled)

		local available, how = ns.KillSoundsAvailable(selectedEventKey)
		if available then
			eventStatusLabel:SetText("Detectable on this client" .. (how and (": " .. how) or "") .. ".")
			eventStatusLabel:SetTextColor(0.4, 0.9, 0.4)
		else
			eventStatusLabel:SetText("Not detectable right now: " .. how)
			eventStatusLabel:SetTextColor(1.0, 0.5, 0.3)
		end

		local count = #ev.sounds
		soundHeader:SetText(("Sounds for %s (%d - one is picked at random)"):format(SelectedEvent().label, count))
		if count > 0 then testEventBtn:Enable() else testEventBtn:Disable() end

		local spellMeta = SPELL_LIST_META[selectedEventKey]
		local hasSpellList = (spellMeta ~= nil)
		procHeader:SetShown(hasSpellList)
		procScroll:SetShown(hasSpellList)
		procAddLabel:SetShown(hasSpellList)
		procAddBox:SetShown(hasSpellList)
		procAddBtn:SetShown(hasSpellList)
		procStatusLabel:SetShown(hasSpellList)
		if spellMeta then
			procHeader:SetText(spellMeta.header)
			procAddLabel:SetText(spellMeta.addLabel)
			procStatusLabel:SetText(spellMeta.note)
			LayoutProcRows()
		end

		LayoutSoundRows()
	end

	local function RefreshFooter()
		local lines = {}
		if ns.IS_MODERN then
			lines[#lines + 1] = "Client: modern engine (interface " .. ns.INTERFACE .. ")."
			lines[#lines + 1] = "No combat log for addons: killing blows come from Blizzard's PARTY_KILL event and honorable-kill credit."
			if ns.db.watchTargetText then
				lines[#lines + 1] = "Crit detection: watching your target's combat text (experimental)."
			else
				lines[#lines + 1] = "Crit sounds need 'Watch my target's combat text' (experimental)."
			end
		else
			lines[#lines + 1] = "Client: classic engine (interface " .. ns.INTERFACE .. ") - combat log available: full kill and crit detection."
		end
		footerLabel:SetText(table.concat(lines, "\n"))
	end

	function ns.RefreshOptions()
		if not panel then return end
		for _, control in ipairs(controls) do
			if control.Refresh then control:Refresh() end
		end
		RefreshEventSection()
		RefreshFooter()
	end

	panel:SetScript("OnShow", ns.RefreshOptions)
end

function ns.CreateOptions()
	BuildPanel()
	if Settings and Settings.RegisterCanvasLayoutCategory then
		category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
		if Settings.RegisterAddOnCategory then
			Settings.RegisterAddOnCategory(category)
		end
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(panel)
	end
end

function ns.OpenOptions()
	if category and Settings.OpenToCategory then
		Settings.OpenToCategory(category:GetID())
	elseif InterfaceOptionsFrame_OpenToCategory then
		-- Called twice: the first call may only open the frame on older clients.
		InterfaceOptionsFrame_OpenToCategory(panel)
		InterfaceOptionsFrame_OpenToCategory(panel)
	end
end

-- ---------------------------------------------------------------------------
-- Addon compartment (the addon button near the minimap)
-- ---------------------------------------------------------------------------

function TagariaSoundFX_OnCompartmentClick(_, button)
	if button == "RightButton" then
		ns.SetEnabled(not ns.db.enabled)
	else
		if ns.OpenOptions then ns.OpenOptions() end
	end
end

function TagariaSoundFX_OnCompartmentEnter(_, menuButton)
	GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
	GameTooltip:AddLine("|cffff8800Tagaria|r|cffffd100Sound|r|cffff8800FX|r")
	GameTooltip:AddLine(ns.db.enabled and "Enabled" or "Disabled", 1, 1, 1)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Left-click: configure sounds")
	GameTooltip:AddLine("Right-click: enable / disable")
	GameTooltip:Show()
end

function TagariaSoundFX_OnCompartmentLeave()
	GameTooltip:Hide()
end
