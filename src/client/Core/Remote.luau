-- Client side of the network contract. All gameplay goes through `request`, which never
-- throws: it always returns { ok, err, data }.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)

local Remote = {}

Remote.StateReceived = Signal.new()
Remote.NotifyReceived = Signal.new()
Remote.EffectReceived = Signal.new()

local folder = ReplicatedStorage:WaitForChild(Net.FolderName)
local requestRemote = folder:WaitForChild(Net.RequestName) :: RemoteFunction
local stateRemote = folder:WaitForChild(Net.StateName) :: RemoteEvent
local notifyRemote = folder:WaitForChild(Net.NotifyName) :: RemoteEvent
local effectRemote = folder:WaitForChild(Net.EffectName) :: RemoteEvent

export type Response = { ok: boolean, err: string?, data: any }

function Remote.request(action: string, ...: any): Response
	local args = table.pack(...)
	local success, response = pcall(function()
		return requestRemote:InvokeServer(action, table.unpack(args, 1, args.n))
	end)
	if not success or type(response) ~= "table" then
		return { ok = false, err = "ServerError" }
	end
	return response
end

function Remote.start()
	stateRemote.OnClientEvent:Connect(function(kind, payload)
		Remote.StateReceived:Fire(kind, payload)
	end)
	notifyRemote.OnClientEvent:Connect(function(kind, payload)
		Remote.NotifyReceived:Fire(kind, payload)
	end)
	effectRemote.OnClientEvent:Connect(function(kind, payload)
		Remote.EffectReceived:Fire(kind, payload)
	end)
end

return Remote
