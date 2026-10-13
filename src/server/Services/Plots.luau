-- Plot allocation and rendering. Each player owns one floating platform with a pedestal grid
-- (artifacts), six machine pads, a showcase for their rarest finds and an owner sign.
-- Rendering is incremental: only pedestals/machines whose state changed are rebuilt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Artifacts = require(Shared.Config.Artifacts)
local Machines = require(Shared.Config.Machines)
local PlotConfig = require(Shared.Config.Plot)
local Rarities = require(Shared.Config.Rarities)
local Build = require(Shared.Util.Build)
local Format = require(Shared.Util.Format)
local Items = require(Shared.Logic.Items)
local ArtifactModels = require(Shared.Visuals.ArtifactModels)
local MachineModels = require(Shared.Visuals.MachineModels)

local Services = script.Parent
local World = require(Services.World)

local Plots = {}

local EMPTY_RING = Color3.fromRGB(60, 90, 130)
local TRIM = Color3.fromRGB(80, 220, 255)
local PLATFORM = Color3.fromRGB(30, 28, 46)
local FLOOR = Color3.fromRGB(42, 40, 66)

type Rendered = {
	slots: { [number]: string },
	unlocked: { [number]: boolean },
	machines: { [string]: string },
	expansion: number,
	showcase: string,
}

local plotModels: { [number]: Model } = {}
local owners: { [number]: any } = {}
local rendered: { [number]: Rendered } = {}

local function newRendered(): Rendered
	return { slots = {}, unlocked = {}, machines = {}, expansion = -1, showcase = "" }
end

-- Geometry (plot-local) --------------------------------------------------------------

function Plots.slotLocal(index: number): CFrame
	local column, row = PlotConfig.slotPosition(index)
	local spacing = PlotConfig.SlotSpacing
	return CFrame.new((column - (PlotConfig.Columns + 1) / 2) * spacing, 0, -18 + (row - 1) * spacing)
end

function Plots.padLocal(pad: number): CFrame
	return CFrame.new(-25 + (pad - 1) * 10, 0, 22)
end

local SHOWCASE_LOCAL = {
	CFrame.new(33, 0, -16),
	CFrame.new(33, 0, -6),
	CFrame.new(33, 0, 4),
}

function Plots.cframe(index: number): CFrame
	return World.plotCFrame(index)
end

function Plots.spawnCFrame(index: number): CFrame
	return Plots.cframe(index) * CFrame.new(0, 4, -27) * CFrame.Angles(0, math.pi, 0)
end

function Plots.model(index: number): Model?
	return plotModels[index]
end

-- Shell construction ------------------------------------------------------------------

local function buildPedestal(parent: Instance, plotIndex: number, slot: number, plotFrame: CFrame)
	local model = Build.model("Slot_" .. slot, parent)
	local base = plotFrame * Plots.slotLocal(slot)
	Build.root(model, base * CFrame.new(0, 0.6, 0))
	Build.cylinder({
		Name = "Base",
		Height = 1.2,
		Diameter = 5,
		CFrame = base * CFrame.new(0, 0.6, 0),
		Color = Color3.fromRGB(52, 54, 72),
		Material = Enum.Material.Metal,
		CanCollide = true,
		Parent = model,
	})
	Build.cylinder({
		Name = "Ring",
		Height = 0.2,
		Diameter = 4.4,
		CFrame = base * CFrame.new(0, 1.25, 0),
		Color = EMPTY_RING,
		Material = Enum.Material.Neon,
		Parent = model,
	})
	local hitbox = Build.part({
		Name = "Hitbox",
		Size = Vector3.new(6, 9, 6),
		CFrame = base * CFrame.new(0, 4.5, 0),
		Transparency = 1,
		Parent = model,
	})
	hitbox:SetAttribute("SlotIndex", slot)
	hitbox:SetAttribute("PlotIndex", plotIndex)
	hitbox:AddTag("PedestalHitbox")
	return model
end

local function buildMachinePad(parent: Instance, pad: number, plotFrame: CFrame)
	local model = Build.model("Pad_" .. pad, parent)
	local base = plotFrame * Plots.padLocal(pad)
	Build.root(model, base * CFrame.new(0, 0.3, 0))
	local plate = Build.part({
		Name = "Plate",
		Size = Vector3.new(9, 0.6, 9),
		CFrame = base * CFrame.new(0, 0.3, 0),
		Color = Color3.fromRGB(60, 62, 80),
		Material = Enum.Material.DiamondPlate,
		CanCollide = true,
		Parent = model,
	})
	-- Neon outline along the pad edges.
	for _, edge in
		{
			{ CFrame.new(0, 0.65, -4.4), Vector3.new(9, 0.15, 0.2) },
			{ CFrame.new(0, 0.65, 4.4), Vector3.new(9, 0.15, 0.2) },
			{ CFrame.new(-4.4, 0.65, 0), Vector3.new(0.2, 0.15, 9) },
			{ CFrame.new(4.4, 0.65, 0), Vector3.new(0.2, 0.15, 9) },
		}
	do
		Build.part({
			Name = "Trim",
			Size = edge[2],
			CFrame = base * edge[1],
			Color = TRIM,
			Material = Enum.Material.Neon,
			Parent = model,
		})
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Prompt"
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt.Enabled = false
	prompt:AddTag("MachinePrompt")
	prompt.Parent = plate
	local info = Build.billboard(plate, UDim2.fromOffset(220, 70), Vector3.new(0, 11, 0), 90)
	info.Name = "Info"
	local title = Build.label(info, "", Color3.new(1, 1, 1), UDim2.fromScale(1, 0.55))
	title.Name = "Title"
	local detail =
		Build.label(info, "", Color3.fromRGB(170, 230, 255), UDim2.fromScale(1, 0.45), UDim2.fromScale(0, 0.55))
	detail.Name = "Detail"
	return model
end

local function buildShell(index: number, parent: Instance): Model
	local plotFrame = Plots.cframe(index)
	local model = Build.model("Plot_" .. index, parent)
	model:SetAttribute("PlotIndex", index)
	model:SetAttribute("OwnerUserId", 0)
	model:SetAttribute("OwnerName", "")
	Build.root(model, plotFrame)

	local base = Build.model("Base", model)
	Build.part({
		Name = "Platform",
		Size = Vector3.new(World.PlotWidth, 4, World.PlotDepth),
		CFrame = plotFrame * CFrame.new(0, -2, 0),
		Color = PLATFORM,
		Material = Enum.Material.Slate,
		CanCollide = true,
		CastShadow = true,
		Parent = base,
	})
	local halfW, halfD = World.PlotWidth / 2, World.PlotDepth / 2
	for _, edge in
		{
			{ CFrame.new(0, 0.05, -halfD), Vector3.new(World.PlotWidth, 0.3, 0.4) },
			{ CFrame.new(0, 0.05, halfD), Vector3.new(World.PlotWidth, 0.3, 0.4) },
			{ CFrame.new(-halfW, 0.05, 0), Vector3.new(0.4, 0.3, World.PlotDepth) },
			{ CFrame.new(halfW, 0.05, 0), Vector3.new(0.4, 0.3, World.PlotDepth) },
		}
	do
		Build.part({
			Name = "Trim",
			Size = edge[2],
			CFrame = plotFrame * edge[1],
			Color = TRIM,
			Material = Enum.Material.Neon,
			Parent = base,
		})
	end
	for _, x in { -28, 0, 28 } do
		for _, z in { -20, 20 } do
			local thruster = Build.cylinder({
				Name = "Thruster",
				Height = 3,
				Diameter = 5,
				CFrame = plotFrame * CFrame.new(x, -5, z),
				Color = Color3.fromRGB(40, 40, 60),
				Material = Enum.Material.Metal,
				Parent = base,
			})
			local glow = Build.cylinder({
				Name = "ThrusterGlow",
				Height = 0.4,
				Diameter = 4,
				CFrame = plotFrame * CFrame.new(x, -6.6, z),
				Color = Color3.fromRGB(150, 90, 255),
				Material = Enum.Material.Neon,
				Parent = base,
			})
			Build.light(glow, Color3.fromRGB(150, 90, 255), 2, 14)
			thruster:SetAttribute("Decor", true)
		end
	end

	local floor = Build.part({
		Name = "Floor",
		Size = Vector3.new(10, 0.2, 10),
		CFrame = plotFrame * CFrame.new(0, 0.1, 0),
		Color = FLOOR,
		Material = Enum.Material.Metal,
		Parent = model,
	})
	floor.CanQuery = false

	local slots = Instance.new("Folder")
	slots.Name = "Slots"
	slots.Parent = model
	for slot = 1, PlotConfig.TotalSlots do
		buildPedestal(slots, index, slot, plotFrame)
	end

	local machines = Instance.new("Folder")
	machines.Name = "Machines"
	machines.Parent = model
	for pad = 1, #Machines.List do
		buildMachinePad(machines, pad, plotFrame)
	end

	local showcase = Build.model("Showcase", model)
	for slot, localFrame in SHOWCASE_LOCAL do
		local podium = Build.cylinder({
			Name = "Podium" .. slot,
			Height = 2,
			Diameter = 4.5,
			CFrame = plotFrame * localFrame * CFrame.new(0, 1, 0),
			Color = Color3.fromRGB(70, 60, 110),
			Material = Enum.Material.Marble,
			CanCollide = true,
			Parent = showcase,
		})
		podium:SetAttribute("ShowcaseSlot", slot)
		Build.cylinder({
			Name = "PodiumRing" .. slot,
			Height = 0.2,
			Diameter = 4.9,
			CFrame = plotFrame * localFrame * CFrame.new(0, 2.05, 0),
			Color = Color3.fromRGB(255, 210, 90),
			Material = Enum.Material.Neon,
			Parent = showcase,
		})
	end
	local showcaseSignAnchor = Build.part({
		Name = "ShowcaseSign",
		Size = Vector3.new(1, 1, 1),
		CFrame = plotFrame * CFrame.new(33, 9, -6),
		Transparency = 1,
		Parent = showcase,
	})
	local showcaseSign = Build.billboard(showcaseSignAnchor, UDim2.fromOffset(200, 40), Vector3.zero, 90)
	Build.label(showcaseSign, "RAREST FINDS", Color3.fromRGB(255, 220, 120))

	local signPole = Build.part({
		Name = "SignPole",
		Size = Vector3.new(1, 14, 1),
		CFrame = plotFrame * CFrame.new(0, 7, 31),
		Color = Color3.fromRGB(50, 50, 70),
		Material = Enum.Material.Metal,
		Parent = model,
	})
	local sign = Build.billboard(signPole, UDim2.fromOffset(360, 110), Vector3.new(0, 10, 0), 400)
	sign.Name = "Sign"
	local ownerLabel = Build.label(sign, "Unclaimed Plot", Color3.new(1, 1, 1), UDim2.fromScale(1, 0.55))
	ownerLabel.Name = "Owner"
	local epsLabel =
		Build.label(sign, "", Color3.fromRGB(120, 255, 200), UDim2.fromScale(1, 0.45), UDim2.fromScale(0, 0.55))
	epsLabel.Name = "Eps"

	local spawnPad = Build.part({
		Name = "Spawn",
		Size = Vector3.new(7, 0.3, 7),
		CFrame = plotFrame * CFrame.new(0, 0.15, -27),
		Color = TRIM,
		Material = Enum.Material.Neon,
		Transparency = 0.5,
		Parent = model,
	})
	spawnPad.CanQuery = false

	local expandAnchor = Build.part({
		Name = "ExpandSign",
		Size = Vector3.new(3, 3, 3),
		CFrame = plotFrame * CFrame.new(0, 3, 0),
		Color = Color3.fromRGB(255, 210, 90),
		Material = Enum.Material.ForceField,
		Transparency = 1,
		Parent = model,
	})
	local expandPrompt = Instance.new("ProximityPrompt")
	expandPrompt.Name = "Prompt"
	expandPrompt.ActionText = "Expand"
	expandPrompt.ObjectText = "Plot expansion"
	expandPrompt.MaxActivationDistance = 16
	expandPrompt.RequiresLineOfSight = false
	expandPrompt.Enabled = false
	expandPrompt:SetAttribute("Action", "BuyExpansion")
	expandPrompt:AddTag("MachinePrompt")
	expandPrompt.Parent = expandAnchor
	local expandInfo = Build.billboard(expandAnchor, UDim2.fromOffset(220, 60), Vector3.new(0, 3, 0), 90)
	expandInfo.Name = "Info"
	expandInfo.Enabled = false
	local expandLabel = Build.label(expandInfo, "", Color3.fromRGB(255, 220, 120))
	expandLabel.Name = "Text"

	return model
end

-- Rendering ---------------------------------------------------------------------------

local function setPedestalLocked(pedestal: Model, locked: boolean)
	local base = pedestal:FindFirstChild("Base") :: BasePart
	local ring = pedestal:FindFirstChild("Ring") :: BasePart
	local hitbox = pedestal:FindFirstChild("Hitbox") :: BasePart
	base.Transparency = if locked then 0.85 else 0
	base.Material = if locked then Enum.Material.ForceField else Enum.Material.Metal
	base.CanCollide = not locked
	ring.Transparency = if locked then 1 else 0
	hitbox:SetAttribute("Locked", locked)
end

local function renderSlots(index: number, profile: any)
	local model = plotModels[index]
	local state = rendered[index]
	local plotFrame = Plots.cframe(index)
	local slotsFolder = model:FindFirstChild("Slots") :: Folder
	for slot = 1, PlotConfig.TotalSlots do
		local pedestal = slotsFolder:FindFirstChild("Slot_" .. slot) :: Model
		local unlocked = PlotConfig.isSlotUnlocked(slot, profile.expansion)
		if state.unlocked[slot] ~= unlocked then
			state.unlocked[slot] = unlocked
			setPedestalLocked(pedestal, not unlocked)
		end
		local key = if unlocked then profile.placed[tostring(slot)] or "" else ""
		if state.slots[slot] == key then
			continue
		end
		state.slots[slot] = key
		local old = pedestal:FindFirstChild("Artifact")
		if old then
			old:Destroy()
		end
		local ring = pedestal:FindFirstChild("Ring") :: BasePart
		local hitbox = pedestal:FindFirstChild("Hitbox") :: BasePart
		local item = Items.parse(key)
		if item then
			local artifactModel = ArtifactModels.build(item.id, { mutation = item.mut, stars = item.stars })
			artifactModel.Name = "Artifact"
			artifactModel:PivotTo(plotFrame * Plots.slotLocal(slot) * CFrame.new(0, 4.3, 0))
			artifactModel:AddTag("FloatingArtifact")
			artifactModel.Parent = pedestal
			local rarity = Rarities.get(Items.rarityOf(item))
			ring.Color = if rarity then rarity.color else EMPTY_RING
			hitbox:SetAttribute("ItemKey", key)
		else
			ring.Color = EMPTY_RING
			hitbox:SetAttribute("ItemKey", nil)
		end
	end
end

local function machineInfo(machine: Machines.Machine, profile: any): (string, string, string?)
	local state = profile.machines[machine.id]
	if state then
		local detail = "Level " .. state.level
		if machine.kind == "fabricator" then
			return machine.name, detail, "Open Box"
		elseif machine.kind == "fusion" then
			return machine.name, detail, "Fuse"
		end
		return machine.name, detail, "Upgrade"
	end
	if profile.rebirths < machine.rebirthRequired then
		return machine.name, "Requires " .. machine.rebirthRequired .. " rebirth", nil
	end
	return machine.name, "⚡ " .. Format.number(machine.cost), "Buy"
end

local function renderMachines(index: number, profile: any)
	local model = plotModels[index]
	local state = rendered[index]
	local plotFrame = Plots.cframe(index)
	local machinesFolder = model:FindFirstChild("Machines") :: Folder
	for _, machine in Machines.List do
		local pad = machinesFolder:FindFirstChild("Pad_" .. machine.pad) :: Model
		local owned = profile.machines[machine.id]
		local mode = if owned then "owned" else "holo"
		local title, detail, action = machineInfo(machine, profile)
		local plate = pad:FindFirstChild("Plate") :: BasePart
		local info = plate:FindFirstChild("Info") :: BillboardGui
		local prompt = plate:FindFirstChild("Prompt") :: ProximityPrompt
		(info:FindFirstChild("Title") :: TextLabel).Text = title;
		(info:FindFirstChild("Detail") :: TextLabel).Text = detail
		prompt.ObjectText = machine.name
		prompt.ActionText = action or "Locked"
		prompt.Enabled = action ~= nil
		prompt:SetAttribute("MachineId", machine.id)
		local promptAction = if not owned
			then "BuyMachine"
			elseif machine.kind == "fabricator" then "OpenBox"
			elseif machine.kind == "fusion" then "OpenFusion"
			else "OpenShop"
		prompt:SetAttribute("Action", promptAction)
		if state.machines[machine.id] == mode then
			continue
		end
		state.machines[machine.id] = mode
		local old = pad:FindFirstChild("Machine")
		if old then
			old:Destroy()
		end
		local machineModel = if owned then MachineModels.build(machine.id) else MachineModels.hologram(machine.id)
		machineModel.Name = "Machine"
		machineModel:PivotTo(plotFrame * Plots.padLocal(machine.pad) * CFrame.new(0, 0.6, 0))
		machineModel.Parent = pad
	end
end

local function renderExpansion(index: number, profile: any)
	local model = plotModels[index]
	local state = rendered[index]
	if state.expansion == profile.expansion then
		return
	end
	state.expansion = profile.expansion
	local plotFrame = Plots.cframe(index)
	local expansion = PlotConfig.getExpansion(profile.expansion)
	local spacing = PlotConfig.SlotSpacing
	local width = expansion.columns * spacing + 2
	local depth = expansion.rows * spacing + 2
	local firstSlot = Plots.slotLocal(1)
	local center = firstSlot.Position
		+ Vector3.new((expansion.columns - 1) * spacing / 2, 0, (expansion.rows - 1) * spacing / 2)
	local floor = model:FindFirstChild("Floor") :: BasePart
	floor.Size = Vector3.new(width, 0.2, depth)
	floor.CFrame = plotFrame * CFrame.new(center.X, 0.1, center.Z)

	local anchor = model:FindFirstChild("ExpandSign") :: BasePart
	local prompt = anchor:FindFirstChild("Prompt") :: ProximityPrompt
	local info = anchor:FindFirstChild("Info") :: BillboardGui
	if profile.expansion >= PlotConfig.MaxExpansionLevel then
		prompt.Enabled = false
		info.Enabled = false
		anchor.Transparency = 1
		return
	end
	local nextExpansion = PlotConfig.getExpansion(profile.expansion + 1)
	-- Centre of the pedestals the next expansion unlocks.
	local sum, count = Vector3.zero, 0
	for slot = 1, PlotConfig.TotalSlots do
		if
			PlotConfig.isSlotUnlocked(slot, profile.expansion + 1)
			and not PlotConfig.isSlotUnlocked(slot, profile.expansion)
		then
			sum += Plots.slotLocal(slot).Position
			count += 1
		end
	end
	local target = if count > 0 then sum / count else Vector3.zero
	anchor.CFrame = plotFrame * CFrame.new(target.X, 7, target.Z)
	anchor.Transparency = 0.2
	prompt.Enabled = true
	info.Enabled = true
	(info:FindFirstChild("Text") :: TextLabel).Text = "EXPAND  ⚡ " .. Format.number(nextExpansion.cost)
end

local function rarestDiscoveries(profile: any): { string }
	local found = {}
	for artifactId in profile.collection do
		local artifact = Artifacts.get(artifactId)
		if artifact then
			table.insert(found, artifact)
		end
	end
	table.sort(found, function(a, b)
		local ra, rb = Rarities.order(a.rarity), Rarities.order(b.rarity)
		if ra ~= rb then
			return ra > rb
		end
		return a.eps > b.eps
	end)
	local ids = {}
	for i = 1, math.min(3, #found) do
		table.insert(ids, found[i].id)
	end
	return ids
end

local function renderShowcase(index: number, profile: any)
	local model = plotModels[index]
	local state = rendered[index]
	local ids = rarestDiscoveries(profile)
	local signature = table.concat(ids, ",")
	if state.showcase == signature then
		return
	end
	state.showcase = signature
	local showcase = model:FindFirstChild("Showcase") :: Model
	for _, child in showcase:GetChildren() do
		if child.Name == "Display" then
			child:Destroy()
		end
	end
	local plotFrame = Plots.cframe(index)
	for slot, artifactId in ids do
		local display = ArtifactModels.build(artifactId)
		display.Name = "Display"
		display:PivotTo(plotFrame * SHOWCASE_LOCAL[slot] * CFrame.new(0, 4.6, 0))
		display:AddTag("FloatingArtifact")
		display.Parent = showcase
	end
end

function Plots.refresh(session: any)
	local index = session.plot
	if not plotModels[index] then
		return
	end
	local profile = session.profile
	renderSlots(index, profile)
	renderMachines(index, profile)
	renderExpansion(index, profile)
	renderShowcase(index, profile)
end

function Plots.refreshSlots(session: any)
	renderSlots(session.plot, session.profile)
end

function Plots.refreshMachines(session: any)
	renderMachines(session.plot, session.profile)
end

function Plots.refreshExpansion(session: any)
	renderExpansion(session.plot, session.profile)
	renderSlots(session.plot, session.profile)
end

function Plots.refreshShowcase(session: any)
	renderShowcase(session.plot, session.profile)
end

function Plots.updateSign(session: any, eps: number)
	local model = plotModels[session.plot]
	if not model then
		return
	end
	local pole = model:FindFirstChild("SignPole")
	local sign = pole and pole:FindFirstChild("Sign")
	if sign then
		local text = "⚡ " .. Format.number(eps) .. "/s"
		if session.profile.rebirths > 0 then
			text ..= "  •  ♻ " .. session.profile.rebirths
		end
		local label = sign:FindFirstChild("Eps") :: TextLabel
		if label.Text ~= text then
			label.Text = text
		end
	end
end

function Plots.setSurge(session: any, active: boolean)
	local model = plotModels[session.plot]
	if model then
		model:SetAttribute("Surging", active)
	end
end

local function reset(index: number)
	local model = plotModels[index]
	if model then
		model:Destroy()
	end
	local folder = (World.folder() :: Instance):FindFirstChild("Plots") :: Folder
	plotModels[index] = buildShell(index, folder)
	rendered[index] = newRendered()
end

-- Assignment --------------------------------------------------------------------------

function Plots.assign(session: any): number?
	for index = 1, PlotConfig.MaxPlots do
		if owners[index] == nil then
			owners[index] = session
			local model = plotModels[index]
			model:SetAttribute("OwnerUserId", session.userId)
			model:SetAttribute("OwnerName", session.player.DisplayName)
			local pole = model:FindFirstChild("SignPole")
			local sign = pole and pole:FindFirstChild("Sign")
			if sign then
				(sign:FindFirstChild("Owner") :: TextLabel).Text = session.player.DisplayName .. "'s Factory"
			end
			session.plot = index
			Plots.refresh(session)
			Plots.updateSign(session, 0)
			-- The character may have spawned before the plot was assigned.
			task.defer(Plots.teleport, session.player, index)
			return index
		end
	end
	return nil
end

function Plots.release(session: any)
	local index = session.plot
	if owners[index] == session then
		owners[index] = nil
		reset(index)
	end
end

function Plots.ownerOf(index: number): any
	return owners[index]
end

function Plots.teleport(player: Player, index: number)
	local character = player.Character
	if character and plotModels[index] then
		character:PivotTo(Plots.spawnCFrame(index))
	end
end

local function sessionPlot(player: Player): number?
	for index, session in owners do
		if session.player == player then
			return index
		end
	end
	return nil
end

function Plots.init()
	local folder = (World.folder() :: Instance):FindFirstChild("Plots") :: Folder
	for index = 1, PlotConfig.MaxPlots do
		plotModels[index] = buildShell(index, folder)
		rendered[index] = newRendered()
	end
	World.setRescueTarget(function(player)
		local index = sessionPlot(player)
		return if index then Plots.spawnCFrame(index) else nil
	end)
end

function Plots.start()
	local function onCharacter(player: Player, character: Model)
		task.spawn(function()
			-- The root part can arrive slightly after CharacterAdded on a real server.
			character:WaitForChild("HumanoidRootPart", 5)
			task.wait(0.1)
			local index = sessionPlot(player)
			if index and character.Parent then
				character:PivotTo(Plots.spawnCFrame(index))
			end
		end)
	end
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		if player.Character then
			onCharacter(player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

return Plots
