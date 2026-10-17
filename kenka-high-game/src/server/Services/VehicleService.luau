--!strict
-- Scooters and motorcycles (blueprint section 6.5). A greybox vehicle is welded under the character
-- and the Humanoid walks at the vehicle's speed. Player attribute Vehicle = mounted vehicle id.
--
--   VehicleService.Mount(player, vehicleId) -> ok, message
--   VehicleService.Dismount(player)
--   VehicleService.IsMounted(player) -> boolean
--
-- Auto-dismount: entering combat, taking damage, being downed, dying, or entering a small Green
-- pocket (shop fronts, nurse, dojo... any Green zone narrower than SMALL_GREEN_SIZE studs).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local MapData = require(ReplicatedStorage.Shared.Map.MapData)
local Net = require(ReplicatedStorage.Shared.Util.Net)
local RateLimiter = require(ReplicatedStorage.Shared.Util.RateLimiter)
local Cleaner = require(ReplicatedStorage.Shared.Util.Cleaner)
local Notify = require(script.Parent.Parent.Systems.Notify)
local EconomyUtil = require(script.Parent.Parent.Systems.EconomyUtil)

local VehicleService = {}
VehicleService.Priority = 45

local Services: any

local SMALL_GREEN_SIZE = 80 -- same rule MapService uses for "pocket" zone plates
local CHECK_INTERVAL = 0.25
local MODEL_NAME = "EconomyVehicle"

type Mount = { Id: string, Speed: number, Humanoid: Humanoid, Cleaner: Cleaner.Cleaner }

local mounts: { [Player]: Mount } = {}
local limiter = RateLimiter.new(3, 2)
local smallGreenZones: { [string]: boolean } = {}
for _, zone in MapData.Zones do
	if zone.Type == "Green" and zone.SizeX < SMALL_GREEN_SIZE then
		smallGreenZones[zone.Name] = true
	end
end

local function inSmallGreen(player: Player): boolean
	if not Services.ZoneService then
		return false
	end
	local zone = Services.ZoneService.GetZone(player)
	return zone ~= nil and zone.Type == "Green" and smallGreenZones[zone.Name] == true
end

local function vehicleColor(config: any): Color3
	local ok, result = pcall(Color3.fromHex, config.Color or "#FFFFFF")
	return if ok then result else Color3.new(1, 1, 1)
end

local function bodyPart(name: string, size: Vector3, color: Color3, material: Enum.Material?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

-- A simple greybox scooter/motorcycle: deck, two wheels, a handlebar post.
local function buildModel(id: string, config: any, root: BasePart, humanoid: Humanoid): Model
	local model = Instance.new("Model")
	model.Name = MODEL_NAME
	model:SetAttribute("VehicleId", id)
	local isBike = id == "Motorcycle"
	local mainColor = vehicleColor(config)
	local dark = Color3.fromHex("#1B1F33")
	local footY = -(root.Size.Y / 2 + humanoid.HipHeight) + 0.6
	local length = if isBike then 5.5 else 4.5

	local function attach(part: BasePart, offset: CFrame)
		part.CFrame = root.CFrame * offset
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
		part.Parent = model
	end

	local deck = bodyPart("Deck", Vector3.new(if isBike then 1.6 else 1.3, if isBike then 1.0 else 0.4, length), mainColor)
	attach(deck, CFrame.new(0, footY, 0))
	local wheelSize = if isBike then 1.8 else 1.1
	for index, z in { -length / 2, length / 2 } do
		local wheel = bodyPart(if index == 1 then "FrontWheel" else "BackWheel", Vector3.new(0.5, wheelSize, wheelSize), dark, Enum.Material.Rubber)
		wheel.Shape = Enum.PartType.Cylinder
		attach(wheel, CFrame.new(0, footY - 0.3, z))
	end
	local post = bodyPart("Post", Vector3.new(0.25, 2.6, 0.25), dark, Enum.Material.Metal)
	attach(post, CFrame.new(0, footY + 1.3, -length / 2 + 0.3))
	local bar = bodyPart("Handlebar", Vector3.new(2, 0.25, 0.25), mainColor)
	attach(bar, CFrame.new(0, footY + 2.6, -length / 2 + 0.3))
	if isBike then
		local seat = bodyPart("Seat", Vector3.new(1.4, 0.4, 1.8), dark)
		attach(seat, CFrame.new(0, footY + 0.7, 0.6))
	end
	return model
end

-- Public API -------------------------------------------------------------------------

function VehicleService.IsMounted(player: Player): boolean
	return mounts[player] ~= nil
end

function VehicleService.Dismount(player: Player)
	local mount = mounts[player]
	if not mount then
		return
	end
	mounts[player] = nil
	mount.Cleaner:Clean()
	player:SetAttribute("Vehicle", nil)
	if Services.CombatService then
		Services.CombatService.RefreshStats(player)
	elseif mount.Humanoid.Parent then
		mount.Humanoid.WalkSpeed = game:GetService("StarterPlayer").CharacterWalkSpeed
	end
end

function VehicleService.Mount(player: Player, vehicleId: string): (boolean, string)
	local config = (Economy.Vehicles :: any)[vehicleId]
	if not config then
		return false, "Unknown vehicle."
	end
	local profile = Services.DataService.GetProfile(player)
	if not profile then
		return false, "Your data is still loading."
	end
	if not profile.Vehicles[vehicleId] then
		return false, "You don't own that vehicle."
	end
	local character = EconomyUtil.GetCharacter(player)
	local humanoid = EconomyUtil.GetHumanoid(player)
	local root = EconomyUtil.GetRoot(player)
	if not character or not humanoid or not root or humanoid.Health <= 0 then
		return false, "You can't ride right now."
	end
	if EconomyUtil.InCombat(Services, player) or EconomyUtil.IsDowned(Services, player) then
		return false, "Not during a fight."
	end
	if player:GetAttribute("InDuel") == true or player:GetAttribute("InTournament") == true then
		return false, "Not during a duel."
	end
	if inSmallGreen(player) then
		return false, "No riding in here. Step out onto the street."
	end
	VehicleService.Dismount(player)

	local cleaner = Cleaner.new()
	local model = buildModel(vehicleId, config, root, humanoid)
	model.Parent = character
	cleaner:Add(model)
	local mount: Mount = { Id = vehicleId, Speed = config.Speed, Humanoid = humanoid, Cleaner = cleaner }
	mounts[player] = mount
	player:SetAttribute("Vehicle", vehicleId)
	humanoid.WalkSpeed = config.Speed

	local lastHealth = humanoid.Health
	cleaner:Add(humanoid.HealthChanged:Connect(function(health: number)
		if health < lastHealth then
			task.defer(VehicleService.Dismount, player)
		end
		lastHealth = health
	end))
	-- CombatService keeps fight HP in the character's HP attribute.
	local lastHP = character:GetAttribute("HP")
	cleaner:Add(character:GetAttributeChangedSignal("HP"):Connect(function()
		local hp = character:GetAttribute("HP")
		if type(hp) == "number" and type(lastHP) == "number" and hp < lastHP then
			task.defer(VehicleService.Dismount, player)
		end
		lastHP = hp
	end))
	cleaner:Add(humanoid.Died:Connect(function()
		VehicleService.Dismount(player)
	end))
	cleaner:Add(character:GetAttributeChangedSignal("Downed"):Connect(function()
		if character:GetAttribute("Downed") == true then
			VehicleService.Dismount(player)
		end
	end))
	cleaner:Add(character.AncestryChanged:Connect(function()
		if not character.Parent then
			VehicleService.Dismount(player)
		end
	end))
	return true, "Riding " .. vehicleId
end

local function onToggle(player: Player, vehicleId: any)
	if not limiter:Allow(player) then
		return
	end
	if vehicleId == nil then
		VehicleService.Dismount(player)
		return
	end
	if not EconomyUtil.IsShortString(vehicleId, 32) then
		return
	end
	local mount = mounts[player]
	if mount and mount.Id == vehicleId then
		VehicleService.Dismount(player)
		return
	end
	local ok, message = VehicleService.Mount(player, vehicleId)
	if not ok then
		Notify.Send(player, message, "bad")
	end
end

-- Lifecycle ----------------------------------------------------------------------------

function VehicleService.Init(services: any)
	Services = services
	Net.Event("Vehicle_Toggle").OnServerEvent:Connect(onToggle)
end

function VehicleService.Start()
	Players.PlayerRemoving:Connect(function(player)
		VehicleService.Dismount(player)
		limiter:Remove(player)
	end)
	while true do
		task.wait(CHECK_INTERVAL)
		for player, mount in mounts do
			if player.Parent ~= Players or not mount.Humanoid.Parent then
				VehicleService.Dismount(player)
			elseif EconomyUtil.InCombat(Services, player) or EconomyUtil.IsDowned(Services, player) then
				VehicleService.Dismount(player)
			elseif inSmallGreen(player) then
				VehicleService.Dismount(player)
				Notify.Send(player, "You hop off your " .. mount.Id .. ".", "info")
			elseif mount.Humanoid.WalkSpeed ~= mount.Speed then
				-- Something (e.g. a stats refresh) reset the speed while riding.
				mount.Humanoid.WalkSpeed = mount.Speed
			end
		end
	end
end

return VehicleService
