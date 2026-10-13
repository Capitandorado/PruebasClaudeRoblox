--!strict
-- Special effect types an artifact can carry (Config/Artifacts `effects`).
-- Production.compute applies them; `describe` produces the text shown in the UI.

local Effects = {}

export type EffectInfo = {
	name: string,
	describe: (effect: any) -> string,
}

local function pct(value: number?): string
	local amount = (value or 0) * 100
	if amount == math.floor(amount) then
		return string.format("%d%%", amount)
	end
	return string.format("%.1f%%", amount)
end

Effects.Types = {
	global_mult = {
		name = "Reactor",
		describe = function(effect)
			return "+" .. pct(effect.amount) .. " output for every artifact in the factory"
		end,
	},
	adjacent_mult = {
		name = "Amplifier",
		describe = function(effect)
			return "+" .. pct(effect.amount) .. " output for artifacts on adjacent pedestals"
		end,
	},
	luck = {
		name = "Distortion",
		describe = function(effect)
			return "+" .. pct(effect.amount) .. " luck on every box (shifts odds toward rarer tiers)"
		end,
	},
	duplicate = {
		name = "Duplicator",
		describe = function(effect)
			return pct(effect.amount) .. " chance that a box gives a second copy"
		end,
	},
	speed = {
		name = "Accelerator",
		describe = function(effect)
			return "Fabricators and printers work " .. pct(effect.amount) .. " faster"
		end,
	},
	entropy = {
		name = "Entropy",
		describe = function(effect)
			local min, max = effect.min or 0, effect.max or 1
			return string.format(
				"Output re-rolls every second between x%.1f and x%.1f (average x%.2f)",
				min,
				max,
				(min + max) / 2
			)
		end,
	},
	singularity = {
		name = "Singularity",
		describe = function(effect)
			return "+" .. pct(effect.amount) .. " factory output for each different effect type placed"
		end,
	},
	surge = {
		name = "Void Surge",
		describe = function(effect)
			return string.format(
				"Every %d min the factory surges for %ds: x%d output and boxes recharge instantly",
				math.floor((effect.period or 300) / 60),
				effect.duration or 30,
				effect.amount or 2
			)
		end,
	},
} :: { [string]: EffectInfo }

function Effects.describe(effect: any): string
	local info = Effects.Types[effect.type]
	return if info then info.describe(effect) else "Unknown effect"
end

function Effects.name(effectType: string): string
	local info = Effects.Types[effectType]
	return if info then info.name else effectType
end

return Effects
