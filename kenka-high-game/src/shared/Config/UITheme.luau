-- "Manga Ink" design tokens (blueprint section 4). Every screen reads colors and fonts from here.

local UITheme = {
	Ink = "#0F1016",
	Panel = "#1C1E2B",
	PanelLight = "#262A3B",
	PanelStroke = "#000000",
	Paper = "#F5F1E8",
	Muted = "#A9ADBD",
	Sakura = "#FF9EC4",

	Buttons = {
		-- top color, bottom color, text outline color
		Primary = { "#FF5A4F", "#B81D17", "#4A0906" },
		Secondary = { "#4A6FC4", "#22397A", "#0B1530" },
		Premium = { "#FFE066", "#E09A00", "#6B4400" },
		Success = { "#5FE08A", "#249A4C", "#0B3D1D" },
		Sakura = { "#FFB3D2", "#E0679B", "#5A1030" },
		Ghost = { "#262A3B", "#262A3B", "#000000" },
		Disabled = { "#5A5E6B", "#3B3E48", "#2A2C33" },
	},

	Bars = {
		HP = "#E4322B",
		HPBack = "#3A0F0E",
		Posture = "#F4C542",
		PostureBack = "#3A300E",
		Heat = { "#FF7A1A", "#FFD23F" },
		Rep = "#FFB627",
	},

	Zones = {
		Green = "#3BC46B",
		Yellow = "#F4C542",
		Red = "#E4322B",
	},

	Rarity = {
		Common = "#B0B6BE",
		Rare = "#3FA7FF",
		Epic = "#B04DFF",
		Legendary = "#FFB627",
		Mythic = "#FF3B6B",
	},

	Gold = "#FFE066",

	Fonts = {
		Title = Enum.Font.Bangers,
		Button = Enum.Font.BuilderSansBold,
		Body = Enum.Font.BuilderSansMedium,
		BodyBold = Enum.Font.BuilderSansBold,
		Number = Enum.Font.FredokaOne,
	},

	TextMax = { Title = 64, Button = 32, Body = 22, Number = 36 },

	Motion = {
		PanelOpen = { Time = 0.22, From = 0.85 },
		PanelClose = { Time = 0.12, To = 0.9 },
		PressIn = { Time = 0.08, Scale = 0.92 },
		PressOut = { Time = 0.15 },
		DimmerTransparency = 0.45,
	},

	-- Sound ids are 0 until you upload or pick sounds from the Creator Store. 0 = silent.
	Sounds = {
		Click = 0,
		Open = 0,
		Purchase = 0,
		Error = 0,
		Hit = 0,
		HeavyHit = 0,
		Parry = 0,
		RankUp = 0,
		Bell = 0,
		KO = 0,
	},
}

return UITheme
