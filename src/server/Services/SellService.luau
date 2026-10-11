--!strict
--[[
	SellService
	===========
	Puesto de venta: al activar su ProximityPrompt, el servidor vende TODOS los
	frutos del jugador. El precio de cada fruto sale de SeedConfig (SellValue),
	nunca del cliente.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SeedConfig = require(Shared:WaitForChild("SeedConfig"))
local Tags = require(Shared:WaitForChild("Tags"))

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))

local SellService = {}

-- Vende todos los frutos del jugador y devuelve el dinero ganado.
function SellService.sellAll(player: Player): number
	local fruits = PlayerDataService.takeAllFruits(player)
	local total, count = 0, 0
	for seedId, amount in fruits do
		local seed = SeedConfig.get(seedId)
		if seed and amount > 0 then
			total += seed.SellValue * amount
			count += amount
		end
	end

	if count == 0 then
		PlayerDataService.notify(player, "No tienes frutos para vender", Color3.fromRGB(255, 200, 120))
		return 0
	end

	PlayerDataService.addMoney(player, total)
	PlayerDataService.notify(player, `Has vendido {count} fruto(s) por ${total}`, Color3.fromRGB(120, 255, 120))
	return total
end

-- Devuelve la Part a la que se engancha el prompt (la Part o la PrimaryPart del Model).
local function getAnchorPart(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	elseif instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function setupStand(stand: Instance)
	local anchor = getAnchorPart(stand)
	if not anchor or anchor:FindFirstChild("SellPrompt") then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SellPrompt"
	prompt.ActionText = "Vender frutos"
	prompt.ObjectText = "Puesto de venta"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Triggered:Connect(function(player: Player)
		SellService.sellAll(player)
	end)
	prompt.Parent = anchor
end

function SellService.init()
	for _, stand in CollectionService:GetTagged(Tags.SellStand) do
		setupStand(stand)
	end
	-- Por si se añaden puestos más tarde.
	CollectionService:GetInstanceAddedSignal(Tags.SellStand):Connect(setupStand)
end

return SellService
