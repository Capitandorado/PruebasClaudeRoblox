--!strict
-- Opening boxes. The server is the only caller: it supplies the clock, the RNG and the
-- cached production result. The client only ever receives the outcome.

local Shared = script.Parent.Parent.Parent
local Machines = require(Shared.Config.Machines)
local Logic = script.Parent.Parent
local Items = require(Logic.Items)
local Roller = require(Logic.Roller)
local State = require(Logic.State)
local Inventory = require(Logic.Inventory)

type Profile = any

export type Context = {
	now: number,
	rng: Roller.Rng,
	production: any,
}

local Boxes = {}

local function rollItem(boxId: string, luck: number, rng: Roller.Rng): Items.Item?
	local artifactId = Roller.rollArtifact(boxId, luck, rng)
	if not artifactId then
		return nil
	end
	return { id = artifactId, mut = Roller.rollMutation(boxId, rng), stars = 1 }
end

-- Rolls one box (plus a possible duplicate) and grants the results.
local function openWith(profile: Profile, machineId: string, boxId: string, context: Context): any
	local luck = State.luck(profile, machineId, context.production)
	local item = rollItem(boxId, luck, context.rng)
	if not item then
		return nil
	end
	local grants = { Inventory.grantRolled(profile, item, context.now) }
	local duplicated = false
	if context.production.duplicateChance > 0 and context.rng:NextNumber() < context.production.duplicateChance then
		duplicated = true
		table.insert(grants, Inventory.grantRolled(profile, item, context.now))
	end
	profile.stats.boxesOpened += 1
	return {
		machineId = machineId,
		boxId = boxId,
		luck = luck,
		duplicated = duplicated,
		grants = grants,
	}
end

-- Player-initiated open at a fabricator: uses a free charge first, otherwise pays boxCost.
function Boxes.open(profile: Profile, machineId: string, context: Context): (boolean, any)
	local machine = Machines.get(machineId)
	if not machine or machine.kind ~= "fabricator" or not machine.box then
		return false, "InvalidMachine"
	end
	local state = profile.machines[machineId]
	if not state then
		return false, "NotOwned"
	end
	if State.freeSpace(profile) < 1 then
		return false, "InventoryFull"
	end
	State.updateCharges(profile, machineId, context.production, context.now)
	local paid = 0
	if state.charges >= 1 then
		-- updateCharges keeps chargeAt = now while full, so the next charge starts filling now.
		state.charges -= 1
	else
		local cost = State.boxCost(profile, machineId)
		if cost <= 0 then
			return false, "NoCharges"
		end
		if not Inventory.spend(profile, cost) then
			return false, "NotEnoughEnergy"
		end
		paid = cost
	end
	local result = openWith(profile, machineId, machine.box, context)
	if not result then
		return false, "InvalidMachine"
	end
	result.paid = paid
	return true, result
end

-- Box Printer: automatic open, called by the simulation tick.
function Boxes.printerOpen(profile: Profile, context: Context): (boolean, any)
	local machine = Machines.get("box_printer")
	if not machine or not machine.box or not State.owns(profile, "box_printer") then
		return false, "NotOwned"
	end
	if State.freeSpace(profile) < 1 then
		return false, "InventoryFull"
	end
	local result = openWith(profile, "box_printer", machine.box, context)
	if not result then
		return false, "InvalidMachine"
	end
	result.paid = 0
	return true, result
end

return Boxes
