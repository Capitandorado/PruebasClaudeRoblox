-- Feedback for big moments: confetti on screen, a shockwave in the world when a machine is
-- bought or the plot grows, the rebirth celebration and Robux purchase confirmations.
-- Everything is cosmetic and local; "reduced effects" keeps only the text.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Monetization = require(Shared.Config.Monetization)
local RebirthConfig = require(Shared.Config.Rebirth)
local Format = require(Shared.Util.Format)
local Build = require(Shared.Util.Build)

local Client = script.Parent.Parent
local Remote = require(Client.Core.Remote)
local Store = require(Client.Core.Store)
local Sound = require(Client.Core.Sound)
local App = require(Client.UI.App)
local Theme = require(Client.UI.Theme)
local C = require(Client.UI.Components)
local Box = require(script.Parent.Box)

local Colors = Theme.Colors

local Celebrate = {}

local CONFETTI_COLORS = {
	Color3.fromRGB(255, 214, 70),
	Color3.fromRGB(90, 220, 255),
	Color3.fromRGB(175, 95, 255),
	Color3.fromRGB(90, 230, 140),
	Color3.fromRGB(255, 120, 200),
}

local function reduced(): boolean
	return Store.profile ~= nil and Store.profile.settings.reducedEffects == true
end

-- Paper confetti falling over the screen.
function Celebrate.confetti(amount: number?)
	local overlay = App.layers.Overlay
	if not overlay or reduced() then
		return
	end
	local count = amount or 36
	local random = Random.new()
	for index = 1, count do
		local piece = C.new("Frame", {
			Name = "Confetti",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(random:NextNumber(0.05, 0.95), 0, 0, -20),
			Size = UDim2.fromOffset(random:NextInteger(7, 12), random:NextInteger(10, 18)),
			BackgroundColor3 = CONFETTI_COLORS[index % #CONFETTI_COLORS + 1],
			BorderSizePixel = 0,
			Rotation = random:NextNumber(0, 360),
			ZIndex = 60,
			Parent = overlay,
		})
		local duration = random:NextNumber(1.2, 2)
		local drift = random:NextNumber(-0.12, 0.12)
		task.delay(random:NextNumber(0, 0.35), function()
			C.tween(piece, duration, {
				Position = piece.Position + UDim2.new(drift, 0, 1.1, 0),
				Rotation = piece.Rotation + random:NextNumber(-540, 540),
				BackgroundTransparency = 0.3,
			}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.delay(duration + 0.05, function()
				piece:Destroy()
			end)
		end)
	end
end

-- Large centred title (rebirths, big purchases).
function Celebrate.banner(title: string, subtitle: string?, color: Color3?)
	local overlay = App.layers.Overlay
	if not overlay then
		return
	end
	local frame = C.new("Frame", {
		Name = "CelebrationBanner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromOffset(720, 130),
		BackgroundTransparency = 1,
		ZIndex = 55,
		Parent = overlay,
	})
	local titleLabel = C.text({
		Name = "Title",
		Text = title,
		FontFace = Theme.Fonts.Display,
		TextSize = 46,
		TextColor3 = color or Colors.Energy,
		TextStrokeTransparency = 0.2,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 64),
		ZIndex = 56,
		Parent = frame,
	})
	local subtitleLabel = C.text({
		Name = "Subtitle",
		Text = subtitle or "",
		TextSize = 22,
		TextColor3 = Colors.Text,
		TextStrokeTransparency = 0.4,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 34),
		Position = UDim2.fromOffset(0, 70),
		ZIndex = 56,
		Parent = frame,
	})
	local scale = C.new("UIScale", { Scale = 0.2, Parent = frame })
	C.tween(scale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(2.8, function()
		C.tween(titleLabel, 0.4, { TextTransparency = 1, TextStrokeTransparency = 1 })
		C.tween(subtitleLabel, 0.4, { TextTransparency = 1, TextStrokeTransparency = 1 })
		task.wait(0.45)
		frame:Destroy()
	end)
end

-- Expanding neon ring in the world.
function Celebrate.shockwave(position: Vector3, color: Color3, size: number?)
	if reduced() then
		return
	end
	local ring = Build.part({
		Name = "Shockwave",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 2, 2),
		CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.2,
		CanQuery = false,
		Parent = Box.effectsFolder(),
	})
	ring.CanTouch = false
	local final = size or 26
	TweenService:Create(
		ring,
		TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.1, final, final), Transparency = 1 }
	):Play()
	task.delay(0.95, function()
		ring:Destroy()
	end)
end

local function plotCentre(plotIndex: number): Vector3?
	local root = workspace:FindFirstChild("VoidFactory")
	local plots = root and root:FindFirstChild("Plots")
	local plot = plots and plots:FindFirstChild("Plot_" .. plotIndex)
	if plot and plot:IsA("Model") and plot.PrimaryPart then
		return plot.PrimaryPart.Position + Vector3.new(0, 1, 0)
	end
	return nil
end

local function onPurchased(summary: any)
	if type(summary) ~= "table" then
		return
	end
	Sound.play("Purchase")
	Celebrate.confetti(48)
	local name = tostring(summary.icon or "🛒") .. " " .. tostring(summary.name or "Purchase")
	if summary.kind == "pass" then
		Celebrate.banner("THANK YOU!", name .. " is now active", Color3.fromRGB(255, 205, 80))
	elseif summary.energy then
		App.toast(name .. ": +⚡" .. Format.number(summary.energy), "success")
	elseif summary.boost then
		local boost = Monetization.Boosts[summary.boost]
		App.toast(
			name
				.. " active: "
				.. (if boost then boost.name else "boost")
				.. " for "
				.. Format.shortDuration(summary.remaining or 0),
			"success"
		)
	else
		App.toast(name .. " applied!", "success")
	end
end

local function onEffect(kind: string, payload: any)
	if type(payload) ~= "table" then
		return
	end
	local own = payload.userId == Players.LocalPlayer.UserId
	if kind == "Purchase" then
		local position = if payload.machineId
			then Box.outputPosition(payload.plot, payload.machineId)
			else plotCentre(payload.plot)
		if position then
			Celebrate.shockwave(position, Color3.fromRGB(255, 214, 70), 18)
		end
		if own and payload.machineId then
			Celebrate.confetti(28)
		end
	elseif kind == "Unlock" then
		local position = plotCentre(payload.plot)
		if position then
			Celebrate.shockwave(position, Colors.Accent, 70)
		end
		if own then
			Celebrate.confetti(30)
			App.toast("🧱 Plot expanded! New pedestals unlocked.", "success")
		end
	elseif kind == "Rebirth" then
		local position = plotCentre(payload.plot)
		if position then
			Celebrate.shockwave(position, Color3.fromRGB(200, 120, 255), 90)
		end
		if own then
			local rebirths = Store.profile and Store.profile.rebirths or 1
			local multiplier = RebirthConfig.productionMultiplier(rebirths)
			Celebrate.banner(
				"REBIRTH #" .. rebirths,
				string.format("Permanent production x%.1f  •  spend your shards on perks", multiplier),
				Color3.fromRGB(200, 140, 255)
			)
			Celebrate.confetti(60)
		end
	end
end

function Celebrate.start()
	Remote.NotifyReceived:Connect(function(kind, payload)
		if kind == "Purchased" then
			onPurchased(payload)
		end
	end)
	Remote.EffectReceived:Connect(onEffect)
end

return Celebrate
