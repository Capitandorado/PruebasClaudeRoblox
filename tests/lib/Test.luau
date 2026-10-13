-- Minimal test framework: suites register tests with t.test(name, fn).

local Test = {}

local function deepEqual(a, b, seen)
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	seen = seen or {}
	if seen[a] == b then
		return true
	end
	seen[a] = b
	for key, value in a do
		if not deepEqual(value, b[key], seen) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

local function describe(value)
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

function Test.newContext()
	local t = { tests = {}, prefix = "" }
	function t.test(name, fn)
		table.insert(t.tests, { name = t.prefix .. name, fn = fn })
	end
	function t.describe(name, fn)
		local previous = t.prefix
		t.prefix = previous .. name .. " > "
		fn()
		t.prefix = previous
	end
	function t.ok(condition, message)
		if not condition then
			error("assertion failed: " .. (message or "expected truthy value"), 2)
		end
	end
	function t.eq(actual, expected, message)
		if actual ~= expected then
			error(
				string.format(
					"%sexpected %s, got %s",
					if message then message .. ": " else "",
					describe(expected),
					describe(actual)
				),
				2
			)
		end
	end
	function t.deepEq(actual, expected, message)
		if not deepEqual(actual, expected) then
			error((message or "values differ") .. " (deep equality)", 2)
		end
	end
	function t.near(actual, expected, tolerance, message)
		if type(actual) ~= "number" or math.abs(actual - expected) > tolerance then
			error(
				string.format(
					"%sexpected %s ± %s, got %s",
					if message then message .. ": " else "",
					tostring(expected),
					tostring(tolerance),
					describe(actual)
				),
				2
			)
		end
	end
	function t.errors(fn, pattern, message)
		local ok, err = pcall(fn)
		if ok then
			error((message or "expected an error") .. " but call succeeded", 2)
		end
		if pattern and not string.find(tostring(err), pattern) then
			error(string.format("error %q does not match %q", tostring(err), pattern), 2)
		end
		return err
	end
	return t
end

Test.deepEqual = deepEqual

return Test
