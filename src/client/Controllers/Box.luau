-- Box opening: sends the request, then plays the reveal on top of the machine. The server
-- has already granted the item when the animation starts, so it is purely cosmetic.
-- Rarer tiers get longer build-ups, more light beams, camera shake, a screen flash and
-- their own sound.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Boxes = require(Shared.Config.Boxes)
local Machines = require(Shared.Config.Machines)
local Rarities = require(Shared.Config.Rarities)
local Format = require(Shared.Util.Format)
local Items = require(Shared.Logic.Items)
local Signal = require(Shared.Util.Signal)
local Build = require(Shared.Util.Build)
local ArtifactModels = require(Shared.Visuals.ArtifactModels)

local Client = script.Parent.Parent
local Remote = require(Client.Core.Remote)
local Store = require(Client.Core.Store)
local Sound = require(Client.Core.Sound)
local App = require(Client.UI.App)
local Theme = require(Client.UI.Theme)
local C = require(Client.UI.Components)

local Box = {}

Box.Busy = Signal.new()
Box.Opened = Signal.new()
Box.AutoChanged = Signal.new()

Box.busy = false
Box.auto = false
Box.autoMachine = Machines.StarterId

local Colors = Theme.Colors

local function reducedEffects(): boolean
	local profile = Store.profile
	return profile ~= nil and profile.settings.reducedEffects == true
end

local function plotModel(index: number): Model?
	local root = workspace:FindFirstChild("VoidFactory")
	local plots = root and root:FindFirstChild("Plots")
	return plots and plots:FindFirstChild("Plot_" .. index) :: Model?
end

-- World position above a machine of a plot (where boxes appear).
local function outputPosition(plotIndex: number, machineId: string): Vector3?
	local machine = Machines.get(machineId)
	local plot = plotModel(plotIndex)
	if not machine or not plot then
		return nil
	end
	local pad = plot:FindFirstChild("Machines") and (plot :: any).Machines:FindFirstChild("Pad_" .. machine.pad)
	local model = pad and pad:FindFirstChild("Machine")
	local output = model and model:FindFirstChild("Output")
	if output and output:IsA("BasePart") then
		return output.Position + Vector3.new(0, 2.5, 0)
	end
	return nil
end

local function fallbackPosition(): Vector3
	local camera = workspace.CurrentCamera
	if camera then
		return camera.CFrame.Position + camera.CFrame.LookVector * 14
	end
	return Vector3.new(0, 10, 0)
end

local function effectsFolder(): Folder
	local folder = workspace:FindFirstChild("ClientEffects")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "ClientEffects"
		folder.Parent = workspace
	end
	return folder :: Folder
end

-- Visual pieces -----------------------------------------------------------------------

local function buildBox(boxId: string): Model
	local box = Boxes.get(boxId)
	local color = if box then box.color else Colors.Accent
	local model = Build.model("RevealBox")
	Build.root(model, CFrame.new(), Vector3.new(2.4, 2.4, 2.4))
	local body = Build.part({
		Name = "Body",
		Size = Vector3.new(2.4, 2.4, 2.4),
		Color = Color3.fromRGB(30, 30, 46),
		Material = Enum.Material.Metal,
		Parent = model,
	})
	for _, axis in { Vector3.new(1, 0, 0), Vector3.new(0, 0, 1) } do
		Build.part({
			Name = "Band",
			Size = Vector3.new(2.5, 2.5, 2.5) - axis * 2.1,
			Color = color,
			Material = Enum.Material.Neon,
			Parent = model,
		})
	end
	Build.part({
		Name = "Lid",
		Size = Vector3.new(2.6, 0.3, 2.6),
		CFrame = CFrame.new(0, 1.2, 0),
		Color = color,
		Material = Enum.Material.Neon,
		Parent = model,
	})
	local light = Build.light(body, color, 1, 10)
	light.Name = "Glow"
	return model
end

local function burst(position: Vector3, color: Color3, beams: number, size: number)
	local folder = effectsFolder()
	local sphere = Build.sphere({
		Name = "Burst",
		Diameter = 1,
		CFrame = CFrame.new(position),
		Color = color,
		Material = Enum.Material.Neon,
		Parent = folder,
	})
	C.tween(sphere, 0.45, { Size = Vector3.new(size, size, size), Transparency = 1 })
	task.delay(0.5, function()
		sphere:Destroy()
	end)
	local light = Build.light(sphere, color, 6, 30)
	C.tween(light, 0.6, { Brightness = 0 })
	local emitter = Build.particles(sphere, "Sparkles", color, 0)
	emitter.Speed = NumberRange.new(10, 22)
	emitter:Emit(20 + beams * 4)
	for index = 1, beams do
		local direction = CFrame.Angles(0, index / beams * math.pi * 2, math.rad(35 + (index % 3) * 20))
		local beam = Build.part({
			Name = "Beam",
			Size = Vector3.new(0.35, 0.35, 26),
			CFrame = CFrame.new(position) * direction * CFrame.new(0, 0, -13),
			Color = color,
			Material = Enum.Material.Neon,
			Transparency = 0.15,
			Parent = folder,
		})
		C.tween(beam, 1.1, { Transparency = 1, Size = Vector3.new(0.05, 0.05, 40) })
		task.delay(1.15, function()
			beam:Destroy()
		end)
	end
end

local function shakeCamera(magnitude: number, duration: number)
	if magnitude <= 0 or reducedEffects() then
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local name = "VoidFactoryShake"
	local elapsed = 0
	RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, function(dt)
		elapsed += dt
		if elapsed >= duration then
			RunService:UnbindFromRenderStep(name)
			return
		end
		local strength = magnitude * (1 - elapsed / duration) * 0.6
		camera.CFrame = camera.CFrame
			* CFrame.new((math.random() - 0.5) * strength, (math.random() - 0.5) * strength, 0)
			* CFrame.Angles(0, 0, (math.random() - 0.5) * strength * 0.03)
	end)
end

local function flashScreen(color: Color3)
	if reducedEffects() then
		return
	end
	local overlay = App.layers.Overlay
	if not overlay then
		return
	end
	local flash = C.new("Frame", {
		Name = "Flash",
		BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.6),
		BackgroundTransparency = 0.25,
		Size = UDim2.fromScale(2, 2),
		Position = UDim2.fromScale(-0.5, -0.5),
		ZIndex = 50,
		Parent = overlay,
	})
	C.tween(flash, 0.7, { BackgroundTransparency = 1 })
	task.delay(0.75, function()
		flash:Destroy()
	end)
end

-- Result card shown in the centre of the screen.
local function showCard(result: any)
	local overlay = App.layers.Overlay
	if not overlay then
		return
	end
	local old = overlay:FindFirstChild("RevealCard")
	if old then
		old:Destroy()
	end
	local grant = result.grants[1]
	local item = Items.parse(grant.key)
	if not item then
		return
	end
	local rarity = Rarities.get(Items.rarityOf(item))
	local color = if rarity then rarity.color else Colors.Accent
	local card = C.panel({
		Name = "RevealCard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.43),
		Size = UDim2.fromOffset(380, 150),
		Parent = overlay,
	})
	local stroke = card:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
		stroke.Thickness = 3
	end
	C.gradient(color:Lerp(Colors.Panel, 0.75), Colors.Panel).Parent = card
	C.text({
		Name = "Rarity",
		Text = string.upper(rarity and rarity.id or "?"),
		FontFace = Theme.Fonts.Display,
		TextColor3 = color,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromOffset(0, 12),
		Parent = card,
	})
	C.text({
		Name = "ItemName",
		Text = Items.displayName(item),
		FontFace = Theme.Fonts.Bold,
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, -20, 0, 36),
		Position = UDim2.fromOffset(10, 44),
		Parent = card,
	})
	local details = {}
	if grant.newArtifact then
		table.insert(details, "✨ NEW DISCOVERY!")
	elseif grant.newVariant then
		table.insert(details, "✨ NEW VARIANT!")
	end
	if result.duplicated then
		table.insert(details, "x2 DUPLICATED")
	end
	if grant.sold then
		table.insert(details, "Auto-sold +⚡" .. Format.number(grant.value))
	end
	table.insert(details, "+" .. Format.number(Items.baseEps(item)) .. " ⚡/s base")
	C.text({
		Name = "Details",
		Text = table.concat(details, "   •   "),
		TextColor3 = Colors.TextDim,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, -20, 0, 40),
		Position = UDim2.fromOffset(10, 92),
		Parent = card,
	})
	local scale = C.new("UIScale", { Scale = 0.5, Parent = card })
	C.tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(1.8, function()
		if card.Parent then
			C.tween(scale, 0.2, { Scale = 0.01 })
			task.wait(0.21)
			card:Destroy()
		end
	end)
end

-- Big centred banner the first time the player reaches a rarity tier.
local function celebrateTier(rarity: Rarities.Rarity)
	local overlay = App.layers.Overlay
	if not overlay then
		return
	end
	local banner = C.new("TextLabel", {
		Name = "TierBanner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.16),
		Size = UDim2.fromOffset(700, 70),
		BackgroundTransparency = 1,
		Text = "NEW BEST RARITY: " .. string.upper(rarity.id),
		FontFace = Theme.Fonts.Display,
		TextSize = 34,
		TextColor3 = rarity.color,
		TextStrokeTransparency = 0.2,
		ZIndex = 40,
		Parent = overlay,
	})
	C.new("UIStroke", { Color = rarity.accent, Thickness = 2, Parent = banner })
	local scale = C.new("UIScale", { Scale = 0.3, Parent = banner })
	C.tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(2.6, function()
		C.tween(banner, 0.4, { TextTransparency = 1, TextStrokeTransparency = 1 })
		task.wait(0.45)
		banner:Destroy()
	end)
end

-- Full reveal sequence. Yields until the animation is over.
function Box.playReveal(result: any)
	local grant = result.grants[1]
	local item = grant and Items.parse(grant.key)
	if not item then
		return
	end
	local rarity = Rarities.get(Items.rarityOf(item)) :: Rarities.Rarity
	local reveal = rarity.reveal
	local reduced = reducedEffects()
	local duration = if reduced then reveal.duration * 0.5 else reveal.duration
	local position = outputPosition(Store.plot, result.machineId)
	local camera = workspace.CurrentCamera
	if not position or (camera and (camera.CFrame.Position - position).Magnitude > 120) then
		-- Visiting another factory (or far away): play the reveal in front of the camera.
		position = fallbackPosition()
	end

	Sound.play("BoxOpen", 0.05)
	local boxModel = buildBox(result.boxId)
	boxModel:PivotTo(CFrame.new(position))
	boxModel.Parent = effectsFolder()
	local glow = (boxModel:FindFirstChild("Body") :: BasePart):FindFirstChild("Glow") :: PointLight
	local buildUp = duration * 0.6
	local elapsed = 0
	local tease = rarity.order >= Rarities.order("Rare")
	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		local alpha = math.clamp(elapsed / buildUp, 0, 1)
		local shake = alpha * alpha * (0.15 + rarity.order * 0.04)
		local wobble =
			CFrame.Angles((math.random() - 0.5) * shake, (math.random() - 0.5) * shake, (math.random() - 0.5) * shake)
		boxModel:PivotTo(CFrame.new(position + Vector3.new(0, math.sin(elapsed * 6) * 0.2, 0)) * wobble)
		glow.Brightness = 1 + alpha * (2 + rarity.order * 0.6)
		if tease and alpha > 0.55 then
			glow.Color = glow.Color:Lerp(rarity.color, 0.15)
		end
	end)
	task.wait(buildUp)
	connection:Disconnect()
	boxModel:Destroy()

	Sound.play(reveal.sound)
	burst(position, rarity.color, if reduced then 0 else reveal.beams, 6 + rarity.order)
	shakeCamera(reveal.shake, 0.5 + reveal.shake * 0.4)
	if reveal.flash then
		flashScreen(rarity.color)
	end
	showCard(result)
	if grant.newTier and rarity.order >= Rarities.order("Rare") then
		celebrateTier(rarity)
	end

	local artifactModel = ArtifactModels.build(item.id, { mutation = item.mut, stars = item.stars })
	artifactModel:PivotTo(CFrame.new(position))
	artifactModel.Parent = effectsFolder()
	local spin = 0
	local showTime = math.max(0.9, duration - buildUp + 0.4)
	local spinConnection = RunService.RenderStepped:Connect(function(dt)
		spin += dt
		artifactModel:PivotTo(
			CFrame.new(position + Vector3.new(0, math.sin(spin * 3) * 0.3, 0)) * CFrame.Angles(0, spin * 2.5, 0)
		)
	end)
	task.wait(showTime)
	spinConnection:Disconnect()
	artifactModel:Destroy()
end

-- Opens one box at `machineId`. Returns true if a box was opened.
function Box.open(machineId: string, quietErrors: boolean?): boolean
	if Box.busy then
		return false
	end
	Box.busy = true
	Box.Busy:Fire(true)
	local response = Remote.request("OpenBox", machineId)
	if not response.ok then
		Box.busy = false
		Box.Busy:Fire(false)
		if not quietErrors then
			App.showError(response.err)
		end
		return false
	end
	local ok, err = pcall(Box.playReveal, response.data)
	if not ok then
		warn("[Box] reveal failed: " .. tostring(err))
	end
	Box.busy = false
	Box.Busy:Fire(false)
	Box.Opened:Fire(response.data)
	return true
end

-- Plays the reveals of boxes opened elsewhere (daily crates), after any reveal in progress.
function Box.playResults(results: { any })
	task.spawn(function()
		while Box.busy do
			task.wait(0.1)
		end
		Box.busy = true
		Box.Busy:Fire(true)
		for _, result in results do
			local ok, err = pcall(Box.playReveal, result)
			if not ok then
				warn("[Box] reveal failed: " .. tostring(err))
			end
		end
		Box.busy = false
		Box.Busy:Fire(false)
	end)
end

-- Auto-open loop: keeps opening at the chosen machine; waits for free charges and stops
-- when a paid machine runs out of Energy or the inventory fills up.
function Box.setAuto(enabled: boolean, machineId: string?)
	Box.autoMachine = machineId or Box.autoMachine
	if Box.auto == enabled then
		return
	end
	Box.auto = enabled
	Box.AutoChanged:Fire(enabled)
	if not enabled then
		return
	end
	task.spawn(function()
		while Box.auto do
			local machine = Box.autoMachine
			local response = nil
			if not Box.busy then
				Box.busy = true
				Box.Busy:Fire(true)
				response = Remote.request("OpenBox", machine)
				if response.ok then
					pcall(Box.playReveal, response.data)
					Box.busy = false
					Box.Busy:Fire(false)
					Box.Opened:Fire(response.data)
				else
					Box.busy = false
					Box.Busy:Fire(false)
				end
			end
			if response and not response.ok then
				if response.err == "NoCharges" or response.err == "RateLimited" then
					task.wait(1)
				else
					App.showError(response.err)
					Box.setAuto(false)
				end
			else
				task.wait(0.25)
			end
		end
	end)
end

-- Other players' reveals: a quick burst above their machine.
local function onEffect(kind: string, payload: any)
	if kind ~= "Reveal" or type(payload) ~= "table" then
		return
	end
	if payload.userId == Players.LocalPlayer.UserId or reducedEffects() then
		return
	end
	local rarity = Rarities.get(payload.rarity)
	local position = outputPosition(payload.plot, payload.machineId)
	local camera = workspace.CurrentCamera
	if rarity and position and camera and (camera.CFrame.Position - position).Magnitude < 220 then
		burst(position, rarity.color, math.min(rarity.reveal.beams, 6), 5 + rarity.order)
	end
end

-- Box Printer results: small burst at the printer and a toast for good finds.
local function onNotify(kind: string, payload: any)
	if kind ~= "Printed" or type(payload) ~= "table" then
		return
	end
	local grant = payload.grants and payload.grants[1]
	local item = grant and Items.parse(grant.key)
	if not item then
		return
	end
	local rarity = Rarities.get(Items.rarityOf(item))
	if not rarity then
		return
	end
	local position = outputPosition(Store.plot, "box_printer")
	if position and not reducedEffects() then
		burst(position, rarity.color, math.min(rarity.reveal.beams, 4), 4 + rarity.order)
	end
	if rarity.order >= Rarities.order("Rare") or grant.newArtifact then
		App.toast(
			"🖨 Printer found " .. Items.displayName(item) .. (if grant.newArtifact then " (NEW!)" else ""),
			"success"
		)
		Sound.play(rarity.reveal.sound)
	end
end

function Box.start()
	Remote.EffectReceived:Connect(onEffect)
	Remote.NotifyReceived:Connect(onNotify)
end

return Box
