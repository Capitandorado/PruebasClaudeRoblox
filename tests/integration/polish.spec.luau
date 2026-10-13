-- Phase 5: mobile layout, onboarding and UI efficiency.

local Fixture = require("../lib/Fixture")
local roblox = require("@lune/roblox")
local Instance = require("../mock/Instance")

local function errorsText(rt)
	local lines = {}
	for _, err in rt:errors() do
		table.insert(lines, err.trace)
	end
	return table.concat(lines, "\n")
end

return function(t)
	t.test("phone-sized screens scale the UI and wrap the menu into columns", function()
		local rt = Fixture.server({ isStudio = true })
		local player = Fixture.join(rt, { userId = 1001, noClient = false })
		rt:run(1, 0.1)
		local ui = player.PlayerGui.VoidFactoryUI
		local menu = rt:findDescendant(ui, "Menu")
		local grid = menu:FindFirstChildOfClass("UIGridLayout")
		local desktopCells = grid.FillDirectionMaxCells
		t.eq(desktopCells, 5, "two columns of five on a 1280x720 screen")
		local playerListOn = rt:asClient(player, function()
			return game:GetService("StarterGui"):GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList)
		end)
		t.eq(playerListOn, false, "Roblox's player list is hidden (it would cover the quest tracker)")
		-- Rotate to a small phone in landscape.
		Instance.setInternal(rt.camera, "ViewportSize", roblox.Vector2.new(812, 375))
		rt:run(0.2, 0.1)
		local scale = ui:FindFirstChildOfClass("UIScale").Scale
		t.near(scale, 0.55, 1e-6, "UI scaled down for the phone")
		t.ok(
			grid.FillDirectionMaxCells <= 5,
			"menu wraps on the phone (" .. grid.FillDirectionMaxCells .. " per column)"
		)
		local buttons = 0
		for _, child in menu:GetChildren() do
			if child:IsA("TextButton") and child.Visible then
				buttons += 1
			end
		end
		local columns = math.ceil(buttons / grid.FillDirectionMaxCells)
		local designHeight = 375 / scale
		local usedHeight = grid.FillDirectionMaxCells * 68
		t.ok(usedHeight <= designHeight - 58, "menu fits vertically (" .. usedHeight .. " <= " .. designHeight .. ")")
		t.ok(columns <= 2, "at most two columns")
		t.eq(#rt:errors(), 0, errorsText(rt))
	end)

	t.test("a player falling into the void is caught by their own client", function()
		local rt = Fixture.server({ isStudio = true })
		local player = Fixture.join(rt, { userId = 1005, noClient = false })
		rt:run(1, 0.1)
		local session = Fixture.session(rt, player)
		local spawn = rt:find(rt.workspace, "VoidFactory.Plots.Plot_" .. session.plot .. ".Spawn")
		local rootPart = player.Character.HumanoidRootPart
		rootPart.AssemblyLinearVelocity = roblox.Vector3.new(0, -180, 0)
		player.Character:PivotTo(roblox.CFrame.new(0, -50, 0)) -- above the server's rescue level
		rt:run(0.5, 0.05)
		t.ok((rootPart.Position - spawn.Position).Magnitude < 8, "back on the spawn pad")
		t.eq(rootPart.AssemblyLinearVelocity.Magnitude, 0, "fall speed cancelled")
		t.eq(#rt:errors(), 0, errorsText(rt))
	end)

	t.test("the goal bar walks a new player through the game and points at what to press", function()
		local rt = Fixture.server({ isStudio = true })
		local player = Fixture.join(rt, { userId = 1002, noClient = false })
		rt:run(1, 0.1)
		local ui = player.PlayerGui.VoidFactoryUI
		local bar = rt:findDescendant(ui, "GoalBar")
		local function glowOn(name)
			return rt:findDescendant(ui, name):FindFirstChild("GuideGlow") ~= nil
		end
		t.ok(bar.Visible and string.find(bar.Label.Text, "OPEN BOX", 1, true) ~= nil, "step 1: " .. bar.Label.Text)
		t.ok(glowOn("OpenButton"), "OPEN BOX glows")
		local opened = Fixture.request(rt, player, "OpenBox", "starter_fabricator")
		rt:run(0.5, 0.1)
		t.ok(string.find(bar.Label.Text, "Place it", 1, true) ~= nil, "step 2: " .. bar.Label.Text)
		t.ok(not glowOn("OpenButton"), "previous glow removed")
		local arrow = rt.workspace:FindFirstChild("GuideArrow")
		t.ok(arrow ~= nil and arrow.Adornee ~= nil, "arrow over an empty pedestal")
		Fixture.request(rt, player, "Place", 1, opened.data.grants[1].key)
		rt:run(0.5, 0.1)
		t.eq(rt.workspace:FindFirstChild("GuideArrow"), nil, "arrow gone once placed")
		t.ok(string.find(bar.Label.Text, "Box Printer", 1, true) ~= nil, "step 3: " .. bar.Label.Text)
		t.ok(bar.Progress.Visible, "progress toward the price")
		Fixture.request(rt, player, "Admin", "energy", 1e5)
		rt:run(0.5, 0.1)
		t.ok(string.find(bar.Label.Text, "afford", 1, true) ~= nil, "affordable: " .. bar.Label.Text)
		t.ok(glowOn("ShopButton"), "Machines button glows")
		rt:click(bar)
		rt:run(0.3, 0.1)
		t.eq(rt:findDescendant(ui, "Window_Shop").Visible, true, "tapping the bar opens the shop")
		t.eq(bar.Visible, false, "hidden while a window is open")
		rt:click(rt:findDescendant(rt:findDescendant(ui, "Window_Shop"), "Close"))
		Fixture.request(rt, player, "BuyMachine", "box_printer")
		rt:run(0.5, 0.1)
		t.ok(string.find(bar.Label.Text, "Expand", 1, true) ~= nil, "next goal: " .. bar.Label.Text)
		t.eq(#rt:errors(), 0, errorsText(rt))
	end)

	t.test("the shop window is not rebuilt every second when nothing changes", function()
		local rt = Fixture.server({ isStudio = true })
		local player = Fixture.join(rt, { userId = 1003, noClient = false })
		rt:run(1, 0.1)
		Fixture.request(rt, player, "Admin", "give", "ion_battery||1")
		Fixture.request(rt, player, "Place", 1, "ion_battery||1")
		local ui = player.PlayerGui.VoidFactoryUI
		rt:click(rt:findDescendant(ui, "ShopButton"))
		rt:run(0.5, 0.1)
		local shop = rt:findDescendant(ui, "Window_Shop")
		local row = rt:findDescendant(shop, "box_printer")
		rt:run(5, 0.25) -- Energy ticks every second, nothing affordable changes
		t.ok(rt:findDescendant(shop, "box_printer") == row, "same row instance kept")
		Fixture.request(rt, player, "Admin", "energy", 1e5)
		rt:run(0.5, 0.1)
		t.ok(rt:findDescendant(shop, "box_printer") ~= row, "rebuilt once the printer became affordable")
		t.eq(#rt:errors(), 0, errorsText(rt))
	end)

	t.test("the inventory grid only rebuilds the cards that changed", function()
		local rt = Fixture.server({ isStudio = true })
		local player = Fixture.join(rt, { userId = 1004, noClient = false })
		rt:run(1, 0.1)
		Fixture.request(rt, player, "Admin", "give", "ion_battery||1")
		Fixture.request(rt, player, "Admin", "give", "scrap_cube||1")
		local ui = player.PlayerGui.VoidFactoryUI
		rt:click(rt:findDescendant(ui, "InventoryButton"))
		rt:run(1, 0.1)
		local window = rt:findDescendant(ui, "Window_Inventory")
		local grid = rt:findDescendant(window, "Grid")
		local battery = grid:FindFirstChild("ion_battery||1")
		local cube = grid:FindFirstChild("scrap_cube||1")
		t.ok(battery and cube, "both cards shown")
		Fixture.request(rt, player, "Admin", "give", "scrap_cube||1")
		Fixture.request(rt, player, "Admin", "give", "prism_lens||1")
		rt:run(1, 0.1)
		t.ok(grid:FindFirstChild("ion_battery||1") == battery, "unchanged card kept")
		local newCube = grid:FindFirstChild("scrap_cube||1")
		t.ok(newCube ~= cube and newCube.CountBadge.Count.Text == "x2", "changed count rebuilt")
		t.ok(grid:FindFirstChild("prism_lens||1") ~= nil, "new item added")
		Fixture.request(rt, player, "Sell", "ion_battery||1", 1)
		rt:run(1, 0.1)
		t.ok(grid:FindFirstChild("ion_battery||1") == nil, "sold item removed")
		rt:click(grid:FindFirstChild("prism_lens||1"))
		rt:run(0.2, 0.1)
		local cards = 0
		for _, child in grid:GetChildren() do
			if child:IsA("TextButton") then
				cards += 1
			end
		end
		t.eq(cards, 2, "no duplicate cards after selecting")
		t.ok(grid:FindFirstChild("scrap_cube||1") == newCube, "selection only rebuilds the cards involved")
		t.eq(#rt:errors(), 0, errorsText(rt))
	end)
end
