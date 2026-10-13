--!strict
-- Per-player simulation: production integration, the Box Printer and Void Surges.
-- The server owns one Runtime per player (not saved) and calls `tick` once per second.

local Logic = script.Parent
local State = require(Logic.State)
local Production = require(Logic.Production)
local Inventory = require(Logic.Inventory)
local Roller = require(Logic.Roller)
local Boxes = require(Logic.Actions.Boxes)

type Profile = any

export type Runtime = {
	production: Production.Result?,
	dirty: boolean,
	printerAt: number?,
	surgeNextAt: number?,
	surgeEndsAt: number,
}

export type TickEvents = {
	printed: { any },
	printerBlocked: boolean,
	surgeStarted: boolean,
	surgeEnded: boolean,
	energy: number,
}

local Simulation = {}

function Simulation.newRuntime(): Runtime
	return { production = nil, dirty = true, printerAt = nil, surgeNextAt = nil, surgeEndsAt = 0 }
end

function Simulation.isSurging(runtime: Runtime, now: number): boolean
	return runtime.surgeEndsAt > now
end

local function scaled(result: Production.Result, mult: number): Production.Result
	if mult == 1 then
		return result
	end
	local copy = table.clone(result)
	copy.total *= mult
	copy.stable *= mult
	copy.multiplier *= mult
	copy.perSlot = table.clone(result.perSlot)
	for slot, eps in copy.perSlot do
		copy.perSlot[slot] = eps * mult
	end
	copy.entropy = {}
	for _, source in result.entropy do
		table.insert(copy.entropy, { slot = source.slot, eps = source.eps * mult, min = source.min, max = source.max })
	end
	return copy
end

-- Returns the cached production, recomputing it if something changed.
function Simulation.getProduction(profile: Profile, runtime: Runtime, now: number): Production.Result
	if runtime.dirty or not runtime.production then
		local base = State.computeProduction(profile)
		local surgeMult = 1
		if base.surge and Simulation.isSurging(runtime, now) then
			surgeMult = base.surge.amount
		end
		runtime.production = scaled(base, surgeMult)
		runtime.dirty = false
	end
	return runtime.production :: Production.Result
end

local function refillCharges(profile: Profile, now: number)
	for machineId, state in profile.machines do
		local cap = State.chargeCap(profile, machineId)
		if cap > 0 then
			state.charges = cap
			state.chargeAt = now
		end
	end
end

function Simulation.tick(profile: Profile, runtime: Runtime, dt: number, now: number, rng: Roller.Rng): TickEvents
	local events: TickEvents = {
		printed = {},
		printerBlocked = false,
		surgeStarted = false,
		surgeEnded = false,
		energy = 0,
	}
	local production = Simulation.getProduction(profile, runtime, now)

	-- Void Surge scheduling (only while an artifact with a surge effect is placed).
	local surge = production.surge
	if surge then
		if runtime.surgeNextAt == nil then
			runtime.surgeNextAt = now + surge.period
		elseif now >= (runtime.surgeNextAt :: number) and not Simulation.isSurging(runtime, now) then
			runtime.surgeEndsAt = now + surge.duration
			runtime.surgeNextAt = now + surge.period
			refillCharges(profile, now)
			runtime.dirty = true
			events.surgeStarted = true
		end
	else
		runtime.surgeNextAt = nil
	end
	if runtime.surgeEndsAt > 0 and not Simulation.isSurging(runtime, now) then
		runtime.surgeEndsAt = 0
		runtime.dirty = true
		events.surgeEnded = true
	end
	if runtime.dirty then
		production = Simulation.getProduction(profile, runtime, now)
	end

	-- Energy.
	local amount = Production.sample(production, dt, rng)
	Inventory.earn(profile, amount, true)
	events.energy = amount
	if production.total > profile.bestEps then
		profile.bestEps = production.total
	end
	profile.playTime += dt

	-- Box Printer.
	local interval = State.printerInterval(profile, production)
	if interval > 0 then
		if runtime.printerAt == nil then
			runtime.printerAt = now + interval
		elseif now >= (runtime.printerAt :: number) then
			runtime.printerAt = now + interval
			local ok, result = Boxes.printerOpen(profile, { now = now, rng = rng, production = production })
			if ok then
				table.insert(events.printed, result)
			else
				events.printerBlocked = result == "InventoryFull"
			end
		end
	else
		runtime.printerAt = nil
	end

	return events
end

return Simulation
