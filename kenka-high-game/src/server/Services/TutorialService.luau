--!strict
-- FTUE "Transfer Day" (blueprint section 10).
--   For a profile with TutorialDone == false: PickStyle -> Attack -> Block -> Parry -> Heavy -> KO -> Explore -> Done.
--   Goro (NPCService.SpawnFighter, Mode "Tutorial") fights the player near the courtyard spawn. Steps advance
--   from CombatService.HitLanded / Parried. Finishing gives +60 Rep and +300 yen; Tutorial_Skip ends it
--   early without the Rep.
-- Public API: TutorialService.IsInTutorial(player) -> boolean · TutorialService.GetStep(player) -> string?
-- Remotes: Tutorial_Update (S->C), Tutorial_PickStyle (RF), Tutorial_Skip.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.Game)
local StylesConfig = require(ReplicatedStorage.Shared.Config.Styles)
local Net = require(ReplicatedStorage.Shared.Util.Net)
local RateLimiter = require(ReplicatedStorage.Shared.Util.RateLimiter)
local Notify = require(script.Parent.Parent.Systems.Notify)
local Util = require(script.Parent.Parent.Systems.ProgressionUtil)

local TutorialService = {}
TutorialService.Priority = 70

local Services: any

-- Tutorial tuning (blueprint section 10). Candidates for a Config.Game.Tutorial table.
local REWARD_REP = 60
local REWARD_YEN = 300
local ATTACK_HITS = 4
local GORO_DOWN_HP = 10 -- Goro "goes down" at or below this HP in the KO step
local GORO_SPAWN_DISTANCE = 12 -- studs in front of the courtyard spawn
local GORO_MIN_HP_FRACTION = 0.4 -- before the KO step Goro is topped up below this
local GORO_REFILL_FRACTION = 1
local PLAYER_MIN_HP_FRACTION = 0.3 -- the player is healed below this so they can't lose
local PLAYER_REFILL_FRACTION = 1
local EXPLORE_SECONDS = 12 -- how long the Explore pointer stays before Done
local CHARACTER_TIMEOUT = 30
local CHARACTER_POLL = 0.25
local REMOTE_RATE, REMOTE_PER = 3, 1

local TEXT = {
	PickStyle = "Oi, transfer kid. You lost? Pick your fighting style.",
	Attack = "Attack! Land %d hits on Goro (Left click / R2). %d/%d",
	Block = "Goro's winding up. Hold F (L2) to BLOCK his hit.",
	Parry = "Now tap F (L2) right as his attack lands to PARRY.",
	Heavy = "Break his guard with a HEAVY attack (Right click / R).",
	KO = "Finish it! Knock Goro down.",
	GoroDown = "Goro: \"...Not bad. You'll need a crew to survive here.\"",
	Explore = "Check out the Nurse's Office mirror to change your look, then read the Rumor Board.",
	Done = "Welcome to Kenka High.",
	Skipped = "Tutorial skipped. Welcome to Kenka High.",
}

type Session = {
	Player: Player,
	Step: string,
	Hits: number,
	Picked: boolean,
	Goro: Model?,
	GoroConnections: { RBXScriptConnection },
	Finished: boolean, -- the fight part is over (Explore step or skipped)
	Ended: boolean,
}

local tutorialUpdate = Net.Event("Tutorial_Update")
local limiter = RateLimiter.new(REMOTE_RATE, REMOTE_PER)
local sessions: { [Player]: Session } = {}
local goroOwners: { [Model]: Session } = {}

local function send(session: Session, step: string, text: string, extra: any?)
	session.Step = step
	if not Util.IsOnline(session.Player) then
		return
	end
	local data: { [string]: any } = { Step = step, Text = text }
	if type(extra) == "table" then
		for k, v in extra do
			data[k] = v
		end
	end
	tutorialUpdate:FireClient(session.Player, data)
end

local function attackText(hits: number): string
	return string.format(TEXT.Attack, ATTACK_HITS, math.min(hits, ATTACK_HITS), ATTACK_HITS)
end

local function despawnGoro(session: Session)
	for _, connection in session.GoroConnections do
		connection:Disconnect()
	end
	session.GoroConnections = {}
	local goro = session.Goro
	session.Goro = nil
	if goro then
		goroOwners[goro] = nil
		if Services.NPCService then
			Services.NPCService.Despawn(goro)
		elseif goro.Parent then
			goro:Destroy()
		end
	end
end

local function markDone(player: Player)
	Services.DataService.Update(player, { "TutorialDone" }, function(profile: any)
		profile.TutorialDone = true
	end)
end

local function endSession(session: Session)
	session.Ended = true
	despawnGoro(session)
	if sessions[session.Player] == session then
		sessions[session.Player] = nil
	end
end

local spawnGoro: (session: Session) -> ()

-- The fight is won: rewards, Goro's line, then the Explore pointer.
local function finishFight(session: Session)
	if session.Finished or session.Ended then
		return
	end
	session.Finished = true
	local player = session.Player
	despawnGoro(session)
	Notify.Send(player, "K.O.!", "gold", 3)
	Notify.Send(player, TEXT.GoroDown, "info", 6)
	if Services.RepService then
		Services.RepService.AddRep(player, REWARD_REP, "Tutorial")
	end
	Services.DataService.AddYen(player, REWARD_YEN, "Tutorial")
	markDone(player)
	send(session, "Explore", TEXT.Explore)
	task.delay(EXPLORE_SECONDS, function()
		if not session.Ended then
			send(session, "Done", TEXT.Done, { Done = true })
			endSession(session)
		end
	end)
end

local function checkGoroDown(session: Session)
	local goro = session.Goro
	if session.Step ~= "KO" or not goro then
		return
	end
	local hp = goro:GetAttribute("HP")
	if goro:GetAttribute("Downed") == true or (type(hp) == "number" and hp <= GORO_DOWN_HP) then
		finishFight(session)
	end
end

local function advance(session: Session, step: string)
	if session.Finished or session.Ended then
		return
	end
	local text = (TEXT :: any)[step] or ""
	send(session, step, text)
	if step == "KO" then
		checkGoroDown(session)
	end
end

spawnGoro = function(session: Session)
	if session.Ended or session.Finished then
		return
	end
	if not Services.NPCService then
		-- No fighter available: give the rewards without the fight.
		finishFight(session)
		return
	end
	local spawnCFrame: CFrame = if Services.MapService
		then Services.MapService.GetSpawnCFrame("Courtyard")
		else CFrame.new()
	local position = (spawnCFrame * CFrame.new(0, 0, -GORO_SPAWN_DISTANCE)).Position
	local ok, goro = pcall(Services.NPCService.SpawnFighter, {
		Name = "Goro",
		Mode = "Tutorial",
		Owner = session.Player,
		IgnoreZones = true,
		CFrame = CFrame.lookAt(position, spawnCFrame.Position),
	})
	if not ok or typeof(goro) ~= "Instance" or not (goro :: Instance):IsA("Model") then
		warn("[TutorialService] Couldn't spawn Goro: " .. tostring(goro))
		finishFight(session)
		return
	end
	local model = goro :: Model
	session.Goro = model
	goroOwners[model] = session
	table.insert(
		session.GoroConnections,
		model:GetAttributeChangedSignal("HP"):Connect(function()
			checkGoroDown(session)
		end)
	)
	table.insert(
		session.GoroConnections,
		model:GetAttributeChangedSignal("Downed"):Connect(function()
			checkGoroDown(session)
		end)
	)
	table.insert(
		session.GoroConnections,
		model.AncestryChanged:Connect(function(_, parent)
			if parent ~= nil or session.Goro ~= model then
				return
			end
			-- Goro vanished (KO'd by the combat system or removed). In the KO step that's a win; earlier, respawn him.
			goroOwners[model] = nil
			session.Goro = nil
			if session.Step == "KO" then
				finishFight(session)
			elseif not session.Finished and not session.Ended then
				task.defer(spawnGoro, session)
			end
		end)
	)
end

local function finishSkipped(session: Session)
	if session.Ended then
		return
	end
	local player = session.Player
	local alreadyFinished = session.Finished
	session.Finished = true
	despawnGoro(session)
	if not session.Picked and Services.StyleService then
		Services.StyleService.GrantStyle(player, StylesConfig.DefaultStyle)
		Services.StyleService.EquipStyle(player, StylesConfig.DefaultStyle)
	end
	if not alreadyFinished then
		Services.DataService.AddYen(player, REWARD_YEN, "Tutorial")
		markDone(player)
	end
	send(session, "Done", if alreadyFinished then TEXT.Done else TEXT.Skipped, { Done = true })
	endSession(session)
end

local function begin(player: Player)
	local profile = Services.DataService.WaitForProfile(player)
	if not profile or profile.TutorialDone then
		return
	end
	if RunService:IsStudio() and GameConfig.Studio.SkipTutorial then
		markDone(player)
		return
	end
	local waited = 0
	while Util.IsOnline(player) and not Util.GetRoot(player) and waited < CHARACTER_TIMEOUT do
		task.wait(CHARACTER_POLL)
		waited += CHARACTER_POLL
	end
	if not Util.IsOnline(player) or sessions[player] then
		return
	end
	local session: Session = {
		Player = player,
		Step = "PickStyle",
		Hits = 0,
		Picked = false,
		Goro = nil,
		GoroConnections = {},
		Finished = false,
		Ended = false,
	}
	sessions[player] = session
	send(session, "PickStyle", TEXT.PickStyle, { Choices = table.clone(StylesConfig.StarterIds) })
end

-- Combat hooks ----------------------------------------------------------------

local function onHitLanded(attackerModel: any, targetModel: any, info: any)
	local hit = if type(info) == "table" then info else {}
	-- Player hits Goro
	local goroSession = if typeof(targetModel) == "Instance" then goroOwners[targetModel :: Model] else nil
	if goroSession and Util.PlayerFromModel(attackerModel) == goroSession.Player then
		local session = goroSession
		if session.Step == "Attack" then
			session.Hits += 1
			if session.Hits >= ATTACK_HITS then
				advance(session, "Block")
			else
				send(session, "Attack", attackText(session.Hits))
			end
		elseif session.Step == "Heavy" then
			if hit.Action == "Heavy" or hit.GuardBreak == true or hit.Kind == "GuardBreak" then
				advance(session, "KO")
			end
		end
		task.defer(function()
			local goro = session.Goro
			if not goro or session.Finished then
				return
			end
			if session.Step == "KO" then
				checkGoroDown(session)
			elseif Util.HPFraction(goro) < GORO_MIN_HP_FRACTION and Services.CombatService then
				Services.CombatService.Revive(goro, GORO_REFILL_FRACTION)
			end
		end)
		return
	end
	-- Goro hits the player
	local attackerSession = if typeof(attackerModel) == "Instance" then goroOwners[attackerModel :: Model] else nil
	local target = Util.PlayerFromModel(targetModel)
	if attackerSession and target == attackerSession.Player then
		local session = attackerSession
		local character = targetModel :: Model
		local blocked = hit.Blocked == true or character:GetAttribute("Blocking") == true
		if session.Step == "Block" and blocked then
			advance(session, "Parry")
		end
		task.defer(function()
			if Util.HPFraction(character) < PLAYER_MIN_HP_FRACTION and Services.CombatService and character.Parent then
				Services.CombatService.Revive(character, PLAYER_REFILL_FRACTION)
			end
		end)
	end
end

local function onParried(defenderModel: any, attackerModel: any)
	local session = if typeof(attackerModel) == "Instance" then goroOwners[attackerModel :: Model] else nil
	if not session or Util.PlayerFromModel(defenderModel) ~= session.Player then
		return
	end
	if session.Step == "Parry" then
		advance(session, "Heavy")
	elseif session.Step == "Block" then
		-- A parry is a perfect block: count it and move on to the parry lesson's next step.
		advance(session, "Heavy")
	end
end

-- Remotes ---------------------------------------------------------------------

local function onPickStyle(player: Player, styleId: any): boolean
	if not limiter:Allow(player) then
		return false
	end
	local session = sessions[player]
	if not session or session.Step ~= "PickStyle" or session.Picked then
		return false
	end
	if type(styleId) ~= "string" or not table.find(StylesConfig.StarterIds, styleId) then
		return false
	end
	if not Services.StyleService then
		return false
	end
	Services.StyleService.GrantStyle(player, styleId)
	if not Services.StyleService.EquipStyle(player, styleId) then
		return false
	end
	session.Picked = true
	if Services.CombatService then
		Services.CombatService.RefreshStats(player)
	end
	session.Hits = 0
	send(session, "Attack", attackText(0))
	task.spawn(spawnGoro, session)
	return true
end

local function onSkip(player: Player)
	if not limiter:Allow(player) then
		return
	end
	local session = sessions[player]
	if session then
		finishSkipped(session)
	end
end

-- Public API -----------------------------------------------------------------

function TutorialService.IsInTutorial(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and not session.Finished and not session.Ended
end

function TutorialService.GetStep(player: Player): string?
	local session = sessions[player]
	return if session then session.Step else nil
end

-- Lifecycle --------------------------------------------------------------------

function TutorialService.Init(services: any)
	Services = services
	Net.Function("Tutorial_PickStyle").OnServerInvoke = onPickStyle
	Net.Event("Tutorial_Skip").OnServerEvent:Connect(onSkip)
end

function TutorialService.Start()
	if Services.CombatService then
		if Services.CombatService.HitLanded then
			Services.CombatService.HitLanded:Connect(onHitLanded)
		end
		if Services.CombatService.Parried then
			Services.CombatService.Parried:Connect(onParried)
		end
	end
	Players.PlayerAdded:Connect(function(player)
		begin(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(begin, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local session = sessions[player]
		if session then
			endSession(session)
		end
		limiter:Remove(player)
	end)
end

return TutorialService
