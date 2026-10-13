--!strict
-- Rarity tiers, ordered from most common to rarest.
-- `luckExponent` controls how strongly luck boosts the tier: weight * luck ^ luckExponent.
-- `reveal` drives the client-side opening animation (duration, beams, shake, flash).
-- `announce` decides who hears about a drop: "none", "self" (local toast) or "server" (everyone).

export type Reveal = {
	duration: number,
	beams: number,
	shake: number,
	flash: boolean,
	sound: string,
}

export type Rarity = {
	id: string,
	order: number,
	color: Color3,
	accent: Color3,
	luckExponent: number,
	announce: string,
	reveal: Reveal,
}

local Rarities = {}

local list: { Rarity } = {
	{
		id = "Common",
		order = 1,
		color = Color3.fromRGB(176, 190, 204),
		accent = Color3.fromRGB(120, 134, 150),
		luckExponent = 0,
		announce = "none",
		reveal = { duration = 0.9, beams = 0, shake = 0, flash = false, sound = "RevealCommon" },
	},
	{
		id = "Uncommon",
		order = 2,
		color = Color3.fromRGB(96, 224, 128),
		accent = Color3.fromRGB(40, 150, 80),
		luckExponent = 0.25,
		announce = "none",
		reveal = { duration = 1.0, beams = 0, shake = 0, flash = false, sound = "RevealCommon" },
	},
	{
		id = "Rare",
		order = 3,
		color = Color3.fromRGB(64, 160, 255),
		accent = Color3.fromRGB(30, 90, 200),
		luckExponent = 0.5,
		announce = "none",
		reveal = { duration = 1.3, beams = 3, shake = 0, flash = false, sound = "RevealRare" },
	},
	{
		id = "Epic",
		order = 4,
		color = Color3.fromRGB(180, 96, 255),
		accent = Color3.fromRGB(110, 40, 200),
		luckExponent = 0.75,
		announce = "self",
		reveal = { duration = 1.6, beams = 5, shake = 0.15, flash = false, sound = "RevealRare" },
	},
	{
		id = "Legendary",
		order = 5,
		color = Color3.fromRGB(255, 186, 48),
		accent = Color3.fromRGB(220, 120, 20),
		luckExponent = 1,
		announce = "server",
		reveal = { duration = 2.1, beams = 7, shake = 0.3, flash = true, sound = "RevealLegendary" },
	},
	{
		id = "Mythic",
		order = 6,
		color = Color3.fromRGB(255, 70, 120),
		accent = Color3.fromRGB(190, 20, 70),
		luckExponent = 1,
		announce = "server",
		reveal = { duration = 2.5, beams = 9, shake = 0.4, flash = true, sound = "RevealLegendary" },
	},
	{
		id = "Divine",
		order = 7,
		color = Color3.fromRGB(255, 246, 180),
		accent = Color3.fromRGB(255, 210, 90),
		luckExponent = 1,
		announce = "server",
		reveal = { duration = 2.9, beams = 11, shake = 0.5, flash = true, sound = "RevealDivine" },
	},
	{
		id = "Celestial",
		order = 8,
		color = Color3.fromRGB(110, 240, 255),
		accent = Color3.fromRGB(40, 150, 255),
		luckExponent = 1,
		announce = "server",
		reveal = { duration = 3.2, beams = 13, shake = 0.6, flash = true, sound = "RevealDivine" },
	},
	{
		id = "Void",
		order = 9,
		color = Color3.fromRGB(150, 70, 255),
		accent = Color3.fromRGB(20, 0, 40),
		luckExponent = 1,
		announce = "server",
		reveal = { duration = 3.6, beams = 16, shake = 0.8, flash = true, sound = "RevealVoid" },
	},
	{
		id = "Secret",
		order = 10,
		color = Color3.fromRGB(255, 255, 255),
		accent = Color3.fromRGB(255, 40, 60),
		luckExponent = 1,
		announce = "server",
		reveal = { duration = 4.2, beams = 20, shake = 1, flash = true, sound = "RevealVoid" },
	},
}

local byId: { [string]: Rarity } = {}
for _, rarity in list do
	byId[rarity.id] = rarity
end

Rarities.List = list
Rarities.ById = byId

function Rarities.get(id: string): Rarity?
	return byId[id]
end

function Rarities.order(id: string): number
	local rarity = byId[id]
	return if rarity then rarity.order else 0
end

function Rarities.isValid(id: any): boolean
	return type(id) == "string" and byId[id] ~= nil
end

return Rarities
