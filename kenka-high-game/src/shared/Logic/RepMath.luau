--!strict
-- Rep, ranks and fight rewards (blueprint sections 1.6, 1.7, 6.2, 6.3).
-- Functions take the Ranks config as a parameter so they stay pure and testable.

-- Config tables are passed in (Config/Ranks.luau). Typed loosely so extra fields are fine.
type RanksConfig = any

local RepMath = {}

function RepMath.RankForRep(ranks: RanksConfig, rep: number): number
	local current = 1
	for _, entry in ranks.List do
		if rep >= entry.Rep then
			current = entry.Number
		end
	end
	return current
end

-- The Rep floor of a rank: losses can't push you below it.
function RepMath.RankFloor(ranks: RanksConfig, rank: number): number
	local entry = ranks.List[rank]
	return if entry then entry.Rep else 0
end

-- Progress toward the next rank, 0..1 (1 at max rank).
function RepMath.Progress(ranks: RanksConfig, rep: number): number
	local rank = RepMath.RankForRep(ranks, rep)
	local nextEntry = ranks.List[rank + 1]
	if not nextEntry then
		return 1
	end
	local floor = ranks.List[rank].Rep
	return math.clamp((rep - floor) / (nextEntry.Rep - floor), 0, 1)
end

-- Rep wagered on a challenge duel: 20 + 10 x (loser rank - winner rank), clamped 5..60.
function RepMath.DuelWager(ranks: RanksConfig, winnerRank: number, loserRank: number): number
	local amount = ranks.DuelBase + ranks.DuelPerRankGap * (loserRank - winnerRank)
	return math.clamp(amount, ranks.DuelMin, ranks.DuelMax)
end

-- Rep for winning an open fight. 0 when the loser is far below the winner (anti-bullying).
function RepMath.OpenFightReward(ranks: RanksConfig, winnerRank: number, loserRank: number): number
	if winnerRank - loserRank >= ranks.NoRepRankGap then
		return 0
	end
	return ranks.OpenFightWin
end

-- Apply a loss: returns the new Rep, never below the floor of the current rank.
function RepMath.ApplyLoss(ranks: RanksConfig, rep: number): number
	local rank = RepMath.RankForRep(ranks, rep)
	return math.max(RepMath.RankFloor(ranks, rank), rep - ranks.LossPenalty)
end

-- Rookie protection: may this attacker hit this target in a Red zone?
function RepMath.RookieAllowsHit(ranks: RanksConfig, attackerRank: number, targetRank: number, targetOptedOut: boolean): boolean
	if targetOptedOut or targetRank > ranks.RookieMaxRank then
		return true
	end
	return attackerRank - targetRank <= ranks.RookieAttackerMaxGap
end

return RepMath
