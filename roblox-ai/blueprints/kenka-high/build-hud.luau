-- KENKA HIGH: HUD builder (blueprint.md sections 4 and 5.1, "Manga Ink" design system)
-- Paste into Roblox Studio > View > Command Bar and press Enter.
-- Builds StarterGui.MainHUD. Ctrl+Z undoes it. Running it again replaces the previous HUD.
-- Element names are stable so gameplay LocalScripts can find them (e.g. MainHUD.PlayerCard.HPBar.Fill).

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local StarterGui = game:GetService("StarterGui")
local recording = ChangeHistoryService:TryBeginRecording("Build Kenka High HUD")

local T = {
	Ink = "#0F1016",
	Panel = "#1C1E2B",
	PanelLight = "#262A3B",
	Paper = "#F5F1E8",
	Muted = "#A9ADBD",
	Primary = { "#FF5A4F", "#B81D17", "#4A0906" },
	Secondary = { "#4A6FC4", "#22397A", "#0B1530" },
	Premium = { "#FFE066", "#E09A00", "#6B4400" },
	Success = { "#5FE08A", "#249A4C", "#0B3D1D" },
	Sakura = { "#FFB3D2", "#E0679B", "#5A1030" },
	Ghost = { "#262A3B", "#262A3B", "#000000" },
	HP = "#E4322B",
	HPBack = "#3A0F0E",
	Posture = "#F4C542",
	PostureBack = "#3A300E",
	Heat = { "#FF7A1A", "#FFD23F" },
	ZoneRed = "#E4322B",
	Gold = "#FFE066",
	RankGold = "#FFB627",
}

local function hex(value)
	return Color3.fromHex(value)
end

local old = StarterGui:FindFirstChild("MainHUD")
if old then
	old:Destroy()
end

local hud = Instance.new("ScreenGui")
hud.Name = "MainHUD"
hud.ResetOnSpawn = false
hud.IgnoreGuiInset = false
hud.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
hud.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
hud.Parent = StarterGui

-- Helpers -------------------------------------------------------------------

local function corner(parent, scale)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale, 0)
	c.Parent = parent
end

local function inkStroke(parent, thickness)
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Thickness = thickness or 4
	s.Color = hex("#000000")
	s.Parent = parent
end

local function textLimit(parent, maxSize)
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = maxSize
	c.Parent = parent
end

local function frame(name, parent, position, size, anchor, color)
	local f = Instance.new("Frame")
	f.Name = name
	f.Position = position
	f.Size = size
	f.AnchorPoint = anchor or Vector2.zero
	if color then
		f.BackgroundColor3 = hex(color)
	else
		f.BackgroundTransparency = 1
	end
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

local function panel(name, parent, position, size, anchor)
	local f = frame(name, parent, position, size, anchor, T.Panel)
	corner(f, 0.12)
	inkStroke(f, 3)
	return f
end

local function label(name, parent, text, position, size, font, color, maxSize, alignX)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Position = position
	l.Size = size
	l.Text = text
	l.Font = font
	l.TextColor3 = hex(color or T.Paper)
	l.TextScaled = true
	l.TextXAlignment = alignX or Enum.TextXAlignment.Center
	textLimit(l, maxSize or 28)
	l.Parent = parent
	return l
end

-- A bar with a back color and a "Fill" child sized by scale (0..1).
local function bar(name, parent, position, size, backColor, fillColor, fill)
	local back = frame(name, parent, position, size, nil, backColor)
	corner(back, 0.4)
	inkStroke(back, 2)
	local f = frame("Fill", back, UDim2.fromScale(0, 0), UDim2.fromScale(fill, 1), nil, "#FFFFFF")
	corner(f, 0.4)
	if type(fillColor) == "table" then
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new(hex(fillColor[1]), hex(fillColor[2]))
		g.Parent = f
	else
		f.BackgroundColor3 = hex(fillColor)
	end
	return back
end

-- Manga Ink button: gradient fill, 4 px black border, colored text outline, UIScale for press feel.
local function button(name, parent, text, style, position, size, anchor, aspect, round)
	local b = Instance.new("TextButton")
	b.Name = name
	b.AutoButtonColor = false
	b.Position = position
	b.Size = size
	b.AnchorPoint = anchor or Vector2.zero
	b.BackgroundColor3 = hex("#FFFFFF")
	b.BorderSizePixel = 0
	b.Text = text
	b.Font = Enum.Font.BuilderSansBold
	b.TextColor3 = hex(T.Paper)
	b.TextScaled = true
	textLimit(b, 32)

	corner(b, round and 1 or 0.18)

	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(hex(style[1]), hex(style[2]))
	g.Parent = b

	inkStroke(b, 4)

	local textStroke = Instance.new("UIStroke") -- Contextual mode outlines the text
	textStroke.Thickness = 2
	textStroke.Color = hex(style[3])
	textStroke.Parent = b

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.1, 0)
	padding.PaddingRight = UDim.new(0.1, 0)
	padding.PaddingTop = UDim.new(0.18, 0)
	padding.PaddingBottom = UDim.new(0.18, 0)
	padding.Parent = b

	if aspect then
		local a = Instance.new("UIAspectRatioConstraint")
		a.AspectRatio = aspect
		a.DominantAxis = Enum.DominantAxis.Height
		a.Parent = b
	end

	local s = Instance.new("UIScale")
	s.Parent = b

	b.Parent = parent
	return b
end

-- PlayerCard (0.01, 0.02) size (0.24, 0.11) ---------------------------------

local card = panel("PlayerCard", hud, UDim2.fromScale(0.01, 0.02), UDim2.fromScale(0.24, 0.11))

local badge = frame("RankBadge", card, UDim2.fromScale(0.03, 0.5), UDim2.fromScale(0.22, 0.84), Vector2.new(0, 0.5), T.RankGold)
corner(badge, 1)
inkStroke(badge, 3)
local badgeAspect = Instance.new("UIAspectRatioConstraint")
badgeAspect.AspectRatio = 1
badgeAspect.DominantAxis = Enum.DominantAxis.Height
badgeAspect.Parent = badge
local badgeInner = frame("Inner", badge, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.74, 0.74), Vector2.new(0.5, 0.5), T.Panel)
corner(badgeInner, 1)
label("RankNumber", badgeInner, "1", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), Enum.Font.Bangers, T.Paper, 40)

label("NameLabel", card, "Player · Transfer Student", UDim2.fromScale(0.26, 0.08), UDim2.fromScale(0.7, 0.26),
	Enum.Font.BuilderSansBold, T.Paper, 22, Enum.TextXAlignment.Left)
bar("HPBar", card, UDim2.fromScale(0.26, 0.38), UDim2.fromScale(0.71, 0.24), T.HPBack, T.HP, 1)
bar("PostureBar", card, UDim2.fromScale(0.26, 0.66), UDim2.fromScale(0.71, 0.14), T.PostureBack, T.Posture, 1)
bar("HeatBar", card, UDim2.fromScale(0.26, 0.84), UDim2.fromScale(0.71, 0.1), T.Ink, T.Heat, 0)

-- ZonePill (0.5, 0.02) size (0.2, 0.05) anchor (0.5, 0) ---------------------

local zonePill = frame("ZonePill", hud, UDim2.fromScale(0.5, 0.02), UDim2.fromScale(0.2, 0.05), Vector2.new(0.5, 0), T.ZoneRed)
corner(zonePill, 1)
inkStroke(zonePill, 3)
local zoneText = label("ZoneLabel", zonePill, "RED ZONE · RIVERBANK", UDim2.fromScale(0.05, 0.1), UDim2.fromScale(0.9, 0.8),
	Enum.Font.Bangers, T.Paper, 30)
local zoneTextStroke = Instance.new("UIStroke")
zoneTextStroke.Thickness = 2
zoneTextStroke.Color = hex("#000000")
zoneTextStroke.Parent = zoneText

-- PeriodPill (0.5, 0.075) size (0.16, 0.04) anchor (0.5, 0) -----------------

local periodPill = panel("PeriodPill", hud, UDim2.fromScale(0.5, 0.075), UDim2.fromScale(0.16, 0.04), Vector2.new(0.5, 0))
periodPill:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(1, 0)
label("PeriodLabel", periodPill, "AFTER SCHOOL  6:12", UDim2.fromScale(0.05, 0.12), UDim2.fromScale(0.9, 0.76),
	Enum.Font.BuilderSansBold, T.Paper, 22)

-- CurrencyStack (0.99, 0.02) size (0.16, 0.1) anchor (1, 0) -----------------

local currency = panel("CurrencyStack", hud, UDim2.fromScale(0.99, 0.02), UDim2.fromScale(0.16, 0.1), Vector2.new(1, 0))
label("YenLabel", currency, "¥ 0", UDim2.fromScale(0.07, 0.08), UDim2.fromScale(0.86, 0.5),
	Enum.Font.FredokaOne, T.Gold, 36, Enum.TextXAlignment.Left)
label("RepTitle", currency, "REP", UDim2.fromScale(0.07, 0.62), UDim2.fromScale(0.18, 0.26),
	Enum.Font.BuilderSansBold, T.Paper, 18, Enum.TextXAlignment.Left)
bar("RepBar", currency, UDim2.fromScale(0.27, 0.66), UDim2.fromScale(0.66, 0.18), T.Ink, T.RankGold, 0)

-- StoreButton (0.99, 0.135) size (0.1, 0.06) anchor (1, 0) ------------------

button("StoreButton", hud, "STORE", T.Premium, UDim2.fromScale(0.99, 0.135), UDim2.fromScale(0.1, 0.06), Vector2.new(1, 0))

-- TurfTicker (0.99, 0.21) size (0.17, 0.18) anchor (1, 0), hidden outside After School

local turf = panel("TurfTicker", hud, UDim2.fromScale(0.99, 0.21), UDim2.fromScale(0.17, 0.18), Vector2.new(1, 0))
turf.Visible = false
label("Title", turf, "TURF WAR", UDim2.fromScale(0.06, 0.04), UDim2.fromScale(0.88, 0.2), Enum.Font.Bangers, "#FF9EC4", 26,
	Enum.TextXAlignment.Left)
local turfNames = { "T1 Shotengai", "T2 Riverbank", "T3 Park", "T4 Docks", "T5 Neon Alley" }
for i, turfName in turfNames do
	label("Row" .. i, turf, turfName .. " · unclaimed", UDim2.fromScale(0.06, 0.24 + (i - 1) * 0.15), UDim2.fromScale(0.88, 0.14),
		Enum.Font.BuilderSansBold, T.Paper, 18, Enum.TextXAlignment.Left)
end

-- Toasts (0.5, 0.16) size (0.4, 0.06) anchor (0.5, 0): a template the toast script clones

local toasts = frame("Toasts", hud, UDim2.fromScale(0.5, 0.16), UDim2.fromScale(0.4, 0.2), Vector2.new(0.5, 0))
local toastList = Instance.new("UIListLayout")
toastList.Padding = UDim.new(0.03, 0)
toastList.HorizontalAlignment = Enum.HorizontalAlignment.Center
toastList.Parent = toasts
local toastTemplate = panel("ToastTemplate", toasts, UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.3))
toastTemplate.Visible = false
label("Text", toastTemplate, "⚠ RED ZONE: open fights", UDim2.fromScale(0.04, 0.12), UDim2.fromScale(0.92, 0.76),
	Enum.Font.BuilderSansBold, T.Paper, 24)

-- MenuRail (0.01, 0.42) size (0.055, 0.42) anchor (0, 0.5) ------------------

local rail = frame("MenuRail", hud, UDim2.fromScale(0.01, 0.42), UDim2.fromScale(0.055, 0.42), Vector2.new(0, 0.5))
local railList = Instance.new("UIListLayout")
railList.Padding = UDim.new(0.015, 0)
railList.SortOrder = Enum.SortOrder.LayoutOrder
railList.Parent = rail
local railButtons = {
	{ "PhoneButton", "PHONE", T.Secondary },
	{ "StyleButton", "STYLE", T.Primary },
	{ "CrewButton", "CREW", T.Sakura },
	{ "MapButton", "MAP", T.Success },
}
for i, info in railButtons do
	local b = button(info[1], rail, info[2], info[3], UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.23))
	b.LayoutOrder = i
	local square = Instance.new("UIAspectRatioConstraint")
	square.AspectRatio = 1
	square.Parent = b
end

-- Mobile combat cluster (0.985, 0.74) size (0.3, 0.32) anchor (1, 1) --------
-- Hidden by default. A LocalScript shows it when UserInputService.TouchEnabled is true.

local cluster = frame("MobileCombat", hud, UDim2.fromScale(0.985, 0.74), UDim2.fromScale(0.3, 0.32), Vector2.new(1, 1))
cluster.Visible = false
-- Name, text, style, right offset (scale from the right edge), bottom offset (scale from the bottom), height (scale)
local combatButtons = {
	{ "Attack", "ATTACK", T.Primary, 0.04, 0, 0.6 },
	{ "Heavy", "HEAVY", T.Primary, 0.41, 0, 0.34 },
	{ "Block", "BLOCK", T.Secondary, 0.41, 0.52, 0.34 },
	{ "Dash", "DASH", T.Secondary, 0.63, 0.04, 0.3 },
	{ "Tech1", "TECH 1", T.Ghost, 0.63, 0.5, 0.3 },
	{ "Tech2", "TECH 2", T.Ghost, 0.83, 0.04, 0.27 },
	{ "Stance", "STANCE", T.Ghost, 0.83, 0.5, 0.27 },
}
for _, info in combatButtons do
	local b = button(info[1] .. "Button", cluster, info[2], info[3], UDim2.fromScale(1 - info[4], 1 - info[5]),
		UDim2.fromScale(1, info[6]), Vector2.new(1, 1), 1, true)
	b.TextXAlignment = Enum.TextXAlignment.Center
end
-- Gold ring behind the Attack button, shown when Heat is full (an element can only have one border stroke).
local heatRing = frame("HeatReadyRing", cluster, UDim2.fromScale(0.97, 1.03), UDim2.fromScale(1, 0.66), Vector2.new(1, 1), "#FFD23F")
heatRing.ZIndex = 0
heatRing.Visible = false
corner(heatRing, 1)
local ringAspect = Instance.new("UIAspectRatioConstraint")
ringAspect.AspectRatio = 1
ringAspect.DominantAxis = Enum.DominantAxis.Height
ringAspect.Parent = heatRing

if recording then
	ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
end
print("Kenka High MainHUD built in StarterGui. Press Play to see it.")
