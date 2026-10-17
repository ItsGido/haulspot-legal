-- Cosmetic capsules (blueprint section 6.7). No combat effect. Odds are shown in game.
-- Every cosmetic is built from code (particles, colors, text) so no art assets are needed yet.
--
-- Slots: "Aura" (particle effect), "Title" (text tag above head), "Armband" (color on the arm),
--        "KOStamp" (text shown to the loser), "Trail" (trail while dashing)

export type Cosmetic = {
	Id: string,
	Name: string,
	Slot: string,
	Rarity: string,
	Color: string?,
	Color2: string?,
	Text: string?,
}

local Capsules = {
	Rarities = {
		{ Id = "Common", Weight = 60.0, Color = "#B0B6BE", Points = 5 },
		{ Id = "Rare", Weight = 28.0, Color = "#3FA7FF", Points = 15 },
		{ Id = "Epic", Weight = 9.0, Color = "#B04DFF", Points = 40 },
		{ Id = "Legendary", Weight = 2.7, Color = "#FFB627", Points = 100 },
		{ Id = "Mythic", Weight = 0.3, Color = "#FF3B6B", Points = 250 },
	},
	PityEpic = 10, -- Epic or better guaranteed on this roll
	PityLegendary = 60, -- Legendary or better guaranteed on this roll
	PointShopPrices = { Common = 40, Rare = 120, Epic = 320, Legendary = 800 }, -- Mythic not sold

	Pool = {
		-- Common
		{ Id = "arm_grey", Name = "Grey Armband", Slot = "Armband", Rarity = "Common", Color = "#8C92A4" },
		{ Id = "arm_white", Name = "White Armband", Slot = "Armband", Rarity = "Common", Color = "#F5F1E8" },
		{ Id = "arm_green", Name = "Green Armband", Slot = "Armband", Rarity = "Common", Color = "#3BC46B" },
		{ Id = "title_rookie", Name = "Title: Rookie", Slot = "Title", Rarity = "Common", Text = "Rookie", Color = "#B0B6BE" },
		{ Id = "title_lunch", Name = "Title: Lunch Thief", Slot = "Title", Rarity = "Common", Text = "Lunch Thief", Color = "#B0B6BE" },
		{ Id = "ko_oops", Name = "KO Stamp: OOPS", Slot = "KOStamp", Rarity = "Common", Text = "OOPS!" },
		-- Rare
		{ Id = "arm_red", Name = "Crimson Armband", Slot = "Armband", Rarity = "Rare", Color = "#E4322B" },
		{ Id = "arm_blue", Name = "Navy Armband", Slot = "Armband", Rarity = "Rare", Color = "#4A6FC4" },
		{ Id = "title_brawler", Name = "Title: Back-Lot Brawler", Slot = "Title", Rarity = "Rare", Text = "Back-Lot Brawler", Color = "#3FA7FF" },
		{ Id = "trail_white", Name = "Chalk Trail", Slot = "Trail", Rarity = "Rare", Color = "#F5F1E8" },
		{ Id = "ko_later", Name = "KO Stamp: LATER", Slot = "KOStamp", Rarity = "Rare", Text = "LATER, KID." },
		-- Epic
		{ Id = "arm_sakura", Name = "Sakura Armband", Slot = "Armband", Rarity = "Epic", Color = "#FF9EC4" },
		{ Id = "title_riverbank", Name = "Title: King of the Riverbank", Slot = "Title", Rarity = "Epic", Text = "King of the Riverbank", Color = "#B04DFF" },
		{ Id = "trail_sakura", Name = "Petal Trail", Slot = "Trail", Rarity = "Epic", Color = "#FF9EC4" },
		{ Id = "ko_crushed", Name = "KO Stamp: CRUSHED", Slot = "KOStamp", Rarity = "Epic", Text = "CRUSHED" },
		-- Legendary
		{ Id = "aura_sakura", Name = "Sakura Storm Aura", Slot = "Aura", Rarity = "Legendary", Color = "#FF9EC4", Color2 = "#FFFFFF" },
		{ Id = "aura_lightning", Name = "Lightning Aura", Slot = "Aura", Rarity = "Legendary", Color = "#9FD8FF", Color2 = "#FFFFFF" },
		{ Id = "aura_flame", Name = "Flame Aura", Slot = "Aura", Rarity = "Legendary", Color = "#FF7A1A", Color2 = "#FFD23F" },
		{ Id = "title_untouchable", Name = "Title: Untouchable", Slot = "Title", Rarity = "Legendary", Text = "Untouchable", Color = "#FFB627" },
		-- Mythic
		{ Id = "aura_oni", Name = "Oni Aura", Slot = "Aura", Rarity = "Mythic", Color = "#E4322B", Color2 = "#0F1016" },
		{ Id = "ko_legend", Name = "KO Stamp: LEGENDARY", Slot = "KOStamp", Rarity = "Mythic", Text = "★ LEGENDARY K.O. ★" },
		{ Id = "trail_rainbow", Name = "Rainbow Trail", Slot = "Trail", Rarity = "Mythic", Color = "#FF3B6B", Color2 = "#3FA7FF" },
	} :: { Cosmetic },
}

function Capsules.ById(id: string): Cosmetic?
	for _, item in Capsules.Pool do
		if item.Id == id then
			return item
		end
	end
	return nil
end

return Capsules
