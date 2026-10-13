-- Makes the factory readable: output labels over your pedestals, neon links between
-- artifacts that boost (green) or drain (red) their neighbours, a production pulse every
-- second and, while placing, the exact Energy/s change each pedestal would give.
-- All of it is local to this client.

local Players = game:GetService("Players")
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
local linkFolder: Folder? = nil
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
	if not labelFolder or not labelFolder.Parent then
		local folder = Instance.new("Folder")
		folder.Name = "FactoryLabels"
		folder.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
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

-- Ring flash on every producing pedestal (once per server tick).
local function pulse()
	local profile = Store.profile
	if not profile or reduced() then
		return
	end
	for slotKey, key in profile.placed do
		local slot = tonumber(slotKey)
		local target = slot and pedestal(slot)
		local ring = target and target:FindFirstChild("Ring")
		local item = Items.parse(key)
		if ring and ring:IsA("BasePart") and item then
			local rarity = Rarities.get(Items.rarityOf(item))
			local color = if rarity then rarity.color else Colors.Accent
			ring.Color = color:Lerp(Color3.new(1, 1, 1), 0.6)
			TweenService:Create(ring, TweenInfo.new(0.6), { Color = color }):Play()
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
end

return FactoryView
