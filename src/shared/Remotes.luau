--!strict
--[[
	Remotes
	=======
	Punto único para obtener los RemoteEvents / RemoteFunctions.
	- En el servidor los crea (si no existen) dentro de ReplicatedStorage.Remotes.
	- En el cliente espera a que existan.

	IMPORTANTE: nunca confíes en los datos que llegan del cliente. Cada handler
	del servidor debe validar tipos, existencia y permisos.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"

-- Nombre -> clase de cada remote.
local DEFINITIONS: { [string]: string } = {
	PlantSeed = "RemoteEvent", -- Cliente -> Servidor: (seedId) plantar en el hueco libre más cercano
	InventoryUpdated = "RemoteEvent", -- Servidor -> Cliente: (inventario) estado completo del inventario
	Notify = "RemoteEvent", -- Servidor -> Cliente: (mensaje, color?) aviso en pantalla
	GetInventory = "RemoteFunction", -- Cliente -> Servidor: devuelve el inventario actual
}

local Remotes = {}

local function getFolder(): Folder
	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = FOLDER_NAME
			folder.Parent = ReplicatedStorage
		end
		return folder :: Folder
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

local function get(name: string): Instance
	local className = DEFINITIONS[name]
	assert(className, "Remote desconocido: " .. name)

	local folder = getFolder()
	if RunService:IsServer() then
		local existing = folder:FindFirstChild(name)
		if existing then
			return existing
		end
		local remote: Instance = Instance.new(className :: any)
		remote.Name = name
		remote.Parent = folder
		return remote
	end
	return folder:WaitForChild(name)
end

function Remotes.event(name: string): RemoteEvent
	return get(name) :: RemoteEvent
end

function Remotes.func(name: string): RemoteFunction
	return get(name) :: RemoteFunction
end

-- Crea todos los remotes de golpe (lo llama el servidor al arrancar).
function Remotes.createAll()
	assert(RunService:IsServer(), "Remotes.createAll sólo puede llamarse en el servidor")
	for name in DEFINITIONS do
		get(name)
	end
end

return Remotes
