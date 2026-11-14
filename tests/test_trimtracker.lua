-- Trim Tracker in a fake game: zone headers over a fake quest tracker, collapsing zones, quests accepted in a
-- collapsed zone, the spacing under a quest whose title wraps, and the slash command.

-- Quest log: Barrens has quests 1 and 2, Wailing Caverns has quest 3. All three are tracked.
local function World(opts)
	opts = opts or {}
	local game, h = FakeWoW.New()
	local timers = {}
	game.C_Timer = {
		After = function(_, fn) table.insert(timers, fn) end,
		NewTicker = function() return { Cancel = function() end } end,
	}
	local function RunTimers() local list = timers; timers = {}; for _, fn in ipairs(list) do fn() end end

	local log = {
		{ isHeader = true, title = "The Barrens" },
		{ questID = 1, title = "Raptor Horns" },
		{ questID = 2, title = "Altered Beings" },
		{ isHeader = true, title = "Wailing Caverns" },
		{ questID = 3, title = "Deviate Hides" },
	}
	local watched = { 1, 2, 3 }
	game.C_QuestLog = {
		GetNumQuestLogEntries = function() return #log end,
		GetInfo = function(i) return log[i] end,
		GetLogIndexForQuestID = function(id) for i, e in ipairs(log) do if e.questID == id then return i end end end,
		GetNumQuestWatches = function() return #watched end,
		GetQuestIDForQuestWatchIndex = function(i) return watched[i] end,
		RemoveQuestWatch = function(id) for i, w in ipairs(watched) do if w == id then table.remove(watched, i) end end end,
		AddQuestWatch = function(id) table.insert(watched, id) end,
	}
	game.UnitName = function() return "Mara" end
	game.GetRealmName = function() return "Forever" end
	game.GetRealZoneText = function() return "The Barrens" end
	game.InCombatLockdown = function() return false end

	-- The tracker and its quest module. Blocks are chained firstBlock -> nextBlock, as Blizzard's are.
	local tracker = game.CreateFrame("Frame", "ObjectiveTrackerFrame")
	tracker.Header = game.CreateFrame("Frame")
	tracker.modules = {}
	function tracker:Update() end
	local QT = game.CreateFrame("Frame", "QuestObjectiveTracker")
	QT.blockTemplate = "ObjectiveTrackerQuestBlock"
	QT.ContentsFrame = game.CreateFrame("Frame")
	QT.blockOffsetX = 0
	function QT:EndLayout() end
	tracker.modules[1] = QT
	local blocks = {}
	for _, id in ipairs({ 1, 2, 3 }) do
		local b = game.CreateFrame("Frame")
		b.id, b.template = id, QT.blockTemplate
		b.HeaderText = game.CreateFrame("FontString")
		b.__bottom, b.HeaderText.__bottom = 100, 100
		b.__regions = { b.HeaderText }
		blocks[#blocks + 1] = b
	end
	for i, b in ipairs(blocks) do b.nextBlock = blocks[i + 1] end
	QT.firstBlock = blocks[1]
	if opts.wrapFirstTitle then blocks[1].HeaderText.__bottom = 100 - opts.wrapFirstTitle end

	h.Load("TrimTracker.lua", "TrimTracker")
	h.Fire("ADDON_LOADED", "TrimTracker")
	h.Fire("PLAYER_ENTERING_WORLD")
	RunTimers()

	local function Layout() QT:EndLayout(); RunTimers() end
	local function Headers()
		local out = {}
		for _, f in ipairs(h.Frames()) do
			if f.zone and f.text and f:IsShown() then out[#out + 1] = f end
		end
		return out
	end
	return game, h, { tracker = tracker, QT = QT, blocks = blocks, watched = watched, Layout = Layout, Headers = Headers, RunTimers = RunTimers }
end

local function HeaderText(world, zone)
	for _, hdr in ipairs(world.Headers()) do
		if hdr.zone == zone then return hdr.text:GetText() end
	end
end

local cases = {}

function cases.zone_headers_with_quest_counts()
	local _, h, w = World()
	w.Layout()
	T.has(HeaderText(w, "The Barrens"), "(2)", "Barrens header")
	T.has(HeaderText(w, "Wailing Caverns"), "(1)", "Wailing Caverns header")
	T.clean(h)
end

function cases.collapsing_a_zone_untracks_its_quests_and_expanding_brings_them_back()
	local _, h, w = World()
	w.Layout()
	local barrens
	for _, hdr in ipairs(w.Headers()) do if hdr.zone == "The Barrens" then barrens = hdr end end
	FakeWoW.RunScript(barrens, "OnClick")
	T.eq(#w.watched, 1, "quests tracked after collapsing")
	FakeWoW.RunScript(barrens, "OnClick")
	T.eq(#w.watched, 3, "quests tracked after expanding")
	T.clean(h)
end

function cases.quest_accepted_in_collapsed_zone_stays_collapsed()
	local _, h, w = World()
	w.Layout()
	for _, hdr in ipairs(w.Headers()) do if hdr.zone == "The Barrens" then FakeWoW.RunScript(hdr, "OnClick") end end
	table.insert(w.watched, 2)   -- the game tracks a Barrens quest again (accepted or progressed)
	h.Fire("QUEST_WATCH_LIST_CHANGED", 2, true)
	T.eq(#w.watched, 1, "the Barrens quest is untracked again")
	T.clean(h)
end

-- The gap between quest 1 and quest 2: the last anchor set on quest 2.
local function GapBelowFirst(w)
	local points = w.blocks[2].__points
	for i = #points, 1, -1 do
		if points[i][1] == "TOP" then return points[i][5] end
	end
end

function cases.wrapped_title_pushes_the_next_quest_down()
	local _, h, plain = World()
	plain.Layout()
	local _, h2, wrapped = World({ wrapFirstTitle = 12 })
	wrapped.Layout()
	T.eq(GapBelowFirst(wrapped), GapBelowFirst(plain) - 12, "gap below a quest whose title wraps by 12")
	T.clean(h); T.clean(h2)
end

function cases.slash_command_runs()
	local _, h = World()
	h.Slash("TRIMTRACKER", "")
	T.clean(h)
end

return cases
