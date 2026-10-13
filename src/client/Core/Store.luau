-- Read-only mirror of the player's profile, kept in sync by the server ("Full"/"Patch").
-- Derived values use the same Shared/Logic code as the server, so the UI always shows
-- exactly what the server will compute.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Util.Signal)
local State = require(Shared.Logic.State)
local Simulation = require(Shared.Logic.Simulation)

local Remote = require(script.Parent.Remote)

local Store = {}

Store.Changed = Signal.new() -- (changedKeys: { [string]: boolean })
Store.Ready = Signal.new()

Store.profile = nil :: any
Store.runtime = { surgeEndsAt = 0, surgeNextAt = 0, printerAt = 0 }
Store.plot = 0
Store.ready = false
Store.energyStamp = 0

local productionCache = nil
local PRODUCTION_KEYS = {
	placed = true,
	machines = true,
	upgrades = true,
	perks = true,
	rebirths = true,
	expansion = true,
	runtime = true,
}

function Store.now(): number
	return workspace:GetServerTimeNow()
end

function Store.isSurging(): boolean
	return Store.runtime.surgeEndsAt > Store.now()
end

-- Production as the server computes it (entropy shown at its average).
function Store.production()
	if not Store.profile then
		return nil
	end
	if not productionCache then
		local base = State.computeProduction(Store.profile)
		if base.surge and Store.isSurging() then
			local runtime = Simulation.newRuntime()
			runtime.surgeEndsAt = Store.runtime.surgeEndsAt
			productionCache = Simulation.getProduction(Store.profile, runtime, Store.now())
		else
			productionCache = base
		end
	end
	return productionCache
end

local function apply(kind: string, payload: any)
	local changed: { [string]: boolean } = {}
	if kind == "Full" then
		Store.profile = payload.profile
		Store.runtime = payload.runtime or Store.runtime
		Store.plot = payload.plot
		changed.all = true
	elseif kind == "Patch" and Store.profile then
		for key, value in payload do
			if key == "runtime" then
				local old = Store.runtime
				if old.surgeEndsAt ~= value.surgeEndsAt or old.printerAt ~= value.printerAt then
					changed.runtime = true
				end
				Store.runtime = value
			else
				Store.profile[key] = value
				changed[key] = true
			end
		end
	else
		return
	end
	if changed.energy or changed.all then
		Store.energyStamp = os.clock()
	end
	for key in changed do
		if PRODUCTION_KEYS[key] or key == "all" then
			productionCache = nil
			break
		end
	end
	if not Store.ready and Store.profile then
		Store.ready = true
		Store.Changed:Fire(changed)
		Store.Ready:Fire()
		return
	end
	Store.Changed:Fire(changed)
end

function Store.start()
	Remote.StateReceived:Connect(apply)
end

-- Calls `callback(changedKeys)` whenever any of `keys` changes (or on a full sync).
function Store.watch(keys: { string }, callback: (changed: { [string]: boolean }) -> ())
	return Store.Changed:Connect(function(changed)
		if changed.all then
			callback(changed)
			return
		end
		for _, key in keys do
			if changed[key] then
				callback(changed)
				return
			end
		end
	end)
end

return Store
