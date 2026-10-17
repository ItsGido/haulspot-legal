--!strict
-- Shared widgets for the HUD, popups and phone screens (UI workstream).
-- Everything here builds on UI/Kit and Config/UITheme ("Manga Ink").

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Kit = require(script.Parent.Kit)
local UITheme = require(ReplicatedStorage.Shared.Config.UITheme)
local Ranks = require(ReplicatedStorage.Shared.Config.Ranks)
local DayCycleMath = require(ReplicatedStorage.Shared.Logic.DayCycleMath)

local W = {}

-- The Robux glyph renders inline in Roblox's built-in fonts.
W.Robux = utf8.char(0xE002)

W.KindColors = {
	info = UITheme.Paper,
	good = "#5FE08A",
	bad = "#E4322B",
	gold = "#FFE066",
	crew = UITheme.Sakura,
} :: { [string]: string }

W.ZoneExtra = {
	Road = "#3B3E48",
	Water = "#2A5A8A",
} :: { [string]: string }

-- Text -------------------------------------------------------------------------

function W.Escape(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

function W.Colored(text: string, color: string): string
	return string.format('<font color="%s">%s</font>', color, text)
end

-- Normalizes a color from a payload (Color3, "#RRGGBB" or "RRGGBB") to "#RRGGBB".
function W.ColorHex(value: any, fallback: string): string
	if typeof(value) == "Color3" then
		return "#" .. (value :: Color3):ToHex()
	elseif type(value) == "string" and #value >= 6 then
		local hex = if value:sub(1, 1) == "#" then value:sub(2) else value
		if hex:match("^%x%x%x%x%x%x$") then
			return "#" .. hex
		end
	end
	return fallback
end

-- Time -------------------------------------------------------------------------

function W.ServerNow(): number
	return workspace:GetServerTimeNow()
end

-- Seconds until a server unix timestamp (0 when missing or past).
function W.Remaining(endsAt: any): number
	if type(endsAt) ~= "number" then
		return 0
	end
	return math.max(0, endsAt - W.ServerNow())
end

function W.UtcToday(): number
	return DayCycleMath.UtcDay(W.ServerNow())
end

-- Seconds until the next 00:00 UTC.
function W.UntilUtcMidnight(): number
	local now = W.ServerNow()
	return (DayCycleMath.UtcDay(now) + 1) * 86400 - now
end

-- Misc helpers -------------------------------------------------------------------

function W.IsTyping(): boolean
	return UserInputService:GetFocusedTextBox() ~= nil
end

function W.RankInfo(rank: any): any
	local n = if type(rank) == "number" then rank else 1
	return Ranks.List[math.clamp(math.floor(n), 1, #Ranks.List)]
end

function W.LocalRank(): number
	local rank = Players.LocalPlayer:GetAttribute("Rank")
	return if type(rank) == "number" then rank else 1
end

function W.DisplayName(player: Player): string
	return player.DisplayName
end

-- Safe toast through ToastController (works before it has started).
function W.Toast(controllers: any, text: string, kind: string?, duration: number?)
	local toasts = controllers and controllers.ToastController
	if toasts and toasts.Show then
		toasts.Show(text, kind, duration)
	end
end

function W.OpenScreen(controllers: any, name: string, data: any?)
	local ui = controllers and controllers.UIController
	if ui and ui.Open then
		ui.Open(name, data)
	end
end

function W.PromptPass(id: number): boolean
	if id == 0 then
		return false
	end
	local ok = pcall(function()
		MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, id)
	end)
	return ok
end

function W.PromptProduct(id: number): boolean
	if id == 0 then
		return false
	end
	local ok = pcall(function()
		MarketplaceService:PromptProductPurchase(Players.LocalPlayer, id)
	end)
	return ok
end

-- Calls a RemoteFunction safely. Returns ok, message/result.
function W.Invoke(remote: RemoteFunction, ...: any): (boolean, any)
	local args = table.pack(...)
	local success, ok, result = pcall(function()
		return remote:InvokeServer(table.unpack(args, 1, args.n))
	end)
	if not success then
		return false, "Couldn't reach the server. Try again."
	end
	return ok == true, result
end

-- Layout building blocks -------------------------------------------------------

-- A HUD-style ScreenGui (not a window): stays across respawns, respects the safe area.
function W.Overlay(playerGui: Instance, name: string, displayOrder: number): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = displayOrder
	gui.Parent = playerGui
	return gui
end

-- A light card row (Panel Light, thin ink stroke).
function W.Row(parent: Instance, name: string, position: UDim2, size: UDim2, color: string?): Frame
	local row = Kit.Frame(name, parent, position, size, color or UITheme.PanelLight)
	Kit.Corner(row, 0.15)
	Kit.InkStroke(row, 2)
	return row
end

-- A small rounded reward chip ("+150 REP"). Sized by the caller or the parent's layout.
function W.Chip(parent: Instance, text: string, color: string, size: UDim2, layoutOrder: number?): TextLabel
	local chip = Kit.Label("Chip", parent, text, UDim2.new(), size, "BodyBold", UITheme.Ink, 18)
	chip.BackgroundTransparency = 0
	chip.BackgroundColor3 = Kit.Hex(color)
	chip.LayoutOrder = layoutOrder or 0
	Kit.Corner(chip, 0.5)
	Kit.InkStroke(chip, 2)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.08, 0)
	pad.PaddingRight = UDim.new(0.08, 0)
	pad.PaddingTop = UDim.new(0.12, 0)
	pad.PaddingBottom = UDim.new(0.12, 0)
	pad.Parent = chip
	return chip
end

-- Quick scale pop on any GuiObject.
function W.Pop(gui: GuiObject, from: number?)
	local scale = gui:FindFirstChildOfClass("UIScale")
	local s: UIScale
	if scale then
		s = scale
	else
		local created = Instance.new("UIScale")
		created.Parent = gui
		s = created
	end
	s.Scale = from or 1.15
	TweenService:Create(s, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- Buttons that can be turned off. Kit buttons still fire Activated, so handlers check W.IsEnabled.
function W.SetEnabled(button: TextButton, enabled: boolean, style: string)
	button:SetAttribute("KenkaDisabled", not enabled)
	Kit.SetButtonStyle(button, if enabled then style else "Disabled")
end

function W.IsEnabled(button: TextButton): boolean
	return button:GetAttribute("KenkaDisabled") ~= true
end

-- Scrolling lists with scale-sized rows: scale inside a ScrollingFrame is relative to the canvas,
-- so the canvas is sized from the row count. Returns the row height (canvas scale).
function W.ScrollRows(scroll: ScrollingFrame, count: number, rowFraction: number, gapFraction: number): number
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.None
	local canvas = math.max(1, count * (rowFraction + gapFraction))
	scroll.CanvasSize = UDim2.fromScale(0, canvas)
	local layout = scroll:FindFirstChildOfClass("UIListLayout")
	if layout then
		layout.Padding = UDim.new(gapFraction / canvas, 0)
	end
	return rowFraction / canvas
end

-- Tabs ----------------------------------------------------------------------------

export type Tabs = {
	Buttons: { [string]: TextButton },
	Select: (name: string) -> (),
	Current: () -> string,
}

function W.Tabs(parent: Instance, names: { string }, position: UDim2, size: UDim2, onSelect: (name: string) -> ()): Tabs
	local bar = Kit.Frame("Tabs", parent, position, size)
	local list = Kit.List(bar, 0.015, true)
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	local buttons: { [string]: TextButton } = {}
	local current = names[1]
	local width = (1 - 0.015 * (#names - 1)) / #names
	local function paint()
		for name, button in buttons do
			Kit.SetButtonStyle(button, if name == current then "Primary" else "Ghost")
		end
	end
	local function select(name: string)
		current = name
		paint()
		onSelect(name)
	end
	for i, name in names do
		local button = Kit.Button(bar, string.upper(name), "Ghost", UDim2.new(), UDim2.fromScale(width, 1))
		button.LayoutOrder = i
		buttons[name] = button
		button.Activated:Connect(function()
			if current ~= name then
				select(name)
			end
		end)
	end
	paint()
	return {
		Buttons = buttons,
		Select = select,
		Current = function()
			return current
		end,
	}
end

-- Toggle switch -------------------------------------------------------------------

export type Toggle = {
	Button: TextButton,
	Set: (value: boolean) -> (),
	Get: () -> boolean,
}

function W.Toggle(parent: Instance, position: UDim2, size: UDim2, initial: boolean, onChanged: (value: boolean) -> ()): Toggle
	local value = initial
	local button = Instance.new("TextButton")
	button.Name = "Toggle"
	button.AutoButtonColor = false
	button.Text = ""
	button.Position = position
	button.Size = size
	button.BorderSizePixel = 0
	button.Parent = parent
	Kit.Corner(button, 1)
	Kit.InkStroke(button, 3)
	Kit.Aspect(button, 2, true)
	local knob = Kit.Frame("Knob", button, UDim2.fromScale(0.05, 0.5), UDim2.fromScale(0.42, 0.84), UITheme.Paper, Vector2.new(0, 0.5))
	Kit.Corner(knob, 1)
	Kit.InkStroke(knob, 2)
	local function paint(animate: boolean)
		button.BackgroundColor3 = Kit.Hex(if value then "#5FE08A" else "#5A5E6B")
		local target = if value then UDim2.fromScale(0.53, 0.5) else UDim2.fromScale(0.05, 0.5)
		if animate then
			TweenService:Create(knob, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Position = target }):Play()
		else
			knob.Position = target
		end
	end
	paint(false)
	button.Activated:Connect(function()
		value = not value
		paint(true)
		Kit.PlaySound("Click")
		onChanged(value)
	end)
	return {
		Button = button,
		Set = function(v: boolean)
			value = v
			paint(false)
		end,
		Get = function()
			return value
		end,
	}
end

-- Slider (0..1) -------------------------------------------------------------------

export type Slider = {
	Frame: Frame,
	Set: (value: number) -> (),
	Get: () -> number,
}

function W.Slider(parent: Instance, position: UDim2, size: UDim2, initial: number, onChanged: (value: number) -> ()): Slider
	local value = math.clamp(initial, 0, 1)
	local track = Kit.Frame("Slider", parent, position, size, UITheme.Ink)
	track.Active = true
	Kit.Corner(track, 1)
	Kit.InkStroke(track, 2)
	local fill = Kit.Frame("Fill", track, UDim2.new(), UDim2.fromScale(value, 1), UITheme.Bars.Rep)
	Kit.Corner(fill, 1)
	local knob = Kit.Frame("Knob", track, UDim2.fromScale(value, 0.5), UDim2.fromScale(1.8, 1.8), UITheme.Paper, Vector2.new(0.5, 0.5))
	Kit.Corner(knob, 1)
	Kit.InkStroke(knob, 3)
	Kit.Aspect(knob, 1, true)
	local readout = Kit.Label("Value", track, "", UDim2.fromScale(1.04, 0.5), UDim2.fromScale(0.2, 2), "Number", UITheme.Paper, 22, Enum.TextXAlignment.Left)
	readout.AnchorPoint = Vector2.new(0, 0.5)

	local function paint()
		fill.Size = UDim2.fromScale(value, 1)
		knob.Position = UDim2.fromScale(value, 0.5)
		readout.Text = tostring(math.floor(value * 100 + 0.5)) .. "%"
	end
	paint()

	local dragging = false
	local function setFromX(x: number)
		local width = track.AbsoluteSize.X
		if width <= 0 then
			return
		end
		local v = math.clamp((x - track.AbsolutePosition.X) / width, 0, 1)
		v = math.floor(v * 20 + 0.5) / 20
		if v ~= value then
			value = v
			paint()
			onChanged(value)
		end
	end
	track.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	return {
		Frame = track,
		Set = function(v: number)
			value = math.clamp(v, 0, 1)
			paint()
		end,
		Get = function()
			return value
		end,
	}
end

-- Window helpers ---------------------------------------------------------------------

-- Keeps a Kit.Window panel at a fixed shape on any screen.
function W.ShapeWindow(window: Kit.Window, aspect: number)
	Kit.Aspect(window.Root, aspect)
end

-- A muted empty-state / info line.
function W.Note(parent: Instance, name: string, text: string, position: UDim2, size: UDim2): TextLabel
	local label = Kit.Label(name, parent, text, position, size, "Body", UITheme.Muted, 20)
	return label
end

return W
