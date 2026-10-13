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
		t.ok(bar.Visible and string.find(bar.Label.Text, "OPEN", 1, true) ~= nil, "step 1: " .. bar.Label.Text)
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

	t.test("feedback animations: energy popups, placement ring, window close", function()
		local rt = Fixture.server({ isStudio = true })
		local player = Fixture.join(rt, { userId = 1006, noClient = false })
		rt:run(1, 0.1)
		local ui = player.PlayerGui.VoidFactoryUI
		Fixture.request(rt, player, "Admin", "energy", 5000)
		rt:run(0.2, 0.05)
		local popup = rt:findDescendant(ui, "EnergyPopup")
		t.ok(popup ~= nil and string.find(popup.Text, "+", 1, true) ~= nil, "gain popup on the counter")
		rt:run(1.5, 0.1)
		t.eq(rt:findDescendant(ui, "EnergyPopup"), nil, "popup cleaned up")
		Fixture.request(rt, player, "Admin", "give", "prism_lens||1")
		Fixture.request(rt, player, "Place", 1, "prism_lens||1")
		rt:run(0.4, 0.05)
		t.ok(rt.workspace.FactoryPulses:FindFirstChild("PlaceWave") ~= nil, "ring when an artifact lands")
		rt:run(1, 0.1)
		t.eq(rt.workspace.FactoryPulses:FindFirstChild("PlaceWave"), nil, "ring cleaned up")
		-- The camera follows the character on a real client; put it over the plot here.
		local session = Fixture.session(rt, player)
		local spawn = rt:find(rt.workspace, "VoidFactory.Plots.Plot_" .. session.plot .. ".Spawn")
		rt.camera.CFrame = roblox.CFrame.new(spawn.Position + roblox.Vector3.new(0, 12, 0))
		local sawGain = rt:runUntil(function()
			return rt.workspace.FactoryPulses:FindFirstChild("Gain") ~= nil
		end, 5, 0.1)
		t.ok(sawGain, "floating production numbers")
		rt:click(rt:findDescendant(ui, "SettingsButton"))
		rt:run(0.3, 0.1)
		local window = rt:findDescendant(ui, "Window_Settings")
		rt:click(rt:findDescendant(window, "Close"))
		t.eq(window.Visible, true, "still visible while it shrinks away")
		rt:run(0.3, 0.05)
		t.eq(window.Visible, false, "hidden after the close animation")
		t.eq(#rt:errors(), 0, errorsText(rt))
	end)

	t.test("candy buttons: pixel outlines, compact sizes, gradient, idle pulse and glint", function()
		local rt = Fixture.server({ isStudio = true })
		local player = Fixture.join(rt, { userId = 1007, noClient = false })
		rt:run(1, 0.1)
		local ui = player.PlayerGui.VoidFactoryUI
		local open = rt:findDescendant(ui, "OpenButton")
		local rim = open:FindFirstChild("Rim")
		t.eq(rim.ApplyStrokeMode, roblox.Enum.ApplyStrokeMode.Border)
		t.ok(rim.Thickness >= 2.5, "thick outline")
		-- Every outline in the interface is in pixels and of a sane width. (ScaledSize reads
		-- Thickness as a fraction of the object's size: 3 would cover the screen.)
		for _, inst in Instance.descendants(player.PlayerGui) do
			if inst:IsA("UIStroke") then
				local scaled = inst.StrokeSizingMode == roblox.Enum.StrokeSizingMode.ScaledSize
				t.ok(
					(scaled and inst.Thickness <= 0.1) or (not scaled and inst.Thickness <= 6),
					"oversized outline on " .. inst.Parent:GetFullName()
				)
			end
		end
		-- The main buttons keep their compact footprint.
		t.eq(open.Parent.Size, roblox.UDim2.fromOffset(300, 72), "OPEN size")
		t.eq(rt:findDescendant(ui, "StoreButton").Parent.Size, roblox.UDim2.fromOffset(96, 64), "STORE size")
		t.eq(rt:findDescendant(ui, "InventoryButton").Parent.Size, roblox.UDim2.fromOffset(70, 58), "menu size")
		t.eq(open.Fill.Rotation, 90, "vertical gradient")
		t.eq(open.Label.Text, "OPEN", "short label")
		t.eq(open.Text, "", "text lives in the outlined label")
		local labelStroke = open.Label:FindFirstChildOfClass("UIStroke")
		t.eq(labelStroke.ApplyStrokeMode, roblox.Enum.ApplyStrokeMode.Contextual, "text outline")
		t.ok(open.Label:FindFirstChildOfClass("UITextSizeConstraint") ~= nil, "TextScaled with a size cap")
		-- Idle: the holder breathes between 1 and 1.05 and the glint sweeps across.
		local breathe = open.Parent:FindFirstChild("Breathe")
		local biggest = 1
		local sweptGlint = false
		for _ = 1, 80 do
			rt:run(0.1, 0.05)
			biggest = math.max(biggest, breathe.Scale)
			if open.Glint.UIGradient.Offset.X > -0.99 then
				sweptGlint = true
			end
		end
		t.ok(biggest > 1.03 and biggest <= 1.0501, "breathes up to 1.05 (" .. biggest .. ")")
		t.ok(sweptGlint, "the glint passed over the button")
		local store = rt:findDescendant(ui, "StoreButton")
		t.ok(store.Parent:FindFirstChild("Breathe") ~= nil, "STORE breathes too")
		t.eq(#rt:errors(), 0, errorsText(rt))
	end)

	t.test("floating production popups reuse a small pool of billboards", function()
		local rt = Fixture.server({ isStudio = true })
		local player = Fixture.join(rt, { userId = 1008, noClient = false })
		rt:run(1, 0.1)
		for slot, key in { "ion_battery||1", "scrap_cube||1", "glow_shard||1" } do
			Fixture.request(rt, player, "Admin", "give", key)
			Fixture.request(rt, player, "Place", slot, key)
		end
		local session = Fixture.session(rt, player)
		local spawn = rt:find(rt.workspace, "VoidFactory.Plots.Plot_" .. session.plot .. ".Spawn")
		rt.camera.CFrame = roblox.CFrame.new(spawn.Position + roblox.Vector3.new(0, 12, 0))
		local most = 0
		local sample = nil
		for _ = 1, 100 do
			rt:run(0.1, 0.05)
			local enabled = 0
			for _, child in rt.workspace.FactoryPulses:GetChildren() do
				if child.Name == "Gain" and child.Enabled then
					enabled += 1
					sample = child
				end
			end
			most = math.max(most, enabled)
		end
		t.ok(most >= 3, "a popup per producing pedestal (" .. most .. ")")
		local total = 0
		for _, child in rt.workspace.FactoryPulses:GetChildren() do
			if child.Name == "Gain" then
				total += 1
			end
		end
		t.ok(total <= 8, "pooled: " .. total .. " billboards after 10 seconds")
		t.ok(sample ~= nil and string.find(sample.Text.Text, "⚡", 1, true) ~= nil, "format +X ⚡")
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
