--!strict
-- Server-authoritative melee combat (blueprint sections 1.3-1.7).
--
-- Every fightable model (player characters and NPCs) is a "fighter" in the registry below. Fight state lives
-- in model attributes that the HUD reads: Fighter, HP, MaxHP, Posture, MaxPosture, Heat, Stance, Blocking,
-- Downed, InCombat, Protected, StunnedUntil (server time), IsNPC, DisplayName. Humanoid.Health is never used.
--
-- Clients send intent with Combat_Request(action, data). The server validates everything, runs windups,
-- picks targets (reach x height multiplier, in front, closest first), applies damage, posture, parries,
-- heat and knockback, and broadcasts Combat_FX so every client can play the matching animation.
--
-- NPCs act through CombatService.PerformAction (the same code path as the remote), so hits, parries and
-- FX behave identically for AI and players.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Combat = require(ReplicatedStorage.Shared.Config.Combat)
local Styles = require(ReplicatedStorage.Shared.Config.Styles)
local Ranks = require(ReplicatedStorage.Shared.Config.Ranks)
local Animations = require(ReplicatedStorage.Shared.Config.Animations)
local CombatMath = require(ReplicatedStorage.Shared.Logic.CombatMath)
local HeightStats = require(ReplicatedStorage.Shared.Logic.HeightStats)
local RepMath = require(ReplicatedStorage.Shared.Logic.RepMath)
local ZoneMath = require(ReplicatedStorage.Shared.Logic.ZoneMath)
local Net = require(ReplicatedStorage.Shared.Util.Net)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Cleaner = require(ReplicatedStorage.Shared.Util.Cleaner)
local RateLimiter = require(ReplicatedStorage.Shared.Util.RateLimiter)
local Notify = require(script.Parent.Parent.Systems.Notify)

local CombatService = {}
CombatService.Priority = 30

CombatService.HitLanded = Signal.new() -- (attackerModel, targetModel, info)
CombatService.Parried = Signal.new() -- (defenderModel, attackerModel)
CombatService.HeatLanded = Signal.new() -- (attackerModel, targetModel)
CombatService.FighterRegistered = Signal.new() -- (model)
CombatService.FighterRemoved = Signal.new() -- (model)

local Services: any

-- Tuning derived from Config (no new numbers here) ------------------------------------------------
local Motion = Animations.Motion
local TICK = 0.1 -- 10 Hz combat loop
local STAT_REFRESH_INTERVAL = 1 -- seconds between buff/height re-reads for players
local M1_FINISHER_RECOVERY = Combat.M1ComboReset -- pause after the 4th light hit
local DUMMY_HITS_PER_XP = 2
local FIGHTER_TAG = "Fighter"

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
-- Actions allowed without stance / while stunned (they only end a state).
local ENDING_ACTIONS = { BlockEnd = true, SprintEnd = true }

-- Types ----------------------------------------------------------------------------------------------
export type FighterOpts = {
	Player: Player?,
	IsNPC: boolean?,
	Owner: Player?,
	IgnoreZones: boolean?,
	Dummy: boolean?, -- dojo dummy: anyone not in a duel may hit it, HP resets at 0
	HeightCm: number?,
	Style: string?,
	MaxHP: number?,
	DisplayName: string?,
	Mode: string?,
}

export type HitSpec = {
	Action: string,
	Index: number?,
	Damage: number,
	IsHeavy: boolean,
	IgnoresBlock: boolean,
	Unparryable: boolean,
	PostureDamage: number,
	BlockPostureCost: number,
	Knockback: number,
	KnockdownTime: number,
	IsHeat: boolean,
	Technique: string?,
	MinTargetHP: number?,
}

export type Overrides = {
	Damage: number?,
	Windup: number?,
	MinTargetHP: number?,
}

type Fighter = {
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Player: Player?,
	IsNPC: boolean,
	Owner: Player?,
	IgnoreZones: boolean,
	Dummy: boolean,
	Mode: string?,
	Opts: FighterOpts,
	Cleaner: any,
	-- derived stats
	StyleId: string,
	BaseWalkSpeed: number,
	Reach: number,
	BaseJumpHeight: number,
	StatsRefreshedAt: number,
	-- live state (mirrored to attributes)
	HP: number,
	MaxHP: number,
	Posture: number,
	Heat: number,
	Stance: boolean,
	Blocking: boolean,
	Sprinting: boolean,
	StunnedUntil: number, -- server time
	GuardBrokenUntil: number, -- server time
	-- timers (os.clock)
	ComboIndex: number,
	LastM1At: number,
	Cooldowns: { [string]: number },
	BusyUntil: number,
	ActionToken: number,
	BlockStartedAt: number,
	LastBlockStartAt: number,
	ParryEligible: boolean,
	LastParryAt: number,
	LastPostureSpendAt: number,
	IFramesUntil: number,
	InCombat: boolean,
	LastCombatAt: number,
	LastHitTakenAt: number,
	HitsDealt: { [Model]: number },
	DummyHits: number,
	ZeroHandled: boolean,
	Removed: boolean,
}

local fighters: { [Model]: Fighter } = {}
local limiter = RateLimiter.new(Combat.MaxRequestsPerSecond, 1)
local playerCleaners: { [Player]: any } = {}

local fxEvent = Net.Event("Combat_FX")
local cooldownEvent = Net.Event("Combat_Cooldown")

-- Helpers ------------------------------------------------------------------------------------------
local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function service(name: string): any
	return Services and Services[name]
end

local function getStyle(f: Fighter): Styles.Style
	local player = f.Player
	if player then
		local styleService = service("StyleService")
		if styleService and styleService.GetEquippedStyle then
			local ok, style = pcall(styleService.GetEquippedStyle, player)
			if ok and type(style) == "table" then
				return style :: Styles.Style
			end
		end
		local attr = player:GetAttribute("Style")
		if type(attr) == "string" and Styles.Styles[attr] then
			return Styles.Styles[attr]
		end
	end
	return Styles.Styles[f.StyleId] or Styles.Styles[Styles.DefaultStyle]
end

local function inDuel(player: Player?): boolean
	if not player then
		return false
	end
	local challenge = service("ChallengeService")
	if challenge and challenge.IsInDuel then
		return challenge.IsInDuel(player) == true
	end
	return player:GetAttribute("InDuel") == true
end

local function areDueling(a: Player, b: Player): boolean
	local challenge = service("ChallengeService")
	if challenge and challenge.AreDueling then
		return challenge.AreDueling(a, b) == true
	end
	return false
end

-- Food buffs are ignored in duels and tournaments.
local function buff(player: Player?, stat: string): number
	if not player then
		return 0
	end
	if player:GetAttribute("InTournament") == true or inDuel(player) then
		return 0
	end
	local shop = service("ShopService")
	if not shop or not shop.GetBuffValue then
		return 0
	end
	local ok, value = pcall(shop.GetBuffValue, player, stat)
	if ok and type(value) == "number" then
		return value
	end
	return 0
end

local function quest(player: Player?, event: string, amount: number?)
	local questService = service("QuestService")
	if player and questService and questService.Progress then
		task.spawn(questService.Progress, player, event, amount)
	end
end

local function dismount(player: Player?)
	local vehicles = service("VehicleService")
	if player and vehicles and vehicles.Dismount then
		task.spawn(vehicles.Dismount, player)
	end
end

local function fx(payload: { [string]: any })
	fxEvent:FireAllClients(payload)
end

local function setAttr(f: Fighter, name: string, value: any)
	if f.Model:GetAttribute(name) ~= value then
		f.Model:SetAttribute(name, value)
	end
end

local function isStunned(f: Fighter): boolean
	return f.StunnedUntil > serverNow()
end

local function isDowned(f: Fighter): boolean
	return f.Model:GetAttribute("Downed") == true
end

local function isProtected(f: Fighter): boolean
	return f.Model:GetAttribute("Protected") == true
end

local function zoneType(f: Fighter): string
	local player = f.Player
	local zones = service("ZoneService")
	if player then
		if zones and zones.GetZoneType then
			return zones.GetZoneType(player)
		end
		local attr = player:GetAttribute("ZoneType")
		return if type(attr) == "string" then attr else "Yellow"
	end
	if zones and zones.ZoneAt then
		return zones.ZoneAt(f.Root.Position).Type
	end
	return "Yellow"
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function setCooldown(f: Fighter, action: string, seconds: number)
	if seconds <= 0 then
		return
	end
	f.Cooldowns[action] = os.clock() + seconds
	local player = f.Player
	if player then
		cooldownEvent:FireClient(player, action, seconds)
	end
end

local function onCooldown(f: Fighter, action: string): boolean
	local ends = f.Cooldowns[action]
	return ends ~= nil and os.clock() < ends
end

local function syncAll(f: Fighter)
	setAttr(f, "HP", math.floor(f.HP * 10 + 0.5) / 10)
	setAttr(f, "MaxHP", f.MaxHP)
	setAttr(f, "Posture", math.floor(f.Posture + 0.5))
	setAttr(f, "MaxPosture", Combat.MaxPosture)
	setAttr(f, "Heat", math.floor(f.Heat + 0.5))
	setAttr(f, "Stance", f.Stance)
	setAttr(f, "Blocking", f.Blocking)
	setAttr(f, "InCombat", f.InCombat)
	setAttr(f, "StunnedUntil", f.StunnedUntil)
end

-- Stats and movement -------------------------------------------------------------------------------
local function heightOf(f: Fighter): number
	local player = f.Player
	if player then
		local data = service("DataService")
		local profile = data and data.GetProfile(player)
		if profile and type(profile.HeightCm) == "number" then
			return profile.HeightCm
		end
		local attr = player:GetAttribute("HeightCm")
		if type(attr) == "number" then
			return attr
		end
	end
	return f.Opts.HeightCm or HeightStats.DefaultCm
end

local function applyMovement(f: Fighter)
	if f.Removed or not f.Humanoid.Parent then
		return
	end
	local player = f.Player
	local vehicle = player and player:GetAttribute("Vehicle")
	if type(vehicle) == "string" and vehicle ~= "" then
		return -- VehicleService owns walk speed while mounted
	end
	local speed = f.BaseWalkSpeed
	local jump = f.BaseJumpHeight
	if f.Dummy then
		speed = 0
		jump = 0
	elseif isDowned(f) then
		speed = Combat.DownedCrawlSpeed
		jump = 0
	else
		if f.Blocking then
			speed *= Combat.BlockWalkSpeedMultiplier
			jump = 0
		end
		if f.Sprinting then
			speed *= Combat.SprintSpeedMultiplier
		end
		if isStunned(f) then
			speed *= Motion.StunWalkSpeedMultiplier
			jump = 0
		end
	end
	if math.abs(f.Humanoid.WalkSpeed - speed) > 0.01 then
		f.Humanoid.WalkSpeed = speed
	end
	if f.Humanoid.UseJumpPower == false and math.abs(f.Humanoid.JumpHeight - jump) > 0.01 then
		f.Humanoid.JumpHeight = jump
	end
end

local function refreshFighterStats(f: Fighter)
	local style = getStyle(f)
	f.StyleId = style.Id
	local stats = HeightStats.Get(heightOf(f))
	local player = f.Player
	local maxHP = if f.Opts.MaxHP then f.Opts.MaxHP else stats.HP + buff(player, "MaxHP")
	maxHP = math.max(1, maxHP)
	if maxHP ~= f.MaxHP then
		f.MaxHP = maxHP
		f.HP = math.min(f.HP, maxHP)
	end
	f.BaseWalkSpeed = math.max(0, stats.WalkSpeed + (style.Passive.WalkSpeedDelta or 0) + buff(player, "WalkSpeed"))
	f.Reach = stats.Reach
	f.StatsRefreshedAt = os.clock()
	syncAll(f)
	applyMovement(f)
end

-- Combat state --------------------------------------------------------------------------------------
local function markCombat(f: Fighter)
	if f.Dummy then
		return
	end
	if not f.InCombat then
		f.InCombat = true
		table.clear(f.HitsDealt)
		setAttr(f, "InCombat", true)
	end
	f.LastCombatAt = os.clock()
end

local function endCombat(f: Fighter)
	f.InCombat = false
	table.clear(f.HitsDealt)
	setAttr(f, "InCombat", false)
end

local function interrupt(f: Fighter)
	f.ActionToken += 1
	f.BusyUntil = 0
end

local function setBlocking(f: Fighter, on: boolean)
	if f.Blocking == on then
		return
	end
	f.Blocking = on
	setAttr(f, "Blocking", on)
	applyMovement(f)
end

local function setSprinting(f: Fighter, on: boolean)
	if f.Sprinting == on then
		return
	end
	f.Sprinting = on
	applyMovement(f)
end

local function stun(f: Fighter, seconds: number)
	f.StunnedUntil = math.max(f.StunnedUntil, serverNow() + seconds)
	setAttr(f, "StunnedUntil", f.StunnedUntil)
	interrupt(f)
	setBlocking(f, false)
	setSprinting(f, false)
	applyMovement(f)
	local model = f.Model
	task.delay(seconds + TICK, function()
		local current = fighters[model]
		if current then
			applyMovement(current)
		end
	end)
end

local function addHeat(f: Fighter, amount: number)
	f.Heat = math.clamp(f.Heat + amount, 0, Combat.MaxHeat)
	setAttr(f, "Heat", math.floor(f.Heat + 0.5))
end

local function setPosture(f: Fighter, value: number)
	f.Posture = math.clamp(value, 0, Combat.MaxPosture)
	setAttr(f, "Posture", math.floor(f.Posture + 0.5))
end

-- Voluntary spend (dash, weave): fails if there isn't enough posture.
local function spendPosture(f: Fighter, amount: number): boolean
	if f.Posture < amount then
		return false
	end
	setPosture(f, f.Posture - amount)
	f.LastPostureSpendAt = os.clock()
	return true
end

local function guardBreak(f: Fighter, attacker: Fighter?)
	f.GuardBrokenUntil = serverNow() + Combat.GuardBreakStun
	setPosture(f, 0)
	f.LastPostureSpendAt = os.clock()
	stun(f, Combat.GuardBreakStun)
	fx({
		Kind = "GuardBreak",
		Attacker = if attacker then attacker.Model else nil,
		Target = f.Model,
		Position = f.Root.Position,
	})
	local model = f.Model
	task.delay(Combat.GuardBreakStun, function()
		local current = fighters[model]
		if current and current.Posture < Combat.GuardBreakPostureRefill then
			setPosture(current, Combat.GuardBreakPostureRefill)
		end
	end)
end

-- Posture damage from a hit. Returns true if it broke the guard.
local function damagePosture(f: Fighter, amount: number, attacker: Fighter?): boolean
	if amount <= 0 then
		return false
	end
	setPosture(f, f.Posture - amount)
	f.LastPostureSpendAt = os.clock()
	if f.Posture <= 0 then
		guardBreak(f, attacker)
		return true
	end
	return false
end

-- Knockback: NPCs are server-owned (we push them here). Player characters are client-owned, so the
-- victim's client applies the velocity we send.
local function pushRoot(root: BasePart, velocity: Vector3, duration: number)
	if root.Anchored then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "KenkaPush"
	attachment.Parent = root
	local mover = Instance.new("LinearVelocity")
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	mover.PrimaryTangentAxis = Vector3.xAxis
	mover.SecondaryTangentAxis = Vector3.zAxis
	mover.PlaneVelocity = Vector2.new(velocity.X, velocity.Z)
	mover.MaxForce = math.huge
	mover.Parent = root
	if velocity.Y > 0 then
		root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, velocity.Y, root.AssemblyLinearVelocity.Z)
	end
	task.delay(duration, function()
		mover:Destroy()
		attachment:Destroy()
	end)
end

local function applyKnockback(attacker: Fighter, target: Fighter, distance: number)
	if distance <= 0 then
		return
	end
	local targetStyle = getStyle(target)
	local studs = CombatMath.Knockback(distance, targetStyle.Passive)
	if studs <= 0 then
		return
	end
	local dir = flat(target.Root.Position - attacker.Root.Position)
	if dir.Magnitude < 0.01 then
		dir = flat(attacker.Root.CFrame.LookVector)
	end
	dir = dir.Unit
	local duration = Motion.KnockbackDuration
	local velocity = dir * (studs / duration) + Vector3.new(0, Motion.KnockbackLift, 0)
	local player = target.Player
	if player then
		fxEvent:FireClient(player, { Kind = "Knockback", Velocity = velocity, Duration = duration })
	else
		pushRoot(target.Root, velocity, duration)
	end
end

-- Hit permission --------------------------------------------------------------------------------------
-- ignoreDowned: KnockoutService uses this to decide who may Finish a downed fighter.
local function canHit(attacker: Fighter, target: Fighter, ignoreDowned: boolean?): boolean
	if attacker == target or attacker.Removed or target.Removed then
		return false
	end
	if not ignoreDowned then
		if target.HP <= 0 or isDowned(target) then
			return false
		end
	end
	if isProtected(target) then
		return false
	end
	local ap, tp = attacker.Player, target.Player

	-- Target is an NPC
	if target.IsNPC then
		if target.Owner then
			if ap ~= target.Owner then
				return false
			end
			if target.IgnoreZones then
				return true
			end
			return ZoneMath.AllowsOpenFight(zoneType(attacker), zoneType(target))
		end
		if target.Dummy then
			return ap ~= nil and not inDuel(ap)
		end
		if not ap or inDuel(ap) then
			return false
		end
		return target.IgnoreZones or ZoneMath.AllowsOpenFight(zoneType(attacker), zoneType(target))
	end

	-- Attacker is an NPC, target is a player
	if attacker.IsNPC then
		if not attacker.Owner or tp ~= attacker.Owner or inDuel(tp) then
			return false
		end
		if attacker.IgnoreZones then
			return true
		end
		return ZoneMath.AllowsOpenFight(zoneType(attacker), zoneType(target))
	end

	-- Player vs player
	if not ap or not tp then
		return false
	end
	local za, zt = zoneType(attacker), zoneType(target)
	if za == "Green" or zt == "Green" then
		return false
	end
	if inDuel(ap) or inDuel(tp) then
		return areDueling(ap, tp)
	end
	if not ZoneMath.AllowsOpenFight(za, zt) then
		return false
	end
	local attackerRank = ap:GetAttribute("Rank")
	local targetRank = tp:GetAttribute("Rank")
	local optedOut = tp:GetAttribute("RookieProtected") ~= true
	return RepMath.RookieAllowsHit(
		Ranks,
		if type(attackerRank) == "number" then attackerRank else 1,
		if type(targetRank) == "number" then targetRank else 1,
		optedOut
	)
end

-- Best target in front of the attacker, closest first.
local function findTarget(attacker: Fighter, baseRange: number, extraStuds: number): Fighter?
	local root = attacker.Root
	local origin = root.Position
	local look = flat(root.CFrame.LookVector)
	if look.Magnitude < 0.01 then
		return nil
	end
	look = look.Unit
	local best: Fighter? = nil
	local bestDistance = math.huge
	for _, target in fighters do
		if target ~= attacker and not target.Removed and target.Root.Parent then
			local offset = target.Root.Position - origin
			local horizontal = flat(offset)
			local distance = horizontal.Magnitude
			if
				math.abs(offset.Y) <= Motion.VerticalHitTolerance
				and CombatMath.InReach(distance, baseRange + extraStuds, attacker.Reach, Combat.ReachLatencyAllowance)
				and distance < bestDistance
			then
				local dot = if distance > 0.01 then look:Dot(horizontal.Unit) else 1
				if CombatMath.InFront(dot, Combat.FacingDotMinimum) and canHit(attacker, target) then
					best = target
					bestDistance = distance
				end
			end
		end
	end
	return best
end

-- Zero HP -------------------------------------------------------------------------------------------
local function resetDummy(f: Fighter)
	f.HP = f.MaxHP
	f.ZeroHandled = false
	setAttr(f, "HP", f.HP)
end

local function handleZeroHP(target: Fighter, attacker: Fighter)
	if target.ZeroHandled then
		return
	end
	if target.Dummy then
		resetDummy(target)
		return
	end
	target.ZeroHandled = true
	interrupt(target)
	setBlocking(target, false)
	setSprinting(target, false)
	local tp, ap = target.Player, attacker.Player
	if tp and ap and areDueling(tp, ap) then
		local challenge = service("ChallengeService")
		if challenge and challenge.OnDuelKO then
			task.spawn(challenge.OnDuelKO, tp, ap)
			return
		end
	end
	local knockout = service("KnockoutService")
	if knockout and knockout.OnZeroHP then
		task.spawn(knockout.OnZeroHP, target.Model, attacker.Model)
	else
		-- Fallback without a KnockoutService: stand back up immediately.
		CombatService.Revive(target.Model, Combat.RecoverHP / target.MaxHP)
	end
end

-- Hit resolution --------------------------------------------------------------------------------------
local function resolveParry(attacker: Fighter, target: Fighter): boolean
	local clock = os.clock()
	-- A tap counts even if the block key was already released when the hit arrives.
	if not (target.ParryEligible and CombatMath.IsParry(target.BlockStartedAt, clock, Combat.ParryWindow)) then
		return false
	end
	markCombat(attacker)
	markCombat(target)
	local position = (attacker.Root.Position + target.Root.Position) / 2
	-- Both fighters tapped block at the same moment: a clash, no bonuses.
	if attacker.ParryEligible and CombatMath.IsParry(attacker.BlockStartedAt, clock, Combat.ParryWindow) then
		attacker.ParryEligible = false
		target.ParryEligible = false
		stun(attacker, Combat.ClashStagger)
		stun(target, Combat.ClashStagger)
		fx({ Kind = "Clash", Attacker = attacker.Model, Target = target.Model, Position = position })
		return true
	end
	target.ParryEligible = false -- one parry per tap
	target.LastParryAt = clock
	stun(attacker, Combat.ParryStun)
	setPosture(target, target.Posture + Combat.ParryPostureGain)
	addHeat(target, Combat.ParryHeatGain)
	fx({ Kind = "Parry", Attacker = attacker.Model, Target = target.Model, Position = position })
	CombatService.Parried:Fire(target.Model, attacker.Model)
	local defenderPlayer = target.Player
	if defenderPlayer then
		quest(defenderPlayer, "Parry")
		local data = service("DataService")
		if data and data.GetProfile(defenderPlayer) then
			data.Update(defenderPlayer, { "Stats" }, function(profile: any)
				profile.Stats.Parries = (profile.Stats.Parries or 0) + 1
			end)
		end
	end
	-- Judo passive: the parry throws the attacker.
	local throw = getStyle(target).Passive.ParryAutoThrowDamage
	if throw and throw > 0 and attacker.HP > 0 and canHit(target, attacker) then
		attacker.HP = math.max(0, attacker.HP - throw)
		attacker.LastHitTakenAt = clock
		setAttr(attacker, "HP", attacker.HP)
		fx({
			Kind = "Hit",
			Attacker = target.Model,
			Target = attacker.Model,
			Action = "ParryThrow",
			Damage = throw,
			Blocked = false,
			Position = attacker.Root.Position,
		})
		dismount(attacker.Player)
		if attacker.HP <= 0 then
			handleZeroHP(attacker, target)
		end
	end
	return true
end

local function resolveHit(attacker: Fighter, target: Fighter, spec: HitSpec)
	if attacker.Removed or target.Removed then
		return
	end
	local clock = os.clock()
	if target.IFramesUntil > clock then
		return -- weaved through it
	end
	if not spec.Unparryable and resolveParry(attacker, target) then
		return
	end

	local now = serverNow()
	local guardBroken = target.GuardBrokenUntil > now
	local style = getStyle(attacker)
	local result = CombatMath.Damage({
		BaseDamage = spec.Damage,
		IsHeavy = spec.IsHeavy,
		AttackerHP = attacker.HP,
		AttackerMaxHP = attacker.MaxHP,
		AttackerPassive = style.Passive,
		TargetBlocking = target.Blocking,
		TargetGuardBroken = guardBroken,
		IgnoresBlock = spec.IgnoresBlock,
		BlockDamageTaken = Combat.BlockDamageTaken,
		GuardBreakMultiplier = Combat.GuardBreakDamageTakenMultiplier,
	})
	local damage = result.Damage
	local blocked = result.Blocked

	-- Posture
	local postureDamage = spec.PostureDamage
	if blocked then
		postureDamage += spec.BlockPostureCost
	end
	local broke = false
	if postureDamage > 0 and not guardBroken then
		broke = damagePosture(target, postureDamage, attacker)
	end

	-- Tutorial NPCs never take the target below a floor.
	if spec.MinTargetHP then
		damage = math.max(0, math.min(damage, target.HP - spec.MinTargetHP))
	end

	target.HP = math.max(0, target.HP - damage)
	target.LastHitTakenAt = clock
	setAttr(target, "HP", math.floor(target.HP * 10 + 0.5) / 10)
	if not target.Dummy then
		-- Training on a dojo dummy doesn't count as a fight (shops and jobs stay usable).
		markCombat(attacker)
		markCombat(target)
		addHeat(target, Combat.HeatPerHitTaken)
	end
	if not spec.IsHeat then
		addHeat(attacker, Combat.HeatPerHitLanded)
	end
	attacker.HitsDealt[target.Model] = (attacker.HitsDealt[target.Model] or 0) + 1

	-- Getting hit (not blocked) interrupts the target's windup.
	if not blocked then
		interrupt(target)
		if spec.Knockback > 0 then
			applyKnockback(attacker, target, spec.Knockback)
		end
		if spec.KnockdownTime > 0 and not broke then
			stun(target, spec.KnockdownTime)
			fx({ Kind = "Knockdown", Attacker = attacker.Model, Target = target.Model, Duration = spec.KnockdownTime, Position = target.Root.Position })
		end
	end

	dismount(target.Player)

	fx({
		Kind = if blocked then "Block" else "Hit",
		Attacker = attacker.Model,
		Target = target.Model,
		Action = spec.Action,
		Index = spec.Index,
		Technique = spec.Technique,
		Damage = damage,
		Blocked = blocked,
		Heavy = spec.IsHeavy,
		IsHeat = spec.IsHeat,
		Position = target.Root.Position,
	})

	local attackerPlayer = attacker.Player
	if attackerPlayer then
		quest(attackerPlayer, "LandHit")
		if target.Dummy then
			attacker.DummyHits += 1
			if attacker.DummyHits % DUMMY_HITS_PER_XP == 0 then
				local styleService = service("StyleService")
				if styleService and styleService.AddMasteryXP then
					task.spawn(styleService.AddMasteryXP, attackerPlayer, 1)
				end
			end
		end
	end

	local info = {
		Action = spec.Action,
		Technique = spec.Technique,
		Damage = damage,
		Blocked = blocked,
		GuardBreak = broke,
		IsHeat = spec.IsHeat,
		Hits = attacker.HitsDealt[target.Model],
	}
	CombatService.HitLanded:Fire(attacker.Model, target.Model, info)
	if spec.IsHeat then
		CombatService.HeatLanded:Fire(attacker.Model, target.Model)
	end

	if target.HP <= 0 then
		handleZeroHP(target, attacker)
	end
end

-- Runs fn after a windup unless the attacker was interrupted (hit, stunned, downed, left stance).
local function afterWindup(f: Fighter, windup: number, fn: () -> ())
	local token = f.ActionToken
	f.BusyUntil = os.clock() + windup
	task.delay(windup, function()
		if f.Removed or f.ActionToken ~= token or isDowned(f) or isStunned(f) or not f.Stance then
			return
		end
		f.BusyUntil = 0
		fn()
	end)
end

local function canAttack(f: Fighter): boolean
	return not f.Blocking and os.clock() >= f.BusyUntil
end

-- Actions -----------------------------------------------------------------------------------------------
local function doM1(f: Fighter, overrides: Overrides?): boolean
	if not canAttack(f) or onCooldown(f, "M1") then
		return false
	end
	local clock = os.clock()
	if clock - f.LastM1At < Combat.M1Interval then
		return false
	end
	if clock - f.LastM1At > Combat.M1ComboReset then
		f.ComboIndex = 0
	end
	f.ComboIndex = (f.ComboIndex % #Combat.M1Damage) + 1
	f.LastM1At = clock
	local index = f.ComboIndex
	local finisher = index == #Combat.M1Damage
	if finisher then
		f.ComboIndex = 0
		setCooldown(f, "M1", M1_FINISHER_RECOVERY)
	end
	fx({ Kind = "Swing", Attacker = f.Model, Action = "M1", Index = index })
	local style = getStyle(f)
	local target = findTarget(f, Combat.M1Range, 0)
	if target then
		resolveHit(f, target, {
			Action = "M1",
			Index = index,
			Damage = if overrides and overrides.Damage then overrides.Damage else Combat.M1Damage[index],
			IsHeavy = false,
			IgnoresBlock = false,
			Unparryable = false,
			PostureDamage = if finisher then style.Passive.M1FinisherPostureDamage or 0 else 0,
			BlockPostureCost = Combat.BlockPostureCostPerHit,
			Knockback = if finisher then Combat.M1FinisherKnockback else 0,
			KnockdownTime = 0,
			IsHeat = false,
			MinTargetHP = overrides and overrides.MinTargetHP,
		})
	end
	return true
end

local function doHeavy(f: Fighter, overrides: Overrides?): boolean
	if not canAttack(f) or onCooldown(f, "Heavy") then
		return false
	end
	local windup = if overrides and overrides.Windup then overrides.Windup else Combat.HeavyWindup
	setCooldown(f, "Heavy", Combat.HeavyCooldown)
	f.ComboIndex = 0
	fx({ Kind = "Swing", Attacker = f.Model, Action = "Heavy", Windup = windup })
	afterWindup(f, windup, function()
		local target = findTarget(f, Combat.HeavyRange, 0)
		if target then
			resolveHit(f, target, {
				Action = "Heavy",
				Damage = if overrides and overrides.Damage then overrides.Damage else Combat.HeavyDamage,
				IsHeavy = true,
				IgnoresBlock = false,
				Unparryable = false,
				PostureDamage = 0,
				BlockPostureCost = Combat.HeavyPostureDamage,
				Knockback = 0,
				KnockdownTime = 0,
				IsHeat = false,
				MinTargetHP = overrides and overrides.MinTargetHP,
			})
		end
	end)
	return true
end

local function isKick(name: string): boolean
	return name:find("Kick") ~= nil or name:find("Teep") ~= nil or name:find("Knee") ~= nil
end

local function doTechnique(f: Fighter, slot: string, overrides: Overrides?): boolean
	if not canAttack(f) or onCooldown(f, slot) then
		return false
	end
	local style = getStyle(f)
	local tech: Styles.Technique? = (style :: any)[slot]
	if not tech then
		return false
	end
	local player = f.Player
	if player then
		local styleService = service("StyleService")
		if not styleService or not styleService.HasTechnique or not styleService.HasTechnique(player, slot) then
			return false
		end
	end
	local isHeat = slot == "Heat"
	if isHeat and f.Heat < Combat.MaxHeat then
		return false
	end
	if tech.RequiresParry and os.clock() - f.LastParryAt > Styles.ParryWindowForCounter then
		return false
	end

	setCooldown(f, slot, tech.Cooldown)
	f.ComboIndex = 0
	if isHeat then
		f.Heat = 0
		setAttr(f, "Heat", 0)
		quest(player, "UseHeat")
	end
	local windup = if overrides and overrides.Windup then overrides.Windup else math.max(tech.Windup, tech.Charge or 0)
	local lunge = if tech.Kind == "Lunge" then tech.LungeDistance or 0 else 0
	fx({
		Kind = if isHeat then "Heat" else "Technique",
		Attacker = f.Model,
		Action = slot,
		Technique = tech.Name,
		TechKind = tech.Kind,
		Windup = windup,
		Lunge = if lunge > 0 then lunge else nil,
	})
	if lunge > 0 and f.IsNPC then
		local duration = math.max(windup, Motion.LungeMinDuration)
		pushRoot(f.Root, flat(f.Root.CFrame.LookVector).Unit * (lunge / duration), duration)
	end

	local range = tech.Range
	local kickBonus = style.Passive.KickReachBonus
	if kickBonus and isKick(tech.Name) then
		range += kickBonus
	end
	local isGrab = tech.Kind == "Grab"
	local function spec(isLast: boolean): HitSpec
		return {
			Action = slot,
			Damage = if overrides and overrides.Damage then overrides.Damage else tech.Damage,
			IsHeavy = false,
			IgnoresBlock = isGrab or tech.GuardBreak == true,
			Unparryable = isGrab,
			PostureDamage = tech.PostureDamage or 0,
			BlockPostureCost = Combat.BlockPostureCostPerHit,
			Knockback = if isLast then tech.Knockback or 0 else 0,
			KnockdownTime = if isLast then tech.KnockdownTime or 0 else 0,
			IsHeat = isHeat,
			Technique = tech.Name,
			MinTargetHP = overrides and overrides.MinTargetHP,
		}
	end

	afterWindup(f, windup, function()
		if tech.Kind == "MultiHit" then
			local hits = math.max(1, tech.Hits or 1)
			local interval = tech.HitInterval or Combat.M1Interval
			local token = f.ActionToken
			f.BusyUntil = os.clock() + hits * interval
			for i = 1, hits do
				if f.Removed or f.ActionToken ~= token or isStunned(f) or isDowned(f) then
					break
				end
				local target = findTarget(f, range, lunge)
				if target then
					resolveHit(f, target, spec(i == hits))
				end
				if i < hits then
					task.wait(interval)
				end
			end
			if f.ActionToken == token then
				f.BusyUntil = 0
			end
		else
			local target = findTarget(f, range, lunge)
			if target then
				resolveHit(f, target, spec(true))
			end
		end
	end)
	return true
end

local function doDash(f: Fighter): boolean
	if onCooldown(f, "Dash") or f.Blocking then
		return false
	end
	if not spendPosture(f, Combat.DashPostureCost) then
		return false
	end
	local passive = getStyle(f).Passive
	setCooldown(f, "Dash", CombatMath.DashCooldown(Combat.DashCooldown, passive, buff(f.Player, "DashCooldown")))
	fx({ Kind = "Dash", Attacker = f.Model })
	if f.IsNPC then
		pushRoot(f.Root, flat(f.Root.CFrame.LookVector).Unit * (Combat.DashDistance / Combat.DashDuration), Combat.DashDuration)
	end
	return true
end

local function doWeave(f: Fighter): boolean
	if onCooldown(f, "Weave") or f.Blocking then
		return false
	end
	if not spendPosture(f, Combat.WeavePostureCost) then
		return false
	end
	local passive = getStyle(f).Passive
	setCooldown(f, "Weave", CombatMath.WeaveCooldown(Combat.WeaveCooldown, passive))
	f.IFramesUntil = os.clock() + CombatMath.WeaveIFrames(Combat.WeaveIFrames, passive)
	fx({ Kind = "Weave", Attacker = f.Model })
	return true
end

local function hittableNPCNearby(f: Fighter): boolean
	for _, other in fighters do
		if other.IsNPC and other ~= f and (other.Root.Position - f.Root.Position).Magnitude <= Motion.GreenStanceNPCRadius then
			if canHit(f, other) then
				return true
			end
		end
	end
	return false
end

-- Green zones put the stance away, unless dueling or training on a nearby NPC.
local function stanceAllowedHere(f: Fighter): boolean
	if not f.Player then
		return true
	end
	if zoneType(f) ~= "Green" then
		return true
	end
	return inDuel(f.Player) or hittableNPCNearby(f)
end

local function setStance(f: Fighter, on: boolean)
	if f.Stance == on then
		return
	end
	f.Stance = on
	setAttr(f, "Stance", on)
	if not on then
		interrupt(f)
		setBlocking(f, false)
		setSprinting(f, false)
	else
		dismount(f.Player)
	end
end

local function perform(f: Fighter, action: string, overrides: Overrides?): boolean
	if f.Removed or isDowned(f) or f.HP <= 0 then
		if action == "BlockEnd" then
			setBlocking(f, false)
		elseif action == "SprintEnd" then
			setSprinting(f, false)
		end
		return false
	end
	if ENDING_ACTIONS[action] then
		if action == "BlockEnd" then
			setBlocking(f, false)
		else
			setSprinting(f, false)
		end
		return true
	end
	if action == "Stance" then
		if f.Stance then
			setStance(f, false)
			return true
		end
		if not stanceAllowedHere(f) then
			if f.Player then
				Notify.Send(f.Player, "Safe zone: no fighting here", "zone")
			end
			return false
		end
		setStance(f, true)
		return true
	end
	if not f.Stance or isStunned(f) then
		return false
	end

	if action == "M1" then
		return doM1(f, overrides)
	elseif action == "Heavy" then
		return doHeavy(f, overrides)
	elseif action == "BlockStart" then
		if f.Blocking or os.clock() < f.BusyUntil then
			return false
		end
		local clock = os.clock()
		f.ParryEligible = clock - f.LastBlockStartAt >= Combat.ParryLockout
		f.LastBlockStartAt = clock
		f.BlockStartedAt = clock
		setSprinting(f, false)
		setBlocking(f, true)
		return true
	elseif action == "Dash" then
		return doDash(f)
	elseif action == "Weave" then
		return doWeave(f)
	elseif action == "SprintStart" then
		if f.Blocking or f.Posture <= 0 then
			return false
		end
		setSprinting(f, true)
		return true
	elseif TECH_SLOTS[action] then
		return doTechnique(f, action, overrides)
	end
	return false
end

-- Registry --------------------------------------------------------------------------------------------
local function unregister(model: Model)
	local f = fighters[model]
	if not f then
		return
	end
	f.Removed = true
	fighters[model] = nil
	f.Cleaner:Clean()
	if model.Parent then
		CollectionService:RemoveTag(model, FIGHTER_TAG)
	end
	CombatService.FighterRemoved:Fire(model)
end

local function register(model: Model, opts: FighterOpts): Model?
	if fighters[model] then
		unregister(model)
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		warn("[CombatService] RegisterFighter needs a Humanoid and a HumanoidRootPart: " .. model:GetFullName())
		return nil
	end
	local isNPC = opts.IsNPC == true or opts.Player == nil
	local f: Fighter = {
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Player = opts.Player,
		IsNPC = isNPC,
		Owner = opts.Owner,
		IgnoreZones = opts.IgnoreZones == true,
		Dummy = opts.Dummy == true,
		Mode = opts.Mode,
		Opts = opts,
		Cleaner = Cleaner.new(),
		StyleId = opts.Style or Styles.DefaultStyle,
		BaseWalkSpeed = StarterPlayer.CharacterWalkSpeed,
		Reach = 1,
		BaseJumpHeight = if opts.Player then StarterPlayer.CharacterJumpHeight else humanoid.JumpHeight,
		StatsRefreshedAt = 0,
		HP = 1,
		MaxHP = 0,
		Posture = Combat.MaxPosture,
		Heat = 0,
		Stance = isNPC and not opts.Dummy,
		Blocking = false,
		Sprinting = false,
		StunnedUntil = 0,
		GuardBrokenUntil = 0,
		ComboIndex = 0,
		LastM1At = 0,
		Cooldowns = {},
		BusyUntil = 0,
		ActionToken = 0,
		BlockStartedAt = 0,
		LastBlockStartAt = -math.huge,
		ParryEligible = false,
		LastParryAt = -math.huge,
		LastPostureSpendAt = 0,
		IFramesUntil = 0,
		InCombat = false,
		LastCombatAt = 0,
		LastHitTakenAt = -math.huge,
		HitsDealt = {},
		DummyHits = 0,
		ZeroHandled = false,
		Removed = false,
	}
	fighters[model] = f
	refreshFighterStats(f)
	f.HP = f.MaxHP
	model:SetAttribute("Fighter", true)
	model:SetAttribute("IsNPC", isNPC)
	model:SetAttribute("DisplayName", opts.DisplayName or (if opts.Player then opts.Player.DisplayName else model.Name))
	model:SetAttribute("Downed", false)
	model:SetAttribute("Protected", false)
	syncAll(f)
	CollectionService:AddTag(model, FIGHTER_TAG)

	f.Cleaner:Add(model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			unregister(model)
		end
	end))
	f.Cleaner:Add(humanoid.Died:Connect(function()
		unregister(model)
	end))
	CombatService.FighterRegistered:Fire(model)
	return model
end

local function onCharacterAdded(player: Player, character: Model)
	local data = service("DataService")
	if data then
		data.WaitForProfile(player)
	end
	if player.Parent ~= Players or player.Character ~= character then
		return
	end
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not root or player.Character ~= character then
		return
	end
	register(character, { Player = player, IsNPC = false, DisplayName = player.DisplayName })
end

local function onPlayerAdded(player: Player)
	local cleaner = Cleaner.new()
	playerCleaners[player] = cleaner
	cleaner:Add(player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end))
	cleaner:Add(player.CharacterRemoving:Connect(function(character)
		unregister(character)
	end))
	-- Style or height changes re-apply stats.
	cleaner:Add(player:GetAttributeChangedSignal("Style"):Connect(function()
		CombatService.RefreshStats(player)
	end))
	cleaner:Add(player:GetAttributeChangedSignal("HeightCm"):Connect(function()
		CombatService.RefreshStats(player)
	end))
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

local function onPlayerRemoving(player: Player)
	local character = player.Character
	if character then
		unregister(character)
	end
	for model, f in fighters do
		if f.Player == player then
			unregister(model)
		end
	end
	local cleaner = playerCleaners[player]
	if cleaner then
		cleaner:Clean()
		playerCleaners[player] = nil
	end
	limiter:Remove(player)
end

-- Loop (10 Hz): combat timeout, regen, posture, sprint drain, stance in Green, buff refresh ------------
local function tickFighter(f: Fighter, dt: number)
	local clock = os.clock()
	if f.InCombat and clock - f.LastCombatAt >= Combat.CombatTimeout then
		endCombat(f)
	end
	local downed = isDowned(f)

	-- Safety net: a KO that nobody resolved (e.g. a duel KO without a revive) stands up after the fight.
	if f.HP <= 0 and not downed and not f.InCombat then
		CombatService.Revive(f.Model, Combat.DuelLoserHPFraction)
	end

	-- Out-of-combat HP regen
	if not f.InCombat and not downed and f.HP > 0 and f.HP < f.MaxHP then
		f.HP = math.min(f.MaxHP, f.HP + Combat.OutOfCombatRegenFraction * f.MaxHP * dt)
		setAttr(f, "HP", math.floor(f.HP * 10 + 0.5) / 10)
	end

	-- Posture: blocking and sprinting hold off regen; sprinting drains.
	if f.Sprinting then
		setPosture(f, f.Posture - Combat.SprintPostureCostPerSecond * dt)
		f.LastPostureSpendAt = clock
		if f.Posture <= 0 then
			setSprinting(f, false)
		end
	elseif f.Blocking then
		f.LastPostureSpendAt = clock
	elseif f.Posture < Combat.MaxPosture and serverNow() >= f.GuardBrokenUntil then
		local rate = Combat.PostureRegenPerSecond * (1 + buff(f.Player, "PostureRegen"))
		setPosture(f, CombatMath.RegenPosture(f.Posture, Combat.MaxPosture, dt, clock - f.LastPostureSpendAt, Combat.PostureRegenDelay, rate))
	end

	if f.Player then
		if f.Stance and not downed and not stanceAllowedHere(f) then
			setStance(f, false)
		end
		if clock - f.StatsRefreshedAt >= STAT_REFRESH_INTERVAL then
			refreshFighterStats(f)
		else
			applyMovement(f)
		end
	end
end

local function onRequest(player: Player, action: any, data: any)
	if type(action) ~= "string" or not ACTIONS[action] then
		return
	end
	if data ~= nil and (type(data) ~= "table" or (data.Direction ~= nil and typeof(data.Direction) ~= "Vector3")) then
		return
	end
	if not limiter:Allow(player) then
		return
	end
	local character = player.Character
	local f = character and fighters[character]
	if not f or f.Player ~= player then
		return
	end
	perform(f, action)
end

-- Public API -----------------------------------------------------------------------------------------
function CombatService.RegisterFighter(model: Model, opts: FighterOpts?): Model?
	return register(model, opts or {})
end

function CombatService.UnregisterFighter(model: Model)
	unregister(model)
end

function CombatService.IsFighter(model: Model): boolean
	return fighters[model] ~= nil
end

function CombatService.IsInCombat(player: Player): boolean
	local character = player.Character
	local f = character and fighters[character]
	return f ~= nil and f.InCombat
end

function CombatService.IsDowned(player: Player): boolean
	local character = player.Character
	if not character then
		return false
	end
	local knockout = service("KnockoutService")
	if knockout and knockout.IsDowned and knockout.IsDowned(character) then
		return true
	end
	return character:GetAttribute("Downed") == true
end

function CombatService.RefreshStats(player: Player)
	local character = player.Character
	local f = character and fighters[character]
	if f then
		refreshFighterStats(f)
	end
end

-- Re-applies walk speed/jump from the current state (KnockoutService calls it after Downed changes).
function CombatService.RefreshMovement(model: Model)
	local f = fighters[model]
	if f then
		applyMovement(f)
	end
end

function CombatService.Heal(player: Player, amount: number): boolean
	local character = player.Character
	local f = character and fighters[character]
	if not f or f.InCombat or isDowned(f) or f.HP <= 0 or amount <= 0 or f.HP >= f.MaxHP then
		return false
	end
	f.HP = math.min(f.MaxHP, f.HP + amount)
	setAttr(f, "HP", math.floor(f.HP * 10 + 0.5) / 10)
	return true
end

-- Clears the downed state and sets HP to a fraction of MaxHP.
function CombatService.Revive(model: Model, hpFraction: number)
	local f = fighters[model]
	local knockout = service("KnockoutService")
	if knockout and knockout.Cancel then
		knockout.Cancel(model)
	end
	model:SetAttribute("Downed", false)
	if not f then
		return
	end
	f.HP = math.clamp(f.MaxHP * hpFraction, 1, f.MaxHP)
	f.ZeroHandled = false
	setAttr(f, "HP", math.floor(f.HP * 10 + 0.5) / 10)
	applyMovement(f)
end

-- Internal API (KnockoutService, NPCService) --------------------------------------------------------

-- Run an action for any fighter through the same validation as Combat_Request (NPC brains use this).
function CombatService.PerformAction(model: Model, action: string, overrides: Overrides?): boolean
	local f = fighters[model]
	if not f or not ACTIONS[action] then
		return false
	end
	return perform(f, action, overrides)
end

-- May attacker hit target? ignoreDowned = true checks permission to Finish a downed target.
function CombatService.CanHit(attackerModel: Model, targetModel: Model, ignoreDowned: boolean?): boolean
	local a, t = fighters[attackerModel], fighters[targetModel]
	if not a or not t then
		return false
	end
	return canHit(a, t, ignoreDowned)
end

-- Hits attacker landed on target since attacker's current fight started.
function CombatService.GetHits(attackerModel: Model?, targetModel: Model?): number
	if not attackerModel or not targetModel then
		return 0
	end
	local f = fighters[attackerModel]
	return if f then f.HitsDealt[targetModel] or 0 else 0
end

function CombatService.GetLastHitTakenAt(model: Model): number
	local f = fighters[model]
	return if f then f.LastHitTakenAt else -math.huge
end

function CombatService.GetFighterModels(): { Model }
	local list = {}
	for model in fighters do
		table.insert(list, model)
	end
	return list
end

function CombatService.GetMaxHP(model: Model): number
	local f = fighters[model]
	return if f then f.MaxHP else 0
end

function CombatService.IsStunned(model: Model): boolean
	local f = fighters[model]
	return f ~= nil and isStunned(f)
end

function CombatService.IsBusy(model: Model): boolean
	local f = fighters[model]
	return f ~= nil and os.clock() < f.BusyUntil
end

function CombatService.SetStance(model: Model, on: boolean)
	local f = fighters[model]
	if f then
		setStance(f, on)
	end
end

-- Lifecycle ------------------------------------------------------------------------------------------
function CombatService.Init(services: any)
	Services = services
	Net.Event("Combat_Request").OnServerEvent:Connect(onRequest)
end

function CombatService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	local last = os.clock()
	while true do
		task.wait(TICK)
		local clock = os.clock()
		local dt = math.min(clock - last, TICK * 5)
		last = clock
		for model, f in fighters do
			if model.Parent == nil then
				unregister(model)
			else
				local ok, err = pcall(tickFighter :: any, f, dt)
				if not ok then
					warn("[CombatService] tick failed for " .. model.Name .. ": " .. tostring(err))
				end
			end
		end
	end
end

return CombatService
