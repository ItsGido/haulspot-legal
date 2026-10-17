--!strict
-- Toast messages (blueprint 5.1 "Toasts"). Server: the Notify remote { Text, Kind, Duration? }.
-- Client code: Controllers.ToastController.Show(text, kind?, duration?)
-- Kinds: info (paper), good (green), bad (red), zone (current zone color), gold, crew (sakura).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Shared.Util.Net)
local UITheme = require(ReplicatedStorage.Shared.Config.UITheme)
local Kit = require(script.Parent.Parent.UI.Kit)
local W = require(script.Parent.Parent.UI.HudWidgets)

local ToastController = {}
ToastController.Priority = 4

local MAX_TOASTS = 4
local DEFAULT_DURATION = 3
local SLIDE_TIME = 0.22

type Toast = {
	Holder: Frame,
	Panel: Frame,
	Text: string,
	Kind: string,
	Token: number,
	Closing: boolean,
}

local container: Frame? = nil
local active: { Toast } = {}
local pending: { { Text: string, Kind: string, Duration: number } } = {}
local order = 0

local function kindColor(kind: string): string
	if kind == "zone" then
		local zoneType = Players.LocalPlayer:GetAttribute("ZoneType")
		local color = if type(zoneType) == "string" then (UITheme.Zones :: any)[zoneType] else nil
		return color or UITheme.Zones.Yellow
	end
	return W.KindColors[kind] or UITheme.Paper
end

local function removeToast(toast: Toast)
	if toast.Closing then
		return
	end
	toast.Closing = true
	local index = table.find(active, toast)
	if index then
		table.remove(active, index)
	end
	local tween = TweenService:Create(
		toast.Panel,
		TweenInfo.new(SLIDE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = UDim2.fromScale(1.3, 0) }
	)
	tween:Play()
	tween.Completed:Once(function()
		toast.Holder:Destroy()
	end)
end

local function schedule(toast: Toast, duration: number)
	toast.Token += 1
	local token = toast.Token
	task.delay(duration, function()
		if toast.Token == token then
			removeToast(toast)
		end
	end)
end

local function build(): Frame
	local gui = W.Overlay(Players.LocalPlayer:WaitForChild("PlayerGui"), "Toasts", 50)
	-- Each toast is 0.06 of the screen high (blueprint), stacked downward from (0.5, 0.16).
	local frame = Kit.Frame("ToastStack", gui, UDim2.fromScale(0.5, 0.16), UDim2.fromScale(0.4, 0.3), nil, Vector2.new(0.5, 0))
	local list = Kit.List(frame, 0.04)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	return frame
end

local function show(text: string, kind: string, duration: number)
	local parent = container
	if not parent then
		table.insert(pending, { Text = text, Kind = kind, Duration = duration })
		return
	end

	-- Same message already on screen: refresh it instead of stacking a duplicate.
	for _, toast in active do
		if toast.Text == text and toast.Kind == kind and not toast.Closing then
			W.Pop(toast.Panel, 1.08)
			schedule(toast, duration)
			return
		end
	end

	while #active >= MAX_TOASTS do
		removeToast(active[1])
	end

	order += 1
	local holder = Kit.Frame("Toast" .. order, parent, UDim2.new(), UDim2.fromScale(1, 0.2))
	holder.LayoutOrder = order
	holder.ClipsDescendants = false

	local panel = Kit.Panel("Panel", holder, UDim2.fromScale(1.3, 0), UDim2.fromScale(1, 1), nil, UITheme.Panel)
	local corner = panel:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0.25, 0)
	end
	local color = kindColor(kind)
	local strip = Kit.Frame("Strip", panel, UDim2.fromScale(0, 0), UDim2.fromScale(0.025, 1), color)
	Kit.Corner(strip, 0.5)
	local label = Kit.Label("Text", panel, text, UDim2.fromScale(0.05, 0.12), UDim2.fromScale(0.91, 0.76), "BodyBold", UITheme.Paper, 24)
	label.TextWrapped = true
	if kind == "gold" then
		label.TextColor3 = Kit.Hex(UITheme.Gold)
	end

	local toast: Toast = { Holder = holder, Panel = panel, Text = text, Kind = kind, Token = 0, Closing = false }
	table.insert(active, toast)
	TweenService:Create(panel, TweenInfo.new(SLIDE_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0, 0) }):Play()
	if kind == "bad" then
		Kit.PlaySound("Error")
	end
	schedule(toast, duration)
end

-- Public: show a toast from any client code.
function ToastController.Show(text: string, kind: string?, duration: number?)
	if type(text) ~= "string" or text == "" then
		return
	end
	local d = if type(duration) == "number" and duration > 0 then math.min(duration, 15) else DEFAULT_DURATION
	show(text, if type(kind) == "string" then kind else "info", d)
end

function ToastController.Clear()
	for i = #active, 1, -1 do
		removeToast(active[i])
	end
end

function ToastController.Init(_controllers: any)
	Net.Event("Notify").OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		ToastController.Show(tostring(payload.Text or ""), payload.Kind, payload.Duration)
	end)
end

function ToastController.Start()
	container = build()
	local queued = pending
	pending = {}
	for _, item in queued do
		show(item.Text, item.Kind, item.Duration)
	end
end

return ToastController
