--!strict
-- Which school period is it? Pure: derived from a server timestamp and the DayCycle config.

type Config = any -- Config/DayCycle.luau

export type PeriodState = {
	Index: number,
	Id: string,
	Name: string,
	Elapsed: number, -- seconds into this period
	Remaining: number, -- seconds left in this period
	EndsAt: number, -- server timestamp when it ends
	DayNumber: number, -- how many full cycles since the epoch
}

local DayCycleMath = {}

function DayCycleMath.At(config: Config, serverTime: number): PeriodState
	local cycleTime = serverTime % config.CycleLength
	local dayNumber = serverTime // config.CycleLength
	local start = 0
	for index, period in config.Periods do
		if cycleTime < start + period.Length then
			local elapsed = cycleTime - start
			return {
				Index = index,
				Id = period.Id,
				Name = period.Name,
				Elapsed = elapsed,
				Remaining = period.Length - elapsed,
				EndsAt = serverTime + (period.Length - elapsed),
				DayNumber = dayNumber,
			}
		end
		start += period.Length
	end
	-- Floating point edge: treat as the very start of the next cycle.
	local first = config.Periods[1]
	return { Index = 1, Id = first.Id, Name = first.Name, Elapsed = 0, Remaining = first.Length, EndsAt = serverTime + first.Length, DayNumber = dayNumber + 1 }
end

-- "6:12"
function DayCycleMath.FormatClock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

-- Calendar day number (UTC) for daily resets, and week number (weeks start Monday).
function DayCycleMath.UtcDay(unixTime: number): number
	return unixTime // 86400
end

function DayCycleMath.UtcWeek(unixTime: number): number
	-- 1970-01-01 was a Thursday; shift so weeks roll over on Monday 00:00 UTC.
	return (unixTime // 86400 + 3) // 7
end

return DayCycleMath
