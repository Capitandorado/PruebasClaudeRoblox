--!strict
-- Shared reward format for codes and collection milestones:
--   seconds/min  Energy worth `seconds` of steady production (at least `min`)
--   crates       Daily Crates (Rare or better), need free storage
--   shards       Void Shards
--   boost/duration  a timed boost ("energy" or "luck") for `duration` seconds of play
-- Also the code-redeeming and milestone-claiming actions that use it.

local Shared = script.Parent.Parent.Parent
local Codes = require(Shared.Config.Codes)
local Milestones = require(Shared.Config.Milestones)
local Monetization = require(Shared.Config.Monetization)
local DailyConfig = require(Shared.Config.Daily)
local Format = require(Shared.Util.Format)
local Logic = script.Parent.Parent
local State = require(Logic.State)
local Inventory = require(Logic.Inventory)
local Boxes = require(script.Parent.Boxes)

type Profile = any
type Reward = { [string]: any }

local Rewards = {}

function Rewards.energyFor(profile: Profile, reward: Reward): number
	if not reward.seconds then
		return 0
	end
	local eps = State.computeProduction(profile, 1, 1, true).total
	return math.floor(math.max(reward.min or 0, eps * reward.seconds))
end

-- Short text such as "⚡12.5K + 1 Crate + 10m x2 Luck".
function Rewards.describe(profile: Profile, reward: Reward): string
	local parts = {}
	local energy = Rewards.energyFor(profile, reward)
	if energy > 0 then
		table.insert(parts, "⚡" .. Format.number(energy))
	end
	if reward.crates then
		table.insert(parts, reward.crates .. (if reward.crates == 1 then " Daily Crate" else " Daily Crates"))
	end
	if reward.shards then
		table.insert(parts, "💠" .. reward.shards .. (if reward.shards == 1 then " Shard" else " Shards"))
	end
	if reward.boost then
		local boost = Monetization.Boosts[reward.boost]
		table.insert(
			parts,
			Format.shortDuration(reward.duration or 0) .. " " .. (if boost then boost.name else reward.boost)
		)
	end
	return table.concat(parts, " + ")
end

function Rewards.canApply(profile: Profile, reward: Reward): (boolean, string?)
	if reward.crates and State.freeSpace(profile) < reward.crates then
		return false, "InventoryFull"
	end
	return true, nil
end

function Rewards.apply(profile: Profile, reward: Reward, context: Boxes.Context): any
	local summary: any = { energy = 0, results = {}, text = Rewards.describe(profile, reward) }
	local energy = Rewards.energyFor(profile, reward)
	if energy > 0 then
		Inventory.earn(profile, energy, false)
		summary.energy = energy
	end
	for _ = 1, reward.crates or 0 do
		local ok, result = Boxes.openCrate(profile, DailyConfig.CrateBox, context)
		if ok then
			table.insert(summary.results, result)
		end
	end
	if reward.shards then
		profile.shards += reward.shards
		summary.shards = reward.shards
	end
	if reward.boost and Monetization.Boosts[reward.boost] then
		local current = profile.boosts[reward.boost] or 0
		profile.boosts[reward.boost] = math.min(Monetization.MaxBoostSeconds, current + (reward.duration or 0))
		summary.boost = reward.boost
	end
	return summary
end

-- Codes ----------------------------------------------------------------------------------

function Rewards.redeemCode(profile: Profile, code: string, now: number, context: Boxes.Context): (boolean, any)
	local entry = Codes.get(code)
	if not entry then
		return false, "InvalidCode"
	end
	if entry.expires and now > entry.expires then
		return false, "CodeExpired"
	end
	if profile.codes[entry.code] then
		return false, "CodeUsed"
	end
	local ok, err = Rewards.canApply(profile, entry.reward)
	if not ok then
		return false, err
	end
	profile.codes[entry.code] = true
	local summary = Rewards.apply(profile, entry.reward, context)
	summary.code = entry.code
	return true, summary
end

-- Milestones -----------------------------------------------------------------------------

-- (artifacts found, mutation variants found)
function Rewards.collectionCounts(profile: Profile): (number, number)
	local artifacts, variants = 0, 0
	for _, entry in profile.collection do
		artifacts += 1
		for _ in entry.muts do
			variants += 1
		end
	end
	return artifacts, variants
end

function Rewards.milestoneProgress(profile: Profile, milestone: Milestones.Milestone): (number, number)
	local artifacts, variants = Rewards.collectionCounts(profile)
	if milestone.artifacts then
		return artifacts, milestone.artifacts
	end
	return variants, milestone.variants or 0
end

function Rewards.milestoneReady(profile: Profile, milestone: Milestones.Milestone): boolean
	if profile.milestones[milestone.id] then
		return false
	end
	local progress, target = Rewards.milestoneProgress(profile, milestone)
	return progress >= target
end

function Rewards.claimMilestone(profile: Profile, id: string, context: Boxes.Context): (boolean, any)
	local milestone = Milestones.get(id)
	if not milestone then
		return false, "BadRequest"
	end
	if profile.milestones[id] then
		return false, "AlreadyClaimed"
	end
	if not Rewards.milestoneReady(profile, milestone) then
		return false, "MilestoneLocked"
	end
	local ok, err = Rewards.canApply(profile, milestone.reward)
	if not ok then
		return false, err
	end
	profile.milestones[id] = true
	local summary = Rewards.apply(profile, milestone.reward, context)
	summary.id = id
	return true, summary
end

return Rewards
