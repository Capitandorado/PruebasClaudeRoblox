--!strict
-- Machine catalog. Every machine sits on a fixed pad of the player's plot (`pad`).
-- Stats scale with the machine level through Logic/Machines.getStat:
--   mode "add": base + perLevel * (level - 1)
--   mode "mul": base * perLevel ^ (level - 1)
-- Upgrading from level L to L + 1 costs upgradeCost.base * upgradeCost.growth ^ (L - 1).
--
-- Kinds
--   fabricator  opens boxes: free `chargeInterval`/`chargeCap` charges, or `boxCost` Energy per box
--   printer     opens a box automatically every `autoInterval` seconds
--   booster     adds `productionBonus` to every artifact's output
--   fusion      fuses three identical artifacts into a higher star level (`fusionDiscount`)

export type Stat = {
	base: number,
	perLevel: number,
	mode: string,
	min: number?,
	max: number?,
	floor: boolean?,
}

export type Machine = {
	id: string,
	name: string,
	kind: string,
	order: number,
	pad: number,
	cost: number,
	rebirthRequired: number,
	maxLevel: number,
	upgradeCost: { base: number, growth: number },
	box: string?,
	stats: { [string]: Stat },
	color: Color3,
	description: string,
}

local Machines = {}

local list: { Machine } = {
	{
		id = "starter_fabricator",
		name = "Starter Fabricator",
		kind = "fabricator",
		order = 1,
		pad = 1,
		cost = 0,
		rebirthRequired = 0,
		maxLevel = 10,
		upgradeCost = { base = 150, growth = 1.8 },
		box = "basic",
		stats = {
			chargeInterval = { base = 8, perLevel = 0.92, mode = "mul", min = 2 },
			chargeCap = { base = 4, perLevel = 0.5, mode = "add", floor = true },
			boxCost = { base = 0, perLevel = 0, mode = "add" },
			luck = { base = 1, perLevel = 0.03, mode = "add" },
		},
		color = Color3.fromRGB(90, 200, 255),
		description = "Fabricates a free Basic Box every few seconds. Upgrades charge faster and store more boxes.",
	},
	{
		id = "box_printer",
		name = "Box Printer",
		kind = "printer",
		order = 2,
		pad = 2,
		cost = 350,
		rebirthRequired = 0,
		maxLevel = 10,
		upgradeCost = { base = 400, growth = 1.75 },
		box = "basic",
		stats = {
			autoInterval = { base = 20, perLevel = 0.88, mode = "mul", min = 4 },
			luck = { base = 1, perLevel = 0, mode = "add" },
		},
		color = Color3.fromRGB(255, 170, 60),
		description = "Opens a Basic Box for you automatically, even while you are busy.",
	},
	{
		id = "overclocker",
		name = "Overclocker",
		kind = "booster",
		order = 3,
		pad = 3,
		cost = 1200,
		rebirthRequired = 0,
		maxLevel = 15,
		upgradeCost = { base = 1500, growth = 1.7 },
		stats = {
			productionBonus = { base = 0.2, perLevel = 0.15, mode = "add" },
		},
		color = Color3.fromRGB(255, 80, 120),
		description = "Pushes every artifact past its limits: more Energy from the whole factory.",
	},
	{
		id = "fusion_chamber",
		name = "Fusion Chamber",
		kind = "fusion",
		order = 4,
		pad = 4,
		cost = 2500,
		rebirthRequired = 0,
		maxLevel = 8,
		upgradeCost = { base = 3000, growth = 1.9 },
		stats = {
			fusionDiscount = { base = 0, perLevel = 0.07, mode = "add", max = 0.6 },
		},
		color = Color3.fromRGB(200, 110, 255),
		description = "Fuses three identical artifacts into one with an extra star (more output).",
	},
	{
		id = "lucky_fabricator",
		name = "Lucky Fabricator",
		kind = "fabricator",
		order = 5,
		pad = 5,
		cost = 4000,
		rebirthRequired = 0,
		maxLevel = 10,
		upgradeCost = { base = 2500, growth = 1.85 },
		box = "lucky",
		stats = {
			boxCost = { base = 150, perLevel = 1, mode = "mul" },
			luck = { base = 1, perLevel = 0.12, mode = "add" },
		},
		color = Color3.fromRGB(120, 255, 140),
		description = "Sells Lucky Boxes: they cost Energy but roll far better rarities.",
	},
	{
		id = "void_forge",
		name = "Void Forge",
		kind = "fabricator",
		order = 6,
		pad = 6,
		cost = 200000,
		rebirthRequired = 1,
		maxLevel = 10,
		upgradeCost = { base = 150000, growth = 1.9 },
		box = "void",
		stats = {
			boxCost = { base = 5000, perLevel = 1, mode = "mul" },
			luck = { base = 1, perLevel = 0.15, mode = "add" },
		},
		color = Color3.fromRGB(170, 80, 255),
		description = "Forges Void Boxes, the only source of Void and Secret artifacts. Requires 1 rebirth.",
	},
}

local byId: { [string]: Machine } = {}
for _, machine in list do
	assert(byId[machine.id] == nil, "Duplicate machine id: " .. machine.id)
	byId[machine.id] = machine
end

Machines.List = list
Machines.ById = byId
Machines.StarterId = "starter_fabricator"

function Machines.get(id: string): Machine?
	return byId[id]
end

return Machines
