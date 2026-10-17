--!strict
-- Text formatting helpers for the UI.

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi" }

-- 950 -> "950", 12480 -> "12.4K", 3400000 -> "3.4M"
function Format.Abbreviate(n: number): string
	local negative = n < 0
	local value = math.abs(n)
	local index = 1
	while value >= 1000 and index < #SUFFIXES do
		value /= 1000
		index += 1
	end
	local text
	if index == 1 then
		text = tostring(math.floor(value))
	else
		text = string.format("%.1f", math.floor(value * 10) / 10):gsub("%.0$", "") .. SUFFIXES[index]
	end
	return if negative then "-" .. text else text
end

-- 12480 -> "12,480"
function Format.Commas(n: number): string
	local text = tostring(math.floor(math.abs(n)))
	local result = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if result:sub(1, 1) == "," then
		result = result:sub(2)
	end
	return if n < 0 then "-" .. result else result
end

function Format.Yen(n: number): string
	return "¥" .. Format.Commas(n)
end

-- 75 -> "1:15", 3725 -> "1:02:05"
function Format.Duration(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	if s >= 3600 then
		return string.format("%d:%02d:%02d", s // 3600, (s % 3600) // 60, s % 60)
	end
	return string.format("%d:%02d", s // 60, s % 60)
end

return Format
