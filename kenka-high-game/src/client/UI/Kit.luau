--!strict
-- "Manga Ink" UI building blocks (blueprint section 4). Every screen is built from these so the
-- whole game looks consistent. All sizes are Scale-based UDim2 values.
--
--   local Kit = require(script.Parent.Kit)
--   local window = Kit.Window(parentGui, "RUMORS", UDim2.fromScale(0.6, 0.7))
--   local btn = Kit.Button(window.Body, "CLAIM", "Success", UDim2.fromScale(0.7, 0.8), UDim2.fromScale(0.25, 0.12))
--   btn.Activated:Connect(...)
--   Kit.OpenWindow(window) / Kit.CloseWindow(window)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local UITheme = require(ReplicatedStorage.Shared.Config.UITheme)

local Kit = {}
Kit.Theme = UITheme

local function hex(value: string): Color3
	return Color3.fromHex(value)
end
Kit.Hex = hex

function Kit.Corner(parent: Instance, scale: number?, offset: number?): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale or 0, offset or 0)
	c.Parent = parent
	return c
end

function Kit.InkStroke(parent: Instance, thickness: number?, color: string?): UIStroke
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Thickness = thickness or 3
	s.Color = hex(color or UITheme.PanelStroke)
	s.Parent = parent
	return s
end

function Kit.TextStroke(parent: Instance, thickness: number?, color: string?): UIStroke
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Thickness = thickness or 2
	s.Color = hex(color or "#000000")
	s.Parent = parent
	return s
end

function Kit.TextLimit(parent: Instance, maxSize: number): UITextSizeConstraint
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = maxSize
	c.Parent = parent
	return c
end

function Kit.Aspect(parent: Instance, ratio: number, dominantHeight: boolean?): UIAspectRatioConstraint
	local a = Instance.new("UIAspectRatioConstraint")
	a.AspectRatio = ratio
	if dominantHeight then
		a.DominantAxis = Enum.DominantAxis.Height
	end
	a.Parent = parent
	return a
end

function Kit.Padding(parent: Instance, scale: number): UIPadding
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(scale, 0)
	p.PaddingRight = UDim.new(scale, 0)
	p.PaddingTop = UDim.new(scale, 0)
	p.PaddingBottom = UDim.new(scale, 0)
	p.Parent = parent
	return p
end

function Kit.List(parent: Instance, padding: number?, horizontal: boolean?): UIListLayout
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(padding or 0.02, 0)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	l.Parent = parent
	return l
end

function Kit.Frame(name: string, parent: Instance, position: UDim2, size: UDim2, color: string?, anchor: Vector2?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Position = position
	f.Size = size
	f.AnchorPoint = anchor or Vector2.zero
	f.BorderSizePixel = 0
	if color then
		f.BackgroundColor3 = hex(color)
	else
		f.BackgroundTransparency = 1
	end
	f.Parent = parent
	return f
end

-- Dark panel with a black ink outline.
function Kit.Panel(name: string, parent: Instance, position: UDim2, size: UDim2, anchor: Vector2?, color: string?): Frame
	local f = Kit.Frame(name, parent, position, size, color or UITheme.Panel, anchor)
	Kit.Corner(f, 0.06)
	Kit.InkStroke(f, 3)
	return f
end

-- font: "Title" | "Button" | "Body" | "BodyBold" | "Number"
function Kit.Label(name: string, parent: Instance, text: string, position: UDim2, size: UDim2, font: string?, color: string?, maxSize: number?, alignX: Enum.TextXAlignment?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Position = position
	l.Size = size
	l.Text = text
	l.RichText = true
	l.Font = (UITheme.Fonts :: any)[font or "Body"] or UITheme.Fonts.Body
	l.TextColor3 = hex(color or UITheme.Paper)
	l.TextScaled = true
	l.TextWrapped = true
	l.TextXAlignment = alignX or Enum.TextXAlignment.Center
	Kit.TextLimit(l, maxSize or UITheme.TextMax.Body)
	if font == "Title" then
		Kit.TextStroke(l, 2)
	end
	l.Parent = parent
	return l
end

local sounds: { [string]: Sound } = {}
function Kit.PlaySound(name: string)
	local id = (UITheme.Sounds :: any)[name]
	if type(id) ~= "number" or id == 0 then
		return
	end
	local sound = sounds[name]
	if not sound then
		local created = Instance.new("Sound")
		created.SoundId = "rbxassetid://" .. id
		created.Parent = SoundService
		sounds[name] = created
		sound = created
	end
	SoundService:PlayLocalSound(sound :: Sound)
end

-- Adds the press/release scale animation and click sound to any GuiButton.
function Kit.Juice(button: GuiButton)
	local scale = button:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = button
	local pressIn = TweenInfo.new(UITheme.Motion.PressIn.Time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local release = TweenInfo.new(UITheme.Motion.PressOut.Time, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, pressIn, { Scale = UITheme.Motion.PressIn.Scale }):Play()
	end)
	local function up()
		TweenService:Create(scale, release, { Scale = 1 }):Play()
	end
	button.MouseButton1Up:Connect(up)
	button.MouseLeave:Connect(up)
	button.Activated:Connect(function()
		Kit.PlaySound("Click")
	end)
end

-- style: "Primary" | "Secondary" | "Premium" | "Success" | "Sakura" | "Ghost" | "Disabled"
function Kit.Button(parent: Instance, text: string, style: string, position: UDim2, size: UDim2, anchor: Vector2?, round: boolean?): TextButton
	local colors = (UITheme.Buttons :: any)[style] or UITheme.Buttons.Primary
	local b = Instance.new("TextButton")
	b.Name = text:gsub("%W", "") .. "Button"
	b.AutoButtonColor = false
	b.Position = position
	b.Size = size
	b.AnchorPoint = anchor or Vector2.zero
	b.BackgroundColor3 = Color3.new(1, 1, 1)
	b.BorderSizePixel = 0
	b.Text = text
	b.RichText = true
	b.Font = UITheme.Fonts.Button
	b.TextColor3 = hex(if style == "Disabled" then UITheme.Muted else UITheme.Paper)
	b.TextScaled = true
	Kit.TextLimit(b, UITheme.TextMax.Button)
	Kit.Corner(b, if round then 1 else 0.18)
	local gradient = Instance.new("UIGradient")
	gradient.Name = "Fill"
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(hex(colors[1]), hex(colors[2]))
	gradient.Parent = b
	Kit.InkStroke(b, 3)
	Kit.TextStroke(b, 2, colors[3])
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.08, 0)
	padding.PaddingRight = UDim.new(0.08, 0)
	padding.PaddingTop = UDim.new(0.15, 0)
	padding.PaddingBottom = UDim.new(0.15, 0)
	padding.Parent = b
	Kit.Juice(b)
	b.Parent = parent
	return b
end

-- Recolor an existing Kit.Button (e.g. affordable -> Disabled).
function Kit.SetButtonStyle(button: TextButton, style: string)
	local colors = (UITheme.Buttons :: any)[style] or UITheme.Buttons.Primary
	local gradient = button:FindFirstChild("Fill") :: UIGradient?
	if gradient then
		gradient.Color = ColorSequence.new(hex(colors[1]), hex(colors[2]))
	end
	for _, child in button:GetChildren() do
		if child:IsA("UIStroke") and child.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual then
			child.Color = hex(colors[3])
		end
	end
	button.TextColor3 = hex(if style == "Disabled" then UITheme.Muted else UITheme.Paper)
end

-- A bar with a "Fill" child. Kit.SetBar(bar, 0.5) to update.
function Kit.Bar(name: string, parent: Instance, position: UDim2, size: UDim2, backColor: string, fillColor: string | { string }, fraction: number?): Frame
	local back = Kit.Frame(name, parent, position, size, backColor)
	Kit.Corner(back, 0.4)
	Kit.InkStroke(back, 2)
	local fill = Kit.Frame("Fill", back, UDim2.fromScale(0, 0), UDim2.fromScale(math.clamp(fraction or 1, 0, 1), 1), "#FFFFFF")
	Kit.Corner(fill, 0.4)
	if type(fillColor) == "table" then
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new(hex(fillColor[1]), hex(fillColor[2]))
		g.Parent = fill
	else
		fill.BackgroundColor3 = hex(fillColor)
	end
	return back
end

function Kit.SetBar(bar: Frame, fraction: number, tweenTime: number?)
	local fill = bar:FindFirstChild("Fill") :: Frame?
	if not fill then
		return
	end
	local target = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
	if tweenTime and tweenTime > 0 then
		TweenService:Create(fill, TweenInfo.new(tweenTime, Enum.EasingStyle.Quad), { Size = target }):Play()
	else
		fill.Size = target
	end
end

export type Window = {
	Gui: ScreenGui,
	Dimmer: Frame,
	Root: Frame,
	Header: Frame,
	Title: TextLabel,
	Body: Frame,
	Close: TextButton,
	Scale: UIScale,
	OnClose: (() -> ())?,
}

-- A full window: its own ScreenGui with a dimmer, a panel with a slanted red header and a close button.
-- size is the panel size as screen scale. Body is the content area (fills the panel under the header).
function Kit.Window(playerGui: Instance, name: string, title: string, size: UDim2, displayOrder: number?): Window
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = displayOrder or 10
	gui.Enabled = false
	gui.Parent = playerGui

	local dimmer = Kit.Frame("Dimmer", gui, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), UITheme.Ink)
	dimmer.BackgroundTransparency = UITheme.Motion.DimmerTransparency
	dimmer.Active = true

	local root = Kit.Panel("Window", gui, UDim2.fromScale(0.5, 0.5), size, Vector2.new(0.5, 0.5))
	root.ClipsDescendants = false
	local scale = Instance.new("UIScale")
	scale.Parent = root

	local header = Kit.Frame("Header", root, UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.12), "#FFFFFF")
	Kit.Corner(header, 0.25)
	local headerGradient = Instance.new("UIGradient")
	headerGradient.Rotation = 90
	headerGradient.Color = ColorSequence.new(hex(UITheme.Buttons.Primary[1]), hex(UITheme.Buttons.Primary[2]))
	headerGradient.Parent = header
	Kit.InkStroke(header, 3)
	local titleLabel = Kit.Label("Title", header, title, UDim2.fromScale(0.03, 0.1), UDim2.fromScale(0.8, 0.8), "Title", UITheme.Paper, 48, Enum.TextXAlignment.Left)
	titleLabel.Rotation = -2

	local close = Kit.Button(root, "✕", "Primary", UDim2.new(1, 0, 0, 0), UDim2.fromScale(0.07, 0.11), Vector2.new(0.6, 0.4), true)
	close.Name = "CloseButton"
	Kit.Aspect(close, 1)

	local body = Kit.Frame("Body", root, UDim2.fromScale(0.03, 0.15), UDim2.fromScale(0.94, 0.82))

	local window: Window = {
		Gui = gui,
		Dimmer = dimmer,
		Root = root,
		Header = header,
		Title = titleLabel,
		Body = body,
		Close = close,
		Scale = scale,
		OnClose = nil,
	}
	close.Activated:Connect(function()
		Kit.CloseWindow(window)
	end)
	return window
end

function Kit.OpenWindow(window: Window)
	window.Gui.Enabled = true
	window.Scale.Scale = UITheme.Motion.PanelOpen.From
	window.Dimmer.BackgroundTransparency = 1
	TweenService:Create(window.Scale, TweenInfo.new(UITheme.Motion.PanelOpen.Time, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(window.Dimmer, TweenInfo.new(0.15), { BackgroundTransparency = UITheme.Motion.DimmerTransparency }):Play()
	Kit.PlaySound("Open")
end

function Kit.CloseWindow(window: Window)
	if not window.Gui.Enabled then
		return
	end
	local tween = TweenService:Create(window.Scale, TweenInfo.new(UITheme.Motion.PanelClose.Time), { Scale = UITheme.Motion.PanelClose.To })
	tween:Play()
	tween.Completed:Once(function()
		window.Gui.Enabled = false
	end)
	if window.OnClose then
		window.OnClose()
	end
end

-- Scrolling list area that grows with its content.
function Kit.Scroll(name: string, parent: Instance, position: UDim2, size: UDim2): ScrollingFrame
	local s = Instance.new("ScrollingFrame")
	s.Name = name
	s.Position = position
	s.Size = size
	s.BackgroundTransparency = 1
	s.BorderSizePixel = 0
	s.ScrollBarThickness = 6
	s.ScrollBarImageColor3 = hex(UITheme.Muted)
	s.CanvasSize = UDim2.new()
	s.AutomaticCanvasSize = Enum.AutomaticSize.Y
	s.ScrollingDirection = Enum.ScrollingDirection.Y
	s.Parent = parent
	return s
end

-- Clears every GuiObject child (keeps layouts and constraints).
function Kit.ClearChildren(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

return Kit
