-- Phase 4: several players on one server, visits and global leaderboards.

local Fixture = require("../lib/Fixture")
local DataStore = require("../mock/DataStore")

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

return function(t)
	t.test("eight players get independent plots, inventories and production", function()
		local rt = Fixture.server({ isStudio = true })
		local players, sessions = {}, {}
		for index = 1, 8 do
			players[index] = Fixture.join(rt, { userId = 800 + index, name = "P" .. index })
			sessions[index] = Fixture.session(rt, players[index])
		end
		local plots = {}
		for index, session in sessions do
			t.ok(not plots[session.plot], "plot " .. session.plot .. " assigned once")
			plots[session.plot] = true
			local model = rt:find(rt.workspace, "VoidFactory.Plots.Plot_" .. session.plot)
			t.eq(model:GetAttribute("OwnerUserId"), 800 + index)
			-- Each character stands on its own plot.
			local character = players[index].Character
			local spawnPad = model:FindFirstChild("Spawn")
			t.ok(
				(character:GetPivot().Position - spawnPad.Position).Magnitude < 10,
				"player " .. index .. " spawned on own plot"
			)
		end
		-- Only even players place an artifact: odd players must not earn anything.
		for index, player in players do
			if index % 2 == 0 then
				Fixture.request(rt, player, "Admin", "give", "ion_battery||1")
				t.ok(Fixture.request(rt, player, "Place", 1, "ion_battery||1").ok)
			end
		end
		local start = {}
		for index, session in sessions do
			start[index] = session.profile.energy
		end
		rt:run(20, 0.25)
		for index, session in sessions do
			local gained = session.profile.energy - start[index]
			if index % 2 == 0 then
				local eps = rt:asServer(function()
					return require(services(rt).Sessions).production(session).total
				end)
				t.near(gained, eps * 20, eps * 1.5, "player " .. index .. " earns its own production")
			else
				t.eq(gained, 0, "player " .. index .. " earns nothing")
			end
		end
		t.eq(#rt:errors(), 0, errorsText(rt))
	end)

	t.test("visiting another factory and coming home", function()
		local rt = Fixture.server({ isStudio = true })
		local alice = Fixture.join(rt, { userId = 901, name = "Alice", noClient = false })
		local bob = Fixture.join(rt, { userId = 902, name = "Bob", noClient = false })
		rt:run(1, 0.1)
		local sa = Fixture.session(rt, alice)
		local sb = Fixture.session(rt, bob)
		local response = Fixture.request(rt, bob, "Visit", 901)
		t.ok(response.ok, tostring(response.err))
		t.eq(response.data.plot, sa.plot)
		local alicePlot = rt:find(rt.workspace, "VoidFactory.Plots.Plot_" .. sa.plot)
		t.ok((bob.Character:GetPivot().Position - alicePlot.Spawn.Position).Magnitude < 10, "bob is at alice's plot")
		-- Bob cannot use Alice's machine prompts (disabled on his client), Alice can.
		local prompt = rt:find(alicePlot, "Machines.Pad_1.Plate.Prompt")
		local promptsBob = rt:requireIn(bob, bob.PlayerScripts.Client.Controllers.Prompts)
		rt:asClient(bob, function()
			promptsBob.trigger(prompt)
		end)
		rt:run(0.5, 0.1)
		t.eq(sb.profile.stats.boxesOpened, 0, "bob's trigger on alice's plot did nothing")
		t.eq(sa.profile.stats.boxesOpened, 0, "and alice's data is untouched")
		-- Visiting someone who is not in the server fails cleanly.
		t.eq(Fixture.request(rt, bob, "Visit", 123456).err, "InvalidTarget")
		t.ok(Fixture.request(rt, bob, "GoHome").ok)
		local bobPlot = rt:find(rt.workspace, "VoidFactory.Plots.Plot_" .. sb.plot)
		t.ok((bob.Character:GetPivot().Position - bobPlot.Spawn.Position).Magnitude < 10, "bob is home")
		t.eq(#rt:errors(), 0, errorsText(rt))
	end)

	t.test("owners keep their machine prompts, visitors don't get them", function()
		local rt = Fixture.server({ isStudio = true })
		local alice = Fixture.join(rt, { userId = 911, name = "Alice", noClient = false })
		local bob = Fixture.join(rt, { userId = 912, name = "Bob", noClient = false })
		rt:run(1, 0.1)
		local sa = Fixture.session(rt, alice)
		local plot = rt:find(rt.workspace, "VoidFactory.Plots.Plot_" .. sa.plot)
		local prompt = rt:find(plot, "Machines.Pad_1.Plate.Prompt")
		-- Shared DataModel in the mock: check each client's view through its own controller.
		local promptsAlice = rt:requireIn(alice, alice.PlayerScripts.Client.Controllers.Prompts)
		rt:asClient(alice, function()
			promptsAlice.trigger(prompt)
		end)
		rt:run(6, 1 / 20)
		t.eq(sa.profile.stats.boxesOpened, 1, "alice opens a box from her own prompt")
		local _ = bob
		t.eq(#rt:errors(), 0, errorsText(rt))
	end)

	t.test("announcements are reserved for extraordinary finds and throttled", function()
		local rt = Fixture.server({ isStudio = true })
		local Game = rt:requireIn("server", services(rt).Game)
		local Rarities = rt:requireIn("server", rt.services.ReplicatedStorage.Shared.Config.Rarities)
		local now = 1000
		t.eq(Game.shouldAnnounce(Rarities.get("Epic"), true, now), false, "epic never global")
		t.eq(Game.shouldAnnounce(Rarities.get("Legendary"), false, now), false, "repeat legendary stays local")
		t.eq(Game.shouldAnnounce(Rarities.get("Legendary"), true, now), true, "first legendary is announced")
		t.eq(Game.shouldAnnounce(Rarities.get("Mythic"), false, now), true)
		-- Simulate a burst: after one announcement the cooldown blocks the next Mythic...
		local player = Fixture.join(rt, { userId = 960 })
		local session = Fixture.session(rt, player)
		local announced = 0
		local remote = Fixture.remotes(rt):FindFirstChild("Notify")
		rt:asClient(player, function()
			remote.OnClientEvent:Connect(function(kind)
				if kind == "Announce" then
					announced += 1
				end
			end)
		end)
		rt:asServer(function()
			for _ = 1, 5 do
				Game.announceGrants(
					session,
					{ machineId = "starter_fabricator", grants = { { key = "void_nucleus||1", newArtifact = false } } }
				)
			end
			-- ...but a Void find always goes through.
			Game.announceGrants(
				session,
				{ machineId = "starter_fabricator", grants = { { key = "the_singularity||1", newArtifact = false } } }
			)
		end)
		rt:run(0.5, 0.1)
		t.eq(announced, 2, "one mythic + the void find")
	end)

	t.test("global leaderboards push, fetch and fill the hub boards", function()
		local backend = DataStore.newBackend()
		local rt = Fixture.server({ backend = backend, isStudio = false })
		local players = {}
		for index = 1, 3 do
			players[index] = Fixture.join(rt, { userId = 950 + index, name = "Racer" .. index })
			local session = Fixture.session(rt, players[index])
			session.profile.bestEps = index * 1000
			session.profile.collection.scrap_cube = { count = 1, muts = {}, stars = 1, first = 0 }
		end
		rt:run(200, 1)
		local leaderboards = rt:requireIn("server", services(rt).Leaderboards)
		local snapshot = rt:asServer(function()
			return leaderboards.snapshot()
		end)
		t.ok(snapshot.global ~= nil, "global data fetched")
		local production = snapshot.global[1]
		t.eq(production.id, "production")
		t.eq(#production.entries, 3)
		t.eq(production.entries[1].userId, 953, "best production first")
		t.eq(production.entries[1].name, "Racer3")
		local board = rt:findDescendant(rt.workspace, "Board_production")
		local row = rt:findDescendant(board, "Row1")
		t.ok(string.find(row.Text, "Racer3", 1, true) ~= nil, "hub board shows the leader: " .. row.Text)
		-- The Global tab of the UI receives the same data.
		local response = Fixture.request(rt, players[1], "GetLeaderboard")
		t.ok(response.ok and response.data.global ~= nil)
		t.eq(#rt:errors(), 0, errorsText(rt))
	end)
end
