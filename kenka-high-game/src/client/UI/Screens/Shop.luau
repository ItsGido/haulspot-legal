--!strict
-- Shotengai shop window (blueprint section 3 Z11). Opened by the server with { ShopId, Name? }.
-- A grid of item cards: name, description, price (Morning food discount shown), and a Buy button
-- that turns Disabled with the reason when the player can't afford it or is rank-locked.
-- Uniform cards show Equip / Wearing once owned. Refreshes on yen and ownership changes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local MapData = require(ReplicatedStorage.Shared.Map.MapData)
local UITheme = require(ReplicatedStorage.Shared.Config.UITheme)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local Net = require(ReplicatedStorage.Shared.Util.Net)
local Kit = require(script.Parent.Parent.Kit)

local Shop = {}
Shop.Name = "Shop"

local CARD_COLUMNS = 3
local CARD_ASPECT = 0.82 -- width / height
local CARD_GAP = 0.02

local Controllers: any
local window: Kit.Window? = nil
local scroll: ScrollingFrame
local grid: UIGridLayout
local yenLabel: TextLabel
local saleLabel: TextLabel
local statusLabel: TextLabel
local currentShop: string? = nil
local busy = false

local function isMorning(): boolean
	return ReplicatedStorage:GetAttribute("PeriodId") == "Morning"
end

local function priceOf(item: Economy.ShopItem): number
	if item.Category == "Food" and isMorning() then
		return math.floor(item.Price * (1 - Economy.MorningFoodDiscount) + 0.5)
	end
	return item.Price
end

local function getData(key: string): any
	if Controllers and Controllers.DataController then
		return Controllers.DataController.Get(key)
	end
	return nil
end

local function myRank(): number
	local rank = getData("Rank")
	if type(rank) ~= "number" then
		rank = Players.LocalPlayer:GetAttribute("Rank")
	end
	return if type(rank) == "number" then rank else 1
end

local function setStatus(text: string, good: boolean?)
	statusLabel.Text = text
	statusLabel.TextColor3 = Kit.Hex(if good == true then UITheme.Buttons.Success[1] elseif good == false then UITheme.Buttons.Primary[1] else UITheme.Muted)
end

local function itemsFor(shopId: string): { Economy.ShopItem }
	local list = {}
	for _, item in Economy.Items do
		if item.Shop == shopId then
			table.insert(list, item)
		end
	end
	table.sort(list, function(a, b)
		if a.Price == b.Price then
			return a.Name < b.Name
		end
		return a.Price < b.Price
	end)
	return list
end

-- What the card's button should say and do. Returns text, style, action ("Buy" | "Equip" | nil), reason?
local function buttonState(item: Economy.ShopItem): (string, string, string?, string?)
	local yen = getData("Yen") or 0
	if item.Category == "Uniform" then
		local owned = getData("OwnedUniforms") or {}
		if owned[item.Id] then
			if getData("Uniform") == item.Id then
				return "WEARING", "Disabled", nil, "You're already wearing this."
			end
			return "EQUIP", "Secondary", "Equip", nil
		end
	elseif item.Category == "Vehicle" then
		local vehicles = getData("Vehicles") or {}
		if item.Vehicle and vehicles[item.Vehicle] then
			return "OWNED", "Disabled", nil, "You already own this. Press B to ride."
		end
	end
	local minRank = item.MinRank or 1
	if myRank() < minRank then
		return "RANK " .. minRank, "Disabled", nil, "Reach Rank " .. minRank .. " to buy this."
	end
	local price = priceOf(item)
	if yen < price then
		return "NEED " .. Format.Yen(price - yen), "Disabled", nil, "Not enough yen."
	end
	return "BUY", "Success", "Buy", nil
end

local function priceText(item: Economy.ShopItem): string
	local price = priceOf(item)
	if price == 0 then
		return "FREE"
	end
	if price ~= item.Price then
		return string.format('<s><font color="%s">%s</font></s>  %s', UITheme.Muted, Format.Yen(item.Price), Format.Yen(price))
	end
	return Format.Yen(price)
end

local render: () -> ()

local function act(item: Economy.ShopItem, action: string?, reason: string?)
	if busy then
		return
	end
	if not action then
		setStatus(reason or "Unavailable.", false)
		Kit.PlaySound("Error")
		return
	end
	local shopId = currentShop
	if not shopId then
		return
	end
	busy = true
	setStatus("...", nil)
	task.spawn(function()
		local ok, success, message = pcall(function()
			if action == "Equip" then
				return Net.Function("Shop_EquipUniform"):InvokeServer(item.Id)
			end
			return Net.Function("Shop_Buy"):InvokeServer(shopId, item.Id)
		end)
		busy = false
		if not ok then
			setStatus("Connection problem. Try again.", false)
			return
		end
		setStatus(tostring(message or ""), success == true)
		Kit.PlaySound(if success then "Purchase" else "Error")
		render()
	end)
end

local function makeCard(item: Economy.ShopItem, order: number)
	local card = Kit.Panel(item.Id, scroll, UDim2.new(), UDim2.new(), nil, UITheme.PanelLight)
	card.LayoutOrder = order
	Kit.Label("Name", card, item.Name, UDim2.fromScale(0.07, 0.05), UDim2.fromScale(0.86, 0.15), "BodyBold", UITheme.Paper, 24, Enum.TextXAlignment.Left)
	Kit.Label("Category", card, string.upper(item.Category) .. (if item.MinRank then "  ·  RANK " .. item.MinRank .. "+" else ""), UDim2.fromScale(0.07, 0.2), UDim2.fromScale(0.86, 0.08), "BodyBold", UITheme.Muted, 14, Enum.TextXAlignment.Left)
	Kit.Label("Description", card, item.Description, UDim2.fromScale(0.07, 0.3), UDim2.fromScale(0.86, 0.24), "Body", UITheme.Muted, 18, Enum.TextXAlignment.Left)
	Kit.Label("Price", card, priceText(item), UDim2.fromScale(0.07, 0.56), UDim2.fromScale(0.86, 0.15), "Number", UITheme.Gold, 28, Enum.TextXAlignment.Left)
	if item.UniformColor then
		local swatch = Kit.Frame("Swatch", card, UDim2.fromScale(0.93, 0.06), UDim2.fromScale(0.16, 0.16), item.UniformColor, Vector2.new(1, 0))
		Kit.Aspect(swatch, 1)
		Kit.Corner(swatch, 1)
		Kit.InkStroke(swatch, 2)
	end
	local text, style, action, reason = buttonState(item)
	local button = Kit.Button(card, text, style, UDim2.fromScale(0.07, 0.74), UDim2.fromScale(0.86, 0.21))
	button.Activated:Connect(function()
		act(item, action, reason)
	end)
end

render = function()
	local w = window
	local shopId = currentShop
	if not w or not shopId then
		return
	end
	local yen = getData("Yen") or 0
	yenLabel.Text = "Your yen: " .. Format.Yen(yen)
	saleLabel.Visible = isMorning()
	Kit.ClearChildren(scroll)
	local items = itemsFor(shopId)
	for index, item in items do
		makeCard(item, index)
	end
	if #items == 0 then
		local empty = Kit.Label("Empty", scroll, "Sold out. Come back later!", UDim2.new(), UDim2.new(), "Body", UITheme.Muted)
		empty.LayoutOrder = 1
	end
end

local function resizeGrid()
	local width = scroll.AbsoluteSize.X
	if width <= 0 then
		return
	end
	local gap = width * CARD_GAP
	local cellWidth = (width - gap * (CARD_COLUMNS - 1) - scroll.ScrollBarThickness) / CARD_COLUMNS
	grid.CellPadding = UDim2.fromOffset(gap, gap)
	grid.CellSize = UDim2.fromOffset(cellWidth, cellWidth / CARD_ASPECT)
end

function Shop.Build(playerGui: Instance, controllers: any): Kit.Window
	Controllers = controllers
	local w = Kit.Window(playerGui, "Shop", "SHOP", UDim2.fromScale(0.72, 0.78))
	window = w
	Kit.Aspect(w.Root, 1.45)

	yenLabel = Kit.Label("Yen", w.Body, "", UDim2.fromScale(0, 0), UDim2.fromScale(0.5, 0.07), "Number", UITheme.Gold, 28, Enum.TextXAlignment.Left)
	saleLabel = Kit.Label("Sale", w.Body, string.format("☀ Morning sale: food %d%% off", math.floor(Economy.MorningFoodDiscount * 100 + 0.5)), UDim2.fromScale(0.5, 0), UDim2.fromScale(0.5, 0.07), "BodyBold", UITheme.Sakura, 22, Enum.TextXAlignment.Right)
	scroll = Kit.Scroll("Items", w.Body, UDim2.fromScale(0, 0.09), UDim2.fromScale(1, 0.83))
	grid = Instance.new("UIGridLayout")
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.FillDirectionMaxCells = CARD_COLUMNS
	grid.Parent = scroll
	scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(resizeGrid)
	resizeGrid()
	statusLabel = Kit.Label("Status", w.Body, "", UDim2.fromScale(0, 0.93), UDim2.fromScale(1, 0.07), "BodyBold", UITheme.Muted, 20)

	local function refreshIfOpen()
		if w.Gui.Enabled and currentShop then
			render()
		end
	end
	if controllers and controllers.DataController then
		for _, key in { "Yen", "Rank", "OwnedUniforms", "Uniform", "Vehicles" } do
			controllers.DataController.Observe(key, refreshIfOpen)
		end
	end
	ReplicatedStorage:GetAttributeChangedSignal("PeriodId"):Connect(refreshIfOpen)
	return w
end

function Shop.Open(w: Kit.Window, data: any?)
	if type(data) == "table" and type(data.ShopId) == "string" then
		currentShop = data.ShopId
		local name = data.Name
		if type(name) ~= "string" then
			local entry = MapData.GetInteractable(data.ShopId)
			name = if entry then entry.Object else data.ShopId
		end
		w.Title.Text = string.upper(name)
		setStatus("", nil)
	end
	task.defer(resizeGrid)
	render()
end

function Shop.Close(_w: Kit.Window)
	busy = false
end

return Shop
