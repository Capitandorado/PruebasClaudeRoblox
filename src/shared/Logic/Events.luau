--!strict
-- Resolves which events are active at a given time and the combined modifiers.
-- `Events.current` is what the rest of the logic reads; the server and the client call
-- `Events.refresh(now)` regularly (cheap), tests can call `Events.set(...)`.

local Config = require(script.Parent.Parent.Config.Events)

export type Modifiers = {
	luckMult: number,
	productionMult: number,
	speedBonus: number,
	mutationMult: number,
	catalogs: { [string]: boolean },
	active: { Config.Event },
	signature: string,
	endsAt: number,
}

local Events = {}

local function neutral(): Modifiers
	return {
		luckMult = 1,
		productionMult = 1,
		speedBonus = 0,
		mutationMult = 1,
		catalogs = { core = true },
		active = {},
		signature = "",
		endsAt = 0,
	}
end

Events.current = neutral()

-- Deterministic pick for a rotating window (same on every machine).
local function rotatingFor(window: number): Config.Event?
	local list = Config.Rotating
	if #list == 0 then
		return nil
	end
	local hash = (window * 2654435761) % 4294967296
	return list[(hash % #list) + 1]
end

function Events.modifiersAt(now: number): Modifiers
	local mods = neutral()
	local ids = {}
	local window = math.floor(now / Config.Period)
	local offset = now - window * Config.Period
	if offset < Config.Duration then
		local event = rotatingFor(window)
		if event then
			table.insert(mods.active, event)
			mods.endsAt = window * Config.Period + Config.Duration
		end
	end
	for _, event in Config.Scheduled do
		if event.startsAt and event.endsAt and now >= event.startsAt and now < event.endsAt then
			table.insert(mods.active, event)
			if mods.endsAt == 0 or event.endsAt < mods.endsAt then
				mods.endsAt = event.endsAt
			end
		end
	end
	for _, event in mods.active do
		mods.luckMult *= event.luckMult or 1
		mods.productionMult *= event.productionMult or 1
		mods.speedBonus += event.speedBonus or 0
		mods.mutationMult *= event.mutationMult or 1
		if event.catalog then
			mods.catalogs[event.catalog] = true
		end
		table.insert(ids, event.id)
	end
	mods.signature = table.concat(ids, ",")
	return mods
end

-- Updates Events.current. Returns true when the set of active events changed.
function Events.refresh(now: number): boolean
	local mods = Events.modifiersAt(now)
	local changed = mods.signature ~= Events.current.signature
	Events.current = mods
	return changed
end

function Events.set(mods: Modifiers?)
	Events.current = mods or neutral()
end

function Events.neutral(): Modifiers
	return neutral()
end

function Events.catalogActive(catalog: string): boolean
	return Events.current.catalogs[catalog] == true
end

-- Next start time of a rotating event (for the "next event in" countdown).
function Events.nextRotatingStart(now: number): number
	local window = math.floor(now / Config.Period)
	return (window + 1) * Config.Period
end

return Events
