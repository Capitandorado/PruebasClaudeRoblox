-- Server side of the network contract (Shared/Net). Creates the remotes, validates and
-- rate-limits every request and isolates handler errors so a bad request can never break
-- the server or leak internal errors to the client.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local RateLimiter = require(Shared.Util.RateLimiter)

local NetService = {}

type Handler = (player: Player, ...any) -> (boolean, any)

local handlers: { [string]: Handler } = {}
local limiters: { [Player]: { [string]: RateLimiter.RateLimiter } } = {}
local remotes: { request: RemoteFunction, state: RemoteEvent, notify: RemoteEvent, effect: RemoteEvent } = nil :: any

NetService.Stats = { requests = 0, rejected = 0, rateLimited = 0, errors = 0 }

local function now(): number
	return os.clock()
end

local function allow(player: Player, action: string): boolean
	local playerLimiters = limiters[player]
	if not playerLimiters then
		playerLimiters = {}
		limiters[player] = playerLimiters
	end
	local t = now()
	local global = playerLimiters["*"]
	if not global then
		global = RateLimiter.new(Net.GlobalRate, Net.GlobalBurst, t)
		playerLimiters["*"] = global
	end
	local limiter = playerLimiters[action]
	if not limiter then
		local spec = Net.Actions[action]
		limiter = RateLimiter.new(spec.rate, spec.burst, t)
		playerLimiters[action] = limiter
	end
	return global:allow(t) and limiter:allow(t)
end

local function onInvoke(player: Player, actionName: any, ...: any)
	NetService.Stats.requests += 1
	local count = select("#", ...)
	local args = { ... }
	local valid, reason = Net.validate(actionName, args, count)
	if not valid then
		NetService.Stats.rejected += 1
		return { ok = false, err = reason }
	end
	if not allow(player, actionName) then
		NetService.Stats.rateLimited += 1
		return { ok = false, err = "RateLimited" }
	end
	local handler = handlers[actionName]
	if not handler then
		NetService.Stats.rejected += 1
		return { ok = false, err = "BadRequest" }
	end
	local success, ok, data = pcall(handler, player, table.unpack(args, 1, count))
	if not success then
		NetService.Stats.errors += 1
		warn(string.format("[Net] %s from %s failed: %s", actionName, player.Name, tostring(ok)))
		return { ok = false, err = "ServerError" }
	end
	if ok then
		return { ok = true, data = data }
	end
	return { ok = false, err = if type(data) == "string" then data else "ServerError" }
end

function NetService.init()
	local folder = Instance.new("Folder")
	folder.Name = Net.FolderName
	local request = Instance.new("RemoteFunction")
	request.Name = Net.RequestName
	request.Parent = folder
	local state = Instance.new("RemoteEvent")
	state.Name = Net.StateName
	state.Parent = folder
	local notify = Instance.new("RemoteEvent")
	notify.Name = Net.NotifyName
	notify.Parent = folder
	local effect = Instance.new("RemoteEvent")
	effect.Name = Net.EffectName
	effect.Parent = folder
	remotes = { request = request, state = state, notify = notify, effect = effect }
	request.OnServerInvoke = onInvoke
	folder.Parent = ReplicatedStorage
	Players.PlayerRemoving:Connect(function(player)
		limiters[player] = nil
	end)
end

function NetService.on(action: string, handler: Handler)
	assert(Net.Actions[action], "Unknown action " .. action)
	handlers[action] = handler
end

function NetService.state(player: Player, kind: string, payload: any)
	if player.Parent then
		remotes.state:FireClient(player, kind, payload)
	end
end

function NetService.notify(player: Player, kind: string, payload: any)
	if player.Parent then
		remotes.notify:FireClient(player, kind, payload)
	end
end

function NetService.notifyAll(kind: string, payload: any)
	remotes.notify:FireAllClients(kind, payload)
end

function NetService.effect(kind: string, payload: any)
	remotes.effect:FireAllClients(kind, payload)
end

return NetService
