-- Trim Tracker: tidies the objective tracker.
--  * hides its "All Objectives" header,
--  * keeps it from running down over the Details windows,
--  * groups tracked quests under collapsible zone headers,
--  * gives the quest timer a movable, sizable frame of its own.
--
-- How it stays out of Blizzard's way: no Blizzard function or field is replaced or written, and no Blizzard
-- function is called. Blizzard lays the quests out as usual; hooks that run afterwards only move frames (the quest
-- blocks under Trim Tracker's own zone headers, the quest timer into its own frame) and size the quest map buttons
-- and fonts. The tracker's height is set from here too (never during combat), which is how room is kept for the
-- headers and above the Details windows.

local tracker = ObjectiveTrackerFrame
if not tracker then return end
local QT = QuestObjectiveTracker

local function DB()
	TrimTrackerDB = TrimTrackerDB or {}
	local db = TrimTrackerDB
	if db.gap == nil then db.gap = 24 end          -- space left above the Details windows (their title bar sits there)
	if db.hideHeader == nil then db.hideHeader = true end
	db.cursorTips = nil   -- setting of the tooltip feature removed in 2.0.0
	if db.zoneHeaders == nil then db.zoneHeaders = true end
	if db.spacing == nil then db.spacing = 5 end      -- space between quests (Blizzard uses 10)
	if db.poiScale == nil then db.poiScale = 0.7 end   -- size of the quest map buttons beside each quest
	if db.timerScale == nil then db.timerScale = 1 end   -- quest timer size, relative to the tracker's
	-- db.fontSize: text size for quest lines at Edit Mode's smallest Text Size (nil = Blizzard's sizes)
	db.zones = db.zones or {}
	return db
end

-- Per-character zone state: which zones are collapsed (and the quests that were untracked to collapse them),
-- plus the last known zone of each quest, for quests whose quest log header is collapsed.
local function ZoneDB()
	local db = DB()
	local key = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "")
	local z = db.zones[key] or {}
	db.zones[key] = z
	z.collapsed = z.collapsed or {}
	z.zoneOf = z.zoneOf or {}
	return z
end

-- Highest top edge, in screen pixels, of a shown Details window that sits under the tracker.
local function DetailsTop(left, right)
	local best
	for i = 1, 20 do
		local frame = _G["DetailsBaseFrame" .. i]
		if frame and frame:IsVisible() then
			local l, r, t = frame:GetLeft(), frame:GetRight(), frame:GetTop()
			if l and r and t then
				local s = frame:GetEffectiveScale()
				l, r, t = l * s, r * s, t * s
				if r > left and l < right then
					best = math.max(best or 0, t)
				end
			end
		end
	end
	return best
end

-- Height ---------------------------------------------------------------------------------------------------

local pending, busy = false, false
local natural          -- the height Blizzard gives the tracker (from Edit Mode or its default position)
local lastSet          -- the last height Trim Tracker set (the game reports size changes a moment later)
local reserve = 0      -- room kept for the zone headers

local function ApplyHeader()
	local header = tracker.Header
	if not header then return end
	local hide = DB().hideHeader
	header:SetAlpha(hide and 0 or 1)
	if header.MinimizeButton then header.MinimizeButton:EnableMouse(not hide) end
end

local function ApplyHeight()
	if busy or not tracker:IsShown() then return end
	if InCombatLockdown() then pending = true return end
	local top, left, right = tracker:GetTop(), tracker:GetLeft(), tracker:GetRight()
	if not (top and left and right) then return end
	natural = natural or tracker:GetHeight()
	local want = natural
	local scale = tracker:GetEffectiveScale()
	local limit = DetailsTop(left * scale, right * scale)
	if limit then want = math.min(want, (top * scale - limit) / scale - DB().gap) end
	want = math.max(60, want - reserve)
	if math.abs(tracker:GetHeight() - want) > 0.5 then
		busy = true
		lastSet = want
		tracker:SetHeight(want)
		busy = false
	end
end

-- Text size: Blizzard's tracker fonts are font objects ObjectiveTrackerFont12 to 22, and Edit Mode's Text Size picks one
-- for quest lines and one 2 sizes up for headers. Shrinking those font objects themselves (never Blizzard's code or
-- tables) lets Edit Mode keep working while going below its smallest size of 12: with a size of 9, Edit Mode's 12
-- becomes 9, its 13 becomes 10, and so on. Blizzard measures the text when it lays the tracker out, so it fits.
local FONT_MIN, FONT_MAX = 12, 22
local fontOriginal = {}

local function ApplyFont()
	local size = DB().fontSize
	for n = FONT_MIN, FONT_MAX do
		local font = _G["ObjectiveTrackerFont" .. n]
		if font and font.GetFont then
			local path, height, flags = font:GetFont()
			if path then
				fontOriginal[n] = fontOriginal[n] or height
				local want = size and math.max(6, size + n - FONT_MIN) or fontOriginal[n]
				if math.abs(height - want) > 0.1 then font:SetFont(path, want, flags or "") end
			end
		end
	end
	-- Fonts that copied their size from these before Trim Tracker loaded follow along.
	for _, name in ipairs({ "ObjectiveTrackerLineFont", "ObjectiveTrackerHeaderFont" }) do
		local font = _G[name]
		local parent = font and font.GetFontObject and font:GetFontObject()
		if parent then font:SetFontObject(parent) end
	end
end

-- The line text size the tracker is showing now.
local function LineFontSize()
	local font = _G.ObjectiveTrackerLineFont
	if not (font and font.GetFont) then return 12 end
	local _, height = font:GetFont()
	return height or 12
end

-- Blizzard lays the tracker out again whenever its size changes, which is how a new text size gets measured.
local function Relayout()
	if InCombatLockdown() or not tracker:IsShown() then return end
	local h = tracker:GetHeight()
	busy = true
	lastSet = h - 1
	tracker:SetHeight(h - 1)
	busy = false
	C_Timer.After(0.1, ApplyHeight)
end

local function Apply()
	if InCombatLockdown() then pending = true return end
	pending = false
	ApplyHeader()
	ApplyHeight()
end

tracker:HookScript("OnSizeChanged", function()
	local h = tracker:GetHeight()
	if busy or (lastSet and math.abs(h - lastSet) < 0.5) then return end   -- our own change
	natural = h      -- Blizzard set it: this is the height to work down from
	C_Timer.After(0, ApplyHeight)
end)
tracker:HookScript("OnShow", function() C_Timer.After(0, Apply) end)

-- Zone headers ---------------------------------------------------------------------------------------------

local HEADER_GAP, INDENT = 4, 8
local function HeaderHeight() return math.floor(LineFontSize() + 2 + 4 + 0.5) end
local OTHER = OTHER or "Other"
local changing = false      -- true while Trim Tracker itself changes quest tracking

-- Zone of every quest in the log (from the quest log's zone headers), and the zones in quest log order.
local function QuestZones()
	local zdb = ZoneDB()
	local order, seen, inLog = {}, {}, {}
	local header
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(i)
		if info then
			if info.isHeader then
				header = info.title
			elseif info.questID then
				inLog[info.questID] = true
				if header then zdb.zoneOf[info.questID] = header end
				local zone = zdb.zoneOf[info.questID] or OTHER
				if not seen[zone] then seen[zone] = true; order[#order + 1] = zone end
			end
		end
	end
	-- forget quests that have left the log
	for id in pairs(zdb.zoneOf) do
		if not inLog[id] and C_QuestLog.GetLogIndexForQuestID(id) == nil then zdb.zoneOf[id] = nil end
	end
	for zone, ids in pairs(zdb.collapsed) do
		for i = #ids, 1, -1 do
			if C_QuestLog.GetLogIndexForQuestID(ids[i]) == nil then table.remove(ids, i) end
		end
		if #ids == 0 then zdb.collapsed[zone] = nil end
	end
	-- the zone you are in comes first
	local here = GetRealZoneText and GetRealZoneText()
	for i, zone in ipairs(order) do
		if zone == here then table.remove(order, i); table.insert(order, 1, zone); break end
	end
	return order
end

local function ZoneOf(questID)
	return ZoneDB().zoneOf[questID] or OTHER
end

local function SetCollapsed(zone, collapse)
	local zdb = ZoneDB()
	changing = true
	if collapse then
		local ids = zdb.collapsed[zone] or {}
		for i = C_QuestLog.GetNumQuestWatches(), 1, -1 do
			local id = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
			if id and ZoneOf(id) == zone then
				ids[#ids + 1] = id
				C_QuestLog.RemoveQuestWatch(id)
			end
		end
		zdb.collapsed[zone] = ids
	else
		local ids = zdb.collapsed[zone] or {}
		zdb.collapsed[zone] = nil
		for i = #ids, 1, -1 do
			if C_QuestLog.GetLogIndexForQuestID(ids[i]) then C_QuestLog.AddQuestWatch(ids[i]) end
		end
	end
	changing = false
end

-- Headers live in their own frame that follows the tracker, so a header stays clickable even when every zone
-- is collapsed and Blizzard hides the tracker for having nothing to show.
local holder = CreateFrame("Frame", "TrimTrackerZoneHeaders", UIParent)
holder:SetFrameStrata(tracker:GetFrameStrata())
holder:SetSize(1, 1)
holder:SetPoint("TOPLEFT", tracker, "TOPLEFT")
local headers = {}

local function GetHeader(i)
	local h = headers[i]
	if h then return h end
	h = CreateFrame("Button", nil, holder)
	h:RegisterForClicks("LeftButtonUp")
	h.icon = h:CreateTexture(nil, "ARTWORK")
	h.icon:SetSize(12, 12)
	h.icon:SetPoint("LEFT", 0, 0)
	h.text = h:CreateFontString(nil, "ARTWORK")
	h.text:SetFontObject(_G.ObjectiveTrackerHeaderFont or GameFontHighlight)
	h.text:SetTextColor(1, 1, 1)
	h.text:SetPoint("LEFT", h.icon, "RIGHT", 4, 0)
	h.text:SetPoint("RIGHT", -2, 0)
	h.text:SetJustifyH("LEFT")
	h.text:SetWordWrap(false)
	h:SetScript("OnClick", function(self)
		SetCollapsed(self.zone, not ZoneDB().collapsed[self.zone])
	end)
	h:SetScript("OnEnter", function(self)
		self.text:SetTextColor(1, 0.82, 0)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(self.zone)
		GameTooltip:AddLine(ZoneDB().collapsed[self.zone] and "Click to show this zone's quests." or "Click to hide this zone's quests.", 1, 1, 1)
		GameTooltip:Show()
	end)
	h:SetScript("OnLeave", function(self)
		self.text:SetTextColor(1, 1, 1)
		GameTooltip:Hide()
	end)
	headers[i] = h
	return h
end

-- The round quest map button beside each quest, made smaller and lined up with the quest's title.
local function SizePOI(block)
	local poi = block.poiButton
	if not (poi and poi.SetScale and block.HeaderText) then return end
	local scale = DB().poiScale
	poi:SetScale(scale)
	poi:ClearAllPoints()
	poi:SetPoint("RIGHT", block.HeaderText, "TOPLEFT", -3 / scale, -LineFontSize() / 2 / scale)
end

local extra = 0   -- how much further down the quest list now ends than Blizzard planned

local function LayoutZones()
	local used = 0
	extra = 0
	local zdb = ZoneDB()
	local on = DB().zoneHeaders and not tracker.isCollapsed and not (EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive())
	if on and QT then
		local order = QuestZones()

		-- Quest blocks as Blizzard laid them out, grouped by zone.
		local groups, prev, first = {}, nil, true
		if QT:IsShown() then
			local block = QT.firstBlock
			while block do
				if block.template == QT.blockTemplate and type(block.id) == "number" then
					local zone = ZoneOf(block.id)
					groups[zone] = groups[zone] or {}
					table.insert(groups[zone], block)
					first = false
				elseif first then
					prev = block      -- pop-ups and the like that sit above the quests stay where they are
				end
				block = block.nextBlock
			end
		end

		local cf = QT.ContentsFrame
		local inline = QT:IsShown() and cf and next(groups) ~= nil
		local anchor, point, gap
		if inline then
			if prev then anchor, point, gap = prev, "BOTTOM", -DB().spacing
			else anchor, point, gap = cf, "TOP", -DB().spacing end
		elseif tracker:IsShown() then
			anchor, point, gap = tracker.NineSlice or tracker, "BOTTOM", -4
		else
			anchor, point, gap = tracker.Header or tracker, "BOTTOM", -4
		end
		local leftFrame = inline and cf or tracker

		holder:SetScale(tracker:GetEffectiveScale() / UIParent:GetEffectiveScale())
		local headerH = HeaderHeight()
		local ours, placed = 0, 0

		-- How many quests each zone has under its header: tracked ones, or the ones collapsing hid.
		local count = {}
		for i = 1, C_QuestLog.GetNumQuestWatches() do
			local id = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
			if id then local z = ZoneOf(id); count[z] = (count[z] or 0) + 1 end
		end
		for _, zone in ipairs(order) do
			local blocks, collapsed = groups[zone], zdb.collapsed[zone]
			if blocks or collapsed then
				used = used + 1
				local h = GetHeader(used)
				h.zone = zone
				h.text:SetText(zone .. " |cffaaaaaa(" .. (collapsed and #collapsed or count[zone] or 0) .. ")|r")
				h:SetHeight(headerH)
				h.icon:SetSize(headerH - 4, headerH - 4)
				h.icon:SetTexture(collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
				h:ClearAllPoints()
				h:SetPoint("TOP", anchor, point, 0, gap)
				h:SetPoint("LEFT", leftFrame, "LEFT", inline and (QT.blockOffsetX or 0) or 0, 0)
				h:SetPoint("RIGHT", leftFrame, "RIGHT", 0, 0)
				h:Show()
				ours = ours + headerH - gap
				anchor, point, gap = h, "BOTTOM", -2
				for _, block in ipairs(blocks or {}) do
					ours = ours - gap
					placed = placed + 1
					block:ClearAllPoints()
					block:SetPoint("TOP", anchor, point, 0, gap)
					block:SetPoint("LEFT", (block.offsetX or QT.blockOffsetX or 0) + INDENT, 0)
					if not block.fixedWidth then block:SetPoint("RIGHT") end
					anchor, point, gap = block, "BOTTOM", -DB().spacing
					SizePOI(block)
				end
				gap = gap - HEADER_GAP
			end
		end
		-- How much further down the quests now end than where Blizzard put them.
		if inline and placed > 0 then
			local blizz = -(prev and (QT.fromBlockOffsetY or -10) or (QT.fromHeaderOffsetY or -10)) - (placed - 1) * (QT.fromBlockOffsetY or -10)
			extra = math.max(0, ours - blizz)
		end
	end
	for i = used + 1, #headers do headers[i]:Hide() end
	holder:SetShown(used > 0)

	-- Keep room for every header the zones need (not only the ones that fit), so the result is stable.
	local want = 0
	if on then
		for _ in pairs(zdb.collapsed) do want = want + 1 end
		local zones = {}
		for i = 1, C_QuestLog.GetNumQuestWatches() do
			local id = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
			if id then zones[ZoneOf(id)] = true end
		end
		for zone in pairs(zones) do if not zdb.collapsed[zone] then want = want + 1 end end
		want = want * (HeaderHeight() + HEADER_GAP)
	end
	if want ~= reserve then
		reserve = want
		C_Timer.After(0, ApplyHeight)
	end
end

-- The next module below the quests (achievements, professions and so on) moves down by the room the headers took.
local function ShiftNextModule()
	if extra <= 0 or not QT or not QT:IsShown() or type(tracker.modules) ~= "table" then return end
	local after = false
	for _, module in ipairs(tracker.modules) do
		if after and module:IsShown() and module:GetHeight() > 0 then
			module:ClearAllPoints()
			module:SetPoint("TOP", QT, "BOTTOM", 0, -(tracker.moduleSpacing or 0) - extra)
			module:SetPoint("LEFT", tracker, "LEFT", module.leftMargin or 0, 0)
			return
		end
		if module == QT then after = true end
	end
end

-- Quest timer ------------------------------------------------------------------------------------------------

-- WoW Forever puts its quest timer box at the top of the tracker, where it covers the first quests and its title
-- tab reaches up under the minimap. Trim Tracker moves the box into a frame of its own that can be dragged anywhere
-- and sized separately. Only where the box sits and its size change; Blizzard's code still fills and shows it.
local timer = QuestTimerFrame
local timerHolder, placingTimer

local function SaveTimerPosition()
	local point, _, relPoint, x, y = timerHolder:GetPoint(1)
	DB().timerPos = { point, relPoint, x, y }
end

local function PlaceTimerHolder()
	local pos = DB().timerPos
	timerHolder:ClearAllPoints()
	if pos then
		timerHolder:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	elseif MinimapCluster then
		timerHolder:SetPoint("TOPRIGHT", MinimapCluster, "TOPLEFT", -10, -30)   -- beside the minimap, clear of the tracker
	else
		timerHolder:SetPoint("TOP", UIParent, "TOP", 0, -120)
	end
end

local function ApplyTimerScale()
	if not timerHolder then return end
	-- The size is relative to the tracker's, so 100% looks the way the box did inside the tracker.
	timerHolder:SetScale(math.max(0.2, (tracker:GetScale() or 1) * DB().timerScale))
end

-- Puts the box in the holder (Blizzard's code may anchor it back to the tracker; it is moved back each time).
local function AttachTimer()
	if not (timer and timerHolder) or placingTimer then return end
	placingTimer = true
	if timer:GetParent() ~= timerHolder then timer:SetParent(timerHolder) end
	timer:ClearAllPoints()
	timer:SetPoint("TOP", timerHolder, "TOP", 0, -13)   -- 13: room for the title tab above the box
	placingTimer = false
end

local timerUnlocked = false
local function SetTimerUnlocked(on)
	timerUnlocked = on and true or false
	if not timerHolder then return end
	timerHolder:EnableMouse(timerUnlocked)
	timerHolder.preview:SetShown(timerUnlocked)
end

if timer then
	timerHolder = CreateFrame("Frame", "TrimTrackerQuestTimer", UIParent)
	timerHolder:SetSize(math.max(160, timer:GetWidth() or 160), 80)
	timerHolder:SetFrameStrata("MEDIUM")
	timerHolder:SetMovable(true)
	timerHolder:SetClampedToScreen(true)
	timerHolder:RegisterForDrag("LeftButton")
	timerHolder:SetScript("OnDragStart", function(self) self:StartMoving() end)
	timerHolder:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SaveTimerPosition()
	end)

	-- Shown while unlocked: a box to drag, standing in for the timer when no timed quest is running.
	local preview = CreateFrame("Frame", nil, timerHolder)
	preview:SetAllPoints()
	preview:SetFrameLevel(timerHolder:GetFrameLevel() + 20)
	local bg = preview:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.1, 0.6, 0.1, 0.35)
	local label = preview:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("CENTER")
	label:SetText("Quest timer\n|cffaaaaaadrag to move|r")
	preview:Hide()
	timerHolder.preview = preview
	timerHolder:EnableMouse(false)

	PlaceTimerHolder()
	ApplyTimerScale()
	AttachTimer()
	hooksecurefunc(timer, "SetPoint", function() if not placingTimer then C_Timer.After(0, AttachTimer) end end)
	hooksecurefunc(timer, "SetParent", function() if not placingTimer then C_Timer.After(0, AttachTimer) end end)
	tracker:HookScript("OnSizeChanged", function() C_Timer.After(0, ApplyTimerScale) end)   -- Edit Mode scale changes
end

if QT then
	hooksecurefunc(QT, "EndLayout", LayoutZones)
	hooksecurefunc(tracker, "Update", function()
		if not QT:IsShown() then LayoutZones() end   -- the quest module skipped its layout: headers still need placing
		ShiftNextModule()
	end)
end

-- Quests that get tracked in a collapsed zone (accepted, progressed, or tracked by hand) stay collapsed.
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
pcall(events.RegisterEvent, events, "EDIT_MODE_LAYOUTS_UPDATED")
events:SetScript("OnEvent", function(_, event, questID, added)
	if event == "ADDON_LOADED" then
		-- Saved settings are in now, before Edit Mode picks the tracker's text size and the first layout.
		if questID == "TrimTracker" then ApplyFont() end
		return
	end
	if event == "QUEST_WATCH_LIST_CHANGED" then
		if changing or not added or not questID or not DB().zoneHeaders then return end
		QuestZones()   -- a quest that was just accepted is not in the zone list yet
		local zone = ZoneOf(questID)
		local ids = ZoneDB().collapsed[zone]
		if ids then
			ids[#ids + 1] = questID
			changing = true
			C_QuestLog.RemoveQuestWatch(questID)
			changing = false
		end
		return
	end
	if event == "ZONE_CHANGED_NEW_AREA" then
		C_Timer.After(0.5, function() if not tracker:IsShown() or not QT or not QT:IsShown() then LayoutZones() end end)
		return
	end
	if event == "PLAYER_REGEN_ENABLED" and not pending then return end
	C_Timer.After(0.5, function()
		Apply()
		if event == "PLAYER_ENTERING_WORLD" and DB().fontSize then ApplyFont(); Relayout() end
		LayoutZones()
	end)
end)

-- Details windows can be moved or opened at any time; a cheap check every two seconds keeps up with them.
C_Timer.NewTicker(2, ApplyHeight)

-- Settings ---------------------------------------------------------------------------------------------------

-- Changes a setting and puts it into effect. Used by both the options panel and the slash commands.
local function Set(key, value)
	local db = DB()
	if key == "fontSize" then
		db.fontSize = value
		ApplyFont()
		-- Text only reports its new height a moment after its font changes, so lay out again once it has.
		C_Timer.After(0.2, Relayout)
		C_Timer.After(1, Relayout)
	elseif key == "spacing" then
		db.spacing = math.max(0, math.min(10, value))
		Relayout()
	elseif key == "poiScale" then
		db.poiScale = math.max(0.3, math.min(1, value))
		Relayout()
	elseif key == "zoneHeaders" then
		db.zoneHeaders = value and true or false
		if not db.zoneHeaders then
			-- bring back everything that was collapsed
			for zone in pairs(ZoneDB().collapsed) do SetCollapsed(zone, false) end
		end
		LayoutZones()
		Relayout()
	elseif key == "timerScale" then
		db.timerScale = math.max(0.5, math.min(2, value))
		ApplyTimerScale()
	elseif key == "timerUnlocked" then
		SetTimerUnlocked(value)
		return
	elseif key == "gap" then
		db.gap = value
		ApplyHeight()
	else
		db[key] = value
	end
	Apply()
end

-- Options > AddOns > Trim Tracker. Settings registered here also show up in the options search box.
local category
local function BuildOptions()
	if category or not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterProxySetting) then return end
	local cat, layout = Settings.RegisterVerticalLayoutCategory("Trim Tracker")
	local VT = Settings.VarType or {}
	local Checkbox = Settings.CreateCheckbox or Settings.CreateCheckBox

	local function Section(title)
		if layout and CreateSettingsListSectionHeaderInitializer then
			layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(title))
		end
	end

	local function Toggle(key, name, default, tooltip)
		local setting = Settings.RegisterProxySetting(cat, "TRIMTRACKER_" .. key:upper(), VT.Boolean or "boolean", name, default,
			function() return DB()[key] and true or false end,
			function(value) Set(key, value) end)
		Checkbox(cat, setting, tooltip)
	end

	-- get/set convert between what the slider shows and what is saved.
	local function Slider(key, name, default, min, max, step, tooltip, label, get, set)
		local setting = Settings.RegisterProxySetting(cat, "TRIMTRACKER_" .. key:upper(), VT.Number or "number", name, default,
			function() return get and get(DB()[key]) or DB()[key] end,
			function(value)
				if set then value = set(value) end
				if value == false then value = nil end
				Set(key, value)
			end)
		local options = Settings.CreateSliderOptions(min, max, step)
		if label and MinimalSliderWithSteppersMixin then
			options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, label)
		end
		Settings.CreateSlider(cat, setting, options, tooltip)
	end

	Section("Zones")
	Toggle("zoneHeaders", "Zone headers", true,
		"Groups tracked quests under their zone, with the zone you're in first. Click a zone header to collapse or expand it: collapsing untracks the zone's quests, expanding tracks them again.\n\nTurning this off tracks all collapsed quests again.")

	Section("Look")
	-- 5 on the slider stands for Blizzard's own sizes, as there is no "off" position on a slider.
	Slider("fontSize", "Text size", 5, 5, 20, 1,
		"Size of quest text when Edit Mode's Text Size is at its smallest (12). Each step up in Edit Mode adds 1. Quest titles are 2 sizes larger.\n\nAll the way left uses Edit Mode's sizes.",
		function(v) return v <= 5 and "Edit Mode" or tostring(v) end,
		function(v) return v or 5 end,
		function(v) if v <= 5 then return false end return v end)
	Slider("spacing", "Space between quests", 5, 0, 10, 1, "Space between one quest and the next. Blizzard uses 10.",
		function(v) return tostring(v) end)
	Slider("poiScale", "Quest button size", 70, 30, 100, 5, "Size of the round quest map buttons beside each quest, as a percentage of Blizzard's.",
		function(v) return v .. "%" end,
		function(v) return math.floor(v * 100 + 0.5) end,
		function(v) return v / 100 end)
	Toggle("hideHeader", "Hide the tracker header", true, "Hides the tracker's \"All Objectives\" header and its collapse button.")

	if timerHolder then
		Section("Quest timer")
		local setting = Settings.RegisterProxySetting(cat, "TRIMTRACKER_TIMERUNLOCKED", VT.Boolean or "boolean", "Move the quest timer", false,
			function() return timerUnlocked end, function(value) Set("timerUnlocked", value) end)
		Checkbox(cat, setting, "Shows a green box where the quest timer goes, even without a timed quest. Drag it where you want the timer, then untick this.")
		Slider("timerScale", "Quest timer size", 100, 50, 200, 5, "Size of the quest timer, as a percentage of the tracker's size.",
			function(v) return v .. "%" end,
			function(v) return math.floor(v * 100 + 0.5) end,
			function(v) return v / 100 end)
		if layout and CreateSettingsButtonInitializer then
			layout:AddInitializer(CreateSettingsButtonInitializer("Quest timer position", "Reset", function()
				DB().timerPos = nil
				PlaceTimerHolder()
			end, "Puts the quest timer back beside the minimap.", true))
		end
	end

	Section("Details!")
	Slider("gap", "Space above Details!", 24, 0, 60, 1,
		"Space kept between the bottom of the tracker and the top of any Details! window under it (room for Details' title bar).",
		function(v) return tostring(v) end)


	Settings.RegisterAddOnCategory(cat)
	category = cat
end

local function OpenOptions()
	if not category then BuildOptions() end
	if category and Settings.OpenToCategory then
		Settings.OpenToCategory(category.GetID and category:GetID() or category)
	end
end

local optionsEvents = CreateFrame("Frame")
optionsEvents:RegisterEvent("ADDON_LOADED")
optionsEvents:SetScript("OnEvent", function(self, _, name)
	if name ~= "TrimTracker" then return end
	self:UnregisterEvent("ADDON_LOADED")
	local ok, err = pcall(BuildOptions)
	if not ok then
		DB().optionsError = tostring(err)
		print("Trim Tracker: the options panel could not be built (" .. tostring(err) .. "). The slash commands still work.")
	else
		DB().optionsError = nil
	end
end)

-- Commands ---------------------------------------------------------------------------------------------------

SLASH_TRIMTRACKER1 = "/trimtracker"
SLASH_TRIMTRACKER2 = "/trackertrim"   -- the old name still works
SlashCmdList.TRIMTRACKER = function(msg)
	local cmd, arg = (msg or ""):lower():match("^(%S*)%s*(.-)$")
	local db = DB()
	local n = tonumber(arg)
	if cmd == "" or cmd == "options" or cmd == "config" then
		OpenOptions()
	elseif cmd == "gap" and n then
		Set("gap", n)
		print("Trim Tracker: gap above Details set to " .. db.gap .. ".")
	elseif cmd == "header" then
		Set("hideHeader", not db.hideHeader)
		print("Trim Tracker: header " .. (db.hideHeader and "hidden" or "shown") .. ".")
	elseif cmd == "font" then
		if arg == "" or arg == "reset" then
			Set("fontSize", nil)
			print("Trim Tracker: tracker text back to Edit Mode's sizes.")
		elseif n and n >= 6 and n <= 20 then
			Set("fontSize", math.floor(n))
			print("Trim Tracker: tracker text size " .. db.fontSize .. " at Edit Mode's smallest Text Size (each step up in Edit Mode adds 1).")
		else
			print("Trim Tracker: /trimtracker font <6-20>, or /trimtracker font reset")
		end
	elseif cmd == "spacing" and n then
		Set("spacing", n)
		print("Trim Tracker: space between quests set to " .. db.spacing .. " (Blizzard uses 10).")
	elseif cmd == "buttons" and n then
		Set("poiScale", n)
		print("Trim Tracker: quest map buttons at " .. math.floor(db.poiScale * 100 + 0.5) .. "% of their usual size.")
	elseif cmd == "timer" then
		if arg == "reset" then
			DB().timerPos = nil
			if timerHolder then PlaceTimerHolder() end
			print("Trim Tracker: quest timer back beside the minimap.")
		elseif n then
			Set("timerScale", n / 100)
			print("Trim Tracker: quest timer at " .. math.floor(db.timerScale * 100 + 0.5) .. "% size.")
		else
			Set("timerUnlocked", not timerUnlocked)
			print("Trim Tracker: quest timer " .. (timerUnlocked and "unlocked: drag the green box, then type /trimtracker timer again to lock it." or "locked."))
		end
	elseif cmd == "zones" then
		Set("zoneHeaders", not db.zoneHeaders)
		print("Trim Tracker: zone headers " .. (db.zoneHeaders and "on" or "off (collapsed zones are tracked again)") .. ".")
	else
		print("Trim Tracker: /trimtracker opens the options. Commands: gap <number> (now " .. db.gap .. "), header (now "
			.. (db.hideHeader and "hidden" or "shown") .. "), zones (now "
			.. (db.zoneHeaders and "on" or "off") .. "), font <size> or reset (now "
			.. (db.fontSize or "Edit Mode's") .. "), spacing <0-10> (now " .. db.spacing
			.. "), buttons <0.3-1> (now " .. db.poiScale .. "), timer (move), timer <50-200> (size, now "
			.. math.floor(db.timerScale * 100 + 0.5) .. "%), timer reset")
	end
end
