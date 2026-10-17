--!strict
-- Deterministic quest selection: the same player gets the same rumors all day, on any server.

local QuestRoll = {}

-- Small deterministic PRNG (LCG) so results match between servers and tests.
function QuestRoll.Rng(seed: number): () -> number
	local state = seed % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return function(): number
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
end

-- Picks `count` distinct quest ids from `pool`, seeded by player and period (day or week number).
-- `exclude` lets a reroll avoid the quests already shown.
function QuestRoll.Pick(pool: { { Id: string } }, count: number, userId: number, period: number, salt: number, exclude: { [string]: boolean }?): { string }
	local rng = QuestRoll.Rng(userId * 7919 + period * 104729 + salt * 31)
	local available = {}
	for _, quest in pool do
		if not (exclude and exclude[quest.Id]) then
			table.insert(available, quest.Id)
		end
	end
	local picked = {}
	while #picked < count and #available > 0 do
		local index = math.clamp(math.floor(rng() * #available) + 1, 1, #available)
		table.insert(picked, table.remove(available, index) :: string)
	end
	return picked
end

return QuestRoll
