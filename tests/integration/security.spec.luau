-- Phase 4: the economy must be server-authoritative and robust to hostile clients.

local Fixture = require("../lib/Fixture")
local roblox = require("@lune/roblox")

local function errorsText(rt)
	local lines = {}
	for _, err in rt:errors() do
		table.insert(lines, err.trace)
	end
	return table.concat(lines, "\n")
end

local function services(rt)
	return rt.services.ServerScriptService.Server.Services
end

local function clientModule(rt, player, path)
	local target = player:FindFirstChild("PlayerScripts"):FindFirstChild("Client")
	for name in string.gmatch(path, "[^%.]+") do
		target = target:FindFirstChild(name)
	end
	return rt:requireIn(player, target)
end

local function isFinite(value)
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

return function(t)
	t.test("fuzzing every action never errors the server or corrupts the profile", function()
		local rt = Fixture.server({ isStudio = false })
		local player = Fixture.join(rt, { userId = 601 })
		local session = Fixture.session(rt, player)
		session.profile.inventory["scrap_cube||1"] = 3
		local Net = rt:requireIn("server", rt.services.ReplicatedStorage.Shared.Net)
		local NetService = rt:requireIn("server", services(rt).Net)
		local Profile = rt:requireIn("server", rt.services.ReplicatedStorage.Shared.Logic.Profile)
		local pool = {
			nil,
			true,
			false,
			0,
			-1,
			1,
			3,
			1.5,
			0 / 0,
			math.huge,
			-math.huge,
			2 ^ 31,
			1e308,
			"",
			"x",
			string.rep("A", 5000),
			"scrap_cube||1",
			"scrap_cube||1|",
			"starter_fabricator",
			"void_forge",
			"Common",
			"luck",
			"sfx",
			{},
			{ 1, 2, 3 },
			{ a = 1 },
			roblox.Vector3.new(1, 2, 3),
		}
		local rng = Fixture.rng(42)
		local function pick()
			return pool[math.floor(rng:NextNumber() * (#pool + 1)) + 1]
		end
		local remote = Fixture.remotes(rt):FindFirstChild("Request")
		local actions = {}
		for name in Net.Actions do
			table.insert(actions, name)
		end
		table.sort(actions)
		local calls, handled, accepted = 0, 0, 0
		session.profile.energy = 1e6
		rt:asClient(player, function()
			for _ = 1, 25 do
				for _, action in actions do
					-- Usually the right number of arguments (so handlers run), sometimes one extra.
					local count = #Net.Actions[action].args
					if rng:NextNumber() < 0.15 then
						count += 1
					end
					local args = {}
					for index = 1, count do
						args[index] = pick()
					end
					local response = remote:InvokeServer(action, table.unpack(args, 1, count))
					calls += 1
					assert(type(response) == "table" and type(response.ok) == "boolean", "malformed response")
					if response.ok then
						accepted += 1
					end
					if response.ok or (response.err ~= "BadRequest" and response.err ~= "RateLimited") then
						handled += 1
					end
				end
				task.wait(1) -- let rate limits refill so handlers actually run
			end
		end, 120)
		t.ok(calls > 400, "fuzzed " .. calls .. " calls")
		t.ok(handled > 100, "handlers really ran (" .. handled .. " reached game logic)")
		t.ok(accepted > 10, "some random requests were valid (" .. accepted .. ")")
		t.eq(NetService.Stats.errors, 0, "no handler crashed")
		t.ok(Profile.validate(session.profile), "profile still valid")
		t.ok(isFinite(session.profile.energy) and session.profile.energy >= 0, "energy sane")
		for key, count in session.profile.inventory do
			t.ok(
				type(key) == "string" and isFinite(count) and count >= 1 and count == math.floor(count),
				"inventory entry " .. key
			)
		end
		t.eq(#rt:errors(), 0, errorsText(rt))
	end)

	t.test("parallel requests cannot open more boxes than the charges allow", function()
		local rt = Fixture.server({ isStudio = false })
		local player = Fixture.join(rt, { userId = 602 })
		local session = Fixture.session(rt, player)
		local remote = Fixture.remotes(rt):FindFirstChild("Request")
		local results = {}
		rt:asClient(player, function()
			local done = 0
			for _ = 1, 20 do
				task.spawn(function()
					local response = remote:InvokeServer("OpenBox", "starter_fabricator")
					table.insert(results, response)
					done += 1
				end)
			end
			while done < 20 do
				task.wait(0.05)
			end
		end)
		local ok = 0
		for _, response in results do
			if response.ok then
				ok += 1
			end
		end
		local cap = 4
		t.ok(ok <= cap, "at most " .. cap .. " boxes opened, got " .. ok)
		t.eq(session.profile.stats.boxesOpened, ok)
		t.ok(session.profile.machines.starter_fabricator.charges >= 0, "charges never negative")
	end)

	t.test("tampering with the client mirror gives the client nothing", function()
		local rt = Fixture.server({ isStudio = false })
		local player = Fixture.join(rt, { userId = 603, noClient = false })
		rt:run(1, 0.1)
		local session = Fixture.session(rt, player)
		local store = clientModule(rt, player, "Core.Store")
		rt:asClient(player, function()
			store.profile.energy = 1e15
			store.profile.inventory["the_anomaly||1"] = 99
			store.profile.machines.void_forge = { level = 10, charges = 99, chargeAt = 0 }
		end)
		local remote = Fixture.remotes(rt):FindFirstChild("Request")
		local responses = rt:asClient(player, function()
			return {
				remote:InvokeServer("BuyMachine", "lucky_fabricator"),
				remote:InvokeServer("Place", 1, "the_anomaly||1"),
				remote:InvokeServer("OpenBox", "void_forge"),
				remote:InvokeServer("Sell", "the_anomaly||1", 99),
				remote:InvokeServer("Rebirth"),
			}
		end)
		for _, response in responses do
			t.eq(response.ok, false, "rejected: " .. tostring(response.err))
		end
		t.eq(session.profile.energy < 1000, true, "server energy unchanged")
		t.eq(session.profile.inventory["the_anomaly||1"], nil)
		t.eq(session.profile.machines.void_forge, nil)
		-- The next server sync overwrites the tampered mirror.
		rt:run(2, 0.1)
		t.ok(store.profile.energy < 1000, "mirror resynced from the server")
	end)

	t.test("the server refuses a ninth player politely", function()
		local rt = Fixture.server({ isStudio = false })
		for index = 1, 8 do
			Fixture.join(rt, { userId = 700 + index })
		end
		local extra = rt:addPlayer({ userId = 799, noClient = true })
		rt:run(2, 0.1)
		t.eq(#rt.kicks, 1)
		t.eq(rt.kicks[1].userId, 799)
		t.ok(string.find(rt.kicks[1].message, "full") ~= nil)
		local _ = extra
		t.eq(#rt:errors(), 0, errorsText(rt))
	end)
end
