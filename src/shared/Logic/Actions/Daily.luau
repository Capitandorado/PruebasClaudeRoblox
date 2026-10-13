--!strict
-- Daily login rewards (Config/Daily). Days are UTC days of the server clock; the client uses
-- the same functions with the synchronised server time to show the track and countdown.

local Shared = script.Parent.Parent.Parent
local DailyConfig = require(Shared.Config.Daily)
local Logic = script.Parent.Parent
local State = require(Logic.State)
local Inventory = require(Logic.Inventory)
local Boxes = require(script.Parent.Boxes)

type Profile = any

export type Status = {
	available: boolean,
	streak: number, -- streak after claiming today's reward (or the current one if claimed)
	index: number, -- position in the 7-day track of the next/current reward
	nextIn: number, -- seconds until the next UTC day
}

local Daily = {}

function Daily.today(now: number): number
	return math.floor(now / DailyConfig.DaySeconds)
end

function Daily.status(profile: Profile, now: number): Status
	local today = Daily.today(now)
	local state = profile.daily
	local available = today > state.day
	local streak = state.streak
	if available then
		streak = if state.day == today - 1 then state.streak + 1 else 1
	end
	streak = math.max(1, streak)
	return {
		available = available,
		streak = streak,
		index = (streak - 1) % #DailyConfig.Rewards + 1,
		nextIn = (today + 1) * DailyConfig.DaySeconds - now,
	}
end

function Daily.energyFor(reward: DailyConfig.Reward, eps: number): number
	if reward.seconds <= 0 then
		return 0
	end
	return math.floor(math.max(reward.min, eps * reward.seconds))
end

function Daily.claim(profile: Profile, now: number, context: Boxes.Context): (boolean, any)
	local status = Daily.status(profile, now)
	if not status.available then
		return false, "AlreadyClaimed"
	end
	local reward = DailyConfig.Rewards[status.index]
	if reward.crates > 0 and State.freeSpace(profile) < reward.crates then
		return false, "InventoryFull"
	end
	local energy = Daily.energyFor(reward, context.production.total)
	Inventory.earn(profile, energy, false)
	local results = {}
	for _ = 1, reward.crates do
		local ok, result = Boxes.openCrate(profile, DailyConfig.CrateBox, context)
		if ok then
			table.insert(results, result)
		end
	end
	profile.daily.day = Daily.today(now)
	profile.daily.streak = status.streak
	profile.daily.claims += 1
	return true, { day = status.index, streak = status.streak, energy = energy, results = results }
end

return Daily
