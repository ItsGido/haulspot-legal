--!strict
-- YenPay: send yen to another player in the server (Rank 3+, daily limit). The server re-checks everything.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Util.Net)
local UITheme = require(ReplicatedStorage.Shared.Config.UITheme)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Ranks = require(ReplicatedStorage.Shared.Config.Ranks)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local Kit = require(script.Parent.Parent.Kit)
local W = require(script.Parent.Parent.HudWidgets)

local YenPay = {}
YenPay.Name = "YenPay"

local player = Players.LocalPlayer
local Controllers: any
local windowRef: Kit.Window? = nil
local selectedId: number? = nil
local busy = false

local scroll: ScrollingFrame = nil :: any
local emptyNote: TextLabel = nil :: any
local targetLabel: TextLabel = nil :: any
local amountBox: TextBox = nil :: any
local sendButton: TextButton = nil :: any
local limitLabel: TextLabel = nil :: any
local reasonLabel: TextLabel = nil :: any

local function getData(key: string): any
	local data = Controllers and Controllers.DataController
	return if data and data.Get then data.Get(key) else nil
end

local function remainingToday(): number
	local yp = getData("YenPay")
	local sent = 0
	if type(yp) == "table" and yp.Day == W.UtcToday() and type(yp.Sent) == "number" then
		sent = yp.Sent
	end
	return math.max(0, Economy.YenPayDailyLimit - sent)
end

local function balance(): number
	local yen = player:GetAttribute("Yen")
	if type(yen) == "number" then
		return yen
	end
	local fromData = getData("Yen")
	return if type(fromData) == "number" then fromData else 0
end

local function amount(): number
	return tonumber(amountBox.Text) or 0
end

local function refreshForm()
	local rank = W.LocalRank()
	local remaining = remainingToday()
	limitLabel.Text = string.format("Today's limit left: %s  ·  Balance: %s", Format.Yen(remaining), Format.Yen(balance()))
	local target = if selectedId then Players:GetPlayerByUserId(selectedId) else nil
	if selectedId and not target then
		selectedId = nil
	end
	targetLabel.Text = if target then "To: " .. W.Escape(target.DisplayName) .. W.Colored(" @" .. target.Name, UITheme.Muted) else "Pick a player on the left"
	local reason: string? = nil
	if rank < Economy.YenPayMinRank then
		reason = string.format("YenPay unlocks at Rank %d (%s).", Economy.YenPayMinRank, Ranks.List[Economy.YenPayMinRank].Title)
	elseif remaining <= 0 then
		reason = "You've hit today's limit. It resets at 00:00 UTC."
	elseif not target then
		reason = nil
	elseif amount() <= 0 then
		reason = nil
	elseif amount() > remaining then
		reason = "That's over today's limit."
	elseif amount() > balance() then
		reason = "You don't have that much yen."
	end
	reasonLabel.Text = reason or ""
	local canSend = reason == nil and target ~= nil and amount() > 0 and not busy
	W.SetEnabled(sendButton, canSend, "Success")
	amountBox.TextEditable = rank >= Economy.YenPayMinRank
end

local function refreshList()
	Kit.ClearChildren(scroll)
	local others = {}
	for _, other in Players:GetPlayers() do
		if other ~= player then
			table.insert(others, other)
		end
	end
	table.sort(others, function(a, b)
		return a.DisplayName:lower() < b.DisplayName:lower()
	end)
	emptyNote.Visible = #others == 0
	local rowHeight = W.ScrollRows(scroll, #others, 0.13, 0.015)
	for i, other in others do
		local isSelected = other.UserId == selectedId
		local rank = other:GetAttribute("Rank")
		local info = W.RankInfo(rank)
		local row = Kit.Button(scroll, "", if isSelected then "Secondary" else "Ghost", UDim2.new(), UDim2.fromScale(0.97, rowHeight))
		row.Name = "Player_" .. other.UserId
		row.LayoutOrder = i
		local dot = Kit.Frame("Rank", row, UDim2.fromScale(0, 0.5), UDim2.fromScale(0.12, 0.9), info.Color, Vector2.new(0, 0.5))
		Kit.Corner(dot, 1)
		Kit.Aspect(dot, 1, true)
		Kit.InkStroke(dot, 2)
		Kit.Label("Number", dot, tostring(if type(rank) == "number" then rank else 1), UDim2.fromScale(0.15, 0.15), UDim2.fromScale(0.7, 0.7), "Title", UITheme.Ink, 20)
		Kit.Label("Name", row, W.Escape(other.DisplayName), UDim2.fromScale(0.18, 0), UDim2.fromScale(0.8, 0.6), "BodyBold", UITheme.Paper, 20, Enum.TextXAlignment.Left)
		Kit.Label("Title", row, W.Escape(info.Title), UDim2.fromScale(0.18, 0.58), UDim2.fromScale(0.8, 0.42), "Body", UITheme.Muted, 16, Enum.TextXAlignment.Left)
		local id = other.UserId
		row.Activated:Connect(function()
			selectedId = id
			refreshList()
			refreshForm()
		end)
	end
end

local function send()
	local window = windowRef
	if busy or not window or not W.IsEnabled(sendButton) then
		return
	end
	local target = if selectedId then Players:GetPlayerByUserId(selectedId) else nil
	local value = math.floor(amount())
	if not target or value <= 0 then
		return
	end
	busy = true
	refreshForm()
	local ok, message = W.Invoke(Net.Function("YenPay_Send"), target.UserId, value)
	busy = false
	if ok then
		Kit.PlaySound("Purchase")
		amountBox.Text = ""
		W.Toast(Controllers, if type(message) == "string" and message ~= "" then message else string.format("Sent %s to %s.", Format.Yen(value), target.DisplayName), "good")
	else
		W.Toast(Controllers, if type(message) == "string" then message else "Payment failed.", "bad")
	end
	refreshForm()
end

function YenPay.Build(playerGui: Instance, controllers: any): Kit.Window
	Controllers = controllers
	local window = Kit.Window(playerGui, "YenPay", "YENPAY", UDim2.fromScale(0.62, 0.74))
	W.ShapeWindow(window, 1.5)
	windowRef = window
	local body = window.Body

	Kit.Label("ListTitle", body, "PLAYERS IN THIS SERVER", UDim2.fromScale(0, 0), UDim2.fromScale(0.45, 0.08), "Title", UITheme.Paper, 26, Enum.TextXAlignment.Left)
	scroll = Kit.Scroll("Players", body, UDim2.fromScale(0, 0.1), UDim2.fromScale(0.45, 0.9))
	Kit.List(scroll, 0.015)
	emptyNote = W.Note(body, "Empty", "Nobody else is here yet.", UDim2.fromScale(0, 0.2), UDim2.fromScale(0.45, 0.1))

	local form = Kit.Panel("Form", body, UDim2.fromScale(0.48, 0), UDim2.fromScale(0.52, 1), nil, UITheme.PanelLight)
	local fc = form:FindFirstChildOfClass("UICorner")
	if fc then
		fc.CornerRadius = UDim.new(0.04, 0)
	end
	targetLabel = Kit.Label("Target", form, "", UDim2.fromScale(0.06, 0.04), UDim2.fromScale(0.88, 0.1), "BodyBold", UITheme.Paper, 24, Enum.TextXAlignment.Left)

	amountBox = Instance.new("TextBox")
	amountBox.Name = "Amount"
	amountBox.Position = UDim2.fromScale(0.06, 0.18)
	amountBox.Size = UDim2.fromScale(0.88, 0.16)
	amountBox.BackgroundColor3 = Kit.Hex(UITheme.Ink)
	amountBox.TextColor3 = Kit.Hex(UITheme.Gold)
	amountBox.PlaceholderText = "¥ amount"
	amountBox.PlaceholderColor3 = Kit.Hex(UITheme.Muted)
	amountBox.Font = UITheme.Fonts.Number
	amountBox.TextScaled = true
	amountBox.ClearTextOnFocus = false
	amountBox.Text = ""
	amountBox.Parent = form
	Kit.Corner(amountBox, 0.2)
	Kit.InkStroke(amountBox, 3)
	Kit.TextLimit(amountBox, 36)
	Kit.Padding(amountBox, 0.04)
	amountBox:GetPropertyChangedSignal("Text"):Connect(function()
		local digits = amountBox.Text:gsub("%D", ""):sub(1, 7)
		if digits ~= amountBox.Text then
			amountBox.Text = digits
		end
		refreshForm()
	end)

	local quick = Kit.Frame("Quick", form, UDim2.fromScale(0.06, 0.38), UDim2.fromScale(0.88, 0.11))
	local quickList = Kit.List(quick, 0.03, true)
	quickList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	for i, step in { 100, 500, 1000, 5000 } do
		local b = Kit.Button(quick, "+" .. Format.Commas(step), "Ghost", UDim2.new(), UDim2.fromScale(0.22, 1))
		b.LayoutOrder = i
		b.Activated:Connect(function()
			if amountBox.TextEditable then
				amountBox.Text = tostring(math.min(9999999, amount() + step))
			end
		end)
	end

	sendButton = Kit.Button(form, "SEND", "Success", UDim2.fromScale(0.06, 0.55), UDim2.fromScale(0.88, 0.15))
	sendButton.Activated:Connect(send)
	limitLabel = Kit.Label("Limit", form, "", UDim2.fromScale(0.06, 0.74), UDim2.fromScale(0.88, 0.08), "BodyBold", UITheme.Paper, 18)
	reasonLabel = Kit.Label("Reason", form, "", UDim2.fromScale(0.06, 0.84), UDim2.fromScale(0.88, 0.12), "BodyBold", UITheme.Bars.HP, 20)

	Players.PlayerAdded:Connect(function()
		if window.Gui.Enabled then
			refreshList()
		end
	end)
	Players.PlayerRemoving:Connect(function()
		if window.Gui.Enabled then
			task.defer(function()
				refreshList()
				refreshForm()
			end)
		end
	end)
	player:GetAttributeChangedSignal("Yen"):Connect(function()
		if window.Gui.Enabled then
			refreshForm()
		end
	end)
	local data = controllers.DataController
	if data and data.Changed then
		data.Changed:Connect(function(key: string)
			if (key == "YenPay" or key == "Rank") and window.Gui.Enabled then
				refreshForm()
			end
		end)
	end
	return window
end

function YenPay.Open(_window: Kit.Window, data: any?)
	if type(data) == "table" and type(data.UserId) == "number" then
		selectedId = data.UserId
	end
	refreshList()
	refreshForm()
end

return YenPay
