--!strict
-- Vehicle key: B (PC) / DPad Down (gamepad) toggles riding the best owned vehicle
-- (Motorcycle preferred, then Scooter). VehicleController.Toggle() is public for a HUD button.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Net = require(ReplicatedStorage.Shared.Util.Net)

local VehicleController = {}

local Controllers: any
local PREFERENCE = { "Motorcycle", "Scooter" }
local TOGGLE_COOLDOWN = 0.5
local lastToggle = 0

local function bestVehicle(): string?
	local owned = Controllers.DataController.Get("Vehicles")
	if type(owned) ~= "table" then
		return nil
	end
	for _, id in PREFERENCE do
		if owned[id] then
			return id
		end
	end
	for id, value in owned do
		if value and (Economy.Vehicles :: any)[id] then
			return id
		end
	end
	return nil
end

function VehicleController.Toggle()
	if os.clock() - lastToggle < TOGGLE_COOLDOWN then
		return
	end
	lastToggle = os.clock()
	local remote = Net.Event("Vehicle_Toggle")
	if Players.LocalPlayer:GetAttribute("Vehicle") ~= nil then
		remote:FireServer(nil)
		return
	end
	local id = bestVehicle()
	if id then
		remote:FireServer(id)
	end
end

function VehicleController.Init(controllers: any)
	Controllers = controllers
end

function VehicleController.Start()
	ContextActionService:BindAction("EconomyVehicleToggle", function(_name, state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			VehicleController.Toggle()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.B, Enum.KeyCode.DPadDown)
end

return VehicleController
