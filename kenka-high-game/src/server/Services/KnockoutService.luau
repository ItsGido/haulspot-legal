--!strict
-- Knockdowns (blueprint section 1.4): at 0 HP outside a duel a fighter is Downed for Combat.DownedDuration
-- seconds, crawling at Combat.DownedCrawlSpeed and unable to attack. Two server ProximityPrompts appear on
-- the downed fighter's HumanoidRootPart:
--   * "KO_Finish"  (V, hold Combat.FinishHoldTime): anyone allowed to hit the target. Sends players to the
--     Nurse (respawn after Combat.RespawnDelay) and shows them the KO screen. Interrupted by any hit taken.
--   * "KO_HelpUp"  (E, hold Combat.HelpUpHoldTime): crewmates and Roblox friends. Stands up at Combat.HelpUpHP.
-- Nobody acts within the downed time: the fighter recovers at Combat.RecoverHP with Combat.RecoverProtection
-- seconds of Protected. The fight result (Rep etc.) is decided at knockdown, not at the finish.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combat = require(ReplicatedStorage.Shared.Config.Combat)
local Net = require(ReplicatedStorage.Shared.Util.Net)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Cleaner = require(ReplicatedStorage.Shared.Util.Cleaner)

local KnockoutService = {}
KnockoutService.Priority = 31

KnockoutService.Downed = Signal.new() -- (targetModel, attackerModel?)
KnockoutService.Finished = Signal.new() -- (targetModel, attackerModel?)
KnockoutService.Recovered = Signal.new() -- (targetModel)
KnockoutService.FightEnded = Signal.new() -- (winner: Player, loser: Player, info)

local Services: any

local PROMPT_DISTANCE = 10 -- studs, same as the map's interactables
local PROMPT_DISTANCE_SLACK = 4 -- extra studs the server allows for latency
local DEFAULT_STAMP = "K.O."
local FINISH_PROMPT = "KO_Finish"
local HELP_PROMPT = "KO_HelpUp"

type DownState = {
	Model: Model,
	Victim: Player?,
	Attacker: Model?,
	AttackerPlayer: Player?,
	Cleaner: any,
	HoldStarted: { [Player]: number },
}

local states: { [Model]: DownState } = {}
local friendCache: { [string]: boolean } = {}

local fxEvent = Net.Event("Combat_FX")
local koScreenEvent = Net.Event("KO_Screen")

local function playerFromModel(model: Model?): Player?
	if not model then
		return nil
	end
	return Players:GetPlayerFromCharacter(model)
end

local function displayName(model: Model?): string
	if not model then
		return "Someone"
	end
	local player = playerFromModel(model)
	if player then
		return player.DisplayName
	end
	local attr = model:GetAttribute("DisplayName")
	return if type(attr) == "string" then attr else model.Name
end

local function rootOf(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function maxHP(model: Model): number
	local combat = Services.CombatService
	local value = if combat and combat.GetMaxHP then combat.GetMaxHP(model) else 0
	if value <= 0 then
		local attr = model:GetAttribute("MaxHP")
		value = if type(attr) == "number" and attr > 0 then attr else Combat.RecoverHP
	end
	return value
end

local function clearState(model: Model): DownState?
	local state = states[model]
	if not state then
		return nil
	end
	states[model] = nil
	state.Cleaner:Clean()
	return state
end

local function withinPromptRange(player: Player, model: Model): Model?
	local character = player.Character
	local root = character and rootOf(character)
	local targetRoot = rootOf(model)
	if not character or not root or not targetRoot then
		return nil
	end
	if (root.Position - targetRoot.Position).Magnitude > PROMPT_DISTANCE + PROMPT_DISTANCE_SLACK then
		return nil
	end
	if character:GetAttribute("Downed") == true or states[character] then
		return nil
	end
	return character
end

local function areFriends(a: Player, b: Player): boolean
	local low, high = math.min(a.UserId, b.UserId), math.max(a.UserId, b.UserId)
	local key = low .. "_" .. high
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

local function mayHelp(helper: Player, victim: Player): boolean
	if helper == victim then
		return false
	end
	local crews = Services.CrewService
	if crews and crews.AreCrewmates and crews.AreCrewmates(helper, victim) then
		return true
	end
	return areFriends(helper, victim)
end

-- Stand-up paths ---------------------------------------------------------------------------------------
local function standUp(state: DownState, hp: number, protect: boolean)
	local model = state.Model
	clearState(model)
	if model.Parent == nil then
		return
	end
	if Services.CombatService then
		Services.CombatService.Revive(model, hp / maxHP(model))
		if Services.CombatService.RefreshMovement then
			Services.CombatService.RefreshMovement(model)
		end
	else
		model:SetAttribute("Downed", false)
	end
	if protect then
		model:SetAttribute("Protected", true)
		task.delay(Combat.RecoverProtection, function()
			if model.Parent and not states[model] then
				model:SetAttribute("Protected", false)
			end
		end)
	end
	KnockoutService.Recovered:Fire(model)
end

-- Finished: by a finisher, by leaving the game, or by the character disappearing.
local function finish(state: DownState, finisher: Model?, showScreen: boolean)
	local model = state.Model
	clearState(model)
	local root = rootOf(model)
	fxEvent:FireAllClients({
		Kind = "Finish",
		Attacker = finisher,
		Target = model,
		Position = if root then root.Position else nil,
	})
	KnockoutService.Finished:Fire(model, finisher)

	local victim = state.Victim
	if victim then
		if Services.MapService then
			Services.MapService.SetNextSpawn(victim, "NurseRespawn")
		end
		if victim.Parent ~= Players then
			return
		end
		if showScreen then
			local finisherPlayer = playerFromModel(finisher)
			local stamp = DEFAULT_STAMP
			local cosmetics = Services.CosmeticsService
			if finisherPlayer and cosmetics and cosmetics.GetKOStamp then
				local ok, result = pcall(cosmetics.GetKOStamp, finisherPlayer)
				if ok and type(result) == "string" and result ~= "" then
					stamp = result
				end
			end
			koScreenEvent:FireClient(victim, {
				KillerName = displayName(finisher),
				Stamp = stamp,
				RespawnIn = Combat.RespawnDelay,
			})
		end
		task.delay(Combat.RespawnDelay, function()
			if victim.Parent ~= Players then
				return
			end
			local character = victim.Character
			if character == nil or character == model then
				pcall(function()
					victim:LoadCharacterAsync()
				end)
			end
		end)
	else
		local npcs = Services.NPCService
		if npcs and npcs.OnFinished then
			task.spawn(npcs.OnFinished, model)
		end
	end
end

-- Prompts ------------------------------------------------------------------------------------------------
local function makePrompt(parent: BasePart, name: string, action: string, object: string, key: Enum.KeyCode, pad: Enum.KeyCode, hold: number): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.KeyboardKeyCode = key
	prompt.GamepadKeyCode = pad
	prompt.HoldDuration = hold
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OneGlobally
	prompt.Parent = parent
	return prompt
end

local function onFinishTriggered(state: DownState, player: Player)
	if states[state.Model] ~= state then
		return
	end
	local character = withinPromptRange(player, state.Model)
	if not character or character == state.Model then
		return
	end
	local combat = Services.CombatService
	if not combat or not combat.CanHit(character, state.Model, true) then
		return
	end
	-- Any hit taken while holding interrupts the finish.
	local started = state.HoldStarted[player] or (os.clock() - Combat.FinishHoldTime)
	state.HoldStarted[player] = nil
	if combat.GetLastHitTakenAt(character) >= started then
		return
	end
	finish(state, character, true)
end

local function onHelpTriggered(state: DownState, player: Player)
	if states[state.Model] ~= state then
		return
	end
	local victim = state.Victim
	local character = withinPromptRange(player, state.Model)
	if not victim or not character or not mayHelp(player, victim) then
		return
	end
	if states[state.Model] ~= state then
		return -- finished or recovered while we checked friendship
	end
	standUp(state, Combat.HelpUpHP, false)
end

-- Public API ---------------------------------------------------------------------------------------------
function KnockoutService.OnZeroHP(targetModel: Model, attackerModel: Model?)
	if states[targetModel] or targetModel.Parent == nil then
		return
	end
	local root = rootOf(targetModel)
	if not root then
		return
	end
	local victim = playerFromModel(targetModel)
	local attackerPlayer = playerFromModel(attackerModel)
	local state: DownState = {
		Model = targetModel,
		Victim = victim,
		Attacker = attackerModel,
		AttackerPlayer = attackerPlayer,
		Cleaner = Cleaner.new(),
		HoldStarted = {},
	}
	states[targetModel] = state

	targetModel:SetAttribute("Downed", true)
	targetModel:SetAttribute("HP", 0)
	local combat = Services.CombatService
	if combat then
		if combat.SetStance then
			combat.SetStance(targetModel, false)
		end
		if combat.RefreshMovement then
			combat.RefreshMovement(targetModel)
		end
	end

	fxEvent:FireAllClients({
		Kind = "Knockdown",
		Attacker = attackerModel,
		Target = targetModel,
		KO = true,
		Duration = Combat.DownedDuration,
		Position = root.Position,
	})
	KnockoutService.Downed:Fire(targetModel, attackerModel)

	-- The fight result is decided now.
	if victim and attackerPlayer and victim ~= attackerPlayer then
		local info = {
			Kind = "Open",
			WinnerHits = if combat then combat.GetHits(attackerModel, targetModel) else 0,
			LoserHits = if combat then combat.GetHits(targetModel, attackerModel) else 0,
		}
		KnockoutService.FightEnded:Fire(attackerPlayer, victim, info)
		local rep = Services.RepService
		if rep and rep.FightResult then
			task.spawn(rep.FightResult, attackerPlayer, victim, info)
		end
	end

	local name = displayName(targetModel)
	local finishPrompt = state.Cleaner:Add(
		makePrompt(root, FINISH_PROMPT, "Finish", name, Enum.KeyCode.V, Enum.KeyCode.ButtonY, Combat.FinishHoldTime)
	)
	state.Cleaner:Add(finishPrompt.PromptButtonHoldBegan:Connect(function(player: Player)
		state.HoldStarted[player] = os.clock()
	end))
	state.Cleaner:Add(finishPrompt.PromptButtonHoldEnded:Connect(function(player: Player)
		task.defer(function()
			state.HoldStarted[player] = nil
		end)
	end))
	state.Cleaner:Add(finishPrompt.Triggered:Connect(function(player: Player)
		onFinishTriggered(state, player)
	end))
	if victim then
		local helpPrompt = state.Cleaner:Add(
			makePrompt(root, HELP_PROMPT, "Help Up", name, Enum.KeyCode.E, Enum.KeyCode.ButtonX, Combat.HelpUpHoldTime)
		)
		state.Cleaner:Add(helpPrompt.Triggered:Connect(function(player: Player)
			onHelpTriggered(state, player)
		end))
	end

	-- Nobody finished them in time: recover.
	state.Cleaner:Add(task.delay(Combat.DownedDuration, function()
		if states[targetModel] == state then
			standUp(state, Combat.RecoverHP, true)
		end
	end))

	-- The character disappearing (reset, removed) counts as finished.
	state.Cleaner:Add(targetModel.AncestryChanged:Connect(function(_, parent)
		if parent == nil and states[targetModel] == state then
			task.defer(finish, state, state.Attacker, false)
		end
	end))
end

function KnockoutService.IsDowned(model: Model): boolean
	return states[model] ~= nil
end

-- Drops the downed state without any signal (CombatService.Revive calls this).
function KnockoutService.Cancel(model: Model)
	if clearState(model) and model.Parent then
		model:SetAttribute("Downed", false)
	end
end

-- Lifecycle ------------------------------------------------------------------------------------------------
function KnockoutService.Init(services: any)
	Services = services
end

function KnockoutService.Start()
	Players.PlayerRemoving:Connect(function(player: Player)
		for _, state in states do
			if state.Victim == player then
				-- Leaving while downed counts as finished.
				finish(state, state.Attacker, false)
			else
				if state.AttackerPlayer == player then
					state.AttackerPlayer = nil
					state.Attacker = nil
				end
				state.HoldStarted[player] = nil
			end
		end
		local prefix, suffix = player.UserId .. "_", "_" .. player.UserId
		for key in friendCache do
			if key:sub(1, #prefix) == prefix or key:sub(-#suffix) == suffix then
				friendCache[key] = nil
			end
		end
	end)
end

return KnockoutService
