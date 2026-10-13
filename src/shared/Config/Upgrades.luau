--!strict
-- Global upgrades bought with Energy. They reset on rebirth.
-- Level 0 = not bought. Cost to buy level L + 1 = cost.base * cost.growth ^ L.
-- `effect` per level is additive (luck, storage) or multiplicative (speed, as 1 - amount).

export type Upgrade = {
	id: string,
	name: string,
	maxLevel: number,
	cost: { base: number, growth: number },
	perLevel: number,
	description: string,
}

local Upgrades = {}

local list: { Upgrade } = {
	{
		id = "luck",
		name = "Lucky Charms",
		maxLevel = 15,
		cost = { base = 600, growth = 1.85 },
		perLevel = 0.08,
		description = "+8% luck on every box per level.",
	},
	{
		id = "speed",
		name = "Quick Assembly",
		maxLevel = 15,
		cost = { base = 450, growth = 1.8 },
		perLevel = 0.06,
		description = "Fabricators and printers work 6% faster per level.",
	},
	{
		id = "storage",
		name = "Cargo Bay",
		maxLevel = 20,
		cost = { base = 250, growth = 1.6 },
		perLevel = 20,
		description = "+20 inventory slots per level.",
	},
}

local byId: { [string]: Upgrade } = {}
for _, upgrade in list do
	byId[upgrade.id] = upgrade
end

Upgrades.List = list
Upgrades.ById = byId

function Upgrades.get(id: string): Upgrade?
	return byId[id]
end

return Upgrades
