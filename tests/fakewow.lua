-- A fake World of Warcraft client for testing addon code outside the game, with plain Lua 5.1 (the game's Lua).
--
-- What it guards against:
--  * Calling a game function the real client doesn't have. The fake only provides what a test defines, and a test
--    may only define names that tests/client-api.lua lists as present in the real client (that list is made from
--    /biddle apidump in the real game). Anything else the addon calls is nil, as in the game, so the call fails.
--  * Secret values: Secret() makes a value that can't be compared, added or concatenated, like the game's.
--
-- This file is the same in every addon repository.

local FakeWoW = {}

local CLIENT = dofile("tests/client-api.lua")   -- { globals = { Name = "f"|"t"|"s"|"n"|"b" }, namespaces = { C_X = { Fn = "f" } } }

-- Lua's own functions, which the game also has (the client list covers the game's own additions).
local LUA = {
	"assert", "error", "ipairs", "next", "pairs", "pcall", "print", "rawequal", "rawget", "rawset", "select",
	"setmetatable", "getmetatable", "tonumber", "tostring", "type", "unpack", "xpcall", "math", "string", "table",
	"coroutine", "os", "bit",
}

-- Secret values ---------------------------------------------------------------------------------------------------

local secrets = setmetatable({}, { __mode = "k" })
local secretMeta
function FakeWoW.Secret(label)
	local s = newproxy(true)
	local mt = getmetatable(s)
	if not secretMeta then secretMeta = mt end
	local function refuse() error("attempt to use a secret value (" .. tostring(label) .. ")", 2) end
	mt.__lt, mt.__le, mt.__add, mt.__sub, mt.__mul, mt.__div, mt.__concat, mt.__len, mt.__unm =
		refuse, refuse, refuse, refuse, refuse, refuse, refuse, refuse, refuse
	mt.__index = refuse
	mt.__tostring = function() return "<secret " .. tostring(label) .. ">" end
	secrets[s] = true
	return s
end
function FakeWoW.IsSecret(v) return type(v) == "userdata" and secrets[v] == true end

-- Frames ----------------------------------------------------------------------------------------------------------
-- Just enough of a frame for addon code to set up: scripts and events are recorded so tests can fire them, and any
-- other method is accepted and does nothing.

local Frame = {}
local function NewFrame(kind, name)
	local f = { __kind = kind or "Frame", __name = name, __scripts = {}, __events = {}, __hooks = {}, __shown = true, __children = {} }
	return setmetatable(f, Frame)
end
-- Widget methods that are accepted and do nothing here. Anything not modelled and not in this list is nil, as an
-- absent field is in the game.
local NOOP = {}
for name in ([[SetAllPoints SetAlpha SetFrameStrata SetFrameLevel SetMovable EnableMouse
	SetClampedToScreen RegisterForDrag SetUserPlaced SetBackdrop SetBackdropColor SetBackdropBorderColor SetTexture
	SetTexCoord SetVertexColor SetColorTexture SetAtlas SetDesaturated SetFont SetFontObject SetJustifyH SetJustifyV
	SetTextColor SetWordWrap SetNonSpaceWrap SetMaxLines SetSpacing SetOwner SetMinMaxValues SetValue SetValueStep
	SetStatusBarColor SetStatusBarTexture SetOrientation SetDrawLayer SetBlendMode SetHitRectInsets SetToplevel
	SetIgnoreParentScale SetIgnoreParentAlpha StartMoving StopMovingOrSizing SetModel SetUnit SetCamDistanceScale
	SetPortraitZoom SetRotation SetPosition ClearModel SetDisplayInfo Play Stop SetLooping CreateAnimation SetDuration
	SetFromAlpha SetToAlpha SetScript SetChecked SetEnabled Enable Disable SetNormalTexture SetPushedTexture
	SetHighlightTexture SetDisabledTexture SetNormalFontObject SetMotionScriptsWhileDisabled SetAttribute
	RegisterForClicks SetPropagateKeyboardInput EnableKeyboard SetFixedFrameStrata SetFixedFrameLevel
	UnregisterAllEvents SetClipsChildren SetResizable SetResizeBounds AdjustPointsOffset]]):gmatch("%S+") do
	NOOP[name] = function() end
end
Frame.__index = function(self, key)
	return rawget(Frame, key) or NOOP[key]
end
function Frame:SetScript(name, fn) self.__scripts[name] = fn end
function Frame:GetScript(name) return self.__scripts[name] end
function Frame:HookScript(name, fn) self.__hooks[name] = self.__hooks[name] or {}; table.insert(self.__hooks[name], fn) end
function Frame:RegisterEvent(event) self.__events[event] = true end
function Frame:UnregisterEvent(event) self.__events[event] = nil end
function Frame:IsEventRegistered(event) return self.__events[event] == true end
function Frame:GetName() return self.__name end
function Frame:Show() self.__shown = true end
function Frame:Hide() self.__shown = false end
function Frame:IsShown() return self.__shown end
function Frame:IsVisible() return self.__shown end
function Frame:SetShown(on) self.__shown = on and true or false end
function Frame:GetObjectType() return self.__kind end
function Frame:CreateTexture() return NewFrame("Texture") end
function Frame:CreateFontString()
	local fs = NewFrame("FontString")
	function fs:SetText(t) self.__text = t end
	function fs:GetText() return self.__text end
	function fs:SetFormattedText(fmt, ...) self.__text = fmt:format(...) end
	return fs
end
function Frame:CreateAnimationGroup() return NewFrame("AnimationGroup") end
function Frame:GetWidth() return self.__w or 100 end
function Frame:GetHeight() return self.__h or 20 end
function Frame:SetWidth(w) self.__w = w end
function Frame:SetHeight(h) self.__h = h end
function Frame:SetSize(w, h) self.__w, self.__h = w, h end
function Frame:GetScale() return self.__scale or 1 end
function Frame:SetScale(s) self.__scale = s end
function Frame:GetEffectiveScale() return self.__scale or 1 end
function Frame:GetParent() return self.__parent end
function Frame:SetParent(p) self.__parent = p end
function Frame:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function Frame:GetNumPoints() return 1 end
function Frame:GetChildren() return unpack(self.__children) end
function Frame:GetRegions() return unpack(self.__regions or {}) end
-- Position: nil until a test sets __top/__bottom/__left/__right, as for a frame that isn't placed yet.
function Frame:GetTop() return self.__top end
function Frame:GetBottom() return self.__bottom end
function Frame:GetLeft() return self.__left end
function Frame:GetRight() return self.__right end
function Frame:GetFrameStrata() return "MEDIUM" end
function Frame:GetFrameLevel() return 1 end
-- Anchors are recorded, newest last, so tests can check where something was put.
function Frame:SetPoint(...) self.__points = self.__points or {}; table.insert(self.__points, { ... }) end
function Frame:ClearAllPoints() self.__points = {} end

-- Run every handler a frame has for a script: the one set with SetScript, then hooks.
function FakeWoW.RunScript(frame, name, ...)
	local fn = frame.__scripts[name]
	if fn then fn(frame, ...) end
	for _, hook in ipairs(frame.__hooks[name] or {}) do hook(frame, ...) end
end

-- The game -------------------------------------------------------------------------------------------------------

-- A new fake client. `game` is where a test defines the game functions and values the addon will see; defining a
-- name the real client doesn't have is an error. Returns the game table and helpers.
function FakeWoW.New()
	local frames = {}
	local env = {}
	for _, name in ipairs(LUA) do env[name] = _G[name] end
	env.table = setmetatable({ wipe = function(t) for k in pairs(t) do t[k] = nil end return t end }, { __index = table })
	env.string = string
	env._G = env

	local game = setmetatable({}, {
		__newindex = function(t, name, value)
			if CLIENT.globals[name] == nil and env[name] == nil then
				error(("the fake game defines %s, which the real client doesn't have (tests/client-api.lua)"):format(name), 2)
			end
			local ns = CLIENT.namespaces[name]
			if ns and type(value) == "table" then
				for fn in pairs(value) do
					if ns[fn] == nil then
						error(("the fake game defines %s.%s, which the real client doesn't have"):format(name, fn), 2)
					end
				end
			end
			rawset(env, name, value)
		end,
		__index = env,
	})

	-- The basics nearly every addon touches.
	game.CreateFrame = function(kind, name, parent)
		local f = NewFrame(kind, name)
		f.__parent = parent
		table.insert(frames, f)
		if name then rawset(env, name, f) end
		return f
	end
	game.UIParent = NewFrame("Frame", "UIParent")
	game.WorldFrame = NewFrame("Frame", "WorldFrame")
	game.SlashCmdList = {}
	game.hooksecurefunc = function(a, b, c)
		-- hooksecurefunc(name, fn) or hooksecurefunc(table, name, fn): run the hook after the original.
		local tbl, name, hook = env, a, b
		if type(a) == "table" then tbl, name, hook = a, b, c end
		local original = tbl[name]
		rawset(tbl, name, function(...)
			local r = { original(...) }
			hook(...)
			return unpack(r)
		end)
	end
	game.issecretvalue = FakeWoW.IsSecret
	game.GetTime = function() return env.__now or 1000 end
	game.time = function() return env.__clock or 1794600000 end
	game.date = os.date
	game.strsplit = function(sep, s)
		local out = {}
		for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end
		return unpack(out)
	end
	game.wipe = env.table.wipe
	game.tinsert, game.tremove, game.format, game.strmatch, game.strfind = table.insert, table.remove, string.format, string.match, string.find
	game.debugstack = function() return "" end

	local errors = {}
	local handler = function(message) table.insert(errors, tostring(message)) end
	game.geterrorhandler = function() return handler end
	game.seterrorhandler = function(h) handler = h end

	local printed = {}
	env.print = function(...)
		local parts = { ... }
		for i = 1, select("#", ...) do parts[i] = tostring(parts[i]) end
		table.insert(printed, table.concat(parts, " "))
	end

	local helpers = {}
	-- Load an addon file into the fake game, as the client would (with the addon's name and private table).
	function helpers.Load(path, addonName, ns)
		local chunk = assert(loadfile(path))
		setfenv(chunk, env)
		return chunk(addonName, ns or {})
	end
	-- Fire an event at every frame registered for it.
	function helpers.Fire(event, ...)
		for _, f in ipairs(frames) do
			if f.__events[event] then FakeWoW.RunScript(f, "OnEvent", event, ...) end
		end
	end
	function helpers.Slash(key, msg) return env.SlashCmdList[key](msg or "") end
	function helpers.Printed() return printed end
	function helpers.ClearPrinted() for i = #printed, 1, -1 do printed[i] = nil end end
	function helpers.Errors() return errors end
	function helpers.Env() return env end
	function helpers.Frames() return frames end
	return game, helpers
end

return FakeWoW
