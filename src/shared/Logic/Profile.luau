--!strict
-- Player save data schema: defaults, migration and sanitising.
-- `reconcile` accepts anything read from the DataStore and always returns a valid profile,
-- so corrupt or outdated fields can never crash the server or leak into the economy.
-- Unknown artifact keys are moved to `orphaned` instead of being deleted.

local Shared = script.Parent.Parent
local Machines = require(Shared.Config.Machines)
local Upgrades = require(Shared.Config.Upgrades)
local Rebirth = require(Shared.Config.Rebirth)
local Plot = require(Shared.Config.Plot)
local Artifacts = require(Shared.Config.Artifacts)
local Mutations = require(Shared.Config.Mutations)
local Economy = require(Shared.Config.Economy)
local Rarities = require(Shared.Config.Rarities)
local DailyConfig = require(Shared.Config.Daily)
local Items = require(script.Parent.Items)
local MachineStats = require(script.Parent.MachineStats)

export type MachineState = { level: number, charges: number, chargeAt: number }
export type CollectionEntry = { count: number, muts: { [string]: boolean }, stars: number, first: number }
export type QuestState = { id: string, base: number, target: number }
export type DailyState = { day: number, streak: number, claims: number }

export type Profile = {
	version: number,
	energy: number,
	lifetimeEnergy: number,
	runEnergy: number,
	rebirths: number,
	shards: number,
	inventory: { [string]: number },
	placed: { [string]: string },
	machines: { [string]: MachineState },
	upgrades: { [string]: number },
	perks: { [string]: number },
	expansion: number,
	collection: { [string]: CollectionEntry },
	stats: { [string]: number },
	quests: { active: { QuestState }, completed: number },
	settings: { sfx: boolean, reducedEffects: boolean, autoSell: { [string]: boolean } },
	bestRarity: number,
	bestEps: number,
	runBestEps: number,
	created: number,
	playTime: number,
	lastOnline: number,
	daily: DailyState,
	orphaned: { [string]: number },
}

local Profile = {}

Profile.Version = 1

Profile.StatNames = {
	"boxesOpened",
	"energyEarned",
	"artifactsPlaced",
	"foundRare",
	"foundEpic",
	"itemsSold",
	"fusions",
	"upgradesBought",
	"rebirths",
	"discoveries",
}

Profile.AutoSellRarities = { "Common", "Uncommon", "Rare" }

local function newMachineState(machineId: string, now: number): MachineState
	local cap = MachineStats.getStat(machineId, "chargeCap", 1)
	return { level = 1, charges = cap, chargeAt = now }
end
Profile.newMachineState = newMachineState

function Profile.new(now: number): Profile
	local stats = {}
	for _, name in Profile.StatNames do
		stats[name] = 0
	end
	local autoSell = {}
	for _, rarity in Profile.AutoSellRarities do
		autoSell[rarity] = false
	end
	return {
		version = Profile.Version,
		energy = Economy.StartingEnergy,
		lifetimeEnergy = 0,
		runEnergy = 0,
		rebirths = 0,
		shards = 0,
		inventory = {},
		placed = {},
		machines = { [Machines.StarterId] = newMachineState(Machines.StarterId, now) },
		upgrades = {},
		perks = {},
		expansion = 0,
		collection = {},
		stats = stats,
		quests = { active = {}, completed = 0 },
		settings = { sfx = true, reducedEffects = false, autoSell = autoSell },
		bestRarity = 0,
		bestEps = 0,
		runBestEps = 0,
		created = now,
		playTime = 0,
		lastOnline = 0,
		daily = { day = 0, streak = 0, claims = 0 },
		orphaned = {},
	}
end

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end
Profile.isFiniteNumber = isFiniteNumber

local function number(value: any, default: number, min: number?, max: number?): number
	if not isFiniteNumber(value) then
		return default
	end
	local result = value :: number
	if min then
		result = math.max(min, result)
	end
	if max then
		result = math.min(max, result)
	end
	return result
end

local function integer(value: any, default: number, min: number?, max: number?): number
	return math.floor(number(value, default, min, max))
end

local function bool(value: any, default: boolean): boolean
	if type(value) == "boolean" then
		return value
	end
	return default
end

-- Upgrades data from older schema versions. Add a branch per version bump.
local function migrate(data: { [string]: any }): { [string]: any }
	local version = if type(data.version) == "number" then data.version else 1
	-- Example for the future:
	-- if version < 2 then data.newField = data.oldField; version = 2 end
	data.version = version
	return data
end

function Profile.reconcile(raw: any, now: number): Profile
	local profile = Profile.new(now)
	if type(raw) ~= "table" then
		return profile
	end
	local data = migrate(raw)

	profile.energy = number(data.energy, Economy.StartingEnergy, 0)
	profile.lifetimeEnergy = number(data.lifetimeEnergy, 0, 0)
	profile.runEnergy = number(data.runEnergy, 0, 0)
	profile.rebirths = integer(data.rebirths, 0, 0, 1000)
	profile.shards = integer(data.shards, 0, 0)
	profile.expansion = integer(data.expansion, 0, 0, Plot.MaxExpansionLevel)
	profile.bestRarity = integer(data.bestRarity, 0, 0, #Rarities.List)
	profile.bestEps = number(data.bestEps, 0, 0)
	profile.runBestEps = number(data.runBestEps, 0, 0)
	profile.created = number(data.created, now)
	profile.playTime = number(data.playTime, 0, 0)
	-- A future timestamp (clock skew between servers) counts as "just now".
	profile.lastOnline = number(data.lastOnline, 0, 0, now)
	if type(data.daily) == "table" then
		profile.daily.day = integer(data.daily.day, 0, 0, math.floor(now / DailyConfig.DaySeconds))
		profile.daily.streak = integer(data.daily.streak, 0, 0)
		profile.daily.claims = integer(data.daily.claims, 0, 0)
	end

	if type(data.orphaned) == "table" then
		for key, count in data.orphaned do
			if type(key) == "string" and isFiniteNumber(count) and count > 0 then
				profile.orphaned[key] = math.floor(count)
			end
		end
	end

	if type(data.inventory) == "table" then
		for key, count in data.inventory do
			if type(key) ~= "string" or not isFiniteNumber(count) or count < 1 then
				continue
			end
			if Items.isValidKey(key) then
				profile.inventory[key] = (profile.inventory[key] or 0) + math.floor(count)
			else
				profile.orphaned[key] = (profile.orphaned[key] or 0) + math.floor(count)
			end
		end
	end

	if type(data.placed) == "table" then
		for slotKey, key in data.placed do
			local slot = tonumber(slotKey)
			if type(key) ~= "string" then
				continue
			end
			if not Items.isValidKey(key) then
				profile.orphaned[key] = (profile.orphaned[key] or 0) + 1
			elseif slot and slot == math.floor(slot) and Plot.isSlotUnlocked(slot, profile.expansion) then
				profile.placed[tostring(slot)] = key
			else
				-- Slot no longer exists or is locked: give the artifact back.
				profile.inventory[key] = (profile.inventory[key] or 0) + 1
			end
		end
	end

	if type(data.machines) == "table" then
		for machineId, state in data.machines do
			local machine = Machines.get(machineId)
			if machine and type(state) == "table" then
				local cap = MachineStats.getStat(machineId, "chargeCap", 1)
				profile.machines[machineId] = {
					level = integer(state.level, 1, 1, machine.maxLevel),
					charges = number(state.charges, cap, 0, 100),
					chargeAt = number(state.chargeAt, now, 0, now + 60),
				}
			end
		end
	end
	if not profile.machines[Machines.StarterId] then
		profile.machines[Machines.StarterId] = newMachineState(Machines.StarterId, now)
	end

	if type(data.upgrades) == "table" then
		for _, upgrade in Upgrades.List do
			local level = integer(data.upgrades[upgrade.id], 0, 0, upgrade.maxLevel)
			if level > 0 then
				profile.upgrades[upgrade.id] = level
			end
		end
	end

	if type(data.perks) == "table" then
		for _, perk in Rebirth.Perks do
			local level = integer(data.perks[perk.id], 0, 0, perk.maxLevel)
			if level > 0 then
				profile.perks[perk.id] = level
			end
		end
	end

	if type(data.collection) == "table" then
		for artifactId, entry in data.collection do
			if Artifacts.isValid(artifactId) and type(entry) == "table" then
				local muts = {}
				if type(entry.muts) == "table" then
					for mutId, owned in entry.muts do
						if owned == true and Mutations.get(mutId) then
							muts[mutId] = true
						end
					end
				end
				profile.collection[artifactId] = {
					count = integer(entry.count, 1, 1),
					muts = muts,
					stars = integer(entry.stars, 1, 1, Economy.MaxStars),
					first = number(entry.first, now, 0),
				}
			end
		end
	end

	if type(data.stats) == "table" then
		for _, name in Profile.StatNames do
			profile.stats[name] = number(data.stats[name], 0, 0)
		end
	end

	if type(data.quests) == "table" then
		profile.quests.completed = integer(data.quests.completed, 0, 0)
		if type(data.quests.active) == "table" then
			for _, quest in data.quests.active do
				if
					type(quest) == "table"
					and type(quest.id) == "string"
					and isFiniteNumber(quest.base)
					and isFiniteNumber(quest.target)
					and #profile.quests.active < 3
				then
					table.insert(profile.quests.active, {
						id = quest.id,
						base = quest.base,
						target = math.max(1, quest.target),
					})
				end
			end
		end
	end

	if type(data.settings) == "table" then
		profile.settings.sfx = bool(data.settings.sfx, true)
		profile.settings.reducedEffects = bool(data.settings.reducedEffects, false)
		if type(data.settings.autoSell) == "table" then
			for _, rarity in Profile.AutoSellRarities do
				profile.settings.autoSell[rarity] = bool(data.settings.autoSell[rarity], false)
			end
		end
	end

	return profile
end

-- Last line of defence before writing to the DataStore.
function Profile.validate(profile: any): (boolean, string?)
	if type(profile) ~= "table" then
		return false, "profile is not a table"
	end
	if profile.version ~= Profile.Version then
		return false, "unexpected version"
	end
	for _, field in { "energy", "lifetimeEnergy", "runEnergy", "rebirths", "shards" } do
		if not isFiniteNumber(profile[field]) or profile[field] < 0 then
			return false, "invalid " .. field
		end
	end
	for _, field in { "inventory", "placed", "machines", "collection", "stats", "quests", "settings" } do
		if type(profile[field]) ~= "table" then
			return false, "missing " .. field
		end
	end
	if not profile.machines[Machines.StarterId] then
		return false, "missing starter machine"
	end
	return true, nil
end

return Profile
