--!strict
-- Fusion Chamber: three identical artifacts (same id, mutation and stars) become one with +1 star.

local Shared = script.Parent.Parent.Parent
local Economy = require(Shared.Config.Economy)
local Logic = script.Parent.Parent
local Items = require(Logic.Items)
local State = require(Logic.State)
local Inventory = require(Logic.Inventory)

type Profile = any

local Fusion = {}

function Fusion.canFuse(profile: Profile, key: string): (boolean, string?)
	if not State.owns(profile, "fusion_chamber") then
		return false, "NeedsFusionChamber"
	end
	local item = Items.parse(key)
	if not item then
		return false, "InvalidItem"
	end
	if item.stars >= Economy.MaxStars then
		return false, "MaxStars"
	end
	if Inventory.count(profile, key) < Economy.FusionCopies then
		return false, "NeedThreeCopies"
	end
	if profile.energy < State.fusionCost(profile, item) then
		return false, "NotEnoughEnergy"
	end
	return true, nil
end

function Fusion.fuse(profile: Profile, key: string, now: number): (boolean, any)
	local ok, reason = Fusion.canFuse(profile, key)
	if not ok then
		return false, reason
	end
	local item = Items.parse(key) :: Items.Item
	local cost = State.fusionCost(profile, item)
	Inventory.spend(profile, cost)
	Inventory.remove(profile, key, Economy.FusionCopies)
	local fused = { id = item.id, mut = item.mut, stars = item.stars + 1 }
	local fusedKey = Items.keyOf(fused)
	Inventory.add(profile, fusedKey, 1)
	local entry = profile.collection[item.id]
	if entry and fused.stars > entry.stars then
		entry.stars = fused.stars
	end
	profile.stats.fusions += 1
	return true, { from = key, key = fusedKey, cost = cost, stars = fused.stars, at = now }
end

return Fusion
