-- Phase 3: effects made readable, events, tier celebration and animated machines.

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

local function give(rt, player, keys)
	for _, key in keys do
		assert(Fixture.request(rt, player, "Admin", "give", key).ok, "give " .. key)
	end
end

return function(t)
	t.test("pedestal labels show output and neon links show adjacency", function()
		local rt = Fixture.server({ isStudio = true })
		local player = Fixture.join(rt, { userId = 501, noClient = false })
		rt:run(1, 0.1)
		give(rt, player, { "gravity_well||1", "scrap_cube||1", "scrap_cube|Corrupted|1" })
		t.ok(Fixture.request(rt, player, "Place", 1, "gravity_well||1").ok)
		t.ok(Fixture.request(rt, player, "Place", 2, "scrap_cube||1").ok)
		t.ok(Fixture.request(rt, player, "Place", 8, "scrap_cube|Corrupted|1").ok)
		rt:run(1, 0.1)
		local labels = player.PlayerGui:FindFirstChild("FactoryLabels")
		t.ok(labels ~= nil, "label folder")
		local label = labels:FindFirstChild("Slot2")
		t.ok(label ~= nil and label.Enabled, "label on pedestal 2")
		t.ok(string.find(label.Main.Text, "⚡", 1, true) ~= nil, "shows output: " .. label.Main.Text)
		t.ok(string.find(label.Sub.Text, "linked", 1, true) ~= nil, "shows link bonus: " .. label.Sub.Text)
		local links = rt.workspace:FindFirstChild("FactoryLinks")
		local green, red = 0, 0
		for _, part in links:GetChildren() do
			if part.Color == roblox.Color3.fromRGB(90, 230, 140) then
				green += 1
			elseif part.Color == roblox.Color3.fromRGB(255, 80, 100) then
				red += 1
			end
		end
		t.ok(green >= 1, "green link from the gravity well")
		t.ok(red >= 1, "red link from the corrupted cube")
		t.eq(#rt:errors(), 0, errorsText(rt))
	end)

	t.test("placement preview shows the Energy/s change on every pedestal", function()
		local rt = Fixture.server({ isStudio = true })
		local player = Fixture.join(rt, { userId = 502, noClient = false })
		rt:run(1, 0.1)
		give(rt, player, { "reactor_core||1", "scrap_cube||1" })
		t.ok(Fixture.request(rt, player, "Place", 1, "scrap_cube||1").ok)
		rt:run(1, 0.1)
		local placement = clientModule(rt, player, "Controllers.Placement")
		rt:asClient(player, function()
			placement.begin("reactor_core||1")
		end)
		rt:run(0.5, 0.1)
		local labels = player.PlayerGui.FactoryLabels
		local best = 0
		for _, slot in { 1, 2, 3, 7, 8, 9 } do -- the starting 3x2 layout
			local label = labels:FindFirstChild("Slot" .. slot)
			t.ok(label and string.find(label.Main.Text, "/s", 1, true), "preview on slot " .. slot)
			if label.Sub.Text == "★ BEST" then
				best += 1
			end
		end
		t.eq(best, 1, "exactly one best pedestal")
		t.ok(
			string.find(labels.Slot1.Main.Text, "^%+") ~= nil,
			"replacing the cube still gains: " .. labels.Slot1.Main.Text
		)
		rt:asClient(player, function()
			placement.cancel()
		end)
		rt:run(0.5, 0.1)
		t.eq(labels.Slot3.Enabled, false, "preview cleared on cancel")
		t.eq(#rt:errors(), 0, errorsText(rt))
	end)

	t.test("timed events change server production and show in the HUD", function()
		local rt = Fixture.server({ isStudio = true })
		local EventsConfig = rt:requireIn("server", rt.services.ReplicatedStorage.Shared.Config.Events)
		local Events = rt:requireIn("server", rt.services.ReplicatedStorage.Shared.Logic.Events)
		-- Jump the clock to the start of an Overdrive window.
		local now = rt.scheduler.epoch + rt.scheduler.clock
		local window = math.floor(now / EventsConfig.Period)
		while Events.modifiersAt((window + 0.01) * EventsConfig.Period).signature ~= "overdrive" do
			window += 1
		end
		rt.scheduler.epoch = window * EventsConfig.Period + 5 - rt.scheduler.clock
		local player = Fixture.join(rt, { userId = 503, noClient = false })
		give(rt, player, { "ion_battery||1" })
		t.ok(Fixture.request(rt, player, "Place", 1, "ion_battery||1").ok)
		rt:run(2, 0.1)
		local session = Fixture.session(rt, player)
		local sessions = rt:requireIn("server", services(rt).Sessions)
		local production = rt:asServer(function()
			return sessions.production(session)
		end)
		local Economy = rt:requireIn("server", rt.services.ReplicatedStorage.Shared.Config.Economy)
		local collectionBonus = 1 + Economy.CollectionBonusPerArtifact -- ion battery discovered
		t.near(production.total, 6 * 1.5 * collectionBonus, 1e-6, "overdrive +50%")
		local pill = rt:findDescendant(player.PlayerGui, "EventPill")
		t.ok(string.find(pill.Text.Text, "OVERDRIVE", 1, true) ~= nil, "HUD shows the event: " .. pill.Text.Text)
		-- After the event the bonus disappears.
		rt:run(EventsConfig.Duration + 2, 0.5)
		production = rt:asServer(function()
			return sessions.production(session)
		end)
		t.near(production.total, 6 * collectionBonus, 1e-6, "back to normal")
		t.eq(#rt:errors(), 0, errorsText(rt))
	end)

	t.test("reaching a new best rarity is flagged for the celebration", function()
		local rt = Fixture.modules()
		local Inventory = Fixture.require(rt, "Logic.Inventory")
		local Profile = Fixture.require(rt, "Logic.Profile")
		local Items = Fixture.require(rt, "Logic.Items")
		local profile = Profile.new(0)
		local first = Inventory.grantRolled(profile, Items.parse("reactor_core||1"), 0)
		t.eq(first.newTier, true)
		local same = Inventory.grantRolled(profile, Items.parse("prism_lens||1"), 0)
		t.eq(same.newTier, false, "same tier is not new")
		local lower = Inventory.grantRolled(profile, Items.parse("scrap_cube||1"), 0)
		t.eq(lower.newTier, false)
	end)

	t.test("machines are animated near the camera", function()
		local rt = Fixture.server({ isStudio = true })
		local player = Fixture.join(rt, { userId = 504, noClient = false })
		rt:run(1, 0.1)
		t.ok(Fixture.request(rt, player, "Admin", "energy", 1e6).ok)
		t.ok(Fixture.request(rt, player, "BuyMachine", "overclocker").ok)
		t.ok(Fixture.request(rt, player, "BuyMachine", "box_printer").ok)
		rt:run(0.5, 0.1)
		local session = Fixture.session(rt, player)
		local plot = rt:find(rt.workspace, "VoidFactory.Plots.Plot_" .. session.plot)
		rt.camera.CFrame = plot:FindFirstChild("Spawn").CFrame
		local fan = rt:findDescendant(rt:find(plot, "Machines.Pad_3"), "Fan")
		local carriage = rt:findDescendant(rt:find(plot, "Machines.Pad_2"), "Carriage")
		local fanBefore = fan:GetPivot()
		local carriageBefore = carriage:GetPivot()
		rt:run(0.5, 1 / 30)
		t.ok((fan:GetPivot().LookVector - fanBefore.LookVector).Magnitude > 0.01, "fan rotates")
		t.ok((carriage:GetPivot().Position - carriageBefore.Position).Magnitude > 0.01, "printer head slides")
		t.eq(#rt:errors(), 0, errorsText(rt))
	end)
end
