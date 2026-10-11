--!strict
--[[
	PlayerDataService
	=================
	Guarda (en memoria del servidor) el dinero y el inventario de cada jugador.
	Es la ÚNICA forma de modificar dinero e inventario: el resto de servicios
	llama a estas funciones y nunca toca los valores directamente.

	- El dinero se refleja en leaderstats para que se vea en la tabla de jugadores.
	- Cada cambio de inventario se envía al cliente con el remote InventoryUpdated.

	Nota: los datos no se guardan entre sesiones. Para persistencia, añade
	DataStoreService en `onPlayerAdded` / `onPlayerRemoving`.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local SeedConfig = require(Shared:WaitForChild("SeedConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))

export type Inventory = {
	Seeds: { [string]: number }, -- seedId -> cantidad de semillas
	Fruits: { [string]: number }, -- seedId -> cantidad de frutos
}

type PlayerData = {
	Money: number,
	Inventory: Inventory,
	MoneyValue: IntValue, -- Valor del leaderstats
}

local PlayerDataService = {}

local dataByPlayer: { [Player]: PlayerData } = {}

local inventoryUpdated = Remotes.event("InventoryUpdated")
local notifyRemote = Remotes.event("Notify")

--------------------------------------------------------------------------------
-- Internos
--------------------------------------------------------------------------------

-- Copia del inventario para enviar al cliente (nunca se envía la tabla real).
local function copyInventory(inventory: Inventory): Inventory
	return {
		Seeds = table.clone(inventory.Seeds),
		Fruits = table.clone(inventory.Fruits),
	}
end

local function pushInventory(player: Player)
	local data = dataByPlayer[player]
	if data then
		inventoryUpdated:FireClient(player, copyInventory(data.Inventory))
	end
end

local function addToBag(bag: { [string]: number }, seedId: string, amount: number)
	bag[seedId] = (bag[seedId] or 0) + amount
	if bag[seedId] <= 0 then
		bag[seedId] = nil
	end
end

local function onPlayerAdded(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local moneyValue = Instance.new("IntValue")
	moneyValue.Name = GameConfig.MoneyStatName
	moneyValue.Value = GameConfig.StartingMoney
	moneyValue.Parent = leaderstats

	leaderstats.Parent = player

	dataByPlayer[player] = {
		Money = GameConfig.StartingMoney,
		Inventory = { Seeds = {}, Fruits = {} },
		MoneyValue = moneyValue,
	}
	pushInventory(player)
end

local function onPlayerRemoving(player: Player)
	dataByPlayer[player] = nil
end

--------------------------------------------------------------------------------
-- API pública
--------------------------------------------------------------------------------

function PlayerDataService.getMoney(player: Player): number
	local data = dataByPlayer[player]
	return if data then data.Money else 0
end

-- Suma (o resta, si amount < 0) dinero. Nunca deja el dinero en negativo.
function PlayerDataService.addMoney(player: Player, amount: number)
	local data = dataByPlayer[player]
	if not data then
		return
	end
	data.Money = math.max(0, data.Money + math.floor(amount))
	data.MoneyValue.Value = data.Money
end

-- Intenta cobrar `amount`. Devuelve true si el jugador tenía dinero suficiente.
function PlayerDataService.trySpend(player: Player, amount: number): boolean
	local data = dataByPlayer[player]
	if not data or amount < 0 or data.Money < amount then
		return false
	end
	data.Money -= amount
	data.MoneyValue.Value = data.Money
	return true
end

function PlayerDataService.getSeedCount(player: Player, seedId: string): number
	local data = dataByPlayer[player]
	return if data then data.Inventory.Seeds[seedId] or 0 else 0
end

function PlayerDataService.addSeed(player: Player, seedId: string, amount: number?)
	local data = dataByPlayer[player]
	if not data or not SeedConfig.get(seedId) then
		return
	end
	addToBag(data.Inventory.Seeds, seedId, amount or 1)
	pushInventory(player)
end

-- Quita una semilla del inventario. Devuelve false si no tenía ninguna.
function PlayerDataService.tryRemoveSeed(player: Player, seedId: string): boolean
	local data = dataByPlayer[player]
	if not data or (data.Inventory.Seeds[seedId] or 0) <= 0 then
		return false
	end
	addToBag(data.Inventory.Seeds, seedId, -1)
	pushInventory(player)
	return true
end

function PlayerDataService.addFruit(player: Player, seedId: string, amount: number?)
	local data = dataByPlayer[player]
	if not data or not SeedConfig.get(seedId) then
		return
	end
	addToBag(data.Inventory.Fruits, seedId, amount or 1)
	pushInventory(player)
end

-- Vacía todos los frutos del jugador y devuelve la tabla seedId -> cantidad.
function PlayerDataService.takeAllFruits(player: Player): { [string]: number }
	local data = dataByPlayer[player]
	if not data then
		return {}
	end
	local fruits = data.Inventory.Fruits
	data.Inventory.Fruits = {}
	pushInventory(player)
	return fruits
end

function PlayerDataService.getInventory(player: Player): Inventory?
	local data = dataByPlayer[player]
	return if data then copyInventory(data.Inventory) else nil
end

-- Envía un aviso que el cliente muestra en pantalla.
function PlayerDataService.notify(player: Player, message: string, color: Color3?)
	notifyRemote:FireClient(player, message, color)
end

function PlayerDataService.init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	-- El cliente puede pedir su inventario al arrancar (por si se perdió el primer envío).
	Remotes.func("GetInventory").OnServerInvoke = function(player: Player)
		return PlayerDataService.getInventory(player)
	end
end

return PlayerDataService
