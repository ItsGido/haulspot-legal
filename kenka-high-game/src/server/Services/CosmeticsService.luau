--!strict
-- Character looks: height scale, uniform jacket color, capsule cosmetics (Armband, Aura, Trail,
-- Title, KOStamp) and the Nurse's Office mirror (character creator). Blueprint sections 1.5, 5.11, 6.7.
--
--   CosmeticsService.Apply(player)       -- re-applies everything to the current character
--   CosmeticsService.GetKOStamp(player)  -- "K.O." or the equipped KO stamp text
--
-- Decisions (greybox until clothing assets exist):
--   * Uniform: a thin welded "Jacket" box over the torso in the uniform's color. UniformClassic
--     shows NO jacket, so the player's own avatar clothing stays visible by default.
--   * Hair color 1 keeps the avatar's own hair texture; 2-12 tint every hair accessory Handle.
--   * Face / Hair numbers are saved in profile.Appearance; applying them visually is a TODO for the
--     art pass (needs face decals and hair accessory assets).
--   * Player attributes: TitleText (equipped title text) and TitleColor (its hex color).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Capsules = require(ReplicatedStorage.Shared.Config.Capsules)
local HeightStats = require(ReplicatedStorage.Shared.Logic.HeightStats)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local Net = require(ReplicatedStorage.Shared.Util.Net)
local RateLimiter = require(ReplicatedStorage.Shared.Util.RateLimiter)
local EconomyUtil = require(script.Parent.Parent.Systems.EconomyUtil)

local CosmeticsService = {}
CosmeticsService.Priority = 40

local Services: any

local FOLDER_NAME = "EconomyCosmetics"
local APPEARANCE_OPTIONS = 12 -- faces, hairs and hair colors each have 12 free options
local MIRROR_RANGE = 24 -- studs from a Mirror interactable to save changes
local APPEARANCE_WAIT = 6 -- seconds to wait for the avatar to load before applying
local DEFAULT_KO_STAMP = "K.O."

-- Hair color swatches (1 = natural, keep the avatar's texture). Sent to the Creator screen.
local HAIR_COLORS = {
	"#2B211C", -- 1 natural (not applied)
	"#0F1016",
	"#5A3A22",
	"#A86B3C",
	"#E8C77A",
	"#F5F1E8",
	"#8C92A4",
	"#E4322B",
	"#FF9EC4",
	"#3FA7FF",
	"#5FE08A",
	"#B04DFF",
}

local limiter = RateLimiter.new(4, 2)
local applyVersion: { [Player]: number } = {}
local uiOpen = Net.Event("UI_Open")

-- Helpers ----------------------------------------------------------------------

local function newPart(name: string, size: Vector3, color: Color3, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Shape = shape or Enum.PartType.Block
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function weldTo(part: BasePart, target: BasePart, offset: CFrame, parent: Instance)
	part.CFrame = target.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = target
	weld.Part1 = part
	weld.Parent = part
	part.Parent = parent
end

local function findPart(character: Model, names: { string }): BasePart?
	for _, name in names do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

local function equippedItem(profile: any, slot: string): Capsules.Cosmetic?
	local id = profile.Cosmetics.Equipped[slot]
	if type(id) ~= "string" or not profile.Cosmetics.Owned[id] then
		return nil
	end
	local item = Capsules.ById(id)
	if item and item.Slot == slot then
		return item
	end
	return nil
end

local function color(hexValue: string?, fallback: string): Color3
	local ok, result = pcall(Color3.fromHex, hexValue or fallback)
	return if ok then result else Color3.fromHex(fallback)
end

-- Pieces --------------------------------------------------------------------------

local function applyHeight(humanoid: Humanoid, profile: any)
	if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return -- scale values only work on R15 rigs
	end
	local scale = HeightStats.Get(profile.HeightCm).Scale
	local okGet, description = pcall(function(): HumanoidDescription
		return humanoid:GetAppliedDescription()
	end)
	if not okGet then
		warn("[CosmeticsService] GetAppliedDescription failed: " .. tostring(description))
		return
	end
	local function near(value: number): boolean
		return math.abs(value - scale) < 1e-3
	end
	if near(description.HeightScale) and near(description.WidthScale) and near(description.DepthScale) and near(description.HeadScale) then
		return -- already applied; applying is slow and rebuilds accessories
	end
	description.HeightScale = scale
	description.WidthScale = scale
	description.DepthScale = scale
	description.HeadScale = scale
	local ok, err = pcall(function()
		humanoid:ApplyDescriptionAsync(description)
	end)
	if not ok then
		warn("[CosmeticsService] ApplyDescriptionAsync failed: " .. tostring(err))
	end
end

local function applyHairColor(character: Model, profile: any)
	local index = profile.Appearance and profile.Appearance.HairColor or 1
	if type(index) ~= "number" or index <= 1 or not HAIR_COLORS[index] then
		return
	end
	local tint = Color3.fromHex(HAIR_COLORS[index])
	for _, child in character:GetChildren() do
		if child:IsA("Accessory") and child.AccessoryType == Enum.AccessoryType.Hair then
			local handle = child:FindFirstChild("Handle")
			if handle and handle:IsA("MeshPart") then
				handle.TextureID = ""
				handle.Color = tint
			elseif handle and handle:IsA("BasePart") then
				local mesh = handle:FindFirstChildOfClass("SpecialMesh")
				if mesh then
					mesh.TextureId = ""
				end
				handle.Color = tint
			end
		end
	end
end

local function buildJacket(character: Model, profile: any, folder: Folder)
	local uniformId = profile.Uniform
	if uniformId == "UniformClassic" then
		return
	end
	local item = Economy.Items[uniformId]
	if not item or not item.UniformColor then
		return
	end
	local torso = findPart(character, { "UpperTorso", "Torso" })
	if not torso then
		return
	end
	local pad = Vector3.new(0.12, 0.06, 0.12)
	local jacket = newPart("Jacket", torso.Size + pad, color(item.UniformColor, "#1B1F33"))
	jacket.Material = Enum.Material.Fabric
	weldTo(jacket, torso, CFrame.new(0, 0.03, 0), folder)
end

local function buildArmband(character: Model, item: Capsules.Cosmetic, folder: Folder)
	local arm = findPart(character, { "LeftUpperArm", "Left Arm" })
	if not arm then
		return
	end
	local diameter = math.max(arm.Size.X, arm.Size.Z) + 0.12
	-- Cylinders run along X; rotate so the ring wraps the vertical arm.
	local ring = newPart("Armband", Vector3.new(0.35, diameter, diameter), color(item.Color, "#E4322B"), Enum.PartType.Cylinder)
	local yOffset = if arm.Name == "Left Arm" then arm.Size.Y * 0.25 else 0
	weldTo(ring, arm, CFrame.new(0, yOffset, 0) * CFrame.Angles(0, 0, math.pi / 2), folder)
end

local function buildAura(root: BasePart, item: Capsules.Cosmetic, folder: Folder)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "EconomyAura"
	local c1 = color(item.Color, "#FFFFFF")
	local c2 = color(item.Color2 or item.Color, "#FFFFFF")
	emitter.Color = ColorSequence.new(c1, c2)
	emitter.LightEmission = 0.7
	emitter.Rate = 18
	emitter.Lifetime = NumberRange.new(0.8, 1.4)
	emitter.Speed = NumberRange.new(1.5, 3)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, 4, 0)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = root
	-- Track it in the folder so a rebuild removes it.
	local marker = Instance.new("ObjectValue")
	marker.Name = "AuraRef"
	marker.Value = emitter
	marker.Parent = folder
end

local function buildTrail(root: BasePart, item: Capsules.Cosmetic, folder: Folder)
	local top = Instance.new("Attachment")
	top.Name = "EconomyTrailTop"
	top.Position = Vector3.new(0, 0.9, 0)
	top.Parent = root
	local bottom = Instance.new("Attachment")
	bottom.Name = "EconomyTrailBottom"
	bottom.Position = Vector3.new(0, -0.9, 0)
	bottom.Parent = root
	local trail = Instance.new("Trail")
	trail.Name = "EconomyTrail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = 0.35
	trail.MinLength = 0.1
	trail.LightEmission = 0.5
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(color(item.Color, "#FFFFFF"), color(item.Color2 or item.Color, "#FFFFFF"))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	-- Always enabled: a Trail only draws segments while its attachments move, so it shows on dashes and runs.
	trail.Enabled = true
	trail.Parent = root
	for _, instance in { top, bottom, trail } :: { Instance } do
		local marker = Instance.new("ObjectValue")
		marker.Name = "TrailRef"
		marker.Value = instance
		marker.Parent = folder
	end
end

local function clearCosmetics(character: Model)
	local old = character:FindFirstChild(FOLDER_NAME)
	if old then
		for _, child in old:GetChildren() do
			if child:IsA("ObjectValue") and child.Value then
				child.Value:Destroy()
			end
		end
		old:Destroy()
	end
end

-- Public API -------------------------------------------------------------------------

function CosmeticsService.Apply(player: Player)
	local profile = Services.DataService.GetProfile(player)
	local character = EconomyUtil.GetCharacter(player)
	if not profile or not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return
	end
	local version = (applyVersion[player] or 0) + 1
	applyVersion[player] = version

	applyHeight(humanoid, profile) -- yields
	if applyVersion[player] ~= version or player.Character ~= character or not character.Parent then
		return -- a newer Apply started, or the character changed while we waited
	end

	clearCosmetics(character)
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = character

	buildJacket(character, profile, folder)
	local armband = equippedItem(profile, "Armband")
	if armband then
		buildArmband(character, armband, folder)
	end
	local aura = equippedItem(profile, "Aura")
	if aura then
		buildAura(root, aura, folder)
	end
	local trail = equippedItem(profile, "Trail")
	if trail then
		buildTrail(root, trail, folder)
	end
	applyHairColor(character, profile)

	local title = equippedItem(profile, "Title")
	player:SetAttribute("TitleText", if title then title.Text else nil)
	player:SetAttribute("TitleColor", if title then title.Color else nil)
end

function CosmeticsService.GetKOStamp(player: Player): string
	local profile = Services.DataService.GetProfile(player)
	if not profile then
		return DEFAULT_KO_STAMP
	end
	local item = equippedItem(profile, "KOStamp")
	return if item and item.Text then item.Text else DEFAULT_KO_STAMP
end

-- Character creator ----------------------------------------------------------------

local function heightIsFree(player: Player, profile: any): boolean
	return (not profile.TutorialDone) or profile.LastHeightChange == 0 or EconomyUtil.InTutorial(Services, player)
end

local function creatorData(player: Player, profile: any): any
	local remaining = math.max(0, profile.LastHeightChange + Economy.HeightChangeCooldown - os.time())
	return {
		FreeHeight = (not profile.TutorialDone) or profile.LastHeightChange == 0,
		HeightCm = profile.HeightCm,
		Appearance = profile.Appearance,
		Cost = Economy.HeightChangeCost,
		CooldownRemaining = if heightIsFree(player, profile) then 0 else remaining,
		HairColors = HAIR_COLORS,
		Options = APPEARANCE_OPTIONS,
	}
end

local function onSave(player: Player, changes: any): (boolean, string)
	if not limiter:Allow(player) then
		return false, "Slow down."
	end
	if type(changes) ~= "table" then
		return false, "Invalid changes."
	end
	local profile = Services.DataService.GetProfile(player)
	if not profile then
		return false, "Your data is still loading."
	end
	if
		not EconomyUtil.InTutorial(Services, player)
		and not EconomyUtil.NearInteractable(player, MIRROR_RANGE, function(entry)
			return entry.Kind == "Mirror"
		end)
	then
		return false, "Use the mirror in the Nurse's Office."
	end
	if EconomyUtil.InCombat(Services, player) then
		return false, "Not during a fight."
	end

	-- Validate everything before charging.
	local newHeight: number? = nil
	if changes.HeightCm ~= nil then
		if not EconomyUtil.IsNumber(changes.HeightCm) then
			return false, "Invalid height."
		end
		local cm = HeightStats.Clamp(changes.HeightCm)
		if cm ~= profile.HeightCm then
			newHeight = cm
		end
	end
	local appearance: { [string]: number } = {}
	for _, key in { "Face", "Hair", "HairColor" } do
		local value = changes[key]
		if value ~= nil then
			if not EconomyUtil.IsInt(value, 1, APPEARANCE_OPTIONS) then
				return false, "Invalid " .. key .. "."
			end
			appearance[key] = value
		end
	end

	local message = "Looking good!"
	if newHeight then
		if not heightIsFree(player, profile) then
			local remaining = profile.LastHeightChange + Economy.HeightChangeCooldown - os.time()
			if remaining > 0 then
				return false, "You can change your height again in " .. Format.Duration(remaining) .. "."
			end
			if not Services.DataService.SpendYen(player, Economy.HeightChangeCost) then
				return false, "A height change costs " .. Format.Yen(Economy.HeightChangeCost) .. "."
			end
			message = "Height changed for " .. Format.Yen(Economy.HeightChangeCost) .. "."
		end
		profile.HeightCm = newHeight
		profile.LastHeightChange = os.time()
	end
	for key, value in appearance do
		profile.Appearance[key] = value
	end
	Services.DataService.Replicate(player, "HeightCm", "Appearance", "LastHeightChange")

	if newHeight and Services.CombatService then
		Services.CombatService.RefreshStats(player)
	end
	task.spawn(CosmeticsService.Apply, player)
	if Services.QuestService then
		Services.QuestService.Progress(player, "Customize", 1)
	end
	return true, message
end

-- Lifecycle ----------------------------------------------------------------------------

local function onCharacterAdded(player: Player, character: Model)
	local profile = Services.DataService.WaitForProfile(player)
	if not profile or player.Character ~= character then
		return
	end
	character:WaitForChild("Humanoid", APPEARANCE_WAIT)
	local waited = 0
	while not player:HasAppearanceLoaded() and waited < APPEARANCE_WAIT and player.Character == character do
		waited += task.wait(0.1)
	end
	if player.Character == character then
		CosmeticsService.Apply(player)
	end
end

function CosmeticsService.Init(services: any)
	Services = services
	Net.Function("Creator_Save").OnServerInvoke = onSave
	Services.InteractionService.Register("Mirror", function(player: Player)
		local profile = Services.DataService.GetProfile(player)
		if not profile then
			return
		end
		uiOpen:FireClient(player, "Creator", creatorData(player, profile))
	end)
end

function CosmeticsService.Start()
	local function hook(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		if player.Character then
			task.spawn(onCharacterAdded, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in Players:GetPlayers() do
		hook(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		applyVersion[player] = nil
		limiter:Remove(player)
	end)
end

return CosmeticsService
