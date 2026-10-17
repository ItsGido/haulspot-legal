--!strict
-- Character creator at the Nurse's Office mirror (blueprint section 5.11). Opened by the server with
-- { FreeHeight, HeightCm, Appearance, Cost, CooldownRemaining, HairColors, Options }.
-- Height slider (157-193 cm) with live HP / Speed / Reach, Face / Hair / Hair Color pickers as
-- numbered swatches, and Save (Creator_Save). Height changes cost yen once per 24 h unless free.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local UITheme = require(ReplicatedStorage.Shared.Config.UITheme)
local HeightStats = require(ReplicatedStorage.Shared.Logic.HeightStats)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local Net = require(ReplicatedStorage.Shared.Util.Net)
local Kit = require(script.Parent.Parent.Kit)

local Creator = {}
Creator.Name = "Creator"

local DEFAULT_OPTIONS = 12
local SWATCH_COLUMNS = 6
local DEFAULT_SWATCH = "#3B3E48"
local PICKERS = { { Key = "Face", Title = "FACE" }, { Key = "Hair", Title = "HAIR" }, { Key = "HairColor", Title = "HAIR COLOR" } }

local Controllers: any
local heightLabel: TextLabel
local statsLabel: TextLabel
local costLabel: TextLabel
local statusLabel: TextLabel
local track: TextButton
local fill: Frame
local knob: Frame
local saveButton: TextButton
local swatchFolders: { [string]: Frame } = {}

local originalHeight = HeightStats.DefaultCm
local selectedHeight = HeightStats.DefaultCm
local selection: { [string]: number } = { Face = 1, Hair = 1, HairColor = 1 }
local freeHeight = false
local cooldownEnds = 0
local cost = Economy.HeightChangeCost
local hairColors: { string } = {}
local optionCount = DEFAULT_OPTIONS
local dragging = false
local busy = false

local function setStatus(text: string, good: boolean?)
	statusLabel.Text = text
	statusLabel.TextColor3 = Kit.Hex(if good == true then UITheme.Buttons.Success[1] elseif good == false then UITheme.Buttons.Primary[1] else UITheme.Muted)
end

local function updateHeight()
	local cm = selectedHeight
	local stats = HeightStats.Get(cm)
	local t = (cm - HeightStats.MinCm) / (HeightStats.MaxCm - HeightStats.MinCm)
	heightLabel.Text = HeightStats.Describe(cm)
	statsLabel.Text = string.format("HP %d   ·   Speed %.1f   ·   Reach %.2f×", stats.HP, stats.WalkSpeed, stats.Reach)
	fill.Size = UDim2.fromScale(t, 1)
	knob.Position = UDim2.fromScale(t, 0.5)

	local changed = cm ~= originalHeight
	local remaining = cooldownEnds - os.clock()
	if not changed then
		costLabel.Text = "Current height"
		costLabel.TextColor3 = Kit.Hex(UITheme.Muted)
	elseif freeHeight then
		costLabel.Text = "FREE height change (first time)"
		costLabel.TextColor3 = Kit.Hex(UITheme.Buttons.Success[1])
	elseif remaining > 0 then
		costLabel.Text = "Height locked for " .. Format.Duration(remaining)
		costLabel.TextColor3 = Kit.Hex(UITheme.Buttons.Primary[1])
	else
		costLabel.Text = "Costs " .. Format.Yen(cost) .. " · once per 24 h"
		costLabel.TextColor3 = Kit.Hex(UITheme.Gold)
	end
end

local function setHeightFromX(x: number)
	local left = track.AbsolutePosition.X
	local width = math.max(1, track.AbsoluteSize.X)
	local t = math.clamp((x - left) / width, 0, 1)
	selectedHeight = HeightStats.Clamp(HeightStats.MinCm + t * (HeightStats.MaxCm - HeightStats.MinCm))
	updateHeight()
end

local function refreshSwatches()
	for key, folder in swatchFolders do
		for _, child in folder:GetChildren() do
			if child:IsA("TextButton") then
				local number = child:GetAttribute("Option")
				local stroke = child:FindFirstChildOfClass("UIStroke")
				local selected = number == selection[key]
				if stroke then
					stroke.Color = Kit.Hex(if selected then UITheme.Gold else UITheme.PanelStroke)
					stroke.Thickness = if selected then 4 else 2
				end
				if key == "HairColor" then
					child.BackgroundColor3 = Kit.Hex(hairColors[number :: number] or DEFAULT_SWATCH)
				end
			end
		end
	end
end

local function buildPicker(parent: Instance, key: string, title: string, y: number)
	Kit.Label(title .. "Title", parent, title, UDim2.fromScale(0, y), UDim2.fromScale(1, 0.07), "Title", UITheme.Paper, 28, Enum.TextXAlignment.Left)
	local holder = Kit.Frame(key .. "Swatches", parent, UDim2.fromScale(0, y + 0.08), UDim2.fromScale(1, 0.2))
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromScale(1 / SWATCH_COLUMNS - 0.02, 0.45)
	grid.CellPadding = UDim2.fromScale(0.02, 0.08)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = holder
	swatchFolders[key] = holder
end

local function rebuildSwatches()
	for key, holder in swatchFolders do
		Kit.ClearChildren(holder)
		for number = 1, optionCount do
			local button = Instance.new("TextButton")
			button.Name = "Option" .. number
			button.LayoutOrder = number
			button.AutoButtonColor = false
			button.BackgroundColor3 = Kit.Hex(UITheme.PanelLight)
			button.Text = tostring(number)
			button.Font = UITheme.Fonts.Number
			button.TextColor3 = Kit.Hex(UITheme.Paper)
			button.TextScaled = true
			button:SetAttribute("Option", number)
			Kit.TextLimit(button, 24)
			Kit.Corner(button, 0.2)
			Kit.InkStroke(button, 2)
			Kit.TextStroke(button, 1.5)
			Kit.Juice(button)
			button.Activated:Connect(function()
				selection[key] = number
				refreshSwatches()
			end)
			button.Parent = holder
		end
	end
	refreshSwatches()
end

local function save()
	if busy then
		return
	end
	local changes: { [string]: number } = {}
	local heightChanged = selectedHeight ~= originalHeight
	if heightChanged then
		if not freeHeight and cooldownEnds - os.clock() > 0 then
			setStatus("Your height is locked for " .. Format.Duration(cooldownEnds - os.clock()) .. ".", false)
			Kit.PlaySound("Error")
			return
		end
		changes.HeightCm = selectedHeight
	end
	for _, picker in PICKERS do
		changes[picker.Key] = selection[picker.Key]
	end
	busy = true
	setStatus("Saving...", nil)
	task.spawn(function()
		local ok, success, message = pcall(function()
			return Net.Function("Creator_Save"):InvokeServer(changes)
		end)
		busy = false
		if not ok then
			setStatus("Connection problem. Try again.", false)
			return
		end
		setStatus(tostring(message or ""), success == true)
		Kit.PlaySound(if success then "Purchase" else "Error")
		if success and heightChanged then
			originalHeight = selectedHeight
			local tutorialDone = Controllers and Controllers.DataController and Controllers.DataController.Get("TutorialDone")
			if tutorialDone ~= false then
				freeHeight = false
				cooldownEnds = os.clock() + Economy.HeightChangeCooldown
			end
			updateHeight()
		end
	end)
end

function Creator.Build(playerGui: Instance, controllers: any): Kit.Window
	Controllers = controllers
	local w = Kit.Window(playerGui, "Creator", "MIRROR, MIRROR", UDim2.fromScale(0.72, 0.78))
	Kit.Aspect(w.Root, 1.45)

	-- Height (left)
	local left = Kit.Frame("Height", w.Body, UDim2.fromScale(0, 0), UDim2.fromScale(0.47, 0.86))
	Kit.Label("HeightTitle", left, "HEIGHT", UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.07), "Title", UITheme.Paper, 28, Enum.TextXAlignment.Left)
	heightLabel = Kit.Label("Value", left, "", UDim2.fromScale(0, 0.1), UDim2.fromScale(1, 0.13), "Number", UITheme.Gold, 36)

	local minus = Kit.Button(left, "−", "Secondary", UDim2.fromScale(0, 0.3), UDim2.fromScale(0.13, 0.11), nil, true)
	Kit.Aspect(minus, 1)
	local plus = Kit.Button(left, "+", "Secondary", UDim2.fromScale(1, 0.3), UDim2.fromScale(0.13, 0.11), Vector2.new(1, 0), true)
	Kit.Aspect(plus, 1)
	minus.Activated:Connect(function()
		selectedHeight = HeightStats.Clamp(selectedHeight - 1)
		updateHeight()
	end)
	plus.Activated:Connect(function()
		selectedHeight = HeightStats.Clamp(selectedHeight + 1)
		updateHeight()
	end)

	local slider = Instance.new("TextButton")
	slider.Name = "Track"
	slider.Text = ""
	slider.AutoButtonColor = false
	slider.Position = UDim2.fromScale(0.18, 0.335)
	slider.Size = UDim2.fromScale(0.64, 0.04)
	slider.BackgroundColor3 = Kit.Hex(UITheme.PanelLight)
	slider.BorderSizePixel = 0
	Kit.Corner(slider, 1)
	Kit.InkStroke(slider, 2)
	slider.Parent = left
	track = slider
	fill = Kit.Frame("Fill", slider, UDim2.fromScale(0, 0), UDim2.fromScale(0.5, 1), UITheme.Buttons.Primary[1])
	Kit.Corner(fill, 1)
	knob = Kit.Frame("Knob", slider, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(2.2, 2.2), UITheme.Paper, Vector2.new(0.5, 0.5))
	knob.SizeConstraint = Enum.SizeConstraint.RelativeYY
	Kit.Corner(knob, 1)
	Kit.InkStroke(knob, 3)
	Kit.Label("Min", left, HeightStats.MinCm .. " cm", UDim2.fromScale(0.18, 0.39), UDim2.fromScale(0.25, 0.05), "Body", UITheme.Muted, 16, Enum.TextXAlignment.Left)
	Kit.Label("Max", left, HeightStats.MaxCm .. " cm", UDim2.fromScale(0.57, 0.39), UDim2.fromScale(0.25, 0.05), "Body", UITheme.Muted, 16, Enum.TextXAlignment.Right)

	slider.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setHeightFromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setHeightFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	local statsCard = Kit.Panel("Stats", left, UDim2.fromScale(0, 0.48), UDim2.fromScale(1, 0.2), nil, UITheme.PanelLight)
	statsLabel = Kit.Label("StatsText", statsCard, "", UDim2.fromScale(0.05, 0.1), UDim2.fromScale(0.9, 0.8), "BodyBold", UITheme.Paper, 22)
	costLabel = Kit.Label("Cost", left, "", UDim2.fromScale(0, 0.72), UDim2.fromScale(1, 0.08), "BodyBold", UITheme.Muted, 22)
	Kit.Label("Note", left, "Taller: more HP and reach. Shorter: faster.", UDim2.fromScale(0, 0.82), UDim2.fromScale(1, 0.08), "Body", UITheme.Muted, 18)

	-- Looks (right)
	local right = Kit.Frame("Looks", w.Body, UDim2.fromScale(0.53, 0), UDim2.fromScale(0.47, 0.86))
	for i, picker in PICKERS do
		buildPicker(right, picker.Key, picker.Title, (i - 1) * 0.31)
	end
	Kit.Label("LookNote", right, "Hair color 1 keeps your avatar's own hair.", UDim2.fromScale(0, 0.93), UDim2.fromScale(1, 0.06), "Body", UITheme.Muted, 16, Enum.TextXAlignment.Left)

	saveButton = Kit.Button(w.Body, "SAVE", "Primary", UDim2.fromScale(0.5, 0.88), UDim2.fromScale(0.3, 0.1), Vector2.new(0.5, 0))
	saveButton.Activated:Connect(save)
	statusLabel = Kit.Label("Status", w.Body, "", UDim2.fromScale(0, 0.88), UDim2.fromScale(0.33, 0.1), "BodyBold", UITheme.Muted, 18, Enum.TextXAlignment.Left)

	return w
end

function Creator.Open(_w: Kit.Window, data: any?)
	local info = if type(data) == "table" then data else {}
	local dataController = Controllers and Controllers.DataController
	local profileHeight = dataController and dataController.Get("HeightCm")
	local appearance = info.Appearance or (dataController and dataController.Get("Appearance")) or {}

	originalHeight = HeightStats.Clamp(tonumber(info.HeightCm) or tonumber(profileHeight) or HeightStats.DefaultCm)
	selectedHeight = originalHeight
	freeHeight = info.FreeHeight == true
	cost = tonumber(info.Cost) or Economy.HeightChangeCost
	cooldownEnds = os.clock() + (tonumber(info.CooldownRemaining) or 0)
	if type(info.HairColors) == "table" then
		hairColors = info.HairColors
	end
	local options = tonumber(info.Options) or DEFAULT_OPTIONS
	for _, picker in PICKERS do
		local value = tonumber(appearance[picker.Key])
		selection[picker.Key] = if value then math.clamp(math.floor(value), 1, options) else 1
	end
	optionCount = math.clamp(math.floor(options), 1, DEFAULT_OPTIONS * 2)
	rebuildSwatches()
	updateHeight()
	setStatus(if freeHeight then "Your first height change is free!" else "", if freeHeight then true else nil)
end

return Creator
