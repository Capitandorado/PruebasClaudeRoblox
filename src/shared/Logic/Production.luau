--!strict
-- Computes a factory's output from its placed artifacts. Pure function: the server caches
-- the result and only recomputes when the plot, machines, upgrades or surge state change.
--
-- slot output = base eps (stars x mutation)
--             x (1 + adjacency bonus)          Amplifier neighbours, minus Corrupted drain
--             x (1 + global bonus)             Reactor + Singularity
--             x (1 + machine bonus)            Overclocker
--             x rebirth multiplier x (1 + perk bonus) x surge multiplier
-- Entropy artifacts are reported separately: their per-second factor is rolled at tick time.

local Shared = script.Parent.Parent
local Artifacts = require(Shared.Config.Artifacts)
local Economy = require(Shared.Config.Economy)
local Mutations = require(Shared.Config.Mutations)
local Plot = require(Shared.Config.Plot)
local Items = require(script.Parent.Items)
local Roller = require(script.Parent.Roller)

export type Context = {
	placed: { [number]: Items.Item },
	machineBonus: number?,
	rebirthMult: number?,
	perkBonus: number?,
	surgeMult: number?,
}

export type EntropySource = { slot: number, eps: number, min: number, max: number }

export type Result = {
	total: number,
	stable: number,
	entropy: { EntropySource },
	perSlot: { [number]: number },
	slotBonus: { [number]: number },
	globalBonus: number,
	multiplier: number,
	luckBonus: number,
	duplicateChance: number,
	speedBonus: number,
	effectTypes: { string },
	surge: { amount: number, period: number, duration: number }?,
}

local Production = {}

function Production.compute(context: Context): Result
	local placed = context.placed
	local slotBonus: { [number]: number } = {}
	local globalBonus = 0
	local luckBonus = 0
	local duplicateChance = 0
	local speedBonus = 0
	local typesPresent: { [string]: boolean } = {}
	local singularityAmount = 0
	local surge = nil

	-- Pass 1: gather effects.
	for slot, item in placed do
		local artifact = Artifacts.get(item.id)
		if not artifact then
			continue
		end
		for _, effect in artifact.effects do
			local amount = effect.amount or 0
			if effect.type ~= "singularity" then
				typesPresent[effect.type] = true
			end
			if effect.type == "global_mult" then
				globalBonus += amount
			elseif effect.type == "adjacent_mult" then
				for _, neighbour in Plot.neighbours(slot) do
					slotBonus[neighbour] = (slotBonus[neighbour] or 0) + amount
				end
			elseif effect.type == "luck" then
				luckBonus += amount
			elseif effect.type == "duplicate" then
				duplicateChance += amount
			elseif effect.type == "speed" then
				speedBonus += amount
			elseif effect.type == "singularity" then
				singularityAmount += amount
			elseif effect.type == "surge" then
				-- Several anomalies do not stack: the strongest one drives the surge.
				if not surge or amount > surge.amount then
					surge = {
						amount = amount,
						period = effect.period or 300,
						duration = effect.duration or 30,
					}
				end
			end
		end
		local mutation = Mutations.get(item.mut)
		if mutation and mutation.adjacentPenalty then
			for _, neighbour in Plot.neighbours(slot) do
				slotBonus[neighbour] = (slotBonus[neighbour] or 0) - mutation.adjacentPenalty
			end
		end
	end

	local effectTypes = {}
	for effectType in typesPresent do
		table.insert(effectTypes, effectType)
	end
	table.sort(effectTypes)
	globalBonus += singularityAmount * #effectTypes

	local multiplier = (1 + globalBonus)
		* (1 + (context.machineBonus or 0))
		* (context.rebirthMult or 1)
		* (1 + (context.perkBonus or 0))
		* (context.surgeMult or 1)

	-- Pass 2: per-slot output.
	local perSlot: { [number]: number } = {}
	local stable = 0
	local entropy: { EntropySource } = {}
	local total = 0
	for slot, item in placed do
		local artifact = Artifacts.get(item.id)
		if not artifact then
			continue
		end
		local bonus = math.max(-0.9, slotBonus[slot] or 0)
		local eps = Items.baseEps(item) * (1 + bonus) * multiplier
		local entropyEffect = nil
		for _, effect in artifact.effects do
			if effect.type == "entropy" then
				entropyEffect = effect
			end
		end
		if entropyEffect then
			local min, max = entropyEffect.min or 0, entropyEffect.max or 1
			table.insert(entropy, { slot = slot, eps = eps, min = min, max = max })
			eps *= (min + max) / 2
		else
			stable += eps
		end
		perSlot[slot] = eps
		total += eps
	end

	return {
		total = total,
		stable = stable,
		entropy = entropy,
		perSlot = perSlot,
		slotBonus = slotBonus,
		globalBonus = globalBonus,
		multiplier = multiplier,
		luckBonus = luckBonus,
		duplicateChance = math.min(Economy.MaxDuplicateChance, duplicateChance),
		speedBonus = math.min(Economy.MaxSpeedBonus, speedBonus),
		effectTypes = effectTypes,
		surge = surge,
	}
end

-- Energy produced over `dt` seconds, rolling entropy factors with `rng`.
function Production.sample(result: Result, dt: number, rng: Roller.Rng): number
	local amount = result.stable
	for _, source in result.entropy do
		amount += source.eps * (source.min + (source.max - source.min) * rng:NextNumber())
	end
	return amount * dt
end

return Production
