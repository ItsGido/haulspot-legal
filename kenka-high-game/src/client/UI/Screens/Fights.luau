--!strict
-- Fights: your record (profile Stats), the rank ladder with unlocks, and a "Challenge a player" list.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Util.Net)
local UITheme = require(ReplicatedStorage.Shared.Config.UITheme)
local Ranks = require(ReplicatedStorage.Shared.Config.Ranks)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local RepMath = require(ReplicatedStorage.Shared.Logic.RepMath)
local Kit = require(script.Parent.Parent.Kit)
local W = require(script.Parent.Parent.HudWidgets)

local Fights = {}
Fights.Name = "Fights"

local player = Players.LocalPlayer
local Controllers: any
local statsGrid: Frame = nil :: any
local ladder: Frame = nil :: any
local repLine: TextLabel = nil :: any
local scroll: ScrollingFrame = nil :: any
local emptyNote: TextLabel = nil :: any
local cooldownUntil: { [number]: number } = {}

local function getData(key: string): any
	local data = Controllers and Controllers.DataController
	return if data and data.Get then data.Get(key) else nil
end

local function statTile(order: number, label: string, value: string, color: string?)
	local tile = W.Row(statsGrid, "Stat" .. order, UDim2.new(), UDim2.new(), UITheme.Panel)
	tile.LayoutOrder = order
	Kit.Label("Value", tile, value, UDim2.fromScale(0.05, 0.08), UDim2.fromScale(0.9, 0.55), "Number", color or UITheme.Paper, 36)
	Kit.Label("Label", tile, label, UDim2.fromScale(0.05, 0.64), UDim2.fromScale(0.9, 0.3), "BodyBold", UITheme.Muted, 16)
end

local function renderStats()
	Kit.ClearChildren(statsGrid)
	local stats = getData("Stats")
	local s = if type(stats) == "table" then stats else {}
	local function n(key: string): number
		local v = s[key]
		return if type(v) == "number" then v else 0
	end
	local wins, losses = n("Wins"), n("Losses")
	local total = wins + losses
	local rate = if total > 0 then math.floor(wins / total * 100 + 0.5) else 0
	local minutes = n("PlaytimeMin")
	statTile(1, "WINS", Format.Commas(wins), "#5FE08A")
	statTile(2, "LOSSES", Format.Commas(losses), UITheme.Bars.HP)
	statTile(3, "WIN RATE", rate .. "%", UITheme.Gold)
	statTile(4, "DUELS WON", Format.Commas(n("DuelsWon")))
	statTile(5, "TOURNEYS WON", Format.Commas(n("TourneysWon")), UITheme.Gold)
	statTile(6, "TURF CAPTURES", Format.Commas(n("TurfCaptures")), UITheme.Sakura)
	statTile(7, "PARRIES", Format.Commas(n("Parries")))
	statTile(8, "PLAYTIME", string.format("%d:%02d", minutes // 60, minutes % 60))
end

local function renderLadder()
	Kit.ClearChildren(ladder)
	local rep = player:GetAttribute("Rep")
	local repValue = if type(rep) == "number" then rep else (if type(getData("Rep")) == "number" then getData("Rep") else 0)
	local current = RepMath.RankForRep(Ranks, repValue)
	local nextEntry = Ranks.List[current + 1]
	repLine.Text = if nextEntry
		then string.format("Rep %s · next: %s at %s", Format.Commas(repValue), W.Escape(nextEntry.Title), Format.Commas(nextEntry.Rep))
		else string.format("Rep %s · max rank!", Format.Commas(repValue))
	for i = #Ranks.List, 1, -1 do
		local entry = Ranks.List[i]
		local isCurrent = entry.Number == current
		local reached = entry.Number <= current
		local row = W.Row(ladder, "Rank" .. entry.Number, UDim2.new(), UDim2.fromScale(1, 0.112), if isCurrent then UITheme.PanelLight else UITheme.Panel)
		row.LayoutOrder = #Ranks.List - i
		local stroke = row:FindFirstChildOfClass("UIStroke")
		if stroke and isCurrent then
			stroke.Color = Kit.Hex(UITheme.Gold)
			stroke.Thickness = 3
		end
		local badge = Kit.Frame("Badge", row, UDim2.fromScale(0.02, 0.5), UDim2.fromScale(0.12, 0.8), entry.Color, Vector2.new(0, 0.5))
		Kit.Corner(badge, 1)
		Kit.Aspect(badge, 1, true)
		Kit.InkStroke(badge, 2)
		Kit.Label("N", badge, tostring(entry.Number), UDim2.fromScale(0.15, 0.15), UDim2.fromScale(0.7, 0.7), "Title", UITheme.Ink, 22)
		local titleColor = if reached then UITheme.Paper else UITheme.Muted
		Kit.Label("Title", row, W.Escape(entry.Title) .. (if isCurrent then W.Colored("  ◀ YOU", UITheme.Gold) else ""), UDim2.fromScale(0.16, 0.04), UDim2.fromScale(0.56, 0.5), "BodyBold", titleColor, 20, Enum.TextXAlignment.Left)
		Kit.Label("Rep", row, Format.Commas(entry.Rep) .. " Rep", UDim2.fromScale(0.72, 0.04), UDim2.fromScale(0.26, 0.5), "Number", UITheme.Bars.Rep, 18, Enum.TextXAlignment.Right)
		Kit.Label("Unlocks", row, W.Escape(entry.Unlocks), UDim2.fromScale(0.16, 0.52), UDim2.fromScale(0.82, 0.44), "Body", UITheme.Muted, 15, Enum.TextXAlignment.Left)
	end
end

local function challenge(target: Player, button: TextButton)
	local now = os.clock()
	if (cooldownUntil[target.UserId] or 0) > now then
		return
	end
	cooldownUntil[target.UserId] = now + 5
	W.SetEnabled(button, false, "Primary")
	task.delay(5, function()
		if button.Parent then
			W.SetEnabled(button, true, "Primary")
		end
	end)
	local controller = Controllers and Controllers.ChallengeController
	if controller and controller.ChallengePlayer then
		controller.ChallengePlayer(target)
	else
		Net.Event("Challenge_Send"):FireServer(target)
	end
end

local function renderPlayers()
	Kit.ClearChildren(scroll)
	local others = {}
	for _, other in Players:GetPlayers() do
		if other ~= player then
			table.insert(others, other)
		end
	end
	table.sort(others, function(a, b)
		local ra = a:GetAttribute("Rank")
		local rb = b:GetAttribute("Rank")
		local na = if type(ra) == "number" then ra else 1
		local nb = if type(rb) == "number" then rb else 1
		if na == nb then
			return a.DisplayName:lower() < b.DisplayName:lower()
		end
		return na > nb
	end)
	emptyNote.Visible = #others == 0
	local rowHeight = W.ScrollRows(scroll, #others, 0.15, 0.015)
	for i, other in others do
		local rank = other:GetAttribute("Rank")
		local info = W.RankInfo(rank)
		local row = W.Row(scroll, "Player_" .. other.UserId, UDim2.new(), UDim2.fromScale(0.97, rowHeight))
		row.LayoutOrder = i
		local tags = ""
		if other:GetAttribute("RookieProtected") == true then
			tags ..= W.Colored(" ROOKIE", "#5FE08A")
		end
		if other:GetAttribute("Crown") == true then
			tags ..= W.Colored(" ♛", UITheme.Gold)
		end
		Kit.Label("Name", row, W.Escape(other.DisplayName) .. tags, UDim2.fromScale(0.05, 0.05), UDim2.fromScale(0.58, 0.5), "BodyBold", UITheme.Paper, 20, Enum.TextXAlignment.Left)
		Kit.Label("Rank", row, string.format("Rank %d · %s", if type(rank) == "number" then rank else 1, W.Escape(info.Title)), UDim2.fromScale(0.05, 0.55), UDim2.fromScale(0.58, 0.4), "Body", info.Color, 16, Enum.TextXAlignment.Left)
		local button = Kit.Button(row, "FIGHT", "Primary", UDim2.fromScale(0.97, 0.5), UDim2.fromScale(0.32, 0.72), Vector2.new(1, 0.5))
		local inDuel = other:GetAttribute("InDuel") == true or player:GetAttribute("InDuel") == true
		W.SetEnabled(button, not inDuel and (cooldownUntil[other.UserId] or 0) <= os.clock(), "Primary")
		button.Activated:Connect(function()
			if W.IsEnabled(button) then
				challenge(other, button)
			elseif other:GetAttribute("InDuel") == true then
				W.Toast(Controllers, other.DisplayName .. " is already in a duel.", "info")
			end
		end)
	end
end

function Fights.Build(playerGui: Instance, controllers: any): Kit.Window
	Controllers = controllers
	local window = Kit.Window(playerGui, "Fights", "FIGHTS · RECORD & RANKS", UDim2.fromScale(0.86, 0.86))
	W.ShapeWindow(window, 1.75)
	local body = window.Body

	-- Record
	local record = Kit.Panel("Record", body, UDim2.fromScale(0, 0), UDim2.fromScale(0.3, 1), nil, UITheme.PanelLight)
	Kit.Label("Title", record, "RECORD", UDim2.fromScale(0.06, 0.02), UDim2.fromScale(0.88, 0.09), "Title", UITheme.Paper, 32, Enum.TextXAlignment.Left)
	statsGrid = Kit.Frame("Stats", record, UDim2.fromScale(0.05, 0.13), UDim2.fromScale(0.9, 0.84))
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromScale(0.48, 0.22)
	grid.CellPadding = UDim2.fromScale(0.04, 0.035)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = statsGrid

	-- Ladder
	local ladderPanel = Kit.Frame("LadderPanel", body, UDim2.fromScale(0.32, 0), UDim2.fromScale(0.37, 1))
	Kit.Label("Title", ladderPanel, "RANK LADDER", UDim2.fromScale(0, 0), UDim2.fromScale(0.6, 0.08), "Title", UITheme.Paper, 32, Enum.TextXAlignment.Left)
	repLine = Kit.Label("Rep", ladderPanel, "", UDim2.fromScale(0, 0.08), UDim2.fromScale(1, 0.05), "BodyBold", UITheme.Bars.Rep, 18, Enum.TextXAlignment.Left)
	ladder = Kit.Frame("Ladder", ladderPanel, UDim2.fromScale(0, 0.14), UDim2.fromScale(1, 0.86))
	Kit.List(ladder, 0.008)

	-- Challenge list
	local challengePanel = Kit.Panel("Challenge", body, UDim2.fromScale(1, 0), UDim2.fromScale(0.29, 1), Vector2.new(1, 0), UITheme.PanelLight)
	Kit.Label("Title", challengePanel, "CHALLENGE A PLAYER", UDim2.fromScale(0.06, 0.02), UDim2.fromScale(0.88, 0.08), "Title", UITheme.Paper, 28, Enum.TextXAlignment.Left)
	Kit.Label("Hint", challengePanel, "Duels never leave you downed. Wager scales with the rank gap.", UDim2.fromScale(0.06, 0.1), UDim2.fromScale(0.88, 0.08), "Body", UITheme.Muted, 15, Enum.TextXAlignment.Left)
	scroll = Kit.Scroll("Players", challengePanel, UDim2.fromScale(0.04, 0.2), UDim2.fromScale(0.92, 0.78))
	Kit.List(scroll, 0.015)
	emptyNote = W.Note(challengePanel, "Empty", "Nobody to fight yet.", UDim2.fromScale(0.06, 0.3), UDim2.fromScale(0.88, 0.1))

	local function refreshPlayersIfOpen()
		if window.Gui.Enabled then
			task.defer(renderPlayers)
		end
	end
	Players.PlayerAdded:Connect(refreshPlayersIfOpen)
	Players.PlayerRemoving:Connect(refreshPlayersIfOpen)
	player:GetAttributeChangedSignal("Rep"):Connect(function()
		if window.Gui.Enabled then
			renderLadder()
		end
	end)
	local data = controllers.DataController
	if data and data.Changed then
		data.Changed:Connect(function(key: string)
			if key == "Stats" and window.Gui.Enabled then
				renderStats()
			end
		end)
	end
	return window
end

function Fights.Open(_window: Kit.Window, _data: any?)
	renderStats()
	renderLadder()
	renderPlayers()
end

return Fights
