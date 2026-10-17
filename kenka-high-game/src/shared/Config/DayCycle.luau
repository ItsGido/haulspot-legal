-- The server-wide school day (blueprint section 1.8). Loops forever, derived from server time,
-- so every server and client agrees on the current period without any saved state.

export type Period = { Id: string, Name: string, Length: number, Description: string }

local DayCycle = {
	Periods = {
		{ Id = "Morning", Name = "MORNING HOMEROOM", Length = 180, Description = "Jobs pay +25%. Food is 20% off." },
		{ Id = "Class", Name = "CLASS", Length = 300, Description = "Take a class in the West Wing for yen and Rep." },
		{ Id = "Lunch", Name = "LUNCH", Length = 180, Description = "Grab food. The rooftop is the place to be." },
		{ Id = "AfterSchool", Name = "AFTER SCHOOL", Length = 540, Description = "Turf war! Turf zones are RED. Double Rep in Red zones." },
	} :: { Period },
	-- Seconds into After School when the gym tournament may start.
	TournamentStartOffset = 60,
	-- Warning before turf zones turn red.
	TurfWarningSeconds = 10,
}

local total = 0
for _, period in DayCycle.Periods do
	total += period.Length
end
DayCycle.CycleLength = total -- 1200 seconds (20 minutes)

return DayCycle
