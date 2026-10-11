--!strict
--[[
	ModelFactory
	============
	Crea los modelos visuales de semillas (en la cinta) y plantas (en los huecos).

	Si existe un modelo definitivo en ServerStorage lo clona; si no, genera un
	placeholder con formas simples:

		ServerStorage
		└── Assets
		    ├── Seeds   -> Model/Part con el nombre del Id de la semilla (ej. "FresaLunar")
		    └── Plants  -> Model/Part con el nombre del Id de la semilla

	Requisitos de los modelos definitivos:
	- Seeds: cualquier Model o Part. Se coloca centrado sobre la cinta.
	- Plants: Model cuyo Pivot esté en la BASE de la planta (a ras de suelo) y
	  con tamaño de planta madura. El servidor lo escala con Model:ScaleTo().
]]

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SeedConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SeedConfig"))

type SeedInfo = SeedConfig.SeedInfo

local ModelFactory = {}

-- Busca ServerStorage.Assets.<category>.<seedId> y lo devuelve como Model.
local function cloneAsset(category: string, seedId: string): Model?
	local assets = ServerStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild(category)
	local template = folder and folder:FindFirstChild(seedId)
	if not template then
		return nil
	end

	local clone = template:Clone()
	if clone:IsA("Model") then
		if not clone.PrimaryPart then
			clone.PrimaryPart = clone:FindFirstChildWhichIsA("BasePart", true)
		end
		return clone
	elseif clone:IsA("BasePart") then
		local model = Instance.new("Model")
		clone.Parent = model
		model.PrimaryPart = clone
		return model
	end

	clone:Destroy()
	warn(`[ModelFactory] Assets.{category}.{seedId} debe ser un Model o una Part`)
	return nil
end

-- Ancla todas las piezas y desactiva colisiones (son objetos decorativos).
local function prepareParts(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
		end
	end
end

local function makePart(name: string, shape: Enum.PartType, size: Vector3, color: Color3, material: Enum.Material?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

-- Modelo de una semilla para la cinta. Su PrimaryPart sirve de ancla para el
-- cartel (BillboardGui) y el ProximityPrompt.
function ModelFactory.createSeedModel(seed: SeedInfo): Model
	local model = cloneAsset("Seeds", seed.Id)
	if not model then
		model = Instance.new("Model")
		local rarity = SeedConfig.getRarity(seed.Rarity)

		-- Placeholder: esfera del color de la semilla con un aro de su rareza.
		local body = makePart("Body", Enum.PartType.Ball, Vector3.new(2, 2, 2), seed.Color)
		body.Parent = model

		local ring = makePart("RarityRing", Enum.PartType.Cylinder, Vector3.new(0.2, 2.8, 2.8), rarity.Color, Enum.Material.Neon)
		ring.CFrame = body.CFrame * CFrame.Angles(0, 0, math.rad(90))
		ring.Parent = model

		model.PrimaryPart = body
	end

	assert(model)
	model.Name = "Seed_" .. seed.Id
	prepareParts(model)
	return model
end

-- Modelo de una planta. Se devuelve a escala 1 (madura) con el Pivot en la base;
-- el PlotService lo escala según la fase de crecimiento.
function ModelFactory.createPlantModel(seed: SeedInfo): Model
	local model = cloneAsset("Plants", seed.Id)
	if not model then
		model = Instance.new("Model")

		-- Placeholder: tallo verde + copa del color de la semilla.
		local stem = makePart("Stem", Enum.PartType.Block, Vector3.new(0.6, 4, 0.6), Color3.fromRGB(70, 160, 60), Enum.Material.Grass)
		stem.CFrame = CFrame.new(0, 2, 0)
		stem.Parent = model

		local head = makePart("Head", Enum.PartType.Ball, Vector3.new(3, 3, 3), seed.Color)
		head.CFrame = CFrame.new(0, 5, 0)
		head.Parent = model

		model.PrimaryPart = stem
		model.WorldPivot = CFrame.new(0, 0, 0) -- base de la planta
	end

	assert(model)
	model.Name = "Plant_" .. seed.Id
	prepareParts(model)
	return model
end

return ModelFactory
