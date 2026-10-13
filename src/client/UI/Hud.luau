-- Always-visible HUD: Energy counter, production, menu, box panel and quest tracker.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Machines = require(Shared.Config.Machines)
local Quests = require(Shared.Config.Quests)
local Rebirth = require(Shared.Config.Rebirth)
local Format = require(Shared.Util.Format)
local State = require(Shared.Logic.State)
local Progression = require(Shared.Logic.Actions.Progression)

local Client = script.Parent.Parent
local Store = require(Client.Core.Store)
local Remote = require(Client.Core.Remote)
local Sound = require(Client.Core.Sound)
local Box = require(Client.Controllers.Box)
local App = require(script.Parent.App)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)

local Hud = {}

local Colors = Theme.Colors

Hud.selectedMachine = Machines.StarterId

local refs: { [string]: any } = {}
local displayedEnergy = 0
local badges: { [string]: Frame } = {}

local MENU = {
	{ id = "Inventory", icon = "🎒", label = "Items" },
	{ id = "Collection", icon = "📖", label = "Collection" },
	{ id = "Shop", icon = "🏭", label = "Machines" },
	{ id = "Upgrades", icon = "⬆️", label = "Upgrades" },
	{ id = "Quests", icon = "📜", label = "Quests" },
	{ id = "Rebirth", icon = "♻️", label = "Rebirth" },
	{ id = "Leaderboard", icon = "🏆", label = "Ranks" },
	{ id = "Settings", icon = "⚙️", label = "Settings" },
}

local function buildTopBar(parent: Frame)
	local bar = C.new("Frame", {
		Name = "TopBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(420, 96),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local pill = C.panel({
		Name = "EnergyPill",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(300, 64),
		Parent = bar,
	})
	C.gradient(Color3.fromRGB(60, 50, 110), Color3.fromRGB(28, 24, 52)).Parent = pill
	C.text({
		Name = "Icon",
		Text = "⚡",
		TextSize = 34,
		TextColor3 = Colors.Energy,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromOffset(54, 64),
		Parent = pill,
	})
	refs.energy = C.text({
		Name = "Energy",
		Text = "0",
		FontFace = Theme.Fonts.Bold,
		TextSize = 32,
		TextColor3 = Colors.Text,
		Size = UDim2.new(1, -64, 0, 38),
		Position = UDim2.fromOffset(54, 4),
		Parent = pill,
	})
	refs.eps = C.text({
		Name = "Eps",
		Text = "+0/s",
		TextSize = 17,
		TextColor3 = Colors.Good,
		Size = UDim2.new(1, -64, 0, 20),
		Position = UDim2.fromOffset(56, 40),
		Parent = pill,
	})
	local shards = C.panel({
		Name = "ShardsPill",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 68),
		Size = UDim2.fromOffset(170, 26),
		Visible = false,
		Parent = bar,
	})
	refs.shards = C.text({
		Name = "Text",
		Text = "",
		TextSize = 15,
		TextColor3 = Colors.Shards,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = shards,
	})
	refs.shardsPill = shards
	local surge = C.panel({
		Name = "Surge",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 100),
		Size = UDim2.fromOffset(300, 34),
		BackgroundColor3 = Color3.fromRGB(60, 10, 90),
		Visible = false,
		Parent = bar,
	})
	refs.surge = C.text({
		Name = "Text",
		Text = "",
		TextSize = 18,
		FontFace = Theme.Fonts.Bold,
		TextColor3 = Color3.fromRGB(255, 200, 255),
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = surge,
	})
	refs.surgePanel = surge
end

local function badge(button: Instance): Frame
	return C.new("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = Colors.Bad,
		Visible = false,
		Children = { C.corner(7) },
		Parent = button,
	})
end

local function buildMenu(parent: Frame)
	local menu = C.new("Frame", {
		Name = "Menu",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(76, 600),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local layout = C.list(Enum.FillDirection.Vertical, 6)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = menu
	local function addButton(id: string, icon: string, label: string, order: number, onClick: () -> ())
		local button = C.new("TextButton", {
			Name = id .. "Button",
			Text = "",
			AutoButtonColor = false,
			Size = UDim2.fromOffset(72, 62),
			BackgroundColor3 = Colors.Panel,
			BackgroundTransparency = 0.1,
			LayoutOrder = order,
			Children = { C.corner(Theme.SmallCorner), C.stroke() },
			Parent = menu,
		})
		C.text({
			Text = icon,
			TextSize = 26,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 0, 36),
			Position = UDim2.fromOffset(0, 4),
			Parent = button,
		})
		C.text({
			Text = label,
			TextSize = 12,
			TextColor3 = Colors.TextDim,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 0, 16),
			Position = UDim2.fromOffset(0, 40),
			Parent = button,
		})
		local scale = C.new("UIScale", { Parent = button })
		button.MouseEnter:Connect(function()
			C.tween(scale, 0.1, { Scale = 1.06 })
		end)
		button.MouseLeave:Connect(function()
			C.tween(scale, 0.1, { Scale = 1 })
		end)
		button.Activated:Connect(onClick)
		badges[id] = badge(button)
		return button
	end
	for order, entry in MENU do
		addButton(entry.id, entry.icon, entry.label, order, function()
			App.toggleWindow(entry.id)
		end)
	end
	addButton("Home", "🏠", "Home", #MENU + 1, function()
		local response = Remote.request("GoHome")
		if not response.ok then
			App.showError(response.err)
		end
	end)
	local adminButton = addButton("Admin", "🛠️", "Debug", #MENU + 2, function()
		App.toggleWindow("Admin")
	end)
	local player = Players.LocalPlayer
	adminButton.Visible = player:GetAttribute("IsAdmin") == true
	player:GetAttributeChangedSignal("IsAdmin"):Connect(function()
		adminButton.Visible = player:GetAttribute("IsAdmin") == true
	end)
end

local function ownedFabricators(): { Machines.Machine }
	local list = {}
	local profile = Store.profile
	if not profile then
		return list
	end
	for _, machine in Machines.List do
		if machine.kind == "fabricator" and profile.machines[machine.id] then
			table.insert(list, machine)
		end
	end
	return list
end

local function refreshChips()
	local chips = refs.chips :: Frame
	C.clear(chips, true)
	local owned = ownedFabricators()
	local found = false
	for _, machine in owned do
		if machine.id == Hud.selectedMachine then
			found = true
		end
	end
	if not found then
		Hud.selectedMachine = Machines.StarterId
	end
	for order, machine in owned do
		local selected = machine.id == Hud.selectedMachine
		C.button({
			name = machine.id,
			text = machine.name,
			color = if selected then machine.color:Lerp(Color3.new(0, 0, 0), 0.25) else Colors.PanelLight,
			size = UDim2.fromOffset(140, 30),
			textSize = 14,
			layoutOrder = order,
			parent = chips,
			onClick = function()
				Hud.selectedMachine = machine.id
				if Box.auto then
					Box.autoMachine = machine.id
				end
				Sound.play("UIClick")
				refreshChips()
				Hud.refreshBoxPanel()
			end,
		})
	end
	chips.Visible = #owned > 1
end

local function buildBoxPanel(parent: Frame)
	local panel = C.new("Frame", {
		Name = "BoxPanel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(460, 140),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local chips = C.new("Frame", {
		Name = "Chips",
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	local chipLayout = C.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center)
	chipLayout.Parent = chips
	refs.chips = chips
	refs.openButton = C.button({
		name = "OpenButton",
		text = "OPEN BOX",
		color = Colors.Accent2,
		size = UDim2.fromOffset(300, 72),
		position = UDim2.new(0.5, -40, 0, 38),
		anchor = Vector2.new(0.5, 0),
		textSize = 26,
		parent = panel,
		onClick = function()
			if Box.auto then
				Box.setAuto(false)
			end
			task.spawn(Box.open, Hud.selectedMachine)
		end,
	})
	refs.openButton.TextYAlignment = Enum.TextYAlignment.Top
	C.padding(8).Parent = refs.openButton
	refs.openSub = C.text({
		Name = "Sub",
		Text = "",
		TextSize = 15,
		TextColor3 = Color3.fromRGB(235, 225, 255),
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.new(0, 0, 1, -34),
		Parent = refs.openButton,
	})
	local bar, setBar = C.progress({
		Name = "Charge",
		Size = UDim2.new(1, -20, 0, 8),
		Position = UDim2.new(0, 10, 1, -12),
		Parent = refs.openButton,
	})
	refs.chargeBar = bar
	refs.setCharge = setBar
	refs.autoButton = C.button({
		name = "AutoButton",
		text = "AUTO\nOFF",
		color = Colors.PanelLight,
		size = UDim2.fromOffset(84, 72),
		position = UDim2.new(0.5, 118, 0, 38),
		textSize = 17,
		parent = panel,
		onClick = function()
			Box.setAuto(not Box.auto, Hud.selectedMachine)
			Sound.play("UIClick")
		end,
	})
	Box.AutoChanged:Connect(function(enabled)
		C.setButton(
			refs.autoButton,
			if enabled then "AUTO\nON" else "AUTO\nOFF",
			true,
			if enabled then Colors.Good else Colors.PanelLight
		)
	end)
end

local function buildQuestTracker(parent: Frame)
	local tracker = C.new("TextButton", {
		Name = "QuestTracker",
		Text = "",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 10),
		Size = UDim2.fromOffset(280, 96),
		BackgroundColor3 = Colors.Panel,
		BackgroundTransparency = 0.15,
		Children = { C.corner(), C.stroke() },
		Parent = parent,
	})
	C.padding(10).Parent = tracker
	C.text({
		Text = "📜 QUEST",
		TextSize = 13,
		TextColor3 = Colors.TextDim,
		Size = UDim2.new(1, 0, 0, 16),
		Parent = tracker,
	})
	refs.questText = C.text({
		Name = "QuestText",
		Text = "",
		TextSize = 16,
		Size = UDim2.new(1, 0, 0, 36),
		Position = UDim2.fromOffset(0, 18),
		Parent = tracker,
	})
	local bar, setBar =
		C.progress({ Size = UDim2.new(1, 0, 0, 10), Position = UDim2.new(0, 0, 1, -14), Parent = tracker })
	refs.questBar = bar
	refs.setQuest = setBar
	tracker.Activated:Connect(function()
		App.toggleWindow("Quests")
	end)
end

local function buildPlacementBanner(parent: Frame)
	local banner = C.panel({
		Name = "PlacementBanner",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -160),
		Size = UDim2.fromOffset(440, 54),
		Visible = false,
		Parent = parent,
	})
	refs.placementText = C.text({
		Name = "Text",
		Text = "",
		TextSize = 16,
		Size = UDim2.new(1, -120, 1, 0),
		Position = UDim2.fromOffset(14, 0),
		Parent = banner,
	})
	refs.placementCancel = C.button({
		name = "Cancel",
		text = "Cancel",
		color = Colors.Bad,
		size = UDim2.fromOffset(96, 36),
		position = UDim2.new(1, -106, 0.5, -18),
		textSize = 16,
		parent = banner,
	})
	refs.placementBanner = banner
end

-- Placement mode banner (driven by the Placement controller).
function Hud.showPlacement(text: string?, onCancel: (() -> ())?)
	local banner = refs.placementBanner
	if not banner then
		return
	end
	banner.Visible = text ~= nil
	refs.placementText.Text = text or ""
	if refs.placementConnection then
		refs.placementConnection:Disconnect()
		refs.placementConnection = nil
	end
	if onCancel then
		refs.placementConnection = refs.placementCancel.Activated:Connect(onCancel)
	end
end

function Hud.refreshBoxPanel()
	local profile = Store.profile
	local button = refs.openButton
	if not profile or not button then
		return
	end
	local machineId = Hud.selectedMachine
	local production = Store.production()
	local state = profile.machines[machineId]
	if not state then
		C.setButton(button, "OPEN BOX", false)
		return
	end
	local cap = State.chargeCap(profile, machineId)
	local interval = State.chargeInterval(profile, machineId, production)
	local cost = State.boxCost(profile, machineId)
	-- Local estimate of charges between server updates (same formula as the server).
	local charges = state.charges
	local progress = 0
	if cap > 0 and interval > 0 then
		local elapsed = math.max(0, Store.now() - state.chargeAt)
		charges = math.min(cap, state.charges + math.floor(elapsed / interval))
		progress = if charges >= cap then 1 else (elapsed % interval) / interval
	end
	local title = if Box.busy then "OPENING..." else "OPEN BOX"
	if charges >= 1 then
		refs.openSub.Text = string.format("%d/%d ready", charges, cap)
		C.setButton(button, title, not Box.busy)
	elseif cost > 0 then
		refs.openSub.Text = "⚡ " .. Format.number(cost) .. " per box"
		C.setButton(button, title, not Box.busy and profile.energy >= cost)
	else
		refs.openSub.Text = string.format("Next box in %s", Format.duration((1 - progress) * interval))
		C.setButton(button, title, false)
	end
	refs.chargeBar.Visible = cap > 0
	refs.setCharge(progress, if charges >= cap then Colors.Good else Colors.Accent)
end

local function refreshQuest()
	local profile = Store.profile
	if not profile then
		return
	end
	local best, bestRatio = nil, -1
	for _, questState in profile.quests.active do
		local ratio = Progression.questProgress(profile, questState) / questState.target
		if ratio > bestRatio then
			best, bestRatio = questState, ratio
		end
	end
	if not best then
		refs.questText.Text = "No quests"
		refs.setQuest(0)
		return
	end
	local def = Quests.ById[best.id]
	local target = if def and def.stat == "energyEarned" then Format.number(best.target) else best.target
	local text = if def then string.format(def.text, target) else best.id
	local progress = math.min(Progression.questProgress(profile, best), best.target)
	if bestRatio >= 1 then
		refs.questText.Text = "✅ " .. text .. " — claim!"
		refs.setQuest(1, Colors.Good)
	else
		refs.questText.Text = text .. string.format("  (%s/%s)", Format.number(progress), Format.number(best.target))
		refs.setQuest(bestRatio, Colors.Accent)
	end
	badges.Quests.Visible = bestRatio >= 1
end

local function refreshBadges()
	local profile = Store.profile
	if not profile then
		return
	end
	badges.Rebirth.Visible = profile.energy >= Rebirth.cost(profile.rebirths)
	badges.Inventory.Visible = State.freeSpace(profile) <= 0
end

local function refreshTop()
	local profile = Store.profile
	if not profile then
		return
	end
	local production = Store.production()
	refs.eps.Text = "+" .. Format.number(production.total) .. "/s"
	refs.shardsPill.Visible = profile.rebirths > 0 or profile.shards > 0
	refs.shards.Text = string.format("💠 %s shards  •  ♻ %d", Format.number(profile.shards), profile.rebirths)
end

function Hud.start()
	local root = App.layers.Hud
	buildTopBar(root)
	buildMenu(root)
	buildBoxPanel(root)
	buildQuestTracker(root)
	buildPlacementBanner(root)

	Store.watch({ "machines" }, function()
		refreshChips()
	end)
	Store.Changed:Connect(function()
		refreshTop()
		refreshQuest()
		refreshBadges()
		Hud.refreshBoxPanel()
	end)
	Box.Busy:Connect(function()
		Hud.refreshBoxPanel()
	end)

	local panelClock = 0
	RunService.RenderStepped:Connect(function(dt)
		local profile = Store.profile
		if not profile then
			return
		end
		-- Smoothly count toward the extrapolated Energy between server ticks.
		local production = Store.production()
		local since = math.min(os.clock() - Store.energyStamp, 1.2)
		local target = profile.energy + production.total * since
		if math.abs(target - displayedEnergy) > target * 0.5 + 1000 then
			displayedEnergy = target
		else
			displayedEnergy += (target - displayedEnergy) * math.min(1, dt * 10)
		end
		refs.energy.Text = Format.number(displayedEnergy)
		panelClock += dt
		if panelClock > 0.2 then
			panelClock = 0
			Hud.refreshBoxPanel()
			local surging = Store.isSurging()
			refs.surgePanel.Visible = surging
			if surging then
				refs.surge.Text =
					string.format("🌀 VOID SURGE  •  %s", Format.duration(Store.runtime.surgeEndsAt - Store.now()))
			end
		end
	end)
end

return Hud
