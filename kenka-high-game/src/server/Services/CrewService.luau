--!strict
-- Crews (blueprint 1.10, 5.5, 7.3 and the crew rows of section 8).
--
-- Storage: Game.CrewStoreName, key "crew_<id>", record:
--   { Id, Name, Color (index into Crews.Colors), Emblem (index into Crews.Emblems), Leader (userId),
--     Members = { [tostring(userId)] = "Leader"|"Lieutenant"|"Member" }, Names = { [tostring(userId)] = displayName },
--     Joined = { [tostring(userId)] = unix time }, MaxMembers, WeeklyRep, WeekNumber, TotalCaptures, Created, Banner? }
--   A disbanded crew is overwritten with a tombstone { Id, Name, Disbanded = true }.
-- Name index: Game.CrewNameStoreName, key = lowercase name -> crew id ("" = free). Claimed with UpdateAsync.
-- Every write goes through UpdateAsync (CrewStore) with retries; the transform re-checks roles on fresh data,
-- so two servers can't overwrite each other.
--
-- Cache: records of crews with members online here, refreshed on every action and every 60 s. A member
-- kicked (or a crew disbanded) on another server is cleared here on the next refresh or on join.
-- Invites and join requests are per server and in memory (both players must be in this server).

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Crews = require(ReplicatedStorage.Shared.Config.Crews)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local GameConfig = require(ReplicatedStorage.Shared.Config.Game)
local DayCycleMath = require(ReplicatedStorage.Shared.Logic.DayCycleMath)
local Net = require(ReplicatedStorage.Shared.Util.Net)
local RateLimiter = require(ReplicatedStorage.Shared.Util.RateLimiter)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Notify = require(script.Parent.Parent.Systems.Notify)
local CrewStore = require(script.Parent.Parent.Systems.CrewStore)
local CrewHQ = require(script.Parent.Parent.Systems.CrewHQ)

local CrewService = {}
CrewService.Priority = 40

CrewService.CrewChanged = Signal.new() -- (player, crewId?)
CrewService.CrewDisbanded = Signal.new() -- (crewId)

local REFRESH_INTERVAL = 60 -- re-read crews of online members (other servers may have changed them)
local REQUEST_TIMEOUT = 300 -- join requests expire after 5 minutes
local MAX_REQUESTS = 20 -- pending join requests kept per crew
local GONE = "That crew no longer exists."
local BUSY = "Crew data is busy. Try again in a moment."
local ROLE_RANK = { Leader = 3, Lieutenant = 2, Member = 1 }

type Invite = { Expires: number, FromUserId: number, FromName: string, CrewName: string }
type Request = { Name: string, Expires: number }

local Services: any
local crews: { [string]: any } = {} -- crewId -> record (live only)
local playerCrew: { [Player]: string } = {}
local invites: { [number]: { [string]: Invite } } = {} -- target userId -> crewId -> invite
local requests: { [string]: { [number]: Request } } = {} -- crewId -> requester userId -> request
local busy: { [Player]: boolean } = {}
local actionLimiter = RateLimiter.new(1, 1)
local readLimiter = RateLimiter.new(3, 1)
local crewUpdate = Net.Event("Crew_Update")
local crewInvite = Net.Event("Crew_Invite")

-- Helpers -------------------------------------------------------------------------

local function key(userId: number): string
	return tostring(userId)
end

local function crewKey(crewId: string): string
	return "crew_" .. crewId
end

local function nameKey(name: string): string
	return string.lower(name)
end

local function currentWeek(): number
	return DayCycleMath.UtcWeek(os.time())
end

local function isLive(record: any): boolean
	return type(record) == "table" and not record.Disbanded and type(record.Members) == "table"
end

local function memberCount(record: any): number
	local n = 0
	for _ in record.Members do
		n += 1
	end
	return n
end

local function capacity(record: any): number
	return math.min(tonumber(record.MaxMembers) or Crews.MaxMembers, Crews.MaxMembers)
end

local function colorHex(record: any): string
	return Crews.Colors[record.Color] or Crews.Colors[1]
end

local function glyph(record: any): string
	return Crews.Emblems[record.Emblem] or Crews.Emblems[1]
end

local function getRank(player: Player): number
	local rep = Services.RepService
	if rep and rep.GetRank then
		local ok, rank = pcall(rep.GetRank, player)
		if ok and type(rank) == "number" then
			return rank
		end
	end
	local attr = player:GetAttribute("Rank")
	return if type(attr) == "number" then attr else 1
end

local function quest(player: Player, event: string)
	local questService = Services.QuestService
	if questService and questService.Progress then
		task.spawn(questService.Progress, player, event)
	end
end

local function ownsPlus(player: Player): boolean
	local monetization = Services.MonetizationService
	if monetization and monetization.OwnsPass then
		local ok, owns = pcall(monetization.OwnsPass, player, "CrewPlus")
		return ok and owns == true
	end
	return false
end

local function onlineMembers(crewId: string): { Player }
	local list = {}
	for player, id in playerCrew do
		if id == crewId and player.Parent == Players then
			table.insert(list, player)
		end
	end
	return list
end

local function officersOnline(crewId: string): { Player }
	local list = {}
	local record = crews[crewId]
	if not isLive(record) then
		return list
	end
	for _, player in onlineMembers(crewId) do
		local role = record.Members[key(player.UserId)]
		if role == "Leader" or role == "Lieutenant" then
			table.insert(list, player)
		end
	end
	return list
end

local function cleanName(raw: string): string
	local trimmed = raw:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
	return trimmed
end

local function newCrewId(): string
	local guid = HttpService:GenerateGUID(false):gsub("%-", "")
	return "c_" .. string.lower(string.sub(guid, 1, 10))
end

-- Removes a member from a record and hands leadership on if needed. Returns true if the crew is now empty.
local function removeFromRecord(record: any, memberKey: string): boolean
	local wasLeader = record.Members[memberKey] == "Leader"
	record.Members[memberKey] = nil
	if type(record.Names) == "table" then
		record.Names[memberKey] = nil
	end
	if type(record.Joined) == "table" then
		record.Joined[memberKey] = nil
	end
	if next(record.Members) == nil then
		return true
	end
	if wasLeader then
		-- The oldest Lieutenant, otherwise the oldest member.
		local bestKey: string? = nil
		local bestScore, bestTime = -1, math.huge
		for k, role in record.Members do
			local score = if role == "Lieutenant" then 1 else 0
			local joined = (type(record.Joined) == "table" and record.Joined[k]) or record.Created or 0
			if score > bestScore or (score == bestScore and joined < bestTime) then
				bestKey, bestScore, bestTime = k, score, joined
			end
		end
		if bestKey then
			record.Members[bestKey] = "Leader"
			record.Leader = tonumber(bestKey)
		end
	end
	return false
end

local function tombstone(record: any)
	for k in record do
		if k ~= "Id" and k ~= "Name" then
			record[k] = nil
		end
	end
	record.Disbanded = true
end

-- Runs fn on the freshest copy of the record inside UpdateAsync. fn mutates it in place and returns an
-- error message to cancel. Returns ok, message?. The message is GONE when the crew doesn't exist.
local function mutateCrew(crewId: string, fn: (record: any) -> string?): (boolean, string?)
	local failure: string? = nil
	local ok, result = CrewStore.Update(GameConfig.CrewStoreName, crewKey(crewId), function(old: any)
		failure = nil
		if not isLive(old) then
			failure = GONE
			return nil
		end
		if old.WeekNumber ~= currentWeek() then
			old.WeekNumber = currentWeek()
			old.WeeklyRep = 0
		end
		local message = fn(old)
		if message then
			failure = message
			return nil
		end
		return old
	end)
	if not ok then
		return false, BUSY
	end
	if failure then
		if failure == GONE then
			crews[crewId] = nil
		end
		return false, failure
	end
	if isLive(result) then
		crews[crewId] = result
	else
		crews[crewId] = nil
	end
	return true, nil
end

-- Reads the record from the store. Returns ok (the read worked), record? (nil = no such crew).
local function loadCrew(crewId: string): (boolean, any)
	local ok, value = CrewStore.Get(GameConfig.CrewStoreName, crewKey(crewId))
	if not ok then
		return false, nil
	end
	if isLive(value) then
		crews[crewId] = value
		return true, value
	end
	crews[crewId] = nil
	return true, nil
end

local function buildSummary(crewId: string, viewer: Player?): any?
	local record = crews[crewId]
	if not isLive(record) then
		return nil
	end
	local members = {}
	for k, role in record.Members do
		local userId = tonumber(k)
		if userId then
			local name = (type(record.Names) == "table" and record.Names[k]) or ("User " .. k)
			table.insert(members, {
				UserId = userId,
				Name = name,
				Role = role,
				Online = Players:GetPlayerByUserId(userId) ~= nil,
			})
		end
	end
	table.sort(members, function(a, b)
		local ra, rb = ROLE_RANK[a.Role] or 0, ROLE_RANK[b.Role] or 0
		if ra ~= rb then
			return ra > rb
		end
		if a.Online ~= b.Online then
			return a.Online
		end
		return string.lower(a.Name) < string.lower(b.Name)
	end)

	local turfs = {}
	local turfService = Services.TurfService
	if turfService and turfService.GetTurfsHeld then
		local ok, held = pcall(turfService.GetTurfsHeld, crewId)
		if ok and type(held) == "table" then
			turfs = held
		end
	end

	local myRole = if viewer then record.Members[key(viewer.UserId)] else nil
	local summary: any = {
		Id = record.Id,
		Name = record.Name,
		Color = colorHex(record),
		Emblem = glyph(record),
		ColorIndex = record.Color,
		EmblemIndex = record.Emblem,
		Leader = record.Leader,
		MyRole = myRole,
		Members = members,
		MaxMembers = capacity(record),
		WeeklyRep = if record.WeekNumber == currentWeek() then record.WeeklyRep or 0 else 0,
		TotalCaptures = record.TotalCaptures or 0,
		TurfsHeld = turfs,
	}
	if myRole == "Leader" or myRole == "Lieutenant" then
		local list = {}
		local now = os.clock()
		local pending: { [number]: Request } = requests[crewId] or {}
		for userId, request in pending do
			if request.Expires > now and Players:GetPlayerByUserId(userId) then
				table.insert(list, { UserId = userId, Name = request.Name })
			end
		end
		summary.Requests = list
	end
	return summary
end

local function hqInfo(crewId: string): CrewHQ.Info?
	local summary = buildSummary(crewId, nil)
	local record = crews[crewId]
	if not summary or not record then
		return nil
	end
	local banner = record.Banner == true
	local leader = if type(record.Leader) == "number" then Players:GetPlayerByUserId(record.Leader) else nil
	if leader then
		banner = ownsPlus(leader)
	end
	return {
		Name = summary.Name,
		ColorHex = summary.Color,
		Glyph = summary.Emblem,
		Banner = banner,
		Roster = summary.Members,
	}
end

local function broadcast(crewId: string)
	for _, player in onlineMembers(crewId) do
		crewUpdate:FireClient(player, buildSummary(crewId, player))
	end
	if CrewHQ.IsBuilt(crewId) then
		local info = hqInfo(crewId)
		if info then
			CrewHQ.UpdateInfo(crewId, info)
		end
	end
end

local function setDisplay(player: Player, record: any?)
	if record and isLive(record) then
		player:SetAttribute("CrewName", record.Name)
		player:SetAttribute("CrewColor", colorHex(record))
		player:SetAttribute("CrewEmblem", glyph(record))
	else
		player:SetAttribute("CrewName", nil)
		player:SetAttribute("CrewColor", nil)
		player:SetAttribute("CrewEmblem", nil)
	end
end

-- Points a player at a crew (or none): cache, profile.CrewId, attributes, signal and their Crew_Update.
local function applyMembership(player: Player, crewId: string?)
	local record = if crewId then crews[crewId] else nil
	local newId: string? = if crewId and isLive(record) then crewId else nil
	local old = playerCrew[player]
	if newId then
		playerCrew[player] = newId
	else
		playerCrew[player] = nil
	end
	setDisplay(player, if newId then record else nil)

	local profile = Services.DataService.GetProfile(player)
	if profile and profile.CrewId ~= (newId or "") then
		profile.CrewId = newId or ""
		Services.DataService.Replicate(player, "CrewId")
	end
	if not newId then
		CrewHQ.Eject(player)
	end
	if old ~= newId then
		CrewService.CrewChanged:Fire(player, newId)
	end
	crewUpdate:FireClient(player, if newId then buildSummary(newId, player) else nil)
end

-- After a fresh read: drop members who are no longer listed, refresh everyone else.
local function reconcileCrew(crewId: string)
	local record = crews[crewId]
	for _, player in onlineMembers(crewId) do
		if not isLive(record) or record.Members[key(player.UserId)] == nil then
			applyMembership(player, nil)
			Notify.Send(player, if isLive(record) then "You were removed from your crew." else "Your crew was disbanded.", "crew")
		else
			setDisplay(player, record)
		end
	end
	if isLive(record) then
		broadcast(crewId)
	end
end

local function clearPendingFor(userId: number)
	invites[userId] = nil
	for _, list in requests do
		list[userId] = nil
	end
end

local function finishDisband(crewId: string, crewName: string?)
	if type(crewName) == "string" then
		local name = crewName
		task.spawn(function()
			CrewStore.Update(GameConfig.CrewNameStoreName, nameKey(name), function(old: any)
				return if old == crewId then "" else nil
			end)
		end)
	end
	crews[crewId] = nil
	requests[crewId] = nil
	for _, list in invites do
		list[crewId] = nil
	end
	for _, player in onlineMembers(crewId) do
		applyMembership(player, nil)
		Notify.Send(player, "Your crew was disbanded.", "crew")
	end
	CrewHQ.Remove(crewId)
	CrewService.CrewDisbanded:Fire(crewId)
end

-- Adds a player (online in this server) to a crew as a Member.
local function joinCrew(player: Player, crewId: string): (boolean, string)
	local profile = Services.DataService.GetProfile(player)
	if not profile then
		return false, "Data is still loading."
	end
	if playerCrew[player] or (profile.CrewId ~= nil and profile.CrewId ~= "") then
		return false, "Already in a crew."
	end
	if getRank(player) < Crews.MinRank then
		return false, string.format("Crews unlock at Rank %d.", Crews.MinRank)
	end
	local k = key(player.UserId)
	local ok, err = mutateCrew(crewId, function(record)
		if record.Members[k] then
			return nil
		end
		local max = capacity(record)
		if memberCount(record) >= max then
			return string.format("Crew full (%d/%d).", max, max)
		end
		record.Members[k] = "Member"
		record.Names = if type(record.Names) == "table" then record.Names else {}
		record.Names[k] = player.DisplayName
		record.Joined = if type(record.Joined) == "table" then record.Joined else {}
		record.Joined[k] = os.time()
		return nil
	end)
	if not ok then
		return false, err or BUSY
	end
	if player.Parent ~= Players then
		-- They left during the write; their profile is gone, so undo the membership.
		task.spawn(mutateCrew, crewId, function(record)
			if record.Members[k] and memberCount(record) > 1 then
				removeFromRecord(record, k)
			end
			return nil
		end)
		return false, "Player left."
	end
	clearPendingFor(player.UserId)
	applyMembership(player, crewId)
	broadcast(crewId)
	local record = crews[crewId]
	local crewName = if record then record.Name else "the crew"
	for _, member in onlineMembers(crewId) do
		if member ~= player then
			Notify.Send(member, player.DisplayName .. " joined the crew!", "crew")
		end
	end
	Notify.Send(player, "Welcome to " .. crewName .. "!", "crew")
	quest(player, "JoinCrew")
	task.spawn(Services.DataService.SaveNow, player)
	return true, "Welcome to " .. crewName .. "!"
end

-- Actions ---------------------------------------------------------------------------

local function actionCreate(player: Player, args: any): (boolean, any)
	local profile = Services.DataService.GetProfile(player)
	if not profile then
		return false, "Data is still loading."
	end
	if playerCrew[player] or (profile.CrewId ~= nil and profile.CrewId ~= "") then
		return false, "Leave your crew first."
	end
	if getRank(player) < Crews.MinRank then
		return false, string.format("Crews unlock at Rank %d.", Crews.MinRank)
	end
	if type(args.Name) ~= "string" or #args.Name > 64 then
		return false, "Enter a crew name."
	end
	local name = cleanName(args.Name)
	local length = utf8.len(name) or #name
	if length < Crews.NameMin or length > Crews.NameMax then
		return false, string.format("Names are %d to %d characters.", Crews.NameMin, Crews.NameMax)
	end
	if not name:match("^[%w %-_']+$") then
		return false, "Use letters, numbers, spaces, - _ and ' only."
	end
	local color, emblem = args.Color, args.Emblem
	if type(color) ~= "number" or color ~= math.floor(color) or color < 1 or color > #Crews.Colors then
		return false, "Pick a color."
	end
	if type(emblem) ~= "number" or emblem ~= math.floor(emblem) or emblem < 1 or emblem > #Crews.Emblems then
		return false, "Pick an emblem."
	end
	local cost = Economy.CrewCreateCost
	if profile.Yen < cost then
		return false, string.format("Need ¥%d more.", cost - profile.Yen)
	end

	local filterOk, filtered = pcall(function()
		local result = TextService:FilterStringAsync(name, player.UserId)
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not filterOk then
		return false, "Couldn't check that name right now. Try again."
	end
	if filtered ~= name then
		return false, "That name isn't allowed."
	end
	if player.Parent ~= Players then
		return false, "Player left."
	end
	if not Services.DataService.SpendYen(player, cost) then
		return false, string.format("You need ¥%d.", cost)
	end
	local function refund()
		Services.DataService.Update(player, { "Yen" }, function(p: any)
			p.Yen += cost
		end)
	end

	local crewId = newCrewId()
	local claimed = false
	local claimOk = CrewStore.Update(GameConfig.CrewNameStoreName, nameKey(name), function(old: any)
		claimed = false
		if old == nil or old == "" then
			claimed = true
			return crewId
		end
		return nil
	end)
	if not claimOk or not claimed then
		refund()
		return false, if claimOk then "That crew name is taken." else BUSY
	end

	local k = key(player.UserId)
	local now = os.time()
	local record = {
		Id = crewId,
		Name = name,
		Color = color,
		Emblem = emblem,
		Leader = player.UserId,
		Members = { [k] = "Leader" },
		Names = { [k] = player.DisplayName },
		Joined = { [k] = now },
		MaxMembers = Crews.MaxMembers,
		WeeklyRep = 0,
		WeekNumber = currentWeek(),
		TotalCaptures = 0,
		Created = now,
		Banner = ownsPlus(player),
	}
	local created = false
	local writeOk, stored = CrewStore.Update(GameConfig.CrewStoreName, crewKey(crewId), function(old: any)
		created = false
		if old ~= nil then
			return nil
		end
		created = true
		return record
	end)
	if not writeOk or not created then
		CrewStore.Update(GameConfig.CrewNameStoreName, nameKey(name), function(old: any)
			return if old == crewId then "" else nil
		end)
		refund()
		return false, BUSY
	end
	crews[crewId] = if isLive(stored) then stored else record

	if player.Parent ~= Players then
		-- Left mid-create: the profile can't point at the crew any more, so don't leave an orphan behind.
		task.spawn(function()
			mutateCrew(crewId, function(r)
				tombstone(r)
				return nil
			end)
			finishDisband(crewId, name)
		end)
		return false, "Player left."
	end

	clearPendingFor(player.UserId)
	applyMembership(player, crewId)
	quest(player, "JoinCrew")
	task.spawn(Services.DataService.SaveNow, player)
	Notify.Send(player, string.format("Crew %s %s created!", glyph(record), name), "crew")
	return true, buildSummary(crewId, player)
end

local function actionInvite(player: Player, args: any): (boolean, any)
	local crewId = playerCrew[player]
	if not crewId then
		return false, "You're not in a crew."
	end
	if type(args.UserId) ~= "number" then
		return false, "Pick a player."
	end
	local target = Players:GetPlayerByUserId(args.UserId)
	if not target or target == player then
		return false, "That player isn't in this server."
	end
	local targetProfile = Services.DataService.GetProfile(target)
	if playerCrew[target] or not targetProfile or (targetProfile.CrewId ~= nil and targetProfile.CrewId ~= "") then
		return false, target.DisplayName .. " is already in a crew."
	end
	if getRank(target) < Crews.MinRank then
		return false, string.format("%s needs Rank %d to join a crew.", target.DisplayName, Crews.MinRank)
	end
	local ok, record = loadCrew(crewId)
	if not ok then
		return false, BUSY
	end
	if not record then
		finishDisband(crewId, nil)
		return false, GONE
	end
	local role = record.Members[key(player.UserId)]
	if role ~= "Leader" and role ~= "Lieutenant" then
		reconcileCrew(crewId)
		return false, "Only the leader and lieutenants can invite."
	end
	local max = capacity(record)
	if memberCount(record) >= max then
		return false, string.format("Crew full (%d/%d).", max, max)
	end
	local pending = invites[target.UserId]
	local existing = pending and pending[crewId]
	if existing and existing.Expires > os.clock() then
		return false, "Already invited. Waiting for an answer."
	end
	local list = pending or {}
	invites[target.UserId] = list
	list[crewId] = {
		Expires = os.clock() + Crews.InviteTimeout,
		FromUserId = player.UserId,
		FromName = player.DisplayName,
		CrewName = record.Name,
	}
	crewInvite:FireClient(target, {
		CrewId = crewId,
		CrewName = record.Name,
		FromName = player.DisplayName,
		Color = colorHex(record),
		Emblem = glyph(record),
		ExpiresIn = Crews.InviteTimeout,
	})
	return true, "Invite sent to " .. target.DisplayName .. "."
end

local function actionRespondInvite(player: Player, args: any): (boolean, any)
	if type(args.CrewId) ~= "string" or type(args.Accept) ~= "boolean" then
		return false, "Bad request."
	end
	local list = invites[player.UserId]
	local invite = list and list[args.CrewId]
	if not list or not invite then
		return false, "That invite expired."
	end
	list[args.CrewId] = nil
	if invite.Expires < os.clock() then
		return false, "That invite expired."
	end
	local inviter = Players:GetPlayerByUserId(invite.FromUserId)
	if not args.Accept then
		if inviter then
			Notify.Send(inviter, player.DisplayName .. " declined the crew invite.", "crew")
		end
		return true, "Invite declined."
	end
	return joinCrew(player, args.CrewId)
end

local function actionRequestJoin(player: Player, args: any): (boolean, any)
	if type(args.CrewId) ~= "string" or #args.CrewId > 32 then
		return false, "Bad request."
	end
	local crewId = args.CrewId
	local profile = Services.DataService.GetProfile(player)
	if playerCrew[player] or not profile or (profile.CrewId ~= nil and profile.CrewId ~= "") then
		return false, "Leave your crew first."
	end
	if getRank(player) < Crews.MinRank then
		return false, string.format("Crews unlock at Rank %d.", Crews.MinRank)
	end
	if #onlineMembers(crewId) == 0 then
		return false, "Nobody from that crew is in this server."
	end
	local ok, record = loadCrew(crewId)
	if not ok then
		return false, BUSY
	end
	if not record then
		finishDisband(crewId, nil)
		return false, GONE
	end
	local max = capacity(record)
	if memberCount(record) >= max then
		return false, string.format("Crew full (%d/%d).", max, max)
	end
	local list: { [number]: Request } = requests[crewId] or {}
	requests[crewId] = list
	local now = os.clock()
	local count = 0
	for userId, request in list do
		if request.Expires <= now then
			list[userId] = nil
		else
			count += 1
		end
	end
	if list[player.UserId] then
		return false, "Request already sent."
	end
	if count >= MAX_REQUESTS then
		return false, "That crew has too many pending requests."
	end
	list[player.UserId] = { Name = player.DisplayName, Expires = now + REQUEST_TIMEOUT }
	Notify.Many(officersOnline(crewId), player.DisplayName .. " wants to join the crew. Open the Crew app.", "crew")
	broadcast(crewId)
	return true, "Request sent to " .. record.Name .. "."
end

local function actionAcceptRequest(player: Player, args: any): (boolean, any)
	local crewId = playerCrew[player]
	if not crewId then
		return false, "You're not in a crew."
	end
	if type(args.UserId) ~= "number" then
		return false, "Bad request."
	end
	local list = requests[crewId]
	local request = list and list[args.UserId]
	if not list or not request or request.Expires < os.clock() then
		if list then
			list[args.UserId] = nil
		end
		broadcast(crewId)
		return false, "That request expired."
	end
	local ok, record = loadCrew(crewId)
	if not ok then
		return false, BUSY
	end
	if not record then
		finishDisband(crewId, nil)
		return false, GONE
	end
	local role = record.Members[key(player.UserId)]
	if role ~= "Leader" and role ~= "Lieutenant" then
		reconcileCrew(crewId)
		return false, "Only the leader and lieutenants can accept requests."
	end
	local target = Players:GetPlayerByUserId(args.UserId)
	if not target then
		list[args.UserId] = nil
		broadcast(crewId)
		return false, "That player left the server."
	end
	local joined, message = joinCrew(target, crewId)
	list[args.UserId] = nil
	if joined then
		return true, target.DisplayName .. " joined the crew."
	end
	broadcast(crewId)
	return false, message
end

local function actionLeave(player: Player): (boolean, any)
	local crewId = playerCrew[player]
	if not crewId then
		return false, "You're not in a crew."
	end
	local k = key(player.UserId)
	local disbanded = false
	local crewName: string? = nil
	local newLeader: string? = nil
	local ok, err = mutateCrew(crewId, function(record)
		disbanded, newLeader = false, nil
		crewName = record.Name
		if not record.Members[k] then
			return nil
		end
		local wasLeader = record.Members[k] == "Leader"
		if removeFromRecord(record, k) then
			disbanded = true
			tombstone(record)
		elseif wasLeader and type(record.Names) == "table" then
			newLeader = record.Names[key(record.Leader)]
		end
		return nil
	end)
	if not ok and err ~= GONE then
		return false, err
	end
	applyMembership(player, nil)
	if disbanded or err == GONE then
		finishDisband(crewId, crewName)
		return true, "You left. The crew has disbanded."
	end
	for _, member in onlineMembers(crewId) do
		Notify.Send(member, player.DisplayName .. " left the crew." .. (if newLeader then " " .. newLeader .. " is the new leader." else ""), "crew")
	end
	broadcast(crewId)
	return true, "You left the crew."
end

local function actionKick(player: Player, args: any): (boolean, any)
	local crewId = playerCrew[player]
	if not crewId then
		return false, "You're not in a crew."
	end
	if type(args.UserId) ~= "number" or args.UserId == player.UserId then
		return false, "Pick a member."
	end
	local actorKey, targetKey = key(player.UserId), key(args.UserId)
	local targetName = "They"
	local ok, err = mutateCrew(crewId, function(record)
		local actorRole, targetRole = record.Members[actorKey], record.Members[targetKey]
		if not actorRole then
			return "You're not in this crew."
		end
		if not targetRole then
			return "They aren't in your crew."
		end
		if actorRole == "Member" or (ROLE_RANK[actorRole] or 0) <= (ROLE_RANK[targetRole] or 0) then
			return "You can't kick them."
		end
		targetName = (type(record.Names) == "table" and record.Names[targetKey]) or targetName
		removeFromRecord(record, targetKey)
		return nil
	end)
	if not ok then
		if err == GONE then
			finishDisband(crewId, nil)
		else
			reconcileCrew(crewId)
		end
		return false, err
	end
	local target = Players:GetPlayerByUserId(args.UserId)
	if target and playerCrew[target] == crewId then
		applyMembership(target, nil)
		Notify.Send(target, "You were kicked from the crew.", "bad")
	end
	broadcast(crewId)
	return true, targetName .. " was kicked."
end

local function actionPromote(player: Player, args: any, promote: boolean): (boolean, any)
	local crewId = playerCrew[player]
	if not crewId then
		return false, "You're not in a crew."
	end
	if type(args.UserId) ~= "number" or args.UserId == player.UserId then
		return false, "Pick a member."
	end
	local actorKey, targetKey = key(player.UserId), key(args.UserId)
	local result = ""
	local ok, err = mutateCrew(crewId, function(record)
		local actorRole, targetRole = record.Members[actorKey], record.Members[targetKey]
		if actorRole ~= "Leader" then
			return "Only the leader can change roles."
		end
		if not targetRole then
			return "They aren't in your crew."
		end
		local name = (type(record.Names) == "table" and record.Names[targetKey]) or "They"
		if promote then
			if targetRole == "Member" then
				record.Members[targetKey] = "Lieutenant"
				result = name .. " is now a Lieutenant."
			elseif targetRole == "Lieutenant" then
				-- Promoting a Lieutenant hands over leadership.
				record.Members[targetKey] = "Leader"
				record.Members[actorKey] = "Lieutenant"
				record.Leader = args.UserId
				result = name .. " is the new leader."
			else
				return "They can't be promoted."
			end
		else
			if targetRole ~= "Lieutenant" then
				return "Only lieutenants can be demoted."
			end
			record.Members[targetKey] = "Member"
			result = name .. " is now a Member."
		end
		return nil
	end)
	if not ok then
		if err == GONE then
			finishDisband(crewId, nil)
		else
			reconcileCrew(crewId)
		end
		return false, err
	end
	Notify.Many(onlineMembers(crewId), result, "crew")
	broadcast(crewId)
	return true, result
end

local function actionDisband(player: Player): (boolean, any)
	local crewId = playerCrew[player]
	if not crewId then
		return false, "You're not in a crew."
	end
	local k = key(player.UserId)
	local crewName: string? = nil
	local ok, err = mutateCrew(crewId, function(record)
		if record.Members[k] ~= "Leader" then
			return "Only the leader can disband the crew."
		end
		crewName = record.Name
		tombstone(record)
		return nil
	end)
	if not ok and err ~= GONE then
		reconcileCrew(crewId)
		return false, err
	end
	finishDisband(crewId, crewName)
	return true, "The crew has disbanded."
end

local function actionInfo(player: Player): (boolean, any)
	local crewId = playerCrew[player]
	if not crewId then
		return true, nil
	end
	local ok, record = loadCrew(crewId)
	if ok then
		if record then
			reconcileCrew(crewId)
		else
			finishDisband(crewId, nil)
		end
	end
	local current = playerCrew[player]
	return true, if current then buildSummary(current, player) else nil
end

local function actionListServer(): (boolean, any)
	local seen = {}
	local list = {}
	for player, crewId in playerCrew do
		local record = crews[crewId]
		if player.Parent == Players and not seen[crewId] and isLive(record) then
			seen[crewId] = true
			local count = memberCount(record)
			table.insert(list, {
				Id = crewId,
				Name = record.Name,
				Color = colorHex(record),
				Emblem = glyph(record),
				Members = count,
				MaxMembers = capacity(record),
				Online = #onlineMembers(crewId),
				Full = count >= capacity(record),
			})
		end
	end
	table.sort(list, function(a, b)
		return a.Online > b.Online
	end)
	return true, list
end

local MUTATING = {
	Create = actionCreate,
	Invite = actionInvite,
	RespondInvite = actionRespondInvite,
	RequestJoin = actionRequestJoin,
	AcceptRequest = actionAcceptRequest,
	Kick = actionKick,
	Promote = function(player: Player, args: any)
		return actionPromote(player, args, true)
	end,
	Demote = function(player: Player, args: any)
		return actionPromote(player, args, false)
	end,
	Leave = function(player: Player, _args: any)
		return actionLeave(player)
	end,
	Disband = function(player: Player, _args: any)
		return actionDisband(player)
	end,
} :: { [string]: (Player, any) -> (boolean, any) }

local function onAction(player: Player, action: any, args: any): (boolean, any)
	if type(action) ~= "string" then
		return false, "Bad request."
	end
	if args ~= nil and type(args) ~= "table" then
		return false, "Bad request."
	end
	local safeArgs = args or {}
	if action == "Info" or action == "ListServer" then
		if not readLimiter:Allow(player) then
			return false, "Slow down."
		end
		if action == "Info" then
			return actionInfo(player)
		end
		return actionListServer()
	end
	local handler = MUTATING[action]
	if not handler then
		return false, "Unknown action."
	end
	if not actionLimiter:Allow(player) then
		return false, "Slow down."
	end
	if busy[player] then
		return false, "Still working on your last request."
	end
	busy[player] = true
	local ok, success, result = pcall(handler, player, safeArgs)
	busy[player] = nil
	if not ok then
		warn("[CrewService] " .. action .. " failed: " .. tostring(success))
		return false, "Something went wrong. Try again."
	end
	return success, result
end

-- Player lifecycle -------------------------------------------------------------------

local function onProfileLoaded(player: Player, profile: any)
	local crewId = profile.CrewId
	if type(crewId) ~= "string" or crewId == "" then
		setDisplay(player, nil)
		crewUpdate:FireClient(player, nil)
		return
	end
	local ok, record = loadCrew(crewId)
	if player.Parent ~= Players then
		return
	end
	if not ok then
		-- Store unreachable: keep the link and let the refresh loop retry the read.
		playerCrew[player] = crewId
		return
	end
	local k = key(player.UserId)
	if not record or record.Members[k] == nil then
		applyMembership(player, nil)
		Notify.Send(player, if record then "You were removed from your crew while you were away." else "Your crew was disbanded.", "crew")
		return
	end
	applyMembership(player, crewId)
	broadcast(crewId)
	-- Keep the stored display name and the leader's Crew Plus banner flag current.
	local isLeader = record.Members[k] == "Leader"
	local plus = isLeader and ownsPlus(player)
	local names = if type(record.Names) == "table" then record.Names else {}
	if names[k] ~= player.DisplayName or (isLeader and record.Banner ~= plus) then
		task.spawn(mutateCrew, crewId, function(r: any): string?
			if not r.Members[k] then
				return "gone"
			end
			r.Names = if type(r.Names) == "table" then r.Names else {}
			r.Names[k] = player.DisplayName
			if r.Members[k] == "Leader" then
				r.Banner = plus
			end
			return nil
		end)
	end
end

local function onPlayerRemoving(player: Player)
	local crewId = playerCrew[player]
	playerCrew[player] = nil
	busy[player] = nil
	actionLimiter:Remove(player)
	readLimiter:Remove(player)
	clearPendingFor(player.UserId)
	CrewHQ.PlayerLeft(player)
	if crewId then
		task.defer(broadcast, crewId) -- after the player is gone, so Online is false
	end
end

local function refreshAll()
	local ids = {}
	for player, crewId in playerCrew do
		if player.Parent == Players then
			ids[crewId] = true
		end
	end
	for crewId in ids do
		local ok, record = loadCrew(crewId)
		if ok then
			if record then
				reconcileCrew(crewId)
			else
				finishDisband(crewId, nil)
			end
		end
	end
	-- Forget cached crews nobody here belongs to, and expired invites/requests.
	for crewId in crews do
		if not ids[crewId] and not CrewHQ.IsBuilt(crewId) then
			crews[crewId] = nil
		end
	end
	local now = os.clock()
	for userId, list in invites do
		for crewId, invite in list do
			if invite.Expires < now then
				list[crewId] = nil
			end
		end
		if next(list) == nil then
			invites[userId] = nil
		end
	end
	for crewId, list in requests do
		for userId, request in list do
			if request.Expires < now then
				list[userId] = nil
			end
		end
		if next(list) == nil then
			requests[crewId] = nil
		end
	end
end

local function onCrewHQ(player: Player, _interactable: any, part: BasePart)
	local crewId = playerCrew[player]
	if not crewId or not crews[crewId] then
		Notify.Send(player, "Crew members only. Join or create a crew in the Crew app.", "crew")
		return
	end
	if getRank(player) < Crews.MinRank then
		Notify.Send(player, string.format("Crew HQs open at Rank %d.", Crews.MinRank), "bad")
		return
	end
	local combat = Services.CombatService
	if combat and combat.IsDowned and combat.IsDowned(player) then
		return
	end
	local info = hqInfo(crewId)
	if not info then
		return
	end
	CrewHQ.Enter(player, crewId, info, CFrame.new(part.Position + Vector3.new(0, 2, -6)))
end

-- Public API -------------------------------------------------------------------------

function CrewService.GetCrewId(player: Player): string?
	return playerCrew[player]
end

-- Summary in the Crew_Update shape. viewer fills MyRole (and Requests for officers).
function CrewService.GetCrewSummary(crewId: string, viewer: Player?): any?
	if type(crewId) ~= "string" then
		return nil
	end
	return buildSummary(crewId, viewer)
end

function CrewService.AreCrewmates(a: Player, b: Player): boolean
	local crewA = playerCrew[a]
	return crewA ~= nil and a ~= b and crewA == playerCrew[b]
end

-- The player's crew color, or nil without a crew.
function CrewService.GetCrewColor(player: Player): Color3?
	local crewId = playerCrew[player]
	local record = crewId and crews[crewId]
	if not isLive(record) then
		return nil
	end
	return Color3.fromHex(colorHex(record))
end

function CrewService.GetOnlineMembers(crewId: string): { Player }
	return onlineMembers(crewId)
end

-- Adds weekly crew Rep (and optionally turf captures). Resets automatically when the UTC week changes.
function CrewService.AddCrewRep(crewId: string, amount: number, captures: number?)
	if type(crewId) ~= "string" or type(amount) ~= "number" or amount < 0 then
		return
	end
	local rep = math.floor(amount)
	local caps = if type(captures) == "number" then math.max(0, math.floor(captures)) else 0
	if rep == 0 and caps == 0 then
		return
	end
	task.spawn(function()
		local ok = mutateCrew(crewId, function(record)
			record.WeeklyRep = (tonumber(record.WeeklyRep) or 0) + rep
			record.TotalCaptures = (tonumber(record.TotalCaptures) or 0) + caps
			return nil
		end)
		if ok then
			broadcast(crewId)
		end
	end)
end

-- Re-sends Crew_Update to every online member (e.g. after turf ownership changes).
function CrewService.BroadcastCrew(crewId: string)
	if type(crewId) == "string" and crews[crewId] then
		broadcast(crewId)
	end
end

-- Lifecycle -----------------------------------------------------------------------------

function CrewService.Init(services: any)
	Services = services
	CrewStore.Init({ GameConfig.CrewStoreName, GameConfig.CrewNameStoreName })
	CrewHQ.Init(function(player: Player, cframe: CFrame)
		if Services.MapService and Services.MapService.Teleport then
			Services.MapService.Teleport(player, cframe)
		else
			local character = player.Character
			if character then
				character:PivotTo(cframe)
			end
		end
	end)
	Net.Function("Crew_Action").OnServerInvoke = function(player: Player, action: any, args: any)
		return onAction(player, action, args)
	end
end

function CrewService.Start()
	Services.InteractionService.Register("CrewHQ", onCrewHQ)

	Services.DataService.ProfileLoaded:Connect(onProfileLoaded)
	for _, player in Players:GetPlayers() do
		local profile = Services.DataService.GetProfile(player)
		if profile then
			task.spawn(onProfileLoaded, player, profile)
		end
	end
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	task.spawn(CrewHQ.Run)
	while true do
		task.wait(REFRESH_INTERVAL)
		xpcall(refreshAll, function(err: any)
			warn("[CrewService] Refresh failed: " .. tostring(err))
		end)
	end
end

return CrewService
