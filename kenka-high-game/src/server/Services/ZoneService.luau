--!strict
-- Tracks which zone every player is in, 4 times a second (blueprint section 1.3).
-- Player attributes (read by the client HUD and by CombatService):
--   Zone (name), ZoneType ("Green" | "Yellow" | "Red", after the turf war rule), ZoneTurf (turf id or nil)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapData = require(ReplicatedStorage.Shared.Map.MapData)
local ZoneMath = require(ReplicatedStorage.Shared.Logic.ZoneMath)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Notify = require(script.Parent.Parent.Systems.Notify)

local ZoneService = {}
ZoneService.Priority = 20

ZoneService.ZoneChanged = Signal.new() -- (player, newZone: ZoneResult, oldZone: ZoneResult?)

local Services: any
local zones: { [Player]: ZoneMath.ZoneResult } = {}

local DEFAULT: ZoneMath.ZoneResult = { Name = "Streets", BaseType = "Yellow", Type = "Yellow", Turf = nil }

function ZoneService.GetZone(player: Player): ZoneMath.ZoneResult
	return zones[player] or DEFAULT
end

function ZoneService.GetZoneType(player: Player): string
	return ZoneService.GetZone(player).Type
end

-- Zone at an arbitrary world position (used for NPCs and duel ring checks).
function ZoneService.ZoneAt(position: Vector3): ZoneMath.ZoneResult
	local turfWar = Services.DayCycleService and Services.DayCycleService.IsTurfWar() or false
	return ZoneMath.Find(MapData.Zones, position.X, position.Y, position.Z, MapData.DefaultZoneType, turfWar)
end

local function update(player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local zone = ZoneService.ZoneAt(root.Position)
	local old = zones[player]
	if old and old.Name == zone.Name and old.Type == zone.Type then
		return
	end
	zones[player] = zone
	player:SetAttribute("Zone", zone.Name)
	player:SetAttribute("ZoneType", zone.Type)
	player:SetAttribute("ZoneTurf", zone.Turf)
	if old and old.Type ~= zone.Type then
		if zone.Type == "Red" then
			Notify.Send(player, "⚠ RED ZONE: open fights", "zone")
		elseif zone.Type == "Green" then
			Notify.Send(player, "Safe zone: no fighting here", "zone")
		end
	end
	ZoneService.ZoneChanged:Fire(player, zone, old)
end

function ZoneService.Init(services: any)
	Services = services
end

function ZoneService.Start()
	Players.PlayerRemoving:Connect(function(player)
		zones[player] = nil
	end)
	while true do
		for _, player in Players:GetPlayers() do
			update(player)
		end
		task.wait(0.25)
	end
end

return ZoneService
