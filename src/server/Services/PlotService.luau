--!strict
--[[
	PlotService
	===========
	Gestiona las parcelas de los jugadores y todo el ciclo de las plantas:

	- Asigna una parcela libre a cada jugador al entrar (máximo GameConfig.Plots.MaxPlots)
	  y la libera al salir. El jugador aparece en su parcela.
	- Atiende la petición del cliente "PlantSeed": valida todo en el servidor
	  (semilla válida, que la tenga, que esté en su parcela, que haya hueco...) y
	  planta la semilla en el hueco libre más cercano al jugador.
	- Hace crecer las plantas por fases (cambia su tamaño) según GrowTime.
	- Cuando una planta madura aparece un ProximityPrompt para cosecharla; sólo
	  el dueño de la parcela puede hacerlo y recibe un fruto en su inventario.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local SeedConfig = require(Shared:WaitForChild("SeedConfig"))
local Tags = require(Shared:WaitForChild("Tags"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local ModelFactory = require(script.Parent:WaitForChild("ModelFactory"))

type SeedInfo = SeedConfig.SeedInfo

type PlantState = {
	Seed: SeedInfo,
	PlantedAt: number, -- os.clock() del momento de plantar
	Model: Model,
	Stage: number, -- Fase visual actual (índice de GameConfig.GrowthStageScales)
	Mature: boolean,
	Label: TextLabel, -- Texto con el progreso encima del hueco
	Billboard: BillboardGui,
	Prompt: ProximityPrompt?, -- Prompt de cosecha (sólo cuando madura)
}

type SlotState = {
	Part: BasePart,
	Plant: PlantState?,
}

type PlotState = {
	Model: Model,
	Base: BasePart,
	Slots: { SlotState },
	Owner: Player?,
	Sign: TextLabel?,
}

local PlotService = {}

local plots: { PlotState } = {}
local plotByPlayer: { [Player]: PlotState } = {}
local lastPlantRequest: { [Player]: number } = {}
local plantsFolder: Folder

local GOOD_COLOR = Color3.fromRGB(120, 255, 120)
local BAD_COLOR = Color3.fromRGB(255, 120, 120)

--------------------------------------------------------------------------------
-- Plantas
--------------------------------------------------------------------------------

local function getSlotTop(slot: SlotState): CFrame
	return slot.Part.CFrame * CFrame.new(0, slot.Part.Size.Y / 2, 0)
end

local function removePlant(slot: SlotState)
	local plant = slot.Plant
	if not plant then
		return
	end
	slot.Plant = nil
	plant.Model:Destroy()
	plant.Billboard:Destroy()
	if plant.Prompt then
		plant.Prompt:Destroy()
	end
end

local function setStage(slot: SlotState, plant: PlantState, stage: number)
	if plant.Stage == stage then
		return
	end
	plant.Stage = stage
	plant.Model:ScaleTo(GameConfig.GrowthStageScales[stage])
	plant.Model:PivotTo(getSlotTop(slot))
end

-- Cosecha (llamado desde el ProximityPrompt, en el servidor).
local function tryHarvest(plot: PlotState, slot: SlotState, player: Player)
	local plant = slot.Plant
	if plot.Owner ~= player then
		PlayerDataService.notify(player, "Esta planta no es tuya", BAD_COLOR)
		return
	end
	if not plant or not plant.Mature then
		return
	end

	local seed = plant.Seed
	removePlant(slot)
	PlayerDataService.addFruit(player, seed.Id, 1)
	PlayerDataService.notify(player, `Has cosechado: fruto de {seed.DisplayName}`, SeedConfig.getRarity(seed.Rarity).Color)
end

local function makeMature(plot: PlotState, slot: SlotState, plant: PlantState)
	plant.Mature = true
	plant.Label.Text = `{plant.Seed.DisplayName}\n¡Lista para cosechar!`
	plant.Label.TextColor3 = GOOD_COLOR

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "HarvestPrompt"
	prompt.ActionText = "Cosechar"
	prompt.ObjectText = plant.Seed.DisplayName
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Triggered:Connect(function(player: Player)
		tryHarvest(plot, slot, player)
	end)
	prompt.Parent = slot.Part
	plant.Prompt = prompt
end

local function plantSeed(slot: SlotState, seed: SeedInfo)
	local model = ModelFactory.createPlantModel(seed)
	model:SetAttribute("SeedId", seed.Id)

	-- Texto de progreso sobre el hueco (no sobre la planta, para que no se escale).
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "GrowLabel"
	billboard.Size = UDim2.fromOffset(170, 44)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 8, 0)
	billboard.MaxDistance = 70
	billboard.Adornee = slot.Part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextStrokeTransparency = 0.3
	label.TextColor3 = SeedConfig.getRarity(seed.Rarity).Color
	label.Text = seed.DisplayName
	label.Parent = billboard
	billboard.Parent = slot.Part

	local plant: PlantState = {
		Seed = seed,
		PlantedAt = os.clock(),
		Model = model,
		Stage = 0,
		Mature = false,
		Label = label,
		Billboard = billboard,
		Prompt = nil,
	}
	slot.Plant = plant

	setStage(slot, plant, 1)
	model.Parent = plantsFolder
	CollectionService:AddTag(model, Tags.Plant)
end

-- Actualiza todas las plantas: fase visual, texto de progreso y madurez.
local function growthTick()
	local stageCount = #GameConfig.GrowthStageScales
	local now = os.clock()

	for _, plot in plots do
		for _, slot in plot.Slots do
			local plant = slot.Plant
			if plant and not plant.Mature then
				local progress = math.clamp((now - plant.PlantedAt) / plant.Seed.GrowTime, 0, 1)
				if progress >= 1 then
					setStage(slot, plant, stageCount)
					makeMature(plot, slot, plant)
				else
					-- Las fases 1..N-1 se reparten el tiempo; la N es "madura".
					local stage = math.clamp(math.floor(progress * (stageCount - 1)) + 1, 1, stageCount - 1)
					setStage(slot, plant, stage)
					local remaining = math.ceil(plant.Seed.GrowTime * (1 - progress))
					plant.Label.Text = `{plant.Seed.DisplayName}\n{math.floor(progress * 100)}% ({remaining}s)`
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Parcelas y jugadores
--------------------------------------------------------------------------------

local function setSign(plot: PlotState, text: string)
	if plot.Sign then
		plot.Sign.Text = text
	end
end

local function teleportToPlot(player: Player, character: Model)
	local plot = plotByPlayer[player]
	if not plot then
		return
	end
	character:WaitForChild("HumanoidRootPart", 5)
	-- Borde delantero de la parcela, para no aparecer encima de los huecos.
	local base = plot.Base
	local target = base.CFrame * CFrame.new(0, base.Size.Y / 2 + 4, base.Size.Z / 2 - 3)
	character:PivotTo(CFrame.lookAt(target.Position, base.Position * Vector3.new(1, 0, 1) + Vector3.new(0, target.Y, 0)))
end

local function onPlayerAdded(player: Player)
	for _, plot in plots do
		if plot.Owner == nil then
			plot.Owner = player
			plotByPlayer[player] = plot
			plot.Model:SetAttribute("OwnerUserId", player.UserId)
			setSign(plot, `Parcela de {player.DisplayName}`)
			break
		end
	end

	if not plotByPlayer[player] then
		PlayerDataService.notify(player, "No quedan parcelas libres en este servidor", BAD_COLOR)
	end

	player.CharacterAdded:Connect(function(character)
		teleportToPlot(player, character)
	end)
	if player.Character then
		task.spawn(teleportToPlot, player, player.Character)
	end
end

local function onPlayerRemoving(player: Player)
	lastPlantRequest[player] = nil
	local plot = plotByPlayer[player]
	if not plot then
		return
	end
	plotByPlayer[player] = nil
	for _, slot in plot.Slots do
		removePlant(slot)
	end
	plot.Owner = nil
	plot.Model:SetAttribute("OwnerUserId", nil)
	setSign(plot, "Parcela libre")
end

-- Petición del cliente para plantar. NUNCA confiamos en lo que envía.
local function onPlantRequest(player: Player, seedId: any)
	-- 1. Límite de frecuencia.
	local now = os.clock()
	if now - (lastPlantRequest[player] or 0) < GameConfig.PlantCooldown then
		return
	end
	lastPlantRequest[player] = now

	-- 2. La semilla debe existir en la configuración (valida también el tipo).
	local seed = SeedConfig.get(seedId)
	if not seed then
		return
	end

	-- 3. El jugador debe tener parcela.
	local plot = plotByPlayer[player]
	if not plot then
		PlayerDataService.notify(player, "No tienes parcela", BAD_COLOR)
		return
	end

	-- 4. Debe tener esa semilla en el inventario.
	if PlayerDataService.getSeedCount(player, seed.Id) <= 0 then
		PlayerDataService.notify(player, "No tienes esa semilla", BAD_COLOR)
		return
	end

	-- 5. Debe estar cerca de su parcela.
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local offset = (root.Position - plot.Base.Position) * Vector3.new(1, 0, 1)
	if offset.Magnitude > GameConfig.Plots.MaxPlantDistance then
		PlayerDataService.notify(player, "Acércate a tu parcela para plantar", BAD_COLOR)
		return
	end

	-- 6. Hueco libre más cercano al jugador.
	local bestSlot: SlotState? = nil
	local bestDistance = math.huge
	for _, slot in plot.Slots do
		if not slot.Plant then
			local distance = (slot.Part.Position - root.Position).Magnitude
			if distance < bestDistance then
				bestSlot, bestDistance = slot, distance
			end
		end
	end
	if not bestSlot then
		PlayerDataService.notify(player, "No tienes huecos libres", BAD_COLOR)
		return
	end

	-- 7. Todo correcto: gastamos la semilla y plantamos.
	if PlayerDataService.tryRemoveSeed(player, seed.Id) then
		plantSeed(bestSlot, seed)
		PlayerDataService.notify(player, `Has plantado: {seed.DisplayName}`, GOOD_COLOR)
	end
end

-- Lee las parcelas del mapa (Models con Tag "Plot").
local function loadPlots()
	local models = {}
	for _, instance in CollectionService:GetTagged(Tags.Plot) do
		if instance:IsA("Model") then
			table.insert(models, instance)
		end
	end
	table.sort(models, function(a, b)
		local ia = a:GetAttribute("PlotIndex") or math.huge
		local ib = b:GetAttribute("PlotIndex") or math.huge
		if ia == ib then
			return a.Name < b.Name
		end
		return ia < ib
	end)

	for i, model in models do
		if i > GameConfig.Plots.MaxPlots then
			break
		end

		local base = model:FindFirstChild("Base")
		if not (base and base:IsA("BasePart")) then
			warn(`[PlotService] La parcela {model:GetFullName()} no tiene una Part llamada "Base"`)
			continue
		end

		local slotParts = {}
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") and CollectionService:HasTag(descendant, Tags.PlotSlot) then
				table.insert(slotParts, descendant)
			end
		end
		table.sort(slotParts, function(a, b)
			return (a:GetAttribute("SlotIndex") or 0) < (b:GetAttribute("SlotIndex") or 0)
		end)

		local slots: { SlotState } = {}
		for _, part in slotParts do
			table.insert(slots, { Part = part, Plant = nil })
		end

		local sign = base:FindFirstChild("Sign")
		local signLabel = sign and sign:FindFirstChild("Text")

		table.insert(plots, {
			Model = model,
			Base = base,
			Slots = slots,
			Owner = nil,
			Sign = if signLabel and signLabel:IsA("TextLabel") then signLabel else nil,
		})
	end
end

function PlotService.init()
	plantsFolder = Instance.new("Folder")
	plantsFolder.Name = "Plants"
	plantsFolder.Parent = workspace

	loadPlots()

	Remotes.event("PlantSeed").OnServerEvent:Connect(onPlantRequest)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	task.spawn(function()
		while true do
			growthTick()
			task.wait(GameConfig.GrowthTickInterval)
		end
	end)
end

return PlotService
