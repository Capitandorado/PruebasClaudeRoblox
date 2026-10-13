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
local Events = require(Shared.Logic.Events)
local Progression = require(Shared.Logic.Actions.Progression)
local Signal = require(Shared.Util.Signal)
local Monetization = require(Shared.Config.Monetization)
local Milestones = require(Shared.Config.Milestones)
local Rewards = require(Shared.Logic.Actions.Rewards)
local Daily = require(Shared.Logic.Actions.Daily)

local Client = script.Parent.Parent
local Store = require(Client.Core.Store)
local Remote = require(Client.Core.Remote)
local Sound = require(Client.Core.Sound)
local Box = require(Client.Controllers.Box)
local App = require(script.Parent.App)
local Goals = require(script.Parent.Goals)
local Idle = require(script.Parent.Idle)
local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)

local Hud = {}

Hud.GoalChanged = Signal.new() -- (goal) when the next-step goal changes

local Colors = Theme.Colors

Hud.selectedMachine = Machines.StarterId

local refs: { [string]: any } = {}
local displayedEnergy = 0
local badges: { [string]: Frame } = {}
local questReady = false
local questSeen = false

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

-- A small centred pill in the top stack (shards, effects, events, surge).
local function infoPill(
	bar: Frame,
	name: string,
	order: number,
	width: number,
	color: Color3,
	background: Color3?
): (Frame, TextLabel)
	local pill = C.panel({
		Name = name,
		Size = UDim2.fromOffset(width, 26),
		LayoutOrder = order,
		Visible = false,
		BackgroundColor3 = background or Colors.Panel,
		Parent = bar,
	})
	local label = C.text({
		Name = "Text",
		Text = "",
		TextSize = 14,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, -12, 1, 0),
		Position = UDim2.fromOffset(6, 0),
		Parent = pill,
	})
	return pill, label
end

local function buildTopBar(parent: Frame)
	local bar = C.new("Frame", {
		Name = "TopBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(520, 190),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	C.list(Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Center).Parent = bar
	local pill = C.panel({
		Name = "EnergyPill",
		Size = UDim2.fromOffset(300, 64),
		LayoutOrder = 1,
		Parent = bar,
	})
	refs.energyPill = pill
	C.paint(pill, Color3.fromRGB(60, 50, 110), Color3.fromRGB(28, 24, 52))
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
		FontFace = Theme.Fonts.Number,
		TextColor3 = Colors.Text,
		Size = UDim2.new(1, -64, 0, 38),
		Position = UDim2.fromOffset(54, 4),
		Parent = pill,
	})
	-- Big numbers shrink to fit instead of overflowing; the thick outline keeps them readable
	-- over any background.
	C.fitText(refs.energy, 36, 16)
	C.outline(refs.energy, Theme.Outline, 3, true)
	refs.eps = C.text({
		Name = "Eps",
		Text = "+0/s",
		FontFace = Theme.Fonts.Number,
		TextColor3 = Colors.Good,
		Size = UDim2.new(1, -64, 0, 20),
		Position = UDim2.fromOffset(56, 40),
		Parent = pill,
	})
	C.fitText(refs.eps, 18, 10)
	C.outline(refs.eps, Theme.Outline, 2, true)
	refs.boostPill, refs.boost =
		infoPill(bar, "BoostPill", 2, 360, Color3.fromRGB(255, 225, 120), Color3.fromRGB(70, 50, 10))
	refs.effectsPill, refs.effects = infoPill(bar, "EffectsPill", 3, 500, Colors.TextDim)
	refs.shardsPill, refs.shards = infoPill(bar, "ShardsPill", 4, 220, Colors.Shards)
	refs.eventPill, refs.event = infoPill(bar, "EventPill", 5, 420, Colors.Text)
	refs.visitPill, refs.visit = infoPill(bar, "VisitPill", 7, 360, Colors.Accent, Color3.fromRGB(16, 40, 60))
	refs.surgePanel, refs.surge =
		infoPill(bar, "Surge", 6, 300, Color3.fromRGB(255, 200, 255), Color3.fromRGB(60, 10, 90))
	refs.surge.FontFace = Theme.Fonts.Bold
end

-- Gold STORE button next to the Energy counter (Robux passes, boosts and codes).
local function buildStoreButton(parent: Frame)
	local holder, button, label = C.candyButton({
		name = "StoreButton",
		text = "STORE",
		icon = "🛒",
		top = Color3.fromRGB(255, 236, 110),
		bottom = Color3.fromRGB(255, 136, 20),
		size = UDim2.fromOffset(104, 68),
		position = UDim2.new(0.5, 158, 0, 6),
		textSize = 20,
		parent = parent,
		onClick = function()
			App.toggleWindow("Store")
		end,
	})
	-- Icon on top, word underneath (the button is tall and narrow).
	local icon = button:FindFirstChild("Icon") :: TextLabel
	icon.Size = UDim2.new(1, 0, 0.56, 0)
	icon.Position = UDim2.fromOffset(0, 4)
	label.Size = UDim2.new(1, -10, 0.36, 0)
	label.Position = UDim2.new(0, 5, 0.56, 0)
	Idle.breathe(holder, 0.05, 1.6)
	Idle.glint(button)
	refs.storeButton = button
end

-- "+⚡12K" rising into the counter (or "−⚡5K" dropping from it) for gains and spends that
-- are bigger than normal production ticks.
local function energyPopup(delta: number)
	local pill = refs.energyPill :: Frame?
	if not pill then
		return
	end
	local positive = delta > 0
	local label = C.text({
		Name = "EnergyPopup",
		Text = (if positive then "+⚡" else "−⚡") .. Format.number(math.abs(delta)),
		FontFace = Theme.Fonts.Bold,
		TextSize = 22,
		TextColor3 = if positive then Colors.Good else Colors.Bad,
		TextStrokeTransparency = 0.3,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, if positive then 26 else 2),
		Size = UDim2.fromOffset(260, 28),
		ZIndex = 5,
		Parent = pill,
	})
	C.tween(label, 1.1, {
		Position = UDim2.new(0.5, 0, 1, if positive then -6 else 34),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(1.15, function()
		label:Destroy()
	end)
	local bump = pill:FindFirstChild("Bump") :: UIScale?
	if not bump then
		bump = C.new("UIScale", { Name = "Bump", Parent = pill })
	end
	local scale = bump :: UIScale
	scale.Scale = if positive then 1.08 else 0.95
	C.tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
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
	-- Two columns, a little below centre: Roblox's chat window occupies the top-left corner.
	local menu = C.new("Frame", {
		Name = "Menu",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 40),
		Size = UDim2.fromOffset(150, 700),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	-- Grid that fills top-to-bottom in columns of at most five buttons (fewer on short
	-- screens, so it never runs off the bottom).
	local layout = C.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(70, 58),
		CellPadding = UDim2.fromOffset(5, 5),
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = menu,
	})
	local function fit()
		-- Height left for the menu: screen minus Roblox's top bar and a small margin.
		local available = App.designViewport().Y - 58 / App.scale() - 24
		layout.FillDirectionMaxCells = math.clamp(math.floor((available - 80 + 5) / 63), 3, 5)
	end
	fit()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end
	local function addButton(id: string, icon: string, label: string, order: number, onClick: () -> ())
		local button = C.new("TextButton", {
			Name = id .. "Button",
			Text = "",
			AutoButtonColor = false,
			Size = UDim2.fromOffset(70, 58),
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
			Size = UDim2.new(1, 0, 0, 34),
			Position = UDim2.fromOffset(0, 3),
			Parent = button,
		})
		C.text({
			Text = label,
			TextSize = 12,
			TextColor3 = Colors.TextDim,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 0, 16),
			Position = UDim2.fromOffset(0, 37),
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
		if response.ok then
			App.VisitChanged:Fire(nil)
		else
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
	local openHolder, openButton, openLabel = C.candyButton({
		name = "OpenButton",
		text = "OPEN",
		icon = "🎁",
		top = Color3.fromRGB(150, 255, 120),
		bottom = Color3.fromRGB(20, 170, 70),
		size = UDim2.fromOffset(300, 78),
		position = UDim2.new(0.5, -40, 0, 34),
		anchor = Vector2.new(0.5, 0),
		textSize = 36,
		parent = panel,
		onClick = function()
			if Box.auto then
				Box.setAuto(false)
			end
			task.spawn(Box.open, Hud.selectedMachine)
		end,
	})
	refs.openButton = openButton
	openLabel.Size = UDim2.new(1, -76, 0, 40)
	openLabel.Position = UDim2.fromOffset(64, 4)
	refs.openSub = C.text({
		Name = "Sub",
		Text = "",
		FontFace = Theme.Fonts.Number,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, -76, 0, 18),
		Position = UDim2.fromOffset(64, 44),
		ZIndex = 4,
		Parent = openButton,
	})
	C.fitText(refs.openSub, 16, 10)
	C.outline(refs.openSub, Color3.fromRGB(10, 70, 30), 2, true)
	local bar, setBar = C.progress({
		Name = "Charge",
		Size = UDim2.new(1, -84, 0, 7),
		Position = UDim2.new(0, 68, 1, -12),
		ZIndex = 4,
		Parent = openButton,
	})
	refs.chargeBar = bar
	refs.setCharge = setBar
	Idle.breathe(openHolder, 0.05, 1.8)
	Idle.glint(openButton, 3, 5.5)
	local _, autoButton = C.candyButton({
		name = "AutoButton",
		text = "AUTO\nOFF",
		top = Color3.fromRGB(140, 150, 210),
		bottom = Color3.fromRGB(64, 66, 130),
		size = UDim2.fromOffset(84, 78),
		position = UDim2.new(0.5, 118, 0, 34),
		textSize = 20,
		parent = panel,
		onClick = function()
			Box.setAuto(not Box.auto, Hud.selectedMachine)
			Sound.play("UIClick")
		end,
	})
	refs.autoButton = autoButton
	Box.AutoChanged:Connect(function(enabled)
		C.setButton(
			refs.autoButton,
			if enabled then "AUTO\nON" else "AUTO\nOFF",
			true,
			if enabled then Color3.fromRGB(60, 210, 110) else Color3.fromRGB(90, 96, 160)
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
	refs.questTracker = tracker
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

-- Goal bar: always says what to do next (UI/Goals) with progress; tapping it opens the
-- window where that happens.
local currentGoal: Goals.Goal? = nil

local function buildGoalBar(parent: Frame)
	local bar = C.new("TextButton", {
		Name = "GoalBar",
		Text = "",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -214),
		Size = UDim2.fromOffset(540, 50),
		BackgroundColor3 = Color3.fromRGB(20, 40, 70),
		BackgroundTransparency = 0.08,
		Visible = false,
		Children = { C.corner(Theme.Corner), C.stroke(Colors.Accent, 1.5, 0.35) },
		Parent = parent,
	})
	refs.goalText = C.text({
		Name = "Label",
		Text = "",
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, -24, 0, 32),
		Position = UDim2.fromOffset(12, 4),
		Parent = bar,
	})
	local progress, setProgress = C.progress({
		Name = "Progress",
		Size = UDim2.new(1, -40, 0, 6),
		Position = UDim2.new(0, 20, 1, -12),
		Parent = bar,
	})
	refs.goalProgress = progress
	refs.setGoalProgress = setProgress
	local scale = C.new("UIScale", { Parent = bar })
	bar.MouseEnter:Connect(function()
		C.tween(scale, 0.1, { Scale = 1.03 })
	end)
	bar.MouseLeave:Connect(function()
		C.tween(scale, 0.1, { Scale = 1 })
	end)
	bar.Activated:Connect(function()
		local goal = currentGoal
		if goal and goal.window then
			App.openWindow(goal.window, if goal.tab then { tab = goal.tab } else nil)
		end
	end)
	refs.tip = bar
end

local function refreshTip()
	local profile = Store.profile
	if not profile or not refs.tip then
		return
	end
	local goal = Goals.current(profile, Store.now())
	local changed = (currentGoal and currentGoal.id) ~= (goal and goal.id)
	currentGoal = goal
	local placing = refs.placementBanner ~= nil and refs.placementBanner.Visible
	refs.tip.Visible = goal ~= nil and App.currentWindow() == nil and not placing
	refs.goalText.Text = if goal then goal.text else ""
	refs.goalProgress.Visible = goal ~= nil and goal.progress ~= nil
	if goal and goal.progress then
		refs.setGoalProgress(goal.progress, if goal.progress >= 1 then Colors.Good else Colors.Accent)
	end
	if changed and goal then
		-- A small pop when the goal changes, so the player notices the new step.
		local scale = refs.tip:FindFirstChildOfClass("UIScale")
		if scale then
			scale.Scale = 0.85
			C.tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		end
		Hud.GoalChanged:Fire(goal)
	end
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
	refreshTip()
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
		C.setButton(button, "OPEN", false)
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
	local title = if Box.busy then "..." else "OPEN"
	if charges >= 1 then
		refs.openSub.Text = string.format("📦 %d/%d", charges, cap)
		C.setButton(button, title, not Box.busy)
	elseif cost > 0 then
		refs.openSub.Text = "⚡" .. Format.number(cost)
		C.setButton(button, title, not Box.busy and profile.energy >= cost)
	else
		refs.openSub.Text = "⏳ " .. Format.duration((1 - progress) * interval)
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
		questReady = false
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
	local ready = bestRatio >= 1
	if ready and not questReady and questSeen and refs.questTracker then
		-- A quest just completed: make the tracker jump so it gets claimed.
		local scale = refs.questTracker:FindFirstChildOfClass("UIScale")
			or C.new("UIScale", { Parent = refs.questTracker })
		scale.Scale = 1.12
		C.tween(scale, 0.45, { Scale = 1 }, Enum.EasingStyle.Elastic)
		Sound.play("QuestComplete")
	end
	questReady = ready
	questSeen = true
end

local function refreshBadges()
	local profile = Store.profile
	if not profile then
		return
	end
	badges.Quests.Visible = questReady or Daily.status(profile, Store.now()).available
	badges.Rebirth.Visible = profile.energy >= Rebirth.cost(profile.rebirths)
	badges.Inventory.Visible = State.freeSpace(profile) <= 0
	-- One-time buys the player can afford right now: a new machine or the next expansion.
	local canBuy = false
	for _, machine in Machines.List do
		if
			not profile.machines[machine.id]
			and profile.rebirths >= machine.rebirthRequired
			and profile.energy >= machine.cost
		then
			canBuy = true
		end
	end
	local expansionCost = State.expansionCost(profile)
	badges.Shop.Visible = canBuy or (expansionCost ~= nil and profile.energy >= expansionCost)
	local milestoneReady = false
	for _, milestone in Milestones.List do
		if Rewards.milestoneReady(profile, milestone) then
			milestoneReady = true
		end
	end
	badges.Collection.Visible = milestoneReady
end

local function refreshTop()
	local profile = Store.profile
	if not profile then
		return
	end
	local production = Store.production()
	refs.eps.Text = "+" .. Format.number(production.total) .. "/s"
	refs.shardsPill.Visible = (profile.rebirths > 0 or profile.shards > 0)
		and not refs.shardsPill:GetAttribute("HiddenByWindow")
	refs.shards.Text = string.format("💠 %s shards  •  ♻ %d", Format.number(profile.shards), profile.rebirths)
	-- Active factory effects in one readable line.
	local parts = {}
	local function pct(value: number): string
		return string.format("%d%%", math.floor(value * 100 + 0.5))
	end
	if production.globalBonus > 1e-9 then
		table.insert(parts, "🔆 Reactor +" .. pct(production.globalBonus))
	end
	if production.luckBonus > 1e-9 then
		table.insert(parts, "🍀 Luck +" .. pct(production.luckBonus))
	end
	if production.speedBonus > 1e-9 then
		table.insert(parts, "⏩ Speed +" .. pct(production.speedBonus))
	end
	if production.duplicateChance > 1e-9 then
		table.insert(parts, "✖2 " .. pct(production.duplicateChance))
	end
	local collection = State.collectionBonus(profile)
	if collection > 1e-9 then
		table.insert(parts, "📖 +" .. pct(collection))
	end
	refs.effectsPill.Visible = #parts > 0 and not refs.effectsPill:GetAttribute("HiddenByWindow")
	refs.effects.Text = table.concat(parts, "   ")
	-- Running boosts (they count down while playing).
	local boosts = {}
	for key, boost in Monetization.Boosts do
		local remaining = State.boostRemaining(profile, key)
		if remaining > 0 then
			table.insert(boosts, boost.icon .. " " .. boost.name .. " " .. Format.duration(remaining))
		end
	end
	table.sort(boosts)
	refs.boostPill.Visible = #boosts > 0 and not refs.boostPill:GetAttribute("HiddenByWindow")
	refs.boost.Text = "🚀 " .. table.concat(boosts, "   ")
end

local function refreshEvent()
	local mods = Events.current
	local now = Store.now()
	local pill = refs.eventPill
	local event = mods.active[1]
	pill.Visible = not pill:GetAttribute("HiddenByWindow")
	if event then
		refs.event.Text = string.format(
			"🎉 %s  •  %s  •  %s",
			string.upper(event.name),
			event.description,
			Format.duration(math.max(0, mods.endsAt - now))
		)
		refs.event.TextColor3 = event.color
	else
		refs.event.Text = "Next server event in " .. Format.duration(Events.nextRotatingStart(now) - now)
		refs.event.TextColor3 = Colors.TextDim
	end
end

function Hud.start()
	local root = App.layers.Hud
	buildTopBar(root)
	buildStoreButton(root)
	buildMenu(root)
	buildBoxPanel(root)
	buildQuestTracker(root)
	buildGoalBar(root)
	buildPlacementBanner(root)

	Store.watch({ "machines" }, function()
		refreshChips()
	end)
	local lastEnergy: number? = nil
	Store.watch({ "energy" }, function(changed)
		local profile = Store.profile
		if not profile then
			return
		end
		local previous = lastEnergy
		lastEnergy = profile.energy
		if changed.all or not previous then
			return -- full syncs (join, rebirth) are not gains or spends
		end
		local delta = profile.energy - previous
		if math.abs(delta) > math.max(Store.production().total * 2.5, 20) then
			energyPopup(delta)
		end
	end)
	Store.Changed:Connect(function()
		refreshTop()
		refreshQuest()
		refreshBadges()
		refreshTip()
		Hud.refreshBoxPanel()
	end)
	Box.Busy:Connect(function()
		Hud.refreshBoxPanel()
	end)
	-- While a window is open only the Energy counter and the quest tracker stay visible, so
	-- windows never overlap the box panel or the info pills.
	App.WindowChanged:Connect(function(name)
		local root = App.layers.Hud
		local hidden = name ~= nil
		for _, element in { root:FindFirstChild("BoxPanel"), root:FindFirstChild("GoalBar") } do
			if element then
				(element :: any).Visible = not hidden and (element.Name ~= "GoalBar" or currentGoal ~= nil)
			end
		end
		-- On phones a window reaches the top of the screen and would cover the quest tracker.
		local tracker = root:FindFirstChild("QuestTracker")
		if tracker then
			(tracker :: any).Visible = not (hidden and App.isNarrow())
		end
		local bar = root:FindFirstChild("TopBar")
		if bar then
			for _, pill in bar:GetChildren() do
				if pill:IsA("GuiObject") and pill.Name ~= "EnergyPill" then
					pill:SetAttribute("HiddenByWindow", hidden)
				end
			end
		end
		refreshTop()
		refreshEvent()
	end)
	App.VisitChanged:Connect(function(name)
		refs.visitPill.Visible = name ~= nil and not refs.visitPill:GetAttribute("HiddenByWindow")
		refs.visit.Text = if name then "👀 Visiting " .. name .. "'s factory  •  🏠 Home to return" else ""
	end)

	local panelClock = 0
	local eventClock = 1
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
		eventClock += dt
		if eventClock >= 1 then
			eventClock = 0
			if Events.refresh(Store.now()) then
				Store.invalidate()
				local event = Events.current.active[1]
				if event then
					App.toast("🎉 " .. event.name .. " started: " .. event.description, "success")
					Sound.play("Unlock")
				end
				Store.Changed:Fire({ events = true })
			end
			refreshEvent()
		end
		panelClock += dt
		if panelClock > 0.2 then
			panelClock = 0
			Hud.refreshBoxPanel()
			local surging = Store.isSurging()
			refs.surgePanel.Visible = surging and not refs.surgePanel:GetAttribute("HiddenByWindow")
			if surging then
				refs.surge.Text =
					string.format("🌀 VOID SURGE  •  %s", Format.duration(Store.runtime.surgeEndsAt - Store.now()))
			end
		end
	end)
end

return Hud
