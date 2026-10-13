--!strict
-- Inventory, wallet and collection mutations shared by every action.

local Shared = script.Parent.Parent
local Artifacts = require(Shared.Config.Artifacts)
local Rarities = require(Shared.Config.Rarities)
local Items = require(script.Parent.Items)
local State = require(script.Parent.State)

type Profile = any

export type Grant = {
	key: string,
	newArtifact: boolean,
	newVariant: boolean,
	newTier: boolean,
	sold: boolean,
	value: number,
}

local Inventory = {}

function Inventory.count(profile: Profile, key: string): number
	return profile.inventory[key] or 0
end

function Inventory.add(profile: Profile, key: string, amount: number)
	profile.inventory[key] = (profile.inventory[key] or 0) + amount
end

function Inventory.remove(profile: Profile, key: string, amount: number): boolean
	local current = profile.inventory[key] or 0
	if amount < 1 or current < amount then
		return false
	end
	local remaining = current - amount
	profile.inventory[key] = if remaining > 0 then remaining else nil
	return true
end

-- Adds Energy from any source. `fromProduction` also feeds the "produce X" quest stat.
function Inventory.earn(profile: Profile, amount: number, fromProduction: boolean?)
	if amount <= 0 or amount ~= amount then
		return
	end
	profile.energy += amount
	profile.lifetimeEnergy += amount
	profile.runEnergy += amount
	if fromProduction then
		profile.stats.energyEarned += amount
	end
end

function Inventory.spend(profile: Profile, amount: number): boolean
	if amount ~= amount or amount < 0 or profile.energy < amount then
		return false
	end
	profile.energy -= amount
	return true
end

-- Records an item in the collection. Returns (new artifact, new mutation variant).
function Inventory.discover(profile: Profile, item: Items.Item, now: number): (boolean, boolean)
	local entry = profile.collection[item.id]
	local newArtifact = entry == nil
	local newVariant = false
	if not entry then
		entry = { count = 0, muts = {}, stars = 1, first = now }
		profile.collection[item.id] = entry
	end
	entry.count += 1
	if item.mut ~= "" and not entry.muts[item.mut] then
		entry.muts[item.mut] = true
		newVariant = true
	end
	if item.stars > entry.stars then
		entry.stars = item.stars
	end
	if newArtifact or newVariant then
		profile.stats.discoveries += 1
	end
	local artifact = Artifacts.get(item.id)
	if artifact then
		local order = Rarities.order(artifact.rarity)
		if order > profile.bestRarity then
			profile.bestRarity = order
		end
	end
	return newArtifact, newVariant
end

-- Gives a freshly rolled item to the player: collection, stats, auto-sell and storage.
-- Items that would overflow storage are sold automatically so nothing is ever lost.
function Inventory.grantRolled(profile: Profile, item: Items.Item, now: number): Grant
	local key = Items.keyOf(item)
	local previousBest = profile.bestRarity
	local newArtifact, newVariant = Inventory.discover(profile, item, now)
	local rarity = Items.rarityOf(item)
	local order = Rarities.order(rarity)
	local newTier = order > previousBest
	if order >= Rarities.order("Rare") then
		profile.stats.foundRare += 1
	end
	if order >= Rarities.order("Epic") then
		profile.stats.foundEpic += 1
	end
	local value = Items.sellValue(item)
	local autoSell = profile.settings.autoSell[rarity] == true and item.mut == "" and not newArtifact
	if autoSell or State.freeSpace(profile) < 1 then
		Inventory.earn(profile, value)
		profile.stats.itemsSold += 1
		return {
			key = key,
			newArtifact = newArtifact,
			newVariant = newVariant,
			newTier = newTier,
			sold = true,
			value = value,
		}
	end
	Inventory.add(profile, key, 1)
	return {
		key = key,
		newArtifact = newArtifact,
		newVariant = newVariant,
		newTier = newTier,
		sold = false,
		value = value,
	}
end

return Inventory
