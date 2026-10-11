--!strict
--[[
	Main (cliente)
	==============
	Conecta la interfaz (UI/HUD) con el servidor:
	- Muestra el dinero leyendo leaderstats (lo escribe sólo el servidor).
	- Recibe el inventario del servidor y lo pinta.
	- Envía al servidor la petición de plantar la semilla seleccionada.
	- Muestra los avisos que manda el servidor.

	El cliente nunca modifica dinero ni inventario: sólo pide cosas y el
	servidor decide si son válidas.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local HUD = require(script.Parent:WaitForChild("UI"):WaitForChild("HUD"))

local player = Players.LocalPlayer

HUD.init()

-- Dinero ------------------------------------------------------------------------
task.spawn(function()
	local leaderstats = player:WaitForChild("leaderstats")
	local money = leaderstats:WaitForChild(GameConfig.MoneyStatName) :: IntValue
	HUD.setMoney(money.Value)
	money.Changed:Connect(function(value)
		HUD.setMoney(value)
	end)
end)

-- Inventario --------------------------------------------------------------------
Remotes.event("InventoryUpdated").OnClientEvent:Connect(function(inventory)
	HUD.setInventory(inventory)
end)

task.spawn(function()
	local inventory = Remotes.func("GetInventory"):InvokeServer()
	if inventory then
		HUD.setInventory(inventory)
	end
end)

-- Avisos ------------------------------------------------------------------------
Remotes.event("Notify").OnClientEvent:Connect(function(message: string, color: Color3?)
	HUD.notify(message, color)
end)

-- Plantar -----------------------------------------------------------------------
HUD.onPlant(function(seedId: string)
	Remotes.event("PlantSeed"):FireServer(seedId)
end)
