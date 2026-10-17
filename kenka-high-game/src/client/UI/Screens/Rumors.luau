--!strict
-- Rumors (quests, blueprint 5.3): Daily / Weekly / Story tabs with progress, rewards, Claim and Reroll.
-- Profile shape: Quests.Daily = { { Id, Progress, Claimed } }, Weekly the same, Story = { Index, Progress }.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Util.Net)
local UITheme = require(ReplicatedStorage.Shared.Config.UITheme)
local Quests = require(ReplicatedStorage.Shared.Config.Quests)
local DayCycleMath = require(ReplicatedStorage.Shared.Logic.DayCycleMath)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local Kit = require(script.Parent.Parent.Kit)
local W = require(script.Parent.Parent.HudWidgets)

local Rumors = {}
Rumors.Name = "Rumors"

local Controllers: any
local windowRef: Kit.Window? = nil
local list: Frame = nil :: any
local resetLabel: TextLabel = nil :: any
local tabs: W.Tabs = nil :: any
local currentTab = "Daily"
local ticker: thread? = nil
local busy = false

local ICONS: { [string]: string } = {
	WinFight = "👊",
	WinDuel = "⚔",
	LandHit = "💥",
	Parry = "🛡",
	FinishJob = "🍜",
	AttendClass = "📚",
	CaptureTurf = "🚩",
	EarnYen = "¥",
	BuyFood = "🍙",
	VisitDojo = "🥋",
	Customize = "🪞",
	JoinCrew = "🤝",
	RankUp = "⭐",
	UseHeat = "🔥",
	TournamentMatch = "🏆",
}

local defsById: { [string]: any } = {}
for _, group in { Quests.Daily, Quests.Weekly, Quests.Story } do
	for _, def in group do
		defsById[def.Id] = def
	end
end

local function getData(key: string): any
	local data = Controllers and Controllers.DataController
	return if data and data.Get then data.Get(key) else nil
end

local function rerollsLeft(quests: any): number
	local free = Quests.DailyRerollsFree
	local derived = getData("Derived")
	if type(derived) == "table" and type(derived.Passes) == "table" and derived.Passes.VIP then
		free += 1
	end
	local used = if type(quests) == "table" and type(quests.RerollsUsed) == "number" then quests.RerollsUsed else 0
	-- RerollsUsed belongs to the current UTC day (QuestService resets it with Quests.Day).
	if type(quests) == "table" and type(quests.Day) == "number" and quests.Day ~= W.UtcToday() then
		used = 0
	end
	return math.max(0, free - used)
end

local render: () -> ()

local function claim(questId: string)
	if busy then
		return
	end
	busy = true
	local ok, message = W.Invoke(Net.Function("Quest_Claim"), questId)
	busy = false
	if ok then
		Kit.PlaySound("Purchase")
		W.Toast(Controllers, if type(message) == "string" and message ~= "" then message else "Rumor complete! Rewards claimed.", "gold")
	else
		W.Toast(Controllers, if type(message) == "string" then message else "Couldn't claim that rumor.", "bad")
	end
	render()
end

local function reroll(questId: string)
	if busy then
		return
	end
	busy = true
	local ok, message = W.Invoke(Net.Function("Quest_Reroll"), questId)
	busy = false
	if ok then
		W.Toast(Controllers, if type(message) == "string" and message ~= "" then message else "New rumor unlocked.", "good")
	else
		W.Toast(Controllers, if type(message) == "string" then message else "No rerolls left today.", "bad")
	end
	render()
end

type RowOptions = {
	Def: any,
	Progress: number,
	Claimed: boolean,
	CanReroll: boolean,
	RerollsLeft: number,
	Preview: boolean?,
	Order: number,
	Height: number,
}

local function buildRow(options: RowOptions)
	local def = options.Def
	local goal = math.max(1, def.Goal)
	local progress = math.min(options.Progress, goal)
	local complete = options.Progress >= goal
	local row = W.Row(list, def.Id, UDim2.new(), UDim2.fromScale(1, options.Height), if options.Preview then UITheme.Panel else UITheme.PanelLight)
	row.LayoutOrder = options.Order

	local icon = Kit.Label("Icon", row, ICONS[def.Event] or "❔", UDim2.fromScale(0.015, 0.15), UDim2.fromScale(0.07, 0.7), "Number", UITheme.Paper, 40)
	Kit.Aspect(icon, 1)
	local titleColor = if options.Preview then UITheme.Muted else UITheme.Paper
	Kit.Label("Title", row, W.Escape(def.Title), UDim2.fromScale(0.1, 0.08), UDim2.fromScale(0.66, 0.38), "BodyBold", titleColor, 24, Enum.TextXAlignment.Left)

	local bar = Kit.Bar("Progress", row, UDim2.fromScale(0.1, 0.58), UDim2.fromScale(0.3, 0.2), UITheme.Ink, if complete then "#5FE08A" else UITheme.Bars.Rep, progress / goal)
	bar.BackgroundTransparency = 0
	Kit.Label("Count", row, Format.Commas(progress) .. " / " .. Format.Commas(goal), UDim2.fromScale(0.41, 0.52), UDim2.fromScale(0.13, 0.32), "Number", UITheme.Paper, 18, Enum.TextXAlignment.Left)

	local chips = Kit.Frame("Rewards", row, UDim2.fromScale(0.55, 0.52), UDim2.fromScale(0.24, 0.34))
	local chipList = Kit.List(chips, 0.03, true)
	chipList.VerticalAlignment = Enum.VerticalAlignment.Center
	if def.Rep > 0 then
		W.Chip(chips, "+" .. def.Rep .. " REP", UITheme.Bars.Rep, UDim2.fromScale(0.36, 1), 1)
	end
	if def.Yen > 0 then
		W.Chip(chips, Format.Yen(def.Yen), UITheme.Gold, UDim2.fromScale(0.34, 1), 2)
	end
	if def.Scrolls > 0 then
		W.Chip(chips, "📜" .. def.Scrolls, "#F5F1E8", UDim2.fromScale(0.24, 1), 3)
	end

	if options.Preview then
		Kit.Label("Next", row, "UP NEXT", UDim2.fromScale(0.8, 0.3), UDim2.fromScale(0.18, 0.4), "Title", UITheme.Muted, 24)
		return
	end

	if options.Claimed then
		Kit.Label("Claimed", row, "✓ CLAIMED", UDim2.fromScale(0.8, 0.3), UDim2.fromScale(0.18, 0.4), "Title", "#5FE08A", 26)
	elseif complete then
		local button = Kit.Button(row, "CLAIM", "Success", UDim2.fromScale(0.8, 0.2), UDim2.fromScale(0.18, 0.6))
		W.Pop(button, 1.15)
		local id = def.Id
		button.Activated:Connect(function()
			claim(id)
		end)
	elseif options.CanReroll then
		local button = Kit.Button(row, "REROLL (" .. options.RerollsLeft .. ")", "Ghost", UDim2.fromScale(0.8, 0.25), UDim2.fromScale(0.18, 0.5))
		W.SetEnabled(button, options.RerollsLeft > 0, "Ghost")
		local id = def.Id
		button.Activated:Connect(function()
			if W.IsEnabled(button) then
				reroll(id)
			else
				W.Toast(Controllers, "No free rerolls left today. They reset at 00:00 UTC.", "info")
			end
		end)
	end
end

local function renderEntries(entries: any, isDaily: boolean, quests: any)
	local valid = {}
	if type(entries) == "table" then
		for _, entry in entries do
			if type(entry) == "table" and type(entry.Id) == "string" and defsById[entry.Id] then
				table.insert(valid, entry)
			end
		end
	end
	if #valid == 0 then
		W.Note(list, "Empty", "No rumors right now. Check back soon!", UDim2.new(), UDim2.fromScale(1, 0.2))
		return
	end
	local left = rerollsLeft(quests)
	for i, entry in valid do
		buildRow({
			Def = defsById[entry.Id],
			Progress = if type(entry.Progress) == "number" then entry.Progress else 0,
			Claimed = entry.Claimed == true,
			CanReroll = isDaily,
			RerollsLeft = left,
			Order = i,
			Height = 0.3,
		})
	end
end

local function renderStory(quests: any)
	local story = if type(quests) == "table" and type(quests.Story) == "table" then quests.Story else { Index = 1, Progress = 0 }
	local index = if type(story.Index) == "number" then story.Index else 1
	local total = #Quests.Story
	if index > total then
		local done = W.Note(list, "Done", "TRANSFER ARC COMPLETE!\nYou're one of us now. Keep climbing the ranks.", UDim2.new(), UDim2.fromScale(1, 0.3))
		done.TextColor3 = Kit.Hex(UITheme.Gold)
		return
	end
	local header = Kit.Label("Step", list, string.format("TRANSFER ARC · STEP %d / %d", index, total), UDim2.new(), UDim2.fromScale(1, 0.1), "Title", UITheme.Sakura, 30, Enum.TextXAlignment.Left)
	header.LayoutOrder = 0
	buildRow({
		Def = Quests.Story[index],
		Progress = if type(story.Progress) == "number" then story.Progress else 0,
		Claimed = false,
		CanReroll = false,
		RerollsLeft = 0,
		Order = 1,
		Height = 0.27,
	})
	for offset = 1, 2 do
		local def = Quests.Story[index + offset]
		if def then
			buildRow({ Def = def, Progress = 0, Claimed = false, CanReroll = false, RerollsLeft = 0, Preview = true, Order = 1 + offset, Height = 0.24 })
		end
	end
end

local function updateReset()
	local now = W.ServerNow()
	if currentTab == "Daily" then
		resetLabel.Text = "Resets in " .. Format.Duration(W.UntilUtcMidnight())
	elseif currentTab == "Weekly" then
		local week = DayCycleMath.UtcWeek(now)
		local nextStart = ((week + 1) * 7 - 3) * 86400
		local remaining = nextStart - now
		local days = math.floor(remaining / 86400)
		resetLabel.Text = "Resets in " .. (if days > 0 then days .. "d " else "") .. Format.Duration(remaining % 86400)
	else
		resetLabel.Text = "The new-student story"
	end
end

render = function()
	local window = windowRef
	if not window or not window.Gui.Enabled then
		return
	end
	Kit.ClearChildren(list)
	local quests = getData("Quests")
	if currentTab == "Daily" then
		renderEntries(if type(quests) == "table" then quests.Daily else nil, true, quests)
	elseif currentTab == "Weekly" then
		renderEntries(if type(quests) == "table" then quests.Weekly else nil, false, quests)
	else
		renderStory(quests)
	end
	updateReset()
end

function Rumors.Build(playerGui: Instance, controllers: any): Kit.Window
	Controllers = controllers
	local window = Kit.Window(playerGui, "Rumors", "RUMORS", UDim2.fromScale(0.62, 0.78))
	W.ShapeWindow(window, 1.5)
	windowRef = window

	tabs = W.Tabs(window.Body, { "Daily", "Weekly", "Story" }, UDim2.fromScale(0, 0), UDim2.fromScale(0.6, 0.11), function(name: string)
		currentTab = name
		render()
	end)
	resetLabel = Kit.Label("Reset", window.Body, "", UDim2.fromScale(0.62, 0), UDim2.fromScale(0.38, 0.11), "BodyBold", UITheme.Muted, 20, Enum.TextXAlignment.Right)

	list = Kit.Frame("List", window.Body, UDim2.fromScale(0, 0.14), UDim2.fromScale(1, 0.86))
	Kit.List(list, 0.03)

	local data = controllers.DataController
	if data and data.Observe then
		data.Observe("Quests", function()
			render()
		end)
		data.Observe("Derived", function()
			render()
		end)
	end
	return window
end

function Rumors.Open(_window: Kit.Window, data: any?)
	if type(data) == "table" and type(data.Tab) == "string" and (data.Tab == "Daily" or data.Tab == "Weekly" or data.Tab == "Story") then
		currentTab = data.Tab
		tabs.Select(data.Tab)
	end
	-- Window becomes enabled right after Open; render on the next frame.
	task.defer(render)
	if ticker then
		pcall(task.cancel, ticker)
	end
	ticker = task.spawn(function()
		while true do
			task.wait(1)
			updateReset()
		end
	end)
end

function Rumors.Close(_window: Kit.Window)
	if ticker then
		pcall(task.cancel, ticker)
		ticker = nil
	end
end

return Rumors
