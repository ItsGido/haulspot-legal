--!strict
-- Overhead name tags on every player character (blueprint 5.1 / 1.10).
--   line 1: display name (the profile CustomName if set, after filtering)
--   line 2: rank title in the rank color
--   line 3: "[emblem] Crew Name" in the crew color (hidden without a crew)
--   line 4: cosmetic title in italics (TitleText, hidden if none)
--   a green ROOKIE pill when RookieProtected, a gold crown when Crown
-- Rebuilt on CharacterAdded, updated whenever one of the watched player attributes changes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Ranks = require(ReplicatedStorage.Shared.Config.Ranks)
local UITheme = require(ReplicatedStorage.Shared.Config.UITheme)

local NameTagService = {}
NameTagService.Priority = 60

local MAX_DISTANCE = 120
local HEAD_OFFSET = 3.4 -- studs above the head center
local CUSTOM_NAME_POLL = 10 -- seconds between CustomName checks (it lives in the profile, not an attribute)
local ROOKIE_COLOR = "#3BC46B"

local WATCHED = {
	RankTitle = true,
	Rank = true,
	CrewName = true,
	CrewColor = true,
	CrewEmblem = true,
	TitleText = true,
	RookieProtected = true,
	Crown = true,
}

type Tag = {
	Gui: BillboardGui,
	Crown: TextLabel,
	Name: TextLabel,
	Rank: TextLabel,
	Crew: TextLabel,
	Title: TextLabel,
	Rookie: Frame,
}

local Services: any
local tags: { [Player]: Tag } = {}
local customNames: { [Player]: { Raw: string, Shown: string? } } = {}

local function safeColor(hex: any, fallback: string): Color3
	if type(hex) == "string" then
		local ok, color = pcall(Color3.fromHex, hex)
		if ok then
			return color
		end
	end
	return Color3.fromHex(fallback)
end

local function line(parent: Instance, name: string, order: number, height: number, font: Enum.Font, color: string): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.LayoutOrder = order
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, height)
	label.Font = font
	label.TextScaled = true
	label.TextColor3 = Color3.fromHex(color)
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.fromHex(UITheme.Ink)
	label.Text = ""
	label.Parent = parent
	return label
end

local function displayName(player: Player): string
	local custom = customNames[player]
	if custom and custom.Shown then
		return custom.Shown
	end
	return player.DisplayName
end

local function refresh(player: Player)
	local tag = tags[player]
	if not tag then
		return
	end
	tag.Name.Text = displayName(player)

	local rank = player:GetAttribute("Rank")
	local rankNumber = if type(rank) == "number" then rank else 1
	local entry = Ranks.List[rankNumber] or Ranks.List[1]
	local rankTitle = player:GetAttribute("RankTitle")
	tag.Rank.Text = if type(rankTitle) == "string" and rankTitle ~= "" then rankTitle else entry.Title
	tag.Rank.TextColor3 = Color3.fromHex(entry.Color)

	local crewName = player:GetAttribute("CrewName")
	if type(crewName) == "string" and crewName ~= "" then
		local emblem = player:GetAttribute("CrewEmblem")
		tag.Crew.Text = (if type(emblem) == "string" and emblem ~= "" then "[" .. emblem .. "] " else "") .. crewName
		tag.Crew.TextColor3 = safeColor(player:GetAttribute("CrewColor"), UITheme.Sakura)
		tag.Crew.Visible = true
	else
		tag.Crew.Visible = false
	end

	local title = player:GetAttribute("TitleText")
	if type(title) == "string" and title ~= "" then
		tag.Title.Text = "<i>" .. (title:gsub("[<>&]", "")) .. "</i>"
		tag.Title.Visible = true
	else
		tag.Title.Visible = false
	end

	tag.Rookie.Visible = player:GetAttribute("RookieProtected") == true
	tag.Crown.Visible = player:GetAttribute("Crown") == true
end

local function build(player: Player, character: Model)
	local head = character:WaitForChild("Head", 10)
	if not head or not head:IsA("BasePart") or character.Parent == nil or player.Character ~= character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	local old = tags[player]
	if old then
		old.Gui:Destroy()
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "NameTag"
	gui.Adornee = head
	gui.Size = UDim2.new(7, 0, 3.6, 0)
	gui.StudsOffset = Vector3.new(0, HEAD_OFFSET, 0)
	gui.MaxDistance = MAX_DISTANCE
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false

	local stack = Instance.new("Frame")
	stack.Name = "Stack"
	stack.BackgroundTransparency = 1
	stack.Size = UDim2.fromScale(1, 1)
	stack.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = stack

	local crown = line(stack, "Crown", 1, 0.17, UITheme.Fonts.BodyBold, UITheme.Gold)
	crown.Text = "♛"
	local name = line(stack, "DisplayName", 2, 0.24, UITheme.Fonts.Button, UITheme.Paper)
	local rank = line(stack, "Rank", 3, 0.15, UITheme.Fonts.Button, UITheme.Muted)
	local crew = line(stack, "Crew", 4, 0.15, UITheme.Fonts.BodyBold, UITheme.Sakura)
	local title = line(stack, "Title", 5, 0.13, UITheme.Fonts.Body, UITheme.Gold)
	title.RichText = true

	local rookie = Instance.new("Frame")
	rookie.Name = "Rookie"
	rookie.LayoutOrder = 6
	rookie.Size = UDim2.fromScale(0.3, 0.11)
	rookie.BackgroundColor3 = Color3.fromHex(ROOKIE_COLOR)
	rookie.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = rookie
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.5
	stroke.Color = Color3.fromHex(UITheme.Ink)
	stroke.Parent = rookie
	local rookieText = line(rookie, "Text", 1, 0.9, UITheme.Fonts.Button, UITheme.Paper)
	rookieText.Position = UDim2.fromScale(0, 0.05)
	rookieText.Text = "ROOKIE"
	rookieText.TextStrokeTransparency = 0.6
	rookie.Parent = stack

	gui.Parent = head
	tags[player] = {
		Gui = gui,
		Crown = crown,
		Name = name,
		Rank = rank,
		Crew = crew,
		Title = title,
		Rookie = rookie,
	}
	refresh(player)
end

-- CustomName is player-chosen text: filter it before showing it to everyone.
local function checkCustomName(player: Player)
	local profile = Services.DataService and Services.DataService.GetProfile(player)
	local raw = if profile and type(profile.CustomName) == "string" then profile.CustomName else ""
	local cached = customNames[player]
	if cached and cached.Raw == raw then
		return
	end
	if raw == "" then
		customNames[player] = nil
		refresh(player)
		return
	end
	local entry: { Raw: string, Shown: string? } = { Raw = raw, Shown = nil }
	customNames[player] = entry
	local ok, filtered = pcall(function()
		return TextService:FilterStringAsync(raw, player.UserId):GetNonChatStringForBroadcastAsync()
	end)
	if customNames[player] ~= entry then
		return
	end
	if ok and filtered == raw then
		entry.Shown = raw
	end
	refresh(player)
end

local function hook(player: Player)
	player.CharacterAdded:Connect(function(character)
		build(player, character)
	end)
	player.AttributeChanged:Connect(function(attribute)
		if WATCHED[attribute] then
			refresh(player)
		end
	end)
	if player.Character then
		task.spawn(build, player, player.Character)
	end
end

function NameTagService.Init(services: any)
	Services = services
end

function NameTagService.Start()
	Players.PlayerAdded:Connect(hook)
	for _, player in Players:GetPlayers() do
		hook(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		tags[player] = nil
		customNames[player] = nil
	end)
	if Services.DataService and Services.DataService.ProfileLoaded then
		Services.DataService.ProfileLoaded:Connect(function(player: Player)
			checkCustomName(player)
		end)
	end
	while true do
		task.wait(CUSTOM_NAME_POLL)
		for _, player in Players:GetPlayers() do
			task.spawn(checkCustomName, player)
		end
	end
end

return NameTagService
