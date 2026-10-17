--!nocheck
-- Unit tests for the pure logic modules. Run with:  .tools/luau tests/run.luau   (or scripts/check.sh)
-- These modules have no Roblox dependencies, so they run in the plain Luau CLI.

local ZoneMath = require("../src/shared/Logic/ZoneMath")
local HeightStats = require("../src/shared/Logic/HeightStats")
local RepMath = require("../src/shared/Logic/RepMath")
local CapsuleRoll = require("../src/shared/Logic/CapsuleRoll")
local CombatMath = require("../src/shared/Logic/CombatMath")
local DayCycleMath = require("../src/shared/Logic/DayCycleMath")
local QuestRoll = require("../src/shared/Logic/QuestRoll")
local Format = require("../src/shared/Logic/Format")

local MapData = require("../src/shared/Map/MapData")
local Ranks = require("../src/shared/Config/Ranks")
local Capsules = require("../src/shared/Config/Capsules")
local DayCycle = require("../src/shared/Config/DayCycle")
local Quests = require("../src/shared/Config/Quests")
local Styles = require("../src/shared/Config/Styles")
local Combat = require("../src/shared/Config/Combat")
local Economy = require("../src/shared/Config/Economy")
local Crews = require("../src/shared/Config/Crews")

local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL  " .. name .. "\n      " .. tostring(err))
	end
end
local function eq(actual, expected, label)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", label or "value", tostring(expected), tostring(actual)), 2)
	end
end
local function near(actual, expected, label)
	if math.abs(actual - expected) > 1e-6 then
		error(string.format("%s: expected %s, got %s", label or "value", tostring(expected), tostring(actual)), 2)
	end
end

-- ZoneMath ------------------------------------------------------------------
local function zoneAt(x, y, z, turfWar)
	return ZoneMath.Find(MapData.Zones, x, y, z, MapData.DefaultZoneType, turfWar or false)
end

test("spawn is in the yellow courtyard", function()
	local r = zoneAt(0, 3, -30)
	eq(r.Name, "School Courtyard")
	eq(r.Type, "Yellow")
end)
test("back lot is red", function()
	eq(zoneAt(0, 3, -160).Type, "Red")
end)
test("rooftop is red only above Y 50", function()
	eq(zoneAt(0, 55, -105).Name, "Rooftop")
	eq(zoneAt(0, 55, -105).Type, "Red")
	eq(zoneAt(0, 3, -105).Name ~= "Rooftop", true, "ground under roof")
end)
test("shop fronts are green pockets inside the shotengai", function()
	local r = zoneAt(-12, 3, 90)
	eq(r.Type, "Green")
	eq(r.Turf, "T1")
end)
test("turf war turns shotengai street red but keeps shop fronts green", function()
	eq(zoneAt(0, 3, 150, false).Type, "Yellow", "street before turf war")
	eq(zoneAt(0, 3, 150, true).Type, "Red", "street during turf war")
	eq(zoneAt(-12, 3, 90, true).Type, "Green", "shop front during turf war")
end)
test("river water counts as red riverbank", function()
	local r = zoneAt(205, 1, 200)
	eq(r.Type, "Red")
	eq(r.Turf, "T2")
end)
test("open ground defaults to yellow streets", function()
	local r = zoneAt(150, 3, 30)
	eq(r.Type, "Yellow")
end)
test("every interactable sits in a green pocket or a safe-enough zone", function()
	for _, item in MapData.Interactables do
		local r = zoneAt(item.X, item.Y, item.Z, true)
		if item.Kind == "Shop" or item.Kind == "Job" or item.Kind == "Capsule" or item.Kind == "Class" or item.Kind == "Mirror" or item.Kind == "Dojo" then
			if item.Id ~= "VendingMachine" then
				eq(r.Type, "Green", item.Id .. " zone (" .. r.Name .. ")")
			end
		end
	end
end)
test("interactables are not inside solid buildings", function()
	for _, item in MapData.Interactables do
		for _, b in MapData.Buildings do
			local inside = math.abs(item.X - b.X) < b.SizeX / 2 and math.abs(item.Z - b.Z) < b.SizeZ / 2
				and item.Y >= b.BaseY and item.Y <= b.BaseY + b.Height
			eq(inside, false, item.Id .. " inside " .. b.Name)
		end
	end
end)
test("spawns are not inside buildings", function()
	for name, p in MapData.Spawns do
		for _, b in MapData.Buildings do
			local inside = math.abs(p[1] - b.X) < b.SizeX / 2 and math.abs(p[3] - b.Z) < b.SizeZ / 2 and p[2] <= b.BaseY + b.Height
			eq(inside, false, name .. " inside " .. b.Name)
		end
	end
end)
test("ramen drop points are reachable", function()
	for i, p in Economy.RamenDropPoints do
		for _, b in MapData.Buildings do
			local inside = math.abs(p[1] - b.X) < b.SizeX / 2 + 2 and math.abs(p[2] - b.Z) < b.SizeZ / 2 + 2
			eq(inside, false, "drop " .. i .. " inside " .. b.Name)
		end
	end
end)
test("job interactables exist", function()
	for _, job in Economy.Jobs do
		local item = MapData.GetInteractable(job.Interactable)
		eq(item ~= nil, true, job.Id)
		eq(item.Job, job.Id, job.Id .. " job link")
	end
end)
test("every shop item points at a real shop interactable", function()
	for _, shopItem in Economy.Items do
		local found = false
		for _, item in MapData.Interactables do
			if item.Shop == shopItem.Shop then
				found = true
			end
		end
		eq(found, true, shopItem.Id .. " shop " .. shopItem.Shop)
	end
end)
test("map is compact: everything within 20 s walk of the gate", function()
	for _, item in MapData.Interactables do
		local distance = math.sqrt(item.X ^ 2 + item.Z ^ 2)
		eq(distance / 16 <= 20, true, item.Id .. " is " .. math.floor(distance / 16) .. " s from the gate")
	end
end)
test("tournament ring is open ground, not inside a building", function()
	local GameConfig = require("../src/shared/Config/Game")
	local c = GameConfig.Tournament.RingCenter
	for _, b in MapData.Buildings do
		local inside = math.abs(c[1] - b.X) < b.SizeX / 2 + GameConfig.Tournament.RingRadius and math.abs(c[2] - b.Z) < b.SizeZ / 2
		eq(inside, false, "ring overlaps " .. b.Name)
	end
	eq(zoneAt(c[1], 3, c[2]).Type ~= "Green", true, "duels are blocked in green zones")
end)
test("arcade tokens can't spawn inside buildings", function()
	local a = Economy.ArcadeTokenArea
	for _, b in MapData.Buildings do
		local overlapX = math.abs(a[1] - b.X) < a[3] + b.SizeX / 2
		local overlapZ = math.abs(a[2] - b.Z) < a[4] + b.SizeZ / 2
		eq(overlapX and overlapZ, false, "token area overlaps " .. b.Name)
	end
end)
test("turf walls match crew turf ids", function()
	for _, id in Crews.TurfIds do
		eq(MapData.TurfWalls[id] ~= nil, true, id)
	end
end)

-- HeightStats ---------------------------------------------------------------
test("height extremes match the blueprint table", function()
	local short, tall, mid = HeightStats.Get(157), HeightStats.Get(193), HeightStats.Get(175)
	eq(short.HP, 90)
	eq(tall.HP, 115)
	eq(mid.HP, 103)
	near(short.WalkSpeed, 17)
	near(tall.WalkSpeed, 15)
	near(tall.Reach, 1.1)
end)
test("height clamps out-of-range input", function()
	eq(HeightStats.Clamp(120), 157)
	eq(HeightStats.Clamp(250), 193)
	eq(HeightStats.Describe(175), "175 cm (5'9\")")
end)

-- RepMath -------------------------------------------------------------------
test("rank thresholds", function()
	eq(RepMath.RankForRep(Ranks, 0), 1)
	eq(RepMath.RankForRep(Ranks, 499), 1)
	eq(RepMath.RankForRep(Ranks, 500), 2)
	eq(RepMath.RankForRep(Ranks, 2500), 3)
	eq(RepMath.RankForRep(Ranks, 999999), 8)
end)
test("duel wager clamps 5..60", function()
	eq(RepMath.DuelWager(Ranks, 3, 3), 20)
	eq(RepMath.DuelWager(Ranks, 2, 5), 50)
	eq(RepMath.DuelWager(Ranks, 1, 8), 60)
	eq(RepMath.DuelWager(Ranks, 8, 1), 5)
end)
test("losses never drop below the rank floor", function()
	eq(RepMath.ApplyLoss(Ranks, 502), 500)
	eq(RepMath.ApplyLoss(Ranks, 600), 595)
	eq(RepMath.ApplyLoss(Ranks, 2), 0)
end)
test("no rep for beating someone 3+ ranks lower", function()
	eq(RepMath.OpenFightReward(Ranks, 5, 2), 0)
	eq(RepMath.OpenFightReward(Ranks, 4, 2), 15)
end)
test("rookie protection", function()
	eq(RepMath.RookieAllowsHit(Ranks, 3, 2, false), true, "one rank above")
	eq(RepMath.RookieAllowsHit(Ranks, 4, 2, false), false, "two ranks above")
	eq(RepMath.RookieAllowsHit(Ranks, 6, 1, true), true, "opted out")
	eq(RepMath.RookieAllowsHit(Ranks, 8, 3, false), true, "not a rookie")
end)
test("progress to next rank", function()
	near(RepMath.Progress(Ranks, 250), 0.5)
	near(RepMath.Progress(Ranks, 200000), 1)
end)

-- CapsuleRoll ---------------------------------------------------------------
test("capsule weights add up to 100", function()
	local total = 0
	for _, r in Capsules.Rarities do
		total += r.Weight
	end
	near(total, 100)
end)
test("every rarity has items", function()
	for _, r in Capsules.Rarities do
		local count = 0
		for _, item in Capsules.Pool do
			if item.Rarity == r.Id then
				count += 1
			end
		end
		eq(count > 0, true, r.Id)
	end
end)
test("pity guarantees epic on roll 10 and legendary on roll 60", function()
	local alwaysCommon = function()
		return 0
	end
	local pity = { PityEpic = 0, PityLegendary = 0 }
	for i = 1, 9 do
		local r = CapsuleRoll.Roll(Capsules, pity, alwaysCommon)
		eq(r.Rarity, "Common", "roll " .. i)
		pity = { PityEpic = r.PityEpic, PityLegendary = r.PityLegendary }
	end
	local tenth = CapsuleRoll.Roll(Capsules, pity, alwaysCommon)
	eq(CapsuleRoll.RarityRank(tenth.Rarity) >= 3, true, "10th roll epic+")
	eq(tenth.PityEpic, 0)
	pity = { PityEpic = 0, PityLegendary = 59 }
	local sixtieth = CapsuleRoll.Roll(Capsules, pity, alwaysCommon)
	eq(CapsuleRoll.RarityRank(sixtieth.Rarity) >= 4, true, "60th roll legendary+")
	eq(sixtieth.PityLegendary, 0)
end)
test("capsule distribution roughly matches weights", function()
	local rng = QuestRoll.Rng(12345)
	local counts = {}
	local pity = { PityEpic = 0, PityLegendary = 0 }
	local n = 20000
	for _ = 1, n do
		local r = CapsuleRoll.Roll(Capsules, { PityEpic = 0, PityLegendary = 0 }, rng)
		counts[r.Rarity] = (counts[r.Rarity] or 0) + 1
		pity = pity
	end
	local commonShare = counts.Common / n
	eq(commonShare > 0.57 and commonShare < 0.63, true, "common share " .. commonShare)
end)

-- CombatMath ----------------------------------------------------------------
local base = { BaseDamage = 10, IsHeavy = false, AttackerHP = 100, AttackerMaxHP = 100, TargetBlocking = false, TargetGuardBroken = false, IgnoresBlock = false, BlockDamageTaken = Combat.BlockDamageTaken, GuardBreakMultiplier = Combat.GuardBreakDamageTakenMultiplier }
local function with(overrides)
	local t = table.clone(base)
	for k, v in overrides do
		t[k] = v
	end
	return t
end
test("blocking takes 20% damage", function()
	local r = CombatMath.Damage(with({ TargetBlocking = true }))
	near(r.Damage, 2)
	eq(r.Blocked, true)
end)
test("guard break ignores block", function()
	local r = CombatMath.Damage(with({ TargetBlocking = true, IgnoresBlock = true }))
	near(r.Damage, 10)
	eq(r.Blocked, false)
end)
test("guard broken targets take +20%", function()
	near(CombatMath.Damage(with({ TargetGuardBroken = true })).Damage, 12)
end)
test("scrappy passive below 30% HP", function()
	local passive = Styles.Styles.StreetBrawler.Passive
	near(CombatMath.Damage(with({ AttackerHP = 20, AttackerPassive = passive })).Damage, 11)
	near(CombatMath.Damage(with({ AttackerHP = 50, AttackerPassive = passive })).Damage, 10)
end)
test("karate heavy bonus", function()
	local passive = Styles.Styles.Karate.Passive
	near(CombatMath.Damage(with({ BaseDamage = 12, IsHeavy = true, AttackerPassive = passive })).Damage, 13.2)
end)
test("parry window", function()
	eq(CombatMath.IsParry(10, 10.1, 0.18), true)
	eq(CombatMath.IsParry(10, 10.3, 0.18), false)
end)
test("boxing dash cooldown", function()
	near(CombatMath.DashCooldown(2, Styles.Styles.Boxing.Passive, 0), 1.5)
	near(CombatMath.DashCooldown(2, nil, -0.3), 1.7)
end)
test("mastery levels", function()
	local level, xp = CombatMath.AddMasteryXP(1, 0, 120, 120, 20)
	eq(level, 2)
	eq(xp, 0)
	level, xp = CombatMath.AddMasteryXP(1, 0, 120 + 240 + 10, 120, 20)
	eq(level, 3)
	eq(xp, 10)
	level = CombatMath.AddMasteryXP(19, 0, 99999, 120, 20)
	eq(level, 20)
end)
test("mastery 5 takes about 15 wins", function()
	local level, xp, fights = 1, 0, 0
	while level < 5 do
		level, xp = CombatMath.AddMasteryXP(level, xp, Combat.MasteryXPWin + 40, Styles.MasteryXPPerLevel, Styles.MaxMastery)
		fights += 1
	end
	eq(fights >= 8 and fights <= 20, true, "fights to mastery 5: " .. fights)
end)
test("sumo knockback resistance", function()
	near(CombatMath.Knockback(10, Styles.Styles.Sumo.Passive), 7)
end)

-- Styles config -------------------------------------------------------------
test("every style has full kits and valid numbers", function()
	local count = 0
	for id, style in Styles.Styles do
		count += 1
		eq(style.Id, id)
		for _, key in { "Tech1", "Tech2", "Heat" } do
			local tech = style[key]
			eq(type(tech.Name), "string", id .. "." .. key)
			eq(tech.Damage > 0, true, id .. "." .. key .. " damage")
			eq(tech.Range > 0, true, id .. "." .. key .. " range")
			if tech.Kind == "MultiHit" then
				eq(tech.Hits ~= nil and tech.HitInterval ~= nil, true, id .. "." .. key .. " multihit fields")
			end
			if tech.Kind == "Lunge" then
				eq(tech.LungeDistance ~= nil, true, id .. "." .. key .. " lunge distance")
			end
		end
	end
	eq(count, 8)
	eq(#Styles.StarterIds, 3)
end)

-- DayCycleMath --------------------------------------------------------------
test("cycle is 20 minutes", function()
	eq(DayCycle.CycleLength, 1200)
end)
test("period boundaries", function()
	eq(DayCycleMath.At(DayCycle, 0).Id, "Morning")
	eq(DayCycleMath.At(DayCycle, 179).Id, "Morning")
	eq(DayCycleMath.At(DayCycle, 180).Id, "Class")
	eq(DayCycleMath.At(DayCycle, 480).Id, "Lunch")
	eq(DayCycleMath.At(DayCycle, 660).Id, "AfterSchool")
	eq(DayCycleMath.At(DayCycle, 1199).Id, "AfterSchool")
	eq(DayCycleMath.At(DayCycle, 1200).Id, "Morning")
	near(DayCycleMath.At(DayCycle, 1200 * 5 + 700).Remaining, 500)
	eq(DayCycleMath.At(DayCycle, 1200 * 5 + 700).DayNumber, 5)
end)
test("clock format", function()
	eq(DayCycleMath.FormatClock(372), "6:12")
	eq(DayCycleMath.FormatClock(5), "0:05")
end)
test("utc week rolls over on monday", function()
	-- 2026-10-12 is a Monday. 2026-10-11 is a Sunday.
	local monday = 1791763200 -- 2026-10-12 00:00:00 UTC
	eq(DayCycleMath.UtcWeek(monday - 1) + 1, DayCycleMath.UtcWeek(monday))
	eq(DayCycleMath.UtcWeek(monday), DayCycleMath.UtcWeek(monday + 6 * 86400 + 86399))
end)

-- QuestRoll -----------------------------------------------------------------
test("quest picks are deterministic and distinct", function()
	local a = QuestRoll.Pick(Quests.Daily, 3, 12345, 20000, 1)
	local b = QuestRoll.Pick(Quests.Daily, 3, 12345, 20000, 1)
	eq(#a, 3)
	eq(table.concat(a, ","), table.concat(b, ","))
	eq(a[1] ~= a[2] and a[2] ~= a[3] and a[1] ~= a[3], true, "distinct")
end)
test("reroll excludes current quests", function()
	local current = QuestRoll.Pick(Quests.Daily, 3, 99, 20000, 1)
	local exclude = {}
	for _, id in current do
		exclude[id] = true
	end
	local replacement = QuestRoll.Pick(Quests.Daily, 1, 99, 20000, 2, exclude)
	eq(exclude[replacement[1]], nil, "replacement is new")
end)
test("quest events are from the documented list", function()
	local valid = { WinFight = true, WinDuel = true, LandHit = true, Parry = true, FinishJob = true, AttendClass = true, CaptureTurf = true, EarnYen = true, BuyFood = true, VisitDojo = true, Customize = true, JoinCrew = true, RankUp = true, UseHeat = true, TournamentMatch = true }
	for _, list in { Quests.Daily, Quests.Weekly, Quests.Story } do
		for _, q in list do
			eq(valid[q.Event], true, q.Id .. " event " .. q.Event)
		end
	end
end)

-- Format --------------------------------------------------------------------
test("abbreviations", function()
	eq(Format.Abbreviate(950), "950")
	eq(Format.Abbreviate(12480), "12.4K")
	eq(Format.Abbreviate(3400000), "3.4M")
	eq(Format.Abbreviate(2000), "2K")
end)
test("commas and yen", function()
	eq(Format.Commas(12480), "12,480")
	eq(Format.Commas(100), "100")
	eq(Format.Commas(1000000), "1,000,000")
	eq(Format.Yen(500), "¥500")
end)
test("durations", function()
	eq(Format.Duration(75), "1:15")
	eq(Format.Duration(3725), "1:02:05")
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
	error("tests failed")
end
