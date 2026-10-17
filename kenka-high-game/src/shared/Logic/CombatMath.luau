--!strict
-- Combat calculations shared by server validation and client prediction (blueprint section 1.4).
-- Pure: every input is a plain value or table.

type Passive = {
	LowHPDamageBonus: number?,
	LowHPThreshold: number?,
	DashCooldownReduction: number?,
	HeavyDamageBonus: number?,
	WeaveCooldownReduction: number?,
	WeaveIFrameBonus: number?,
	KnockbackResistance: number?,
	KickReachBonus: number?,
}

export type DamageInput = {
	BaseDamage: number,
	IsHeavy: boolean,
	AttackerHP: number,
	AttackerMaxHP: number,
	AttackerPassive: Passive?,
	TargetBlocking: boolean,
	TargetGuardBroken: boolean,
	IgnoresBlock: boolean, -- guard breaks and grabs
	BlockDamageTaken: number,
	GuardBreakMultiplier: number,
}

export type DamageResult = { Damage: number, Blocked: boolean }

local CombatMath = {}

function CombatMath.Damage(input: DamageInput): DamageResult
	local damage = input.BaseDamage
	local passive = input.AttackerPassive
	if passive then
		if passive.LowHPDamageBonus and passive.LowHPThreshold and input.AttackerMaxHP > 0 then
			if input.AttackerHP / input.AttackerMaxHP < passive.LowHPThreshold then
				damage *= 1 + passive.LowHPDamageBonus
			end
		end
		if input.IsHeavy and passive.HeavyDamageBonus then
			damage *= 1 + passive.HeavyDamageBonus
		end
	end

	local blocked = input.TargetBlocking and not input.IgnoresBlock and not input.TargetGuardBroken
	if blocked then
		damage *= input.BlockDamageTaken
	end
	if input.TargetGuardBroken then
		damage *= input.GuardBreakMultiplier
	end
	return { Damage = math.floor(damage * 10 + 0.5) / 10, Blocked = blocked }
end

-- Was a block started recently enough to count as a parry?
function CombatMath.IsParry(blockStartedAt: number, hitAt: number, window: number): boolean
	local elapsed = hitAt - blockStartedAt
	return elapsed >= 0 and elapsed <= window
end

-- Server reach check: horizontal distance within reach, plus a latency allowance.
function CombatMath.InReach(distance: number, baseRange: number, reachMultiplier: number, allowance: number): boolean
	return distance <= baseRange * reachMultiplier + allowance
end

-- Is the target roughly in front? dot = attackerLook . directionToTarget (both unit vectors).
function CombatMath.InFront(dot: number, minimumDot: number): boolean
	return dot >= minimumDot
end

function CombatMath.DashCooldown(base: number, passive: Passive?, buffDelta: number): number
	local reduction = if passive and passive.DashCooldownReduction then passive.DashCooldownReduction else 0
	return math.max(0.5, base - reduction + buffDelta)
end

function CombatMath.WeaveCooldown(base: number, passive: Passive?): number
	local reduction = if passive and passive.WeaveCooldownReduction then passive.WeaveCooldownReduction else 0
	return math.max(0.5, base - reduction)
end

function CombatMath.WeaveIFrames(base: number, passive: Passive?): number
	return base + (if passive and passive.WeaveIFrameBonus then passive.WeaveIFrameBonus else 0)
end

function CombatMath.Knockback(distance: number, targetPassive: Passive?): number
	local resistance = if targetPassive and targetPassive.KnockbackResistance then targetPassive.KnockbackResistance else 0
	return distance * (1 - resistance)
end

-- Mastery: level L needs perLevel * L XP to reach L + 1. Returns new level and leftover XP.
function CombatMath.AddMasteryXP(level: number, xp: number, gained: number, perLevel: number, maxLevel: number): (number, number)
	level, xp = level, xp + gained
	while level < maxLevel and xp >= perLevel * level do
		xp -= perLevel * level
		level += 1
	end
	if level >= maxLevel then
		xp = 0
	end
	return level, xp
end

-- Posture after regen over dt seconds, if enough time passed since the last posture spend.
function CombatMath.RegenPosture(posture: number, maxPosture: number, dt: number, sinceSpend: number, delay: number, rate: number): number
	if sinceSpend < delay then
		return posture
	end
	return math.min(maxPosture, posture + rate * dt)
end

return CombatMath
