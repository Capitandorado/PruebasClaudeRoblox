--!strict
-- Rebirth: reset Energy, machines, upgrades and plot expansions in exchange for
-- Void Shards and a permanent production multiplier. Artifacts and the collection are kept.

export type Perk = {
	id: string,
	name: string,
	maxLevel: number,
	-- shard cost to buy level L + 1 = costBase + costPerLevel * L
	costBase: number,
	costPerLevel: number,
	perLevel: number,
	description: string,
}

local Rebirth = {}

Rebirth.BaseCost = 1.5e7
Rebirth.CostGrowth = 10
Rebirth.ProductionPerRebirth = 0.5
Rebirth.BaseShards = 2
Rebirth.ShardsPerRebirth = 1

function Rebirth.cost(rebirths: number): number
	return Rebirth.BaseCost * Rebirth.CostGrowth ^ rebirths
end

function Rebirth.shardReward(rebirths: number): number
	return Rebirth.BaseShards + Rebirth.ShardsPerRebirth * rebirths
end

function Rebirth.productionMultiplier(rebirths: number): number
	return 1 + Rebirth.ProductionPerRebirth * rebirths
end

Rebirth.Perks = {
	{
		id = "efficiency",
		name = "Void Efficiency",
		maxLevel = 20,
		costBase = 1,
		costPerLevel = 1,
		perLevel = 0.15,
		description = "+15% production per level.",
	},
	{
		id = "fortune",
		name = "Fortune",
		maxLevel = 10,
		costBase = 2,
		costPerLevel = 1,
		perLevel = 0.1,
		description = "+10% luck per level.",
	},
	{
		id = "overflow",
		name = "Overflow",
		maxLevel = 5,
		costBase = 2,
		costPerLevel = 2,
		perLevel = 1,
		description = "+1 Starter Fabricator box capacity per level.",
	},
	{
		id = "headstart",
		name = "Head Start",
		maxLevel = 5,
		costBase = 1,
		costPerLevel = 1,
		perLevel = 2500,
		description = "Start every rebirth with Energy (x4 per level).",
	},
	{
		id = "deepstorage",
		name = "Deep Storage",
		maxLevel = 10,
		costBase = 1,
		costPerLevel = 1,
		perLevel = 25,
		description = "+25 inventory slots per level (permanent).",
	},
} :: { Perk }

local byId: { [string]: Perk } = {}
for _, perk in Rebirth.Perks do
	byId[perk.id] = perk
end
Rebirth.PerksById = byId

return Rebirth
