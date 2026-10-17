--!strict
-- MainHUD (blueprint 5.1). Always-on HUD bound to attributes:
--   Character: HP, MaxHP, Posture, MaxPosture, Heat, MaxHeat?, Stance
--   Player:    Rank, RankTitle, Rep, Yen, Zone, ZoneType, InDuel, CrewId
--   ReplicatedStorage: PeriodName, PeriodEndsAt, CrownHolderName
-- Public API:
--   HUDController.GetTurfState() -> last Turf_Update payload (or nil)
--   HUDController.TurfChanged (Signal: payload)
--   HUDController.GetClockText() -> "AFTER SCHOOL 6:12"
--   HUDController.SetMobileControls(forced: boolean?)  (nil = auto-detect touch)
--   HUDController.SetVisible(visible: boolean)

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Util.Net)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Cleaner = require(ReplicatedStorage.Shared.Util.Cleaner)
local UITheme = require(ReplicatedStorage.Shared.Config.UITheme)
local Ranks = require(ReplicatedStorage.Shared.Config.Ranks)
local Styles = require(ReplicatedStorage.Shared.Config.Styles)
local Combat = require(ReplicatedStorage.Shared.Config.Combat)
local Crews = require(ReplicatedStorage.Shared.Config.Crews)
local DayCycle = require(ReplicatedStorage.Shared.Config.DayCycle)
local DayCycleMath = require(ReplicatedStorage.Shared.Logic.DayCycleMath)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local RepMath = require(ReplicatedStorage.Shared.Logic.RepMath)
local Kit = require(script.Parent.Parent.UI.Kit)
local W = require(script.Parent.Parent.UI.HudWidgets)

local HUDController = {}
HUDController.Priority = 20
HUDController.TurfChanged = Signal.new()

local player = Players.LocalPlayer
local Controllers: any

-- UI references (assigned in build()).
local hud: ScreenGui = nil :: any
local card: Frame = nil :: any
local badge: Frame = nil :: any
local rankNumber: TextLabel = nil :: any
local nameLabel: TextLabel = nil :: any
local hpBar: Frame = nil :: any
local hpGhost: Frame = nil :: any
local hpText: TextLabel = nil :: any
local postureBar: Frame = nil :: any
local heatBar: Frame = nil :: any
local heatStroke: UIStroke = nil :: any
local zonePill: Frame = nil :: any
local zoneLabel: TextLabel = nil :: any
local periodLabel: TextLabel = nil :: any
local currency: Frame = nil :: any
local yenLabel: TextLabel = nil :: any
local repBar: Frame = nil :: any
local repPct: TextLabel = nil :: any
local crownChip: Frame = nil :: any
local crownLabel: TextLabel = nil :: any
local turfTicker: Frame = nil :: any
local turfRows: { TextLabel } = {}
local duelBanner: Frame = nil :: any
local duelLabel: TextLabel = nil :: any
local stanceTag: TextLabel = nil :: any
local cluster: Frame = nil :: any

type CombatButton = {
	Button: TextButton,
	Label: TextLabel,
	Seconds: TextLabel,
	Overlay: Frame,
	Gradient: UIGradient,
	Action: string,
	Style: string,
}
local combatButtons: { [string]: CombatButton } = {}
local attackStroke: UIStroke? = nil
local heatButton: TextButton? = nil

-- State
local charCleaner = Cleaner.new()
local lastHP: number? = nil
local ghostToken = 0
local postureLow = false
local heatFull = false
local inStance = false
local mobileForced: boolean? = nil
local turfState: any = nil
local duelOpponent = ""
local cooldownEnds: { [string]: number } = {}
local cooldownTotal: { [string]: number } = {}
local yenValue: NumberValue = Instance.new("NumberValue")
local yenShown: number? = nil
local repShown: number? = nil
local lastZoneKey = ""

-- Helpers ----------------------------------------------------------------------------

local function dataGet(key: string): any
	local data = Controllers and Controllers.DataController
	if data and data.Get then
		return data.Get(key)
	end
	return nil
end

local function openScreen(name: string)
	local ui = Controllers and Controllers.UIController
	if ui and ui.Open then
		ui.Open(name)
	end
end

local function requestCombat(action: string)
	local combat = Controllers and Controllers.CombatController
	if combat and combat.Request then
		combat.Request(action)
	end
end

local function numberAttr(instance: Instance, name: string): number?
	local value = instance:GetAttribute(name)
	return if type(value) == "number" then value else nil
end

local function masteryLevel(): number
	local styles = dataGet("Styles")
	if type(styles) ~= "table" or type(styles.Mastery) ~= "table" then
		return 1
	end
	local entry = styles.Mastery[styles.Equipped]
	if type(entry) == "table" and type(entry.Level) == "number" then
		return entry.Level
	end
	return 1
end

local function equippedStyle(): any
	local styles = dataGet("Styles")
	local id = if type(styles) == "table" then styles.Equipped else nil
	if type(id) ~= "string" then
		local attr = player:GetAttribute("Style")
		id = if type(attr) == "string" then attr else Styles.DefaultStyle
	end
	return Styles.Styles[id] or Styles.Styles[Styles.DefaultStyle]
end

local function floatText(parent: GuiObject, text: string, color: string)
	local label = Kit.Label("Float", parent, text, UDim2.fromScale(0.5, 0.9), UDim2.fromScale(0.6, 0.4), "Number", color, 30)
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.ZIndex = 5
	Kit.TextStroke(label, 2)
	local info = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(label, info, { Position = UDim2.fromScale(0.5, 1.5), TextTransparency = 1 }):Play()
	for _, child in label:GetChildren() do
		if child:IsA("UIStroke") then
			TweenService:Create(child, info, { Transparency = 1 }):Play()
		end
	end
	task.delay(1, function()
		label:Destroy()
	end)
end

-- Build ------------------------------------------------------------------------------

local function buildPlayerCard()
	card = Kit.Panel("PlayerCard", hud, UDim2.fromScale(0.01, 0.02), UDim2.fromScale(0.24, 0.11))
	Kit.Aspect(card, 3.9)
	local corner = card:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0.12, 0)
	end

	badge = Kit.Frame("RankBadge", card, UDim2.fromScale(0.03, 0.5), UDim2.fromScale(0.22, 0.84), Ranks.List[1].Color, Vector2.new(0, 0.5))
	Kit.Corner(badge, 1)
	Kit.InkStroke(badge, 3)
	Kit.Aspect(badge, 1, true)
	local inner = Kit.Frame("Inner", badge, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.74, 0.74), UITheme.Panel, Vector2.new(0.5, 0.5))
	Kit.Corner(inner, 1)
	rankNumber = Kit.Label("RankNumber", inner, "1", UDim2.fromScale(0.1, 0.1), UDim2.fromScale(0.8, 0.8), "Title", UITheme.Paper, 40)
	local badgeButton = Instance.new("TextButton")
	badgeButton.Name = "RankButton"
	badgeButton.Text = ""
	badgeButton.BackgroundTransparency = 1
	badgeButton.Size = UDim2.fromScale(1, 1)
	badgeButton.Parent = badge
	badgeButton.Activated:Connect(function()
		openScreen("Fights")
	end)

	nameLabel = Kit.Label("NameLabel", card, player.DisplayName, UDim2.fromScale(0.27, 0.06), UDim2.fromScale(0.7, 0.28), "BodyBold", UITheme.Paper, 22, Enum.TextXAlignment.Left)

	hpBar = Kit.Bar("HPBar", card, UDim2.fromScale(0.27, 0.38), UDim2.fromScale(0.7, 0.24), UITheme.Bars.HPBack, UITheme.Bars.HP, 1)
	local hpFill = hpBar:FindFirstChild("Fill") :: Frame
	hpFill.ZIndex = 3
	hpGhost = Kit.Frame("Ghost", hpBar, UDim2.new(), UDim2.fromScale(1, 1), "#FFFFFF")
	hpGhost.BackgroundTransparency = 0.3
	hpGhost.ZIndex = 2
	Kit.Corner(hpGhost, 0.4)
	hpText = Kit.Label("HPText", hpBar, "", UDim2.fromScale(0.02, 0), UDim2.fromScale(0.96, 1), "Number", UITheme.Paper, 16, Enum.TextXAlignment.Right)
	hpText.ZIndex = 4
	Kit.TextStroke(hpText, 1.5)

	postureBar = Kit.Bar("PostureBar", card, UDim2.fromScale(0.27, 0.66), UDim2.fromScale(0.7, 0.14), UITheme.Bars.PostureBack, UITheme.Bars.Posture, 1)
	heatBar = Kit.Bar("HeatBar", card, UDim2.fromScale(0.27, 0.84), UDim2.fromScale(0.7, 0.1), UITheme.Ink, UITheme.Bars.Heat, 0)
	heatStroke = heatBar:FindFirstChildOfClass("UIStroke") :: UIStroke
end

local function buildTopCenter()
	zonePill = Kit.Frame("ZonePill", hud, UDim2.fromScale(0.5, 0.02), UDim2.fromScale(0.2, 0.05), UITheme.Zones.Yellow, Vector2.new(0.5, 0))
	Kit.Corner(zonePill, 1)
	Kit.InkStroke(zonePill, 3)
	Kit.Aspect(zonePill, 7.1)
	zonePill.Visible = false
	zoneLabel = Kit.Label("ZoneLabel", zonePill, "", UDim2.fromScale(0.05, 0.1), UDim2.fromScale(0.9, 0.8), "Title", UITheme.Paper, 30)

	local periodPill = Kit.Panel("PeriodPill", hud, UDim2.fromScale(0.5, 0.075), UDim2.fromScale(0.16, 0.04), Vector2.new(0.5, 0))
	Kit.Aspect(periodPill, 7.1)
	local pc = periodPill:FindFirstChildOfClass("UICorner")
	if pc then
		pc.CornerRadius = UDim.new(1, 0)
	end
	periodLabel = Kit.Label("PeriodLabel", periodPill, "", UDim2.fromScale(0.05, 0.12), UDim2.fromScale(0.9, 0.76), "BodyBold", UITheme.Paper, 22)

	duelBanner = Kit.Frame("DuelBanner", hud, UDim2.fromScale(0.5, 0.122), UDim2.fromScale(0.2, 0.034), "#FFFFFF", Vector2.new(0.5, 0))
	Kit.Corner(duelBanner, 0.3)
	Kit.InkStroke(duelBanner, 3)
	Kit.Aspect(duelBanner, 10.4)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(Kit.Hex(UITheme.Buttons.Primary[1]), Kit.Hex(UITheme.Buttons.Primary[2]))
	g.Parent = duelBanner
	duelLabel = Kit.Label("DuelLabel", duelBanner, "DUEL", UDim2.fromScale(0.04, 0.08), UDim2.fromScale(0.92, 0.84), "Title", UITheme.Paper, 26)
	duelBanner.Visible = false

	stanceTag = Kit.Label("StanceTag", hud, "STANCE", UDim2.fromScale(0.5, 0.86), UDim2.fromScale(0.12, 0.05), "Title", UITheme.Buttons.Primary[1], 34)
	stanceTag.AnchorPoint = Vector2.new(0.5, 0.5)
	stanceTag.Rotation = -3
	stanceTag.Visible = false
end

local function buildRight()
	currency = Kit.Panel("CurrencyStack", hud, UDim2.fromScale(0.99, 0.02), UDim2.fromScale(0.16, 0.1), Vector2.new(1, 0))
	Kit.Aspect(currency, 2.84)
	local cc = currency:FindFirstChildOfClass("UICorner")
	if cc then
		cc.CornerRadius = UDim.new(0.15, 0)
	end
	yenLabel = Kit.Label("YenLabel", currency, "¥ 0", UDim2.fromScale(0.07, 0.06), UDim2.fromScale(0.86, 0.5), "Number", UITheme.Gold, 36, Enum.TextXAlignment.Left)
	Kit.Label("RepTitle", currency, "REP", UDim2.fromScale(0.07, 0.6), UDim2.fromScale(0.16, 0.28), "BodyBold", UITheme.Paper, 18, Enum.TextXAlignment.Left)
	repBar = Kit.Bar("RepBar", currency, UDim2.fromScale(0.25, 0.64), UDim2.fromScale(0.5, 0.2), UITheme.Ink, UITheme.Bars.Rep, 0)
	repPct = Kit.Label("RepPct", currency, "0%", UDim2.fromScale(0.77, 0.58), UDim2.fromScale(0.2, 0.32), "Number", UITheme.Paper, 18, Enum.TextXAlignment.Left)

	local store = Kit.Button(hud, W.Robux .. " STORE", "Premium", UDim2.fromScale(0.99, 0.135), UDim2.fromScale(0.1, 0.06), Vector2.new(1, 0))
	store.Name = "StoreButton"
	Kit.Aspect(store, 2.96)
	store.Activated:Connect(function()
		openScreen("Store")
	end)

	crownChip = Kit.Panel("CrownChip", hud, UDim2.fromScale(0.885, 0.14), UDim2.fromScale(0.12, 0.045), Vector2.new(1, 0))
	Kit.Aspect(crownChip, 4.7)
	local chipCorner = crownChip:FindFirstChildOfClass("UICorner")
	if chipCorner then
		chipCorner.CornerRadius = UDim.new(1, 0)
	end
	local chipStroke = crownChip:FindFirstChildOfClass("UIStroke")
	if chipStroke then
		chipStroke.Color = Kit.Hex(UITheme.Gold)
	end
	crownLabel = Kit.Label("CrownLabel", crownChip, "", UDim2.fromScale(0.06, 0.1), UDim2.fromScale(0.88, 0.8), "BodyBold", UITheme.Gold, 20)
	crownChip.Visible = false

	turfTicker = Kit.Panel("TurfTicker", hud, UDim2.fromScale(0.99, 0.21), UDim2.fromScale(0.17, 0.18), Vector2.new(1, 0))
	Kit.Aspect(turfTicker, 1.68)
	turfTicker.Visible = false
	Kit.Label("Title", turfTicker, "TURF WAR", UDim2.fromScale(0.06, 0.03), UDim2.fromScale(0.88, 0.2), "Title", UITheme.Sakura, 26, Enum.TextXAlignment.Left)
	for i, id in Crews.TurfIds do
		local row = Kit.Label("Row" .. i, turfTicker, id .. " " .. (Crews.TurfNames :: any)[id], UDim2.fromScale(0.06, 0.24 + (i - 1) * 0.15), UDim2.fromScale(0.9, 0.14), "BodyBold", UITheme.Paper, 18, Enum.TextXAlignment.Left)
		turfRows[i] = row
	end
end

local function buildRail()
	local rail = Kit.Frame("MenuRail", hud, UDim2.fromScale(0.01, 0.42), UDim2.fromScale(0.055, 0.42), nil, Vector2.new(0, 0.5))
	Kit.List(rail, 0.015)
	local entries = {
		{ "PHONE", "📱", "Secondary", "Phone" },
		{ "STYLE", "👊", "Primary", "Style" },
		{ "CREW", "🚩", "Sakura", "Crew" },
		{ "MAP", "🗺", "Success", "Map" },
	}
	for i, entry in entries do
		local button = Kit.Button(rail, "", entry[3], UDim2.new(), UDim2.fromScale(1, 0.23))
		button.Name = entry[1] .. "Button"
		button.LayoutOrder = i
		Kit.Aspect(button, 1)
		Kit.Label("Glyph", button, entry[2], UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.6), "Body", UITheme.Paper, 30)
		local text = Kit.Label("Text", button, entry[1], UDim2.fromScale(-0.1, 0.62), UDim2.fromScale(1.2, 0.38), "BodyBold", UITheme.Paper, 14)
		Kit.TextStroke(text, 1.5, (UITheme.Buttons :: any)[entry[3]][3])
		local screen = entry[4]
		button.Activated:Connect(function()
			local ui = Controllers and Controllers.UIController
			if ui and ui.Toggle then
				ui.Toggle(screen)
			end
		end)
	end
end

-- Mobile combat cluster ------------------------------------------------------------------

local function makeRoundButton(name: string, text: string, style: string, right: number, bottom: number, height: number): CombatButton
	local b = Kit.Button(cluster, "", style, UDim2.fromScale(1 - right, 1 - bottom), UDim2.fromScale(1, height), Vector2.new(1, 1), true)
	b.Name = name .. "Button"
	Kit.Aspect(b, 1, true)
	local padding = b:FindFirstChildOfClass("UIPadding")
	if padding then
		padding:Destroy()
	end
	local overlay = Kit.Frame("Cooldown", b, UDim2.new(), UDim2.fromScale(1, 1), "#000000")
	overlay.ZIndex = 2
	overlay.Visible = false
	Kit.Corner(overlay, 1)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Parent = overlay
	local label = Kit.Label("Label", b, text, UDim2.fromScale(0.12, 0.3), UDim2.fromScale(0.76, 0.4), "Button", UITheme.Paper, 26)
	label.ZIndex = 3
	Kit.TextStroke(label, 2, (UITheme.Buttons :: any)[style][3])
	local seconds = Kit.Label("Seconds", b, "", UDim2.fromScale(0.15, 0.2), UDim2.fromScale(0.7, 0.6), "Number", UITheme.Paper, 30)
	seconds.ZIndex = 4
	Kit.TextStroke(seconds, 2)
	return { Button = b, Label = label, Seconds = seconds, Overlay = overlay, Gradient = gradient, Action = name, Style = style }
end

local function bindPress(entry: CombatButton, onDown: () -> (), onUp: (() -> ())?)
	local held = false
	local function release()
		if held then
			held = false
			if onUp then
				onUp()
			end
		end
	end
	entry.Button.InputBegan:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind ~= Enum.UserInputType.Touch and kind ~= Enum.UserInputType.MouseButton1 then
			return
		end
		if input.UserInputState ~= Enum.UserInputState.Begin or not W.IsEnabled(entry.Button) then
			return
		end
		held = true
		onDown()
		if onUp then
			local conn: RBXScriptConnection? = nil
			conn = input:GetPropertyChangedSignal("UserInputState"):Connect(function()
				local state = input.UserInputState
				if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
					if conn then
						conn:Disconnect()
					end
					release()
				end
			end)
		end
	end)
	if onUp then
		entry.Button.InputEnded:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				release()
			end
		end)
	end
end

local function buildCluster()
	cluster = Kit.Frame("MobileCombat", hud, UDim2.fromScale(0.985, 0.74), UDim2.fromScale(0.3, 0.32), nil, Vector2.new(1, 1))
	cluster.Visible = false
	-- name, text, style, right offset, bottom offset, height (all scale of the cluster)
	local layout: { { Name: string, Text: string, Style: string, Right: number, Bottom: number, Height: number } } = {
		{ Name = "M1", Text = "ATTACK", Style = "Primary", Right = 0.04, Bottom = 0, Height = 0.6 },
		{ Name = "Heavy", Text = "HEAVY", Style = "Primary", Right = 0.41, Bottom = 0, Height = 0.34 },
		{ Name = "Block", Text = "BLOCK", Style = "Secondary", Right = 0.41, Bottom = 0.52, Height = 0.34 },
		{ Name = "Dash", Text = "DASH", Style = "Secondary", Right = 0.63, Bottom = 0.04, Height = 0.3 },
		{ Name = "Tech1", Text = "TECH 1", Style = "Ghost", Right = 0.63, Bottom = 0.5, Height = 0.3 },
		{ Name = "Tech2", Text = "TECH 2", Style = "Ghost", Right = 0.83, Bottom = 0.04, Height = 0.27 },
		{ Name = "Stance", Text = "STANCE", Style = "Ghost", Right = 0.83, Bottom = 0.5, Height = 0.27 },
	}
	for _, info in layout do
		local entry = makeRoundButton(info.Name, info.Text, info.Style, info.Right, info.Bottom, info.Height)
		combatButtons[entry.Action] = entry
		if entry.Action == "Block" then
			bindPress(entry, function()
				requestCombat("BlockStart")
			end, function()
				requestCombat("BlockEnd")
			end)
		else
			local action = entry.Action
			bindPress(entry, function()
				requestCombat(action)
			end, nil)
		end
	end
	local attack = combatButtons.M1
	attack.Label.TextSize = 32
	attackStroke = attack.Button:FindFirstChildOfClass("UIStroke")

	local heat = makeRoundButton("Heat", "HEAT", "Premium", 0.13, 0.64, 0.26)
	heat.Button.Visible = false
	combatButtons.Heat = heat
	heatButton = heat.Button
	bindPress(heat, function()
		requestCombat("Heat")
	end, nil)
end

-- Updates ------------------------------------------------------------------------------

local function refreshTechButtons()
	local style = equippedStyle()
	local level = masteryLevel()
	local slots: { { Slot: string, Need: number, Tech: any } } = {
		{ Slot = "Tech1", Need = Styles.Tech1Mastery, Tech = style.Tech1 },
		{ Slot = "Tech2", Need = Styles.Tech2Mastery, Tech = style.Tech2 },
	}
	for _, slot in slots do
		local entry = combatButtons[slot.Slot]
		if entry then
			local unlocked = level >= slot.Need
			W.SetEnabled(entry.Button, unlocked, entry.Style)
			entry.Label.Text = if unlocked then string.upper(if slot.Tech then slot.Tech.Name else slot.Slot) else "🔒 M" .. slot.Need
		end
	end
	local heat = combatButtons.Heat
	if heat then
		local unlocked = level >= Styles.HeatMastery
		heat.Label.Text = if unlocked and style.Heat then string.upper(style.Heat.Name) else "HEAT"
		W.SetEnabled(heat.Button, unlocked, heat.Style)
	end
end

local function isMobile(): boolean
	if mobileForced ~= nil then
		return mobileForced
	end
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function refreshStance()
	local mobile = isMobile()
	stanceTag.Visible = inStance and not mobile
	local entry = combatButtons.Stance
	if entry then
		Kit.SetButtonStyle(entry.Button, if inStance then "Primary" else "Ghost")
	end
end

local function refreshMobile()
	cluster.Visible = isMobile()
	refreshStance()
end

local function refreshHeatReady()
	if attackStroke then
		attackStroke.Color = Kit.Hex(if heatFull then "#FFD23F" else UITheme.PanelStroke)
		attackStroke.Thickness = if heatFull then 6 else 3
	end
	if heatButton then
		heatButton.Visible = heatFull and masteryLevel() >= Styles.HeatMastery
	end
	if not heatFull then
		heatStroke.Color = Kit.Hex(UITheme.PanelStroke)
		heatStroke.Thickness = 2
	end
end

local function updateHP(character: Model)
	local hp = numberAttr(character, "HP")
	local maxHP = numberAttr(character, "MaxHP")
	if not hp or not maxHP or maxHP <= 0 then
		hpBar.Visible = false
		lastHP = nil
		return
	end
	hpBar.Visible = true
	local fraction = math.clamp(hp / maxHP, 0, 1)
	Kit.SetBar(hpBar, fraction, 0.15)
	hpText.Text = string.format("%d / %d", math.ceil(hp), math.floor(maxHP))
	ghostToken += 1
	local token = ghostToken
	local previous = lastHP
	if previous and hp < previous then
		task.delay(0.4, function()
			if token == ghostToken then
				TweenService:Create(hpGhost, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(fraction, 1) }):Play()
			end
		end)
		-- Getting hit closes the phone (blueprint 5.2).
		local ui = Controllers and Controllers.UIController
		if ui and ui.IsOpen and ui.IsOpen("Phone") then
			ui.Close("Phone")
		end
	else
		hpGhost.Size = UDim2.fromScale(fraction, 1)
	end
	lastHP = hp
end

local function updatePosture(character: Model)
	local posture = numberAttr(character, "Posture")
	local maxPosture = numberAttr(character, "MaxPosture") or Combat.MaxPosture
	if not posture or maxPosture <= 0 then
		postureBar.Visible = false
		postureLow = false
		return
	end
	postureBar.Visible = true
	local fraction = math.clamp(posture / maxPosture, 0, 1)
	Kit.SetBar(postureBar, fraction, 0.15)
	postureLow = fraction < 0.25
	if not postureLow then
		local fill = postureBar:FindFirstChild("Fill") :: Frame?
		if fill then
			fill.BackgroundTransparency = 0
		end
	end
end

local function updateHeat(character: Model)
	local heat = numberAttr(character, "Heat")
	local maxHeat = numberAttr(character, "MaxHeat") or Combat.MaxHeat
	if not heat or maxHeat <= 0 then
		heatBar.Visible = false
		heatFull = false
		refreshHeatReady()
		return
	end
	heatBar.Visible = true
	Kit.SetBar(heatBar, math.clamp(heat / maxHeat, 0, 1), 0.15)
	local full = heat >= maxHeat
	if full ~= heatFull then
		heatFull = full
		refreshHeatReady()
		if full then
			W.Pop(heatBar, 1.2)
		end
	end
end

local function updateStanceFromCharacter(character: Model)
	local combat = Controllers and Controllers.CombatController
	if combat and combat.IsInStance then
		inStance = combat.IsInStance() == true
	else
		inStance = character:GetAttribute("Stance") == true
	end
	refreshStance()
end

local function bindCharacter(character: Model)
	charCleaner:Clean()
	lastHP = nil
	local function hpChanged()
		updateHP(character)
	end
	local function postureChanged()
		updatePosture(character)
	end
	local function heatChanged()
		updateHeat(character)
	end
	charCleaner:Add(character:GetAttributeChangedSignal("HP"):Connect(hpChanged))
	charCleaner:Add(character:GetAttributeChangedSignal("MaxHP"):Connect(hpChanged))
	charCleaner:Add(character:GetAttributeChangedSignal("Posture"):Connect(postureChanged))
	charCleaner:Add(character:GetAttributeChangedSignal("MaxPosture"):Connect(postureChanged))
	charCleaner:Add(character:GetAttributeChangedSignal("Heat"):Connect(heatChanged))
	charCleaner:Add(character:GetAttributeChangedSignal("MaxHeat"):Connect(heatChanged))
	charCleaner:Add(character:GetAttributeChangedSignal("Stance"):Connect(function()
		updateStanceFromCharacter(character)
	end))
	hpChanged()
	postureChanged()
	heatChanged()
	updateStanceFromCharacter(character)
	-- A fresh character has no cooldowns running.
	table.clear(cooldownEnds)
end

local function updateIdentity()
	local rank = W.LocalRank()
	local info = W.RankInfo(rank)
	local title = player:GetAttribute("RankTitle")
	local titleText = if type(title) == "string" then title else info.Title
	local custom = dataGet("CustomName")
	local name = if type(custom) == "string" and custom ~= "" then custom else player.DisplayName
	nameLabel.Text = W.Escape(name) .. " " .. W.Colored("· " .. W.Escape(titleText), UITheme.Muted)
	rankNumber.Text = tostring(rank)
	badge.BackgroundColor3 = Kit.Hex(info.Color)
end

local function updateYen()
	local yen = numberAttr(player, "Yen")
	if not yen then
		local fromData = dataGet("Yen")
		yen = if type(fromData) == "number" then fromData else nil
	end
	if not yen then
		return
	end
	local previous = yenShown
	yenShown = yen
	if previous == nil then
		yenValue.Value = yen
		yenLabel.Text = "¥ " .. Format.Commas(yen)
		return
	end
	local delta = yen - previous
	if delta == 0 then
		return
	end
	TweenService:Create(yenValue, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { Value = yen }):Play()
	floatText(currency, (if delta > 0 then "+" else "-") .. Format.Commas(math.abs(delta)), if delta > 0 then UITheme.Gold else UITheme.Bars.HP)
end

local function updateRep()
	local rep = numberAttr(player, "Rep")
	if not rep then
		return
	end
	local progress = RepMath.Progress(Ranks, rep)
	Kit.SetBar(repBar, progress, if repShown then 0.4 else 0)
	repPct.Text = if RepMath.RankForRep(Ranks, rep) >= #Ranks.List then "MAX" else tostring(math.floor(progress * 100)) .. "%"
	local previous = repShown
	repShown = rep
	if previous and rep > previous then
		floatText(repBar, "+" .. Format.Commas(rep - previous) .. " REP", UITheme.Bars.Rep)
	end
end

local function updateZone()
	local zoneType = player:GetAttribute("ZoneType")
	local zone = player:GetAttribute("Zone")
	if type(zoneType) ~= "string" then
		zonePill.Visible = false
		return
	end
	zonePill.Visible = true
	local color = (UITheme.Zones :: any)[zoneType] or UITheme.Zones.Yellow
	zonePill.BackgroundColor3 = Kit.Hex(color)
	local zoneName = if type(zone) == "string" and zone ~= "" then " · " .. W.Escape(zone) else ""
	zoneLabel.Text = string.upper(zoneType) .. " ZONE" .. zoneName
	local key = zoneType .. "|" .. tostring(zone)
	if lastZoneKey ~= "" and key ~= lastZoneKey then
		W.Pop(zonePill, 1.25)
	end
	lastZoneKey = key
end

local function clockParts(): (string, number)
	local name = ReplicatedStorage:GetAttribute("PeriodName")
	local endsAt = ReplicatedStorage:GetAttribute("PeriodEndsAt")
	if type(name) == "string" and type(endsAt) == "number" then
		return name, W.Remaining(endsAt)
	end
	local state = DayCycleMath.At(DayCycle, W.ServerNow())
	return state.Name, state.Remaining
end

local function updatePeriod()
	local name, remaining = clockParts()
	periodLabel.Text = W.Escape(name) .. "  " .. W.Colored(DayCycleMath.FormatClock(remaining), UITheme.Bars.Posture)
end

local function updateCrown()
	local holder = ReplicatedStorage:GetAttribute("CrownHolderName")
	if type(holder) == "string" and holder ~= "" then
		crownChip.Visible = true
		crownLabel.Text = "♛ " .. W.Escape(holder)
	else
		crownChip.Visible = false
	end
end

local function updateDuel()
	local inDuel = player:GetAttribute("InDuel") == true
	duelBanner.Visible = inDuel
	if inDuel then
		duelLabel.Text = if duelOpponent ~= "" then "DUEL vs " .. W.Escape(duelOpponent) else "DUEL!"
		W.Pop(duelBanner, 1.2)
	end
end

local function progressBlocks(progress: any): string
	local p = if type(progress) == "number" then math.clamp(progress, 0, 100) else 0
	local filled = math.floor(p / 100 * 4 + 0.5)
	return string.rep("▮", filled) .. string.rep("▯", 4 - filled)
end

local function renderTurf()
	local payload = turfState
	if type(payload) ~= "table" then
		turfTicker.Visible = false
		return
	end
	turfTicker.Visible = payload.Active == true
	local turfs = if type(payload.Turfs) == "table" then payload.Turfs else {}
	for i, id in Crews.TurfIds do
		local row = turfRows[i]
		local t = turfs[id]
		local turfName = (Crews.TurfNames :: any)[id]
		local status: string
		if type(t) == "table" then
			if type(t.Name) == "string" then
				turfName = t.Name
			end
			if t.Contested then
				status = W.Colored("contested " .. progressBlocks(t.Progress), UITheme.Bars.Posture)
			elseif type(t.CapturingName) == "string" then
				status = W.Colored(W.Escape(t.CapturingName) .. " " .. progressBlocks(t.Progress), W.ColorHex(t.CapturingColor, UITheme.Sakura))
			elseif type(t.OwnerName) == "string" then
				local emblem = if type(t.OwnerEmblem) == "string" then t.OwnerEmblem .. " " else ""
				status = W.Colored(W.Escape(emblem .. t.OwnerName), W.ColorHex(t.OwnerColor, UITheme.Paper))
			else
				status = W.Colored("unclaimed", UITheme.Muted)
			end
		else
			status = W.Colored("unclaimed", UITheme.Muted)
		end
		row.Text = id .. " " .. W.Escape(turfName) .. " · " .. status
	end
end

local function setCooldownFill(entry: CombatButton, remaining: number, total: number)
	if remaining <= 0 then
		entry.Overlay.Visible = false
		entry.Seconds.Text = ""
		entry.Label.TextTransparency = 0
		return
	end
	local fraction = math.clamp(remaining / math.max(total, 0.01), 0, 1)
	local edge = math.clamp(1 - fraction, 0.001, 0.997)
	entry.Overlay.Visible = true
	entry.Gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(edge, 1),
		NumberSequenceKeypoint.new(edge + 0.002, 0.3),
		NumberSequenceKeypoint.new(1, 0.3),
	})
	entry.Seconds.Text = if remaining < 1 then string.format("%.1f", remaining) else tostring(math.ceil(remaining))
	entry.Label.TextTransparency = 0.7
end

local function onCooldown(action: any, endsAtClock: any)
	if type(action) ~= "string" or type(endsAtClock) ~= "number" then
		return
	end
	cooldownEnds[action] = endsAtClock
	cooldownTotal[action] = math.max(0.05, endsAtClock - os.clock())
end

local function stepFrame()
	local now = os.clock()
	-- Posture flashes under 25%.
	if postureLow and postureBar.Visible then
		local fill = postureBar:FindFirstChild("Fill") :: Frame?
		if fill then
			fill.BackgroundTransparency = 0.6 * (0.5 + 0.5 * math.sin(now * 14))
		end
	end
	-- Heat glows at 100.
	if heatFull then
		heatStroke.Color = Kit.Hex("#FFD23F")
		heatStroke.Thickness = 2 + 2 * (0.5 + 0.5 * math.sin(now * 8))
	end
	-- Cooldown overlays (only while the cluster is visible).
	if cluster.Visible then
		local combat = Controllers and Controllers.CombatController
		for action, entry in combatButtons do
			local remaining = 0
			local ends = cooldownEnds[action]
			if ends then
				remaining = math.max(0, ends - now)
				if remaining <= 0 then
					cooldownEnds[action] = nil
				end
			elseif combat and combat.GetCooldownRemaining then
				local r = combat.GetCooldownRemaining(action)
				if type(r) == "number" and r > 0 then
					onCooldown(action, now + r)
					remaining = r
				end
			end
			setCooldownFill(entry, remaining, cooldownTotal[action] or remaining)
		end
	end
end

-- Phone hotkey ------------------------------------------------------------------------------

local function onPhoneKey(_name: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult?
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if W.IsTyping() then
		return Enum.ContextActionResult.Pass
	end
	local ui = Controllers and Controllers.UIController
	if ui and ui.Toggle then
		ui.Toggle("Phone")
	end
	return Enum.ContextActionResult.Sink
end

-- Public API ------------------------------------------------------------------------------

function HUDController.GetTurfState(): any
	return turfState
end

function HUDController.GetClockText(): string
	local name, remaining = clockParts()
	return name .. " " .. DayCycleMath.FormatClock(remaining)
end

function HUDController.SetMobileControls(forced: boolean?)
	mobileForced = forced
	if cluster then
		refreshMobile()
	end
end

function HUDController.SetVisible(visible: boolean)
	if hud then
		hud.Enabled = visible
	end
end

-- Lifecycle -------------------------------------------------------------------------------

function HUDController.Init(controllers: any)
	Controllers = controllers
	Net.Event("Turf_Update").OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		turfState = payload
		HUDController.TurfChanged:Fire(payload)
		if turfTicker then
			renderTurf()
		end
	end)
	Net.Event("Challenge_Update").OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		if payload.State == "Started" then
			local opponent = payload.Opponent
			if type(payload.OpponentName) == "string" then
				duelOpponent = payload.OpponentName
			elseif typeof(opponent) == "Instance" and opponent:IsA("Player") then
				duelOpponent = opponent.DisplayName
			end
			if duelBanner then
				updateDuel()
			end
		elseif payload.State == "Ended" or payload.State == "Cancelled" then
			duelOpponent = ""
		end
	end)
	-- Fallback cooldown source if CombatController doesn't publish CooldownChanged.
	Net.Event("Combat_Cooldown").OnClientEvent:Connect(function(action: any, seconds: any)
		if type(action) == "string" and type(seconds) == "number" and seconds > 0 then
			onCooldown(action, os.clock() + seconds)
		end
	end)
end

function HUDController.Start()
	hud = W.Overlay(player:WaitForChild("PlayerGui"), "MainHUD", 1)
	buildPlayerCard()
	buildTopCenter()
	buildRight()
	buildRail()
	buildCluster()

	yenValue.Changed:Connect(function(value: number)
		yenLabel.Text = "¥ " .. Format.Commas(math.floor(value + 0.5))
	end)

	-- Player attributes
	for _, name in { "Rank", "RankTitle" } do
		player:GetAttributeChangedSignal(name):Connect(updateIdentity)
	end
	player:GetAttributeChangedSignal("Yen"):Connect(updateYen)
	player:GetAttributeChangedSignal("Rep"):Connect(updateRep)
	player:GetAttributeChangedSignal("ZoneType"):Connect(updateZone)
	player:GetAttributeChangedSignal("Zone"):Connect(updateZone)
	player:GetAttributeChangedSignal("InDuel"):Connect(updateDuel)
	player:GetAttributeChangedSignal("Style"):Connect(refreshTechButtons)
	ReplicatedStorage:GetAttributeChangedSignal("CrownHolderName"):Connect(updateCrown)
	ReplicatedStorage:GetAttributeChangedSignal("PeriodName"):Connect(updatePeriod)

	local data = Controllers.DataController
	if data and data.Changed then
		data.Changed:Connect(function(key: string)
			if key == "Styles" then
				refreshTechButtons()
				refreshHeatReady()
			elseif key == "CustomName" then
				updateIdentity()
			elseif key == "Yen" then
				updateYen()
			end
		end)
	end

	-- Combat controller signals (optional, built by the Combat workstream)
	local combat = Controllers.CombatController
	if combat then
		if combat.CooldownChanged then
			combat.CooldownChanged:Connect(onCooldown)
		end
		if combat.StanceChanged then
			combat.StanceChanged:Connect(function(value: any)
				inStance = value == true
				refreshStance()
			end)
		end
	end

	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(refreshMobile)
	UserInputService:GetPropertyChangedSignal("KeyboardEnabled"):Connect(refreshMobile)

	ContextActionService:BindAction("KenkaPhone", onPhoneKey, false, Enum.KeyCode.LeftAlt, Enum.KeyCode.DPadUp)

	player.CharacterAdded:Connect(bindCharacter)
	player.CharacterRemoving:Connect(function()
		charCleaner:Clean()
	end)
	if player.Character then
		bindCharacter(player.Character)
	end

	updateIdentity()
	updateYen()
	updateRep()
	updateZone()
	updatePeriod()
	updateCrown()
	updateDuel()
	renderTurf()
	refreshTechButtons()
	refreshMobile()
	refreshHeatReady()

	RunService.RenderStepped:Connect(stepFrame)

	task.spawn(function()
		while true do
			updatePeriod()
			task.wait(1)
		end
	end)

	if data and data.WaitForLoad then
		data.WaitForLoad()
		updateIdentity()
		updateYen()
		refreshTechButtons()
	end
end

return HUDController
