--!strict
-- Offline progress. While a player is away their factory keeps producing at a reduced rate
-- (capped in time) and the Box Printer banks a few boxes. Only the server applies it, from
-- its own clock and the saved `lastOnline`, so the client cannot influence the amount.

local Shared = script.Parent.Parent
local Economy = require(Shared.Config.Economy)
local Logic = script.Parent
local State = require(Logic.State)
local Inventory = require(Logic.Inventory)
local Roller = require(Logic.Roller)
local Boxes = require(Logic.Actions.Boxes)

type Profile = any

export type Result = {
	away: number,
	seconds: number,
	rate: number,
	eps: number,
	energy: number,
	grants: { any },
}

local Offline = {}

function Offline.rate(profile: Profile): number
	return math.min(Economy.OfflineMaxRate, Economy.OfflineRate + State.perkBonus(profile, "nightshift"))
end

function Offline.maxSeconds(): number
	return Economy.OfflineMaxHours * 3600
end

-- Grants the progress made since `profile.lastOnline` and returns what was earned, or nil
-- when the player was not away long enough (or has never played).
function Offline.apply(profile: Profile, now: number, rng: Roller.Rng): Result?
	local last = profile.lastOnline
	if type(last) ~= "number" or last <= 0 then
		return nil
	end
	local away = now - last
	if away < Economy.OfflineMinSeconds then
		return nil
	end
	local seconds = math.min(away, Offline.maxSeconds())
	-- Steady production only: no Void Surge and no timed server event.
	local production = State.computeProduction(profile, 1, 1)
	local rate = Offline.rate(profile)
	local energy = math.floor(production.total * seconds * rate)
	Inventory.earn(profile, energy, false)

	local grants = {}
	local interval = State.printerInterval(profile, production)
	if interval > 0 then
		local boxes = math.min(Economy.PrinterBacklog, math.floor(seconds / interval))
		for _ = 1, boxes do
			local ok, result = Boxes.printerOpen(profile, { now = now, rng = rng, production = production })
			if not ok then
				break
			end
			for _, grant in result.grants do
				table.insert(grants, grant)
			end
		end
	end

	profile.lastOnline = now
	return {
		away = away,
		seconds = seconds,
		rate = rate,
		eps = production.total,
		energy = energy,
		grants = grants,
	}
end

return Offline
