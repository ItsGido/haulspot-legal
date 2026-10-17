--!strict
-- Settings (blueprint 5.12): volume sliders, camera shake, damage numbers, rookie protection and Unstuck.
-- Changes are sent with Settings_Save (debounced 0.5 s); the server clamps and re-checks them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Util.Net)
local UITheme = require(ReplicatedStorage.Shared.Config.UITheme)
local Ranks = require(ReplicatedStorage.Shared.Config.Ranks)
local GameConfig = require(ReplicatedStorage.Shared.Config.Game)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local Kit = require(script.Parent.Parent.Kit)
local W = require(script.Parent.Parent.HudWidgets)

local Settings = {}
Settings.Name = "Settings"

local Controllers: any
local music: W.Slider = nil :: any
local sfx: W.Slider = nil :: any
local shake: W.Toggle = nil :: any
local damage: W.Toggle = nil :: any
local rookie: W.Toggle = nil :: any
local rookieRow: Frame = nil :: any
local rookieNote: TextLabel = nil :: any
local unstuckButton: TextButton = nil :: any

local pending: { [string]: any } = {}
local saveToken = 0
local unstuckReadyAt = 0

local function getData(key: string): any
	local data = Controllers and Controllers.DataController
	return if data and data.Get then data.Get(key) else nil
end

local function queueSave(key: string, value: any)
	pending[key] = value
	saveToken += 1
	local token = saveToken
	task.delay(0.5, function()
		if token ~= saveToken then
			return
		end
		local payload = pending
		pending = {}
		Net.Event("Settings_Save"):FireServer(payload)
	end)
end

local function rookieCooldownLeft(): number
	local optedAt = getData("RookieOptOutAt")
	if type(optedAt) ~= "number" or optedAt <= 0 then
		return 0
	end
	return math.max(0, optedAt + Ranks.RookieReenableCooldown - W.ServerNow())
end

local function loadValues()
	if next(pending) ~= nil then
		return -- don't stomp on unsaved edits
	end
	local s = getData("Settings")
	local settings = if type(s) == "table" then s else {}
	music.Set(if type(settings.Music) == "number" then settings.Music else 0.6)
	sfx.Set(if type(settings.SFX) == "number" then settings.SFX else 0.8)
	shake.Set(settings.CameraShake ~= false)
	damage.Set(settings.DamageNumbers ~= false)
	local optedOut = settings.RookieOptOut == true
	rookie.Set(optedOut)
	local rank = W.LocalRank()
	rookieRow.Visible = rank <= Ranks.RookieMaxRank or optedOut
	local left = rookieCooldownLeft()
	local base = "Turns off rookie protection: anyone can fight you in Red zones."
	local cooldownText = string.format("Turning protection back on has a %d-minute cooldown.", Ranks.RookieReenableCooldown // 60)
	if optedOut and left > 0 then
		cooldownText = "You can turn protection back on in " .. Format.Duration(left) .. "."
	end
	rookieNote.Text = base .. " " .. cooldownText
end

local function settingRow(parent: Instance, order: number, title: string, height: number): Frame
	local row = W.Row(parent, title:gsub("%W", ""), UDim2.new(), UDim2.fromScale(1, height))
	row.LayoutOrder = order
	Kit.Label("Title", row, title, UDim2.fromScale(0.04, 0), UDim2.fromScale(0.42, if height > 0.15 then 0.45 else 1), "BodyBold", UITheme.Paper, 24, Enum.TextXAlignment.Left)
	return row
end

function Settings.Build(playerGui: Instance, controllers: any): Kit.Window
	Controllers = controllers
	local window = Kit.Window(playerGui, "Settings", "SETTINGS", UDim2.fromScale(0.56, 0.8))
	W.ShapeWindow(window, 1.2)
	local body = window.Body
	Kit.List(body, 0.022)

	local musicRow = settingRow(body, 1, "🎵 Music", 0.12)
	music = W.Slider(musicRow, UDim2.fromScale(0.48, 0.5), UDim2.fromScale(0.36, 0.2), 0.6, function(value: number)
		queueSave("Music", value)
	end)
	music.Frame.AnchorPoint = Vector2.new(0, 0.5)

	local sfxRow = settingRow(body, 2, "🔊 Sound effects", 0.12)
	sfx = W.Slider(sfxRow, UDim2.fromScale(0.48, 0.5), UDim2.fromScale(0.36, 0.2), 0.8, function(value: number)
		queueSave("SFX", value)
	end)
	sfx.Frame.AnchorPoint = Vector2.new(0, 0.5)

	local shakeRow = settingRow(body, 3, "📳 Camera shake", 0.12)
	shake = W.Toggle(shakeRow, UDim2.fromScale(0.96, 0.5), UDim2.fromScale(0.2, 0.6), true, function(value: boolean)
		queueSave("CameraShake", value)
	end)
	shake.Button.AnchorPoint = Vector2.new(1, 0.5)

	local damageRow = settingRow(body, 4, "💥 Damage numbers", 0.12)
	damage = W.Toggle(damageRow, UDim2.fromScale(0.96, 0.5), UDim2.fromScale(0.2, 0.6), true, function(value: boolean)
		queueSave("DamageNumbers", value)
	end)
	damage.Button.AnchorPoint = Vector2.new(1, 0.5)

	rookieRow = settingRow(body, 5, "🛡 I'm ready to fight anyone", 0.22)
	rookie = W.Toggle(rookieRow, UDim2.fromScale(0.96, 0.25), UDim2.fromScale(0.2, 0.34), false, function(value: boolean)
		if not value then
			local left = rookieCooldownLeft()
			if left > 0 then
				rookie.Set(true)
				W.Toast(Controllers, "You can turn rookie protection back on in " .. Format.Duration(left) .. ".", "info")
				return
			end
		end
		queueSave("RookieOptOut", value)
		W.Toast(Controllers, if value then "Rookie protection OFF. Anyone can fight you in Red zones." else "Rookie protection ON.", if value then "bad" else "good")
	end)
	rookie.Button.AnchorPoint = Vector2.new(1, 0.5)
	rookieNote = Kit.Label("Note", rookieRow, "", UDim2.fromScale(0.04, 0.48), UDim2.fromScale(0.92, 0.48), "Body", UITheme.Muted, 18, Enum.TextXAlignment.Left)

	local unstuckRow = settingRow(body, 6, "🧭 Stuck somewhere?", 0.12)
	unstuckButton = Kit.Button(unstuckRow, "UNSTUCK", "Secondary", UDim2.fromScale(0.96, 0.5), UDim2.fromScale(0.3, 0.7), Vector2.new(1, 0.5))
	unstuckButton.Activated:Connect(function()
		local now = os.clock()
		if now < unstuckReadyAt then
			W.Toast(Controllers, string.format("Unstuck is on cooldown (%ds).", math.ceil(unstuckReadyAt - now)), "info")
			return
		end
		unstuckReadyAt = now + GameConfig.UnstuckCooldown
		Net.Event("Unstuck"):FireServer()
		W.Toast(Controllers, "Getting you unstuck…", "info")
		local ui = Controllers and Controllers.UIController
		if ui and ui.Close then
			ui.Close("Settings")
		end
	end)

	local data = controllers.DataController
	if data and data.Changed then
		data.Changed:Connect(function(key: string)
			if (key == "Settings" or key == "Rank" or key == "RookieOptOutAt") and window.Gui.Enabled then
				loadValues()
			end
		end)
	end
	return window
end

function Settings.Open(_window: Kit.Window, _data: any?)
	loadValues()
end

return Settings
