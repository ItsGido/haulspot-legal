--!strict
-- Routes every ProximityPrompt in the map to the service that owns its Kind.
--   InteractionService.Register("Shop", function(player, interactable, part) ... end)
-- interactable is the MapData entry (Id, Kind, Shop, Job, Target...). Handlers run after these checks:
--   * the player is close enough (server-side distance check)
--   * "safe" kinds (shops, jobs, class...) are blocked while the player is in combat or downed

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapData = require(ReplicatedStorage.Shared.Map.MapData)
local Notify = require(script.Parent.Parent.Systems.Notify)

local InteractionService = {}
InteractionService.Priority = 5

type Handler = (player: Player, interactable: any, part: BasePart) -> ()

local handlers: { [string]: Handler } = {}
local Services: any

local SAFE_KINDS = {
	Shop = true,
	Job = true,
	Class = true,
	Capsule = true,
	Mirror = true,
	Dojo = true,
	Bathhouse = true,
	Tournament = true,
	CrewHQ = true,
	RumorBoard = false,
	Fountain = false,
	Teleport = true,
	Station = false,
}

function InteractionService.Register(kind: string, handler: Handler)
	assert(handlers[kind] == nil, "Interaction kind already registered: " .. kind)
	handlers[kind] = handler
end

local function onTriggered(part: BasePart, player: Player)
	local id = part:GetAttribute("InteractId")
	local kind = part:GetAttribute("Kind")
	if type(id) ~= "string" or type(kind) ~= "string" then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or (root.Position - part.Position).Magnitude > 16 then
		return
	end
	if SAFE_KINDS[kind] and Services.CombatService then
		if Services.CombatService.IsDowned(player) then
			return
		end
		if Services.CombatService.IsInCombat(player) then
			Notify.Send(player, "You're still in a fight. Wait a few seconds.", "bad")
			return
		end
	end
	local handler = handlers[kind]
	if not handler then
		Notify.Send(player, "Coming soon.", "info")
		return
	end
	local interactable = MapData.GetInteractable(id) or { Id = id, Kind = kind }
	handler(player, interactable, part)
end

local function hookPart(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Triggered:Connect(function(player)
			onTriggered(part, player)
		end)
	end
end

function InteractionService.Init(services: any)
	Services = services
end

function InteractionService.Start()
	for _, part in CollectionService:GetTagged("Interactable") do
		hookPart(part)
	end
	CollectionService:GetInstanceAddedSignal("Interactable"):Connect(hookPart)
end

return InteractionService
