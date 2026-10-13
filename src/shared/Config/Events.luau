--!strict
-- Timed events. Everything is derived from the shared clock (workspace:GetServerTimeNow), so
-- every server and client agrees on which events are active without any messaging.
--
-- Rotating events: every `Period` seconds one event (picked deterministically from the time
-- window) runs for `Duration` seconds, on every server at once.
-- Scheduled events: fixed UTC windows; they can enable extra artifact catalogs, so seasonal
-- artifacts only drop while their event runs (see `catalog` in Config/Artifacts).
--
-- Modifiers: luckMult, productionMult, speedBonus (added after the speed cap), mutationMult.

export type Event = {
	id: string,
	name: string,
	description: string,
	color: Color3,
	luckMult: number?,
	productionMult: number?,
	speedBonus: number?,
	mutationMult: number?,
	catalog: string?,
	startsAt: number?,
	endsAt: number?,
}

local Events = {}

Events.Period = 1800
Events.Duration = 300

Events.Rotating = {
	{
		id = "luck_storm",
		name = "Luck Storm",
		description = "+50% luck on every box",
		color = Color3.fromRGB(110, 255, 150),
		luckMult = 1.5,
	},
	{
		id = "overdrive",
		name = "Overdrive",
		description = "+50% Energy production",
		color = Color3.fromRGB(255, 200, 60),
		productionMult = 1.5,
	},
	{
		id = "rapid_fabrication",
		name = "Rapid Fabrication",
		description = "Fabricators and printers 50% faster",
		color = Color3.fromRGB(90, 200, 255),
		speedBonus = 0.5,
	},
	{
		id = "mutation_rain",
		name = "Mutation Rain",
		description = "x3 mutation chance",
		color = Color3.fromRGB(255, 120, 230),
		mutationMult = 3,
	},
} :: { Event }

-- Times are UTC unix seconds.
Events.Scheduled = {
	{
		id = "winter_freeze_2026",
		name = "Winter Freeze",
		description = "Frost artifacts can drop from every box, +20% luck",
		color = Color3.fromRGB(170, 230, 255),
		luckMult = 1.2,
		catalog = "winter",
		startsAt = 1797638400, -- 2026-12-19 00:00 UTC
		endsAt = 1799193600, -- 2027-01-06 00:00 UTC
	},
} :: { Event }

return Events
