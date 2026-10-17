--!strict
-- Capsule Corner (blueprint sections 5.9 and 6.7). The odds table and pity counter are ALWAYS visible
-- (left sidebar, Roblox policy). Tabs: Roll (x1 yen, x1 token, x10 tokens, buy tokens with Robux,
-- shake -> pop reveal with a rarity-colored burst), Inventory (owned cosmetics by slot with Equip),
-- Point Shop (non-Mythic items for Capsule Points).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Capsules = require(ReplicatedStorage.Shared.Config.Capsules)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local UITheme = require(ReplicatedStorage.Shared.Config.UITheme)
local CapsuleRoll = require(ReplicatedStorage.Shared.Logic.CapsuleRoll)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local Net = require(ReplicatedStorage.Shared.Util.Net)
local Kit = require(script.Parent.Parent.Kit)

local Capsule = {}
Capsule.Name = "Capsule"

local SLOT_ORDER = { "Aura", "Title", "Armband", "Trail", "KOStamp" }
local SLOT_NAMES = { Aura = "AURA", Title = "TITLE", Armband = "ARMBAND", Trail = "TRAIL", KOStamp = "K.O. STAMP" }
local TABS = { "Roll", "Inventory", "Points" }
local TAB_LABELS = { Roll = "ROLL", Inventory = "INVENTORY", Points = "POINT SHOP" }
local SHAKE_STEPS = 8
local SHAKE_ANGLE = 14
local SHAKE_STEP_TIME = 0.06
local POP_TIME = 0.35
local ROW_SCALE = 0.13 -- list row height as a fraction of the list's height
local MIN_ROW_PX = 40

local Controllers: any
local window: Kit.Window? = nil
local currentTab = "Roll"
local busy = false
local revealing = false

local tabButtons: { [string]: TextButton } = {}
local pages: { [string]: Frame } = {}
local pityLabel: TextLabel
local walletLabel: TextLabel
local statusLabel: TextLabel
local capsuleBall: Frame
local capsuleScale: UIScale
local capsuleMark: TextLabel
local burst: Frame
local resultsFrame: Frame
local rollYenButton: TextButton
local rollTokenButton: TextButton
local rollTenButton: TextButton
local inventoryScroll: ScrollingFrame
local pointsScroll: ScrollingFrame

local rarityById: { [string]: any } = {}
for _, rarity in Capsules.Rarities do
	rarityById[rarity.Id] = rarity
end

local function getData(key: string): any
	if Controllers and Controllers.DataController then
		return Controllers.DataController.Get(key)
	end
	return nil
end

local function capsuleData(): any
	local data = getData("Capsule")
	return if type(data) == "table" then data else { PityEpic = 0, PityLegendary = 0, Points = 0, Tokens = 0 }
end

local function cosmeticsData(): any
	local data = getData("Cosmetics")
	return if type(data) == "table" then data else { Owned = {}, Equipped = {} }
end

local function rarityColor(rarity: string): string
	return (UITheme.Rarity :: any)[rarity] or (rarityById[rarity] and rarityById[rarity].Color) or UITheme.Paper
end

local function setStatus(text: string, good: boolean?)
	statusLabel.Text = text
	statusLabel.TextColor3 = Kit.Hex(if good == true then UITheme.Buttons.Success[1] elseif good == false then UITheme.Buttons.Primary[1] else UITheme.Muted)
end

local function rowHeight(scroll: ScrollingFrame): number
	return math.max(MIN_ROW_PX, scroll.AbsoluteSize.Y * ROW_SCALE)
end

-- Sidebar ------------------------------------------------------------------------------------

local function refreshSidebar()
	local data = capsuleData()
	local epicIn, legendaryIn = CapsuleRoll.RollsUntilGuarantee(Capsules, { PityEpic = data.PityEpic or 0, PityLegendary = data.PityLegendary or 0 })
	pityLabel.Text = string.format("Epic+ in <b>%d</b> · Legendary+ in <b>%d</b>", math.max(1, epicIn), math.max(1, legendaryIn))
	walletLabel.Text = string.format("🎟 Tokens: <b>%d</b>\n✦ Points: <b>%d</b>\n¥ %s", data.Tokens or 0, data.Points or 0, Format.Commas(getData("Yen") or 0))
end

local function buildSidebar(parent: Instance)
	local side = Kit.Panel("Odds", parent, UDim2.fromScale(0, 0), UDim2.fromScale(0.3, 1), nil, UITheme.PanelLight)
	Kit.Label("OddsTitle", side, "ODDS", UDim2.fromScale(0.06, 0.02), UDim2.fromScale(0.88, 0.08), "Title", UITheme.Paper, 32, Enum.TextXAlignment.Left)
	local totalWeight = 0
	for _, rarity in Capsules.Rarities do
		totalWeight += rarity.Weight
	end
	for i, rarity in Capsules.Rarities do
		local y = 0.11 + (i - 1) * 0.075
		local dot = Kit.Frame(rarity.Id .. "Dot", side, UDim2.fromScale(0.06, y + 0.015), UDim2.fromScale(0.08, 0.04), rarityColor(rarity.Id))
		Kit.Aspect(dot, 1)
		Kit.Corner(dot, 1)
		Kit.InkStroke(dot, 2)
		Kit.Label(rarity.Id, side, rarity.Id, UDim2.fromScale(0.17, y), UDim2.fromScale(0.45, 0.07), "BodyBold", rarityColor(rarity.Id), 20, Enum.TextXAlignment.Left)
		Kit.Label(rarity.Id .. "Odds", side, string.format("%.1f%%", rarity.Weight / totalWeight * 100), UDim2.fromScale(0.6, y), UDim2.fromScale(0.34, 0.07), "Number", UITheme.Paper, 20, Enum.TextXAlignment.Right)
	end
	local y = 0.11 + #Capsules.Rarities * 0.075 + 0.01
	Kit.Label("DupNote", side, "Duplicates turn into Capsule Points.", UDim2.fromScale(0.06, y), UDim2.fromScale(0.88, 0.07), "Body", UITheme.Muted, 16, Enum.TextXAlignment.Left)
	Kit.Label("PityTitle", side, "PITY", UDim2.fromScale(0.06, y + 0.09), UDim2.fromScale(0.88, 0.07), "Title", UITheme.Paper, 28, Enum.TextXAlignment.Left)
	pityLabel = Kit.Label("Pity", side, "", UDim2.fromScale(0.06, y + 0.16), UDim2.fromScale(0.88, 0.1), "BodyBold", UITheme.Gold, 20, Enum.TextXAlignment.Left)
	walletLabel = Kit.Label("Wallet", side, "", UDim2.fromScale(0.06, y + 0.28), UDim2.fromScale(0.88, 0.2), "BodyBold", UITheme.Paper, 20, Enum.TextXAlignment.Left)
	walletLabel.TextYAlignment = Enum.TextYAlignment.Top
end

-- Roll tab ----------------------------------------------------------------------------------

local function refreshRollButtons()
	local data = capsuleData()
	local yen = getData("Yen") or 0
	local tokens = data.Tokens or 0
	Kit.SetButtonStyle(rollYenButton, if yen >= Economy.CapsuleYenCost and not busy then "Primary" else "Disabled")
	Kit.SetButtonStyle(rollTokenButton, if tokens >= 1 and not busy then "Sakura" else "Disabled")
	Kit.SetButtonStyle(rollTenButton, if tokens >= 10 and not busy then "Premium" else "Disabled")
end

local function showResults(results: { any })
	Kit.ClearChildren(resultsFrame)
	for i, entry in results do
		local item = Capsules.ById(entry.ItemId)
		local color = rarityColor(entry.Rarity)
		local chip = Kit.Frame("Result" .. i, resultsFrame, UDim2.new(), UDim2.new(), UITheme.Panel)
		chip.LayoutOrder = i
		Kit.Corner(chip, 0.15)
		Kit.InkStroke(chip, 3, color)
		local text = (if item then item.Name else entry.ItemId)
		if entry.Duplicate then
			text ..= string.format('\n<font color="%s">DUP +%d pts</font>', UITheme.Muted, entry.Points or 0)
		else
			text ..= string.format('\n<font color="%s">NEW!</font>', UITheme.Gold)
		end
		Kit.Label("Name", chip, text, UDim2.fromScale(0.05, 0.05), UDim2.fromScale(0.9, 0.9), "BodyBold", color, 16)
	end
end

local function reveal(results: { any })
	revealing = true
	local best = "Common"
	for _, entry in results do
		if CapsuleRoll.RarityRank(entry.Rarity) > CapsuleRoll.RarityRank(best) then
			best = entry.Rarity
		end
	end
	Kit.ClearChildren(resultsFrame)
	capsuleMark.Text = "?"
	-- Shake
	for step = 1, SHAKE_STEPS do
		local angle = (if step % 2 == 0 then 1 else -1) * SHAKE_ANGLE * (step / SHAKE_STEPS)
		TweenService:Create(capsuleBall, TweenInfo.new(SHAKE_STEP_TIME), { Rotation = angle }):Play()
		task.wait(SHAKE_STEP_TIME)
	end
	capsuleBall.Rotation = 0
	-- Pop with a rarity burst
	local color = Kit.Hex(rarityColor(best))
	burst.BackgroundColor3 = color
	burst.BackgroundTransparency = 0.1
	burst.Size = UDim2.fromScale(0.2, 0.2)
	burst.Visible = true
	TweenService:Create(burst, TweenInfo.new(POP_TIME * 1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromScale(1.6, 1.6), BackgroundTransparency = 1 }):Play()
	capsuleScale.Scale = 1
	local pop = TweenService:Create(capsuleScale, TweenInfo.new(POP_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.25 })
	pop:Play()
	capsuleMark.Text = string.upper(best)
	capsuleMark.TextColor3 = color
	Kit.PlaySound("Purchase")
	task.wait(POP_TIME)
	TweenService:Create(capsuleScale, TweenInfo.new(0.2), { Scale = 1 }):Play()
	showResults(results)
	local newCount = 0
	for _, entry in results do
		if not entry.Duplicate then
			newCount += 1
		end
	end
	setStatus(string.format("%d new item%s! Equip them in the Inventory tab.", newCount, if newCount == 1 then "" else "s"), true)
	task.wait(POP_TIME)
	burst.Visible = false
	revealing = false
end

local function roll(count: number, currency: string)
	if busy or revealing then
		return
	end
	local data = capsuleData()
	if currency == "Yen" and (getData("Yen") or 0) < Economy.CapsuleYenCost then
		setStatus("You need " .. Format.Yen(Economy.CapsuleYenCost) .. ".", false)
		Kit.PlaySound("Error")
		return
	end
	if currency == "Token" and (data.Tokens or 0) < count then
		setStatus("Not enough tokens. Buy some below or earn them from daily logins.", false)
		Kit.PlaySound("Error")
		return
	end
	busy = true
	refreshRollButtons()
	setStatus("Rolling...", nil)
	task.spawn(function()
		local ok, success, results = pcall(function()
			return Net.Function("Capsule_Roll"):InvokeServer(count, currency)
		end)
		if not ok then
			busy = false
			refreshRollButtons()
			setStatus("Connection problem. Try again.", false)
			return
		end
		if success ~= true or type(results) ~= "table" then
			busy = false
			refreshRollButtons()
			setStatus(tostring(results or "Couldn't roll."), false)
			Kit.PlaySound("Error")
			return
		end
		reveal(results)
		busy = false
		refreshRollButtons()
		refreshSidebar()
	end)
end

local function buyTokens(key: string)
	local product = Monetization.DeveloperProducts[key]
	if not product or product.Id == 0 then
		setStatus("Coming soon!", nil)
		return
	end
	MarketplaceService:PromptProductPurchase(Players.LocalPlayer, product.Id)
end

local function buildRollPage(page: Frame)
	local machine = Kit.Frame("Machine", page, UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.4))
	burst = Kit.Frame("Burst", machine, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.2, 0.2), UITheme.Paper, Vector2.new(0.5, 0.5))
	burst.SizeConstraint = Enum.SizeConstraint.RelativeYY
	Kit.Corner(burst, 1)
	burst.Visible = false
	capsuleBall = Kit.Frame("Capsule", machine, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.85, 0.85), "#FFFFFF", Vector2.new(0.5, 0.5))
	capsuleBall.SizeConstraint = Enum.SizeConstraint.RelativeYY
	Kit.Corner(capsuleBall, 1)
	Kit.InkStroke(capsuleBall, 4)
	local split = Instance.new("UIGradient")
	split.Rotation = 90
	split.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Kit.Hex(UITheme.Buttons.Primary[1])),
		ColorSequenceKeypoint.new(0.49, Kit.Hex(UITheme.Buttons.Primary[2])),
		ColorSequenceKeypoint.new(0.5, Kit.Hex(UITheme.Ink)),
		ColorSequenceKeypoint.new(0.52, Kit.Hex(UITheme.Paper)),
		ColorSequenceKeypoint.new(1, Kit.Hex(UITheme.Muted)),
	})
	split.Parent = capsuleBall
	capsuleScale = Instance.new("UIScale")
	capsuleScale.Parent = capsuleBall
	capsuleMark = Kit.Label("Mark", capsuleBall, "?", UDim2.fromScale(0.1, 0.3), UDim2.fromScale(0.8, 0.4), "Title", UITheme.Paper, 48)

	resultsFrame = Kit.Frame("Results", page, UDim2.fromScale(0, 0.42), UDim2.fromScale(1, 0.25))
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromScale(0.19, 0.46)
	grid.CellPadding = UDim2.fromScale(0.0125, 0.06)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.Parent = resultsFrame

	rollYenButton = Kit.Button(page, "ROLL ×1  " .. Format.Yen(Economy.CapsuleYenCost), "Primary", UDim2.fromScale(0, 0.69), UDim2.fromScale(0.32, 0.14))
	rollTokenButton = Kit.Button(page, "ROLL ×1  🎟1", "Sakura", UDim2.fromScale(0.34, 0.69), UDim2.fromScale(0.32, 0.14))
	rollTenButton = Kit.Button(page, "ROLL ×10  🎟10", "Premium", UDim2.fromScale(0.68, 0.69), UDim2.fromScale(0.32, 0.14))
	rollYenButton.Activated:Connect(function()
		roll(1, "Yen")
	end)
	rollTokenButton.Activated:Connect(function()
		roll(1, "Token")
	end)
	rollTenButton.Activated:Connect(function()
		roll(10, "Token")
	end)

	for i, key in { "CapsuleToken1", "CapsuleToken10" } do
		local product = Monetization.DeveloperProducts[key]
		local enabled = product ~= nil and product.Id ~= 0
		local label = if not enabled then "COMING SOON" elseif key == "CapsuleToken1" then string.format("BUY 1 TOKEN · R$ %d", product.Price) else string.format("BUY 10 TOKENS · R$ %d", product.Price)
		local button = Kit.Button(page, label, if enabled then "Premium" else "Disabled", UDim2.fromScale((i - 1) * 0.51, 0.86), UDim2.fromScale(0.49, 0.13))
		button.Activated:Connect(function()
			buyTokens(key)
		end)
	end
end

-- Inventory tab -----------------------------------------------------------------------------

local function equip(slot: string, itemId: string?)
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local ok, success, message = pcall(function()
			return Net.Function("Capsule_Equip"):InvokeServer(slot, itemId)
		end)
		busy = false
		if not ok then
			setStatus("Connection problem. Try again.", false)
			return
		end
		setStatus(tostring(message or ""), success == true)
	end)
end

local function addRow(scroll: ScrollingFrame, order: number, item: Capsules.Cosmetic, rightText: string?, buttonText: string, style: string, onClick: () -> ())
	local row = Kit.Frame(item.Id, scroll, UDim2.new(), UDim2.new(1, -8, 0, rowHeight(scroll)), UITheme.PanelLight)
	row.LayoutOrder = order
	Kit.Corner(row, 0.15)
	Kit.InkStroke(row, 2)
	Kit.Label("Name", row, item.Name, UDim2.fromScale(0.03, 0.1), UDim2.fromScale(0.5, 0.8), "BodyBold", rarityColor(item.Rarity), 20, Enum.TextXAlignment.Left)
	if rightText then
		Kit.Label("Info", row, rightText, UDim2.fromScale(0.5, 0.1), UDim2.fromScale(0.22, 0.8), "Number", UITheme.Gold, 20, Enum.TextXAlignment.Right)
	end
	local button = Kit.Button(row, buttonText, style, UDim2.fromScale(0.97, 0.5), UDim2.fromScale(0.22, 0.8), Vector2.new(1, 0.5))
	button.Activated:Connect(onClick)
end

local function addHeader(scroll: ScrollingFrame, order: number, text: string)
	local header = Kit.Label("Header" .. order, scroll, text, UDim2.new(), UDim2.new(1, -8, 0, rowHeight(scroll) * 0.7), "Title", UITheme.Paper, 28, Enum.TextXAlignment.Left)
	header.LayoutOrder = order
end

local function renderInventory()
	Kit.ClearChildren(inventoryScroll)
	local cosmetics = cosmeticsData()
	local order = 0
	local any = false
	for _, slot in SLOT_ORDER do
		local owned = {}
		for _, item in Capsules.Pool do
			if item.Slot == slot and cosmetics.Owned[item.Id] then
				table.insert(owned, item)
			end
		end
		if #owned > 0 then
			any = true
			order += 1
			addHeader(inventoryScroll, order, SLOT_NAMES[slot] or slot)
			table.sort(owned, function(a, b)
				return CapsuleRoll.RarityRank(a.Rarity) > CapsuleRoll.RarityRank(b.Rarity)
			end)
			for _, item in owned do
				order += 1
				local equipped = cosmetics.Equipped[slot] == item.Id
				addRow(inventoryScroll, order, item, item.Rarity, if equipped then "UNEQUIP" else "EQUIP", if equipped then "Ghost" else "Success", function()
					equip(slot, if equipped then nil else item.Id)
				end)
			end
		end
	end
	if not any then
		local empty = Kit.Label("Empty", inventoryScroll, "No cosmetics yet. Roll a capsule!", UDim2.new(), UDim2.new(1, -8, 0, rowHeight(inventoryScroll)), "Body", UITheme.Muted, 22)
		empty.LayoutOrder = 1
	end
end

-- Point shop tab ---------------------------------------------------------------------------

local function buyWithPoints(item: Capsules.Cosmetic, price: number)
	if busy then
		return
	end
	if (capsuleData().Points or 0) < price then
		setStatus(string.format("Needs %d points.", price), false)
		Kit.PlaySound("Error")
		return
	end
	busy = true
	task.spawn(function()
		local ok, success, message = pcall(function()
			return Net.Function("Capsule_BuyWithPoints"):InvokeServer(item.Id)
		end)
		busy = false
		if not ok then
			setStatus("Connection problem. Try again.", false)
			return
		end
		setStatus(tostring(message or ""), success == true)
		Kit.PlaySound(if success then "Purchase" else "Error")
	end)
end

local function renderPoints()
	Kit.ClearChildren(pointsScroll)
	local cosmetics = cosmeticsData()
	local points = capsuleData().Points or 0
	local order = 0
	for _, slot in SLOT_ORDER do
		local items = {}
		for _, item in Capsules.Pool do
			local price = (Capsules.PointShopPrices :: any)[item.Rarity]
			if item.Slot == slot and item.Rarity ~= "Mythic" and type(price) == "number" then
				table.insert(items, item)
			end
		end
		if #items > 0 then
			order += 1
			addHeader(pointsScroll, order, SLOT_NAMES[slot] or slot)
			table.sort(items, function(a, b)
				return CapsuleRoll.RarityRank(a.Rarity) < CapsuleRoll.RarityRank(b.Rarity)
			end)
			for _, item in items do
				order += 1
				local price = (Capsules.PointShopPrices :: any)[item.Rarity] :: number
				local owned = cosmetics.Owned[item.Id] == true
				local style = if owned or points < price then "Disabled" else "Success"
				addRow(pointsScroll, order, item, price .. " pts", if owned then "OWNED" else "BUY", style, function()
					if owned then
						setStatus("You already own that.", nil)
					else
						buyWithPoints(item, price)
					end
				end)
			end
		end
	end
	order += 1
	local note = Kit.Label("MythicNote", pointsScroll, "Mythic items only come from capsules.", UDim2.new(), UDim2.new(1, -8, 0, rowHeight(pointsScroll) * 0.6), "Body", UITheme.Muted, 18)
	note.LayoutOrder = order
end

-- Tabs ----------------------------------------------------------------------------------------

local function renderCurrent()
	refreshSidebar()
	if currentTab == "Roll" then
		refreshRollButtons()
	elseif currentTab == "Inventory" then
		renderInventory()
	elseif currentTab == "Points" then
		renderPoints()
	end
end

local function selectTab(tab: string)
	currentTab = tab
	for name, button in tabButtons do
		Kit.SetButtonStyle(button, if name == tab then "Primary" else "Ghost")
	end
	for name, page in pages do
		page.Visible = name == tab
	end
	renderCurrent()
end

local function makeListPage(parent: Instance, name: string): (Frame, ScrollingFrame)
	local page = Kit.Frame(name, parent, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1))
	local scroll = Kit.Scroll("List", page, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1))
	Kit.List(scroll, 0.01)
	local layout = scroll:FindFirstChildOfClass("UIListLayout")
	if layout then
		layout.Padding = UDim.new(0, 6)
	end
	return page, scroll
end

function Capsule.Build(playerGui: Instance, controllers: any): Kit.Window
	Controllers = controllers
	local w = Kit.Window(playerGui, "Capsule", "CAPSULE CORNER", UDim2.fromScale(0.82, 0.84))
	window = w
	Kit.Aspect(w.Root, 1.5)

	buildSidebar(w.Body)
	local right = Kit.Frame("Main", w.Body, UDim2.fromScale(0.32, 0), UDim2.fromScale(0.68, 1))
	for i, tab in TABS do
		local button = Kit.Button(right, TAB_LABELS[tab], if tab == currentTab then "Primary" else "Ghost", UDim2.fromScale((i - 1) * 0.34, 0), UDim2.fromScale(0.32, 0.08))
		button.Activated:Connect(function()
			selectTab(tab)
		end)
		tabButtons[tab] = button
	end
	local container = Kit.Frame("Pages", right, UDim2.fromScale(0, 0.1), UDim2.fromScale(1, 0.83))
	local rollPage = Kit.Frame("Roll", container, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1))
	buildRollPage(rollPage)
	pages.Roll = rollPage
	local inventoryPage, inventoryList = makeListPage(container, "Inventory")
	pages.Inventory, inventoryScroll = inventoryPage, inventoryList
	local pointsPage, pointsList = makeListPage(container, "Points")
	pages.Points, pointsScroll = pointsPage, pointsList
	statusLabel = Kit.Label("Status", right, "", UDim2.fromScale(0, 0.94), UDim2.fromScale(1, 0.06), "BodyBold", UITheme.Muted, 20)

	local function refreshIfOpen()
		if w.Gui.Enabled and not revealing then
			renderCurrent()
		end
	end
	if controllers and controllers.DataController then
		for _, key in { "Capsule", "Cosmetics", "Yen" } do
			controllers.DataController.Observe(key, refreshIfOpen)
		end
	end
	return w
end

function Capsule.Open(_w: Kit.Window, data: any?)
	if type(data) == "table" and type(data.Tab) == "string" and table.find(TABS, data.Tab) then
		selectTab(data.Tab)
	else
		selectTab(currentTab)
	end
	local _ = window
end

return Capsule
