--!strict
-- An item is one artifact variant: artifact id + mutation ("" for none) + stars (1..MaxStars).
-- Inventory and pedestals store items by their key "id|mutation|stars".

local Config = script.Parent.Parent.Config
local Artifacts = require(Config.Artifacts)
local Mutations = require(Config.Mutations)
local Economy = require(Config.Economy)

export type Item = {
	id: string,
	mut: string,
	stars: number,
}

local Items = {}

function Items.key(id: string, mut: string?, stars: number?): string
	return string.format("%s|%s|%d", id, mut or "", stars or 1)
end

function Items.keyOf(item: Item): string
	return Items.key(item.id, item.mut, item.stars)
end

-- Returns nil for anything that is not a well-formed key of a known artifact.
function Items.parse(key: any): Item?
	if type(key) ~= "string" or #key > 80 then
		return nil
	end
	local parts = string.split(key, "|")
	if #parts ~= 3 then
		return nil
	end
	local id, mut, starsText = parts[1], parts[2], parts[3]
	local stars = tonumber(starsText)
	if not Artifacts.isValid(id) or not Mutations.isValid(mut) then
		return nil
	end
	if stars == nil or stars ~= math.floor(stars) or stars < 1 or stars > Economy.MaxStars then
		return nil
	end
	-- Reject non-canonical spellings such as "01" so one item never has two keys.
	if tostring(stars) ~= starsText then
		return nil
	end
	return { id = id, mut = mut, stars = stars }
end

function Items.isValidKey(key: any): boolean
	return Items.parse(key) ~= nil
end

function Items.starMultiplier(stars: number): number
	return Economy.StarMultipliers[stars] or 1
end

function Items.mutationMultiplier(mut: string): number
	local mutation = Mutations.get(mut)
	return if mutation then mutation.mult else 1
end

-- Output multiplier of the item itself (stars x mutation), before plot-wide effects.
function Items.multiplier(item: Item): number
	return Items.starMultiplier(item.stars) * Items.mutationMultiplier(item.mut)
end

function Items.baseEps(item: Item): number
	local artifact = Artifacts.get(item.id)
	return if artifact then artifact.eps * Items.multiplier(item) else 0
end

function Items.sellValue(item: Item): number
	local artifact = Artifacts.get(item.id)
	if not artifact then
		return 0
	end
	return math.floor(artifact.value * Items.multiplier(item) * Economy.SellFactor)
end

function Items.rarityOf(item: Item): string
	local artifact = Artifacts.get(item.id)
	return if artifact then artifact.rarity else "Common"
end

function Items.displayName(item: Item): string
	local artifact = Artifacts.get(item.id)
	local name = if artifact then artifact.name else item.id
	if item.mut ~= "" then
		name = item.mut .. " " .. name
	end
	if item.stars > 1 then
		name ..= " " .. string.rep("★", item.stars - 1)
	end
	return name
end

return Items
