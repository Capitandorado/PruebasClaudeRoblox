--!strict
-- Promo codes. Each works once per player; `expires` (Unix time, UTC) is optional.
-- Codes are case-insensitive: write them in UPPERCASE here.
-- Rewards use the format of Logic/Actions/Rewards.

local Codes = {}

export type Code = { code: string, reward: { [string]: any }, expires: number? }

Codes.List = {
	{ code = "VOIDFACTORY", reward = { seconds = 300, min = 2500 } },
	{ code = "LUCKY", reward = { boost = "luck", duration = 600 } },
	{ code = "CRATE", reward = { crates = 1 } },
} :: { Code }

local byCode: { [string]: Code } = {}
for _, entry in Codes.List do
	byCode[entry.code] = entry
end

function Codes.get(code: string): Code?
	return byCode[string.upper(code)]
end

return Codes
