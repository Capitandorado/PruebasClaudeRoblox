-- Economy pacing simulator: a bot plays VOID FACTORY with the real game logic
-- (Shared/Logic) and reports when it reaches each milestone.
--
--   lune run tools/simulate.luau [minutes=150] [style=active|casual] [seeds=5]
--
-- "active" opens a box whenever one is ready (or affordable at a paid machine);
-- "casual" plays in short bursts (30 s every 3 min) and leaves the factory running.

local process = require("@lune/process")
local stdio = require("@lune/stdio")
local Fixture = require("../tests/lib/Fixture")

local minutes = tonumber(process.args[1]) or 150
local style = process.args[2] or "active"
local seeds = tonumber(process.args[3]) or 5

local rt = Fixture.modules()
local function req(path)
	return Fixture.require(rt, path)
end
local Machines = req("Config.Machines")
local Rarities = req("Config.Rarities")
local Upgrades = req("Config.Upgrades")
local Rebirth = req("Config.Rebirth")
local Items = req("Logic.Items")
local Profile = req("Logic.Profile")
local State = req("Logic.State")
local MachineStats = req("Logic.MachineStats")
local Simulation = req("Logic.Simulation")
local Boxes = req("Logic.Actions.Boxes")
local Factory = req("Logic.Actions.Factory")
local Shop = req("Logic.Actions.Shop")
local Fusion = req("Logic.Actions.Fusion")
local Progression = req("Logic.Actions.Progression")

local function fmt(seconds)
	if not seconds then
		return "   —   "
	end
	return string.format("%3dm%02ds", math.floor(seconds / 60), math.floor(seconds % 60))
end

-- Keeps the best artifacts on the pedestals (re-places everything when it helps).
local function rearrange(profile)
	local best = 0
	for _, count in profile.inventory do
		best += count
	end
	if best == 0 then
		return
	end
	Factory.clear(profile)
	Factory.autoFill(profile)
end

local function playOnce(seed)
	local rng = Fixture.rng(seed)
	local now = 0
	local profile = Profile.new(now)
	local runtime = Simulation.newRuntime()
	Progression.ensureQuests(profile, rng)
	local milestones = {}
	local function mark(name)
		if not milestones[name] then
			milestones[name] = now
		end
	end
	local epsAt = {}
	local boxes = 0

	local function production()
		return Simulation.getProduction(profile, runtime, now)
	end

	local function tryOpen(machineId)
		local ok, result = Boxes.open(profile, machineId, { now = now, rng = rng, production = production() })
		if ok then
			boxes += 1
			for _, grant in result.grants do
				local item = Items.parse(grant.key)
				local rarity = Rarities.get(Items.rarityOf(item))
				mark("first " .. rarity.id)
			end
			rearrange(profile)
			runtime.dirty = true
		end
		return ok, result
	end

	-- Cheapest useful purchase first (machines, levels, upgrades, expansion).
	local function shop()
		local options = {}
		for _, machine in Machines.List do
			local state = profile.machines[machine.id]
			if not state and profile.rebirths >= machine.rebirthRequired then
				table.insert(options, { cost = machine.cost, kind = "machine", id = machine.id })
			elseif state then
				local cost = MachineStats.upgradeCost(machine.id, state.level)
				if cost then
					table.insert(options, { cost = cost * 1.5, real = cost, kind = "level", id = machine.id })
				end
			end
		end
		for _, upgrade in Upgrades.List do
			local cost = State.upgradeCost(profile, upgrade.id)
			if cost and (upgrade.id ~= "storage" or State.freeSpace(profile) < 10) then
				table.insert(options, { cost = cost, kind = "upgrade", id = upgrade.id })
			end
		end
		local expansion = State.expansionCost(profile)
		if expansion then
			table.insert(options, { cost = expansion * 0.8, real = expansion, kind = "expansion" })
		end
		table.sort(options, function(a, b)
			return a.cost < b.cost
		end)
		local option = options[1]
		if option and profile.energy >= (option.real or option.cost) then
			local ok
			if option.kind == "machine" then
				ok = Shop.buyMachine(profile, option.id, now)
				if ok then
					mark("buy " .. option.id)
				end
			elseif option.kind == "level" then
				ok = Shop.upgradeMachine(profile, option.id)
			elseif option.kind == "upgrade" then
				ok = Shop.buyUpgrade(profile, option.id)
			else
				ok = Shop.buyExpansion(profile)
				if ok then
					mark("expansion " .. profile.expansion)
					rearrange(profile)
				end
			end
			runtime.dirty = true
			return ok
		end
		return false
	end

	local total = minutes * 60
	while now < total do
		now += 1
		local active = style == "active" or (now % 180) < 30
		local events = Simulation.tick(profile, runtime, 1, now, rng)
		if #events.printed > 0 then
			boxes += #events.printed
			rearrange(profile)
			runtime.dirty = true
		end
		if active then
			-- Free boxes first, then paid boxes while keeping a reserve for shopping.
			tryOpen(Machines.StarterId)
			for _, machineId in { "void_forge", "lucky_fabricator" } do
				if profile.machines[machineId] then
					local cost = State.boxCost(profile, machineId)
					if profile.energy > cost * 8 then
						tryOpen(machineId)
					end
				end
			end
			for _ = 1, 3 do
				if not shop() then
					break
				end
			end
			for key, count in table.clone(profile.inventory) do
				if count >= 3 and Fusion.canFuse(profile, key) then
					Fusion.fuse(profile, key, now)
					rearrange(profile)
					mark("first fusion")
				end
			end
			if State.freeSpace(profile) < 3 then
				Shop.sellRarity(profile, "Common", 0)
				Shop.sellRarity(profile, "Uncommon", 1)
			end
			for index = #profile.quests.active, 1, -1 do
				if Progression.claimQuest(profile, index, production().total, rng) then
					mark("first quest")
				end
			end
			if profile.energy >= Rebirth.cost(profile.rebirths) then
				Progression.rebirth(profile, now)
				Progression.ensureQuests(profile, rng)
				runtime = Simulation.newRuntime()
				mark("rebirth " .. profile.rebirths)
				-- Spend shards: efficiency first, then fortune.
				while Progression.buyPerk(profile, "efficiency") or Progression.buyPerk(profile, "fortune") do
				end
				rearrange(profile)
			end
		end
		if now % 600 == 0 then
			epsAt[now // 600] = production().total
		end
	end
	return { milestones = milestones, eps = epsAt, boxes = boxes, profile = profile }
end

local runs = {}
for seed = 1, seeds do
	table.insert(runs, playOnce(seed * 7919))
end

local function median(values)
	table.sort(values)
	if #values == 0 then
		return nil
	end
	return values[math.ceil(#values / 2)]
end

local names = {}
local seen = {}
for _, run in runs do
	for name in run.milestones do
		if not seen[name] then
			seen[name] = true
			table.insert(names, name)
		end
	end
end
table.sort(names, function(a, b)
	local ta, tb = {}, {}
	for _, run in runs do
		table.insert(ta, run.milestones[a] or math.huge)
		table.insert(tb, run.milestones[b] or math.huge)
	end
	return median(ta) < median(tb)
end)

print(string.format("VOID FACTORY pacing — %s player, %d min, %d seeds (median / reached)", style, minutes, seeds))
for _, name in names do
	local times = {}
	for _, run in runs do
		if run.milestones[name] then
			table.insert(times, run.milestones[name])
		end
	end
	print(string.format("  %-28s %s   %d/%d", name, fmt(median(times)), #times, seeds))
end
print("  production (median ⚡/s):")
for slot = 1, math.floor(minutes / 10) do
	local values = {}
	for _, run in runs do
		table.insert(values, run.eps[slot] or 0)
	end
	stdio.write(string.format("    %3dm %-10.0f", slot * 10, median(values)))
	if slot % 4 == 0 then
		print()
	end
end
print()
local boxes, rebirths = {}, {}
for _, run in runs do
	table.insert(boxes, run.boxes)
	table.insert(rebirths, run.profile.rebirths)
end
print(string.format("  boxes opened (median): %d   rebirths (median): %d", median(boxes), median(rebirths)))
