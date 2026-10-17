-- Yen economy: jobs, shop items, sinks (blueprint sections 6.4 and 6.5).

export type ShopItem = {
	Id: string,
	Name: string,
	Category: string, -- "Food", "Medical", "Vehicle", "Uniform", "Service"
	Price: number,
	Shop: string, -- interactable id of the shop that sells it
	MinRank: number?,
	Buff: { Stat: string, Amount: number, Duration: number, Group: string }?,
	Heal: number?,
	Vehicle: string?,
	UniformColor: string?,
	Description: string,
}

export type Job = {
	Id: string,
	Name: string,
	Interactable: string,
	Duration: number, -- expected seconds
	MinDuration: number, -- server rejects finishes faster than this
	Pay: number,
	GoldBonus: number,
	GoldTime: number?, -- finish under this for the bonus
	Cooldown: number, -- seconds between shifts
	Description: string,
}

local Economy = {
	StartingYen = 500,
	HeightChangeCost = 2500,
	HeightChangeCooldown = 24 * 60 * 60,
	CrewCreateCost = 5000,
	CapsuleYenCost = 1500,
	FountainCoinCost = 10,
	FountainCooldown = 60,
	MorningJobBonus = 0.25,
	MorningFoodDiscount = 0.2,
	YenPayMinRank = 3,
	YenPayDailyLimit = 10000,
	ClassYen = 120,
	TurfIncomePerMinute = 30,

	Jobs = {
		RamenDelivery = {
			Id = "RamenDelivery",
			Name = "Ramen Delivery",
			Interactable = "RamenJob",
			Duration = 90,
			MinDuration = 25,
			Pay = 250,
			GoldBonus = 50,
			GoldTime = 70,
			Cooldown = 20,
			Description = "Deliver 3 bowls around town before they go cold.",
		},
		KonbiniShift = {
			Id = "KonbiniShift",
			Name = "Konbini Shift",
			Interactable = "KonbiniJob",
			Duration = 120,
			MinDuration = 45,
			Pay = 220,
			GoldBonus = 40,
			Cooldown = 20,
			Description = "Scan items to the beat. Don't miss a customer.",
		},
		ArcadeAttendant = {
			Id = "ArcadeAttendant",
			Name = "Arcade Attendant",
			Interactable = "ArcadeJob",
			Duration = 90,
			MinDuration = 25,
			Pay = 200,
			GoldBonus = 40,
			GoldTime = 60,
			Cooldown = 20,
			Description = "Collect the scattered tokens around Neon Alley.",
		},
	} :: { [string]: Job },

	-- Ramen delivery drop points (X, Z). Server checks the player reaches each in order.
	RamenDropPoints = { { -110, 90 }, { 90, 95 }, { -60, 200 }, { 50, 215 }, { -150, 110 }, { 130, 55 } },
	RamenDropRadius = 12,
	RamenDropsPerRun = 3,

	-- Arcade token spawn area around Neon Alley (center X, Z, half size)
	ArcadeTokenArea = { 105, 165, 35, 15 },
	ArcadeTokensPerRun = 6,
	ArcadeTokenRadius = 6,

	Items = {
		-- Food buffs (do not work in duels or tournaments)
		Ramen = { Id = "Ramen", Name = "Ramen", Category = "Food", Price = 120, Shop = "IchibanBowl", Buff = { Stat = "PostureRegen", Amount = 0.2, Duration = 300, Group = "Meal" }, Description = "Posture regen +20% for 5 min" },
		Onigiri = { Id = "Onigiri", Name = "Onigiri", Category = "Food", Price = 80, Shop = "Konbini24", Buff = { Stat = "MaxHP", Amount = 10, Duration = 300, Group = "Snack" }, Description = "+10 max HP for 5 min" },
		EnergyDrink = { Id = "EnergyDrink", Name = "Energy Drink", Category = "Food", Price = 150, Shop = "Konbini24", Buff = { Stat = "DashCooldown", Amount = -0.3, Duration = 180, Group = "Drink" }, Description = "Dash cooldown -0.3 s for 3 min" },
		VendingSoda = { Id = "VendingSoda", Name = "Vending Soda", Category = "Food", Price = 80, Shop = "VendingMachine", Buff = { Stat = "WalkSpeed", Amount = 1, Duration = 120, Group = "Drink" }, Description = "+1 walk speed for 2 min" },
		Coffee = { Id = "Coffee", Name = "Kissa Coffee", Category = "Food", Price = 100, Shop = "KissaHoshi", Buff = { Stat = "PostureRegen", Amount = 0.1, Duration = 600, Group = "Drink" }, Description = "Posture regen +10% for 10 min" },
		-- Medical
		Bandages = { Id = "Bandages", Name = "Bandages", Category = "Medical", Price = 50, Shop = "Pharmacy", Heal = 30, Description = "Heal 30 HP (out of combat)" },
		-- Vehicles
		Scooter = { Id = "Scooter", Name = "Scooter", Category = "Vehicle", Price = 8000, Shop = "SpeedyCycles", MinRank = 2, Vehicle = "Scooter", Description = "Ride at 40 studs/s" },
		Motorcycle = { Id = "Motorcycle", Name = "Motorcycle", Category = "Vehicle", Price = 45000, Shop = "SpeedyCycles", MinRank = 5, Vehicle = "Motorcycle", Description = "Ride at 60 studs/s" },
		-- Uniform variants (armband/jacket color until real clothing assets exist)
		UniformClassic = { Id = "UniformClassic", Name = "Classic Gakuran", Category = "Uniform", Price = 0, Shop = "TailorTanaka", UniformColor = "#1B1F33", Description = "The standard black uniform" },
		UniformWhite = { Id = "UniformWhite", Name = "White Long Coat", Category = "Uniform", Price = 1500, Shop = "TailorTanaka", UniformColor = "#ECE8DF", Description = "A delinquent classic" },
		UniformCrimson = { Id = "UniformCrimson", Name = "Crimson Jacket", Category = "Uniform", Price = 4000, Shop = "TailorTanaka", UniformColor = "#9E1B1B", Description = "Stand out in a crowd" },
		UniformNavy = { Id = "UniformNavy", Name = "Navy Blazer", Category = "Uniform", Price = 2500, Shop = "TailorTanaka", UniformColor = "#22397A", Description = "Prep-school look" },
		UniformGold = { Id = "UniformGold", Name = "Gold Trim Coat", Category = "Uniform", Price = 20000, Shop = "TailorTanaka", MinRank = 4, UniformColor = "#C99A2E", Description = "For those who earned it" },
	} :: { [string]: ShopItem },

	BathhouseBuff = { Stat = "PostureRegen", Amount = 0.1, Duration = 600, Group = "Bath" },

	-- Vehicles
	Vehicles = {
		Scooter = { Speed = 40, Color = "#FF9EC4" },
		Motorcycle = { Speed = 60, Color = "#E4322B" },
	},

	-- Daily login streak rewards (day 1..7, then repeats)
	LoginRewards = {
		{ Yen = 300 },
		{ Yen = 500 },
		{ Scrolls = 1 },
		{ Yen = 1200 },
		{ Scrolls = 2 },
		{ CapsuleTokens = 1 },
		{ Scrolls = 3, Badge = "Week1" },
	},
}

return Economy
