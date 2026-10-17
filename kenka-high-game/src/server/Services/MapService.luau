--!strict
-- Builds the greybox world from MapData (if the place doesn't already contain Workspace.KenkaHighMap),
-- creates ProximityPrompts for every interactable, and handles spawning, teleports, the void and unstuck.
--
-- Art pass: build the real map in Studio as Workspace.KenkaHighMap, keeping these child names:
--   Zones/<zone name>, Interactables/<id> (a part with a ProximityPrompt + Kind/InteractId attributes),
--   TurfWalls/<turf id>, DummySpawns/<n>. MapService will then use your map instead of building one.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapData = require(ReplicatedStorage.Shared.Map.MapData)
local UITheme = require(ReplicatedStorage.Shared.Config.UITheme)
local GameConfig = require(ReplicatedStorage.Shared.Config.Game)
local Net = require(ReplicatedStorage.Shared.Util.Net)
local Notify = require(script.Parent.Parent.Systems.Notify)

local MapService = {}
MapService.Priority = 1

local Services: any
local mapFolder: Folder

local ZONE_COLORS = {
	Green = "#3BC46B",
	Yellow = "#F4C542",
	Red = "#E4322B",
	Road = "#3A3D48",
	Water = "#3FA7FF",
}

local function v3(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

local function makeFolder(name: string, parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function makePart(name: string, parent: Instance, size: Vector3, position: Vector3, color: string, transparency: number?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.Position = position
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.fromHex(color)
	part.Transparency = transparency or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function addLabel(part: BasePart, text: string, height: number, maxDistance: number?)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromOffset(220, 40)
	gui.StudsOffset = Vector3.new(0, height, 0)
	gui.MaxDistance = maxDistance or 250
	gui.AlwaysOnTop = false
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = UITheme.Fonts.Button
	label.TextColor3 = Color3.fromHex(UITheme.Paper)
	label.TextStrokeTransparency = 0
	label.Parent = gui
	gui.Parent = part
end

local function buildMap(): Folder
	local root = Instance.new("Folder")
	root.Name = "KenkaHighMap"

	local ground = MapData.Ground
	makePart("Ground", root, Vector3.new(ground.SizeX, 2, ground.SizeZ), Vector3.new(ground.X, -1, ground.Z), "#23262F")

	local zones = makeFolder("Zones", root)
	for _, zone in MapData.Zones do
		local y = if zone.Type == "Road" then 0.05 elseif zone.Type == "Water" then 0.15 else 0.1
		if zone.MinY then
			y = zone.MinY + 2.1 -- rooftop sits on the building top
		end
		if zone.Name:find("Bridge") then
			y = 0.2
		end
		-- Green "pockets" are thin decals on top of larger zones; keep them subtle.
		local plate = makePart(zone.Name, zones, Vector3.new(zone.SizeX, 0.1, zone.SizeZ), Vector3.new(zone.X, y, zone.Z), ZONE_COLORS[zone.Type] or "#888888")
		plate.Transparency = if zone.SizeX < 80 and zone.Type == "Green" then 0.5 else 0
		plate.CanCollide = zone.MinY == nil -- the roof building is solid already
		plate:SetAttribute("ZoneType", zone.Type)
		if zone.Turf then
			plate:SetAttribute("TurfId", zone.Turf)
		end
		if zone.Type ~= "Road" and zone.Type ~= "Water" and zone.SizeX >= 60 then
			addLabel(plate, zone.Name, 8, 400)
		end
	end

	local buildings = makeFolder("Buildings", root)
	for _, b in MapData.Buildings do
		local block = makePart(b.Name, buildings, Vector3.new(b.SizeX, b.Height, b.SizeZ), Vector3.new(b.X, b.BaseY + b.Height / 2, b.Z), "#8C92A4")
		addLabel(block, b.Name, b.Height / 2 + 4, 400)
	end

	-- Rooftop fence so players don't walk off the main building (blueprint Z5).
	local fence = makeFolder("RooftopFence", root)
	local roofTop = 52
	makePart("North", fence, Vector3.new(240, 8, 1), Vector3.new(0, roofTop + 4, -200), "#5A5E6B", 0.4)
	makePart("South", fence, Vector3.new(240, 8, 1), Vector3.new(0, roofTop + 4, -140), "#5A5E6B", 0.4)
	makePart("West", fence, Vector3.new(1, 8, 60), Vector3.new(-120, roofTop + 4, -170), "#5A5E6B", 0.4)
	makePart("East", fence, Vector3.new(1, 8, 60), Vector3.new(120, roofTop + 4, -170), "#5A5E6B", 0.4)

	local interactables = makeFolder("Interactables", root)
	for _, item in MapData.Interactables do
		local marker = makePart(item.Id, interactables, Vector3.new(3, 5, 3), Vector3.new(item.X, item.Y - 0.5, item.Z), "#FFD23F")
		marker.Material = Enum.Material.Neon
		marker.CanCollide = false
		marker:SetAttribute("Kind", item.Kind)
		marker:SetAttribute("InteractId", item.Id)
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = item.Action
		prompt.ObjectText = item.Object
		prompt.HoldDuration = item.Hold or 0
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = marker
		addLabel(marker, item.Object, 4, 120)
	end

	local turfWalls = makeFolder("TurfWalls", root)
	for turfId, pos in MapData.TurfWalls do
		local wall = makePart(turfId, turfWalls, Vector3.new(20, 10, 2), Vector3.new(pos[1], 5, pos[2]), "#FF9EC4")
		wall:SetAttribute("TurfId", turfId)
		addLabel(wall, "Turf " .. turfId, 8, 300)
	end

	local dummySpawns = makeFolder("DummySpawns", root)
	for i, pos in MapData.Dummies do
		local spot = makePart(tostring(i), dummySpawns, Vector3.new(4, 0.2, 4), Vector3.new(pos[1], 0.2, pos[2]), "#FFFFFF", 0.6)
		spot.CanCollide = false
	end

	local spawns = makeFolder("Spawns", root)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "CourtyardSpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = Vector3.new(MapData.Spawns.Courtyard[1], 0.5, MapData.Spawns.Courtyard[3])
	spawn.Color = Color3.fromHex("#5FE08A")
	spawn.Parent = spawns

	return root
end

-- Public API -----------------------------------------------------------------

function MapService.GetMapFolder(): Folder
	return mapFolder
end

-- name: "Courtyard" | "NurseRespawn" | "Station"
function MapService.GetSpawnCFrame(name: string): CFrame
	local spawnPoint = (MapData.Spawns :: any)[name] or MapData.Spawns.Courtyard
	return CFrame.new(v3(spawnPoint)) * CFrame.Angles(0, math.pi, 0)
end

function MapService.Teleport(player: Player, target: CFrame)
	local character = player.Character
	if character and character.PrimaryPart then
		character:PivotTo(target)
	end
end

-- The next time this player's character spawns, put it at this spawn point.
function MapService.SetNextSpawn(player: Player, name: string)
	player:SetAttribute("NextSpawn", name)
end

local lastUnstuck: { [Player]: number } = {}

local function onCharacterAdded(player: Player, character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root then
		return
	end
	local next = player:GetAttribute("NextSpawn")
	player:SetAttribute("NextSpawn", nil)
	if type(next) == "string" then
		task.defer(function()
			character:PivotTo(MapService.GetSpawnCFrame(next))
		end)
	end
end

function MapService.Init(services: any)
	Services = services
	local existing = workspace:FindFirstChild("KenkaHighMap")
	if existing and existing:IsA("Folder") then
		mapFolder = existing
	else
		mapFolder = buildMap()
		mapFolder.Parent = workspace
	end
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		baseplate:Destroy()
	end
	for _, part in mapFolder:WaitForChild("Interactables"):GetChildren() do
		CollectionService:AddTag(part, "Interactable")
	end
	for _, part in mapFolder:WaitForChild("TurfWalls"):GetChildren() do
		CollectionService:AddTag(part, "TurfWall")
	end

	Net.Event("Unstuck").OnServerEvent:Connect(function(player: Player)
		local last = lastUnstuck[player] or 0
		if os.clock() - last < GameConfig.UnstuckCooldown then
			Notify.Send(player, string.format("Unstuck is on cooldown (%ds).", math.ceil(GameConfig.UnstuckCooldown - (os.clock() - last))), "bad")
			return
		end
		if Services.CombatService and Services.CombatService.IsInCombat(player) then
			Notify.Send(player, "You can't use Unstuck during a fight.", "bad")
			return
		end
		lastUnstuck[player] = os.clock()
		MapService.Teleport(player, MapService.GetSpawnCFrame("Courtyard"))
	end)
end

function MapService.Start()
	-- Interactions for teleports and the station sign
	Services.InteractionService.Register("Teleport", function(player: Player, item: any)
		if item.Target then
			if Services.CombatService and Services.CombatService.IsDowned(player) then
				return
			end
			MapService.Teleport(player, CFrame.new(v3(item.Target)))
		end
	end)
	Services.InteractionService.Register("Station", function(player: Player)
		Notify.Send(player, "Trains to the next district arrive in a future update. Rank 3+ can spawn here.", "info")
	end)

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
		lastUnstuck[player] = nil
	end)

	-- Void check: falling off the map returns you to the courtyard (no KO). Crew HQs live far below.
	while true do
		task.wait(1)
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and root.Position.Y < GameConfig.VoidY and root.Position.Y > MapData.CrewHQOrigin[2] + 500 then
				MapService.Teleport(player, MapService.GetSpawnCFrame("Courtyard"))
			end
		end
	end
end

return MapService
