--!strict
-- Buying machines, machine levels, global upgrades, plot expansions and selling artifacts.

local Shared = script.Parent.Parent.Parent
local Machines = require(Shared.Config.Machines)
local Upgrades = require(Shared.Config.Upgrades)
local Rarities = require(Shared.Config.Rarities)
local Profile = require(Shared.Logic.Profile)
local Logic = script.Parent.Parent
local Items = require(Logic.Items)
local MachineStats = require(Logic.MachineStats)
local State = require(Logic.State)
local Inventory = require(Logic.Inventory)

type ProfileData = any

local Shop = {}

function Shop.buyMachine(profile: ProfileData, machineId: string, now: number): (boolean, any)
	local machine = Machines.get(machineId)
	if not machine then
		return false, "InvalidMachine"
	end
	if profile.machines[machineId] then
		return false, "AlreadyOwned"
	end
	if profile.rebirths < machine.rebirthRequired then
		return false, "NeedsRebirth"
	end
	if not Inventory.spend(profile, machine.cost) then
		return false, "NotEnoughEnergy"
	end
	profile.machines[machineId] = Profile.newMachineState(machineId, now)
	return true, { machineId = machineId, cost = machine.cost }
end

function Shop.upgradeMachine(profile: ProfileData, machineId: string): (boolean, any)
	local state = profile.machines[machineId]
	if not Machines.get(machineId) then
		return false, "InvalidMachine"
	end
	if not state then
		return false, "NotOwned"
	end
	local cost = MachineStats.upgradeCost(machineId, state.level)
	if not cost then
		return false, "MaxLevel"
	end
	if not Inventory.spend(profile, cost) then
		return false, "NotEnoughEnergy"
	end
	state.level += 1
	profile.stats.upgradesBought += 1
	return true, { machineId = machineId, level = state.level, cost = cost }
end

function Shop.buyUpgrade(profile: ProfileData, upgradeId: string): (boolean, any)
	if not Upgrades.get(upgradeId) then
		return false, "InvalidUpgrade"
	end
	local cost = State.upgradeCost(profile, upgradeId)
	if not cost then
		return false, "MaxLevel"
	end
	if not Inventory.spend(profile, cost) then
		return false, "NotEnoughEnergy"
	end
	profile.upgrades[upgradeId] = (profile.upgrades[upgradeId] or 0) + 1
	profile.stats.upgradesBought += 1
	return true, { upgradeId = upgradeId, level = profile.upgrades[upgradeId], cost = cost }
end

function Shop.buyExpansion(profile: ProfileData): (boolean, any)
	local cost = State.expansionCost(profile)
	if not cost then
		return false, "MaxLevel"
	end
	if not Inventory.spend(profile, cost) then
		return false, "NotEnoughEnergy"
	end
	profile.expansion += 1
	return true, { level = profile.expansion, cost = cost }
end

function Shop.sell(profile: ProfileData, key: string, amount: number): (boolean, any)
	local item = Items.parse(key)
	if not item then
		return false, "InvalidItem"
	end
	if type(amount) ~= "number" or amount ~= math.floor(amount) or amount < 1 then
		return false, "InvalidAmount"
	end
	if not Inventory.remove(profile, key, amount) then
		return false, "NotInInventory"
	end
	local value = Items.sellValue(item) * amount
	Inventory.earn(profile, value)
	profile.stats.itemsSold += amount
	return true, { key = key, amount = amount, value = value }
end

-- Sells every plain (no mutation, 1 star) artifact of one rarity, keeping `keep` copies of each.
function Shop.sellRarity(profile: ProfileData, rarityId: string, keep: number): (boolean, any)
	if not Rarities.isValid(rarityId) then
		return false, "InvalidRarity"
	end
	keep = math.clamp(math.floor(keep), 0, 1000)
	local total, sold = 0, 0
	local inventory: { [string]: number } = table.clone(profile.inventory)
	for key, count in inventory do
		local item = Items.parse(key)
		if item and item.mut == "" and item.stars == 1 and Items.rarityOf(item) == rarityId and count > keep then
			local amount = count - keep
			Inventory.remove(profile, key, amount)
			total += Items.sellValue(item) * amount
			sold += amount
		end
	end
	if sold == 0 then
		return false, "NothingToSell"
	end
	Inventory.earn(profile, total)
	profile.stats.itemsSold += sold
	return true, { sold = sold, value = total }
end

function Shop.setAutoSell(profile: ProfileData, rarityId: string, enabled: boolean): (boolean, any)
	if profile.settings.autoSell[rarityId] == nil then
		return false, "InvalidRarity"
	end
	profile.settings.autoSell[rarityId] = enabled == true
	return true, { rarity = rarityId, enabled = enabled == true }
end

return Shop
