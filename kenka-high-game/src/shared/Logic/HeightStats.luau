--!strict
-- Height to combat stats (blueprint section 1.5).

export type Stats = { HP: number, WalkSpeed: number, Reach: number, Scale: number }

local HeightStats = {
	MinCm = 157,
	MaxCm = 193,
	DefaultCm = 175,
}

function HeightStats.Clamp(cm: number): number
	return math.clamp(math.floor(cm + 0.5), HeightStats.MinCm, HeightStats.MaxCm)
end

function HeightStats.Get(cm: number): Stats
	local t = (HeightStats.Clamp(cm) - HeightStats.MinCm) / (HeightStats.MaxCm - HeightStats.MinCm)
	return {
		HP = math.floor(90 + 25 * t + 0.5),
		WalkSpeed = 17 - 2 * t,
		Reach = 0.95 + 0.15 * t,
		Scale = 0.92 + 0.16 * t,
	}
end

-- "175 cm (5'9\")"
function HeightStats.Describe(cm: number): string
	local clamped = HeightStats.Clamp(cm)
	local totalInches = math.floor(clamped / 2.54 + 0.5)
	return string.format("%d cm (%d'%d\")", clamped, totalInches // 12, totalInches % 12)
end

return HeightStats
