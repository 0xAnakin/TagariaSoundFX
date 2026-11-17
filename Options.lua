-- ---------------------------------------------------------------------------
-- TagariaSoundFX options panel
--
-- Modern layout: event list on the left, event details on the right, general
-- settings in a card below. Built only from client-safe widgets (BackdropTemplate
-- cards, WowCheckButtonTemplate checkboxes with fallbacks, WowStyle1 dropdowns).
-- ---------------------------------------------------------------------------

local ADDON_NAME, ns = ...

local controls = {}
local panel, category
local selectedEventKey = "KillPlayer"

-- ---------------------------------------------------------------------------
-- Palette
-- ---------------------------------------------------------------------------

local C = {
	card     = { 0.055, 0.058, 0.065, 0.92 },
	edge     = { 0.20, 0.20, 0.24, 1.0 },
	cardSoft = { 0.085, 0.085, 0.10, 0.90 },
	hover    = { 0.14, 0.14, 0.17, 0.90 },
	gold     = { 0.95, 0.61, 0.12, 1.0 },
	selBg    = { 0.18, 0.12, 0.03, 0.95 },
	textDim  = { 0.55, 0.55, 0.58, 1.0 },
	textMid  = { 0.78, 0.78, 0.82, 1.0 },
	green    = { 0.30, 0.85, 0.35, 1.0 },
	red      = { 0.95, 0.30, 0.25, 1.0 },
	orange   = { 0.95, 0.70, 0.25, 1.0 },
}

local function AddControl(c)
	controls[#controls + 1] = c
	return c
end

-- ---------------------------------------------------------------------------
-- Widget factory helpers
-- ---------------------------------------------------------------------------

-- Flat, rounded-feeling dark card with a subtle border.
local function CreateCard(parent, width, height)
	local ok, card = pcall(CreateFrame, "Frame", nil, parent, "BackdropTemplate")
	if not ok or not card then
		card = CreateFrame("Frame", nil, parent)
	end
	card:SetSize(width or 400, height or 100)
	if card.SetBackdrop then
		card:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8x8",
			edgeFile = "Interface\\Buttons\\WHITE8x8",
			edgeSize = 1,
			tile = false,
		})
		card:SetBackdropColor(unpack(C.card))
		card:SetBackdropBorderColor(unpack(C.edge))
	end
	return card
end

local function CreateModernCheckbox(parent, label, tooltip, onClick, labelSide)
	local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check:SetSize(24, 24)
	local text = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	if labelSide == "left" then
		text:SetPoint("RIGHT", check, "LEFT", -6, 0)
		text:SetJustifyH("RIGHT")
	else
		text:SetPoint("LEFT", check, "RIGHT", 6, 0)
		text:SetJustifyH("LEFT")
	end

	check:SetScript("OnClick", function(self)
		onClick(self:GetChecked() and true or false)
	end)
	if tooltip then
		check:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(label, 1, 1, 1)
			GameTooltip:AddLine(tooltip, nil, nil, nil, true)
			GameTooltip:Show()
		end)
		check:SetScript("OnLeave", GameTooltip_Hide)
	end
	check.label = text
	check.onGet = isChecked
	function check:Refresh()
		self.label:SetText(label)
		if self.onGet then self:SetChecked(self.onGet()) end
	end
	return check
end

local function CreateModernButton(parent, label, width, height)
	local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	btn:SetSize(width or 80, height or 22)
	btn:SetText(label)
	return btn
end

local function CreateEditBox(parent, width)
	local ok, box = pcall(CreateFrame, "EditBox", nil, parent, "InputBoxTemplate")
	if not ok or not box then
		box = CreateFrame("EditBox", nil, parent)
		box:SetFontObject("GameFontHighlight")
	end
	box:SetSize(width or 220, 20)
	box:SetAutoFocus(false)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	return box
end

-- Dropdown: modern menu system with the old template as a fallback.
local function CreateDropdown(parent, getEntries, isSelected, onSelect, getText, width)
	local ok, dropdown = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	if ok and dropdown and dropdown.SetupMenu then
		dropdown:SetWidth(width or 200)
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
	pcall(UIDropDownMenu_SetWidth, dropdown, width or 180)
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

-- "label value  [<] [>]"
local function CreateStepper(parent, label, getText, onPrev, onNext, textWidth, tip)
	local frame = CreateFrame("Frame", nil, parent)
	local tw = textWidth or 60
	frame:SetSize(tw + 58, 20)

	local text = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	text:SetPoint("LEFT", 0, 0)
	text:SetWidth(tw)
	text:SetJustifyH("LEFT")

	local prev = CreateModernButton(frame, "<", 20, 18)
	prev:SetPoint("RIGHT", -24, 0)

	local nextBtn = CreateModernButton(frame, ">", 20, 18)
	nextBtn:SetPoint("RIGHT", 0, 0)

	for _, btn in ipairs({ prev, nextBtn }) do
		btn:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(tip or label, 1, 1, 1)
			GameTooltip:Show()
		end)
		btn:SetScript("OnLeave", GameTooltip_Hide)
	end
	-- Refresh after each click so the value visibly changes.
	prev:SetScript("OnClick", function()
		onPrev()
		frame:Refresh()
	end)
	nextBtn:SetScript("OnClick", function()
		onNext()
		frame:Refresh()
	end)

	function frame:Refresh()
		text:SetText(("|cff888888%s|r  |cffffffff%s|r"):format(label, getText()))
	end
	frame:Refresh()
	return frame
end

local function ShowTooltip(owner, title, text)
	GameTooltip:SetOwner(owner, "ANCHOR_TOPRIGHT")
	GameTooltip:SetText(title, 1, 1, 1)
	GameTooltip:AddLine(text, nil, nil, nil, true)
	GameTooltip:Show()
end

-- ---------------------------------------------------------------------------
-- Event list metadata
-- ---------------------------------------------------------------------------

local SPELL_LIST_META = {
	Proc = {
		dbKey    = "procSpells",
		header   = "PROC SPELLS",
		addLabel = "Spell name (e.g. Berserking) or spell ID",
		note     = "Built-in: the current Forever proc talents (Bloodthrill, Weaponmaster, Enrage, Flurry, Blood Craze, Gore Drinker, Unbridled Wrath, Redoubt, Reckoning, Vengeance, Unsealed Wrath, Deadly Aspects, Frenzy, Expose Prey, Remorseless Attacks, Quick Getaway, Spirit Tap, Elemental Focus, Maelstrom Weapon, Fingers of Frost, Frostbite, Missile Barrage, Heating Up, Nightfall, Oomen of Clarity, Nature's Grace, Eclipse) plus the enchants Crusader, Revelation, Insight, Recovery, Lifestealing, Fiery Weapon, Unholy Weapon, Icy Chill. Procs with no aura (extra attacks, instant energy, free casts) are not detectable. Add your own below.",
	},
	Interrupt = {
		dbKey    = "interruptSpells",
		header   = "INTERRUPT / SILENCE SPELLS",
		addLabel = "Extra spell name (e.g. Silence) or spell ID",
		note     = "Built-in: Kick, Pummel, Shield Bash, Counterspell, Earth Shock, Spell Lock, Silence (all ranks). Interrupts are detected directly; silences are detected when you land them on your target.",
	},
}

local function CurrentSpellList()
	local meta = SPELL_LIST_META[selectedEventKey]
	if not meta then return nil, nil end
	return ns.db[meta.dbKey], meta
end

-- Compact labels for the event list; the full label is shown in the details
-- pane and in tooltips.
local SHORT_LABELS = {
	KillPlayer     = "Kill: Player",
	KillNPC        = "Kill: Mob",
	Death          = "You Died",
	DeathByPlayer  = "Died to Player",
	Proc           = "Proc / Buff",
	CritPlayer     = "Crit: Player",
	Interrupt      = "Interrupt / Silence",
	Streak2        = "Double Kill",
	Streak3        = "Triple Kill",
	Streak4        = "Quad Kill",
	Streak5        = "Multi Kill 5+",
	CombatIn       = "Combat Start",
	CombatOut      = "Combat End",
}

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

-- ---------------------------------------------------------------------------
-- Panel content
-- ---------------------------------------------------------------------------

local ROW_H = 24
local MAX_SOUNDS = 40
local MAX_SPELLS = 20

-- Header
local headerIcon, enableCheck

-- Event nav
local navCard, navRows = {}, {}
local NAV_W, NAV_ROW_H = 210, 24

-- Details pane
local detailTitle, detailStatus, detailEnable
local soundsCard, soundsHeader, soundsScroll, soundsContent, soundRows, soundsEmpty, soundBar
local addBox, addBtn, testBtn
local spellCard, spellHeader, spellScroll, spellContent, spellRows, spellEmpty, spellNote, spellBar
local spellAddBox, spellAddBtn

-- General + footer
local generalCard, channelDropdown, streakStepper, pvpStepper, onlyMineCheck, watchCheck
local footerText

-- Layout helpers ------------------------------------------------------------

local function LayoutSoundRows()
	local sounds = ns.db.events[selectedEventKey].sounds
	local n = #sounds
	for i, row in ipairs(soundRows) do
		if i <= n then
			row.name:SetText(sounds[i])
			row.index = i
			row:Show()
		else
			row:Hide()
		end
	end
	soundsContent:SetHeight(math.max(n * ROW_H, 2))
	soundsEmpty:SetShown(n == 0)
	soundsScroll:SetShown(n > 0)
	if soundBar then soundBar:SetShown(n > 0 and n * ROW_H > soundsScroll:GetHeight()) end
	local hasSounds = n > 0
	if hasSounds then testBtn:Enable() else testBtn:Disable() end
end

local function LayoutSpellRows()
	local spells = select(1, CurrentSpellList()) or {}
	local n = #spells
	for i, row in ipairs(spellRows) do
		if i <= n then
			row.name:SetText(SpellDisplay(spells[i]))
			row.index = i
			row:Show()
		else
			row:Hide()
		end
	end
	spellContent:SetHeight(math.max(n * ROW_H, 2))
	spellEmpty:SetShown(n == 0)
	spellScroll:SetShown(n > 0)
	if spellBar then spellBar:SetShown(n > 0 and n * ROW_H > spellScroll:GetHeight()) end
end

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
		ns.Print("|cffff8040note:|r '" .. name .. "' does not end in .mp3, .wav or .ogg.")
	end
	sounds[#sounds + 1] = name
	LayoutSoundRows()
	ns.PlaySoundPath(ns.ResolveSoundPath(name))
	if ns.RefreshOptions then ns.RefreshOptions() end
	return true
end

local function AddSpellEntry(value)
	local spells = select(1, CurrentSpellList())
	if not spells then return false end
	if #spells >= MAX_SPELLS then
		ns.Print("that spell list is full (20 entries).")
		return false
	end
	value = strtrim(tostring(value or ""))
	if value == "" then return false end
	spells[#spells + 1] = tonumber(value) or value
	ns.RebuildProcLookups()
	ns.RebuildInterruptLookups()
	LayoutSpellRows()
	if ns.RefreshOptions then ns.RefreshOptions() end
	return true
end

-- ---------------------------------------------------------------------------
-- Build the panel
-- ---------------------------------------------------------------------------

local function BuildNavRow(parent, index)
	local row = CreateFrame("Button", nil, parent)
	row:SetSize(NAV_W - 20, NAV_ROW_H)
	row:RegisterForClicks("LeftButtonUp")

	local hl = row:CreateTexture(nil, "BACKGROUND")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1)
	hl:SetVertexColor(unpack(C.hover))
	hl:SetAlpha(0)
	row.highlight = hl

	local accent = row:CreateTexture(nil, "BORDER")
	accent:SetSize(3, NAV_ROW_H - 6)
	accent:SetPoint("LEFT", 0, 0)
	accent:SetColorTexture(unpack(C.gold))
	accent:Hide()
	row.accent = accent

	local dot = row:CreateTexture(nil, "ARTWORK")
	dot:SetSize(8, 8)
	dot:SetPoint("LEFT", 12, 0)
	dot:SetColorTexture(0.3, 0.9, 0.35, 1)
	row.dot = dot

	local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	label:SetPoint("LEFT", 24, 0)
	label:SetJustifyH("LEFT")
	label:SetWidth(NAV_W - 76)
	label:SetWordWrap(false)
	row.label = label

	local count = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	count:SetPoint("RIGHT", -4, 0)
	row.count = count

	row:SetScript("OnEnter", function(self)
		self.highlight:SetAlpha(1)
		local event = ns.EVENT_BY_KEY[self.eventKey]
		if event then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(event.label, 1, 1, 1)
			GameTooltip:AddLine(event.tip or "", nil, nil, nil, true)
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine("|cff999999Click to configure this event|r")
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
		if selectedEventKey ~= self.eventKey then self.highlight:SetAlpha(0) end
	end)
	row:SetScript("OnClick", function(self)
		selectedEventKey = self.eventKey
		if ns.RefreshOptions then ns.RefreshOptions() end
	end)
	return row
end

local function CreateSoundRow(parent, i)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(280, ROW_H)

	local hl = row:CreateTexture(nil, "BACKGROUND")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1)
	hl:SetVertexColor(unpack(C.hover))
	hl:SetAlpha(0)
	row:SetScript("OnEnter", function() hl:SetAlpha(1) end)
	row:SetScript("OnLeave", function() hl:SetAlpha(0) end)

	local name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	name:SetPoint("LEFT", 10, 0)
	name:SetWidth(170)
	name:SetJustifyH("LEFT")
	name:SetWordWrap(false)

	local play = CreateModernButton(row, "Play", 48, 20)
	play:SetPoint("RIGHT", -34, 0)
	play:SetScript("OnClick", function()
		if row.index then
			ns.PlaySoundPath(ns.ResolveSoundPath(ns.db.events[selectedEventKey].sounds[row.index]))
		end
	end)

	local remove = CreateModernButton(row, "X", 22, 20)
	remove:SetPoint("RIGHT", -6, 0)
	remove:SetScript("OnClick", function()
		if row.index then
			table.remove(ns.db.events[selectedEventKey].sounds, row.index)
			LayoutSoundRows()
			if ns.RefreshOptions then ns.RefreshOptions() end
		end
	end)

	row.name = name
	row:Hide()
	return row
end

local function CreateSpellRow(parent, i)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(280, ROW_H)

	local hl = row:CreateTexture(nil, "BACKGROUND")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1)
	hl:SetVertexColor(unpack(C.hover))
	hl:SetAlpha(0)
	row:SetScript("OnEnter", function() hl:SetAlpha(1) end)
	row:SetScript("OnLeave", function() hl:SetAlpha(0) end)

	local name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	name:SetPoint("LEFT", 10, 0)
	name:SetWidth(240)
	name:SetJustifyH("LEFT")
	name:SetWordWrap(false)

	local remove = CreateModernButton(row, "X", 22, 20)
	remove:SetPoint("RIGHT", -6, 0)
	remove:SetScript("OnClick", function()
		local spells = select(1, CurrentSpellList())
		if row.index and spells then
			table.remove(spells, row.index)
			ns.RebuildProcLookups()
			ns.RebuildInterruptLookups()
			LayoutSpellRows()
			if ns.RefreshOptions then ns.RefreshOptions() end
		end
	end)

	row.name = name
	row:Hide()
	return row
end

local function BuildPanel()
	panel = CreateFrame("Frame")
	panel.name = "Tagaria SoundFX"
	panel:SetSize(600, 636)

	-- Header ------------------------------------------------------------

	local header = CreateCard(panel, 580, 56)
	header:SetPoint("TOPLEFT", 10, -8)

	headerIcon = header:CreateTexture(nil, "ARTWORK")
	headerIcon:SetSize(36, 36)
	headerIcon:SetPoint("LEFT", 14, 0)
	headerIcon:SetTexture("Interface\\Icons\\INV_Misc_Drum_01")

	local title = header:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", headerIcon, "TOPRIGHT", 12, -4)
	title:SetText("|cffff8800Tagaria|r |cffffd100Sound|r|cffff8800FX|r")

	local subtitle = header:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	subtitle:SetPoint("TOPLEFT", header, "TOPLEFT", 66, -36)
	subtitle:SetText("Add file names below - several sounds are picked at random.")

	local version = header:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	version:SetPoint("LEFT", title, "RIGHT", 10, 0)
	version:SetText("v" .. ns.VERSION)

	enableCheck = CreateModernCheckbox(header, "Enabled", "Master switch: on enables every event, off disables every event.", function(value)
		ns.SetEnabled(value)
	end, "left", function() return ns.db.enabled end)
	enableCheck:SetPoint("RIGHT", -14, 0)
	AddControl(enableCheck)

	-- Event list (left) ---------------------------------------------------

	navCard = CreateCard(panel, NAV_W, 424)
	navCard:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)

	local navHeader = navCard:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	navHeader:SetPoint("TOPLEFT", navCard, "TOPLEFT", 14, -10)
	navHeader:SetText("|cffffd100EVENTS|r")

	local navHint = navCard:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	navHint:SetPoint("TOPRIGHT", navCard, "TOPRIGHT", -12, -10)
	navHint:SetText("sounds")

	for i, event in ipairs(ns.EVENTS) do
		local row = BuildNavRow(navCard, i)
		row:SetPoint("TOPLEFT", navCard, "TOPLEFT", 10, -32 - (i - 1) * NAV_ROW_H)
		row.eventKey = event.key
		navRows[i] = row
	end

	-- Details (right) -----------------------------------------------------

	local detail = CreateCard(panel, 362, 424)
	detail:SetPoint("TOPLEFT", navCard, "TOPRIGHT", 8, 0)

	detailTitle = detail:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	detailTitle:SetPoint("TOPLEFT", detail, "TOPLEFT", 16, -10)
	detailTitle:SetWidth(330)
	detailTitle:SetJustifyH("LEFT")

	detailEnable = CreateModernCheckbox(detail, "Event enabled", nil, function(value)
		ns.db.events[selectedEventKey].enabled = value
		if ns.RefreshOptions then ns.RefreshOptions() end
	end, nil, function() return ns.db.events[selectedEventKey].enabled end)
	detailEnable:SetPoint("TOPLEFT", detail, "TOPLEFT", 12, -32)
	AddControl(detailEnable)

	detailStatus = detail:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	detailStatus:SetPoint("TOPLEFT", detail, "TOPLEFT", 128, -36)
	detailStatus:SetWidth(220)
	detailStatus:SetJustifyH("LEFT")
	detailStatus:SetScript("OnEnter", function(self)
		local available, how = ns.KillSoundsAvailable(selectedEventKey)
		local event = ns.EVENT_BY_KEY[selectedEventKey]
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
		GameTooltip:SetText(event.label, 1, 1, 1)
		if available then
			GameTooltip:AddLine("|cff4dd44dDetectable on this client|r - " .. (how or ""), nil, nil, nil, true)
		else
			GameTooltip:AddLine("|cffff6633Not detectable right now|r - " .. (how or ""), nil, nil, nil, true)
		end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(event.tip or "", nil, nil, nil, true)
		GameTooltip:Show()
	end)
	detailStatus:SetScript("OnLeave", GameTooltip_Hide)

	-- Sounds card ----------------------------------------------------------

	soundsCard = CreateCard(detail, 330, 172)
	soundsCard:SetPoint("TOPLEFT", detail, "TOPLEFT", 16, -60)
	if soundsCard.SetBackdrop then
		soundsCard:SetBackdropColor(unpack(C.cardSoft))
	end

	soundsHeader = soundsCard:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	soundsHeader:SetPoint("TOPLEFT", soundsCard, "TOPLEFT", 12, -6)

	soundsScroll = CreateFrame("ScrollFrame", "TagariaSoundFXSoundScroll", soundsCard, "UIPanelScrollFrameTemplate")
	-- Size follows the card (which stretches on events without a spell list),
	-- reserving space at top for the header and at bottom for the input row.
	soundsScroll:SetPoint("TOPLEFT", soundsCard, "TOPLEFT", 8, -26)
	soundsScroll:SetPoint("BOTTOMRIGHT", soundsCard, "BOTTOMRIGHT", -8, 44)

	-- Pin the template's scrollbar inside the card: without this the arrows
	-- can drift to the card's edge (or beyond).
	soundBar = soundsScroll.ScrollBar
	if soundBar then
		soundBar:ClearAllPoints()
		soundBar:SetPoint("TOPLEFT", soundsScroll, "TOPRIGHT", -13, -2)
		soundBar:SetPoint("BOTTOMLEFT", soundsScroll, "BOTTOMRIGHT", -13, 2)
	end

	soundsContent = CreateFrame("Frame", nil, soundsScroll)
	soundsContent:SetWidth(280)
	soundsScroll:SetScrollChild(soundsContent)

	soundsEmpty = soundsCard:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	soundsEmpty:SetPoint("TOPLEFT", soundsCard, "TOPLEFT", 12, -28)
	soundsEmpty:SetWidth(300)
	soundsEmpty:SetJustifyH("LEFT")
	soundsEmpty:SetText("No sounds yet - type a file name below and press Add.")

	soundRows = {}
	for i = 1, MAX_SOUNDS do
		local row = CreateSoundRow(soundsContent, i)
		row:SetPoint("TOPLEFT", soundsContent, "TOPLEFT", 0, -((i - 1) * ROW_H))
		soundRows[i] = row
	end

	addBox = CreateEditBox(soundsCard, 120)
	addBox:SetPoint("BOTTOMLEFT", soundsCard, "BOTTOMLEFT", 12, 10)
	addBox:SetScript("OnEnterPressed", function(self)
		if AddSoundEntry(self:GetText()) then
			self:SetText("")
			self:ClearFocus()
		end
	end)

	addBtn = CreateModernButton(soundsCard, "Add", 52, 22)
	addBtn:SetPoint("LEFT", addBox, "RIGHT", 6, 0)
	addBtn:SetScript("OnClick", function()
		if AddSoundEntry(addBox:GetText()) then addBox:SetText("") end
	end)

	testBtn = CreateModernButton(soundsCard, "Test", 56, 22)
	testBtn:SetPoint("LEFT", addBtn, "RIGHT", 6, 0)
	testBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
		GameTooltip:SetText("Test Event", 1, 1, 1)
		GameTooltip:AddLine("Play a random sound from this event's list.", nil, nil, nil, true)
		GameTooltip:Show()
	end)
	testBtn:SetScript("OnLeave", GameTooltip_Hide)
	testBtn:SetScript("OnClick", function()
		ns.PlayEvent(selectedEventKey)
	end)

	-- Spell list card (Proc / Interrupt) ------------------------------------

	spellCard = CreateCard(detail, 330, 148)
	spellCard:SetPoint("TOPLEFT", soundsCard, "BOTTOMLEFT", 0, -8)
	if spellCard.SetBackdrop then
		spellCard:SetBackdropColor(unpack(C.cardSoft))
	end

	spellHeader = spellCard:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	spellHeader:SetPoint("TOPLEFT", spellCard, "TOPLEFT", 12, -6)

	spellScroll = CreateFrame("ScrollFrame", "TagariaSoundFXSpellScroll", spellCard, "UIPanelScrollFrameTemplate")
	spellScroll:SetSize(288, 50)
	spellScroll:SetPoint("TOPLEFT", spellCard, "TOPLEFT", 8, -24)

	spellBar = spellScroll.ScrollBar
	if spellBar then
		spellBar:ClearAllPoints()
		spellBar:SetPoint("TOPLEFT", spellScroll, "TOPRIGHT", -13, -2)
		spellBar:SetPoint("BOTTOMLEFT", spellScroll, "BOTTOMRIGHT", -13, 2)
	end

	spellContent = CreateFrame("Frame", nil, spellScroll)
	spellContent:SetWidth(280)
	spellScroll:SetScrollChild(spellContent)

	spellEmpty = spellCard:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	spellEmpty:SetPoint("TOPLEFT", spellCard, "TOPLEFT", 12, -26)
	spellEmpty:SetWidth(300)
	spellEmpty:SetJustifyH("LEFT")
	spellEmpty:SetText("No extra spells - built-ins are used.")

	spellRows = {}
	for i = 1, MAX_SPELLS do
		local row = CreateSpellRow(spellContent, i)
		row:SetPoint("TOPLEFT", spellContent, "TOPLEFT", 0, -((i - 1) * ROW_H))
		spellRows[i] = row
	end

	spellAddBox = CreateEditBox(spellCard, 120)
	spellAddBox:SetPoint("BOTTOMLEFT", spellCard, "BOTTOMLEFT", 12, 10)
	spellAddBox:SetScript("OnEnterPressed", function(self)
		if AddSpellEntry(self:GetText()) then
			self:SetText("")
			self:ClearFocus()
		end
	end)

	spellAddBtn = CreateModernButton(spellCard, "Add", 52, 22)
	spellAddBtn:SetPoint("LEFT", spellAddBox, "RIGHT", 6, 0)
	spellAddBtn:SetScript("OnClick", function()
		if AddSpellEntry(spellAddBox:GetText()) then spellAddBox:SetText("") end
	end)

	spellNote = spellCard:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	spellNote:SetPoint("BOTTOMLEFT", spellCard, "BOTTOMLEFT", 12, 34)
	spellNote:SetPoint("RIGHT", spellCard, "RIGHT", -12, 0)
	spellNote:SetJustifyH("LEFT")

	-- General card -----------------------------------------------------------

	generalCard = CreateCard(panel, 580, 92)
	generalCard:SetPoint("TOPLEFT", navCard, "BOTTOMLEFT", 0, -8)

	local genLabel = generalCard:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	genLabel:SetPoint("TOPLEFT", generalCard, "TOPLEFT", 12, -6)
	genLabel:SetText("|cffffd100GENERAL|r")

	channelDropdown = CreateDropdown(generalCard,
		function()
			return {
				{ value = "Master", text = "Master volume" },
				{ value = "SFX",    text = "Sound Effects volume" },
			}
		end,
		function(value) return ns.db.channel == value end,
		function(value)
			ns.db.channel = value
			if ns.RefreshOptions then ns.RefreshOptions() end
		end,
		function()
			return (ns.db.channel == "SFX") and "SFX volume" or "Master volume"
		end,
		140)
	channelDropdown:SetPoint("TOPLEFT", generalCard, "TOPLEFT", 12, -22)
	AddControl(channelDropdown)

	streakStepper = CreateStepper(generalCard, "Streaks",
		function() return tostring(ns.db.streakWindow) .. "s" end,
		function() ns.db.streakWindow = math.max(2, (tonumber(ns.db.streakWindow) or 8) - 1) end,
		function() ns.db.streakWindow = math.min(30, (tonumber(ns.db.streakWindow) or 8) + 1) end,
		60, "Seconds between your kills that still counts as one streak. < and > adjust the window.")
	streakStepper:SetPoint("LEFT", channelDropdown, "RIGHT", 14, 0)
	AddControl(streakStepper)

	pvpStepper = CreateStepper(generalCard, "PvP death",
		function() return tostring(ns.db.pvpDeathWindow) .. "s" end,
		function() ns.db.pvpDeathWindow = math.max(2, (tonumber(ns.db.pvpDeathWindow) or 15) - 1) end,
		function() ns.db.pvpDeathWindow = math.min(60, (tonumber(ns.db.pvpDeathWindow) or 15) + 1) end,
		78, "Seconds after taking damage from a player that a death still counts as a PvP death. < and > adjust the window.")
	pvpStepper:SetPoint("LEFT", streakStepper, "RIGHT", 14, 0)
	AddControl(pvpStepper)

	onlyMineCheck = CreateModernCheckbox(generalCard, "Only my killing blows",
		"In a group, only play kill sounds for players that you or your pet finished off yourself. When the client cannot tell who struck the final blow, the kill still counts.",
		function(value) ns.db.onlyMyKills = value end, nil, function() return ns.db.onlyMyKills end)
	onlyMineCheck:SetPoint("TOPLEFT", generalCard, "TOPLEFT", 12, -56)
	AddControl(onlyMineCheck)

	watchCheck = CreateModernCheckbox(generalCard, "Watch my target's combat text",
		"EXPERIMENTAL: this client does not give addons your outgoing critical hits. The addon tells the game to watch your TARGET for floating combat text; when your target takes a critical hit - usually from you - Critical Hit and Critical Killing Blow sounds can play. Your own floating combat text then shows your target's damage taken instead.",
		function(value)
			ns.db.watchTargetText = value
			ns.ApplyWatchTarget()
			if ns.RefreshOptions then ns.RefreshOptions() end
		end, nil, function() return ns.db.watchTargetText end)
	watchCheck:SetPoint("TOPLEFT", generalCard, "TOPLEFT", 180, -56)
	AddControl(watchCheck)

	-- Footer -------------------------------------------------------------------

	footerText = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	footerText:SetPoint("TOPLEFT", generalCard, "BOTTOMLEFT", 12, -6)
	footerText:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
	footerText:SetJustifyH("LEFT")

	-- Refresh logic -------------------------------------------------------------

	local function RefreshNav()
		for _, row in ipairs(navRows) do
			local ev = ns.db.events[row.eventKey]
			local n = ev.sounds and #ev.sounds or 0
			row.label:SetText(SHORT_LABELS[row.eventKey] or ns.EVENT_BY_KEY[row.eventKey].label)
			row.count:SetText(n > 0 and tostring(n) or "")
			if ev.enabled and n > 0 then
				row.dot:SetVertexColor(unpack(C.green))
			elseif ev.enabled then
				row.dot:SetVertexColor(unpack(C.orange))
			else
				row.dot:SetVertexColor(0.35, 0.35, 0.40, 1)
			end
			local selected = (row.eventKey == selectedEventKey)
			row.accent:SetShown(selected)
			row.highlight:SetAlpha(selected and 1 or 0)
			if selected then
				row.label:SetTextColor(unpack(C.gold))
			else
				row.label:SetTextColor(unpack(C.textMid))
			end
		end
	end

	local function RefreshDetail()
		local event = ns.EVENT_BY_KEY[selectedEventKey]
		local ev = ns.db.events[selectedEventKey]
		detailTitle:SetText("|cffffd100" .. event.label .. "|r")
		detailEnable:SetChecked(ev.enabled)

		local available = ns.KillSoundsAvailable(selectedEventKey)
		if available then
			detailStatus:SetText("|cff4dd44dDetectable on this client|r")
		else
			detailStatus:SetText("|cffff6633Not detectable right now|r")
		end

		soundsHeader:SetText(("|cffffd100SOUNDS|r %d - one is picked at random"):format(#ev.sounds))

		local spellMeta = SPELL_LIST_META[selectedEventKey]
		spellCard:SetShown(spellMeta ~= nil)
		-- With a spell list both cards stay compact; without one the sounds
		-- card stretches to fill the pane instead of leaving dead space.
		soundsCard:ClearAllPoints()
		soundsCard:SetPoint("TOPLEFT", detail, "TOPLEFT", 16, -60)
		if spellMeta then
			soundsCard:SetSize(330, 172)
			spellHeader:SetText("|cffffd100" .. spellMeta.header .. "|r")
			spellNote:SetText(spellMeta.note)
			LayoutSpellRows()
		else
			soundsCard:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -16, 14)
		end
		LayoutSoundRows()
	end

	local function RefreshFooter()
		local line
		if ns.IS_MODERN then
			line = ("WoW Forever (%d): kills via PARTY_KILL + kill credit"):format(ns.INTERFACE)
			if ns.db.watchTargetText then
				line = line .. " | crit: watch target"
			else
				line = line .. " | crit: 'Watch my target's combat text'"
			end
		else
			line = ("Classic client (%d): combat log - full kill and crit detection."):format(ns.INTERFACE)
		end
		footerText:SetText(line)
	end

	function ns.RefreshOptions()
		if not panel then return end
		for _, control in ipairs(controls) do
			if control.Refresh then control:Refresh() end
		end
		RefreshNav()
		RefreshDetail()
		RefreshFooter()
	end

	-- If the container is somehow narrower than the panel, shrink to fit
	-- instead of overflowing the Blizzard window.
	local function FitPanel()
		local parent = panel:GetParent()
		if parent and parent.GetWidth then
			local ok, pw = pcall(parent.GetWidth, parent)
			if ok and type(pw) == "number" and pw > 200 then
				local scale = pw / 600
				if scale < 0.8 then scale = 0.8 end
				if scale > 1 then scale = 1 end
				panel:SetScale(scale)
				return
			end
		end
		panel:SetScale(1)
	end

	panel:SetScript("OnShow", function()
		FitPanel()
		ns.RefreshOptions()
	end)
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
		InterfaceOptionsFrame_OpenToCategory(panel)
		InterfaceOptionsFrame_OpenToCategory(panel)
	end
end

-- ---------------------------------------------------------------------------
-- Addon compartment
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
	GameTooltip:AddLine("|cffff8800Tagaria|r |cffffd100Sound|r|cffff8800FX|r")
	GameTooltip:AddLine(ns.db.enabled and "Enabled" or "Disabled", 1, 1, 1)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Left-click: configure sounds")
	GameTooltip:AddLine("Right-click: enable / disable")
	GameTooltip:Show()
end

function TagariaSoundFX_OnCompartmentLeave()
	GameTooltip:Hide()
end
