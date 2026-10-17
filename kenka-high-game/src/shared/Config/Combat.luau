-- Combat tuning (blueprint section 1.4). All times are seconds, distances are studs.

local Combat = {
	-- Light attack (M1) combo
	M1Damage = { 4, 4, 4, 6 },
	M1Interval = 0.35, -- minimum time between M1 hits
	M1ComboReset = 1.0, -- combo resets after this long without an M1
	M1FinisherKnockback = 6,
	M1Range = 6, -- base reach before the height multiplier

	-- Heavy attack (M2)
	HeavyDamage = 12,
	HeavyWindup = 0.45,
	HeavyCooldown = 1.4,
	HeavyPostureDamage = 35, -- posture damage when the heavy is blocked (guard break)
	HeavyRange = 6.5,

	-- Blocking and posture
	MaxPosture = 100,
	PostureRegenPerSecond = 12,
	PostureRegenDelay = 1.5,
	BlockDamageTaken = 0.2, -- fraction of damage taken while blocking
	BlockPostureCostPerHit = 10,
	BlockWalkSpeedMultiplier = 0.5,
	GuardBreakStun = 1.2,
	GuardBreakDamageTakenMultiplier = 1.2,
	GuardBreakPostureRefill = 40,

	-- Parry
	ParryWindow = 0.18,
	ParryStun = 0.6,
	ParryPostureGain = 15,
	ParryHeatGain = 10,
	ParryLockout = 0.8,
	ClashStagger = 0.3,

	-- Movement abilities
	DashDistance = 14,
	DashDuration = 0.3,
	DashCooldown = 2.0,
	DashPostureCost = 15,
	WeaveDistance = 6,
	WeaveIFrames = 0.25,
	WeaveCooldown = 1.5,
	WeavePostureCost = 10,
	SprintPostureCostPerSecond = 6,
	SprintSpeedMultiplier = 1.45,

	-- Heat
	MaxHeat = 100,
	HeatPerHitLanded = 2,
	HeatPerHitTaken = 5,
	HeatMoveDamage = 25,
	HeatMoveRange = 7,

	-- Knockdown, finish, recovery
	DownedDuration = 8,
	DownedCrawlSpeed = 4,
	HelpUpHoldTime = 3,
	HelpUpHP = 30,
	FinishHoldTime = 1.5,
	RecoverHP = 25,
	RecoverProtection = 3,
	RespawnDelay = 5,
	DuelLoserHPFraction = 0.5,

	-- Out of combat
	CombatTimeout = 8, -- seconds after the last hit dealt or taken
	OutOfCombatRegenFraction = 0.05, -- of MaxHP per second

	-- Server validation
	ReachLatencyAllowance = 2, -- extra studs allowed on server hit checks
	FacingDotMinimum = -0.17, -- cos(100 degrees): target must be roughly in front
	MaxRequestsPerSecond = 12,

	-- Fight rewards
	FightWinYen = 20,
	MasteryXPWin = 80,
	MasteryXPLoss = 25,
	MasteryXPPerHit = 1,
	MasteryXPHitCapPerFight = 40,
}

return table.freeze(Combat)
