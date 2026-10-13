--!strict
-- Placing artifacts on pedestals and taking them back.

local Shared = script.Parent.Parent.Parent
local Plot = require(Shared.Config.Plot)
local Logic = script.Parent.Parent
local Items = require(Logic.Items)
local State = require(Logic.State)
local Inventory = require(Logic.Inventory)

type Profile = any

local Factory = {}

local function validSlot(profile: Profile, slot: any): boolean
	return type(slot) == "number" and slot == math.floor(slot) and Plot.isSlotUnlocked(slot, profile.expansion)
end

-- Places `key` on `slot`. If the slot is occupied, the two artifacts swap places.
function Factory.place(profile: Profile, slot: number, key: string): (boolean, any)
	if not validSlot(profile, slot) then
		return false, "InvalidSlot"
	end
	if not Items.isValidKey(key) then
		return false, "InvalidItem"
	end
	if Inventory.count(profile, key) < 1 then
		return false, "NotInInventory"
	end
	local slotKey = tostring(slot)
	local previous = profile.placed[slotKey]
	if previous == key then
		return false, "AlreadyPlaced"
	end
	Inventory.remove(profile, key, 1)
	if previous then
		Inventory.add(profile, previous, 1)
	end
	profile.placed[slotKey] = key
	profile.stats.artifactsPlaced += 1
	return true, { slot = slot, key = key, swapped = previous }
end

function Factory.remove(profile: Profile, slot: number): (boolean, any)
	if not validSlot(profile, slot) then
		return false, "InvalidSlot"
	end
	local slotKey = tostring(slot)
	local key = profile.placed[slotKey]
	if not key then
		return false, "EmptySlot"
	end
	if State.freeSpace(profile) < 1 then
		return false, "InventoryFull"
	end
	profile.placed[slotKey] = nil
	Inventory.add(profile, key, 1)
	return true, { slot = slot, key = key }
end

-- Fills every empty unlocked pedestal with the highest-output artifacts in the inventory.
function Factory.autoFill(profile: Profile): (boolean, any)
	local candidates = {}
	for key, count in profile.inventory do
		local item = Items.parse(key)
		if item then
			for _ = 1, count do
				table.insert(candidates, { key = key, eps = Items.baseEps(item) })
			end
		end
	end
	table.sort(candidates, function(a, b)
		if a.eps == b.eps then
			return a.key < b.key
		end
		return a.eps > b.eps
	end)
	local placedCount = 0
	local nextCandidate = 1
	for _, slot in Plot.unlockedSlots(profile.expansion) do
		if profile.placed[tostring(slot)] == nil then
			local candidate = candidates[nextCandidate]
			if not candidate then
				break
			end
			nextCandidate += 1
			Inventory.remove(profile, candidate.key, 1)
			profile.placed[tostring(slot)] = candidate.key
			placedCount += 1
		end
	end
	if placedCount == 0 then
		return false, if #candidates == 0 then "NothingToPlace" else "NoFreeSlot"
	end
	profile.stats.artifactsPlaced += placedCount
	return true, { placed = placedCount }
end

-- Moves every placed artifact back to the inventory (ignores storage limits on purpose:
-- the player already owns these items).
function Factory.clear(profile: Profile): (boolean, any)
	local count = 0
	for slotKey, key in profile.placed do
		Inventory.add(profile, key, 1)
		profile.placed[slotKey] = nil
		count += 1
	end
	if count == 0 then
		return false, "NothingPlaced"
	end
	return true, { removed = count }
end

return Factory
