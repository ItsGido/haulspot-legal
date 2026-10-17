-- Animation asset ids and combat visual/motion tuning.
-- An id of 0 means "use the built-in procedural animation" (FXController tweens the Motor6D joints).
-- Paste an uploaded animation id (a number, without "rbxassetid://") to replace one.

local Animations = {
	-- Looping poses (played while the matching attribute is true)
	StanceIdle = 0,
	Block = 0,
	Downed = 0,

	-- One-shots
	M1_1 = 0,
	M1_2 = 0,
	M1_3 = 0,
	M1_4 = 0,
	Heavy = 0,
	Dash = 0,
	Weave = 0,
	Finish = 0,

	-- Techniques, keyed by the technique Name in Config/Styles
	Techniques = {
		-- Street Brawler
		["Headbutt"] = 0,
		["Haymaker"] = 0,
		["Dropkick"] = 0,
		-- Boxing
		["Feint Jab"] = 0,
		["Counter Hook"] = 0,
		["Rush Combo"] = 0,
		-- Karate
		["Front Kick"] = 0,
		["Breaking Chop"] = 0,
		["Iron Fist"] = 0,
		-- Judo
		["Hip Toss"] = 0,
		["Foot Sweep"] = 0,
		["Shoulder Slam"] = 0,
		-- Muay Thai
		["Teep"] = 0,
		["Spinning Elbow"] = 0,
		["Flying Knee"] = 0,
		-- Capoeira
		["Cartwheel Kick"] = 0,
		["Rasteira"] = 0,
		["Armada Spin"] = 0,
		-- Sumo
		["Slap Barrage"] = 0,
		["Charge"] = 0,
		["Ring-Out Shove"] = 0,
		-- Taekwondo
		["Axe Kick"] = 0,
		["Spinning Back Kick"] = 0,
		["Tornado Kick"] = 0,
	},

	-- Motion tuning shared by the server (NPC movement) and the client (own character, FX).
	Motion = {
		KnockbackDuration = 0.25, -- seconds a knockback push lasts
		KnockbackLift = 12, -- upward velocity (studs/s) added to a knockback
		LungeMinDuration = 0.15, -- a lunge never moves faster than distance / this
		StunWalkSpeedMultiplier = 0.35, -- walk speed while stunned
		VerticalHitTolerance = 6, -- studs of height difference a melee hit allows
		GreenStanceNPCRadius = 30, -- stance stays allowed in a Green zone this close to a hittable NPC
	},

	-- Client effects
	FX = {
		DamageNumberTime = 0.6,
		DamageNumberRise = 2.5, -- studs the number floats up
		DamageNumberStart = 2, -- studs above the target where it pops up
		CameraShakeHit = 0.3, -- shake strength on hits (blueprint 4.5)
		CameraShakeHeavy = 0.6,
		CameraShakeTime = 0.2,
		HitStopTime = 0.05, -- the brief camera nudge on a hit
		HitStopNudge = 0.15, -- studs
		ParryFlashTime = 0.15,
		ParryFlashStart = 0.8, -- transparency at the start of the white flash
		StampTime = 0.7,
		HeatZoomTime = 0.6,
		HeatZoomFov = 15, -- degrees the FOV narrows during a Heat move
		SparkCount = 6,
		SparkTime = 0.25,
		SparkSpeed = 6, -- studs the sparks fly
		PoseSmoothing = 14, -- higher = faster blend into stance/block/downed poses
		PoseMaxDistance = 150, -- procedural poses are skipped for fighters farther than this
		DownedDrop = 2.2, -- studs the root drops for the crawl pose
		SwingRecover = 0.18, -- seconds to return from a strike pose
		StrikeTime = 0.1, -- seconds from windup pose to full extension
	},
}

return Animations
