--!strict
-- Number and time formatting for the UI.

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

function Format.number(value: number): string
	if value ~= value then
		return "0"
	end
	if value == math.huge then
		return "∞"
	end
	local negative = value < 0
	value = math.abs(value)
	local text
	if value < 1000 then
		if value < 10 and value ~= math.floor(value) then
			text = string.format("%.1f", value)
		else
			text = tostring(math.floor(value))
		end
	else
		local tier = math.min(#SUFFIXES - 1, math.floor(math.log10(value) / 3))
		local scaled = value / 10 ^ (tier * 3)
		if scaled >= 999.95 and tier < #SUFFIXES - 1 then
			tier += 1
			scaled = value / 10 ^ (tier * 3)
		end
		local decimals = if scaled < 10 then 2 elseif scaled < 100 then 1 else 0
		text = string.format("%." .. decimals .. "f", scaled)
		if decimals > 0 then
			text = string.gsub(text, "%.?0+$", "")
		end
		text ..= SUFFIXES[tier + 1]
	end
	return if negative then "-" .. text else text
end

-- 1234567 -> "1,234,567"
function Format.commas(value: number): string
	local text = tostring(math.floor(value))
	local result = string.reverse(text)
	result = string.gsub(result, "(%d%d%d)", "%1,")
	result = string.reverse(result)
	result = string.gsub(result, "^,", "")
	result = string.gsub(result, "^%-,", "-")
	return result
end

function Format.percent(chance: number): string
	local value = chance * 100
	if value >= 10 then
		return string.format("%.1f%%", value)
	elseif value >= 1 then
		return string.format("%.2f%%", value)
	elseif value >= 0.01 then
		return string.format("%.3f%%", value)
	end
	return string.format("%.5f%%", value)
end

function Format.oneIn(chance: number): string
	if chance <= 0 then
		return "never"
	end
	local n = 1 / chance
	if n < 10 then
		return string.format("1 in %.1f", n)
	end
	return "1 in " .. Format.commas(math.floor(n + 0.5))
end

function Format.duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds + 0.5))
	if seconds < 60 then
		return seconds .. "s"
	end
	local minutes = math.floor(seconds / 60)
	if minutes < 60 then
		return string.format("%dm %02ds", minutes, seconds % 60)
	end
	local hours = math.floor(minutes / 60)
	return string.format("%dh %02dm", hours, minutes % 60)
end

return Format
