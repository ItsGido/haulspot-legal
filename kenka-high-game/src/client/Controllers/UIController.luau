--!strict
-- Opens and closes full-screen windows ("screens"). One screen is open at a time.
-- Screens are ModuleScripts in client/UI/Screens. Each returns a table:
--   Screen.Name = "Rumors"
--   Screen.Build(playerGui, controllers) -> Kit.Window   (called once, lazily)
--   Screen.Open(window, data?)                            (fill/refresh content, called on every open)
--   Screen.Close(window)?                                 (optional cleanup)
-- Open from anywhere:  Controllers.UIController.Open("Rumors")
-- The server can open screens too, with the UI_Open remote (e.g. a shop prompt opens "Shop").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Util.Net)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Kit = require(script.Parent.Parent.UI.Kit)

local UIController = {}
UIController.Priority = 5

UIController.ScreenOpened = Signal.new() -- (name)
UIController.ScreenClosed = Signal.new() -- (name)

local Controllers: any
local screenModules: { [string]: any } = {}
local windows: { [string]: Kit.Window } = {}
local current: string? = nil

local function playerGui(): PlayerGui
	return Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
end

local function getWindow(name: string): Kit.Window?
	local screen = screenModules[name]
	if not screen then
		warn("[UIController] Unknown screen: " .. name)
		return nil
	end
	local window = windows[name]
	if not window then
		local w: Kit.Window = screen.Build(playerGui(), Controllers)
		window = w
		w.OnClose = function()
			if current == name then
				current = nil
			end
			if screen.Close then
				screen.Close(w)
			end
			UIController.ScreenClosed:Fire(name)
		end
		windows[name] = w
	end
	return window
end

function UIController.Open(name: string, data: any?)
	if current and current ~= name then
		UIController.Close(current)
	end
	local window = getWindow(name)
	if not window then
		return
	end
	current = name
	screenModules[name].Open(window, data)
	Kit.OpenWindow(window)
	UIController.ScreenOpened:Fire(name)
end

function UIController.Close(name: string?)
	local target = name or current
	if not target then
		return
	end
	local window = windows[target]
	if window then
		Kit.CloseWindow(window)
	end
end

function UIController.Toggle(name: string, data: any?)
	if current == name then
		UIController.Close(name)
	else
		UIController.Open(name, data)
	end
end

function UIController.GetCurrent(): string?
	return current
end

function UIController.IsOpen(name: string): boolean
	return current == name
end

-- Refresh the open screen (e.g. after data changes) without re-animating.
function UIController.Refresh(name: string, data: any?)
	if current == name and windows[name] then
		screenModules[name].Open(windows[name], data)
	end
end

function UIController.Init(controllers: any)
	Controllers = controllers
	local screensFolder = script.Parent.Parent.UI:FindFirstChild("Screens")
	if screensFolder then
		for _, module in screensFolder:GetChildren() do
			if module:IsA("ModuleScript") then
				local ok, screen = pcall(require, module)
				if ok and type(screen) == "table" and screen.Name then
					screenModules[screen.Name] = screen
				else
					warn("[UIController] Failed to load screen " .. module.Name .. ": " .. tostring(screen))
				end
			end
		end
	end
	Net.Event("UI_Open").OnClientEvent:Connect(function(name: string, data: any?)
		UIController.Open(name, data)
	end)
end

function UIController.Start() end

return UIController
