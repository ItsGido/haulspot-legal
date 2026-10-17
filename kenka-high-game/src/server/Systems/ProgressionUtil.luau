--!strict
-- Small helpers shared by the Progression services (Rep, Style, Challenge, Crown, Tournament, Tutorial).
-- Pure Roblox-instance helpers only: no state, no requires of services.

local Players = game:GetService("Players")

local ProgressionUtil = {}

-- The HumanoidRootPart of a player's character, or nil.
function ProgressionUtil.GetRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- The HumanoidRootPart of any model (characters and NPCs).
function ProgressionUtil.GetModelRoot(model: Model?): BasePart?
	if not model then
		return nil
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	local primary = model.PrimaryPart
	return primary
end

-- The player that owns a character model, or nil (NPCs, nil).
function ProgressionUtil.PlayerFromModel(model: any): Player?
	if typeof(model) ~= "Instance" or not (model :: Instance):IsA("Model") then
		return nil
	end
	return Players:GetPlayerFromCharacter(model :: Model)
end

-- True while the player is still in the server.
function ProgressionUtil.IsOnline(player: Player?): boolean
	return player ~= nil and player.Parent == Players
end

-- Current HP fraction (0..1) of a fighter model. Reads the HP/MaxHP attributes, then the Humanoid.
function ProgressionUtil.HPFraction(model: Model?): number
	if not model then
		return 0
	end
	local hp = model:GetAttribute("HP")
	local maxHp = model:GetAttribute("MaxHP")
	if type(hp) == "number" and type(maxHp) == "number" and maxHp > 0 then
		return math.clamp(hp / maxHp, 0, 1)
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.MaxHealth > 0 then
		return math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
	end
	return 0
end

-- Horizontal (XZ) distance between two points.
function ProgressionUtil.FlatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Reports quest progress if QuestService is loaded.
function ProgressionUtil.Quest(services: any, player: Player, event: string, amount: number?)
	local questService = services and services.QuestService
	if questService and questService.Progress then
		questService.Progress(player, event, amount)
	end
end

-- Display name used in announcements.
function ProgressionUtil.Name(player: Player?): string
	if not player then
		return "?"
	end
	return player.DisplayName
end

return ProgressionUtil
