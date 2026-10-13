-- Integration tests: the real server scripts running in the mock runtime.

local Fixture = require("../lib/Fixture")

return function(t)
	t.test("server boots without errors and builds the world", function()
		local rt = Fixture.server({ isStudio = true })
		t.eq(#rt:errors(), 0, "script errors: " .. (rt:errors()[1] and rt:errors()[1].trace or ""))
		local remotes = Fixture.remotes(rt)
		t.ok(remotes ~= nil, "remotes created")
		local plots = rt:find(rt.workspace, "VoidFactory.Plots")
		t.eq(#plots:GetChildren(), 8)
		t.ok(rt:find(rt.workspace, "VoidFactory.Hub") ~= nil, "hub built")
		t.ok(table.find(rt:outputOf("print"), "[VoidFactory] server ready") ~= nil)
	end)

	t.test("a player can open a box, place the artifact and earn energy", function()
		local rt = Fixture.server({ isStudio = true })
		local player, states = Fixture.join(rt, { userId = 101, name = "Alice" })
		local session = Fixture.session(rt, player)
		t.ok(session ~= nil, "session ready")
		t.eq(states[1].kind, "Full")
		t.eq(states[1].payload.plot, session.plot)

		local response = Fixture.request(rt, player, "OpenBox", "starter_fabricator")
		t.ok(response.ok, tostring(response.err))
		local grant = response.data.grants[1]
		t.ok(type(grant.key) == "string", "grant has an item key")
		t.eq(session.profile.stats.boxesOpened, 1)

		local placed = Fixture.request(rt, player, "Place", 1, grant.key)
		t.ok(placed.ok, tostring(placed.err))
		local plotModel = rt:find(rt.workspace, "VoidFactory.Plots.Plot_" .. session.plot)
		local pedestal = rt:find(plotModel, "Slots.Slot_1")
		t.ok(pedestal:FindFirstChild("Artifact") ~= nil, "artifact model on pedestal")

		local before = session.profile.energy
		rt:run(10, 0.25)
		t.ok(session.profile.energy > before, "energy grows")
		t.eq(#rt:errors(), 0, rt:errors()[1] and rt:errors()[1].trace or "")
	end)

	t.test("purchases are validated and charged on the server", function()
		local rt = Fixture.server({ isStudio = true })
		local player = Fixture.join(rt, { userId = 102 })
		local session = Fixture.session(rt, player)
		local response = Fixture.request(rt, player, "BuyMachine", "box_printer")
		t.eq(response.ok, false)
		t.eq(response.err, "NotEnoughEnergy")
		t.ok(Fixture.request(rt, player, "Admin", "energy", 1000).ok)
		response = Fixture.request(rt, player, "BuyMachine", "box_printer")
		t.ok(response.ok, tostring(response.err))
		t.eq(session.profile.energy, 650)
		local plotModel = rt:find(rt.workspace, "VoidFactory.Plots.Plot_" .. session.plot)
		local machine = rt:find(plotModel, "Machines.Pad_2.Machine")
		t.ok(machine ~= nil and machine:GetAttribute("Hologram") == nil, "real machine model built")
		-- The printer opens boxes by itself.
		local opened = session.profile.stats.boxesOpened
		rt:run(25, 0.5)
		t.ok(session.profile.stats.boxesOpened > opened, "printer opened a box")
	end)

	t.test("malformed and malicious requests are rejected without side effects", function()
		local rt = Fixture.server({ isStudio = false })
		local player = Fixture.join(rt, { userId = 103 })
		local session = Fixture.session(rt, player)
		session.profile.inventory["scrap_cube||1"] = 1
		local snapshot = session.profile.energy
		local cases = {
			{ "NotAnAction" },
			{ 42 },
			{ "OpenBox", { "table" } },
			{ "OpenBox", "starter_fabricator", "extra" },
			{ "Place", 0 / 0, "scrap_cube||1" },
			{ "Place", 1e12, "scrap_cube||1" },
			{ "Place", -1, "scrap_cube||1" },
			{ "Place", 1.5, "scrap_cube||1" },
			{ "Sell", "scrap_cube||1", -5 },
			{ "Sell", "scrap_cube||1", 1e9 },
			{ "Sell", string.rep("x", 500), 1 },
			{ "BuyMachine", nil },
			{ "SetSetting", "energy", true },
		}
		for _, case in cases do
			local response = Fixture.request(rt, player, table.unpack(case))
			t.eq(response.ok, false, "rejected: " .. tostring(case[1]))
		end
		-- Admin tools are refused outside Studio for normal players.
		local admin = Fixture.request(rt, player, "Admin", "energy", 1e9)
		t.eq(admin.err, "NotAllowed")
		-- Selling more than owned fails, selling what is owned works.
		t.eq(Fixture.request(rt, player, "Sell", "scrap_cube||1", 2).err, "NotInInventory")
		t.eq(session.profile.energy, snapshot)
		t.ok(Fixture.request(rt, player, "Sell", "scrap_cube||1", 1).ok)
		t.eq(#rt:errors(), 0, rt:errors()[1] and rt:errors()[1].trace or "")
	end)

	t.test("flooding requests is rate limited", function()
		local rt = Fixture.server({ isStudio = true })
		local player = Fixture.join(rt, { userId = 104 })
		local limited = 0
		local remote = Fixture.remotes(rt):FindFirstChild("Request")
		rt:asClient(player, function()
			for _ = 1, 60 do
				local response = remote:InvokeServer("SetAutoSell", "Common", true)
				if response.err == "RateLimited" then
					limited += 1
				end
			end
		end)
		t.ok(limited > 30, "most of a 60-request burst is limited (got " .. limited .. ")")
	end)

	t.test("players get separate plots and leaving frees the plot", function()
		local rt = Fixture.server({ isStudio = true })
		local alice = Fixture.join(rt, { userId = 201, name = "Alice" })
		local bob = Fixture.join(rt, { userId = 202, name = "Bob" })
		local sa, sb = Fixture.session(rt, alice), Fixture.session(rt, bob)
		t.ok(sa.plot ~= sb.plot, "different plots")
		t.ok(Fixture.request(rt, alice, "OpenBox", "starter_fabricator").ok)
		t.eq(sb.profile.stats.boxesOpened, 0, "bob unaffected")
		local plots = rt:find(rt.workspace, "VoidFactory.Plots")
		t.eq(plots:FindFirstChild("Plot_" .. sb.plot):GetAttribute("OwnerUserId"), 202)
		rt:removePlayer(bob)
		rt:run(0.5)
		t.eq(plots:FindFirstChild("Plot_" .. sb.plot):GetAttribute("OwnerUserId"), 0, "plot released")
		t.eq(#rt:errors(), 0, rt:errors()[1] and rt:errors()[1].trace or "")
	end)
end
