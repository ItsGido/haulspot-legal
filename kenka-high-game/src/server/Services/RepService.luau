--!strict
-- Rep, ranks and fight rewards (blueprint sections 1.6, 1.7, 6.2, 6.3).
--   RepService.GetRank(player) -> number
--   RepService.AddRep(player, amount, reason)   raw add, handles rank-ups
--   RepService.FightResult(winner, loser, info) the single place fight rewards happen
--     info = { Kind = "Open"|"Duel"|"Tournament", Wager?, WinnerHits?, LoserHits? }

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ranks = require(ReplicatedStorage.Shared.Config.Ranks)
local Combat = require(ReplicatedStorage.Shared.Config.Combat)
local RepMath = require(ReplicatedStorage.Shared.Logic.RepMath)
local Net = require(ReplicatedStorage.Shared.Util.Net)
local Notify = require(script.Parent.Parent.Systems.Notify)
local Util = require(script.Parent.Parent.Systems.ProgressionUtil)

local RepService = {}
RepService.Priority = 40

local Services: any

local SECONDS_PER_HOUR = 3600
local RANKUP_BANNER_POLL = 0.5 -- seconds between "still in combat?" checks before showing the banner
local RANKUP_BANNER_MAX_WAIT = 30 -- show the banner anyway after this long

local rankUpEvent = Net.Event("RankUp")

-- Anti-farm: recent rewarded wins per "winnerId:loserId" pair (os.clock timestamps).
local pairWins: { [string]: { number } } = {}
-- Roblox friendship cache: "lowId:highId" -> boolean
local friendCache: { [string]: boolean } = {}

local function friendKey(a: Player, b: Player): string
	local lo, hi = math.min(a.UserId, b.UserId), math.max(a.UserId, b.UserId)
	return lo .. ":" .. hi
end

local function areFriends(a: Player, b: Player): boolean
	if a == b or a.UserId <= 0 or b.UserId <= 0 then
		return false
	end
	local key = friendKey(a, b)
	local cached = friendCache[key]
	if cached ~= nil then
		return cached
	end
	local ok, result = pcall(function()
		return a:IsFriendsWithAsync(b.UserId)
	end)
	local value = ok and result == true
	if ok then
		friendCache[key] = value
	end
	return value
end

local function hasFriendNearby(winner: Player): boolean
	local root = Util.GetRoot(winner)
	if not root then
		return false
	end
	for _, other in Players:GetPlayers() do
		if other ~= winner then
			local otherRoot = Util.GetRoot(other)
			if otherRoot and (otherRoot.Position - root.Position).Magnitude <= Ranks.FriendNearbyRadius and areFriends(winner, other) then
				return true
			end
		end
	end
	return false
end

-- Records a rewarded win and returns true if the pair is still under the hourly cap.
local function underFarmCap(winner: Player, loser: Player): boolean
	local key = winner.UserId .. ":" .. loser.UserId
	local now = os.clock()
	local list: { number } = pairWins[key] or {}
	local fresh = {}
	for _, t in list do
		if now - t < SECONDS_PER_HOUR then
			table.insert(fresh, t)
		end
	end
	if #fresh >= Ranks.SameOpponentCapPerHour then
		pairWins[key] = fresh
		return false
	end
	table.insert(fresh, now)
	pairWins[key] = fresh
	return true
end

local function rankTitle(rank: number): string
	local entry = Ranks.List[rank]
	return if entry then entry.Title else Ranks.List[1].Title
end

local function showRankUpBanner(player: Player, payload: any)
	-- The banner waits until combat ends (blueprint section 8).
	local waited = 0
	while Services.CombatService and Services.CombatService.IsInCombat(player) and waited < RANKUP_BANNER_MAX_WAIT do
		task.wait(RANKUP_BANNER_POLL)
		waited += RANKUP_BANNER_POLL
		if not Util.IsOnline(player) then
			return
		end
	end
	if Util.IsOnline(player) then
		rankUpEvent:FireClient(player, payload)
		Notify.Send(player, string.format("RANK UP! You're now a %s.", payload.Title), "gold", 5)
	end
end

-- Public API -----------------------------------------------------------------

function RepService.GetRank(player: Player): number
	local profile = Services.DataService.GetProfile(player)
	if profile and type(profile.Rank) == "number" then
		return profile.Rank
	end
	local attr = player:GetAttribute("Rank")
	return if type(attr) == "number" then attr else 1
end

-- Raw Rep add (positive or negative). Handles rank-ups and their rewards.
-- Ranks are permanent: Rep never drops below the floor of the current rank.
function RepService.AddRep(player: Player, amount: number, reason: string?): number
	local profile = Services.DataService.GetProfile(player)
	if not profile or type(amount) ~= "number" or amount ~= amount or amount == 0 then
		return 0
	end
	amount = math.floor(amount + 0.5)
	local oldRank = profile.Rank
	local before = profile.Rep
	local floor = RepMath.RankFloor(Ranks, oldRank)
	profile.Rep = math.max(floor, profile.Rep + amount)
	local gained = profile.Rep - before
	if gained > 0 and type(profile.Term) == "table" then
		profile.Term.Rep = (profile.Term.Rep or 0) + gained
	end
	local newRank = math.max(oldRank, RepMath.RankForRep(Ranks, profile.Rep))
	profile.Rank = newRank
	Services.DataService.Replicate(player, "Rep", "Rank", "Term")

	if newRank > oldRank then
		local scrolls, yen = 0, 0
		for rank = oldRank + 1, newRank do
			scrolls += Ranks.RankUpScrolls
			yen += Ranks.RankUpYenPerRank * rank
		end
		Services.DataService.AddScrolls(player, scrolls)
		Services.DataService.AddYen(player, yen, "RankUp")
		local payload = { Rank = newRank, Title = rankTitle(newRank), Scrolls = scrolls, Yen = yen }
		task.spawn(showRankUpBanner, player, payload)
		Util.Quest(Services, player, "RankUp", newRank)
		if Services.CosmeticsService and Services.CosmeticsService.Apply then
			task.spawn(Services.CosmeticsService.Apply, player)
		end
	end
	local _ = reason
	return gained
end

-- The single place fight rewards happen.
function RepService.FightResult(winner: Player, loser: Player, info: any?)
	if typeof(winner) ~= "Instance" or typeof(loser) ~= "Instance" or winner == loser then
		return
	end
	local fight = if type(info) == "table" then info else {}
	local kind = if type(fight.Kind) == "string" then fight.Kind else "Open"
	local winnerProfile = Services.DataService.GetProfile(winner)
	local loserProfile = Services.DataService.GetProfile(loser)
	local winnerRank = RepService.GetRank(winner)
	local loserRank = RepService.GetRank(loser)

	-- Winner Rep
	local repGained = 0
	if winnerProfile and kind ~= "Tournament" then
		local base = 0
		if kind == "Duel" then
			base = if type(fight.Wager) == "number" then fight.Wager else RepMath.DuelWager(Ranks, winnerRank, loserRank)
		else
			base = RepMath.OpenFightReward(Ranks, winnerRank, loserRank)
		end
		if base > 0 and not underFarmCap(winner, loser) then
			base = 0
			Notify.Send(winner, "No Rep: you've beaten this player too often this hour.", "info")
		end
		if base > 0 then
			local multiplier = 1
			local zoneService = Services.ZoneService
			local dayCycle = Services.DayCycleService
			if zoneService and dayCycle and dayCycle.IsTurfWar() then
				local zone = zoneService.GetZone(winner)
				if zone and (zone.BaseType == "Red" or zone.Type == "Red") then
					multiplier *= Ranks.AfterSchoolRedZoneMultiplier
				end
			end
			if Services.CrownService and Services.CrownService.IsCrownHolder(winner) then
				multiplier *= Ranks.CrownHolderMultiplier
			end
			if hasFriendNearby(winner) then
				multiplier *= 1 + Ranks.FriendNearbyBonus
			end
			repGained = RepService.AddRep(winner, base * multiplier, "Fight")
		end
	end

	-- Loser penalty (floored at the current rank)
	local repLost = 0
	if loserProfile and kind ~= "Tournament" then
		local before = loserProfile.Rep
		loserProfile.Rep = RepMath.ApplyLoss(Ranks, before)
		repLost = before - loserProfile.Rep
		Services.DataService.Replicate(loser, "Rep")
	end

	-- Yen
	if winnerProfile and kind ~= "Tournament" then
		Services.DataService.AddYen(winner, Combat.FightWinYen, "Fight")
	end

	-- Mastery XP
	local styleService = Services.StyleService
	if styleService then
		local winnerHits = if type(fight.WinnerHits) == "number" then fight.WinnerHits else 0
		local loserHits = if type(fight.LoserHits) == "number" then fight.LoserHits else 0
		if winnerProfile then
			local hitXP = math.min(winnerHits * Combat.MasteryXPPerHit, Combat.MasteryXPHitCapPerFight)
			styleService.AddMasteryXP(winner, Combat.MasteryXPWin + hitXP)
		end
		if loserProfile then
			local hitXP = math.min(loserHits * Combat.MasteryXPPerHit, Combat.MasteryXPHitCapPerFight)
			styleService.AddMasteryXP(loser, Combat.MasteryXPLoss + hitXP)
		end
	end

	-- Stats and quests
	if winnerProfile then
		winnerProfile.Stats.Wins += 1
		if kind == "Duel" then
			winnerProfile.Stats.DuelsWon += 1
		end
		Services.DataService.Replicate(winner, "Stats")
		Util.Quest(Services, winner, "WinFight", 1)
		if kind == "Duel" then
			Util.Quest(Services, winner, "WinDuel", 1)
		end
	end
	if loserProfile then
		loserProfile.Stats.Losses += 1
		Services.DataService.Replicate(loser, "Stats")
	end

	-- Toasts
	if winnerProfile and Util.IsOnline(winner) and kind ~= "Tournament" then
		Notify.Send(winner, string.format("You beat %s! +%d Rep, +¥%d", Util.Name(loser), repGained, Combat.FightWinYen), "good")
	end
	if loserProfile and Util.IsOnline(loser) and kind ~= "Tournament" then
		Notify.Send(loser, string.format("%s beat you. -%d Rep", Util.Name(winner), repLost), "bad")
	end
end

-- Lifecycle --------------------------------------------------------------------

local function warmFriendCache(player: Player)
	for _, other in Players:GetPlayers() do
		if other ~= player and Util.IsOnline(player) then
			areFriends(player, other)
		end
	end
end

function RepService.Init(services: any)
	Services = services
end

function RepService.Start()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(warmFriendCache, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(warmFriendCache, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local id = tostring(player.UserId)
		for key in friendCache do
			local lo, hi = string.match(key, "^(%-?%d+):(%-?%d+)$")
			if lo == id or hi == id then
				friendCache[key] = nil
			end
		end
	end)
	-- Prune old anti-farm entries every so often (they are also pruned on read).
	while true do
		task.wait(SECONDS_PER_HOUR / 4)
		local now = os.clock()
		for key, list in pairWins do
			local keep = false
			for _, t in list do
				if now - t < SECONDS_PER_HOUR then
					keep = true
					break
				end
			end
			if not keep then
				pairWins[key] = nil
			end
		end
	end
end

return RepService
