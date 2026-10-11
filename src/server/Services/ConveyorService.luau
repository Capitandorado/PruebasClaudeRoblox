--!strict
--[[
	ConveyorService
	===============
	Gestiona la cinta transportadora compartida:
	1. Cada `SpawnInterval` segundos crea una semilla aleatoria (según rarezas).
	2. Las semillas avanzan por la cinta a velocidad constante.
	3. Al llegar al final, si nadie las ha comprado, desaparecen.
	4. Un jugador la compra con su ProximityPrompt. El servidor comprueba que
	   siga disponible y que el jugador tenga dinero; si otro jugador la compró
	   antes, la compra se rechaza.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local SeedConfig = require(Shared:WaitForChild("SeedConfig"))
local Tags = require(Shared:WaitForChild("Tags"))

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local ModelFactory = require(script.Parent:WaitForChild("ModelFactory"))

type SeedInfo = SeedConfig.SeedInfo

-- Una semilla que está sobre la cinta.
type ConveyorItem = {
	Seed: SeedInfo,
	Model: Model,
	Distance: number, -- Studs recorridos desde el inicio de la cinta
	HeightOffset: number, -- Altura sobre la superficie de la cinta
	Available: boolean, -- false en cuanto alguien la compra o desaparece
}

local ConveyorService = {}

local belt: BasePart
local seedsFolder: Folder
local items: { ConveyorItem } = {}
local rng = Random.new()

--------------------------------------------------------------------------------
-- Geometría de la cinta
--------------------------------------------------------------------------------

-- CFrame del punto de inicio de la cinta (centro de la cara trasera, encima).
local function getStartCFrame(): CFrame
	return belt.CFrame * CFrame.new(0, belt.Size.Y / 2, belt.Size.Z / 2)
end

local function getLength(): number
	return belt.Size.Z
end

--------------------------------------------------------------------------------
-- Creación y eliminación de semillas
--------------------------------------------------------------------------------

-- Cartel flotante con nombre, rareza (en su color) y precio.
local function createLabel(seed: SeedInfo, adornee: BasePart, height: number)
	local rarity = SeedConfig.getRarity(seed.Rarity)

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "SeedLabel"
	billboard.Size = UDim2.fromOffset(160, 66)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, height + 1.8, 0)
	billboard.MaxDistance = 60
	billboard.Adornee = adornee

	local layout = Instance.new("UIListLayout")
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = billboard

	local lines = {
		{ text = seed.DisplayName, color = Color3.new(1, 1, 1) },
		{ text = rarity.DisplayName, color = rarity.Color },
		{ text = `${seed.Price}`, color = Color3.fromRGB(120, 255, 120) },
	}
	for i, line in lines do
		local label = Instance.new("TextLabel")
		label.LayoutOrder = i
		label.Size = UDim2.new(1, 0, 1 / #lines, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextColor3 = line.color
		label.TextStrokeTransparency = 0.2
		label.Text = line.text
		label.Parent = billboard
	end

	billboard.Parent = adornee
end

local function removeItem(item: ConveyorItem)
	item.Available = false
	local index = table.find(items, item)
	if index then
		table.remove(items, index)
	end
	item.Model:Destroy()
end

-- Intento de compra. Se ejecuta en el servidor, así que el resultado es fiable.
local function tryPurchase(item: ConveyorItem, player: Player)
	-- ¿Sigue en la cinta? (otro jugador puede haberla comprado justo antes)
	if not item.Available then
		PlayerDataService.notify(player, "¡Otro jugador ya compró esa semilla!", Color3.fromRGB(255, 120, 120))
		return
	end

	if not PlayerDataService.trySpend(player, item.Seed.Price) then
		PlayerDataService.notify(player, `No tienes dinero suficiente (cuesta ${item.Seed.Price})`, Color3.fromRGB(255, 120, 120))
		return
	end

	-- Marcamos y quitamos la semilla ANTES de dársela, para que nadie más pueda comprarla.
	removeItem(item)
	PlayerDataService.addSeed(player, item.Seed.Id, 1)
	PlayerDataService.notify(player, `Has comprado: {item.Seed.DisplayName}`, SeedConfig.getRarity(item.Seed.Rarity).Color)
end

local function spawnSeed()
	if #items >= GameConfig.Conveyor.MaxSeeds then
		return
	end

	local seed = SeedConfig.rollSeed(rng)
	local model = ModelFactory.createSeedModel(seed)
	local root = model.PrimaryPart :: BasePart
	local heightOffset = model:GetExtentsSize().Y / 2 + 0.1

	local item: ConveyorItem = {
		Seed = seed,
		Model = model,
		Distance = 0,
		HeightOffset = heightOffset,
		Available = true,
	}

	model:SetAttribute("SeedId", seed.Id)
	model:PivotTo(getStartCFrame() * CFrame.new(0, heightOffset, 0))
	createLabel(seed, root, heightOffset)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BuyPrompt"
	prompt.ActionText = `Comprar (${seed.Price})`
	prompt.ObjectText = seed.DisplayName
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Triggered:Connect(function(player: Player)
		tryPurchase(item, player)
	end)
	prompt.Parent = root

	model.Parent = seedsFolder
	CollectionService:AddTag(model, Tags.ConveyorSeed)
	table.insert(items, item)
end

--------------------------------------------------------------------------------
-- Bucle principal
--------------------------------------------------------------------------------

local function update(dt: number)
	local speed = GameConfig.Conveyor.Speed
	local length = getLength()
	local start = getStartCFrame()
	local spin = CFrame.Angles(0, os.clock() * 1.5, 0)

	-- Recorremos al revés para poder eliminar mientras iteramos.
	for i = #items, 1, -1 do
		local item = items[i]
		item.Distance += speed * dt
		if item.Distance >= length then
			removeItem(item) -- Llegó al final sin que nadie la comprase
		else
			-- Avanza hacia -Z local (LookVector de la cinta).
			item.Model:PivotTo(start * CFrame.new(0, item.HeightOffset, -item.Distance) * spin)
		end
	end
end

function ConveyorService.init()
	local tagged = CollectionService:GetTagged(Tags.Conveyor)
	local found = tagged[1]
	assert(found and found:IsA("BasePart"), "[ConveyorService] No hay ninguna Part con la Tag 'Conveyor'")
	belt = found :: BasePart

	seedsFolder = Instance.new("Folder")
	seedsFolder.Name = "ConveyorSeeds"
	seedsFolder.Parent = workspace

	RunService.Heartbeat:Connect(update)

	task.spawn(function()
		while true do
			spawnSeed()
			task.wait(GameConfig.Conveyor.SpawnInterval)
		end
	end)
end

return ConveyorService
