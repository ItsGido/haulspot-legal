--!strict
-- The gym tournament (blueprint Z7, Config.Game.Tournament).
--   Sign up at the "Tournament" interactable (Rank >= MinRank, not in a duel, max MaxPlayers; press again to
--   withdraw). Starts when full, or during After School past DayCycle.TournamentStartOffset with at least
--   the minimum signed up. Single elimination with random seeding and byes, each match a forced duel in
--   the gym ring via ChallengeService.StartForcedDuel. Broadcasts Tourney_Update on every change.
-- Public API: TournamentService.IsParticipant(player) · TournamentService.GetState() -> string

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.Game)
local DayCycle = require(ReplicatedStorage.Shared.Config.DayCycle)
local Ranks = require(ReplicatedStorage.Shared.Config.Ranks)
local MapData = require(ReplicatedStorage.Shared.Map.MapData)
local Net = require(ReplicatedStorage.Shared.Util.Net)
local Notify = require(script.Parent.Parent.Systems.Notify)
local Util = require(script.Parent.Parent.Systems.ProgressionUtil)

local Config = GameConfig.Tournament

local TournamentService = {}
TournamentService.Priority = 60

local Services: any

-- Internal timings and placement (not gameplay tuning).
local POLL_INTERVAL = 1 -- seconds between auto-start checks
local RESULT_POLL = 0.25 -- seconds between "is the match over?" checks
local TELEPORT_SETTLE = 0.5 -- seconds after teleporting before the ring forms
local CHARACTER_WAIT = 10 -- seconds to wait for a respawning fighter before they forfeit
local ENTRANCE_OFFSET = Vector3.new(0, 0, 6) -- from the sign-up board, away from the gym
local FALLBACK_STAND_Y = 3 -- standing height when the sign-up board is missing from MapData
local FULL_HP = 1

type Match = { A: string, B: string?, Winner: string? }

local tourneyUpdate = Net.Event("Tourney_Update")

local state = "Idle" -- "Idle" | "Signup" | "Running" | "Finished"
local signups: { Player } = {}
local participants: { [Player]: boolean } = {}
local bracket: { { Match } } = {}
local currentMatch: { A: string, B: string, EndsAt: number }? = nil
local message: string? = nil
local cooldownUntil = 0

local standY = FALLBACK_STAND_Y
local entranceCFrame: CFrame
do
	local board = nil
	for _, item in MapData.Interactables do
		if item.Kind == "Tournament" then
			board = item
			break
		end
	end
	local boardPos = if board
		then Vector3.new(board.X, board.Y, board.Z)
		else Vector3.new(Config.RingCenter[1], FALLBACK_STAND_Y, Config.RingCenter[2])
	standY = boardPos.Y
	local entrance = boardPos + ENTRANCE_OFFSET
	entranceCFrame = CFrame.lookAt(entrance, entrance + ENTRANCE_OFFSET)
end

local ringCenter = Vector3.new(Config.RingCenter[1], 0, Config.RingCenter[2])

local function minPlayers(): number
	if RunService:IsStudio() then
		return GameConfig.Studio.TournamentMinPlayers
	end
	return Config.MinPlayers
end

local function names(list: { Player }): { string }
	local out = {}
	for _, p in list do
		table.insert(out, p.DisplayName)
	end
	return out
end

local function payload(): any
	local players: { string } = {}
	if state == "Signup" or state == "Idle" then
		players = names(signups)
	else
		for p in participants do
			table.insert(players, p.DisplayName)
		end
		table.sort(players)
	end
	return {
		State = state,
		Players = players,
		Needed = minPlayers(),
		Max = Config.MaxPlayers,
		Bracket = bracket,
		Match = currentMatch,
		Message = message,
	}
end

local function broadcast()
	tourneyUpdate:FireAllClients(payload())
end

local function removeSignup(player: Player): boolean
	local index = table.find(signups, player)
	if index then
		table.remove(signups, index)
		return true
	end
	return false
end

local function teleportOut(player: Player)
	if Util.IsOnline(player) and Services.MapService then
		Services.MapService.Teleport(player, entranceCFrame)
	end
end

local function heal(player: Player)
	if Util.IsOnline(player) and player.Character and Services.CombatService then
		Services.CombatService.Revive(player.Character, FULL_HP)
	end
end

local function waitForRoot(player: Player): boolean
	local waited = 0
	while Util.IsOnline(player) and not Util.GetRoot(player) and waited < CHARACTER_WAIT do
		task.wait(RESULT_POLL)
		waited += RESULT_POLL
	end
	return Util.IsOnline(player) and Util.GetRoot(player) ~= nil
end

local function stillIn(player: Player): boolean
	return Util.IsOnline(player) and participants[player] == true
end

-- Plays one match. Returns winner?, loser?.
local function playMatch(a: Player, b: Player?, entry: Match): (Player?, Player?)
	if not b then
		entry.Winner = a.DisplayName
		message = a.DisplayName .. " gets a bye."
		broadcast()
		return if stillIn(a) then a else nil, nil
	end
	local opponent = b :: Player
	local aIn, bIn = stillIn(a), stillIn(opponent)
	if aIn and Services.ChallengeService and Services.ChallengeService.IsInDuel(a) then
		aIn = false
	end
	if bIn and Services.ChallengeService and Services.ChallengeService.IsInDuel(opponent) then
		bIn = false
	end
	aIn = aIn and waitForRoot(a)
	bIn = bIn and waitForRoot(opponent)
	if not aIn and not bIn then
		message = "Both fighters are gone. No winner."
		broadcast()
		return nil, nil
	elseif not aIn then
		message = a.DisplayName .. " forfeits."
		return opponent, a
	elseif not bIn then
		message = opponent.DisplayName .. " forfeits."
		return a, opponent
	end

	heal(a)
	heal(opponent)
	local offset = Vector3.new(Config.RingRadius / 2, 0, 0)
	local standCenter = Vector3.new(ringCenter.X, standY, ringCenter.Z)
	if Services.MapService then
		Services.MapService.Teleport(a, CFrame.lookAt(standCenter - offset, standCenter))
		Services.MapService.Teleport(opponent, CFrame.lookAt(standCenter + offset, standCenter))
	end
	task.wait(TELEPORT_SETTLE)

	local result: { Done: boolean, Winner: Player?, Loser: Player?, Info: any } = { Done = false, Winner = nil, Loser = nil, Info = nil }
	local started = false
	if Services.ChallengeService and stillIn(a) and stillIn(opponent) then
		started = Services.ChallengeService.StartForcedDuel(a, opponent, {
			Kind = "Tournament",
			Center = ringCenter,
			Radius = Config.RingRadius,
			TimeLimit = Config.MatchSeconds,
			OnEnd = function(winner: Player?, loser: Player?, _reason: string, info: any)
				result.Winner = winner
				result.Loser = loser
				result.Info = info
				result.Done = true
			end,
		})
	end
	if not started then
		-- Couldn't form the ring: whoever is still here advances.
		if stillIn(a) and not stillIn(opponent) then
			return a, opponent
		elseif stillIn(opponent) and not stillIn(a) then
			return opponent, a
		end
		local coin = math.random() < 0.5
		message = "The ring couldn't form. A coin toss decides."
		return if coin then a else opponent, if coin then opponent else a
	end

	currentMatch = { A = a.DisplayName, B = opponent.DisplayName, EndsAt = workspace:GetServerTimeNow() + Config.MatchSeconds }
	message = string.format("%s vs %s!", a.DisplayName, opponent.DisplayName)
	broadcast()
	Notify.Many({ a, opponent }, "FIGHT! First KO wins, or the healthier fighter at the bell.", "gold")

	while not result.Done do
		task.wait(RESULT_POLL)
	end
	currentMatch = nil

	local winner, loser = result.Winner, result.Loser
	for _, p in { a, opponent } do
		if Util.IsOnline(p) then
			Util.Quest(Services, p, "TournamentMatch", 1)
		end
	end
	if winner and loser and Services.RepService then
		local info = result.Info or {}
		Services.RepService.FightResult(winner, loser, {
			Kind = "Tournament",
			WinnerHits = info.WinnerHits,
			LoserHits = info.LoserHits,
		})
	end
	heal(a)
	heal(opponent)
	teleportOut(a)
	teleportOut(opponent)
	return winner, loser
end

local function givePrizes(champion: Player?, finalist: Player?, semifinalists: { Player })
	local repService = Services.RepService
	if champion and Util.IsOnline(champion) then
		if repService then
			repService.AddRep(champion, Ranks.TournamentWinner, "Tournament")
		end
		Services.DataService.AddScrolls(champion, Config.WinnerScrolls)
		Services.DataService.Update(champion, { "Stats" }, function(profile: any)
			profile.Stats.TourneysWon += 1
		end)
		Notify.All(string.format("🏆 %s is the GYM KING!", champion.DisplayName), "gold", 6)
		Notify.Send(champion, string.format("+%d Rep, +%d scrolls", Ranks.TournamentWinner, Config.WinnerScrolls), "gold")
	end
	if finalist and Util.IsOnline(finalist) then
		if repService then
			repService.AddRep(finalist, Ranks.TournamentFinalist, "Tournament")
		end
		Services.DataService.AddScrolls(finalist, Config.FinalistScrolls)
		Notify.Send(finalist, string.format("Finalist! +%d Rep, +%d scrolls", Ranks.TournamentFinalist, Config.FinalistScrolls), "gold")
	end
	for _, semi in semifinalists do
		if Util.IsOnline(semi) then
			if repService then
				repService.AddRep(semi, Ranks.TournamentSemifinalist, "Tournament")
			end
			Notify.Send(semi, string.format("Semifinalist! +%d Rep", Ranks.TournamentSemifinalist), "gold")
		end
	end
end

local function shuffle(list: { Player })
	for i = #list, 2, -1 do
		local j = math.random(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

local function run()
	if state ~= "Signup" then
		return
	end
	local entrants: { Player } = {}
	for _, p in signups do
		if Util.IsOnline(p) and not (Services.ChallengeService and Services.ChallengeService.IsInDuel(p)) then
			table.insert(entrants, p)
		end
	end
	if #entrants < minPlayers() then
		message = "Not enough fighters are ready. Sign-ups stay open."
		broadcast()
		return
	end
	state = "Running"
	signups = {}
	bracket = {}
	participants = {}
	for _, p in entrants do
		participants[p] = true
		p:SetAttribute("InTournament", true)
	end
	shuffle(entrants)
	message = "The tournament begins!"
	broadcast()
	Notify.All(string.format("The gym tournament is starting with %d fighters!", #entrants), "gold")

	local alive = entrants
	local finalist: Player? = nil
	local semifinalists: { Player } = {}
	while #alive > 1 do
		local round: { Match } = {}
		local matchups: { { Player? } } = {}
		for i = 1, #alive, 2 do
			local a, b = alive[i], alive[i + 1]
			table.insert(round, { A = a.DisplayName, B = if b then b.DisplayName else nil, Winner = nil })
			table.insert(matchups, { a, b })
		end
		table.insert(bracket, round)
		broadcast()

		local nextAlive: { Player } = {}
		local roundLosers: { Player } = {}
		local fieldSize = #alive
		for index, pair in matchups do
			local a = pair[1] :: Player
			local b = pair[2]
			local entry = round[index]
			local winner, loser = playMatch(a, b, entry)
			if winner then
				entry.Winner = winner.DisplayName
				table.insert(nextAlive, winner)
			end
			if loser then
				table.insert(roundLosers, loser)
			end
			broadcast()
			if index < #matchups or #nextAlive > 1 then
				task.wait(Config.BetweenMatchesSeconds)
			end
		end
		if fieldSize == 2 then
			finalist = roundLosers[1]
		elseif fieldSize <= 4 then
			semifinalists = roundLosers
		end
		alive = nextAlive
	end

	local champion: Player? = alive[1]
	if champion and not Util.IsOnline(champion) then
		champion = nil
	end
	givePrizes(champion, finalist, semifinalists)

	state = "Finished"
	message = if champion then champion.DisplayName .. " is the Gym King!" else "The tournament ended with no winner."
	broadcast()
	for p in participants do
		if Util.IsOnline(p) then
			p:SetAttribute("InTournament", nil)
			teleportOut(p)
		end
	end
	cooldownUntil = os.clock() + Config.SignupCooldownSeconds
	task.wait(Config.BetweenMatchesSeconds)
	state = "Idle"
	participants = {}
	currentMatch = nil
	message = string.format("Next tournament sign-ups open in %d min.", math.ceil(Config.SignupCooldownSeconds / 60))
	broadcast()
end

local function onSignup(player: Player)
	if state == "Running" or state == "Finished" then
		Notify.Send(player, "A tournament is in progress. Watch from the bleachers!", "info")
		return
	end
	if removeSignup(player) then
		Notify.Send(player, "You withdrew from the tournament.", "info")
		if #signups == 0 then
			state = "Idle"
		end
		message = nil
		broadcast()
		return
	end
	local remaining = cooldownUntil - os.clock()
	if remaining > 0 then
		Notify.Send(player, string.format("Sign-ups reopen in %ds.", math.ceil(remaining)), "bad")
		return
	end
	local rank = if Services.RepService then Services.RepService.GetRank(player) else 1
	if rank < Config.MinRank then
		local entry = Ranks.List[Config.MinRank]
		Notify.Send(player, string.format("You need to be a %s (Rank %d) to enter.", if entry then entry.Title else "higher rank", Config.MinRank), "bad")
		return
	end
	if Services.ChallengeService and Services.ChallengeService.IsInDuel(player) then
		Notify.Send(player, "Finish your duel first.", "bad")
		return
	end
	if #signups >= Config.MaxPlayers then
		Notify.Send(player, "The bracket is full.", "bad")
		return
	end
	table.insert(signups, player)
	state = "Signup"
	message = string.format("%s signed up.", player.DisplayName)
	Notify.Send(player, string.format("Signed up! (%d/%d)", #signups, Config.MaxPlayers), "good")
	broadcast()
	if #signups >= Config.MaxPlayers then
		task.spawn(run)
	end
end

local function canAutoStart(): boolean
	if state ~= "Signup" or #signups < minPlayers() then
		return false
	end
	local dayCycle = Services.DayCycleService
	if not dayCycle then
		return false
	end
	local period = dayCycle.GetPeriod()
	return period.Id == "AfterSchool" and period.Elapsed >= DayCycle.TournamentStartOffset
end

-- Public API -----------------------------------------------------------------

function TournamentService.IsParticipant(player: Player): boolean
	return participants[player] == true or table.find(signups, player) ~= nil
end

function TournamentService.GetState(): string
	return state
end

-- Lifecycle --------------------------------------------------------------------

function TournamentService.Init(services: any)
	Services = services
end

function TournamentService.Start()
	Services.InteractionService.Register("Tournament", function(player: Player)
		onSignup(player)
	end)
	Players.PlayerAdded:Connect(function(player)
		tourneyUpdate:FireClient(player, payload())
	end)
	Players.PlayerRemoving:Connect(function(player)
		if removeSignup(player) then
			if #signups == 0 and state == "Signup" then
				state = "Idle"
			end
			broadcast()
		end
		if participants[player] then
			participants[player] = nil
			Notify.All(string.format("%s left the tournament.", player.DisplayName), "info")
			-- Their current match (if any) ends through ChallengeService; later matches are forfeits.
		end
	end)
	while true do
		task.wait(POLL_INTERVAL)
		if canAutoStart() then
			run()
		end
	end
end

return TournamentService
