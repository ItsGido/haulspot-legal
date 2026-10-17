-- Fighting styles (blueprint section 6.6). Styles are sidegrades: same base damage, different tools.
--
-- Technique fields:
--   Kind:      "Strike" (hit in front), "Lunge" (move forward then strike), "Grab" (unblockable, short range),
--              "MultiHit" (several small hits), "Projectile-free" kits only; no ranged attacks in v1.
--   Damage, Cooldown, Range (studs), Windup (seconds)
--   GuardBreak: ignores block and deals PostureDamage
--   Knockback (studs), KnockdownTime (seconds the target is floored, can't act)
--   Hits/HitInterval for MultiHit, LungeDistance for Lunge, Charge (seconds held) for charged moves
--   RequiresParry: only usable within 1.5 s after a successful parry

export type Technique = {
	Name: string,
	Kind: string,
	Damage: number,
	Cooldown: number,
	Range: number,
	Windup: number,
	GuardBreak: boolean?,
	PostureDamage: number?,
	Knockback: number?,
	KnockdownTime: number?,
	Hits: number?,
	HitInterval: number?,
	LungeDistance: number?,
	Charge: number?,
	RequiresParry: boolean?,
}

export type Passive = {
	Name: string,
	Description: string,
	-- Numeric modifiers read by CombatMath. Missing fields mean "no change".
	LowHPDamageBonus: number?, -- extra damage multiplier below LowHPThreshold
	LowHPThreshold: number?,
	DashCooldownReduction: number?,
	HeavyDamageBonus: number?,
	ParryAutoThrowDamage: number?,
	M1FinisherPostureDamage: number?,
	WeaveCooldownReduction: number?,
	WeaveIFrameBonus: number?,
	KnockbackResistance: number?,
	WalkSpeedDelta: number?,
	KickReachBonus: number?,
}

export type Style = {
	Id: string,
	DisplayName: string,
	Order: number,
	Starter: boolean,
	ScrollCost: number,
	Color: string,
	Icon: string,
	Passive: Passive,
	Tech1: Technique, -- unlocks at Mastery 5
	Tech2: Technique, -- unlocks at Mastery 10
	Heat: Technique, -- unlocks at Mastery 15
}

local Styles: { [string]: Style } = {
	StreetBrawler = {
		Id = "StreetBrawler",
		DisplayName = "Street Brawler",
		Order = 1,
		Starter = true,
		ScrollCost = 0,
		Color = "#FF5A4F",
		Icon = "👊",
		Passive = { Name = "Scrappy", Description = "+10% damage below 30% HP", LowHPDamageBonus = 0.1, LowHPThreshold = 0.3 },
		Tech1 = { Name = "Headbutt", Kind = "Strike", Damage = 7, Cooldown = 8, Range = 4.5, Windup = 0.25, GuardBreak = true, PostureDamage = 30 },
		Tech2 = { Name = "Haymaker", Kind = "Strike", Damage = 18, Cooldown = 10, Range = 6, Windup = 0.8, Charge = 0.8, Knockback = 10 },
		Heat = { Name = "Dropkick", Kind = "Lunge", Damage = 25, Cooldown = 0, Range = 6, Windup = 0.35, LungeDistance = 12, Knockback = 16, KnockdownTime = 1.0 },
	},
	Boxing = {
		Id = "Boxing",
		DisplayName = "Boxing",
		Order = 2,
		Starter = true,
		ScrollCost = 0,
		Color = "#3FA7FF",
		Icon = "🥊",
		Passive = { Name = "Footwork", Description = "Dash cooldown -0.5 s", DashCooldownReduction = 0.5 },
		Tech1 = { Name = "Feint Jab", Kind = "Strike", Damage = 3, Cooldown = 6, Range = 6, Windup = 0.1, PostureDamage = 10 },
		Tech2 = { Name = "Counter Hook", Kind = "Strike", Damage = 14, Cooldown = 8, Range = 6, Windup = 0.15, RequiresParry = true, Knockback = 6 },
		Heat = { Name = "Rush Combo", Kind = "MultiHit", Damage = 5, Hits = 5, HitInterval = 0.12, Cooldown = 0, Range = 6.5, Windup = 0.2 },
	},
	Karate = {
		Id = "Karate",
		DisplayName = "Karate",
		Order = 3,
		Starter = true,
		ScrollCost = 0,
		Color = "#F5F1E8",
		Icon = "🥋",
		Passive = { Name = "Kime", Description = "Heavy attacks +10% damage", HeavyDamageBonus = 0.1 },
		Tech1 = { Name = "Front Kick", Kind = "Strike", Damage = 9, Cooldown = 7, Range = 9, Windup = 0.3, Knockback = 8 },
		Tech2 = { Name = "Breaking Chop", Kind = "Strike", Damage = 10, Cooldown = 10, Range = 6, Windup = 0.4, GuardBreak = true, PostureDamage = 40 },
		Heat = { Name = "Iron Fist", Kind = "Strike", Damage = 25, Cooldown = 0, Range = 7, Windup = 0.5, Knockback = 14, KnockdownTime = 1.0 },
	},
	Judo = {
		Id = "Judo",
		DisplayName = "Judo",
		Order = 4,
		Starter = false,
		ScrollCost = 25,
		Color = "#5FE08A",
		Icon = "🤼",
		Passive = { Name = "Kuzushi", Description = "A successful parry throws the attacker (6 dmg)", ParryAutoThrowDamage = 6 },
		Tech1 = { Name = "Hip Toss", Kind = "Grab", Damage = 10, Cooldown = 9, Range = 4.5, Windup = 0.3, KnockdownTime = 0.8 },
		Tech2 = { Name = "Foot Sweep", Kind = "Strike", Damage = 5, Cooldown = 10, Range = 5.5, Windup = 0.25, KnockdownTime = 0.8 },
		Heat = { Name = "Shoulder Slam", Kind = "Grab", Damage = 25, Cooldown = 0, Range = 5, Windup = 0.3, KnockdownTime = 1.2 },
	},
	MuayThai = {
		Id = "MuayThai",
		DisplayName = "Muay Thai",
		Order = 5,
		Starter = false,
		ScrollCost = 25,
		Color = "#FF7A1A",
		Icon = "🦵",
		Passive = { Name = "Clinch", Description = "4th light hit is a knee: +15 posture damage", M1FinisherPostureDamage = 15 },
		Tech1 = { Name = "Teep", Kind = "Strike", Damage = 6, Cooldown = 7, Range = 7.5, Windup = 0.25, Knockback = 10 },
		Tech2 = { Name = "Spinning Elbow", Kind = "Strike", Damage = 13, Cooldown = 9, Range = 5, Windup = 0.35 },
		Heat = { Name = "Flying Knee", Kind = "Lunge", Damage = 25, Cooldown = 0, Range = 6, Windup = 0.3, LungeDistance = 14, Knockback = 12 },
	},
	Capoeira = {
		Id = "Capoeira",
		DisplayName = "Capoeira",
		Order = 6,
		Starter = false,
		ScrollCost = 25,
		Color = "#FFD23F",
		Icon = "🌀",
		Passive = { Name = "Ginga", Description = "Weave cooldown -0.5 s, +0.05 s i-frames", WeaveCooldownReduction = 0.5, WeaveIFrameBonus = 0.05 },
		Tech1 = { Name = "Cartwheel Kick", Kind = "Lunge", Damage = 9, Cooldown = 8, Range = 6, Windup = 0.25, LungeDistance = 10 },
		Tech2 = { Name = "Rasteira", Kind = "Strike", Damage = 6, Cooldown = 10, Range = 6.5, Windup = 0.3, KnockdownTime = 0.9 },
		Heat = { Name = "Armada Spin", Kind = "MultiHit", Damage = 9, Hits = 3, HitInterval = 0.2, Cooldown = 0, Range = 7.5, Windup = 0.3, Knockback = 10 },
	},
	Sumo = {
		Id = "Sumo",
		DisplayName = "Sumo",
		Order = 7,
		Starter = false,
		ScrollCost = 25,
		Color = "#B04DFF",
		Icon = "🏋️",
		Passive = { Name = "Rooted", Description = "30% knockback resistance, -1 walk speed", KnockbackResistance = 0.3, WalkSpeedDelta = -1 },
		Tech1 = { Name = "Slap Barrage", Kind = "MultiHit", Damage = 3, Hits = 5, HitInterval = 0.12, Cooldown = 9, Range = 5.5, Windup = 0.15 },
		Tech2 = { Name = "Charge", Kind = "Lunge", Damage = 12, Cooldown = 11, Range = 5, Windup = 0.3, LungeDistance = 18, Knockback = 14 },
		Heat = { Name = "Ring-Out Shove", Kind = "Strike", Damage = 25, Cooldown = 0, Range = 6, Windup = 0.4, Knockback = 30, KnockdownTime = 1.0 },
	},
	Taekwondo = {
		Id = "Taekwondo",
		DisplayName = "Taekwondo",
		Order = 8,
		Starter = false,
		ScrollCost = 25,
		Color = "#FF9EC4",
		Icon = "🦶",
		Passive = { Name = "Long Leg", Description = "Kicks +1 stud reach", KickReachBonus = 1 },
		Tech1 = { Name = "Axe Kick", Kind = "Strike", Damage = 9, Cooldown = 9, Range = 7, Windup = 0.4, GuardBreak = true, PostureDamage = 30 },
		Tech2 = { Name = "Spinning Back Kick", Kind = "Strike", Damage = 14, Cooldown = 10, Range = 7.5, Windup = 0.35, Knockback = 10 },
		Heat = { Name = "Tornado Kick", Kind = "MultiHit", Damage = 9, Hits = 3, HitInterval = 0.18, Cooldown = 0, Range = 8, Windup = 0.3, Knockback = 12 },
	},
}

local Config = {
	Styles = Styles,
	DefaultStyle = "StreetBrawler",
	StarterIds = { "StreetBrawler", "Boxing", "Karate" },
	Tech1Mastery = 5,
	Tech2Mastery = 10,
	HeatMastery = 15,
	MaxMastery = 20,
	MasteryXPPerLevel = 120, -- level L needs 120 * L XP to reach L + 1
	ParryWindowForCounter = 1.5,
	DojoRange = 20, -- studs from the Sensei to switch styles
}

function Config.Ordered(): { Style }
	local list = {}
	for _, style in Styles do
		table.insert(list, style)
	end
	table.sort(list, function(a, b)
		return a.Order < b.Order
	end)
	return list
end

return Config
