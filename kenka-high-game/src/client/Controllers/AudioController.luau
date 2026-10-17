--!strict
-- Applies the player's audio settings: SFX volume for every Kit sound, and music volume for
-- SoundService.Music (a SoundGroup; put background music Sounds in it during the art pass).

local SoundService = game:GetService("SoundService")

local Kit = require(script.Parent.Parent.UI.Kit)

local AudioController = {}
AudioController.Priority = 10

local Controllers: any

local function musicGroup(): SoundGroup
	local existing = SoundService:FindFirstChild("Music")
	if existing and existing:IsA("SoundGroup") then
		return existing
	end
	local group = Instance.new("SoundGroup")
	group.Name = "Music"
	group.Parent = SoundService
	return group
end

local function apply(settings: any)
	if type(settings) ~= "table" then
		return
	end
	if type(settings.SFX) == "number" then
		Kit.SetSFXVolume(settings.SFX)
	end
	if type(settings.Music) == "number" then
		musicGroup().Volume = math.clamp(settings.Music, 0, 1)
	end
end

function AudioController.Init(controllers: any)
	Controllers = controllers
end

function AudioController.Start()
	Controllers.DataController.Observe("Settings", apply)
end

return AudioController
