--!strict
-- Central artifact catalog. To add an artifact, append an entry here (and, optionally, a
-- new `shape` builder in Visuals/ArtifactModels). Nothing else needs to change: odds, the
-- collection, the shop UI and production all read from this table.
--
-- Fields
--   id          unique, stable key (saved in player data — never rename a shipped id)
--   name        display name
--   rarity      a Rarities id
--   weight      relative chance inside its rarity tier (odds are shown in-game)
--   eps         base Energy per second while placed on a pedestal
--   value       Energy received when sold
--   effects     list of special effects (see Logic/Effects for every type)
--   shape       procedural model builder key (Visuals/ArtifactModels)
--   primary / secondary   main colors used by the model
--   lore        short collection text
--   catalog     catalog/event this artifact belongs to ("core" for the base game)

export type Effect = {
	type: string,
	amount: number?,
	min: number?,
	max: number?,
	period: number?,
	duration: number?,
}

export type Artifact = {
	id: string,
	name: string,
	rarity: string,
	weight: number,
	eps: number,
	value: number,
	effects: { Effect },
	shape: string,
	primary: Color3,
	secondary: Color3,
	lore: string,
	catalog: string,
}

local Artifacts = {}

local list: { Artifact } = {
	{
		id = "scrap_cube",
		name = "Scrap Cube",
		rarity = "Common",
		weight = 65,
		eps = 1,
		value = 4,
		effects = {},
		shape = "ScrapCube",
		primary = Color3.fromRGB(140, 150, 165),
		secondary = Color3.fromRGB(90, 220, 255),
		lore = "Compressed debris that still hums with leftover charge.",
		catalog = "core",
	},
	{
		id = "glow_shard",
		name = "Glow Shard",
		rarity = "Common",
		weight = 35,
		eps = 2,
		value = 8,
		effects = {},
		shape = "Shard",
		primary = Color3.fromRGB(80, 230, 255),
		secondary = Color3.fromRGB(200, 250, 255),
		lore = "A splinter of crystallised light from the edge of the void.",
		catalog = "core",
	},
	{
		id = "ion_battery",
		name = "Ion Battery",
		rarity = "Uncommon",
		weight = 60,
		eps = 6,
		value = 25,
		effects = {},
		shape = "Battery",
		primary = Color3.fromRGB(60, 70, 90),
		secondary = Color3.fromRGB(110, 255, 140),
		lore = "Stores ions harvested from passing comets.",
		catalog = "core",
	},
	{
		id = "flux_coil",
		name = "Flux Coil",
		rarity = "Uncommon",
		weight = 40,
		eps = 4,
		value = 30,
		effects = { { type = "speed", amount = 0.08 } },
		shape = "Coil",
		primary = Color3.fromRGB(255, 140, 60),
		secondary = Color3.fromRGB(255, 230, 120),
		lore = "Oscillates so fast that nearby fabricators try to keep up.",
		catalog = "core",
	},
	{
		id = "reactor_core",
		name = "Reactor Core",
		rarity = "Rare",
		weight = 50,
		eps = 18,
		value = 120,
		effects = { { type = "global_mult", amount = 0.10 } },
		shape = "Reactor",
		primary = Color3.fromRGB(70, 80, 100),
		secondary = Color3.fromRGB(60, 255, 200),
		lore = "A miniature fusion heart. Every machine runs a little hotter around it.",
		catalog = "core",
	},
	{
		id = "prism_lens",
		name = "Prism Lens",
		rarity = "Rare",
		weight = 50,
		eps = 14,
		value = 140,
		effects = { { type = "luck", amount = 0.15 } },
		shape = "Prism",
		primary = Color3.fromRGB(150, 200, 255),
		secondary = Color3.fromRGB(255, 120, 230),
		lore = "Bends probability the same way it bends light.",
		catalog = "core",
	},
	{
		id = "echo_duplicator",
		name = "Echo Duplicator",
		rarity = "Epic",
		weight = 50,
		eps = 45,
		value = 600,
		effects = { { type = "duplicate", amount = 0.08 } },
		shape = "Duplicator",
		primary = Color3.fromRGB(40, 40, 60),
		secondary = Color3.fromRGB(200, 110, 255),
		lore = "Whatever goes in sometimes comes out twice. Nobody knows where the copy comes from.",
		catalog = "core",
	},
	{
		id = "gravity_well",
		name = "Gravity Well",
		rarity = "Epic",
		weight = 50,
		eps = 55,
		value = 550,
		effects = { { type = "adjacent_mult", amount = 0.35 } },
		shape = "GravityWell",
		primary = Color3.fromRGB(25, 20, 45),
		secondary = Color3.fromRGB(120, 140, 255),
		lore = "Pulls energy out of the artifacts next to it and gives it back amplified.",
		catalog = "core",
	},
	{
		id = "entropy_engine",
		name = "Entropy Engine",
		rarity = "Legendary",
		weight = 50,
		eps = 160,
		value = 3000,
		effects = { { type = "entropy", min = 0, max = 3.5 } },
		shape = "Entropy",
		primary = Color3.fromRGB(255, 80, 40),
		secondary = Color3.fromRGB(255, 220, 60),
		lore = "Its output is pure chaos: nothing at all one second, triple the next.",
		catalog = "core",
	},
	{
		id = "chrono_turbine",
		name = "Chrono Turbine",
		rarity = "Legendary",
		weight = 50,
		eps = 220,
		value = 3200,
		effects = { { type = "speed", amount = 0.30 } },
		shape = "Turbine",
		primary = Color3.fromRGB(230, 235, 245),
		secondary = Color3.fromRGB(80, 200, 255),
		lore = "Spins slightly ahead of time, dragging the fabricators along.",
		catalog = "core",
	},
	{
		id = "void_nucleus",
		name = "Void Nucleus",
		rarity = "Mythic",
		weight = 100,
		eps = 900,
		value = 18000,
		effects = { { type = "adjacent_mult", amount = 0.75 } },
		shape = "Nucleus",
		primary = Color3.fromRGB(10, 5, 20),
		secondary = Color3.fromRGB(190, 60, 255),
		lore = "A pocket of absolute nothing that makes everything around it more.",
		catalog = "core",
	},
	{
		id = "halo_reactor",
		name = "Halo Reactor",
		rarity = "Divine",
		weight = 100,
		eps = 3200,
		value = 70000,
		effects = { { type = "global_mult", amount = 0.30 }, { type = "luck", amount = 0.25 } },
		shape = "Halo",
		primary = Color3.fromRGB(255, 250, 230),
		secondary = Color3.fromRGB(255, 200, 70),
		lore = "Radiates a calm golden glow. Machines near it simply work better.",
		catalog = "core",
	},
	{
		id = "astral_compass",
		name = "Astral Compass",
		rarity = "Celestial",
		weight = 100,
		eps = 9000,
		value = 220000,
		effects = { { type = "luck", amount = 0.6 }, { type = "duplicate", amount = 0.06 } },
		shape = "Compass",
		primary = Color3.fromRGB(30, 60, 120),
		secondary = Color3.fromRGB(120, 255, 255),
		lore = "Always points toward the rarest thing in the room.",
		catalog = "core",
	},
	{
		id = "the_singularity",
		name = "The Singularity",
		rarity = "Void",
		weight = 100,
		eps = 30000,
		value = 800000,
		effects = { { type = "singularity", amount = 0.12 } },
		shape = "Singularity",
		primary = Color3.fromRGB(0, 0, 0),
		secondary = Color3.fromRGB(255, 120, 40),
		lore = "Absorbs the nature of every artifact around it and feeds it back to the factory.",
		catalog = "core",
	},
	{
		id = "the_anomaly",
		name = "The Anomaly",
		rarity = "Secret",
		weight = 100,
		eps = 90000,
		value = 3000000,
		effects = { { type = "surge", amount = 3, period = 300, duration = 30 } },
		shape = "Anomaly",
		primary = Color3.fromRGB(255, 255, 255),
		secondary = Color3.fromRGB(255, 30, 60),
		lore = "It should not exist. Every few minutes the whole factory forgets its own rules.",
		catalog = "core",
	},
}

local byId: { [string]: Artifact } = {}
local byRarity: { [string]: { Artifact } } = {}
for _, artifact in list do
	assert(byId[artifact.id] == nil, "Duplicate artifact id: " .. artifact.id)
	byId[artifact.id] = artifact
	local bucket = byRarity[artifact.rarity]
	if not bucket then
		bucket = {}
		byRarity[artifact.rarity] = bucket
	end
	table.insert(bucket, artifact)
end

Artifacts.List = list
Artifacts.ById = byId
Artifacts.ByRarity = byRarity

function Artifacts.get(id: string): Artifact?
	return byId[id]
end

function Artifacts.isValid(id: any): boolean
	return type(id) == "string" and byId[id] ~= nil
end

return Artifacts
