-- Robux products (blueprint section 9).
-- IMPORTANT: the Id fields are 0 until you create the passes and products on the Creator Hub
-- (Creations > your experience > Monetization) and paste their ids here. A 0 id is skipped safely.

export type Product = { Key: string, Id: number, Name: string, Price: number, Description: string }

local Monetization = {
	GamePasses = {
		VIP = { Key = "VIP", Id = 0, Name = "VIP", Price = 299, Description = "+10% yen, VIP booth, gold chat tag, extra rumor reroll" },
		DoubleYen = { Key = "DoubleYen", Id = 0, Name = "2× Yen", Price = 399, Description = "Double yen from jobs and class" },
		OutfitSlots = { Key = "OutfitSlots", Id = 0, Name = "Outfit Slots", Price = 149, Description = "6 saved outfits instead of 2" },
		CrewPlus = { Key = "CrewPlus", Id = 0, Name = "Crew Plus", Price = 249, Description = "Crew banner and extra emblem colors (cosmetic)" },
	} :: { [string]: Product },

	DeveloperProducts = {
		StyleTicket = { Key = "StyleTicket", Id = 0, Name = "Style Ticket", Price = 249, Description = "Unlock one fighting style of your choice" },
		CapsuleToken1 = { Key = "CapsuleToken1", Id = 0, Name = "Capsule Token", Price = 25, Description = "1 capsule roll" },
		CapsuleToken10 = { Key = "CapsuleToken10", Id = 0, Name = "10 Capsule Tokens", Price = 225, Description = "10 capsule rolls" },
		StarterPack = { Key = "StarterPack", Id = 0, Name = "Starter Pack", Price = 99, Description = "5,000 yen, 10 scrolls, 3 capsule tokens, Rookie jacket" },
		TermPass = { Key = "TermPass", Id = 0, Name = "Term Pass", Price = 399, Description = "Premium track for this term" },
		NameChange = { Key = "NameChange", Id = 0, Name = "Name Change", Price = 99, Description = "Change your in-game display name" },
		YenPack = { Key = "YenPack", Id = 0, Name = "Yen Pack", Price = 49, Description = "2,000 yen" },
	} :: { [string]: Product },

	VIPYenBonus = 0.1,
	StarterPackWindowHours = 48,
	StarterPack = { Yen = 5000, Scrolls = 10, CapsuleTokens = 3, Cosmetic = "arm_red" },
	YenPackAmount = 2000,

	-- Studio only: pretend the player owns every game pass, for testing.
	StudioGrantAllPasses = false,
}

return Monetization
