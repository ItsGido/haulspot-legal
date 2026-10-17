-- Global game settings.

local Game = {
	Title = "KENKA HIGH",
	ServerSize = 30,

	-- DataStores. Bump the version suffix to wipe all progress (never do this after launch).
	ProfileStoreName = "KenkaProfiles_v1",
	CrewStoreName = "KenkaCrews_v1",
	CrewNameStoreName = "KenkaCrewNames_v1",
	AutosaveInterval = 120,
	SessionLockTimeout = 300, -- a lock older than this (no autosave refresh) is treated as abandoned
	DataLoadRetries = 3,

	-- Studio testing helpers. These only apply in Roblox Studio, never in live servers.
	Studio = {
		UseMemoryDataWhenStoreUnavailable = true, -- if API access is off, play with unsaved data
		TournamentMinPlayers = 2, -- live servers use Tournament.MinPlayers
		SkipTutorial = false,
	},

	Tournament = {
		MinPlayers = 8,
		MaxPlayers = 8,
		MinRank = 2,
		MatchSeconds = 120,
		BetweenMatchesSeconds = 5,
		SignupCooldownSeconds = 600, -- after a tournament ends
		WinnerScrolls = 10,
		FinalistScrolls = 4,
		RingCenter = { -260, -230 }, -- X, Z inside the gym (fighters are teleported here)
		RingRadius = 18,
	},

	Crown = {
		StreakToClaim = 3,
		MinOpponentRank = 3,
		ForcedChallengeMinRank = 5,
		DuelCooldown = 90,
	},

	Challenge = {
		PromptDistance = 8,
		RingRadius = 30,
		ResponseTimeout = 10,
		LeaveRingGrace = 3,
		CooldownAfterDuel = 30,
		DeclineCooldownSamePlayer = 60,
	},

	VoidY = -50,
	UnstuckCooldown = 60,
	FriendRepBonusRadius = 60,
}

return Game
