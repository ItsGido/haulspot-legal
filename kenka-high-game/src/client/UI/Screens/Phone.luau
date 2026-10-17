--!strict
-- Phone (blueprint 5.2): a phone-shaped window with a status bar and a 3x3 app grid.
-- The phone doesn't dim or block the world: you can keep walking while it's open.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UITheme = require(ReplicatedStorage.Shared.Config.UITheme)
local DayCycle = require(ReplicatedStorage.Shared.Config.DayCycle)
local DayCycleMath = require(ReplicatedStorage.Shared.Logic.DayCycleMath)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local Kit = require(script.Parent.Parent.Kit)
local W = require(script.Parent.Parent.HudWidgets)

local Phone = {}
Phone.Name = "Phone"

local Controllers: any
local clockLabel: TextLabel = nil :: any
local yenLabel: TextLabel = nil :: any
local ticker: thread? = nil

type App = { Name: string, Glyph: string, Style: string, Screen: string? }

local APPS: { App } = {
	{ Name = "Rumors", Glyph = "📜", Style = "Primary", Screen = "Rumors" },
	{ Name = "Jobber", Glyph = "🍜", Style = "Success", Screen = nil },
	{ Name = "Crew", Glyph = "🚩", Style = "Sakura", Screen = "Crew" },
	{ Name = "Map", Glyph = "🗺", Style = "Secondary", Screen = "Map" },
	{ Name = "YenPay", Glyph = "¥", Style = "Premium", Screen = "YenPay" },
	{ Name = "Style", Glyph = "👊", Style = "Primary", Screen = "Style" },
	{ Name = "Fights", Glyph = "🏆", Style = "Ghost", Screen = "Fights" },
	{ Name = "Store", Glyph = "🛒", Style = "Premium", Screen = "Store" },
	{ Name = "Settings", Glyph = "⚙", Style = "Ghost", Screen = "Settings" },
}

local function clockText(): string
	local hud = Controllers and Controllers.HUDController
	if hud and hud.GetClockText then
		return hud.GetClockText()
	end
	local name = ReplicatedStorage:GetAttribute("PeriodName")
	local endsAt = ReplicatedStorage:GetAttribute("PeriodEndsAt")
	if type(name) == "string" and type(endsAt) == "number" then
		return name .. " " .. DayCycleMath.FormatClock(W.Remaining(endsAt))
	end
	local state = DayCycleMath.At(DayCycle, W.ServerNow())
	return state.Name .. " " .. DayCycleMath.FormatClock(state.Remaining)
end

local function refreshStatus()
	clockLabel.Text = W.Escape(clockText())
	local yen = Players.LocalPlayer:GetAttribute("Yen")
	if type(yen) ~= "number" then
		local data = Controllers and Controllers.DataController
		yen = if data and data.Get then data.Get("Yen") else nil
	end
	yenLabel.Text = if type(yen) == "number" then Format.Yen(yen) else "¥ —"
end

function Phone.Build(playerGui: Instance, controllers: any): Kit.Window
	Controllers = controllers
	local window = Kit.Window(playerGui, "Phone", "PHONE", UDim2.fromScale(0.28, 0.8), 12)
	local root = window.Root
	root.Position = UDim2.fromScale(0.72, 0.5)
	root.BackgroundColor3 = Kit.Hex(UITheme.Ink)
	Kit.Aspect(root, 0.5)
	local corner = root:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0.09, 0)
	end
	window.Header.Visible = false
	window.Dimmer.Visible = false -- don't block the world while the phone is out
	window.Close.Size = UDim2.fromScale(0.16, 0.08)
	window.Body.Position = UDim2.fromScale(0.06, 0.035)
	window.Body.Size = UDim2.fromScale(0.88, 0.93)

	local screen = Kit.Frame("Screen", window.Body, UDim2.new(), UDim2.fromScale(1, 1), UITheme.Panel)
	Kit.Corner(screen, 0.07)
	Kit.InkStroke(screen, 2, "#2B2E3C")

	-- Status bar: school clock + yen
	clockLabel = Kit.Label("Clock", screen, "", UDim2.fromScale(0.06, 0.025), UDim2.fromScale(0.58, 0.05), "BodyBold", UITheme.Paper, 18, Enum.TextXAlignment.Left)
	yenLabel = Kit.Label("Yen", screen, "", UDim2.fromScale(0.62, 0.025), UDim2.fromScale(0.32, 0.05), "Number", UITheme.Gold, 18, Enum.TextXAlignment.Right)
	local notch = Kit.Frame("Notch", screen, UDim2.fromScale(0.5, 0), UDim2.fromScale(0.3, 0.018), UITheme.Ink, Vector2.new(0.5, 0))
	Kit.Corner(notch, 1)

	local title = Kit.Label("Title", screen, "KENKA PHONE", UDim2.fromScale(0.06, 0.09), UDim2.fromScale(0.88, 0.06), "Title", UITheme.Paper, 30)
	title.Rotation = -2

	local grid = Kit.Frame("Apps", screen, UDim2.fromScale(0.06, 0.2), UDim2.fromScale(0.88, 0.7))
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromScale(0.3, 0.3)
	layout.CellPadding = UDim2.fromScale(0.05, 0.04)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = grid

	for i, app in APPS do
		local cell = Kit.Frame(app.Name, grid, UDim2.new(), UDim2.new())
		cell.LayoutOrder = i
		local icon = Kit.Button(cell, "", app.Style, UDim2.fromScale(0.5, 0), UDim2.fromScale(0.8, 0.72), Vector2.new(0.5, 0))
		icon.Name = app.Name .. "App"
		Kit.Aspect(icon, 1)
		Kit.Label("Glyph", icon, app.Glyph, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), "Number", UITheme.Paper, 40)
		local label = Kit.Label("Label", cell, app.Name, UDim2.fromScale(-0.1, 0.75), UDim2.fromScale(1.2, 0.25), "BodyBold", UITheme.Paper, 16)
		Kit.TextStroke(label, 1.5)
		local target = app.Screen
		icon.Activated:Connect(function()
			if target then
				W.OpenScreen(Controllers, target)
			else
				W.Toast(Controllers, "Find job boards in the Shotengai: Ramen, Konbini, Arcade", "info", 4)
			end
		end)
	end

	local homeBar = Kit.Frame("HomeBar", screen, UDim2.fromScale(0.5, 0.965), UDim2.fromScale(0.36, 0.012), UITheme.Muted, Vector2.new(0.5, 0.5))
	Kit.Corner(homeBar, 1)

	return window
end

function Phone.Open(_window: Kit.Window, _data: any?)
	refreshStatus()
	if ticker then
		pcall(task.cancel, ticker)
	end
	ticker = task.spawn(function()
		while true do
			task.wait(1)
			refreshStatus()
		end
	end)
end

function Phone.Close(_window: Kit.Window)
	if ticker then
		pcall(task.cancel, ticker)
		ticker = nil
	end
end

return Phone
