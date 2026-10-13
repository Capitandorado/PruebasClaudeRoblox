-- Makes the factory readable: output labels over your pedestals, neon links between
-- artifacts that boost (green) or drain (red) their neighbours, a production pulse every
-- second and, while placing, the exact Energy/s change each pedestal would give.
-- All of it is local to this client.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Artifacts = require(Shared.Config.Artifacts)
local Mutations = require(Shared.Config.Mutations)
local PlotConfig = require(Shared.Config.Plot)
local Rarities = require(Shared.Config.Rarities)
local Format = require(Shared.Util.Format)
local Build = require(Shared.Util.Build)
local Items = require(Shared.Logic.Items)
local State = require(Shared.Logic.State)

local Client = script.Parent.Parent
local Store = require(Client.Core.Store)
local Theme = require(Client.UI.Theme)
local C = require(Client.UI.Components)

local FactoryView = {}

local Colors = Theme.Colors

local labels: { [number]: BillboardGui } = {}
local pulses: { [number]: BasePart } = {}
local linkFolder: Folder? = nil
local pulseFolder: Folder? = nil
local labelFolder: Folder? = nil
local previewKey: string? = nil

local function ownPlot(): Model?
	local root = workspace:FindFirstChild("VoidFactory")
	local plots = root and root:FindFirstChild("Plots")
	return plots and plots:FindFirstChild("Plot_" .. Store.plot) :: Model?
end

local function pedestal(slot: number): Model?
	local plot = ownPlot()
	local slots = plot and plot:FindFirstChild("Slots")
	return slots and slots:FindFirstChild("Slot_" .. slot) :: Model?
end

local function reduced(): boolean
	return Store.profile ~= nil and Store.profile.settings.reducedEffects == true
end

local function ensureFolders()
	if not linkFolder or not linkFolder.Parent then
		local folder = Instance.new("Folder")
		folder.Name = "FactoryLinks"
		folder.Parent = workspace
		linkFolder = folder
	end
	if not pulseFolder or not pulseFolder.Parent then
		local folder = Instance.new("Folder")
		folder.Name = "FactoryPulses"
		folder.Parent = workspace
		pulseFolder = folder
	end
	-- Labels live in a client-only workspace folder (they render through their Adornee):
	-- PlayerGui is emptied on respawn, which would make them vanish.
	if not labelFolder or not labelFolder.Parent then
		local folder = Instance.new("Folder")
		folder.Name = "FactoryLabels"
		folder.Parent = workspace
		labelFolder = folder
	end
end

local function labelFor(slot: number): BillboardGui?
	local existing = labels[slot]
	if existing and existing.Parent then
		return existing
	end
	local target = pedestal(slot)
	local hitbox = target and target:FindFirstChild("Hitbox")
	if not hitbox or not hitbox:IsA("BasePart") then
		return nil
	end
	ensureFolders()
	local gui = C.new("BillboardGui", {
		Name = "Slot" .. slot,
		Adornee = hitbox,
		Size = UDim2.fromOffset(110, 40),
		StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0),
		MaxDistance = 70,
		LightInfluence = 0,
		ResetOnSpawn = false,
		Parent = labelFolder,
	})
	C.text({
		Name = "Main",
		Text = "",
		FontFace = Theme.Fonts.Bold,
		TextSize = 16,
		TextColor3 = Colors.Energy,
		TextStrokeTransparency = 0.3,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0.55, 0),
		Parent = gui,
	})
	C.text({
		Name = "Sub",
		Text = "",
		TextSize = 13,
		TextStrokeTransparency = 0.3,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0.45, 0),
		Position = UDim2.fromScale(0, 0.55),
		Parent = gui,
	})
	labels[slot] = gui
	return gui
end

local function setLabel(slot: number, main: string, mainColor: Color3, sub: string, subColor: Color3)
	local gui = labelFor(slot)
	if not gui then
		return
	end
	gui.Enabled = main ~= "" or sub ~= ""
	local mainLabel = gui:FindFirstChild("Main") :: TextLabel
	local subLabel = gui:FindFirstChild("Sub") :: TextLabel
	mainLabel.Text = main
	mainLabel.TextColor3 = mainColor
	subLabel.Text = sub
	subLabel.TextColor3 = subColor
end

local function slotPosition(slot: number): Vector3?
	local target = pedestal(slot)
	local ring = target and target:FindFirstChild("Ring")
	return if ring and ring:IsA("BasePart") then ring.Position else nil
end

local function link(from: number, to: number, color: Color3)
	local a, b = slotPosition(from), slotPosition(to)
	if not a or not b or not linkFolder then
		return
	end
	local lift = Vector3.new(0, 1.2, 0)
	local length = (b - a).Magnitude
	local part = Build.part({
		Name = "Link",
		Size = Vector3.new(0.25, 0.25, length),
		CFrame = CFrame.lookAt((a + b) / 2 + lift, b + lift),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.25,
		Parent = linkFolder,
	})
	part.CanQuery = false
end

local function rebuildLinks(profile: any)
	ensureFolders()
	local folder = linkFolder :: Folder
	folder:ClearAllChildren()
	if reduced() then
		return
	end
	for slotKey, key in profile.placed do
		local slot = tonumber(slotKey)
		local item = Items.parse(key)
		if not slot or not item or not PlotConfig.isSlotUnlocked(slot, profile.expansion) then
			continue
		end
		local artifact = Artifacts.get(item.id)
		local boosts = false
		for _, effect in (artifact and artifact.effects or {}) do
			if effect.type == "adjacent_mult" then
				boosts = true
			end
		end
		local mutation = Mutations.get(item.mut)
		local drains = mutation ~= nil and mutation.adjacentPenalty ~= nil
		for _, neighbour in PlotConfig.neighbours(slot) do
			if profile.placed[tostring(neighbour)] and PlotConfig.isSlotUnlocked(neighbour, profile.expansion) then
				if boosts then
					link(slot, neighbour, Colors.Good)
				end
				if drains then
					link(slot, neighbour, Colors.Bad)
				end
			end
		end
	end
end

function FactoryView.refresh()
	local profile = Store.profile
	if not profile or Store.plot == 0 then
		return
	end
	local production = Store.production()
	if previewKey then
		local current = production.total
		local best, bestDelta = nil, -math.huge
		local deltas = {}
		for slot = 1, PlotConfig.TotalSlots do
			if PlotConfig.isSlotUnlocked(slot, profile.expansion) then
				local delta = State.previewPlacement(profile, slot, previewKey) - current
				deltas[slot] = delta
				if delta > bestDelta then
					best, bestDelta = slot, delta
				end
			end
		end
		for slot = 1, PlotConfig.TotalSlots do
			local delta = deltas[slot]
			if delta == nil then
				setLabel(slot, "", Colors.Text, "", Colors.Text)
			else
				local sign = if delta >= 0 then "+" else "-"
				local text = sign .. Format.number(math.abs(delta)) .. "/s"
				setLabel(
					slot,
					text,
					if delta > 1e-9 then Colors.Good elseif delta < -1e-9 then Colors.Bad else Colors.TextDim,
					if slot == best and bestDelta > 0 then "★ BEST" else "",
					Colors.Energy
				)
			end
		end
	else
		for slot = 1, PlotConfig.TotalSlots do
			local eps = production.perSlot[slot]
			if eps and PlotConfig.isSlotUnlocked(slot, profile.expansion) then
				local bonus = production.slotBonus[slot] or 0
				local sub, subColor = "", Colors.TextDim
				if bonus > 1e-9 then
					sub, subColor = string.format("+%d%% linked", math.floor(bonus * 100 + 0.5)), Colors.Good
				elseif bonus < -1e-9 then
					sub, subColor = string.format("%d%% drained", math.floor(bonus * 100 - 0.5)), Colors.Bad
				end
				setLabel(slot, "⚡" .. Format.number(eps) .. "/s", Colors.Energy, sub, subColor)
			else
				setLabel(slot, "", Colors.Text, "", Colors.Text)
			end
		end
	end
	rebuildLinks(profile)
end

function FactoryView.preview(key: string?)
	previewKey = key
	FactoryView.refresh()
end

-- Flash over every producing pedestal's ring (once per server tick). It uses a client-only
-- overlay part: tweening the server's Ring would race its replicated colour changes and
-- could leave an emptied pedestal lit on this client.
local function pulsePart(slot: number, ring: BasePart): BasePart
	local part = pulses[slot]
	if not part or not part.Parent then
		ensureFolders()
		part = Build.part({
			Name = "Pulse" .. slot,
			Shape = Enum.PartType.Cylinder,
			Size = ring.Size + Vector3.new(0.04, 0.1, 0.1),
			CFrame = ring.CFrame,
			Material = Enum.Material.Neon,
			Transparency = 1,
			CanQuery = false,
			Parent = pulseFolder,
		})
		part.CanTouch = false
		pulses[slot] = part
	end
	part.CFrame = ring.CFrame
	return part
end

-- Floating "+1.5K ⚡" popups: on every production tick each nearby producing pedestal
-- throws its gain into the air (pop, float up, fade). Billboards are pooled and reused, and
-- only the closest pedestals show them, so a full plot stays cheap and readable.
local GAIN_EVERY = 1 -- production ticks between popups
local GAIN_RANGE = 70 -- studs from the camera
local GAIN_MAX = 8 -- pedestals per tick
local GAIN_LIFETIME = 1.1
local pulseCount = 0
local gainPool: { BillboardGui } = {}
local gainRandom = Random.new()

local function newGainGui(): BillboardGui
	local gui = C.new("BillboardGui", {
		Name = "Gain",
		Size = UDim2.fromScale(5, 1.4),
		LightInfluence = 0,
		AlwaysOnTop = false,
		MaxDistance = GAIN_RANGE,
		ResetOnSpawn = false,
		Enabled = false,
	})
	local label = C.text({
		Name = "Text",
		Text = "",
		FontFace = Theme.Fonts.Number,
		TextColor3 = Colors.Energy,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	})
	label.TextScaled = true
	C.outline(label, Color3.fromRGB(70, 40, 0), 2, true)
	C.new("UIScale", { Name = "Pop", Parent = label })
	return gui
end

local function floatGain(hitbox: BasePart, amount: number)
	local gui = table.remove(gainPool) or newGainGui()
	local label = gui:FindFirstChild("Text") :: TextLabel
	local pop = label:FindFirstChild("Pop") :: UIScale
	local stroke = label:FindFirstChildOfClass("UIStroke") :: UIStroke
	local x = gainRandom:NextNumber(-0.9, 0.9)
	gui.Adornee = hitbox
	gui.StudsOffsetWorldSpace = Vector3.new(x, 2.6, 0)
	gui.Parent = pulseFolder
	gui.Enabled = true
	label.Text = "+" .. Format.number(amount) .. " ⚡"
	label.TextTransparency = 0
	stroke.Transparency = 0
	-- Pop in, then drift up while fading out.
	pop.Scale = 0.3
	C.tween(pop, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
	C.tween(gui, GAIN_LIFETIME, { StudsOffsetWorldSpace = Vector3.new(x * 1.4, 5.2, 0) }, Enum.EasingStyle.Quad)
	task.delay(GAIN_LIFETIME * 0.45, function()
		C.tween(label, GAIN_LIFETIME * 0.55, { TextTransparency = 1 })
		C.tween(stroke, GAIN_LIFETIME * 0.55, { Transparency = 1 })
	end)
	task.delay(GAIN_LIFETIME + 0.05, function()
		gui.Enabled = false
		gui.Adornee = nil
		table.insert(gainPool, gui)
	end)
end

local function showGains(profile: any)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local production = Store.production()
	local nearby = {}
	for slotKey in profile.placed do
		local slot = tonumber(slotKey)
		local eps = slot and production.perSlot[slot]
		local target = slot and pedestal(slot)
		local hitbox = target and target:FindFirstChild("Hitbox")
		if eps and eps > 0 and hitbox and hitbox:IsA("BasePart") then
			local distance = (hitbox.Position - camera.CFrame.Position).Magnitude
			if distance < GAIN_RANGE then
				table.insert(nearby, { hitbox = hitbox, eps = eps, distance = distance })
			end
		end
	end
	table.sort(nearby, function(a, b)
		return a.distance < b.distance
	end)
	ensureFolders()
	for index, entry in nearby do
		if index > GAIN_MAX then
			break
		end
		floatGain(entry.hitbox, entry.eps * GAIN_EVERY)
	end
end

-- A ring of light expands from a pedestal when an artifact lands on it.
local function placeRing(slot: number, color: Color3)
	local target = pedestal(slot)
	local ring = target and target:FindFirstChild("Ring")
	if not ring or not ring:IsA("BasePart") or reduced() then
		return
	end
	ensureFolders()
	local wave = Build.part({
		Name = "PlaceWave",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, 4.4, 4.4),
		CFrame = ring.CFrame,
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.1,
		CanQuery = false,
		Parent = pulseFolder,
	})
	wave.CanTouch = false
	TweenService
		:Create(wave, TweenInfo.new(0.7, Enum.EasingStyle.Quad), { Size = Vector3.new(0.1, 14, 14), Transparency = 1 })
		:Play()
	task.delay(0.75, function()
		wave:Destroy()
	end)
end

local lastPlaced: { [string]: string }? = nil

local function onPlacedChanged(changed: { [string]: boolean })
	local profile = Store.profile
	if not profile then
		return
	end
	local previous = lastPlaced
	lastPlaced = table.clone(profile.placed)
	if not previous or changed.all then
		return
	end
	for slotKey, key in profile.placed do
		if previous[slotKey] ~= key then
			local item = Items.parse(key)
			local rarity = item and Rarities.get(Items.rarityOf(item))
			-- Wait for the server's new artifact model to replicate first.
			task.delay(0.2, placeRing, tonumber(slotKey) :: number, if rarity then rarity.color else Colors.Accent)
		end
	end
end

local function pulse()
	local profile = Store.profile
	if not profile or reduced() then
		return
	end
	pulseCount += 1
	if pulseCount % GAIN_EVERY == 0 then
		showGains(profile)
	end
	for slotKey, key in profile.placed do
		local slot = tonumber(slotKey)
		local target = slot and pedestal(slot)
		local ring = target and target:FindFirstChild("Ring")
		local item = Items.parse(key)
		if slot and ring and ring:IsA("BasePart") and item then
			local rarity = Rarities.get(Items.rarityOf(item))
			local color = if rarity then rarity.color else Colors.Accent
			local part = pulsePart(slot, ring)
			part.Color = color:Lerp(Color3.new(1, 1, 1), 0.6)
			part.Transparency = 0.35
			TweenService:Create(part, TweenInfo.new(0.6), { Transparency = 1 }):Play()
		end
	end
end

function FactoryView.start()
	Store.watch(
		{ "placed", "machines", "upgrades", "perks", "rebirths", "expansion", "collection", "settings", "runtime" },
		function()
			-- The server rebuilds pedestal models first; refresh once they replicated.
			task.delay(0.2, FactoryView.refresh)
		end
	)
	Store.watch({ "energy" }, pulse)
	Store.watch({ "placed" }, onPlacedChanged)
end

return FactoryView
