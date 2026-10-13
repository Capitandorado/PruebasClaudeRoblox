-- Test runner: lune run tests/run.luau [filter]
-- Requires sourcemap.json (tools/check.sh generates it with `rojo sourcemap`).

local fs = require("@lune/fs")
local process = require("@lune/process")
local stdio = require("@lune/stdio")
local Test = require("./lib/Test")

local filter = process.args[1]

local files = {}
for _, folder in { "tests/unit", "tests/integration" } do
	if fs.isDir(folder) then
		for _, name in fs.readDir(folder) do
			if string.match(name, "%.spec%.luau$") then
				table.insert(files, folder .. "/" .. name)
			end
		end
	end
end
table.sort(files)

local passed, failed = 0, 0
local failures = {}
local started = os.clock()

for _, file in files do
	local modulePath = "./" .. string.gsub(string.gsub(file, "^tests/", ""), "%.luau$", "")
	local suite = require(modulePath)
	local t = Test.newContext()
	suite(t)
	for _, case in t.tests do
		local fullName = file .. " :: " .. case.name
		if filter and not string.find(fullName, filter, 1, true) then
			continue
		end
		local caseStart = os.clock()
		local ok, err = xpcall(case.fn, function(message)
			return debug.traceback(tostring(message), 2)
		end)
		local elapsed = os.clock() - caseStart
		if ok then
			passed += 1
			print(
				stdio.color("green")
					.. "  PASS "
					.. stdio.color("reset")
					.. fullName
					.. string.format(" (%.2fs)", elapsed)
			)
		else
			failed += 1
			table.insert(failures, { name = fullName, err = err })
			print(stdio.color("red") .. "  FAIL " .. stdio.color("reset") .. fullName)
		end
	end
end

for _, failure in failures do
	print(
		"\n"
			.. stdio.color("red")
			.. "FAILED: "
			.. failure.name
			.. stdio.color("reset")
			.. "\n"
			.. tostring(failure.err)
	)
end
print(string.format("\n%d passed, %d failed (%.1fs)", passed, failed, os.clock() - started))
process.exit(if failed > 0 then 1 else 0)
