--!strict
-- Daily login rewards: a 7-day track that repeats. Claiming on consecutive days (UTC) keeps
-- the streak; missing a day restarts it at day 1. Energy rewards are worth `seconds` of the
-- player's current production, with a floor so new players still get something useful.
-- `crates` are Daily Crates (Config/Boxes "daily"), rolled on the server.

export type Reward = { seconds: number, min: number, crates: number }

local Daily = {}

Daily.DaySeconds = 86400
Daily.CrateBox = "daily"

Daily.Rewards = {
	{ seconds = 120, min = 250, crates = 0 },
	{ seconds = 180, min = 750, crates = 0 },
	{ seconds = 0, min = 0, crates = 1 },
	{ seconds = 300, min = 2500, crates = 0 },
	{ seconds = 420, min = 6000, crates = 0 },
	{ seconds = 600, min = 12000, crates = 0 },
	{ seconds = 600, min = 20000, crates = 2 },
} :: { Reward }

return Daily
