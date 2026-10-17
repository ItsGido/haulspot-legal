--!strict
-- Client copy of the player's public profile (everything except server-only keys).
--   DataController.Get("Yen")                     -> current value
--   DataController.Changed:Connect(function(key, value) ... end)
--   DataController.Observe("Quests", function(value) ... end) -- runs now and on every change
-- The server pushes changed top-level keys with Data_Update.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Util.Net)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local DataController = {}
DataController.Priority = 1

DataController.Changed = Signal.new() -- (key, value)
DataController.Loaded = Signal.new() -- (profile)

local profile: { [string]: any } = {}
local loaded = false

function DataController.Get(key: string): any
	return profile[key]
end

function DataController.GetAll(): { [string]: any }
	return profile
end

function DataController.IsLoaded(): boolean
	return loaded
end

function DataController.WaitForLoad()
	if not loaded then
		DataController.Loaded:Wait()
	end
end

function DataController.Observe(key: string, callback: (value: any) -> ()): Signal.Connection
	if loaded then
		task.spawn(callback, profile[key])
	end
	return DataController.Changed:Connect(function(changedKey, value)
		if changedKey == key then
			callback(value)
		end
	end)
end

function DataController.Init(_controllers: any)
	Net.Event("Data_Update").OnClientEvent:Connect(function(payload: { [string]: any })
		for key, value in payload do
			profile[key] = value
			if loaded then
				DataController.Changed:Fire(key, value)
			end
		end
	end)
end

function DataController.Start()
	local result
	repeat
		local ok, data = pcall(function()
			return Net.Function("Data_Request"):InvokeServer()
		end)
		if ok and data then
			result = data
		else
			task.wait(1)
		end
	until result
	for key, value in result do
		if profile[key] == nil then
			profile[key] = value
		end
	end
	loaded = true
	DataController.Loaded:Fire(profile)
	for key, value in profile do
		DataController.Changed:Fire(key, value)
	end
end

return DataController
