--!strict
-- Style / Dojo (blueprint 5.4). Left: the 8 styles. Right: details, techniques, mastery, and actions.
-- Opened by StyleService at the Sensei with { AtDojo = true }; anywhere else it's view + unlock only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Util.Net)
local UITheme = require(ReplicatedStorage.Shared.Config.UITheme)
local Styles = require(ReplicatedStorage.Shared.Config.Styles)
local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local Kit = require(script.Parent.Parent.Kit)
local W = require(script.Parent.Parent.HudWidgets)

local Style = {}
Style.Name = "Style"

local Controllers: any
local windowRef: Kit.Window? = nil
local atDojo = false
local selected: string = Styles.DefaultStyle
local busy = false

local listFrame: Frame = nil :: any
local nameLabel: TextLabel = nil :: any
local iconLabel: TextLabel = nil :: any
local passiveLabel: TextLabel = nil :: any
local masteryLabel: TextLabel = nil :: any
local masteryBar: Frame = nil :: any
local xpLabel: TextLabel = nil :: any
local techFrame: Frame = nil :: any
local hintLabel: TextLabel = nil :: any
local equipButton: TextButton = nil :: any
local unlockButton: TextButton = nil :: any
local ticketButton: TextButton = nil :: any

local function getData(key: string): any
	local data = Controllers and Controllers.DataController
	return if data and data.Get then data.Get(key) else nil
end

local function profileStyles(): any
	local styles = getData("Styles")
	if type(styles) == "table" then
		return styles
	end
	return { Owned = { Styles.DefaultStyle }, Equipped = Styles.DefaultStyle, Mastery = {} }
end

local function owns(styles: any, id: string): boolean
	return type(styles.Owned) == "table" and table.find(styles.Owned, id) ~= nil
end

local function mastery(styles: any, id: string): (number, number)
	local entry = if type(styles.Mastery) == "table" then styles.Mastery[id] else nil
	local level = if type(entry) == "table" and type(entry.Level) == "number" then entry.Level else 1
	local xp = if type(entry) == "table" and type(entry.XP) == "number" then entry.XP else 0
	return level, xp
end

local function techDetails(tech: Styles.Technique, need: number, isHeat: boolean): string
	local parts = { (if isHeat then "Heat move · " else "") .. "Mastery " .. need }
	if tech.Hits then
		table.insert(parts, string.format("%d×%d dmg", tech.Hits, tech.Damage))
	else
		table.insert(parts, tech.Damage .. " dmg")
	end
	if tech.GuardBreak then
		table.insert(parts, "guard break")
	end
	if tech.RequiresParry then
		table.insert(parts, "after a parry")
	end
	if tech.KnockdownTime then
		table.insert(parts, "knockdown")
	end
	if tech.Kind == "Grab" then
		table.insert(parts, "unblockable grab")
	elseif tech.Kind == "Lunge" then
		table.insert(parts, "lunge")
	end
	if tech.Cooldown > 0 then
		table.insert(parts, tech.Cooldown .. " s cd")
	end
	return table.concat(parts, " · ")
end

local render: () -> ()

local function invoke(remoteName: string, ...: any)
	if busy then
		return
	end
	busy = true
	local ok, message = W.Invoke(Net.Function(remoteName), ...)
	busy = false
	if ok then
		Kit.PlaySound("Purchase")
	end
	local text = if type(message) == "string" and message ~= "" then message elseif ok then "Done!" else "That didn't work."
	W.Toast(Controllers, text, if ok then "good" else "bad")
	render()
end

local function renderList(styles: any)
	Kit.ClearChildren(listFrame)
	for i, style in Styles.Ordered() do
		local owned = owns(styles, style.Id)
		local isEquipped = styles.Equipped == style.Id
		local level = mastery(styles, style.Id)
		local text: string
		if owned then
			text = style.Icon .. " " .. string.upper(style.DisplayName) .. (if isEquipped then " ★" else "") .. " · M" .. level
		else
			text = "🔒 " .. string.upper(style.DisplayName) .. " · " .. style.ScrollCost .. " 📜"
		end
		local styleName = if style.Id == selected then (if owned then "Primary" else "Secondary") elseif owned then "Ghost" else "Disabled"
		local button = Kit.Button(listFrame, text, styleName, UDim2.new(), UDim2.fromScale(1, 0.112))
		button.Name = style.Id
		button.LayoutOrder = i
		button.TextXAlignment = Enum.TextXAlignment.Left
		if owned and style.Id ~= selected then
			-- owned styles keep their color as a left accent
			local accent = Kit.Frame("Accent", button, UDim2.fromScale(-0.07, -0.1), UDim2.fromScale(0.025, 1.2), style.Color)
			Kit.Corner(accent, 1)
		end
		local id = style.Id
		button.Activated:Connect(function()
			selected = id
			render()
		end)
	end
end

local function renderTechs(style: Styles.Style, level: number)
	Kit.ClearChildren(techFrame)
	local slots: { { Tech: Styles.Technique, Need: number, Heat: boolean } } = {
		{ Tech = style.Tech1, Need = Styles.Tech1Mastery, Heat = false },
		{ Tech = style.Tech2, Need = Styles.Tech2Mastery, Heat = false },
		{ Tech = style.Heat, Need = Styles.HeatMastery, Heat = true },
	}
	for i, slot in slots do
		local unlocked = level >= slot.Need
		local card = Kit.Panel("Tech" .. i, techFrame, UDim2.new(), UDim2.fromScale(0.32, 1), nil, UITheme.Panel)
		card.LayoutOrder = i
		card.BackgroundTransparency = if unlocked then 0 else 0.35
		local nameColor = if not unlocked then UITheme.Muted elseif slot.Heat then UITheme.Bars.Heat[1] else "#5FE08A"
		Kit.Label("Name", card, (if unlocked then "✓ " else "🔒 ") .. W.Escape(string.upper(slot.Tech.Name)), UDim2.fromScale(0.06, 0.06), UDim2.fromScale(0.88, 0.3), "Title", nameColor, 30, Enum.TextXAlignment.Left)
		Kit.Label("Info", card, W.Escape(techDetails(slot.Tech, slot.Need, slot.Heat)), UDim2.fromScale(0.06, 0.4), UDim2.fromScale(0.88, 0.54), "BodyBold", if unlocked then UITheme.Paper else UITheme.Muted, 18, Enum.TextXAlignment.Left)
	end
end

render = function()
	local window = windowRef
	if not window or not window.Gui.Enabled then
		return
	end
	local styles = profileStyles()
	local style = Styles.Styles[selected] or Styles.Styles[Styles.DefaultStyle]
	renderList(styles)

	nameLabel.Text = W.Escape(string.upper(style.DisplayName))
	iconLabel.Text = style.Icon
	passiveLabel.Text = "Passive · " .. W.Colored(W.Escape(style.Passive.Name), UITheme.Bars.Posture) .. ": " .. W.Escape(style.Passive.Description)

	local owned = owns(styles, style.Id)
	local level, xp = mastery(styles, style.Id)
	if level >= Styles.MaxMastery then
		masteryLabel.Text = "MASTERY " .. level
		Kit.SetBar(masteryBar, 1)
		xpLabel.Text = "MAX"
	else
		local need = Styles.MasteryXPPerLevel * level
		masteryLabel.Text = "MASTERY " .. level
		Kit.SetBar(masteryBar, xp / math.max(1, need), 0.2)
		xpLabel.Text = string.format("%s / %s XP", Format.Commas(xp), Format.Commas(need))
	end
	renderTechs(style, if owned then level else 0)

	local isEquipped = styles.Equipped == style.Id
	local scrolls = getData("Scrolls")
	local scrollCount = if type(scrolls) == "number" then scrolls else 0
	local tickets = getData("StyleTickets")
	local ticketCount = if type(tickets) == "number" then tickets else 0
	local product = Monetization.DeveloperProducts.StyleTicket

	equipButton.Visible = owned
	unlockButton.Visible = not owned
	ticketButton.Visible = not owned
	if owned then
		if isEquipped then
			equipButton.Text = "EQUIPPED"
			W.SetEnabled(equipButton, false, "Primary")
			hintLabel.Text = "This is your current style. Win fights to raise its mastery."
		else
			equipButton.Text = "EQUIP"
			W.SetEnabled(equipButton, atDojo, "Primary")
			hintLabel.Text = if atDojo then "Switch to this style. Your mastery is kept per style." else "Visit the Sensei at the Dojo to switch styles"
		end
	else
		local cost = style.ScrollCost
		unlockButton.Text = if cost > 0 then string.format("UNLOCK · %d 📜", cost) else "UNLOCK · FREE"
		W.SetEnabled(unlockButton, scrollCount >= cost, "Success")
		if ticketCount > 0 then
			ticketButton.Text = string.format("USE STYLE TICKET (%d)", ticketCount)
			W.SetEnabled(ticketButton, true, "Premium")
		elseif product.Id ~= 0 then
			ticketButton.Text = W.Robux .. " STYLE TICKET " .. product.Price
			W.SetEnabled(ticketButton, true, "Premium")
		else
			ticketButton.Text = "STYLE TICKET · SOON"
			W.SetEnabled(ticketButton, false, "Premium")
		end
		hintLabel.Text = string.format("You have %d scrolls. Earn them from rank-ups, rumors and tournaments.", scrollCount)
	end
end

function Style.Build(playerGui: Instance, controllers: any): Kit.Window
	Controllers = controllers
	local window = Kit.Window(playerGui, "Style", "DOJO · FIGHTING STYLES", UDim2.fromScale(0.8, 0.84))
	W.ShapeWindow(window, 1.65)
	windowRef = window
	local body = window.Body

	listFrame = Kit.Frame("Styles", body, UDim2.fromScale(0, 0), UDim2.fromScale(0.3, 1))
	Kit.List(listFrame, 0.014)

	local detail = Kit.Panel("Detail", body, UDim2.fromScale(0.32, 0), UDim2.fromScale(0.68, 1), nil, UITheme.PanelLight)
	local dc = detail:FindFirstChildOfClass("UICorner")
	if dc then
		dc.CornerRadius = UDim.new(0.03, 0)
	end
	nameLabel = Kit.Label("StyleName", detail, "", UDim2.fromScale(0.04, 0.02), UDim2.fromScale(0.74, 0.14), "Title", UITheme.Paper, 64, Enum.TextXAlignment.Left)
	nameLabel.Rotation = -2
	iconLabel = Kit.Label("Icon", detail, "", UDim2.fromScale(0.82, 0.02), UDim2.fromScale(0.14, 0.14), "Number", UITheme.Paper, 60)
	passiveLabel = Kit.Label("Passive", detail, "", UDim2.fromScale(0.04, 0.17), UDim2.fromScale(0.92, 0.08), "BodyBold", UITheme.Paper, 24, Enum.TextXAlignment.Left)
	masteryLabel = Kit.Label("Mastery", detail, "", UDim2.fromScale(0.04, 0.27), UDim2.fromScale(0.18, 0.06), "BodyBold", UITheme.Paper, 20, Enum.TextXAlignment.Left)
	masteryBar = Kit.Bar("MasteryBar", detail, UDim2.fromScale(0.23, 0.28), UDim2.fromScale(0.5, 0.04), UITheme.Ink, UITheme.Bars.Rep, 0)
	xpLabel = Kit.Label("XP", detail, "", UDim2.fromScale(0.75, 0.27), UDim2.fromScale(0.21, 0.06), "Number", UITheme.Paper, 18, Enum.TextXAlignment.Right)

	techFrame = Kit.Frame("Techniques", detail, UDim2.fromScale(0.04, 0.37), UDim2.fromScale(0.92, 0.36))
	local techList = Kit.List(techFrame, 0.02, true)
	techList.HorizontalAlignment = Enum.HorizontalAlignment.Center

	hintLabel = Kit.Label("Hint", detail, "", UDim2.fromScale(0.04, 0.75), UDim2.fromScale(0.92, 0.07), "Body", UITheme.Muted, 20)

	equipButton = Kit.Button(detail, "EQUIP", "Primary", UDim2.fromScale(0.04, 0.83), UDim2.fromScale(0.92, 0.13))
	unlockButton = Kit.Button(detail, "UNLOCK", "Success", UDim2.fromScale(0.04, 0.83), UDim2.fromScale(0.45, 0.13))
	ticketButton = Kit.Button(detail, "STYLE TICKET", "Premium", UDim2.fromScale(0.51, 0.83), UDim2.fromScale(0.45, 0.13))

	equipButton.Activated:Connect(function()
		if not W.IsEnabled(equipButton) then
			if not atDojo then
				W.Toast(Controllers, "Visit the Sensei at the Dojo to switch styles", "info")
			end
			return
		end
		invoke("Style_Equip", selected)
	end)
	unlockButton.Activated:Connect(function()
		if not W.IsEnabled(unlockButton) then
			W.Toast(Controllers, "Not enough scrolls yet.", "bad")
			return
		end
		invoke("Style_Unlock", selected, "Scrolls")
	end)
	ticketButton.Activated:Connect(function()
		if W.IsEnabled(ticketButton) then
			invoke("Style_Unlock", selected, "Robux")
		end
	end)

	local data = controllers.DataController
	if data and data.Changed then
		data.Changed:Connect(function(key: string)
			if key == "Styles" or key == "Scrolls" or key == "StyleTickets" then
				render()
			end
		end)
	end
	return window
end

function Style.Open(_window: Kit.Window, data: any?)
	atDojo = type(data) == "table" and data.AtDojo == true
	local styles = profileStyles()
	if type(data) == "table" and type(data.StyleId) == "string" and Styles.Styles[data.StyleId] then
		selected = data.StyleId
	elseif type(styles.Equipped) == "string" and Styles.Styles[styles.Equipped] then
		selected = styles.Equipped
	end
	task.defer(render)
end

function Style.Close(_window: Kit.Window)
	atDojo = false
end

return Style
