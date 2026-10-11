--!strict
--[[
	Main (servidor)
	===============
	Punto de entrada del servidor. Inicializa los servicios en orden:

	1. Remotes           -> crea los RemoteEvents/RemoteFunctions.
	2. MapBuilder        -> genera cinta, parcelas, puesto de venta (si no existen).
	3. PlayerDataService -> dinero (leaderstats) e inventario.
	4. PlotService       -> parcelas, plantar, crecer y cosechar.
	5. ConveyorService   -> cinta de semillas y compras.
	6. SellService       -> venta de frutos.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local Services = script.Parent:WaitForChild("Services")
local MapBuilder = require(Services:WaitForChild("MapBuilder"))
local PlayerDataService = require(Services:WaitForChild("PlayerDataService"))
local PlotService = require(Services:WaitForChild("PlotService"))
local ConveyorService = require(Services:WaitForChild("ConveyorService"))
local SellService = require(Services:WaitForChild("SellService"))

Remotes.createAll()
MapBuilder.build()
PlayerDataService.init()
PlotService.init()
ConveyorService.init()
SellService.init()

print("[Cultivo] Servidor listo")
