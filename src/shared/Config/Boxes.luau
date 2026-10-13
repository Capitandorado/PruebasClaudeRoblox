--!strict
-- Loot tables. Each box defines relative weights per rarity tier; artifacts inside a tier
-- are then chosen by their own `weight` (Config/Artifacts). Weights do not need to sum to
-- anything: Logic/Roller normalises them and the in-game odds panel shows the real result.

export type Box = {
	id: string,
	name: string,
	rarityWeights: { [string]: number },
	mutationMult: number,
	color: Color3,
}

local Boxes = {}

local list: { Box } = {
	{
		id = "basic",
		name = "Basic Box",
		rarityWeights = {
			Common = 600,
			Uncommon = 270,
			Rare = 100,
			Epic = 24,
			Legendary = 5,
			Mythic = 0.9,
			Divine = 0.1,
		},
		mutationMult = 1,
		color = Color3.fromRGB(90, 200, 255),
	},
	{
		id = "lucky",
		name = "Lucky Box",
		rarityWeights = {
			Common = 380,
			Uncommon = 320,
			Rare = 190,
			Epic = 80,
			Legendary = 24,
			Mythic = 5,
			Divine = 0.9,
			Celestial = 0.1,
		},
		mutationMult = 1.5,
		color = Color3.fromRGB(120, 255, 140),
	},
	{
		id = "void",
		name = "Void Box",
		rarityWeights = {
			Uncommon = 300,
			Rare = 350,
			Epic = 210,
			Legendary = 100,
			Mythic = 30,
			Divine = 8,
			Celestial = 1.6,
			Void = 0.36,
			Secret = 0.04,
		},
		mutationMult = 2,
		color = Color3.fromRGB(170, 80, 255),
	},
}

local byId: { [string]: Box } = {}
for _, box in list do
	byId[box.id] = box
end

Boxes.List = list
Boxes.ById = byId

function Boxes.get(id: string): Box?
	return byId[id]
end

return Boxes
