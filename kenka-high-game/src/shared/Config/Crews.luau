-- Crews and turf (blueprint sections 1.10, 5.5, 7.3 and the turf rules).

local Crews = {
	MinRank = 3,
	MaxMembers = 12,
	NameMin = 3,
	NameMax = 16,
	Roles = { "Leader", "Lieutenant", "Member" },
	InviteTimeout = 60,

	Colors = {
		"#E4322B", "#FF7A1A", "#FFD23F", "#5FE08A", "#3BC46B", "#3FA7FF",
		"#4A6FC4", "#B04DFF", "#FF9EC4", "#F5F1E8", "#8C92A4", "#0F1016",
	},
	-- Emblems are text glyphs for now; swap for image ids in the art pass.
	Emblems = {
		"龍", "虎", "鬼", "狼", "鷹", "蛇", "桜", "炎", "雷", "風",
		"刀", "拳", "星", "月", "日", "山", "川", "王", "魂", "侍",
		"★", "♠", "♣", "♥", "♦", "☠", "⚡", "☯", "♛", "⚔",
		"Ⅰ", "Ⅱ", "Ⅲ", "Ω", "Δ", "Σ", "∞", "✚", "✪", "❖",
	},

	-- Turf capture
	TurfIds = { "T1", "T2", "T3", "T4", "T5" },
	TurfNames = { T1 = "Shotengai", T2 = "Riverbank", T3 = "Hinode Park", T4 = "Docks", T5 = "Neon Alley" },
	CaptureRadius = 25,
	CaptureSeconds = 60, -- for one crew member
	CaptureMaxMultiplier = 3, -- 3+ members capture 3x faster
	CaptureDecayPerSecond = 2, -- percent per second with nobody present
	IncomeIntervalSeconds = 60,
}

return Crews
