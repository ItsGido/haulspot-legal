--!strict
-- Challenge duels (blueprint section 1.7).
--   Hold E on a player (server-made "ChallengePrompt" on every HumanoidRootPart) or Challenge_Send from
--   the player list. The target gets Challenge_Incoming and answers with Challenge_Respond within
--   Game.Challenge.ResponseTimeout. On accept a ring forms at the midpoint; first KO wins, leaving the ring
--   for Game.Challenge.LeaveRingGrace seconds loses.
--
-- Public API:
--   ChallengeService.IsInDuel(player) -> boolean
--   ChallengeService.AreDueling(a, b) -> boolean
--   ChallengeService.GetOpponent(player) -> (Player?, kind: string?)
--   ChallengeService.OnDuelKO(loser, winner)               (CombatService calls this at 0 HP in a duel)
--   ChallengeService.StartForcedDuel(a, b, opts) -> boolean
--     opts = { Kind = "Tournament", Center: Vector3, Radius: number?, TimeLimit: number?,
--              OnEnd = function(winner?, loser?, reason, info) }  (no accept, no wager, no FightResult)
--   ChallengeService.DuelEnded (Signal: winner, loser, info { Kind, Wager?, Reason, WinnerHits, LoserHits })

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.Game)
local Ranks = require(ReplicatedStorage.Shared.Config.Ranks)
local Combat = require(ReplicatedStorage.Shared.Config.Combat)
local RepMath = require(ReplicatedStorage.Shared.Logic.RepMath)
local Net = require(ReplicatedStorage.Shared.Util.Net)
local RateLimiter = require(ReplicatedStorage.Shared.Util.RateLimiter)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Notify = require(script.Parent.Parent.Systems.Notify)
local Util = require(script.Parent.Parent.Systems.ProgressionUtil)

local Config = GameConfig.Challenge

local ChallengeService = {}
ChallengeService.Priority = 50

ChallengeService.DuelEnded = Signal.new() -- (winner: Player?, loser: Player?, info)

local Services: any

-- Internal timings and visuals (not gameplay tuning).
local MONITOR_INTERVAL = 0.2 -- seconds between ring / time-limit checks
local OUTSIDER_WARN_INTERVAL = 4 -- seconds between "leave the ring" toasts to the same outsider
local RING_THICKNESS = 0.3
local RING_TRANSPARENCY = 0.75
local RING_COLOR = Color3.fromRGB(255, 59, 107)
local FORCED_RING_COLOR = Color3.fromRGB(255, 182, 39)
local PROMPT_HOLD = 0.3 -- seconds (blueprint 1.7: "hold E")
local DEFAULT_FOOT_OFFSET = 3 -- studs below the root when the humanoid can't be measured
local REMOTE_RATE, REMOTE_PER = 3, 1

type Duel = {
	A: Player,
	B: Player,
	Kind: string, -- "Duel" | "Tournament" | ...
	Forced: boolean,
	Center: Vector3,
	Radius: number,
	Ring: BasePart?,
	EndsAt: number?, -- os.clock deadline (forced duels with a time limit)
	OutsideSince: { [Player]: number },
	Hits: { [Player]: number },
	Warned: { [Player]: number },
	OnEnd: ((Player?, Player?, string, any) -> ())?,
	Ended: boolean,
}

type Pending = {
	From: Player,
	Target: Player,
	ExpiresAt: number, -- os.clock
	Token: number,
}

local challengeUpdate = Net.Event("Challenge_Update")
local challengeIncoming = Net.Event("Challenge_Incoming")

local sendLimiter = RateLimiter.new(REMOTE_RATE, REMOTE_PER)
local respondLimiter = RateLimiter.new(REMOTE_RATE, REMOTE_PER)

local duels: { [Player]: Duel } = {}
local activeDuels: { [Duel]: boolean } = {}
local outgoing: { [Player]: Pending } = {} -- one pending challenge per challenger
local lastDuelEnd: { [Player]: number } = {}
local declined: { [string]: number } = {} -- "targetId:fromId" -> os.clock of the decline
local nextToken = 0
local duelsFolder: Folder

local function getDuelsFolder(): Folder
	local existing = workspace:FindFirstChild("Duels")
	if existing and existing:IsA("Folder") then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "Duels"
	created.Parent = workspace
	return created
end

local function declineKey(target: Player, from: Player): string
	return target.UserId .. ":" .. from.UserId
end

local function update(player: Player?, payload: any)
	if player and Util.IsOnline(player) then
		challengeUpdate:FireClient(player, payload)
	end
end

local function rankOf(player: Player): number
	if Services.RepService then
		return Services.RepService.GetRank(player)
	end
	local attr = player:GetAttribute("Rank")
	return if type(attr) == "number" then attr else 1
end

local function isDowned(player: Player): boolean
	if Services.CombatService and Services.CombatService.IsDowned(player) then
		return true
	end
	local character = player.Character
	return character ~= nil and character:GetAttribute("Downed") == true
end

-- Why this player can't duel right now, or nil if they can. `who` is "You" or the other's name.
local function blockReason(player: Player, who: string): string?
	if not Util.IsOnline(player) or not Services.DataService.GetProfile(player) then
		return who .. " can't duel right now."
	end
	if not Util.GetRoot(player) then
		return who .. " can't duel right now."
	end
	if duels[player] then
		return who .. " already in a duel."
	end
	if player:GetAttribute("InTournament") == true then
		return who .. " in the tournament."
	end
	if Services.TutorialService and Services.TutorialService.IsInTutorial(player) then
		return who .. " still in the tutorial."
	end
	if isDowned(player) then
		return who .. " down."
	end
	if Services.CombatService and Services.CombatService.IsInCombat(player) then
		return who .. " in a fight."
	end
	if Services.ZoneService and Services.ZoneService.GetZoneType(player) == "Green" then
		return who .. " in a safe zone."
	end
	local last = lastDuelEnd[player]
	if last and os.clock() - last < Config.CooldownAfterDuel then
		return string.format("%s on duel cooldown (%ds).", who, math.ceil(Config.CooldownAfterDuel - (os.clock() - last)))
	end
	return nil
end

local function selfReason(player: Player): string?
	local reason = blockReason(player, "You're")
	return reason
end

local function otherReason(player: Player): string?
	return blockReason(player, player.DisplayName .. " is")
end

local function footPosition(player: Player): Vector3?
	local root = Util.GetRoot(player)
	if not root then
		return nil
	end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local offset = if humanoid then root.Size.Y / 2 + humanoid.HipHeight else DEFAULT_FOOT_OFFSET
	return root.Position - Vector3.new(0, offset, 0)
end

local function makeRing(center: Vector3, radius: number, forced: boolean): BasePart
	local ring = Instance.new("Part")
	ring.Name = "DuelRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = if forced then FORCED_RING_COLOR else RING_COLOR
	ring.Transparency = RING_TRANSPARENCY
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Size = Vector3.new(RING_THICKNESS, radius * 2, radius * 2)
	-- A cylinder's axis is X; rotate it so the disc lies flat.
	ring.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Parent = duelsFolder
	return ring
end

local function opponentOf(duel: Duel, player: Player): Player
	return if duel.A == player then duel.B else duel.A
end

local function clearPendingFor(player: Player, reasonText: string)
	local mine = outgoing[player]
	if mine then
		outgoing[player] = nil
		update(mine.Target, { State = "Cancelled", Opponent = player, OpponentName = player.DisplayName, Message = reasonText })
	end
	for from, pending in outgoing do
		if pending.Target == player then
			outgoing[from] = nil
			update(from, { State = "Cancelled", Opponent = player, OpponentName = player.DisplayName, Message = reasonText })
		end
	end
end

-- Ending ------------------------------------------------------------------------

local function endDuel(duel: Duel, winner: Player?, loser: Player?, reason: string)
	if duel.Ended then
		return
	end
	duel.Ended = true
	activeDuels[duel] = nil
	for _, p in { duel.A, duel.B } do
		if duels[p] == duel then
			duels[p] = nil
		end
		lastDuelEnd[p] = os.clock()
		if Util.IsOnline(p) then
			p:SetAttribute("InDuel", nil)
		end
	end
	if duel.Ring then
		duel.Ring:Destroy()
		duel.Ring = nil
	end

	local winnerHits = if winner then duel.Hits[winner] or 0 else 0
	local loserHits = if loser then duel.Hits[loser] or 0 else 0

	-- First KO wins: the loser stands up at 50% HP (no downed state, no finish).
	if reason == "KO" and loser and loser.Character and Services.CombatService then
		Services.CombatService.Revive(loser.Character, Combat.DuelLoserHPFraction)
	end

	local wager: number? = nil
	if not duel.Forced and winner and loser then
		wager = RepMath.DuelWager(Ranks, rankOf(winner), rankOf(loser))
		if Services.RepService then
			Services.RepService.FightResult(winner, loser, {
				Kind = "Duel",
				Wager = wager,
				WinnerHits = winnerHits,
				LoserHits = loserHits,
			})
		end
	end

	local info = { Kind = duel.Kind, Wager = wager, Reason = reason, WinnerHits = winnerHits, LoserHits = loserHits }
	ChallengeService.DuelEnded:Fire(winner, loser, info)

	local message: string
	if reason == "LeftRing" then
		message = (if loser then loser.DisplayName else "A fighter") .. " left the ring."
	elseif reason == "Left" then
		message = (if loser then loser.DisplayName else "A fighter") .. " left the server."
	elseif reason == "Timeout" then
		message = "Time! The healthier fighter wins."
	elseif reason == "Cancelled" then
		message = "The duel was cancelled."
	else
		message = "K.O.!"
	end
	local payload = {
		State = "Ended",
		Winner = winner,
		WinnerName = if winner then winner.DisplayName else nil,
		Wager = wager,
		Message = message,
	}
	update(duel.A, payload)
	update(duel.B, payload)

	if duel.OnEnd then
		local onEnd = duel.OnEnd :: (Player?, Player?, string, any) -> ()
		task.spawn(onEnd, winner, loser, reason, info)
	end
end

-- Starting ----------------------------------------------------------------------

local function beginDuel(a: Player, b: Player, opts: any): Duel?
	local footA, footB = footPosition(a), footPosition(b)
	if not footA or not footB then
		return nil
	end
	local forced = opts.Forced == true
	local center: Vector3 = if typeof(opts.Center) == "Vector3" then opts.Center else (footA + footB) / 2
	local radius: number = if type(opts.Radius) == "number" and opts.Radius > 0 then opts.Radius else Config.RingRadius
	local duel: Duel = {
		A = a,
		B = b,
		Kind = if type(opts.Kind) == "string" then opts.Kind else "Duel",
		Forced = forced,
		Center = center,
		Radius = radius,
		Ring = nil,
		EndsAt = if type(opts.TimeLimit) == "number" and opts.TimeLimit > 0 then os.clock() + opts.TimeLimit else nil,
		OutsideSince = {},
		Hits = { [a] = 0, [b] = 0 },
		Warned = {},
		OnEnd = if type(opts.OnEnd) == "function" then opts.OnEnd else nil,
		Ended = false,
	}
	duel.Ring = makeRing(center, radius, forced)
	duels[a] = duel
	duels[b] = duel
	activeDuels[duel] = true
	clearPendingFor(a, "They started another duel.")
	clearPendingFor(b, "They started another duel.")
	a:SetAttribute("InDuel", true)
	b:SetAttribute("InDuel", true)

	local endsAtServer: number? = nil
	if duel.EndsAt then
		endsAtServer = workspace:GetServerTimeNow() + (duel.EndsAt - os.clock())
	end
	local wagerA = if forced then nil else RepMath.DuelWager(Ranks, rankOf(a), rankOf(b))
	local wagerB = if forced then nil else RepMath.DuelWager(Ranks, rankOf(b), rankOf(a))
	update(a, {
		State = "Started",
		Opponent = b,
		OpponentName = b.DisplayName,
		Center = center,
		Radius = radius,
		Wager = wagerA,
		Kind = duel.Kind,
		EndsAt = endsAtServer,
	})
	update(b, {
		State = "Started",
		Opponent = a,
		OpponentName = a.DisplayName,
		Center = center,
		Radius = radius,
		Wager = wagerB,
		Kind = duel.Kind,
		EndsAt = endsAtServer,
	})
	return duel
end

local function startNormalDuel(a: Player, b: Player)
	local duel = beginDuel(a, b, { Kind = "Duel" })
	if not duel then
		Notify.Many({ a, b }, "The duel couldn't start.", "bad")
		return
	end
	Notify.Many({ a, b }, string.format("DUEL! %s vs %s. First KO wins.", a.DisplayName, b.DisplayName), "gold")
end

-- Requests ----------------------------------------------------------------------

local function sendChallenge(from: Player, target: Player)
	if from == target or not Util.IsOnline(target) then
		return
	end
	local reason = selfReason(from) or otherReason(target)
	if reason then
		Notify.Send(from, reason, "bad")
		return
	end
	local declinedAt = declined[declineKey(target, from)]
	if declinedAt and os.clock() - declinedAt < Config.DeclineCooldownSamePlayer then
		Notify.Send(
			from,
			string.format(
				"%s declined recently. Try again in %ds.",
				target.DisplayName,
				math.ceil(Config.DeclineCooldownSamePlayer - (os.clock() - declinedAt))
			),
			"bad"
		)
		return
	end
	local existing = outgoing[from]
	if existing and os.clock() < existing.ExpiresAt then
		Notify.Send(from, "Wait for your last challenge to be answered.", "bad")
		return
	end
	-- A target who already challenged us: treat this as an accept.
	local reverse = outgoing[target]
	if reverse and reverse.Target == from and os.clock() < reverse.ExpiresAt then
		outgoing[target] = nil
		startNormalDuel(target, from)
		return
	end

	-- The Banchō must accept challenges from Rank 5+.
	if Services.CrownService and Services.CrownService.MustAccept(target, from) then
		Notify.Send(target, string.format("%s challenged the Banchō. You must accept!", from.DisplayName), "gold")
		Notify.Send(from, string.format("%s holds the crown and must accept.", target.DisplayName), "gold")
		startNormalDuel(from, target)
		return
	end

	nextToken += 1
	local token = nextToken
	local pending: Pending = {
		From = from,
		Target = target,
		ExpiresAt = os.clock() + Config.ResponseTimeout,
		Token = token,
	}
	outgoing[from] = pending
	local fromRank = rankOf(from)
	local targetRank = rankOf(target)
	challengeIncoming:FireClient(target, {
		From = from,
		FromName = from.DisplayName,
		FromRank = fromRank,
		FromTitle = (Ranks.List[fromRank] or Ranks.List[1]).Title,
		Wager = RepMath.DuelWager(Ranks, targetRank, fromRank), -- what the target wins
		ExpiresAt = workspace:GetServerTimeNow() + Config.ResponseTimeout,
	})
	update(from, {
		State = "Sent",
		Opponent = target,
		OpponentName = target.DisplayName,
		Wager = RepMath.DuelWager(Ranks, fromRank, targetRank), -- what the challenger wins
	})
	task.delay(Config.ResponseTimeout, function()
		local current = outgoing[from]
		if current and current.Token == token then
			outgoing[from] = nil
			update(from, { State = "Expired", Opponent = target, OpponentName = target.DisplayName, Message = "No answer." })
			update(target, { State = "Expired", Opponent = from, OpponentName = from.DisplayName })
		end
	end)
end

local function respond(target: Player, from: Player, accept: boolean)
	local pending = outgoing[from]
	if not pending or pending.Target ~= target or os.clock() > pending.ExpiresAt then
		update(target, { State = "Expired", Opponent = from, OpponentName = from.DisplayName, Message = "That challenge expired." })
		return
	end
	outgoing[from] = nil
	if not accept then
		declined[declineKey(target, from)] = os.clock()
		update(from, { State = "Declined", Opponent = target, OpponentName = target.DisplayName, Message = target.DisplayName .. " declined." })
		return
	end
	local reason = selfReason(target) or otherReason(from)
	if reason then
		Notify.Send(target, reason, "bad")
		update(from, { State = "Cancelled", Opponent = target, OpponentName = target.DisplayName, Message = "The duel couldn't start." })
		return
	end
	startNormalDuel(from, target)
end

-- Prompts -----------------------------------------------------------------------

local function addPrompt(player: Player, character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root or not root:IsA("BasePart") or root:FindFirstChild("ChallengePrompt") then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ChallengePrompt"
	prompt.ActionText = "Challenge"
	prompt.ObjectText = player.DisplayName
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.MaxActivationDistance = Config.PromptDistance
	prompt.HoldDuration = PROMPT_HOLD
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	prompt.Triggered:Connect(function(triggering: Player)
		if triggering ~= player and sendLimiter:Allow(triggering) then
			sendChallenge(triggering, player)
		end
	end)
end

-- Monitoring --------------------------------------------------------------------

local function decideTimeout(duel: Duel)
	local fa = Util.HPFraction(duel.A.Character)
	local fb = Util.HPFraction(duel.B.Character)
	if fa > fb then
		endDuel(duel, duel.A, duel.B, "Timeout")
	elseif fb > fa then
		endDuel(duel, duel.B, duel.A, "Timeout")
	elseif math.random() < 0.5 then
		endDuel(duel, duel.A, duel.B, "Timeout")
	else
		endDuel(duel, duel.B, duel.A, "Timeout")
	end
end

local function monitorDuel(duel: Duel, now: number)
	if duel.EndsAt and now >= duel.EndsAt then
		decideTimeout(duel)
		return
	end
	for _, p in { duel.A, duel.B } do
		if duel.Ended then
			return
		end
		local root = Util.GetRoot(p)
		local inside = root ~= nil and Util.FlatDistance(root.Position, duel.Center) <= duel.Radius
		if inside then
			duel.OutsideSince[p] = nil
		else
			local since = duel.OutsideSince[p]
			if not since then
				duel.OutsideSince[p] = now
				Notify.Send(p, string.format("Get back in the ring! (%ds)", Config.LeaveRingGrace), "bad", Config.LeaveRingGrace)
			elseif now - since >= Config.LeaveRingGrace then
				endDuel(duel, opponentOf(duel, p), p, "LeftRing")
				return
			end
		end
	end
	-- Ask outsiders standing in the ring to step out (CombatService already blocks their hits).
	for _, other in Players:GetPlayers() do
		if other ~= duel.A and other ~= duel.B then
			local root = Util.GetRoot(other)
			if root and Util.FlatDistance(root.Position, duel.Center) <= duel.Radius then
				local last = duel.Warned[other]
				if not last or now - last >= OUTSIDER_WARN_INTERVAL then
					duel.Warned[other] = now
					Notify.Send(other, "A duel is on. Please step out of the ring.", "info")
				end
			end
		end
	end
end

-- Public API -----------------------------------------------------------------

function ChallengeService.IsInDuel(player: Player): boolean
	return duels[player] ~= nil
end

function ChallengeService.AreDueling(a: Player, b: Player): boolean
	local duel = duels[a]
	return duel ~= nil and not duel.Ended and duels[b] == duel and a ~= b
end

function ChallengeService.GetOpponent(player: Player): (Player?, string?)
	local duel = duels[player]
	if not duel then
		return nil, nil
	end
	return opponentOf(duel, player), duel.Kind
end

function ChallengeService.OnDuelKO(loser: Player, winner: Player?)
	local duel = duels[loser]
	if not duel or duel.Ended then
		return
	end
	local opponent = opponentOf(duel, loser)
	if winner and winner ~= opponent then
		return -- only the opponent can win a duel
	end
	endDuel(duel, opponent, loser, "KO")
end

function ChallengeService.StartForcedDuel(a: Player, b: Player, opts: any): boolean
	if a == b or not Util.IsOnline(a) or not Util.IsOnline(b) or duels[a] or duels[b] then
		return false
	end
	local options: any = if type(opts) == "table" then table.clone(opts) else {}
	options.Forced = true
	options.Kind = if type(options.Kind) == "string" then options.Kind else "Tournament"
	local duel = beginDuel(a, b, options)
	return duel ~= nil
end

-- Lifecycle --------------------------------------------------------------------

function ChallengeService.Init(services: any)
	Services = services
	duelsFolder = getDuelsFolder()

	Net.Event("Challenge_Send").OnServerEvent:Connect(function(player: Player, target: any)
		if not sendLimiter:Allow(player) then
			return
		end
		if typeof(target) ~= "Instance" or not (target :: Instance):IsA("Player") then
			return
		end
		sendChallenge(player, target :: Player)
	end)

	Net.Event("Challenge_Respond").OnServerEvent:Connect(function(player: Player, from: any, accept: any)
		if not respondLimiter:Allow(player) then
			return
		end
		if typeof(from) ~= "Instance" or not (from :: Instance):IsA("Player") or type(accept) ~= "boolean" then
			return
		end
		respond(player, from :: Player, accept)
	end)
end

function ChallengeService.Start()
	local function hook(player: Player)
		player.CharacterAdded:Connect(function(character)
			addPrompt(player, character)
		end)
		if player.Character then
			task.spawn(addPrompt, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in Players:GetPlayers() do
		hook(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		clearPendingFor(player, player.DisplayName .. " left.")
		local duel = duels[player]
		if duel then
			endDuel(duel, opponentOf(duel, player), player, "Left")
		end
		lastDuelEnd[player] = nil
		sendLimiter:Remove(player)
		respondLimiter:Remove(player)
		local id = tostring(player.UserId)
		for key in declined do
			local targetId, fromId = string.match(key, "^(%-?%d+):(%-?%d+)$")
			if targetId == id or fromId == id then
				declined[key] = nil
			end
		end
	end)

	-- Count hits inside duels (mastery XP for duel results).
	if Services.CombatService and Services.CombatService.HitLanded then
		Services.CombatService.HitLanded:Connect(function(attackerModel: any, targetModel: any)
			local attacker = Util.PlayerFromModel(attackerModel)
			local target = Util.PlayerFromModel(targetModel)
			if attacker and target and ChallengeService.AreDueling(attacker, target) then
				local duel = duels[attacker]
				duel.Hits[attacker] = (duel.Hits[attacker] or 0) + 1
			end
		end)
	end

	game:BindToClose(function()
		-- Server shutdown: duels end with no result.
		for duel in activeDuels do
			duel.OnEnd = nil
			duel.Forced = true
			endDuel(duel, nil, nil, "Cancelled")
		end
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < MONITOR_INTERVAL then
			return
		end
		accumulator = 0
		local now = os.clock()
		for duel in activeDuels do
			if not duel.Ended then
				local ok, err = pcall(function()
					monitorDuel(duel, now)
				end)
				if not ok then
					warn("[ChallengeService] monitor error: " .. tostring(err))
				end
			end
		end
	end)
end

return ChallengeService
