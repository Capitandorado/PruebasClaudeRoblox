-- Rewards on join: the "welcome back" summary of offline progress and a one-time reminder
-- when the daily reward is ready (opens Quests → Daily for returning players).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Rarities = require(Shared.Config.Rarities)
local Format = require(Shared.Util.Format)
local Items = require(Shared.Logic.Items)
local Daily = require(Shared.Logic.Actions.Daily)

local Client = script.Parent.Parent
local Remote = require(Client.Core.Remote)
local Store = require(Client.Core.Store)
local Sound = require(Client.Core.Sound)
local App = require(Client.UI.App)
local Theme = require(Client.UI.Theme)
local C = require(Client.UI.Components)

local Colors = Theme.Colors

local Rewards = {}

local dailyReminded = false

-- Returning players (not someone on their very first minutes) get the daily window once.
local function remindDaily()
	if dailyReminded then
		return
	end
	local profile = Store.profile
	if not profile then
		return
	end
	local returning = profile.daily.claims > 0 or profile.rebirths > 0 or profile.stats.boxesOpened >= 10
	if not returning or not Daily.status(profile, Store.now()).available then
		return
	end
	dailyReminded = true
	task.delay(1, function()
		if App.currentWindow() == nil then
			App.openWindow("Quests", { tab = "Daily" })
		end
	end)
end

-- "Scrap Cube x2 (Common), Glow Shard (Common, NEW)"
local function itemLine(items: { any }): string
	local order, counts, isNew = {}, {}, {}
	for _, entry in items do
		if not counts[entry.key] then
			table.insert(order, entry.key)
			counts[entry.key] = 0
		end
		counts[entry.key] += 1
		isNew[entry.key] = isNew[entry.key] or entry.newArtifact == true
	end
	local names = {}
	for _, key in order do
		local item = Items.parse(key)
		if item then
			local rarity = Rarities.get(Items.rarityOf(item))
			table.insert(
				names,
				Items.displayName(item)
					.. (if counts[key] > 1 then " x" .. counts[key] else "")
					.. " ("
					.. (if rarity then rarity.id else "?")
					.. (if isNew[key] then ", NEW" else "")
					.. ")"
			)
		end
	end
	return table.concat(names, ", ")
end

function Rewards.showWelcome(data: any, onClose: (() -> ())?)
	local overlay = App.layers.Overlay
	if not overlay or type(data) ~= "table" or type(data.energy) ~= "number" then
		return
	end
	local old = overlay:FindFirstChild("WelcomeBack")
	if old then
		old:Destroy()
	end
	local backdrop = C.new("TextButton", {
		Name = "WelcomeBack",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 30,
		Parent = overlay,
	})
	local items = if type(data.items) == "table" then data.items else {}
	local panel = C.panel({
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(440, if #items > 0 then 300 else 250),
		BackgroundTransparency = 0,
		ZIndex = 31,
		Parent = backdrop,
	})
	C.gradient(Colors.Accent:Lerp(Colors.Panel, 0.8), Colors.Panel).Parent = panel
	local function line(name: string, text: string, y: number, height: number, props: { [string]: any }?)
		local label = C.text({
			Name = name,
			Text = text,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = true,
			Size = UDim2.new(1, -40, 0, height),
			Position = UDim2.fromOffset(20, y),
			ZIndex = 32,
			Parent = panel,
		})
		if props then
			for key, value in props do
				(label :: any)[key] = value
			end
		end
		return label
	end
	line(
		"Title",
		"WELCOME BACK!",
		16,
		32,
		{ FontFace = Theme.Fonts.Display, TextSize = 24, TextColor3 = Colors.Accent }
	)
	local away = Format.duration(data.away)
	local capped = data.away > data.seconds + 1
	line(
		"Away",
		"You were away for "
			.. away
			.. (if capped then " (production counts up to " .. Format.duration(data.seconds) .. ")" else "")
			.. ".",
		52,
		36,
		{ TextSize = 15, TextColor3 = Colors.TextDim }
	)
	line(
		"Energy",
		"+⚡ " .. Format.number(data.energy),
		92,
		44,
		{ FontFace = Theme.Fonts.Bold, TextSize = 36, TextColor3 = Colors.Energy }
	)
	line(
		"Rate",
		string.format(
			"Your factory kept running at %d%% speed while you were away (max %dh).",
			math.floor(data.rate * 100 + 0.5),
			Economy.OfflineMaxHours
		),
		138,
		36,
		{ TextSize = 14, TextColor3 = Colors.TextDim }
	)
	if #items > 0 then
		line(
			"Printed",
			"🖨 The Box Printer made "
				.. #items
				.. (if #items == 1 then " artifact: " else " artifacts: ")
				.. itemLine(items),
			178,
			50,
			{ TextSize = 14, TextColor3 = Colors.Text }
		)
	end
	local close = C.button({
		name = "Continue",
		text = "CONTINUE",
		color = Colors.Good,
		textColor = Color3.fromRGB(10, 40, 20),
		size = UDim2.fromOffset(180, 44),
		anchor = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, -16),
		parent = panel,
	})
	close.ZIndex = 33
	local scale = C.new("UIScale", { Scale = 0.6, Parent = panel })
	C.tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	Sound.play("QuestComplete")
	local closed = false
	local function dismiss()
		if closed then
			return
		end
		closed = true
		Sound.play("UIClick")
		backdrop:Destroy()
		if onClose then
			onClose()
		end
	end
	C.onClick(close, dismiss)
end

function Rewards.start()
	local function onReady()
		local welcome = Store.pendingWelcome
		Store.pendingWelcome = nil
		if welcome then
			Rewards.showWelcome(welcome, remindDaily)
		else
			remindDaily()
		end
	end
	if Store.ready then
		onReady()
	else
		local connection
		connection = Store.Ready:Connect(function()
			connection:Disconnect()
			onReady()
		end)
	end
	Remote.NotifyReceived:Connect(function(kind, payload)
		if kind == "Welcome" then
			Rewards.showWelcome(payload)
		end
	end)
end

return Rewards
