--!strict
-- Mutations are rolled independently after the artifact itself (see Logic/Roller).
-- `chance` is the base probability per box; a box's `mutationMult` scales it.
-- Rarest mutations are checked first so they can never be shadowed by common ones.
-- `adjacentPenalty` (Corrupted) reduces the output of neighbouring pedestals.

export type Mutation = {
	id: string,
	name: string,
	chance: number,
	mult: number,
	adjacentPenalty: number?,
	color: Color3,
	description: string,
}

local Mutations = {}

local list: { Mutation } = {
	{
		id = "Corrupted",
		name = "Corrupted",
		chance = 0.002,
		mult = 5,
		adjacentPenalty = 0.15,
		color = Color3.fromRGB(200, 20, 50),
		description = "x5 output, but drains 15% from each adjacent artifact.",
	},
	{
		id = "Rainbow",
		name = "Rainbow",
		chance = 0.004,
		mult = 3,
		color = Color3.fromRGB(255, 120, 220),
		description = "x3 output. Shifts through every colour of the spectrum.",
	},
	{
		id = "Neon",
		name = "Neon",
		chance = 0.015,
		mult = 1.5,
		color = Color3.fromRGB(80, 255, 240),
		description = "x1.5 output. Glows brightly.",
	},
	{
		id = "Gold",
		name = "Gold",
		chance = 0.03,
		mult = 2,
		color = Color3.fromRGB(255, 205, 60),
		description = "x2 output. Plated in solid gold.",
	},
}

local byId: { [string]: Mutation } = {}
for _, mutation in list do
	byId[mutation.id] = mutation
end

Mutations.List = list
Mutations.ById = byId
-- Hard ceiling for mutation chances after multipliers, so no box can mutate everything.
Mutations.MaxChance = 0.25

function Mutations.get(id: string): Mutation?
	return byId[id]
end

-- "" means "no mutation".
function Mutations.isValid(id: any): boolean
	return id == "" or (type(id) == "string" and byId[id] ~= nil)
end

return Mutations
