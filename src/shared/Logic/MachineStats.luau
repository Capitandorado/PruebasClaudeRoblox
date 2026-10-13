--!strict
-- Level-dependent machine stats and costs (formulas documented in Config/Machines).

local Config = script.Parent.Parent.Config
local Machines = require(Config.Machines)

local MachineStats = {}

function MachineStats.getStat(machineId: string, statName: string, level: number): number
	local machine = Machines.get(machineId)
	if not machine then
		return 0
	end
	local stat = machine.stats[statName]
	if not stat then
		return 0
	end
	local steps = math.max(0, level - 1)
	local value
	if stat.mode == "mul" then
		value = stat.base * stat.perLevel ^ steps
	else
		value = stat.base + stat.perLevel * steps
	end
	if stat.floor then
		value = math.floor(value)
	end
	if stat.min then
		value = math.max(stat.min, value)
	end
	if stat.max then
		value = math.min(stat.max, value)
	end
	return value
end

-- Cost to go from `level` to `level + 1`, or nil when already at max level.
function MachineStats.upgradeCost(machineId: string, level: number): number?
	local machine = Machines.get(machineId)
	if not machine or level >= machine.maxLevel then
		return nil
	end
	return math.floor(machine.upgradeCost.base * machine.upgradeCost.growth ^ (level - 1))
end

return MachineStats
