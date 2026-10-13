--!strict
-- Weighted random rolls for boxes. The same functions produce the odds shown to players,
-- so the displayed probabilities are exactly the ones the server uses.
--
-- 1. Each rarity tier gets weight = box.rarityWeights[tier] * luck ^ tier.luckExponent
--    (tiers with no artifacts in the catalog are skipped).
-- 2. Inside a tier, an artifact is chosen by its catalog `weight`.
-- 3. A mutation is rolled independently (rarest first, single uniform draw).
-- Artifacts from event catalogs only exist while their event is active (Logic/Events).

local Config = script.Parent.Parent.Config
local Artifacts = require(Config.Artifacts)
local Boxes = require(Config.Boxes)
local Economy = require(Config.Economy)
local Mutations = require(Config.Mutations)
local Rarities = require(Config.Rarities)
local Events = require(script.Parent.Events)

-- Anything with Random:NextNumber() (Roblox's Random, or a deterministic test RNG).
export type Rng = {
	NextNumber: (self: any, min: number?, max: number?) -> number,
}

export type RarityOdds = { rarity: string, chance: number }
export type ArtifactOdds = { id: string, rarity: string, chance: number }
export type MutationOdds = { id: string, chance: number }

local Roller = {}

local oddsCache: { [string]: { ArtifactOdds } } = {}
local cacheSize = 0

local function clampLuck(luck: number): number
	if luck ~= luck then
		return 1
	end
	return math.clamp(luck, 1, Economy.MaxLuck)
end

function Roller.clampLuck(luck: number): number
	return clampLuck(luck)
end

-- Artifacts of a tier that can currently drop (core + active event catalogs).
local function availableIn(rarityId: string): { Artifacts.Artifact }
	local result = {}
	local bucket: { Artifacts.Artifact } = Artifacts.ByRarity[rarityId] or {}
	for _, artifact in bucket do
		if Events.catalogActive(artifact.catalog) then
			table.insert(result, artifact)
		end
	end
	return result
end

function Roller.getRarityOdds(boxId: string, luck: number): { RarityOdds }
	local box = Boxes.get(boxId)
	if not box then
		return {}
	end
	luck = clampLuck(luck)
	local weights = {}
	local total = 0
	for _, rarity in Rarities.List do
		local base = box.rarityWeights[rarity.id] or 0
		local bucket = availableIn(rarity.id)
		if base > 0 and #bucket > 0 then
			local weight = base * luck ^ rarity.luckExponent
			table.insert(weights, { rarity = rarity.id, weight = weight })
			total += weight
		end
	end
	local odds = {}
	for _, entry in weights do
		table.insert(odds, { rarity = entry.rarity, chance = entry.weight / total })
	end
	return odds
end

function Roller.getArtifactOdds(boxId: string, luck: number): { ArtifactOdds }
	luck = clampLuck(luck)
	local cacheKey = string.format("%s:%.4f:%s", boxId, luck, Events.current.signature)
	local cached = oddsCache[cacheKey]
	if cached then
		return cached
	end
	local result = {}
	for _, rarityOdds in Roller.getRarityOdds(boxId, luck) do
		local bucket = availableIn(rarityOdds.rarity)
		local bucketWeight = 0
		for _, artifact in bucket do
			bucketWeight += artifact.weight
		end
		for _, artifact in bucket do
			table.insert(result, {
				id = artifact.id,
				rarity = artifact.rarity,
				chance = rarityOdds.chance * artifact.weight / bucketWeight,
			})
		end
	end
	if cacheSize > 256 then
		table.clear(oddsCache)
		cacheSize = 0
	end
	oddsCache[cacheKey] = result
	cacheSize += 1
	return result
end

function Roller.getMutationOdds(boxId: string): { MutationOdds }
	local box = Boxes.get(boxId)
	local mult = (if box then box.mutationMult else 1) * Events.current.mutationMult
	local odds = {}
	for _, mutation in Mutations.List do
		table.insert(odds, { id = mutation.id, chance = math.min(Mutations.MaxChance, mutation.chance * mult) })
	end
	return odds
end

function Roller.rollArtifact(boxId: string, luck: number, rng: Rng): string?
	local odds = Roller.getArtifactOdds(boxId, luck)
	if #odds == 0 then
		return nil
	end
	local roll = rng:NextNumber()
	local cumulative = 0
	for _, entry in odds do
		cumulative += entry.chance
		if roll < cumulative then
			return entry.id
		end
	end
	-- Floating point slack: fall back to the last entry.
	return odds[#odds].id
end

function Roller.rollMutation(boxId: string, rng: Rng): string
	local roll = rng:NextNumber()
	local cumulative = 0
	for _, entry in Roller.getMutationOdds(boxId) do
		cumulative += entry.chance
		if roll < cumulative then
			return entry.id
		end
	end
	return ""
end

-- "1 in N" helper for the odds panel.
function Roller.oneIn(chance: number): number
	if chance <= 0 then
		return math.huge
	end
	return 1 / chance
end

return Roller
