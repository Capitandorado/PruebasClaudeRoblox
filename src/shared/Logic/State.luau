--!strict
-- Derived values computed from a profile (capacity, luck, intervals, charges...).
-- Used by the server for decisions and by the client for display, so both always agree.

local Shared = script.Parent.Parent
local Economy = require(Shared.Config.Economy)
local Machines = require(Shared.Config.Machines)
local Upgrades = require(Shared.Config.Upgrades)
local Rebirth = require(Shared.Config.Rebirth)
local Plot = require(Shared.Config.Plot)
local Items = require(script.Parent.Items)
local MachineStats = require(script.Parent.MachineStats)
local Production = require(script.Parent.Production)
local Roller = require(script.Parent.Roller)

type Profile = any

local State = {}

local function upgradeLevel(profile: Profile, id: string): number
	return profile.upgrades[id] or 0
end

local function perkLevel(profile: Profile, id: string): number
	return profile.perks[id] or 0
end

function State.upgradeBonus(profile: Profile, id: string): number
	local upgrade = Upgrades.get(id)
	return if upgrade then upgrade.perLevel * upgradeLevel(profile, id) else 0
end

function State.perkBonus(profile: Profile, id: string): number
	local perk = Rebirth.PerksById[id]
	return if perk then perk.perLevel * perkLevel(profile, id) else 0
end

function State.capacity(profile: Profile): number
	return Economy.BaseStorage + State.upgradeBonus(profile, "storage") + State.perkBonus(profile, "deepstorage")
end

function State.inventoryCount(profile: Profile): number
	local count = 0
	for _, amount in profile.inventory do
		count += amount
	end
	return count
end

function State.freeSpace(profile: Profile): number
	return math.max(0, State.capacity(profile) - State.inventoryCount(profile))
end

function State.placedItems(profile: Profile): { [number]: Items.Item }
	local result = {}
	for slotKey, key in profile.placed do
		local slot = tonumber(slotKey)
		local item = Items.parse(key)
		if slot and item and Plot.isSlotUnlocked(slot, profile.expansion) then
			result[slot] = item
		end
	end
	return result
end

function State.machineLevel(profile: Profile, machineId: string): number
	local state = profile.machines[machineId]
	return if state then state.level else 0
end

function State.owns(profile: Profile, machineId: string): boolean
	return profile.machines[machineId] ~= nil
end

function State.computeProduction(profile: Profile, surgeMult: number?): Production.Result
	local overclock = State.machineLevel(profile, "overclocker")
	return Production.compute({
		placed = State.placedItems(profile),
		machineBonus = if overclock > 0 then MachineStats.getStat("overclocker", "productionBonus", overclock) else 0,
		rebirthMult = Rebirth.productionMultiplier(profile.rebirths),
		perkBonus = State.perkBonus(profile, "efficiency"),
		surgeMult = surgeMult or 1,
	})
end

function State.luck(profile: Profile, machineId: string, production: Production.Result): number
	local level = math.max(1, State.machineLevel(profile, machineId))
	local machineLuck = MachineStats.getStat(machineId, "luck", level)
	if machineLuck <= 0 then
		machineLuck = 1
	end
	local bonus = State.upgradeBonus(profile, "luck") + State.perkBonus(profile, "fortune") + production.luckBonus
	return Roller.clampLuck(machineLuck * (1 + bonus))
end

-- Interval divisor from speed sources (Quick Assembly upgrade + Accelerator artifacts).
function State.speedFactor(profile: Profile, production: Production.Result): number
	local upgradeSpeed = State.upgradeBonus(profile, "speed")
	return 1 + math.min(Economy.MaxSpeedBonus, upgradeSpeed + production.speedBonus)
end

function State.chargeInterval(profile: Profile, machineId: string, production: Production.Result): number
	local level = math.max(1, State.machineLevel(profile, machineId))
	local interval = MachineStats.getStat(machineId, "chargeInterval", level)
	if interval <= 0 then
		return 0
	end
	return interval / State.speedFactor(profile, production)
end

function State.chargeCap(profile: Profile, machineId: string): number
	local level = math.max(1, State.machineLevel(profile, machineId))
	local cap = MachineStats.getStat(machineId, "chargeCap", level)
	if cap > 0 and machineId == Machines.StarterId then
		cap += State.perkBonus(profile, "overflow")
	end
	return cap
end

function State.boxCost(profile: Profile, machineId: string): number
	local level = math.max(1, State.machineLevel(profile, machineId))
	return math.floor(MachineStats.getStat(machineId, "boxCost", level))
end

function State.printerInterval(profile: Profile, production: Production.Result): number
	local level = State.machineLevel(profile, "box_printer")
	if level <= 0 then
		return 0
	end
	return MachineStats.getStat("box_printer", "autoInterval", level) / State.speedFactor(profile, production)
end

-- Brings a fabricator's free charges up to date. Mutates the machine state.
function State.updateCharges(profile: Profile, machineId: string, production: Production.Result, now: number)
	local state = profile.machines[machineId]
	if not state then
		return
	end
	local cap = State.chargeCap(profile, machineId)
	local interval = State.chargeInterval(profile, machineId, production)
	if cap <= 0 or interval <= 0 then
		state.charges = 0
		state.chargeAt = now
		return
	end
	if state.charges >= cap then
		state.charges = cap
		state.chargeAt = now
		return
	end
	local elapsed = now - state.chargeAt
	if elapsed < 0 then
		state.chargeAt = now
		return
	end
	local gained = math.floor(elapsed / interval)
	if gained > 0 then
		state.charges = math.min(cap, state.charges + gained)
		state.chargeAt = if state.charges >= cap then now else state.chargeAt + gained * interval
	end
end

function State.machineCost(machineId: string): number
	local machine = Machines.get(machineId)
	return if machine then machine.cost else math.huge
end

function State.upgradeCost(profile: Profile, upgradeId: string): number?
	local upgrade = Upgrades.get(upgradeId)
	if not upgrade then
		return nil
	end
	local level = upgradeLevel(profile, upgradeId)
	if level >= upgrade.maxLevel then
		return nil
	end
	return math.floor(upgrade.cost.base * upgrade.cost.growth ^ level)
end

function State.expansionCost(profile: Profile): number?
	if profile.expansion >= Plot.MaxExpansionLevel then
		return nil
	end
	return Plot.getExpansion(profile.expansion + 1).cost
end

function State.perkCost(profile: Profile, perkId: string): number?
	local perk = Rebirth.PerksById[perkId]
	if not perk then
		return nil
	end
	local level = perkLevel(profile, perkId)
	if level >= perk.maxLevel then
		return nil
	end
	return perk.costBase + perk.costPerLevel * level
end

function State.fusionCost(profile: Profile, item: Items.Item): number
	local level = State.machineLevel(profile, "fusion_chamber")
	local discount = if level > 0 then MachineStats.getStat("fusion_chamber", "fusionDiscount", level) else 0
	local artifactValue = Items.sellValue({ id = item.id, mut = item.mut, stars = 1 })
	return math.floor(artifactValue * Economy.FusionCostFactor * item.stars * (1 - discount))
end

return State
