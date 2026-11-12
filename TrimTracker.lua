-- Trim Tracker: hides the objective tracker's "All Objectives" header and keeps the tracker from running down
-- over the Details windows. Only hooks and frame sizes are touched; no Blizzard functions or fields are replaced,
-- and nothing is changed during combat (pending changes apply when combat ends).

local tracker = ObjectiveTrackerFrame
if not tracker then return end

local function DB()
	TrimTrackerDB = TrimTrackerDB or {}
	local db = TrimTrackerDB
	if db.gap == nil then db.gap = 24 end          -- space left above the Details windows (their title bar sits there)
	if db.hideHeader == nil then db.hideHeader = true end
	if db.cursorTips == nil then db.cursorTips = true end
	return db
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

local pending, busy = false, false

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
	local scale = tracker:GetEffectiveScale()
	local limit = DetailsTop(left * scale, right * scale)
	if not limit then return end
	local want = math.max(60, (top * scale - limit) / scale - DB().gap)
	if tracker:GetHeight() > want + 0.5 then
		busy = true
		tracker:SetHeight(want)
		busy = false
	end
end

local function Apply()
	if InCombatLockdown() then pending = true return end
	pending = false
	ApplyHeader()
	ApplyHeight()
end

tracker:HookScript("OnSizeChanged", function()
	if not busy then C_Timer.After(0, ApplyHeight) end
end)
tracker:HookScript("OnShow", function() C_Timer.After(0, Apply) end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
pcall(events.RegisterEvent, events, "EDIT_MODE_LAYOUTS_UPDATED")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_ENABLED" and not pending then return end
	C_Timer.After(0.5, Apply)
end)

-- Details windows can be moved or opened at any time; a cheap check every two seconds keeps up with them.
C_Timer.NewTicker(2, ApplyHeight)

-- Tooltips that would go to the default corner spot (action bar skills and the like) follow the cursor instead,
-- the way Leatrix Plus already places them over the game world. Leatrix's own offsets are reused if it has them.
if GameTooltip_SetDefaultAnchor then
	hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
		if not DB().cursorTips or not tooltip or not parent then return end
		if WorldFrame.IsMouseMotionFocus and WorldFrame:IsMouseMotionFocus() then return end   -- the world: Leatrix's job
		local lea = LeaPlusDB or {}
		tooltip:SetOwner(parent, "ANCHOR_CURSOR_RIGHT", tonumber(lea.TipCursorX) or 0, tonumber(lea.TipCursorY) or 0)
	end)
end

SLASH_TRIMTRACKER1 = "/trimtracker"
SLASH_TRIMTRACKER2 = "/trackertrim"   -- the old name still works
SlashCmdList.TRIMTRACKER = function(msg)
	local cmd, arg = (msg or ""):lower():match("^(%S*)%s*(.-)$")
	local db = DB()
	if cmd == "gap" and tonumber(arg) then
		db.gap = tonumber(arg)
		print("Trim Tracker: gap above Details set to " .. db.gap .. ". /reload to let the tracker grow back if it got shorter than needed.")
	elseif cmd == "tips" then
		db.cursorTips = not db.cursorTips
		print("Trim Tracker: skill and interface tooltips " .. (db.cursorTips and "follow the cursor" or "use their usual spot") .. ".")
	elseif cmd == "header" then
		db.hideHeader = not db.hideHeader
		print("Trim Tracker: header " .. (db.hideHeader and "hidden" or "shown") .. ".")
	else
		print("Trim Tracker: /trimtracker gap <number> (now " .. db.gap .. "), /trimtracker header (now "
			.. (db.hideHeader and "hidden" or "shown") .. "), /trimtracker tips (now "
			.. (db.cursorTips and "at cursor" or "default spot") .. ")")
		return
	end
	Apply()
end
