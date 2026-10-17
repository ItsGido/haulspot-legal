-- Rank ladder and Rep rules (blueprint sections 6.2 and 6.3).

export type Rank = { Number: number, Title: string, Rep: number, Color: string, Unlocks: string }

local Ranks = {
	List = {
		{ Number = 1, Title = "Transfer Student", Rep = 0, Color = "#B0B6BE", Unlocks = "Tutorial, rookie protection" },
		{ Number = 2, Title = "Freshman", Rep = 500, Color = "#5BD96A", Unlocks = "Scooters, gym tournament" },
		{ Number = 3, Title = "Troublemaker", Rep = 2500, Color = "#3FA7FF", Unlocks = "Crews, YenPay gifting, station spawn" },
		{ Number = 4, Title = "Delinquent", Rep = 8000, Color = "#B04DFF", Unlocks = "Jacket customization" },
		{ Number = 5, Title = "Enforcer", Rep = 20000, Color = "#FF7A1A", Unlocks = "Motorcycle, forced crown challenges" },
		{ Number = 6, Title = "Lieutenant", Rep = 45000, Color = "#FF3B6B", Unlocks = "Name color" },
		{ Number = 7, Title = "Ace", Rep = 90000, Color = "#FFB627", Unlocks = "Aura cosmetic slot" },
		{ Number = 8, Title = "Legend", Rep = 160000, Color = "#FFE066", Unlocks = "Legend jacket, hall of fame" },
	} :: { Rank },

	RankUpScrolls = 5,
	RankUpYenPerRank = 1000,

	-- Rep sources
	OpenFightWin = 15,
	DuelBase = 20,
	DuelPerRankGap = 10,
	DuelMin = 5,
	DuelMax = 60,
	LossPenalty = 5,
	ClassReward = 20,
	TurfCaptureReward = 200,
	TournamentWinner = 1000,
	TournamentFinalist = 400,
	TournamentSemifinalist = 150,
	AfterSchoolRedZoneMultiplier = 2,
	CrownHolderMultiplier = 1.5,
	FriendNearbyBonus = 0.1,
	FriendNearbyRadius = 60,

	-- Anti-farm
	NoRepRankGap = 3, -- beating someone this many ranks below gives 0 Rep
	SameOpponentCapPerHour = 3,

	-- Rookie protection
	RookieMaxRank = 2,
	RookieAttackerMaxGap = 1, -- attackers more than this many ranks above can't hit rookies
	RookieReenableCooldown = 600,
}

return Ranks
