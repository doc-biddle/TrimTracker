-- Runs every tests/test_*.lua with plain Lua 5.1, from the repository root: lua5.1 tests/run.lua
-- Each test file returns a table of named test functions. Exits non-zero when any test fails, which stops the
-- release pipeline. This file is the same in every addon repository.

FakeWoW = dofile("tests/fakewow.lua")

-- Small assertions for the tests.
T = {}
function T.eq(actual, expected, what)
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(what or "value", tostring(expected), tostring(actual)), 2)
	end
end
function T.ok(value, what) if not value then error((what or "expected a true value"), 2) end end
function T.has(text, needle, what)
	if type(text) ~= "string" or not text:find(needle, 1, true) then
		error(("%s: expected %q in %q"):format(what or "text", needle, tostring(text)), 2)
	end
end
function T.lacks(text, needle, what)
	if type(text) == "string" and text:find(needle, 1, true) then
		error(("%s: did not expect %q in %q"):format(what or "text", needle, text), 2)
	end
end
-- No errors were reported to the game's error handler, and nothing printed as an error.
function T.clean(helpers, what)
	local errs = helpers.Errors()
	if #errs > 0 then error((what or "run") .. ": error handler got: " .. errs[1], 2) end
	for _, line in ipairs(helpers.Printed()) do
		if line:lower():find("error") then error((what or "run") .. ": printed: " .. line, 2) end
	end
end

local files = {}
local list = io.popen("ls tests/test_*.lua 2>/dev/null")
for path in list:lines() do files[#files + 1] = path end
list:close()

local passed, failed = 0, 0
for _, path in ipairs(files) do
	local cases = dofile(path)
	local names = {}
	for name in pairs(cases) do names[#names + 1] = name end
	table.sort(names)
	for _, name in ipairs(names) do
		local ok, err = xpcall(cases[name], debug.traceback)
		if ok then
			passed = passed + 1
			print("ok    " .. path .. ": " .. name)
		else
			failed = failed + 1
			print("FAIL  " .. path .. ": " .. name .. "\n      " .. tostring(err):gsub("\n", "\n      "))
		end
	end
end
print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
