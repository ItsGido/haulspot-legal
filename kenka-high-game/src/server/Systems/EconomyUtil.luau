--!strict
-- Small helpers shared by the Economy services (argument validation, character lookups,
-- interactable positions). Pure helpers only: no state, no remotes connected here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapData = require(ReplicatedStorage.Shared.Map.MapData)
local Net = require(ReplicatedStorage.Shared.Util.Net)

local EconomyUtil = {}

local uiOpen = Net.Event("UI_Open")

function EconomyUtil.GetCharacter(player: Player): Model?
	local character = player.Character
	if character and character.Parent then
		return character
	end
	return nil
end

function EconomyUtil.GetRoot(player: Player): BasePart?
	local character = EconomyUtil.GetCharacter(player)
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

function EconomyUtil.GetHumanoid(player: Player): Humanoid?
	local character = EconomyUtil.GetCharacter(player)
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

function EconomyUtil.IsAlive(player: Player): boolean
	local humanoid = EconomyUtil.GetHumanoid(player)
	return humanoid ~= nil and humanoid.Health > 0
end

function EconomyUtil.IsOnline(player: Player): boolean
	return player.Parent == Players
end

-- A finite number (not NaN / inf).
function EconomyUtil.IsNumber(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

-- An integer within [min, max].
function EconomyUtil.IsInt(value: any, min: number, max: number): boolean
	return EconomyUtil.IsNumber(value) and value % 1 == 0 and value >= min and value <= max
end

-- A non-empty string no longer than maxLen.
function EconomyUtil.IsShortString(value: any, maxLen: number): boolean
	return type(value) == "string" and #value > 0 and #value <= maxLen
end

function EconomyUtil.InCombat(services: any, player: Player): boolean
	local combat = services and services.CombatService
	if combat and combat.IsInCombat then
		return combat.IsInCombat(player) == true
	end
	return false
end

function EconomyUtil.IsDowned(services: any, player: Player): boolean
	local combat = services and services.CombatService
	if combat and combat.IsDowned then
		if combat.IsDowned(player) == true then
			return true
		end
	end
	local character = EconomyUtil.GetCharacter(player)
	return character ~= nil and character:GetAttribute("Downed") == true
end

function EconomyUtil.InTutorial(services: any, player: Player): boolean
	local tutorial = services and services.TutorialService
	if tutorial and tutorial.IsInTutorial then
		return tutorial.IsInTutorial(player) == true
	end
	return false
end

-- World position of an interactable: the real part in Workspace.KenkaHighMap if present
-- (an art-pass map may move it), otherwise the MapData coordinates.
function EconomyUtil.InteractablePosition(id: string): Vector3?
	local map = workspace:FindFirstChild("KenkaHighMap")
	local folder = map and map:FindFirstChild("Interactables")
	local part = folder and folder:FindFirstChild(id)
	if part and part:IsA("BasePart") then
		return part.Position
	end
	local entry = MapData.GetInteractable(id)
	if entry then
		return Vector3.new(entry.X, entry.Y, entry.Z)
	end
	return nil
end

-- True if the player is within range studs of any interactable matching the predicate.
function EconomyUtil.NearInteractable(player: Player, range: number, predicate: (entry: any) -> boolean): boolean
	local root = EconomyUtil.GetRoot(player)
	if not root then
		return false
	end
	for _, entry in MapData.Interactables do
		if predicate(entry) then
			local position = EconomyUtil.InteractablePosition(entry.Id)
			if position and (position - root.Position).Magnitude <= range then
				return true
			end
		end
	end
	return false
end

function EconomyUtil.ServerNow(): number
	return workspace:GetServerTimeNow()
end

function EconomyUtil.OpenUI(player: Player, screen: string, data: any?)
	uiOpen:FireClient(player, screen, data)
end

-- Fisher-Yates shuffle of a copy.
function EconomyUtil.Shuffled<T>(list: { T }, rng: Random): { T }
	local copy = table.clone(list)
	for i = #copy, 2, -1 do
		local j = rng:NextInteger(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

return EconomyUtil
