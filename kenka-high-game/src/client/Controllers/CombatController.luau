--!strict
-- Combat input, client prediction and cooldown state (blueprint section 1.4, input map in ARCHITECTURE.md).
-- The server decides every hit; this controller sends intent (Combat_Request), plays the local swing at once
-- through FXController, and moves the local character for Dash, Weave, lunges and knockback (the character's
-- physics belong to this client).
--
-- Public API (used by the HUD and the mobile buttons):
--   CombatController.Request(action) -> boolean    same as pressing the key ("BlockStart"/"BlockEnd" for block)
--   CombatController.CooldownChanged               Signal (action, endsAtClockTime)   os.clock() based
--   CombatController.GetCooldownRemaining(action) -> number
--   CombatController.IsInStance() -> boolean
--   CombatController.StanceChanged                 Signal (inStance: boolean)

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Animations = require(ReplicatedStorage.Shared.Config.Animations)
local Combat = require(ReplicatedStorage.Shared.Config.Combat)
local Styles = require(ReplicatedStorage.Shared.Config.Styles)
local CombatMath = require(ReplicatedStorage.Shared.Logic.CombatMath)
local Net = require(ReplicatedStorage.Shared.Util.Net)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Cleaner = require(ReplicatedStorage.Shared.Util.Cleaner)

local CombatController = {}
CombatController.Priority = 30

CombatController.CooldownChanged = Signal.new() -- (action, endsAtClockTime)
CombatController.StanceChanged = Signal.new() -- (inStance)

local Controllers: any
local localPlayer = Players.LocalPlayer
local Motion = Animations.Motion

local MOVE_THRESHOLD = 0.1 -- MoveDirection magnitude that counts as "moving" for Weave
local FORWARD_DOT = 0.5 -- a weave pressed forward turns into a sideways slip
local PROMPT_NAMES = { KO_Finish = true, KO_HelpUp = true }

local ACTIONS = {
	Stance = true,
	M1 = true,
	Heavy = true,
	BlockStart = true,
	BlockEnd = true,
	Dash = true,
	Weave = true,
	SprintStart = true,
	SprintEnd = true,
	Tech1 = true,
	Tech2 = true,
	Heat = true,
}
local TECH_SLOTS = { Tech1 = true, Tech2 = true, Heat = true }

local requestEvent: RemoteEvent
local cooldowns: { [string]: number } = {}
local inStance = false
local character: Model? = nil
local characterCleaner = Cleaner.new()
local moveCleaner = Cleaner.new()
local blockHeld = false
local sprintHeld = false
local comboIndex = 0
local lastM1 = -math.huge

-- State helpers --------------------------------------------------------------------------------------------
local function getHumanoid(): Humanoid?
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

local function getRoot(): BasePart?
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function attr(name: string): any
	return if character then character:GetAttribute(name) else nil
end

local function isStunned(): boolean
	local untilTime = attr("StunnedUntil")
	return type(untilTime) == "number" and untilTime > workspace:GetServerTimeNow()
end

local function isDowned(): boolean
	return attr("Downed") == true
end

local function currentStyle(): Styles.Style
	local id = localPlayer:GetAttribute("Style")
	return (if type(id) == "string" then Styles.Styles[id] else nil) or Styles.Styles[Styles.DefaultStyle]
end

local function setCooldown(action: string, seconds: number)
	local endsAt = os.clock() + seconds
	cooldowns[action] = endsAt
	CombatController.CooldownChanged:Fire(action, endsAt)
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function fx(): any
	return Controllers and Controllers.FXController
end

-- Movement (the local character is client-owned physics) --------------------------------------------------
local function push(velocity: Vector3, duration: number)
	local root = getRoot()
	if not root then
		return
	end
	moveCleaner:Clean()
	local attachment = moveCleaner:Add(Instance.new("Attachment"))
	attachment.Name = "KenkaMove"
	attachment.Parent = root
	local mover = moveCleaner:Add(Instance.new("LinearVelocity"))
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	mover.PrimaryTangentAxis = Vector3.xAxis
	mover.SecondaryTangentAxis = Vector3.zAxis
	mover.PlaneVelocity = Vector2.new(velocity.X, velocity.Z)
	mover.MaxForce = math.huge
	mover.Parent = root
	if velocity.Y > 0 then
		local current = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(current.X, velocity.Y, current.Z)
	end
	moveCleaner:Add(task.delay(duration, function()
		moveCleaner:Clean()
	end))
end

local function facing(): Vector3
	local root = getRoot()
	local look = if root then flat(root.CFrame.LookVector) else Vector3.zAxis
	return if look.Magnitude > 0.01 then look.Unit else Vector3.zAxis
end

local function moveDirection(): Vector3
	local humanoid = getHumanoid()
	local direction = if humanoid then flat(humanoid.MoveDirection) else Vector3.zero
	return direction
end

local function dashMove()
	local direction = moveDirection()
	direction = if direction.Magnitude > MOVE_THRESHOLD then direction.Unit else facing()
	push(direction * (Combat.DashDistance / Combat.DashDuration), Combat.DashDuration)
end

local function weaveMove()
	local direction = moveDirection()
	if direction.Magnitude <= MOVE_THRESHOLD then
		return
	end
	direction = direction.Unit
	local look = facing()
	if direction:Dot(look) > FORWARD_DOT then
		-- Weaves slip sideways or backward, never forward: pick the side the stick leans to.
		local right = look:Cross(Vector3.yAxis)
		direction = if direction:Dot(right) >= 0 then right else -right
	end
	push(direction * (Combat.WeaveDistance / Combat.WeaveIFrames), Combat.WeaveIFrames)
end

-- Requests -------------------------------------------------------------------------------------------------
local function send(action: string)
	requestEvent:FireServer(action, { Direction = facing() })
end

local function predictM1(): boolean
	local now = os.clock()
	if now - lastM1 < Combat.M1Interval then
		return false
	end
	if now - lastM1 > Combat.M1ComboReset then
		comboIndex = 0
	end
	comboIndex = (comboIndex % #Combat.M1Damage) + 1
	lastM1 = now
	local index = comboIndex
	if index == #Combat.M1Damage then
		comboIndex = 0
	end
	local controller = fx()
	if controller then
		controller.Predict("M1", { Index = index })
	end
	return true
end

function CombatController.Request(action: string): boolean
	if not ACTIONS[action] or not character then
		return false
	end
	if action == "BlockEnd" or action == "SprintEnd" then
		send(action)
		return true
	end
	if isDowned() then
		return false
	end
	if action ~= "Stance" then
		if not inStance or isStunned() then
			return false
		end
		if CombatController.GetCooldownRemaining(action) > 0 then
			return false
		end
	end

	local posture = attr("Posture")
	local postureValue = if type(posture) == "number" then posture else Combat.MaxPosture
	local style = currentStyle()
	local controller = fx()

	if action == "M1" then
		if attr("Blocking") == true or not predictM1() then
			return false
		end
	elseif action == "Heavy" then
		if attr("Blocking") == true then
			return false
		end
		comboIndex = 0
		if controller then
			controller.Predict("Heavy", { Windup = Combat.HeavyWindup })
		end
	elseif action == "Dash" then
		if postureValue < Combat.DashPostureCost or attr("Blocking") == true then
			return false
		end
		setCooldown("Dash", CombatMath.DashCooldown(Combat.DashCooldown, style.Passive, 0))
		dashMove()
		if controller then
			controller.Predict("Dash")
		end
	elseif action == "Weave" then
		if postureValue < Combat.WeavePostureCost or attr("Blocking") == true then
			return false
		end
		setCooldown("Weave", CombatMath.WeaveCooldown(Combat.WeaveCooldown, style.Passive))
		weaveMove()
		if controller then
			controller.Predict("Weave")
		end
	elseif TECH_SLOTS[action] then
		if attr("Blocking") == true then
			return false
		end
		if action == "Heat" then
			local heat = attr("Heat")
			if type(heat) ~= "number" or heat < Combat.MaxHeat then
				return false
			end
		end
		-- The server answers with the real cooldown; the technique animation plays when it confirms.
	end
	send(action)
	return true
end

function CombatController.GetCooldownRemaining(action: string): number
	local endsAt = cooldowns[action]
	return if endsAt then math.max(0, endsAt - os.clock()) else 0
end

function CombatController.IsInStance(): boolean
	return inStance
end

-- Character tracking ----------------------------------------------------------------------------------------
local function setStance(value: boolean)
	if inStance == value then
		return
	end
	inStance = value
	if not value then
		if blockHeld then
			blockHeld = false
			send("BlockEnd")
		end
		if sprintHeld then
			sprintHeld = false
			send("SprintEnd")
		end
	end
	CombatController.StanceChanged:Fire(value)
end

local function hidePrompt(instance: Instance)
	if instance:IsA("ProximityPrompt") and PROMPT_NAMES[instance.Name] then
		instance.Enabled = false -- our own Finish / Help Up prompts (local only)
	end
end

local function onCharacter(newCharacter: Model?)
	characterCleaner:Clean()
	moveCleaner:Clean()
	character = newCharacter
	comboIndex = 0
	blockHeld = false
	sprintHeld = false
	if not newCharacter then
		setStance(false)
		return
	end
	setStance(newCharacter:GetAttribute("Stance") == true)
	characterCleaner:Add(newCharacter:GetAttributeChangedSignal("Stance"):Connect(function()
		setStance(newCharacter:GetAttribute("Stance") == true)
	end))
	for _, descendant in newCharacter:GetDescendants() do
		hidePrompt(descendant)
	end
	characterCleaner:Add(newCharacter.DescendantAdded:Connect(hidePrompt))
end

-- Server messages -------------------------------------------------------------------------------------------
local function onFX(payload: any)
	if type(payload) ~= "table" or not character then
		return
	end
	if payload.Kind == "Knockback" then
		if typeof(payload.Velocity) == "Vector3" then
			local duration = tonumber(payload.Duration) or Motion.KnockbackDuration
			push(payload.Velocity, math.clamp(duration, 0, Motion.KnockbackDuration * 4))
		end
	elseif (payload.Kind == "Technique" or payload.Kind == "Heat") and payload.Attacker == character then
		local lunge = tonumber(payload.Lunge)
		if lunge and lunge > 0 then
			local duration = math.max(tonumber(payload.Windup) or 0, Motion.LungeMinDuration)
			push(facing() * (lunge / duration), duration)
		end
	end
end

-- Input ------------------------------------------------------------------------------------------------------
local function typing(): boolean
	return UserInputService:GetFocusedTextBox() ~= nil
end

local function onAction(actionName: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	local pass = Enum.ContextActionResult.Pass
	local sink = Enum.ContextActionResult.Sink
	if typing() then
		return pass
	end
	local began = state == Enum.UserInputState.Begin
	local ended = state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel

	if actionName == "KH_Stance" then
		if began then
			CombatController.Request("Stance")
		end
		return sink
	elseif actionName == "KH_Block" then
		if ended and blockHeld then
			blockHeld = false
			CombatController.Request("BlockEnd")
			return sink
		end
		if not inStance then
			return pass
		end
		if began then
			blockHeld = CombatController.Request("BlockStart")
		end
		return sink
	elseif actionName == "KH_Sprint" then
		if ended and sprintHeld then
			sprintHeld = false
			CombatController.Request("SprintEnd")
			return sink
		end
		if not inStance then
			return pass
		end
		if began then
			sprintHeld = CombatController.Request("SprintStart")
		end
		return sink
	elseif actionName == "KH_Weave" then
		-- Space jumps normally unless we're in stance and moving.
		if not began or not inStance or moveDirection().Magnitude <= MOVE_THRESHOLD then
			return pass
		end
		CombatController.Request("Weave")
		return sink
	end

	if not inStance then
		return pass -- left click etc. keep working outside of stance
	end
	if began then
		local map = {
			KH_M1 = "M1",
			KH_Heavy = "Heavy",
			KH_Dash = "Dash",
			KH_Tech1 = "Tech1",
			KH_Tech2 = "Tech2",
			KH_Heat = "Heat",
		}
		local action = map[actionName]
		if action then
			CombatController.Request(action)
		end
	end
	-- Right mouse also rotates the camera: let it through.
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		return pass
	end
	return sink
end

local function bind()
	local high = Enum.ContextActionPriority.High.Value
	ContextActionService:BindActionAtPriority("KH_Stance", onAction, false, high, Enum.KeyCode.T, Enum.KeyCode.ButtonY)
	ContextActionService:BindActionAtPriority("KH_M1", onAction, false, high, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)
	ContextActionService:BindActionAtPriority("KH_Heavy", onAction, false, high, Enum.UserInputType.MouseButton2, Enum.KeyCode.R, Enum.KeyCode.ButtonR1)
	ContextActionService:BindActionAtPriority("KH_Block", onAction, false, high, Enum.KeyCode.F, Enum.KeyCode.ButtonL2)
	ContextActionService:BindActionAtPriority("KH_Dash", onAction, false, high, Enum.KeyCode.Q, Enum.KeyCode.ButtonB)
	ContextActionService:BindActionAtPriority("KH_Sprint", onAction, false, high, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
	ContextActionService:BindActionAtPriority("KH_Weave", onAction, false, high, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
	ContextActionService:BindActionAtPriority("KH_Tech1", onAction, false, high, Enum.KeyCode.Z, Enum.KeyCode.DPadLeft)
	ContextActionService:BindActionAtPriority("KH_Tech2", onAction, false, high, Enum.KeyCode.X, Enum.KeyCode.DPadRight)
	ContextActionService:BindActionAtPriority("KH_Heat", onAction, false, high, Enum.KeyCode.G, Enum.KeyCode.ButtonL1)
end

-- Lifecycle --------------------------------------------------------------------------------------------------
function CombatController.Init(controllers: any)
	Controllers = controllers
	requestEvent = Net.Event("Combat_Request")
end

function CombatController.Start()
	Net.Event("Combat_Cooldown").OnClientEvent:Connect(function(action: any, seconds: any)
		if type(action) == "string" and type(seconds) == "number" and seconds >= 0 then
			setCooldown(action, seconds)
		end
	end)
	Net.Event("Combat_FX").OnClientEvent:Connect(onFX)

	localPlayer.CharacterAdded:Connect(onCharacter)
	localPlayer.CharacterRemoving:Connect(function(old)
		if character == old then
			onCharacter(nil)
		end
	end)
	if localPlayer.Character then
		onCharacter(localPlayer.Character)
	end
	bind()
end

return CombatController
