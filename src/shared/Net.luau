--!strict
-- Network contract between client and server.
--
-- Client -> server: one RemoteFunction ("Request") carrying an action name plus arguments.
--   The server validates every argument against `Actions[name].args`, applies a per-action
--   token-bucket rate limit and returns { ok = boolean, err = string?, data = any }.
-- Server -> client: "State" (profile mirror), "Notify" (toasts, results, announcements) and
--   "Effect" (cosmetic world effects for every client).

local Net = {}

Net.FolderName = "Remotes"
Net.RequestName = "Request"
Net.StateName = "State"
Net.NotifyName = "Notify"
Net.EffectName = "Effect"

export type Validator = (value: any) -> boolean
export type ActionSpec = { args: { Validator }, rate: number, burst: number }

local function isInteger(value: any): boolean
	return type(value) == "number" and value == value and value == math.floor(value) and math.abs(value) < 2 ^ 31
end

local V = {}

function V.integer(min: number, max: number): Validator
	return function(value)
		return isInteger(value) and value >= min and value <= max
	end
end

-- Roblox UserIds no longer fit in 32 bits, and Studio test players have negative ids.
function V.userId(value: any): boolean
	return type(value) == "number" and value == math.floor(value) and value ~= 0 and math.abs(value) < 2 ^ 53
end

function V.id(maxLength: number): Validator
	return function(value)
		return type(value) == "string" and #value > 0 and #value <= maxLength and not string.find(value, "[%c]")
	end
end

function V.boolean(value: any): boolean
	return type(value) == "boolean"
end

function V.optional(validator: Validator): Validator
	return function(value)
		return value == nil or validator(value)
	end
end

function V.any(_value: any): boolean
	return true
end

Net.V = V

local ID = V.id(48)
local KEY = V.id(80)

Net.Actions = {
	OpenBox = { args = { ID }, rate = 6, burst = 8 },
	Place = { args = { V.integer(1, 64), KEY }, rate = 10, burst = 15 },
	Remove = { args = { V.integer(1, 64) }, rate = 10, burst = 15 },
	AutoFill = { args = {}, rate = 2, burst = 3 },
	ClearPlot = { args = {}, rate = 2, burst = 3 },
	Sell = { args = { KEY, V.integer(1, 100000) }, rate = 8, burst = 12 },
	SellRarity = { args = { ID, V.integer(0, 1000) }, rate = 2, burst = 3 },
	SetAutoSell = { args = { ID, V.boolean }, rate = 4, burst = 8 },
	BuyMachine = { args = { ID }, rate = 4, burst = 6 },
	UpgradeMachine = { args = { ID }, rate = 6, burst = 10 },
	BuyUpgrade = { args = { ID }, rate = 6, burst = 10 },
	BuyExpansion = { args = {}, rate = 2, burst = 3 },
	Fuse = { args = { KEY }, rate = 4, burst = 6 },
	Rebirth = { args = {}, rate = 0.5, burst = 1 },
	BuyPerk = { args = { ID }, rate = 4, burst = 6 },
	ClaimQuest = { args = { V.integer(1, 10) }, rate = 4, burst = 6 },
	ClaimDaily = { args = {}, rate = 1, burst = 2 },
	StudioPurchase = { args = { ID }, rate = 2, burst = 4 },
	RedeemCode = { args = { V.id(32) }, rate = 1, burst = 5 },
	ClaimMilestone = { args = { ID }, rate = 2, burst = 4 },
	SetSetting = { args = { ID, V.boolean }, rate = 4, burst = 8 },
	Visit = { args = { V.userId }, rate = 1, burst = 3 },
	GoHome = { args = {}, rate = 1, burst = 3 },
	GetLeaderboard = { args = {}, rate = 1, burst = 3 },
	Admin = { args = { ID, V.any }, rate = 10, burst = 20 },
} :: { [string]: ActionSpec }

-- Global cap across all actions for one player.
Net.GlobalRate = 25
Net.GlobalBurst = 40

-- `count` is select("#", ...) of the received arguments (holes make #args unreliable).
function Net.validate(actionName: any, args: { any }, count: number): (boolean, string?)
	if type(actionName) ~= "string" then
		return false, "BadRequest"
	end
	local spec = Net.Actions[actionName]
	if not spec then
		return false, "BadRequest"
	end
	if count > #spec.args then
		return false, "BadRequest"
	end
	for index, validator in spec.args do
		if not validator(args[index]) then
			return false, "BadRequest"
		end
	end
	return true, nil
end

return Net
