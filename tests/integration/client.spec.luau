-- End-to-end tests with the real client scripts: UI buttons -> remotes -> server -> UI.

local Fixture = require("../lib/Fixture")

local function errorsText(rt)
	local lines = {}
	for _, err in rt:errors() do
		table.insert(lines, err.trace)
	end
	return table.concat(lines, "\n")
end

local function gui(rt, player)
	return player:FindFirstChild("PlayerGui"):FindFirstChild("VoidFactoryUI")
end

local function clientModule(rt, player, path)
	local target = player:FindFirstChild("PlayerScripts"):FindFirstChild("Client")
	for name in string.gmatch(path, "[^%.]+") do
		target = target:FindFirstChild(name)
	end
	return rt:requireIn(player, target)
end

return function(t)
	t.test("client boots, shows the HUD and syncs Energy", function()
		local rt = Fixture.server({ isStudio = true })
		local player = Fixture.join(rt, { userId = 301, noClient = false })
		rt:run(3, 0.1)
		t.eq(#rt:errors(), 0, errorsText(rt))
		local ui = gui(rt, player)
		t.ok(ui ~= nil, "ScreenGui created")
		local energy = rt:findDescendant(ui, "Energy")
		t.ok(energy ~= nil and energy:IsA("TextLabel"), "energy label")
		local store = clientModule(rt, player, "Core.Store")
		t.ok(store.ready, "store synced")
		t.eq(store.plot, Fixture.session(rt, player).plot)
	end)

	t.test("OPEN BOX button opens a box and plays the reveal", function()
		local rt = Fixture.server({ isStudio = true })
		local player = Fixture.join(rt, { userId = 302, noClient = false })
		rt:run(1, 0.1)
		local session = Fixture.session(rt, player)
		local button = rt:findDescendant(gui(rt, player), "OpenButton")
		t.ok(button ~= nil, "open button")
		rt:click(button)
		rt:run(6, 1 / 30)
		t.eq(session.profile.stats.boxesOpened, 1, "server opened one box")
		t.eq(#rt:errors(), 0, errorsText(rt))
		-- The client mirror received the new item.
		local store = clientModule(rt, player, "Core.Store")
		local count = 0
		for _, amount in store.profile.inventory do
			count += amount
		end
		t.eq(count, 1)
		-- The reveal cleaned up after itself.
		local effects = rt.workspace:FindFirstChild("ClientEffects")
		t.ok(effects == nil or #effects:GetChildren() == 0, "reveal effects removed")
	end)

	t.test("inventory -> place mode -> pedestal tap places the artifact", function()
		local rt = Fixture.server({ isStudio = true })
		local player = Fixture.join(rt, { userId = 303, noClient = false })
		rt:run(1, 0.1)
		local session = Fixture.session(rt, player)
		session.profile.inventory["reactor_core||1"] = 1
		local sessions = rt:requireIn("server", rt.services.ServerScriptService.Server.Services.Sessions)
		rt:asServer(function()
			sessions.replicate(session)
		end)
		rt:run(0.5, 0.1)
		local ui = gui(rt, player)
		rt:click(rt:findDescendant(ui, "InventoryButton"))
		rt:run(0.5, 0.1)
		local window = rt:findDescendant(ui, "Window_Inventory")
		t.ok(window ~= nil and window.Visible, "inventory window open")
		local card = rt:findDescendant(window, "reactor_core||1")
		t.ok(card ~= nil, "item card listed")
		rt:click(card)
		rt:run(0.2, 0.1)
		rt:click(rt:findDescendant(window, "Place"))
		rt:run(0.2, 0.1)
		local placement = clientModule(rt, player, "Controllers.Placement")
		t.eq(placement.activeKey, "reactor_core||1", "placement mode active")
		local plotModel = rt:find(rt.workspace, "VoidFactory.Plots.Plot_" .. session.plot)
		local hitbox = rt:find(plotModel, "Slots.Slot_2.Hitbox")
		rt:asClient(player, function()
			placement.handlePedestal(hitbox)
		end)
		rt:run(0.5, 0.1)
		t.eq(session.profile.placed["2"], "reactor_core||1", "server placed it")
		t.ok(rt:find(plotModel, "Slots.Slot_2.Artifact") ~= nil, "model on pedestal")
		t.eq(placement.activeKey, nil, "placement mode ended")
		t.eq(#rt:errors(), 0, errorsText(rt))
	end)

	t.test("every window opens and renders without errors", function()
		local rt = Fixture.server({ isStudio = true })
		local player = Fixture.join(rt, { userId = 304, noClient = false })
		rt:run(1, 0.1)
		local ui = gui(rt, player)
		for _, name in
			{ "Inventory", "Collection", "Shop", "Upgrades", "Quests", "Rebirth", "Leaderboard", "Settings", "Admin" }
		do
			rt:click(rt:findDescendant(ui, name .. "Button"))
			rt:run(0.4, 0.1)
			local window = rt:findDescendant(ui, "Window_" .. name)
			t.ok(window ~= nil and window.Visible, name .. " window visible")
		end
		-- Tabs inside windows.
		rt:click(rt:findDescendant(ui, "CollectionButton"))
		rt:run(0.2, 0.1)
		rt:click(rt:findDescendant(rt:findDescendant(ui, "Window_Collection"), "OddsTab"))
		rt:run(0.2, 0.1)
		t.ok(rt:findDescendant(rt:findDescendant(ui, "Window_Collection"), "Note") ~= nil, "odds table rendered")
		t.eq(#rt:errors(), 0, errorsText(rt))
	end)

	t.test("buying from the shop window and the debug panel", function()
		local rt = Fixture.server({ isStudio = true })
		local player = Fixture.join(rt, { userId = 305, noClient = false })
		rt:run(1, 0.1)
		local session = Fixture.session(rt, player)
		local ui = gui(rt, player)
		rt:click(rt:findDescendant(ui, "AdminButton"))
		rt:run(0.3, 0.1)
		local admin = rt:findDescendant(ui, "Window_Admin")
		rt:click(rt:findDescendant(admin, "energy2"))
		rt:run(0.5, 0.1)
		t.eq(session.profile.energy >= 100000, true, "debug energy granted")
		rt:click(rt:findDescendant(ui, "ShopButton"))
		rt:run(0.5, 0.1)
		local shop = rt:findDescendant(ui, "Window_Shop")
		local row = rt:findDescendant(shop, "box_printer")
		rt:click(rt:findDescendant(row, "Action"))
		rt:run(0.5, 0.1)
		t.ok(session.profile.machines.box_printer ~= nil, "printer bought through the UI")
		t.eq(#rt:errors(), 0, errorsText(rt))
	end)

	t.test("auto-open keeps opening while charges last", function()
		local rt = Fixture.server({ isStudio = true })
		local player = Fixture.join(rt, { userId = 306, noClient = false })
		rt:run(1, 0.1)
		local session = Fixture.session(rt, player)
		rt:click(rt:findDescendant(gui(rt, player), "AutoButton"))
		rt:run(30, 1 / 20)
		t.ok(session.profile.stats.boxesOpened >= 5, "opened " .. session.profile.stats.boxesOpened .. " boxes")
		t.eq(#rt:errors(), 0, errorsText(rt))
	end)
end
