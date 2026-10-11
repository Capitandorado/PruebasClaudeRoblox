--!strict
--[[
	MapBuilder
	==========
	Se asegura de que el mapa tenga todo lo necesario para jugar. Por cada
	elemento busca primero un objeto con su Tag (ver Shared/Tags); si no existe,
	genera un placeholder con bloques simples.

	Así puedes construir el mapa definitivo en Studio, ponerle las Tags y el
	código lo usará sin cambios:

	- Tag "Conveyor"  : una Part. Las semillas recorren su eje Z local, desde
	                    la cara trasera (+Z) hasta la delantera (-Z, LookVector).
	- Tag "Plot"      : un Model con una Part "Base" y Parts hijas con Tag
	                    "PlotSlot" (los huecos de tierra). Si existe al menos una
	                    parcela con Tag no se genera ninguna.
	- Tag "SellStand" : una Part o Model (con PrimaryPart) del puesto de venta.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Tags = require(Shared:WaitForChild("Tags"))

local MapBuilder = {}

--------------------------------------------------------------------------------
-- Utilidades
--------------------------------------------------------------------------------

local function getOrCreateFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function makeBlock(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(part :: any)[key] = value
	end
	return part
end

local function addSign(adornee: BasePart, text: string, offsetY: number): TextLabel
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Sign"
	billboard.Size = UDim2.fromOffset(220, 50)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 120
	billboard.Adornee = adornee

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Text = text
	label.Parent = billboard

	billboard.Parent = adornee
	return label
end

--------------------------------------------------------------------------------
-- Generadores de placeholders
--------------------------------------------------------------------------------

local function ensureGround(map: Folder)
	if workspace:FindFirstChild("Baseplate") or map:FindFirstChild("Suelo") then
		return
	end
	makeBlock({
		Name = "Suelo",
		Size = Vector3.new(240, 1, 240),
		Position = Vector3.new(0, -0.5, 0),
		Color = Color3.fromRGB(110, 170, 80),
		Material = Enum.Material.Grass,
	}).Parent = map
end

local function ensureSpawn(map: Folder)
	if workspace:FindFirstChildWhichIsA("SpawnLocation", true) then
		return
	end
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "Spawn"
	spawnLocation.Anchored = true
	spawnLocation.Size = Vector3.new(8, 1, 8)
	spawnLocation.Position = GameConfig.SellStandPosition + Vector3.new(0, 0, -12)
	spawnLocation.Neutral = true
	spawnLocation.Duration = 0
	spawnLocation.Parent = map
end

local function ensureConveyor(map: Folder)
	if #CollectionService:GetTagged(Tags.Conveyor) > 0 then
		return
	end
	local cfg = GameConfig.Conveyor

	local belt = makeBlock({
		Name = "Conveyor",
		Size = cfg.Size,
		Position = cfg.Position,
		Color = Color3.fromRGB(45, 45, 50),
		Material = Enum.Material.DiamondPlate,
	})
	belt.Parent = map
	CollectionService:AddTag(belt, Tags.Conveyor)

	-- Barandillas decorativas a ambos lados.
	for _, side in { -1, 1 } do
		makeBlock({
			Name = "ConveyorRail",
			Size = Vector3.new(0.6, 1.4, cfg.Size.Z),
			Position = cfg.Position + Vector3.new(side * (cfg.Size.X / 2 + 0.3), 0.2, 0),
			Color = Color3.fromRGB(240, 200, 40),
		}).Parent = map
	end

	-- Bloques de inicio (verde) y fin (rojo) para que se vea la dirección.
	for _, info in { { z = cfg.Size.Z / 2, color = Color3.fromRGB(60, 200, 90) }, { z = -cfg.Size.Z / 2, color = Color3.fromRGB(220, 60, 60) } } do
		makeBlock({
			Name = "ConveyorEnd",
			Size = Vector3.new(cfg.Size.X + 1.2, 3, 1),
			Position = cfg.Position + Vector3.new(0, 1, info.z + math.sign(info.z) * 0.5),
			Color = info.color,
			Material = Enum.Material.Neon,
		}).Parent = map
	end

	addSign(belt, "🌱 Cinta de semillas", 6)
end

local function ensureSellStand(map: Folder)
	if #CollectionService:GetTagged(Tags.SellStand) > 0 then
		return
	end
	local pos = GameConfig.SellStandPosition

	local stand = Instance.new("Model")
	stand.Name = "SellStand"

	local counter = makeBlock({
		Name = "Counter",
		Size = Vector3.new(10, 3, 4),
		Position = pos + Vector3.new(0, 1, 0),
		Color = Color3.fromRGB(160, 110, 60),
		Material = Enum.Material.WoodPlanks,
	})
	counter.Parent = stand

	for _, x in { -4.5, 4.5 } do
		makeBlock({
			Name = "Pole",
			Size = Vector3.new(0.6, 6, 0.6),
			Position = pos + Vector3.new(x, 5.5, 0),
			Color = Color3.fromRGB(120, 80, 40),
		}).Parent = stand
	end

	makeBlock({
		Name = "Roof",
		Size = Vector3.new(11, 0.6, 5),
		Position = pos + Vector3.new(0, 8.7, 0),
		Color = Color3.fromRGB(220, 60, 60),
	}).Parent = stand

	stand.PrimaryPart = counter
	stand.Parent = map
	CollectionService:AddTag(stand, Tags.SellStand)

	addSign(counter, "💰 Puesto de venta", 9)
end

-- Crea una parcela en `center` con los huecos de tierra iniciales.
local function createPlot(parent: Folder, index: number, center: Vector3)
	local cfg = GameConfig.Plots

	local plot = Instance.new("Model")
	plot.Name = "Plot_" .. index
	plot:SetAttribute("PlotIndex", index)

	local base = makeBlock({
		Name = "Base",
		Size = cfg.Size,
		Position = center,
		Color = Color3.fromRGB(150, 200, 110),
		Material = Enum.Material.Grass,
	})
	base.Parent = plot
	plot.PrimaryPart = base

	local slots = getOrCreateFolder(plot, "Slots")
	-- Rejilla lo más cuadrada posible con StartingSlots huecos.
	local columns = math.ceil(math.sqrt(cfg.StartingSlots))
	local rows = math.ceil(cfg.StartingSlots / columns)
	for i = 1, cfg.StartingSlots do
		local col = (i - 1) % columns
		local row = math.floor((i - 1) / columns)
		local offset = Vector3.new(
			(col - (columns - 1) / 2) * cfg.SlotSpacing,
			cfg.Size.Y / 2 + cfg.SlotSize.Y / 2,
			(row - (rows - 1) / 2) * cfg.SlotSpacing
		)
		local slot = makeBlock({
			Name = "Slot_" .. i,
			Size = cfg.SlotSize,
			Position = center + offset,
			Color = Color3.fromRGB(100, 65, 40),
			Material = Enum.Material.Ground,
		})
		slot:SetAttribute("SlotIndex", i)
		slot.Parent = slots
		CollectionService:AddTag(slot, Tags.PlotSlot)
	end

	addSign(base, "Parcela libre", 10)

	plot.Parent = parent
	CollectionService:AddTag(plot, Tags.Plot)
end

local function ensurePlots()
	if #CollectionService:GetTagged(Tags.Plot) > 0 then
		return
	end
	local cfg = GameConfig.Plots
	local plotsFolder = getOrCreateFolder(workspace, "Plots")

	-- Dos columnas de parcelas, una a cada lado de la cinta.
	local perSide = math.ceil(cfg.MaxPlots / 2)
	local distanceX = GameConfig.Conveyor.Size.X / 2 + cfg.Size.X / 2 + 12
	local spacingZ = cfg.Size.Z + 4
	for i = 1, cfg.MaxPlots do
		local side = if i % 2 == 1 then -1 else 1
		local rowIndex = math.floor((i - 1) / 2)
		local z = (rowIndex - (perSide - 1) / 2) * spacingZ
		createPlot(plotsFolder, i, Vector3.new(side * distanceX, cfg.Size.Y / 2, z))
	end
end

--------------------------------------------------------------------------------
-- API pública
--------------------------------------------------------------------------------

function MapBuilder.build()
	local map = getOrCreateFolder(workspace, "Map")
	ensureGround(map)
	ensureSpawn(map)
	ensureConveyor(map)
	ensureSellStand(map)
	ensurePlots()
end

return MapBuilder
