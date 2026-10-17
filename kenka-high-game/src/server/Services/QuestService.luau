--!strict
-- Rumors (quests): daily, weekly and the Transfer Arc story chain, plus the daily login streak
-- (blueprint sections 5.3 and 11).
--
--   QuestService.Progress(player, "WinFight")          -- +1
--   QuestService.Progress(player, "EarnYen", 250)      -- +250
--   QuestService.Progress(player, "RankUp", newRank)   -- story step compares against Goal + 1
--
-- Profile shape: Quests = { Day, Daily = { { Id, Progress, Claimed } }, RerollsUsed, Week, Weekly, Story = { Index, Progress } }
-- Dailies are picked deterministically per player and UTC day (QuestRoll), weeklies per UTC week.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Quests = require(ReplicatedStorage.Shared.Config.Quests)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local QuestRoll = require(ReplicatedStorage.Shared.Logic.QuestRoll)
local DayCycleMath = require(ReplicatedStorage.Shared.Logic.DayCycleMath)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local Net = require(ReplicatedStorage.Shared.Util.Net)
local RateLimiter = require(ReplicatedStorage.Shared.Util.RateLimiter)
local Notify = require(script.Parent.Parent.Systems.Notify)
local EconomyUtil = require(script.Parent.Parent.Systems.EconomyUtil)

local QuestService = {}
QuestService.Priority = 30

local Services: any

local REPLICATE_INTERVAL = 0.5 -- at most one "Quests" push per player per this many seconds
local ROLLOVER_POLL = 30 -- seconds between checks for the UTC day/week rollover while online
local LOGIN_POPUP_DELAY = 4 -- seconds after load before the login reward popup (lets the client UI boot)
local REROLL_SALT_BASE = 2 -- QuestRoll salt for rerolls = base + rerolls used (1 is the daily pick)

local limiter = RateLimiter.new(6, 2)
local lastReplicate: { [Player]: number } = {}
local replicatePending: { [Player]: boolean } = {}

local uiOpen = Net.Event("UI_Open")
local loginEvent = Net.Event("LoginReward")

type QuestDef = Quests.QuestDef

local dailyById: { [string]: QuestDef } = {}
local weeklyById: { [string]: QuestDef } = {}
for _, def in Quests.Daily do
	dailyById[def.Id] = def
end
for _, def in Quests.Weekly do
	weeklyById[def.Id] = def
end

-- Replication (throttled) ---------------------------------------------------------

local function replicateNow(player: Player)
	lastReplicate[player] = os.clock()
	replicatePending[player] = nil
	Services.DataService.Replicate(player, "Quests")
end

local function replicateQuests(player: Player)
	local last = lastReplicate[player] or 0
	local elapsed = os.clock() - last
	if elapsed >= REPLICATE_INTERVAL then
		replicateNow(player)
	elseif not replicatePending[player] then
		replicatePending[player] = true
		task.delay(REPLICATE_INTERVAL - elapsed, function()
			if replicatePending[player] and player.Parent == Players then
				replicateNow(player)
			end
		end)
	end
end

-- Rolling --------------------------------------------------------------------------

local function newEntries(ids: { string }): { any }
	local list = {}
	for _, id in ids do
		table.insert(list, { Id = id, Progress = 0, Claimed = false })
	end
	return list
end

-- Re-rolls dailies/weeklies when the UTC day/week changed. Returns true if anything changed.
local function ensureRolled(player: Player, profile: any): boolean
	local q = profile.Quests
	local nowTime = os.time()
	local today = DayCycleMath.UtcDay(nowTime)
	local week = DayCycleMath.UtcWeek(nowTime)
	local changed = false
	if q.Day ~= today or type(q.Daily) ~= "table" or #q.Daily == 0 then
		q.Day = today
		q.RerollsUsed = 0
		q.Daily = newEntries(QuestRoll.Pick(Quests.Daily :: any, Quests.DailyCount, player.UserId, today, 1))
		changed = true
	end
	if q.Week ~= week or type(q.Weekly) ~= "table" or #q.Weekly == 0 then
		q.Week = week
		q.Weekly = newEntries(QuestRoll.Pick(Quests.Weekly :: any, Quests.WeeklyCount, player.UserId, week, 1))
		changed = true
	end
	if type(q.Story) ~= "table" then
		q.Story = { Index = 1, Progress = 0 }
		changed = true
	end
	return changed
end

-- RankUp progress: Goal 2 means reaching rank 3, so progress = rank - 1.
local function applyProgress(def: QuestDef, current: number, event: string, amount: number): number
	if event == "RankUp" then
		return math.min(def.Goal, math.max(current, amount - 1))
	end
	return math.min(def.Goal, current + amount)
end

-- A story RankUp step already satisfied by the player's current rank (they ranked up earlier).
local function catchUpStory(profile: any): boolean
	local story = profile.Quests.Story
	local def = Quests.Story[story.Index]
	if def and def.Event == "RankUp" and story.Progress < def.Goal then
		local progress = applyProgress(def, story.Progress, "RankUp", profile.Rank or 1)
		if progress ~= story.Progress then
			story.Progress = progress
			return true
		end
	end
	return false
end

-- Public API ------------------------------------------------------------------------

function QuestService.Progress(player: Player, event: string, amount: number?)
	local value = amount or 1
	if type(event) ~= "string" or not EconomyUtil.IsNumber(value) or value <= 0 then
		return
	end
	local profile = Services.DataService.GetProfile(player)
	if not profile then
		return
	end
	local changed = ensureRolled(player, profile)
	local completed: { string } = {}

	local function bump(def: QuestDef?, entry: any)
		if not def or def.Event ~= event or entry.Claimed or entry.Progress >= def.Goal then
			return
		end
		local progress = applyProgress(def, entry.Progress, event, value)
		if progress ~= entry.Progress then
			entry.Progress = progress
			changed = true
			if progress >= def.Goal then
				table.insert(completed, def.Title)
			end
		end
	end

	for _, entry in profile.Quests.Daily do
		bump(dailyById[entry.Id], entry)
	end
	for _, entry in profile.Quests.Weekly do
		bump(weeklyById[entry.Id], entry)
	end
	local story = profile.Quests.Story
	bump(Quests.Story[story.Index], story)

	for _, title in completed do
		Notify.Send(player, "Rumor complete: " .. title .. "! Claim it in the Rumors app.", "gold")
	end
	if changed then
		replicateQuests(player)
	end
end

local function grant(player: Player, def: QuestDef)
	if def.Rep > 0 and Services.RepService then
		Services.RepService.AddRep(player, def.Rep, "Quest")
	end
	if def.Yen > 0 then
		Services.DataService.AddYen(player, def.Yen, "Quest")
	end
	if def.Scrolls > 0 then
		Services.DataService.AddScrolls(player, def.Scrolls)
	end
end

local function rewardText(def: QuestDef): string
	local parts = {}
	if def.Rep > 0 then
		table.insert(parts, "+" .. def.Rep .. " Rep")
	end
	if def.Yen > 0 then
		table.insert(parts, "+" .. Format.Yen(def.Yen))
	end
	if def.Scrolls > 0 then
		table.insert(parts, "+" .. def.Scrolls .. " scrolls")
	end
	return table.concat(parts, " · ")
end

local function onClaim(player: Player, questId: any): (boolean, string)
	if not limiter:Allow(player) then
		return false, "Slow down."
	end
	if not EconomyUtil.IsShortString(questId, 32) then
		return false, "Invalid rumor."
	end
	local profile = Services.DataService.GetProfile(player)
	if not profile then
		return false, "Your data is still loading."
	end
	ensureRolled(player, profile)
	local q = profile.Quests

	for _, pair in { { q.Daily, dailyById }, { q.Weekly, weeklyById } } do
		local list, lookup = pair[1] :: { any }, pair[2] :: { [string]: QuestDef }
		for _, entry in list do
			if entry.Id == questId then
				local def = lookup[entry.Id]
				if not def then
					return false, "That rumor no longer exists."
				end
				if entry.Claimed then
					return false, "Already claimed."
				end
				if entry.Progress < def.Goal then
					return false, "Not finished yet."
				end
				entry.Claimed = true
				replicateNow(player)
				grant(player, def)
				return true, "Claimed: " .. rewardText(def)
			end
		end
	end

	local story = q.Story
	local def = Quests.Story[story.Index]
	if def and def.Id == questId then
		if story.Progress < def.Goal then
			return false, "Not finished yet."
		end
		story.Index += 1
		story.Progress = 0
		catchUpStory(profile)
		replicateNow(player)
		grant(player, def)
		return true, "Story claimed: " .. rewardText(def)
	end
	return false, "That rumor isn't on your board."
end

local function rerollsAllowed(player: Player): number
	local allowed = Quests.DailyRerollsFree
	if Services.MonetizationService and Services.MonetizationService.OwnsPass(player, "VIP") then
		allowed += 1
	end
	return allowed
end

local function onReroll(player: Player, questId: any): (boolean, string)
	if not limiter:Allow(player) then
		return false, "Slow down."
	end
	if not EconomyUtil.IsShortString(questId, 32) then
		return false, "Invalid rumor."
	end
	local profile = Services.DataService.GetProfile(player)
	if not profile then
		return false, "Your data is still loading."
	end
	ensureRolled(player, profile)
	local q = profile.Quests
	local allowed = rerollsAllowed(player)
	if q.RerollsUsed >= allowed then
		return false, "No rerolls left today."
	end
	local index: number? = nil
	local exclude: { [string]: boolean } = {}
	for i, entry in q.Daily do
		exclude[entry.Id] = true
		if entry.Id == questId and not entry.Claimed then
			index = i
		end
	end
	if not index then
		return false, "You can only reroll an unclaimed daily rumor."
	end
	local picked = QuestRoll.Pick(Quests.Daily :: any, 1, player.UserId, q.Day, REROLL_SALT_BASE + q.RerollsUsed, exclude)
	if #picked == 0 then
		return false, "No other rumors available."
	end
	q.Daily[index] = { Id = picked[1], Progress = 0, Claimed = false }
	q.RerollsUsed += 1
	replicateNow(player)
	local def = dailyById[picked[1]]
	return true, "New rumor: " .. (if def then def.Title else picked[1])
end

-- Login streak -------------------------------------------------------------------------

local function checkLogin(player: Player, profile: any, delayPopup: boolean)
	local today = DayCycleMath.UtcDay(os.time())
	local login = profile.Login
	if login.LastDay == today then
		return
	end
	if login.LastDay == today - 1 then
		login.Streak += 1
	else
		login.Streak = 1
	end
	login.LastDay = today

	local day = ((login.Streak - 1) % #Economy.LoginRewards) + 1
	local reward = Economy.LoginRewards[day] :: any
	if reward.Yen then
		Services.DataService.AddYen(player, reward.Yen, "Login")
	end
	if reward.Scrolls then
		Services.DataService.AddScrolls(player, reward.Scrolls)
	end
	if reward.CapsuleTokens then
		profile.Capsule.Tokens += reward.CapsuleTokens
	end
	if reward.Badge then
		profile.Badges[reward.Badge] = true
	end
	Services.DataService.Replicate(player, "Login", "Capsule", "Badges")

	local payload = { Day = day, Streak = login.Streak, Reward = reward }
	local function fire()
		if player.Parent == Players then
			loginEvent:FireClient(player, payload)
		end
	end
	if delayPopup then
		task.delay(LOGIN_POPUP_DELAY, fire)
	else
		fire()
	end
end

local function onProfileLoaded(player: Player, profile: any)
	ensureRolled(player, profile)
	catchUpStory(profile)
	replicateNow(player)
	checkLogin(player, profile, true)
end

-- Lifecycle ----------------------------------------------------------------------------

function QuestService.Init(services: any)
	Services = services
	Net.Function("Quest_Claim").OnServerInvoke = onClaim
	Net.Function("Quest_Reroll").OnServerInvoke = onReroll
	Services.InteractionService.Register("RumorBoard", function(player: Player)
		uiOpen:FireClient(player, "Rumors")
	end)
end

function QuestService.Start()
	Services.DataService.ProfileLoaded:Connect(onProfileLoaded)
	for _, player in Players:GetPlayers() do
		local profile = Services.DataService.GetProfile(player)
		if profile then
			task.spawn(onProfileLoaded, player, profile)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		lastReplicate[player] = nil
		replicatePending[player] = nil
		limiter:Remove(player)
	end)

	-- UTC midnight / Monday rollover while players stay online.
	while true do
		task.wait(ROLLOVER_POLL)
		for _, player in Players:GetPlayers() do
			local profile = Services.DataService.GetProfile(player)
			if profile then
				if ensureRolled(player, profile) then
					replicateNow(player)
				end
				checkLogin(player, profile, false)
			end
		end
	end
end

return QuestService
