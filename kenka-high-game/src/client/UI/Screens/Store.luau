--!strict
-- Store (blueprint 5.10): Passes · Tokens · Term Pass, from Config/Monetization.
-- Purchases go through MarketplaceService prompts; the server grants (MonetizationService).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UITheme = require(ReplicatedStorage.Shared.Config.UITheme)
local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local Kit = require(script.Parent.Parent.Kit)
local W = require(script.Parent.Parent.HudWidgets)

local Store = {}
Store.Name = "Store"

local player = Players.LocalPlayer
local Controllers: any
local windowRef: Kit.Window? = nil
local grid: Frame = nil :: any
local infoLabel: TextLabel = nil :: any
local tabs: W.Tabs = nil :: any
local currentTab = "Passes"
local boughtPasses: { [number]: boolean } = {} -- passes bought this session (before the server refreshes)

local ICONS: { [string]: string } = {
	VIP = "👑",
	DoubleYen = "💴",
	OutfitSlots = "👕",
	CrewPlus = "🚩",
	StyleTicket = "🎫",
	CapsuleToken1 = "🎟",
	CapsuleToken10 = "🎟",
	StarterPack = "🎁",
	TermPass = "📘",
	NameChange = "✏",
	YenPack = "¥",
}

local PASS_ORDER = { "VIP", "DoubleYen", "OutfitSlots", "CrewPlus" }
local TOKEN_ORDER = { "StarterPack", "CapsuleToken1", "CapsuleToken10", "StyleTicket", "YenPack", "NameChange" }

local function getData(key: string): any
	local data = Controllers and Controllers.DataController
	return if data and data.Get then data.Get(key) else nil
end

local function ownsPass(product: Monetization.Product): boolean
	if product.Id ~= 0 and boughtPasses[product.Id] then
		return true
	end
	local derived = getData("Derived")
	return type(derived) == "table" and type(derived.Passes) == "table" and derived.Passes[product.Key] == true
end

local function starterAvailable(): boolean
	local pack = getData("StarterPack")
	if type(pack) ~= "table" or pack.Bought == true then
		return false
	end
	local firstJoin = if type(pack.FirstJoin) == "number" then pack.FirstJoin else 0
	return firstJoin > 0 and W.ServerNow() - firstJoin <= Monetization.StarterPackWindowHours * 3600
end

local function card(order: number, product: Monetization.Product, isPass: boolean, owned: boolean, badge: string?)
	local frame = Kit.Panel(product.Key, grid, UDim2.new(), UDim2.new(), nil, UITheme.PanelLight)
	frame.LayoutOrder = order
	local corner = frame:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0.08, 0)
	end
	if owned then
		local stroke = frame:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = Kit.Hex("#5FE08A")
		end
	end
	local iconText = ICONS[product.Key] or "★"
	if product.Key == "CapsuleToken10" then
		iconText ..= "×10"
	end
	Kit.Label("Icon", frame, iconText, UDim2.fromScale(0.05, 0.04), UDim2.fromScale(0.9, 0.28), "Number", UITheme.Gold, 54)
	local name = Kit.Label("Name", frame, W.Escape(string.upper(product.Name)), UDim2.fromScale(0.05, 0.33), UDim2.fromScale(0.9, 0.15), "Title", UITheme.Paper, 34)
	name.Rotation = -2
	Kit.Label("Desc", frame, W.Escape(product.Description), UDim2.fromScale(0.06, 0.5), UDim2.fromScale(0.88, 0.25), "Body", UITheme.Muted, 18)
	if badge then
		local tag = W.Chip(frame, badge, UITheme.Sakura, UDim2.fromScale(0.42, 0.1))
		tag.Position = UDim2.fromScale(0.97, 0.03)
		tag.AnchorPoint = Vector2.new(1, 0)
		tag.Rotation = 6
	end

	local button: TextButton
	if owned then
		button = Kit.Button(frame, "OWNED", "Disabled", UDim2.fromScale(0.08, 0.78), UDim2.fromScale(0.84, 0.17))
		button:SetAttribute("KenkaDisabled", true)
	elseif product.Id == 0 then
		button = Kit.Button(frame, "COMING SOON", "Disabled", UDim2.fromScale(0.08, 0.78), UDim2.fromScale(0.84, 0.17))
		button:SetAttribute("KenkaDisabled", true)
	else
		button = Kit.Button(frame, W.Robux .. " " .. Format.Commas(product.Price), "Premium", UDim2.fromScale(0.08, 0.78), UDim2.fromScale(0.84, 0.17))
	end
	local id = product.Id
	button.Activated:Connect(function()
		if not W.IsEnabled(button) then
			return
		end
		local ok = if isPass then W.PromptPass(id) else W.PromptProduct(id)
		if not ok then
			W.Toast(Controllers, "The store isn't available right now.", "bad")
		end
	end)
end

local function render()
	local window = windowRef
	if not window or not window.Gui.Enabled then
		return
	end
	Kit.ClearChildren(grid)
	if currentTab == "Passes" then
		infoLabel.Text = "Game passes are permanent and work in every server."
		for i, key in PASS_ORDER do
			local product = Monetization.GamePasses[key]
			if product then
				card(i, product, true, ownsPass(product), nil)
			end
		end
	elseif currentTab == "Tokens" then
		infoLabel.Text = "Capsules are cosmetic only. Odds are shown at Capsule Corner."
		local order = 0
		for _, key in TOKEN_ORDER do
			local product = Monetization.DeveloperProducts[key]
			if product and (key ~= "StarterPack" or starterAvailable()) then
				order += 1
				card(order, product, false, false, if key == "StarterPack" then "NEW STUDENTS" else nil)
			end
		end
	else
		local term = getData("Term")
		local termId = if type(term) == "table" and type(term.Id) == "number" then term.Id else 1
		local termRep = if type(term) == "table" and type(term.Rep) == "number" then term.Rep else 0
		local owned = type(term) == "table" and term.PassOwned == true
		infoLabel.Text = string.format("Term %d · Term Rep %s. The premium track adds cosmetic rewards for this term.", termId, Format.Commas(termRep))
		local product = Monetization.DeveloperProducts.TermPass
		card(1, product, false, owned, "THIS TERM")
	end
end

function Store.Build(playerGui: Instance, controllers: any): Kit.Window
	Controllers = controllers
	local window = Kit.Window(playerGui, "Store", "STORE", UDim2.fromScale(0.78, 0.84))
	W.ShapeWindow(window, 1.6)
	windowRef = window
	local headerGradient = window.Header:FindFirstChildOfClass("UIGradient")
	if headerGradient then
		headerGradient.Color = ColorSequence.new(Kit.Hex(UITheme.Buttons.Premium[1]), Kit.Hex(UITheme.Buttons.Premium[2]))
	end
	local titleStroke = window.Title:FindFirstChildOfClass("UIStroke")
	if titleStroke then
		titleStroke.Color = Kit.Hex(UITheme.Buttons.Premium[3])
	end

	tabs = W.Tabs(window.Body, { "Passes", "Tokens", "Term Pass" }, UDim2.fromScale(0, 0), UDim2.fromScale(0.62, 0.1), function(name: string)
		currentTab = name
		render()
	end)
	infoLabel = Kit.Label("Info", window.Body, "", UDim2.fromScale(0.64, 0), UDim2.fromScale(0.36, 0.1), "Body", UITheme.Muted, 18, Enum.TextXAlignment.Right)

	grid = Kit.Frame("Cards", window.Body, UDim2.fromScale(0, 0.13), UDim2.fromScale(1, 0.87))
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromScale(0.235, 0.47)
	layout.CellPadding = UDim2.fromScale(0.02, 0.04)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = grid

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(who: Player, passId: number, purchased: boolean)
		if who ~= player or not purchased then
			return
		end
		boughtPasses[passId] = true
		for _, product in Monetization.GamePasses do
			if product.Id == passId then
				W.Toast(Controllers, "Thanks! " .. product.Name .. " unlocked.", "gold", 4)
			end
		end
		render()
	end)

	local data = controllers.DataController
	if data and data.Changed then
		data.Changed:Connect(function(key: string)
			if key == "Derived" or key == "Term" or key == "StarterPack" then
				render()
			end
		end)
	end
	return window
end

function Store.Open(_window: Kit.Window, data: any?)
	if type(data) == "table" and (data.Tab == "Passes" or data.Tab == "Tokens" or data.Tab == "Term Pass") then
		currentTab = data.Tab
		tabs.Select(data.Tab)
	end
	task.defer(render)
end

return Store
