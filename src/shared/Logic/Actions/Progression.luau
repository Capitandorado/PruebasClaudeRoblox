--!strict
-- Rebirth, rebirth perks and quests.

local Shared = script.Parent.Parent.Parent
local Artifacts = require(Shared.Config.Artifacts)
local Mutations = require(Shared.Config.Mutations)
local Machines = require(Shared.Config.Machines)
local Rebirth = require(Shared.Config.Rebirth)
local Quests = require(Shared.Config.Quests)
local Economy = require(Shared.Config.Economy)
local Plot = require(Shared.Config.Plot)
local Profile = require(Shared.Logic.Profile)
local Logic = script.Parent.Parent
local State = require(Logic.State)
local Events = require(Logic.Events)
local Roller = require(Logic.Roller)
local Inventory = require(Logic.Inventory)

type ProfileData = any

local Progression = {}

function Progression.rebirthCost(profile: ProfileData): number
	return Rebirth.cost(profile.rebirths)
end

function Progression.rebirth(profile: ProfileData, now: number): (boolean, any)
	local cost = Progression.rebirthCost(profile)
	if profile.energy < cost then
		return false, "NotEnoughEnergy"
	end
	local shards = Rebirth.shardReward(profile.rebirths)
	profile.rebirths += 1
	profile.stats.rebirths += 1
	profile.shards += shards
	local headStartLevel = profile.perks.headstart or 0
	local headStart = Rebirth.PerksById.headstart
	profile.energy = if headStartLevel > 0 then headStart.perLevel * 4 ^ (headStartLevel - 1) else 0
	profile.runEnergy = 0
	profile.runBestEps = 0
	profile.upgrades = {}
	profile.expansion = 0
	profile.machines = { [Machines.StarterId] = Profile.newMachineState(Machines.StarterId, now) }
	-- Artifacts on pedestals that no longer exist go back to the inventory.
	local placed: { [string]: string } = table.clone(profile.placed)
	for slotKey, key in placed do
		local slot = tonumber(slotKey)
		if not slot or not Plot.isSlotUnlocked(slot, profile.expansion) then
			profile.placed[slotKey] = nil
			Inventory.add(profile, key, 1)
		end
	end
	-- Quest targets scale with rebirths: refresh the board.
	profile.quests.active = {}
	return true, { rebirths = profile.rebirths, shards = shards }
end

function Progression.buyPerk(profile: ProfileData, perkId: string): (boolean, any)
	if not Rebirth.PerksById[perkId] then
		return false, "InvalidPerk"
	end
	local cost = State.perkCost(profile, perkId)
	if not cost then
		return false, "MaxLevel"
	end
	if profile.shards < cost then
		return false, "NotEnoughShards"
	end
	profile.shards -= cost
	profile.perks[perkId] = (profile.perks[perkId] or 0) + 1
	return true, { perkId = perkId, level = profile.perks[perkId], cost = cost }
end

-- Quests ------------------------------------------------------------------------------

function Progression.questTarget(profile: ProfileData, questId: string): number
	local quest = Quests.ById[questId]
	if not quest then
		return 1
	end
	return quest.target + quest.targetPerRebirth * profile.rebirths
end

function Progression.questProgress(profile: ProfileData, questState: any): number
	local quest = Quests.ById[questState.id]
	if not quest then
		return 0
	end
	return math.max(0, (profile.stats[quest.stat] or 0) - questState.base)
end

function Progression.questReward(profile: ProfileData, questId: string, eps: number): number
	local quest = Quests.ById[questId]
	if not quest then
		return 0
	end
	local base = quest.rewardBase * (1 + profile.rebirths)
	return math.floor(math.max(base, eps * Economy.QuestRewardSeconds * quest.rewardScale))
end

-- Discovery quests disappear once every artifact and mutation variant has been found.
-- Undiscovered artifacts/variants that can currently drop (event catalogs only count while
-- their event runs, so the quest is never impossible).
function Progression.remainingDiscoveries(profile: ProfileData): number
	local remaining = 0
	for _, artifact in Artifacts.List do
		if not Events.catalogActive(artifact.catalog) then
			continue
		end
		local entry = profile.collection[artifact.id]
		if not entry then
			remaining += 1 + #Mutations.List
		else
			for _, mutation in Mutations.List do
				if not entry.muts[mutation.id] then
					remaining += 1
				end
			end
		end
	end
	return remaining
end

function Progression.questAvailable(profile: ProfileData, questId: string): boolean
	local quest = Quests.ById[questId]
	if not quest then
		return false
	end
	if quest.stat == "discoveries" then
		return Progression.remainingDiscoveries(profile) > 0
	end
	return true
end

-- Removes unknown quests and tops the board up to Quests.ActiveCount. Returns true if changed.
function Progression.ensureQuests(profile: ProfileData, rng: Roller.Rng): boolean
	local changed = false
	local active = {}
	local used = {}
	for _, questState in profile.quests.active do
		if Quests.ById[questState.id] and not used[questState.id] then
			table.insert(active, questState)
			used[questState.id] = true
		else
			changed = true
		end
	end
	while #active < Quests.ActiveCount do
		local pool = {}
		for _, quest in Quests.List do
			if not used[quest.id] and Progression.questAvailable(profile, quest.id) then
				table.insert(pool, quest)
			end
		end
		if #pool == 0 then
			break
		end
		local quest = pool[math.min(#pool, math.floor(rng:NextNumber() * #pool) + 1)]
		used[quest.id] = true
		table.insert(active, {
			id = quest.id,
			base = profile.stats[quest.stat] or 0,
			target = Progression.questTarget(profile, quest.id),
		})
		changed = true
	end
	profile.quests.active = active
	return changed
end

function Progression.claimQuest(profile: ProfileData, index: number, eps: number, rng: Roller.Rng): (boolean, any)
	local questState = profile.quests.active[index]
	if not questState then
		return false, "InvalidQuest"
	end
	if Progression.questProgress(profile, questState) < questState.target then
		return false, "QuestIncomplete"
	end
	local reward = Progression.questReward(profile, questState.id, eps)
	Inventory.earn(profile, reward)
	table.remove(profile.quests.active, index)
	profile.quests.completed += 1
	Progression.ensureQuests(profile, rng)
	return true, { questId = questState.id, reward = reward }
end

return Progression
