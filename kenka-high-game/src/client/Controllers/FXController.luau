--!strict
-- Combat visuals for every fighter (blueprint section 4.5).
--   * Animations: Config/Animations ids when set, otherwise procedural poses made by blending Motor6D C0s
--     (R15: shoulders, elbows, hips, waist, root; R6: the Torso joints and RootJoint). Persistent poses follow
--     the fighter's attributes (Stance, Blocking, Downed); one-shot clips play on Combat_FX (Swing, Technique,
--     Heat, Dash, Weave, Finish). Every C0 is restored when the fighter goes away.
--   * Hit sparks, damage numbers (Settings.DamageNumbers), camera shake and hit-stop (Settings.CameraShake),
--     the parry flash and stamps, the Heat FOV zoom, and sounds through Kit.PlaySound.
--   FXController.Predict(action, index?, technique?) plays the local player's swing immediately; the matching
--   server Swing for the local character is then skipped.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Animations = require(ReplicatedStorage.Shared.Config.Animations)
local Combat = require(ReplicatedStorage.Shared.Config.Combat)
local UITheme = require(ReplicatedStorage.Shared.Config.UITheme)
local Net = require(ReplicatedStorage.Shared.Util.Net)
local Cleaner = require(ReplicatedStorage.Shared.Util.Cleaner)
local Kit = require(script.Parent.Parent.UI.Kit)

local FXController = {}
FXController.Priority = 20

local Controllers: any
local localPlayer = Players.LocalPlayer
local FX = Animations.FX

local FIGHTER_TAG = "Fighter"
local PREDICT_WINDOW = 0.5 -- seconds: a server Swing this soon after a local prediction is a duplicate
local HOLD_TIME = 0.05 -- seconds a strike pose holds at full extension
local SPARK_SIZE = 0.35
local NUMBER_SIZE = UDim2.fromScale(3, 1.2) -- studs (BillboardGui scale)
local STAMP_SIZE = UDim2.fromScale(0.6, 0.18)
local STAMP_POP_SCALE = 1.6
local STAMP_POP_TIME = 0.15
local FX_DISPLAY_ORDER = 40

local rad = math.rad
local IDENTITY = CFrame.identity

-- Poses ----------------------------------------------------------------------------------------------------
-- Offsets are rotations around each joint in its parent part's space (X right, Y up, -Z forward).
type Pose = { [string]: CFrame }

local POSES: { [string]: Pose } = {
	Stance = {
		RightArm = CFrame.Angles(rad(75), 0, rad(-20)),
		LeftArm = CFrame.Angles(rad(85), 0, rad(20)),
		RightForearm = CFrame.Angles(rad(70), 0, 0),
		LeftForearm = CFrame.Angles(rad(80), 0, 0),
		Torso = CFrame.Angles(0, rad(-15), 0),
		RightLeg = CFrame.Angles(0, 0, rad(8)),
		LeftLeg = CFrame.Angles(0, 0, rad(-8)),
	},
	Block = {
		RightArm = CFrame.Angles(rad(115), 0, rad(-35)),
		LeftArm = CFrame.Angles(rad(115), 0, rad(35)),
		RightForearm = CFrame.Angles(rad(100), 0, 0),
		LeftForearm = CFrame.Angles(rad(100), 0, 0),
		Torso = CFrame.Angles(rad(-8), 0, 0),
	},
	Downed = {
		Root = CFrame.new(0, -FX.DownedDrop, 0) * CFrame.Angles(rad(-80), 0, 0),
		RightArm = CFrame.Angles(rad(150), 0, rad(-15)),
		LeftArm = CFrame.Angles(rad(130), 0, rad(15)),
		RightLeg = CFrame.Angles(rad(-10), 0, 0),
		LeftLeg = CFrame.Angles(rad(10), 0, 0),
	},
}

-- Joint discovery: logical name -> { part name, motor name } for each rig type.
local R15_JOINTS: { [string]: { string } } = {
	RightArm = { "RightUpperArm", "RightShoulder" },
	LeftArm = { "LeftUpperArm", "LeftShoulder" },
	RightForearm = { "RightLowerArm", "RightElbow" },
	LeftForearm = { "LeftLowerArm", "LeftElbow" },
	RightLeg = { "RightUpperLeg", "RightHip" },
	LeftLeg = { "LeftUpperLeg", "LeftHip" },
	Torso = { "UpperTorso", "Waist" },
	Root = { "LowerTorso", "Root" },
}
local R6_JOINTS: { [string]: { string } } = {
	RightArm = { "Torso", "Right Shoulder" },
	LeftArm = { "Torso", "Left Shoulder" },
	RightLeg = { "Torso", "Right Hip" },
	LeftLeg = { "Torso", "Left Hip" },
	Torso = { "HumanoidRootPart", "RootJoint" },
	Root = { "HumanoidRootPart", "RootJoint" },
}
-- R6 has one joint for both Torso and Root; apply Root first, then the torso twist.
local JOINT_ORDER = { "Root", "Torso", "RightArm", "LeftArm", "RightForearm", "LeftForearm", "RightLeg", "LeftLeg" }

type Keyframe = { T: number, Pose: Pose }
type Clip = { Keys: { Keyframe }, Start: number, Duration: number }

type Rig = {
	Model: Model,
	Motors: { [string]: Motor6D },
	Base: { [Motor6D]: CFrame },
	Current: Pose, -- smoothed persistent pose
	Clip: Clip?,
	Tracks: { [number]: AnimationTrack },
	Loops: { [string]: AnimationTrack },
	Settled: boolean,
	Cleaner: any,
	NextDiscover: number,
}

local rigs: { [Model]: Rig } = {}
local predicted: { [string]: number } = {}
local fxGui: ScreenGui? = nil

-- Settings -----------------------------------------------------------------------------------------------------
local function setting(name: string): boolean
	local data = Controllers and Controllers.DataController
	local settings = data and data.Get("Settings")
	if type(settings) == "table" and settings[name] == false then
		return false
	end
	return true
end

local function localCharacter(): Model?
	return localPlayer.Character
end

local function involved(payload: any): boolean
	local character = localCharacter()
	return character ~= nil and (payload.Attacker == character or payload.Target == character)
end

-- Rigs ----------------------------------------------------------------------------------------------------------
local function discover(rig: Rig)
	local humanoid = rig.Model:FindFirstChildOfClass("Humanoid")
	local map: { [string]: { string } } = if humanoid and humanoid.RigType == Enum.HumanoidRigType.R6 then R6_JOINTS else R15_JOINTS
	for name, path in map do
		if not rig.Motors[name] then
			local holder = rig.Model:FindFirstChild(path[1])
			local motor = holder and holder:FindFirstChild(path[2])
			if motor and motor:IsA("Motor6D") then
				rig.Motors[name] = motor
				if not rig.Base[motor] then
					rig.Base[motor] = motor.C0
				end
			end
		end
	end
	rig.NextDiscover = os.clock() + 1
end

local function restore(rig: Rig)
	for motor, base in rig.Base do
		if motor.Parent then
			motor.C0 = base
		end
	end
end

local function getAnimator(model: Model): Animator?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return humanoid and humanoid:FindFirstChildOfClass("Animator")
end

local function getTrack(rig: Rig, id: number): AnimationTrack?
	local track = rig.Tracks[id]
	if track then
		return track
	end
	local animator = getAnimator(rig.Model)
	if not animator then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. id
	local ok, loaded = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	animation:Destroy()
	if ok and loaded then
		rig.Tracks[id] = loaded
		rig.Cleaner:Add(function()
			loaded:Stop(0)
			loaded:Destroy()
		end)
		return loaded
	end
	return nil
end

local function removeRig(model: Model)
	local rig = rigs[model]
	if not rig then
		return
	end
	rigs[model] = nil
	rig.Cleaner:Clean()
	restore(rig)
end

local function updateLoops(rig: Rig)
	local model = rig.Model
	local wanted: { [string]: boolean } = {
		Downed = model:GetAttribute("Downed") == true,
		Block = model:GetAttribute("Blocking") == true and model:GetAttribute("Downed") ~= true,
		StanceIdle = model:GetAttribute("Stance") == true,
	}
	for name, on in wanted do
		local id = (Animations :: any)[name]
		if type(id) == "number" and id ~= 0 then
			local track = rig.Loops[name] or getTrack(rig, id)
			if track then
				rig.Loops[name] = track
				track.Looped = true
				if on and not track.IsPlaying then
					track:Play()
				elseif not on and track.IsPlaying then
					track:Stop()
				end
			end
		end
	end
	rig.Settled = false
end

local function addRig(model: Model)
	if rigs[model] or not model:IsA("Model") then
		return
	end
	local rig: Rig = {
		Model = model,
		Motors = {},
		Base = {},
		Current = {},
		Clip = nil,
		Tracks = {},
		Loops = {},
		Settled = false,
		Cleaner = Cleaner.new(),
		NextDiscover = 0,
	}
	rigs[model] = rig
	discover(rig)
	for _, attr in { "Stance", "Blocking", "Downed" } do
		rig.Cleaner:Add(model:GetAttributeChangedSignal(attr):Connect(function()
			updateLoops(rig)
		end))
	end
	rig.Cleaner:Add(model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			removeRig(model)
		end
	end))
	updateLoops(rig)
end

-- The pose a rig should hold from its attributes (procedural only when no looping id is set).
local function persistentPose(model: Model): Pose?
	if model:GetAttribute("Downed") == true then
		return if Animations.Downed == 0 then POSES.Downed else nil
	end
	if model:GetAttribute("Blocking") == true then
		return if Animations.Block == 0 then POSES.Block else nil
	end
	if model:GetAttribute("Stance") == true then
		return if Animations.StanceIdle == 0 then POSES.Stance else nil
	end
	return nil
end

local function evaluateClip(clip: Clip, now: number, joint: string, persistent: CFrame): CFrame
	local t = now - clip.Start
	local keys = clip.Keys
	local function value(key: Keyframe): CFrame
		return key.Pose[joint] or persistent
	end
	if t <= keys[1].T then
		return value(keys[1])
	end
	for i = 1, #keys - 1 do
		local a, b = keys[i], keys[i + 1]
		if t <= b.T then
			local span = b.T - a.T
			local alpha = if span > 0 then (t - a.T) / span else 1
			alpha = alpha * alpha * (3 - 2 * alpha) -- smoothstep
			return value(a):Lerp(value(b), alpha)
		end
	end
	return value(keys[#keys])
end

local function stepRig(rig: Rig, now: number, dt: number, cameraPosition: Vector3)
	local model = rig.Model
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	if (root.Position - cameraPosition).Magnitude > FX.PoseMaxDistance then
		return
	end
	if now >= rig.NextDiscover then
		local missing = false
		for _, name in JOINT_ORDER do
			if not rig.Motors[name] then
				missing = true
				break
			end
		end
		if missing then
			discover(rig)
		end
	end

	local clip = rig.Clip
	if clip and now - clip.Start > clip.Duration then
		rig.Clip = nil
		clip = nil
	end
	local target = persistentPose(model)
	if not clip and rig.Settled and target == nil then
		return
	end

	local alpha = 1 - math.exp(-FX.PoseSmoothing * dt)
	local settled = clip == nil
	local perMotor: { [Motor6D]: CFrame } = {}
	for _, name in JOINT_ORDER do
		local motor = rig.Motors[name]
		if motor then
			local goal = if target then target[name] or IDENTITY else IDENTITY
			local current = rig.Current[name] or IDENTITY
			local nextPose = current:Lerp(goal, alpha)
			if (nextPose.Position - goal.Position).Magnitude > 0.001 or nextPose.LookVector:Dot(goal.LookVector) < 0.9999 or nextPose.UpVector:Dot(goal.UpVector) < 0.9999 then
				settled = false
			else
				nextPose = goal
			end
			rig.Current[name] = nextPose
			local offset = if clip then evaluateClip(clip, now, name, nextPose) else nextPose
			perMotor[motor] = (perMotor[motor] or IDENTITY) * offset
		end
	end
	for motor, offset in perMotor do
		local base = rig.Base[motor]
		if base and motor.Parent then
			motor.C0 = CFrame.new(base.Position) * offset * base.Rotation
		end
	end
	rig.Settled = settled and target == nil
end

-- Clips ---------------------------------------------------------------------------------------------------------
local function strike(windup: number, wind: Pose, hit: Pose): { Keyframe }
	local strikeAt = windup + FX.StrikeTime
	return {
		{ T = 0, Pose = {} },
		{ T = windup, Pose = wind },
		{ T = strikeAt, Pose = hit },
		{ T = strikeAt + HOLD_TIME, Pose = hit },
		{ T = strikeAt + HOLD_TIME + FX.SwingRecover, Pose = {} },
	}
end

local PUNCH_WIND_TIME = 0.06

local function punchRight(windup: number): { Keyframe }
	return strike(
		math.max(windup, PUNCH_WIND_TIME),
		{ RightArm = CFrame.Angles(rad(60), 0, rad(-10)), RightForearm = CFrame.Angles(rad(100), 0, 0) },
		{ RightArm = CFrame.Angles(rad(90), 0, rad(-5)), RightForearm = IDENTITY, Torso = CFrame.Angles(0, rad(25), 0) }
	)
end

local function punchLeft(windup: number): { Keyframe }
	return strike(
		math.max(windup, PUNCH_WIND_TIME),
		{ LeftArm = CFrame.Angles(rad(60), 0, rad(10)), LeftForearm = CFrame.Angles(rad(100), 0, 0) },
		{ LeftArm = CFrame.Angles(rad(90), 0, rad(5)), LeftForearm = IDENTITY, Torso = CFrame.Angles(0, rad(-25), 0) }
	)
end

local function uppercut(windup: number): { Keyframe }
	return strike(
		math.max(windup, PUNCH_WIND_TIME),
		{ RightArm = CFrame.Angles(rad(20), 0, 0), RightForearm = CFrame.Angles(rad(90), 0, 0), Torso = CFrame.Angles(0, rad(-20), 0) },
		{ RightArm = CFrame.Angles(rad(150), 0, rad(-10)), RightForearm = CFrame.Angles(rad(40), 0, 0), Torso = CFrame.Angles(rad(8), rad(20), 0) }
	)
end

local function heavy(windup: number): { Keyframe }
	return strike(
		windup,
		{ RightArm = CFrame.Angles(rad(-30), 0, rad(30)), RightForearm = CFrame.Angles(rad(90), 0, 0), Torso = CFrame.Angles(0, rad(-45), 0) },
		{ RightArm = CFrame.Angles(rad(95), 0, 0), RightForearm = IDENTITY, Torso = CFrame.Angles(0, rad(40), 0) }
	)
end

local function kick(windup: number): { Keyframe }
	return strike(
		windup,
		{ RightLeg = CFrame.Angles(rad(40), 0, 0), Torso = CFrame.Angles(rad(8), 0, 0) },
		{ RightLeg = CFrame.Angles(rad(95), 0, 0), Torso = CFrame.Angles(rad(15), 0, 0), LeftArm = CFrame.Angles(rad(30), 0, rad(30)) }
	)
end

local function grab(windup: number): { Keyframe }
	return strike(
		windup,
		{ RightArm = CFrame.Angles(rad(90), 0, rad(-15)), LeftArm = CFrame.Angles(rad(90), 0, rad(15)) },
		{ RightArm = CFrame.Angles(rad(160), 0, 0), LeftArm = CFrame.Angles(rad(160), 0, 0), Torso = CFrame.Angles(rad(15), rad(30), 0) }
	)
end

local function multiHit(windup: number, hits: number, interval: number, kicks: boolean): { Keyframe }
	local keys: { Keyframe } = { { T = 0, Pose = {} } }
	local t = windup
	for i = 1, hits do
		local right = i % 2 == 1
		local hitPose: Pose
		if kicks then
			hitPose = if right
				then { RightLeg = CFrame.Angles(rad(90), 0, 0), Torso = CFrame.Angles(0, rad(30), 0) }
				else { LeftLeg = CFrame.Angles(rad(90), 0, 0), Torso = CFrame.Angles(0, rad(-30), 0) }
		else
			hitPose = if right
				then { RightArm = CFrame.Angles(rad(90), 0, 0), RightForearm = IDENTITY, Torso = CFrame.Angles(0, rad(20), 0) }
				else { LeftArm = CFrame.Angles(rad(90), 0, 0), LeftForearm = IDENTITY, Torso = CFrame.Angles(0, rad(-20), 0) }
		end
		table.insert(keys, { T = t, Pose = {} })
		table.insert(keys, { T = t + math.min(FX.StrikeTime, interval * 0.5), Pose = hitPose })
		t += interval
	end
	table.insert(keys, { T = t + FX.SwingRecover, Pose = {} })
	return keys
end

local function lean(duration: number, pose: Pose): { Keyframe }
	local inTime = math.min(FX.StrikeTime, duration * 0.3)
	return {
		{ T = 0, Pose = {} },
		{ T = inTime, Pose = pose },
		{ T = duration, Pose = pose },
		{ T = duration + FX.SwingRecover, Pose = {} },
	}
end

local function finishStomp(): { Keyframe }
	return strike(
		Combat.FinishHoldTime * 0.2,
		{ RightLeg = CFrame.Angles(rad(70), 0, 0), RightArm = CFrame.Angles(rad(40), 0, rad(30)), LeftArm = CFrame.Angles(rad(40), 0, rad(-30)) },
		{ RightLeg = CFrame.Angles(rad(10), 0, 0), Torso = CFrame.Angles(rad(-15), 0, 0) }
	)
end

local function playClip(model: Model, keys: { Keyframe })
	local rig = rigs[model]
	if not rig then
		addRig(model)
		rig = rigs[model]
	end
	if not rig then
		return
	end
	local last = keys[#keys]
	rig.Clip = { Keys = keys, Start = os.clock(), Duration = last.T }
	rig.Settled = false
end

-- Plays an id-based animation if one is configured. Returns true if it did.
local function playId(model: Model, id: any): boolean
	if type(id) ~= "number" or id == 0 then
		return false
	end
	if not rigs[model] then
		addRig(model)
	end
	local rig = rigs[model]
	local track = rig and getTrack(rig, id)
	if track then
		track:Play()
		return true
	end
	return false
end

local function isKickName(name: string?): boolean
	return name ~= nil and (name:find("Kick") ~= nil or name:find("Teep") ~= nil or name:find("Knee") ~= nil)
end

-- action: "M1" | "Heavy" | "Tech1" | "Tech2" | "Heat" | "Dash" | "Weave" | "Finish"
-- info: { Index?, Technique?, TechKind?, Windup?, Hits?, HitInterval? }
local function animate(model: Model, action: string, info: any)
	if action == "M1" then
		local index = tonumber(info.Index) or 1
		if playId(model, (Animations :: any)["M1_" .. index]) then
			return
		end
		local keys = if index == #Combat.M1Damage
			then uppercut(0)
			elseif index % 2 == 0 then punchLeft(0)
			else punchRight(0)
		playClip(model, keys)
	elseif action == "Heavy" then
		if playId(model, Animations.Heavy) then
			return
		end
		playClip(model, heavy(tonumber(info.Windup) or Combat.HeavyWindup))
	elseif action == "Dash" then
		if playId(model, Animations.Dash) then
			return
		end
		playClip(model, lean(Combat.DashDuration, { Torso = CFrame.Angles(rad(-20), 0, 0), RightArm = CFrame.Angles(rad(-30), 0, 0), LeftArm = CFrame.Angles(rad(-30), 0, 0) }))
	elseif action == "Weave" then
		if playId(model, Animations.Weave) then
			return
		end
		playClip(model, lean(Combat.WeaveIFrames, { Root = CFrame.new(0, -0.8, 0), Torso = CFrame.Angles(rad(-15), 0, rad(25)) }))
	elseif action == "Finish" then
		if playId(model, Animations.Finish) then
			return
		end
		playClip(model, finishStomp())
	else
		local name = info.Technique
		if type(name) == "string" and playId(model, Animations.Techniques[name]) then
			return
		end
		local windup = tonumber(info.Windup) or Combat.HeavyWindup
		local kind = info.TechKind
		local kicks = isKickName(name)
		local keys
		if kind == "MultiHit" then
			keys = multiHit(windup, tonumber(info.Hits) or 3, tonumber(info.HitInterval) or Combat.M1Interval, kicks)
		elseif kind == "Grab" then
			keys = grab(windup)
		elseif kicks then
			keys = kick(windup)
		elseif windup >= Combat.HeavyWindup * 0.75 then
			keys = heavy(windup)
		else
			keys = punchRight(windup)
		end
		playClip(model, keys)
	end
end

-- Screen effects ------------------------------------------------------------------------------------------------
local function getGui(): ScreenGui
	local current = fxGui
	if current and current.Parent then
		return current
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "KenkaFX"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = FX_DISPLAY_ORDER
	gui.Parent = localPlayer:WaitForChild("PlayerGui")
	fxGui = gui
	return gui
end

-- Runs a set of tweens and destroys everything in the cleaner after `lifetime` seconds.
local function expire(cleaner: any, lifetime: number)
	task.delay(lifetime, function()
		cleaner:Clean()
	end)
end

local function tween(cleaner: any, instance: Instance, time: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local t = TweenService:Create(instance, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
	cleaner:Add(t)
	t:Play()
	return t
end

local function fxParent(): Instance
	return workspace.CurrentCamera or workspace
end

local function spark(position: Vector3, color: Color3)
	local cleaner = Cleaner.new()
	for _ = 1, FX.SparkCount do
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = color
		p.Size = Vector3.one * SPARK_SIZE
		p.CFrame = CFrame.new(position)
		p.Parent = fxParent()
		cleaner:Add(p)
		local direction = Vector3.new(math.random() - 0.5, math.random() * 0.8, math.random() - 0.5)
		direction = if direction.Magnitude > 0.01 then direction.Unit else Vector3.yAxis
		tween(cleaner, p, FX.SparkTime, {
			CFrame = CFrame.new(position + direction * FX.SparkSpeed),
			Size = Vector3.zero,
			Transparency = 1,
		})
	end
	expire(cleaner, FX.SparkTime + 0.05)
end

local function damageNumber(position: Vector3, amount: number, color: Color3)
	local cleaner = Cleaner.new()
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.1
	anchor.CFrame = CFrame.new(position + Vector3.new((math.random() - 0.5), FX.DamageNumberStart, 0))
	anchor.Parent = fxParent()
	cleaner:Add(anchor)
	local gui = Instance.new("BillboardGui")
	gui.Size = NUMBER_SIZE
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = anchor
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = UITheme.Fonts.Number
	label.TextScaled = true
	label.Text = if amount % 1 == 0 then tostring(amount) else string.format("%.1f", amount)
	label.TextColor3 = color
	label.TextStrokeTransparency = 0
	label.Parent = gui
	tween(cleaner, gui, FX.DamageNumberTime, { StudsOffsetWorldSpace = Vector3.new(0, FX.DamageNumberRise, 0) })
	tween(cleaner, label, FX.DamageNumberTime, { TextTransparency = 1, TextStrokeTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	expire(cleaner, FX.DamageNumberTime)
end

local function stamp(text: string, color: string)
	local cleaner = Cleaner.new()
	local label = Instance.new("TextLabel")
	label.Name = "Stamp"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.38)
	label.Size = STAMP_SIZE
	label.BackgroundTransparency = 1
	label.Font = UITheme.Fonts.Title
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = Kit.Hex(color)
	label.Rotation = -6
	Kit.TextStroke(label, 3)
	local scale = Instance.new("UIScale")
	scale.Scale = STAMP_POP_SCALE
	scale.Parent = label
	label.Parent = getGui()
	cleaner:Add(label)
	tween(cleaner, scale, STAMP_POP_TIME, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	task.delay(FX.StampTime * 0.6, function()
		if label.Parent then
			tween(cleaner, label, FX.StampTime * 0.4, { TextTransparency = 1 })
		end
	end)
	expire(cleaner, FX.StampTime)
end

local function flash()
	local cleaner = Cleaner.new()
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BackgroundTransparency = FX.ParryFlashStart
	frame.BorderSizePixel = 0
	frame.Parent = getGui()
	cleaner:Add(frame)
	tween(cleaner, frame, FX.ParryFlashTime, { BackgroundTransparency = 1 })
	expire(cleaner, FX.ParryFlashTime)
end

-- Camera shake and hit-stop nudge are applied after the camera updates each frame.
local shakeStrength, shakeUntil, shakeDuration = 0, 0, 1
local nudgeUntil = 0
local function shake(strength: number)
	if not setting("CameraShake") then
		return
	end
	local now = os.clock()
	if now < shakeUntil and shakeStrength > strength then
		return
	end
	shakeStrength, shakeDuration, shakeUntil = strength, FX.CameraShakeTime, now + FX.CameraShakeTime
	nudgeUntil = now + FX.HitStopTime
end

local function cameraStep()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local now = os.clock()
	local offset = IDENTITY
	if now < shakeUntil then
		local fade = (shakeUntil - now) / shakeDuration
		local s = shakeStrength * fade
		offset *= CFrame.new((math.random() - 0.5) * s, (math.random() - 0.5) * s, 0)
			* CFrame.Angles(0, 0, rad((math.random() - 0.5) * s * 2))
	end
	if now < nudgeUntil then
		offset *= CFrame.new(0, 0, -FX.HitStopNudge)
	end
	if offset ~= IDENTITY then
		camera.CFrame *= offset
	end
end

local zoomBaseFov: number? = nil
local zoomCleaner = Cleaner.new()
local function heatZoom()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	zoomCleaner:Clean()
	local base = zoomBaseFov or camera.FieldOfView
	zoomBaseFov = base
	local half = FX.HeatZoomTime / 2
	local zoomIn = tween(zoomCleaner, camera, half, { FieldOfView = base - FX.HeatZoomFov })
	zoomCleaner:Add(zoomIn.Completed:Connect(function()
		local zoomOut = tween(zoomCleaner, camera, half, { FieldOfView = base }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		zoomCleaner:Add(zoomOut.Completed:Connect(function()
			zoomBaseFov = nil
		end))
	end))
	zoomCleaner:Add(function()
		if zoomBaseFov and camera.Parent then
			camera.FieldOfView = zoomBaseFov
		end
	end)
end

-- Combat_FX ------------------------------------------------------------------------------------------------------
local function asModel(value: any): Model?
	if typeof(value) == "Instance" and (value :: Instance):IsA("Model") then
		return value :: Model
	end
	return nil
end

local function positionOf(payload: any, model: Model?): Vector3?
	if typeof(payload.Position) == "Vector3" then
		return payload.Position
	end
	local root = model and model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function wasPredicted(attacker: Model, action: string): boolean
	if attacker ~= localCharacter() then
		return false
	end
	local at = predicted[action]
	if at and os.clock() - at < PREDICT_WINDOW then
		predicted[action] = nil
		return true
	end
	return false
end

local function onHit(payload: any, attacker: Model?, target: Model?)
	local position = positionOf(payload, target)
	local character = localCharacter()
	local blocked = payload.Blocked == true
	local damage = tonumber(payload.Damage) or 0
	local heavyHit = payload.Heavy == true or payload.IsHeat == true
	if position then
		spark(position, if blocked then Kit.Hex(UITheme.Muted) else Kit.Hex(UITheme.Gold))
	end
	if character and (attacker == character or target == character) then
		Kit.PlaySound(if heavyHit then "HeavyHit" else "Hit")
		shake(if heavyHit then FX.CameraShakeHeavy else FX.CameraShakeHit)
		if position and damage > 0 and setting("DamageNumbers") then
			local color = if target == character
				then Kit.Hex(UITheme.Bars.HP)
				elseif blocked then Kit.Hex(UITheme.Muted)
				else Kit.Hex(UITheme.Paper)
			damageNumber(position, damage, color)
		end
	end
end

local function onFX(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local kind = payload.Kind
	local attacker = asModel(payload.Attacker)
	local target = asModel(payload.Target)

	if kind == "Swing" then
		if attacker and not wasPredicted(attacker, payload.Action or "") then
			animate(attacker, payload.Action or "M1", payload)
		end
	elseif kind == "Technique" or kind == "Heat" then
		if attacker and not wasPredicted(attacker, payload.Action or "") then
			animate(attacker, payload.Action or "Tech1", payload)
		end
		if kind == "Heat" and involved(payload) then
			heatZoom()
		end
	elseif kind == "Hit" or kind == "Block" then
		onHit(payload, attacker, target)
	elseif kind == "Parry" then
		local position = positionOf(payload, target)
		if position then
			spark(position, Color3.new(1, 1, 1))
		end
		if involved(payload) then
			flash()
			stamp("PARRY!", UITheme.Paper)
			Kit.PlaySound("Parry")
			shake(FX.CameraShakeHit)
		end
	elseif kind == "Clash" then
		local position = positionOf(payload, attacker)
		if position then
			spark(position, Kit.Hex(UITheme.Gold))
		end
		if involved(payload) then
			stamp("CLASH!", UITheme.Gold)
			Kit.PlaySound("Parry")
			shake(FX.CameraShakeHit)
		end
	elseif kind == "GuardBreak" then
		local position = positionOf(payload, target)
		if position then
			spark(position, Kit.Hex(UITheme.Bars.Posture))
		end
		if involved(payload) then
			stamp("GUARD BREAK!", UITheme.Bars.Posture)
			Kit.PlaySound("HeavyHit")
			shake(FX.CameraShakeHeavy)
		end
	elseif kind == "Dash" or kind == "Weave" then
		if attacker and not wasPredicted(attacker, kind) then
			animate(attacker, kind, payload)
		end
	elseif kind == "Knockdown" then
		if payload.KO == true and involved(payload) then
			Kit.PlaySound("KO")
			shake(FX.CameraShakeHeavy)
			if attacker == localCharacter() then
				stamp("DOWN!", UITheme.Zones.Red)
			end
		end
	elseif kind == "Finish" then
		if attacker then
			animate(attacker, "Finish", payload)
		end
		if involved(payload) then
			Kit.PlaySound("KO")
			shake(FX.CameraShakeHeavy)
			if attacker == localCharacter() then
				stamp("K.O.", UITheme.Zones.Red)
			end
		end
	end
end

-- Public API -------------------------------------------------------------------------------------------------------

-- Play the local player's own animation right away (client prediction). info like the Combat_FX payload.
function FXController.Predict(action: string, info: any?)
	local character = localCharacter()
	if not character then
		return
	end
	predicted[action] = os.clock()
	animate(character, action, info or {})
end

-- Play an action animation on any fighter model.
function FXController.PlayAction(model: Model, action: string, info: any?)
	animate(model, action, info or {})
end

-- Lifecycle --------------------------------------------------------------------------------------------------------
function FXController.Init(controllers: any)
	Controllers = controllers
end

function FXController.Start()
	Net.Event("Combat_FX").OnClientEvent:Connect(onFX)

	for _, model in CollectionService:GetTagged(FIGHTER_TAG) do
		if model:IsA("Model") then
			addRig(model)
		end
	end
	CollectionService:GetInstanceAddedSignal(FIGHTER_TAG):Connect(function(instance)
		if instance:IsA("Model") then
			addRig(instance)
		end
	end)
	CollectionService:GetInstanceRemovedSignal(FIGHTER_TAG):Connect(function(instance)
		if instance:IsA("Model") then
			removeRig(instance)
		end
	end)

	RunService:BindToRenderStep("KenkaCameraFX", Enum.RenderPriority.Camera.Value + 1, cameraStep)

	local last = os.clock()
	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local dt = now - last
		last = now
		local camera = workspace.CurrentCamera
		local cameraPosition = if camera then camera.CFrame.Position else Vector3.zero
		for model, rig in rigs do
			if model.Parent == nil then
				removeRig(model)
			else
				stepRig(rig, now, dt, cameraPosition)
			end
		end
	end)
end

return FXController
