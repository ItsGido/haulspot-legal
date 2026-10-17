--!strict
-- AI fighters: dojo dummies, the tutorial opponent and sparring partners.
--   NPCService.SpawnFighter({ Name, Mode = "Dummy"|"Tutorial"|"Sparring", CFrame, HeightCm?, Style?, MaxHP?,
--                             Owner: Player?, IgnoreZones: boolean?, Respawn: boolean? }) -> Model
--   NPCService.Despawn(model)
-- NPCs are registered with CombatService.RegisterFighter and attack through CombatService.PerformAction,
-- the same validated code path players use, so hits, parries, signals and FX behave identically.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combat = require(ReplicatedStorage.Shared.Config.Combat)
local UITheme = require(ReplicatedStorage.Shared.Config.UITheme)
local HeightStats = require(ReplicatedStorage.Shared.Logic.HeightStats)
local MapData = require(ReplicatedStorage.Shared.Map.MapData)
local Cleaner = require(ReplicatedStorage.Shared.Util.Cleaner)

local NPCService = {}
NPCService.Priority = 40

local Services: any

-- AI tuning -------------------------------------------------------------------------------------------------
type Brain = {
	M1Damage: number,
	M1Interval: number, -- seconds between light attacks
	HeavyDamage: number,
	HeavyEvery: number, -- seconds between telegraphed heavies
	Telegraph: number, -- seconds the "!" shows before the heavy lands (the heavy's windup)
	MinTargetHP: number?, -- never takes the target below this (tutorial can't be lost)
}

local BRAINS: { [string]: Brain } = {
	Tutorial = { M1Damage = 2, M1Interval = 1.1, HeavyDamage = 8, HeavyEvery = 3, Telegraph = 0.8, MinTargetHP = 10 },
	Sparring = { M1Damage = 3, M1Interval = 0.75, HeavyDamage = 10, HeavyEvery = 2.5, Telegraph = 0.6, MinTargetHP = nil },
}

local AI_TICK = 0.15
local DUMMY_TICK = 1
local ENGAGE_RANGE = Combat.M1Range * 0.8 -- start attacking inside this distance (inside the M1 reach)
local STANDOFF = Combat.M1Range * 0.5 -- where the NPC tries to stand relative to its target
local FINISH_DESPAWN_DELAY = Combat.FinishHoldTime
local GROUND_RAY_UP = 6
local GROUND_RAY_DOWN = 120
local LABEL_HEIGHT = 2.6
local NPC_FOLDER_NAME = "KenkaNPCs"

export type SpawnOpts = {
	Name: string?,
	Mode: string?,
	CFrame: CFrame?,
	HeightCm: number?,
	Style: string?,
	MaxHP: number?,
	Owner: Player?,
	IgnoreZones: boolean?,
	Respawn: boolean?,
}

type NPC = {
	Model: Model,
	Opts: SpawnOpts,
	Mode: string,
	Home: CFrame,
	Cleaner: any,
}

local npcs: { [Model]: NPC } = {}
local folder: Folder? = nil

local function getFolder(): Folder
	local current = folder
	if current and current.Parent then
		return current
	end
	local existing = workspace:FindFirstChild(NPC_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		folder = existing
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = NPC_FOLDER_NAME
	created.Parent = workspace
	folder = created
	return created
end

-- Rigs ------------------------------------------------------------------------------------------------------
local function part(name: string, size: Vector3, parent: Instance, color: Color3?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color or Color3.fromRGB(230, 200, 170)
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function motor(name: string, part0: BasePart, part1: BasePart, c0: CFrame, c1: CFrame)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = c0
	m.C1 = c1
	m.Parent = part0
end

-- A plain R6 rig built from parts, used when CreateHumanoidModelFromDescription is unavailable.
local function buildFallbackRig(): Model
	local model = Instance.new("Model")
	local root = part("HumanoidRootPart", Vector3.new(2, 2, 1), model)
	root.Transparency = 1
	local torso = part("Torso", Vector3.new(2, 2, 1), model, Color3.fromRGB(40, 44, 60))
	local head = part("Head", Vector3.new(2, 1, 1), model)
	local rightArm = part("Right Arm", Vector3.new(1, 2, 1), model)
	local leftArm = part("Left Arm", Vector3.new(1, 2, 1), model)
	local rightLeg = part("Right Leg", Vector3.new(1, 2, 1), model, Color3.fromRGB(30, 30, 36))
	local leftLeg = part("Left Leg", Vector3.new(1, 2, 1), model, Color3.fromRGB(30, 30, 36))
	local rootC = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
	motor("RootJoint", root, torso, rootC, rootC)
	motor("Neck", torso, head, CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0))
	motor("Right Shoulder", torso, rightArm, CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))
	motor("Left Shoulder", torso, leftArm, CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0))
	motor("Right Hip", torso, rightLeg, CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))
	motor("Left Hip", torso, leftLeg, CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0))
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.Parent = model
	Instance.new("Animator").Parent = humanoid
	model.PrimaryPart = root
	return model
end

local function buildRig(heightCm: number?): Model
	local ok, result = pcall(function()
		local description = Instance.new("HumanoidDescription")
		if heightCm then
			local scale = HeightStats.Get(heightCm).Scale
			description.HeightScale = scale
			description.WidthScale = scale
			description.DepthScale = scale
			description.HeadScale = scale
		end
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if ok and typeof(result) == "Instance" and result:IsA("Model") then
		local model = result :: Model
		-- A server NPC can't use the client Animate script; FXController animates fighters procedurally.
		local animate = model:FindFirstChild("Animate")
		if animate then
			animate:Destroy()
		end
		return model
	end
	warn("[NPCService] CreateHumanoidModelFromDescription failed, using a part rig: " .. tostring(result))
	return buildFallbackRig()
end

local function addLabel(model: Model, text: string)
	local head = model:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "NPCName"
	gui.Size = UDim2.fromScale(4, 0.8)
	gui.StudsOffsetWorldSpace = Vector3.new(0, LABEL_HEIGHT, 0)
	gui.MaxDistance = 80
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = UITheme.Fonts.Title
	label.TextColor3 = Color3.fromHex(UITheme.Paper)
	label.TextStrokeTransparency = 0
	label.Parent = gui
	gui.Parent = head
end

-- "!" above the head while a heavy winds up.
local function telegraph(model: Model, seconds: number)
	local head = model:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "Telegraph"
	gui.Size = UDim2.fromScale(1.6, 1.6)
	gui.StudsOffsetWorldSpace = Vector3.new(0, LABEL_HEIGHT + 1.6, 0)
	gui.AlwaysOnTop = true
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "!"
	label.TextScaled = true
	label.Font = UITheme.Fonts.Title
	label.TextColor3 = Color3.fromHex(UITheme.Zones.Red)
	label.TextStrokeTransparency = 0
	label.Parent = gui
	gui.Parent = head
	task.delay(seconds, function()
		gui:Destroy()
	end)
end

-- Put the model's feet on the ground under cframe.
local function place(model: Model, cframe: CFrame)
	model:PivotTo(cframe)
	local boxCFrame, size = model:GetBoundingBox()
	local bottom = boxCFrame.Position.Y - size.Y / 2
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { model, getFolder() }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	params.FilterDescendantsInstances = exclude
	local origin = cframe.Position + Vector3.new(0, GROUND_RAY_UP, 0)
	local hit = workspace:Raycast(origin, Vector3.new(0, -GROUND_RAY_DOWN, 0), params)
	local groundY = if hit then hit.Position.Y else cframe.Position.Y
	model:PivotTo(cframe + Vector3.new(0, groundY - bottom, 0))
end

-- Brains ------------------------------------------------------------------------------------------------------
local function alive(npc: NPC): boolean
	return npcs[npc.Model] == npc and npc.Model.Parent ~= nil
end

local function fighterBrain(npc: NPC, brain: Brain)
	local model = npc.Model
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return
	end
	local combat = Services.CombatService
	local lastM1 = 0
	local lastHeavy = os.clock()
	while alive(npc) do
		task.wait(AI_TICK)
		if not alive(npc) then
			break
		end
		local owner = npc.Opts.Owner
		if owner and owner.Parent ~= Players then
			NPCService.Despawn(model)
			break
		end
		local character = owner and owner.Character
		local targetRoot = character and character:FindFirstChild("HumanoidRootPart")
		local idle = model:GetAttribute("Downed") == true or combat.IsStunned(model)
		if
			idle
			or not character
			or not targetRoot
			or not targetRoot:IsA("BasePart")
			or character:GetAttribute("Downed") == true
			or not combat.CanHit(model, character)
		then
			humanoid:Move(Vector3.zero)
			continue
		end
		local targetPart = targetRoot :: BasePart
		local offset = Vector3.new(targetPart.Position.X - root.Position.X, 0, targetPart.Position.Z - root.Position.Z)
		local distance = offset.Magnitude
		if distance > ENGAGE_RANGE then
			if not combat.IsBusy(model) then
				local direction = if distance > 0.01 then offset.Unit else Vector3.zAxis
				humanoid:MoveTo(targetPart.Position - direction * STANDOFF)
			end
			continue
		end
		humanoid:Move(Vector3.zero)
		if distance > 0.01 then
			root.CFrame = CFrame.lookAt(root.Position, root.Position + offset)
		end
		if combat.IsBusy(model) then
			continue
		end
		local now = os.clock()
		if now - lastHeavy >= brain.HeavyEvery then
			lastHeavy = now
			if combat.PerformAction(model, "Heavy", { Damage = brain.HeavyDamage, Windup = brain.Telegraph, MinTargetHP = brain.MinTargetHP }) then
				telegraph(model, brain.Telegraph)
				lastM1 = now
			end
		elseif now - lastM1 >= brain.M1Interval then
			lastM1 = now
			combat.PerformAction(model, "M1", { Damage = brain.M1Damage, MinTargetHP = brain.MinTargetHP })
		end
	end
end

local function dummyBrain(npc: NPC)
	local model = npc.Model
	while alive(npc) do
		task.wait(DUMMY_TICK)
		if not alive(npc) then
			break
		end
		local hp = model:GetAttribute("HP")
		if type(hp) == "number" and hp <= 0 and Services.CombatService then
			Services.CombatService.Revive(model, 1)
		end
	end
end

-- Public API ----------------------------------------------------------------------------------------------------
function NPCService.SpawnFighter(opts: SpawnOpts): Model
	local mode = opts.Mode or "Dummy"
	local name = opts.Name or "Fighter"
	local model = buildRig(opts.HeightCm)
	model.Name = name
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.BreakJointsOnDeath = false
		humanoid.RequiresNeck = false
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	local home = opts.CFrame or CFrame.new()
	place(model, home)
	if root and root:IsA("BasePart") and mode == "Dummy" then
		root.Anchored = true
	end
	addLabel(model, name)
	model.Parent = getFolder()
	if root and root:IsA("BasePart") and not root.Anchored then
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
	end

	local npc: NPC = {
		Model = model,
		Opts = opts,
		Mode = mode,
		Home = model:GetPivot(),
		Cleaner = Cleaner.new(),
	}
	npcs[model] = npc
	npc.Cleaner:Add(model.AncestryChanged:Connect(function(_, parent)
		if parent == nil and npcs[model] == npc then
			npcs[model] = nil
			npc.Cleaner:Clean()
		end
	end))

	if Services.CombatService then
		Services.CombatService.RegisterFighter(model, {
			IsNPC = true,
			Owner = opts.Owner,
			IgnoreZones = opts.IgnoreZones,
			Dummy = mode == "Dummy",
			HeightCm = opts.HeightCm,
			Style = opts.Style,
			MaxHP = opts.MaxHP,
			DisplayName = name,
			Mode = mode,
		})
	end

	local brain = BRAINS[mode]
	if brain then
		npc.Cleaner:Add(task.spawn(fighterBrain, npc, brain))
	else
		npc.Cleaner:Add(task.spawn(dummyBrain, npc))
	end
	return model
end

function NPCService.Despawn(model: Model)
	local npc = npcs[model]
	npcs[model] = nil
	if npc then
		npc.Cleaner:Clean()
	end
	if Services.CombatService then
		Services.CombatService.UnregisterFighter(model)
	end
	if model.Parent then
		model:Destroy()
	end
end

function NPCService.IsNPC(model: Model): boolean
	return npcs[model] ~= nil
end

-- KnockoutService calls this when an NPC is finished: respawning NPCs stand back up at home, others leave.
function NPCService.OnFinished(model: Model)
	local npc = npcs[model]
	if not npc then
		return
	end
	if npc.Opts.Respawn or npc.Mode == "Dummy" then
		task.delay(Combat.RespawnDelay, function()
			if npcs[model] ~= npc then
				return
			end
			model:PivotTo(npc.Home)
			if Services.CombatService then
				Services.CombatService.Revive(model, 1)
			end
		end)
	else
		task.delay(FINISH_DESPAWN_DELAY, function()
			if npcs[model] == npc then
				NPCService.Despawn(model)
			end
		end)
	end
end

-- Lifecycle -------------------------------------------------------------------------------------------------------
function NPCService.Init(services: any)
	Services = services
end

function NPCService.Start()
	-- Dojo dummies: use the map's DummySpawns parts if present (art pass), otherwise MapData.
	local positions: { Vector3 } = {}
	local map = Services.MapService and Services.MapService.GetMapFolder()
	local spawns = map and map:FindFirstChild("DummySpawns")
	if spawns then
		for _, spot in spawns:GetChildren() do
			if spot:IsA("BasePart") then
				table.insert(positions, spot.Position)
			end
		end
	end
	if #positions == 0 then
		for _, pos in MapData.Dummies do
			table.insert(positions, Vector3.new(pos[1], 0, pos[2]))
		end
	end
	for i, position in positions do
		local ok, err = pcall(NPCService.SpawnFighter, {
			Name = "Training Dummy",
			Mode = "Dummy",
			CFrame = CFrame.lookAt(position, position + Vector3.zAxis),
			Respawn = true,
		})
		if not ok then
			warn(string.format("[NPCService] Dummy %d failed to spawn: %s", i, tostring(err)))
		end
	end
end

return NPCService
