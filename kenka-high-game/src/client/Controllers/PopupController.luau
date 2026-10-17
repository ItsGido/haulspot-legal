--!strict
-- Overlays that are not UIController windows: challenge popup (5.7), rank-up banner, KO screen (5.8),
-- login calendar, tournament banner, tutorial card + style pick (FTUE), and the starter pack offer.
-- Public API:
--   PopupController.ShowStarterPack()        (respects the purchase window and Bought flag)
--   PopupController.HideTutorial()

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Shared.Util.Net)
local UITheme = require(ReplicatedStorage.Shared.Config.UITheme)
local Styles = require(ReplicatedStorage.Shared.Config.Styles)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local GameConfig = require(ReplicatedStorage.Shared.Config.Game)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local Kit = require(script.Parent.Parent.UI.Kit)
local W = require(script.Parent.Parent.UI.HudWidgets)

local PopupController = {}
PopupController.Priority = 25

local player = Players.LocalPlayer
local Controllers: any

local gui: ScreenGui = nil :: any -- DisplayOrder 40: above windows, below toasts
local koGui: ScreenGui = nil :: any -- DisplayOrder 60: above everything
local ready = false
local queue: { () -> () } = {}

local starterOffered = false

local TIPS = {
	"Tip: Block (F) a heavy, then tap it right before a hit to PARRY.",
	"Tip: Green zones are safe. Red zones are open fights.",
	"Tip: Duels never leave you downed. Challenge players with E.",
	"Tip: Crewmates can Help Up a downed friend.",
	"Tip: Food buffs from the Shotengai don't work in duels.",
	"Tip: Watch your posture bar. At 0 your guard breaks.",
}

-- Helpers ----------------------------------------------------------------------------

local function toast(text: string, kind: string?, duration: number?)
	W.Toast(Controllers, text, kind, duration)
end

local function whenReady(fn: () -> ())
	if ready then
		fn()
	else
		table.insert(queue, fn)
	end
end

local function getData(key: string): any
	local data = Controllers and Controllers.DataController
	if data and data.Get then
		return data.Get(key)
	end
	return nil
end

local function popupPanel(name: string, position: UDim2, size: UDim2, aspect: number?): (Frame, UIScale)
	local panel = Kit.Panel(name, gui, position, size, Vector2.new(0.5, 0.5))
	panel.Visible = false
	if aspect then
		Kit.Aspect(panel, aspect)
	end
	local scale = Instance.new("UIScale")
	scale.Parent = panel
	return panel, scale
end

local function header(parent: Frame, title: string, height: number): Frame
	local strip = Kit.Frame("Header", parent, UDim2.fromScale(0, 0), UDim2.fromScale(1, height), "#FFFFFF")
	Kit.Corner(strip, 0.25)
	Kit.InkStroke(strip, 3)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(Kit.Hex(UITheme.Buttons.Primary[1]), Kit.Hex(UITheme.Buttons.Primary[2]))
	g.Parent = strip
	local label = Kit.Label("Title", strip, title, UDim2.fromScale(0.04, 0.08), UDim2.fromScale(0.9, 0.84), "Title", UITheme.Paper, 48, Enum.TextXAlignment.Left)
	label.Rotation = -3
	return strip
end

local function showPanel(panel: Frame, scale: UIScale)
	panel.Visible = true
	scale.Scale = UITheme.Motion.PanelOpen.From
	TweenService:Create(scale, TweenInfo.new(UITheme.Motion.PanelOpen.Time, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	Kit.PlaySound("Open")
end

local function hidePanel(panel: Frame, scale: UIScale)
	if not panel.Visible then
		return
	end
	local tween = TweenService:Create(scale, TweenInfo.new(UITheme.Motion.PanelClose.Time), { Scale = UITheme.Motion.PanelClose.To })
	tween:Play()
	tween.Completed:Once(function()
		if scale.Scale <= UITheme.Motion.PanelClose.To + 0.001 then
			panel.Visible = false
		end
	end)
end

-- Challenge popup (5.7) -------------------------------------------------------------------

local challenge = {
	Panel = nil :: Frame?,
	Scale = nil :: UIScale?,
	Body = nil :: TextLabel?,
	Wager = nil :: TextLabel?,
	Bar = nil :: Frame?,
	From = nil :: Player?,
	ExpiresAt = 0,
	Total = 10,
	Token = 0,
}

local function hideChallenge()
	challenge.Token += 1
	challenge.From = nil
	local panel, scale = challenge.Panel, challenge.Scale
	if panel and scale then
		hidePanel(panel, scale)
	end
end

local function buildChallenge()
	local panel, scale = popupPanel("ChallengePopup", UDim2.fromScale(0.5, 0.35), UDim2.fromScale(0.34, 0.24), 2.5)
	header(panel, "CHALLENGE!", 0.24)
	local body = Kit.Label("Body", panel, "", UDim2.fromScale(0.05, 0.28), UDim2.fromScale(0.9, 0.2), "BodyBold", UITheme.Paper, 24, Enum.TextXAlignment.Left)
	local wager = Kit.Label("Wager", panel, "", UDim2.fromScale(0.05, 0.47), UDim2.fromScale(0.9, 0.12), "BodyBold", UITheme.Bars.Posture, 22, Enum.TextXAlignment.Left)
	local accept = Kit.Button(panel, "ACCEPT", "Primary", UDim2.fromScale(0.05, 0.62), UDim2.fromScale(0.43, 0.22))
	local decline = Kit.Button(panel, "DECLINE", "Ghost", UDim2.fromScale(0.52, 0.62), UDim2.fromScale(0.43, 0.22))
	local bar = Kit.Bar("Countdown", panel, UDim2.fromScale(0.05, 0.89), UDim2.fromScale(0.9, 0.06), UITheme.Ink, UITheme.Buttons.Primary[1], 1)
	challenge.Panel, challenge.Scale, challenge.Body, challenge.Wager, challenge.Bar = panel, scale, body, wager, bar

	local respond = Net.Event("Challenge_Respond")
	accept.Activated:Connect(function()
		local from = challenge.From
		if from then
			respond:FireServer(from, true)
		end
		hideChallenge()
	end)
	decline.Activated:Connect(function()
		local from = challenge.From
		if from then
			respond:FireServer(from, false)
		end
		hideChallenge()
	end)
end

local function showChallenge(payload: any)
	local from = payload.From
	if typeof(from) ~= "Instance" or not from:IsA("Player") then
		return
	end
	local panel, scale, body, wager, bar = challenge.Panel, challenge.Scale, challenge.Body, challenge.Wager, challenge.Bar
	if not (panel and scale and body and wager and bar) then
		return
	end
	local fromPlayer = from :: Player
	challenge.From = fromPlayer
	challenge.Token += 1
	local token = challenge.Token
	local name = if type(payload.FromName) == "string" then payload.FromName else fromPlayer.DisplayName
	local rank = if type(payload.FromRank) == "number" then payload.FromRank else 1
	local title = if type(payload.FromTitle) == "string" then payload.FromTitle else W.RankInfo(rank).Title
	body.Text = string.format("%s %s wants to fight.", W.Escape(name), W.Colored(string.format("· Rank %d %s", rank, W.Escape(title)), UITheme.Muted))
	local amount = if type(payload.Wager) == "number" then payload.Wager else 0
	wager.Text = if amount > 0 then string.format("Wager: %d Rep", amount) else "Friendly duel (no wager)"
	local expiresAt = if type(payload.ExpiresAt) == "number" then payload.ExpiresAt else W.ServerNow() + GameConfig.Challenge.ResponseTimeout
	local total = math.max(1, W.Remaining(expiresAt))
	challenge.ExpiresAt = expiresAt
	challenge.Total = total
	Kit.SetBar(bar, 1)
	showPanel(panel, scale)
	Kit.PlaySound("Bell")
	task.spawn(function()
		while challenge.Token == token do
			local remaining = W.Remaining(expiresAt)
			Kit.SetBar(bar, remaining / total)
			if remaining <= 0 then
				hideChallenge()
				break
			end
			task.wait(0.05)
		end
	end)
end

-- Starter pack offer ------------------------------------------------------------------------

local starter = { Panel = nil :: Frame?, Scale = nil :: UIScale? }

local function starterEligible(): boolean
	local pack = getData("StarterPack")
	if type(pack) ~= "table" or pack.Bought == true then
		return false
	end
	local firstJoin = if type(pack.FirstJoin) == "number" then pack.FirstJoin else 0
	if firstJoin <= 0 then
		return false
	end
	return W.ServerNow() - firstJoin <= Monetization.StarterPackWindowHours * 3600
end

local function buildStarter()
	local panel, scale = popupPanel("StarterPack", UDim2.fromScale(0.5, 0.45), UDim2.fromScale(0.36, 0.42), 1.5)
	header(panel, "STARTER PACK!", 0.16)
	local product = Monetization.DeveloperProducts.StarterPack
	local reward = Monetization.StarterPack
	Kit.Label("Pitch", panel, "Nice win! A one-time deal for new students:", UDim2.fromScale(0.05, 0.19), UDim2.fromScale(0.9, 0.1), "BodyBold", UITheme.Paper, 22)
	local chips = Kit.Frame("Chips", panel, UDim2.fromScale(0.05, 0.33), UDim2.fromScale(0.9, 0.24))
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromScale(0.48, 0.42)
	grid.CellPadding = UDim2.fromScale(0.04, 0.12)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = chips
	W.Chip(chips, Format.Yen(reward.Yen), UITheme.Gold, UDim2.new(), 1)
	W.Chip(chips, "📜 " .. reward.Scrolls .. " scrolls", UITheme.Bars.Rep, UDim2.new(), 2)
	W.Chip(chips, "🎟 " .. reward.CapsuleTokens .. " capsule tokens", UITheme.Rarity.Rare, UDim2.new(), 3)
	W.Chip(chips, "Rookie jacket", UITheme.Sakura, UDim2.new(), 4)
	Kit.Label("Window", panel, string.format("Only within %d hours of your first day.", Monetization.StarterPackWindowHours), UDim2.fromScale(0.05, 0.6), UDim2.fromScale(0.9, 0.08), "Body", UITheme.Muted, 18)
	local buy = Kit.Button(panel, W.Robux .. " " .. product.Price, "Premium", UDim2.fromScale(0.05, 0.73), UDim2.fromScale(0.52, 0.2))
	local later = Kit.Button(panel, "LATER", "Ghost", UDim2.fromScale(0.61, 0.73), UDim2.fromScale(0.34, 0.2))
	buy.Visible = product.Id ~= 0
	buy.Activated:Connect(function()
		W.PromptProduct(product.Id)
		hidePanel(panel, scale)
	end)
	later.Activated:Connect(function()
		hidePanel(panel, scale)
	end)
	starter.Panel, starter.Scale = panel, scale
end

function PopupController.ShowStarterPack()
	whenReady(function()
		local panel, scale = starter.Panel, starter.Scale
		if not panel or not scale or not starterEligible() then
			return
		end
		if Monetization.DeveloperProducts.StarterPack.Id == 0 then
			return -- not configured yet: don't show an offer that can't be bought
		end
		starterOffered = true
		showPanel(panel, scale)
	end)
end

-- Challenge updates --------------------------------------------------------------------------

local function nameOf(payload: any, field: string, playerField: string): string
	local name = payload[field]
	if type(name) == "string" and name ~= "" then
		return name
	end
	local p = payload[playerField]
	if typeof(p) == "Instance" and p:IsA("Player") then
		return (p :: Player).DisplayName
	end
	return "your opponent"
end

local function onChallengeUpdate(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local state: string = if type(payload.State) == "string" then payload.State else "Idle"
	local opponent = nameOf(payload, "OpponentName", "Opponent")
	local message = if type(payload.Message) == "string" and payload.Message ~= "" then payload.Message else nil
	if state == "Sent" then
		toast(message or ("Challenge sent to " .. opponent .. "."), "info")
	elseif state == "Declined" then
		toast(message or (opponent .. " declined your challenge."), "bad")
	elseif state == "Expired" then
		toast(message or "The challenge expired.", "info")
		if challenge.From and payload.Opponent == challenge.From then
			hideChallenge()
		end
	elseif state == "Started" then
		hideChallenge()
		toast(message or ("Duel started vs " .. opponent .. "! Stay inside the ring."), "zone", 4)
	elseif state == "Ended" then
		local winner = payload.Winner
		local won = winner == player
		local wager = if type(payload.Wager) == "number" then payload.Wager else 0
		if won then
			toast(message or (if wager > 0 then string.format("You won the duel! +%d Rep", wager) else "You won the duel!"), "good", 4)
			if not starterOffered and starterEligible() then
				task.delay(2, PopupController.ShowStarterPack)
			end
		else
			local winnerName = nameOf(payload, "WinnerName", "Winner")
			toast(message or (if winner then winnerName .. " won the duel." else "The duel ended in a draw."), if winner then "bad" else "info", 4)
		end
	elseif state == "Cancelled" then
		hideChallenge()
		toast(message or "The duel was cancelled.", "info")
	end
end

-- Rank-up banner -------------------------------------------------------------------------

local rankBanner = { Frame = nil :: Frame?, Title = nil :: TextLabel?, Rewards = nil :: TextLabel?, Token = 0 }

local function buildRankBanner()
	local banner = Kit.Frame("RankUpBanner", gui, UDim2.fromScale(-1, 0.3), UDim2.fromScale(1, 0.15), "#FFFFFF")
	Kit.InkStroke(banner, 4)
	banner.Visible = false
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(Kit.Hex(UITheme.Buttons.Primary[1]), Kit.Hex(UITheme.Buttons.Primary[2]))
	g.Parent = banner
	local title = Kit.Label("Title", banner, "", UDim2.fromScale(0.1, 0.05), UDim2.fromScale(0.8, 0.6), "Title", UITheme.Gold, 64)
	title.Rotation = -3
	local rewards = Kit.Label("Rewards", banner, "", UDim2.fromScale(0.1, 0.66), UDim2.fromScale(0.8, 0.28), "BodyBold", UITheme.Paper, 26)
	Kit.TextStroke(rewards, 2)
	rankBanner.Frame, rankBanner.Title, rankBanner.Rewards = banner, title, rewards
end

local function goldBurst(parent: Frame)
	local rng = Random.new()
	for _ = 1, 22 do
		local size = rng:NextNumber(0.012, 0.026)
		local bit = Kit.Frame("Spark", parent, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(size, size * 3), if rng:NextNumber() < 0.5 then UITheme.Gold else "#FFFFFF", Vector2.new(0.5, 0.5))
		bit.ZIndex = 5
		bit.Rotation = rng:NextNumber(0, 360)
		Kit.Aspect(bit, 1)
		Kit.InkStroke(bit, 1.5)
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(0.25, 0.55)
		local target = UDim2.fromScale(0.5 + math.cos(angle) * distance, 0.5 + math.sin(angle) * distance * 2.2)
		local info = TweenInfo.new(rng:NextNumber(0.6, 1.1), Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(bit, info, { Position = target, BackgroundTransparency = 1, Rotation = bit.Rotation + 180 }):Play()
		local stroke = bit:FindFirstChildOfClass("UIStroke")
		if stroke then
			TweenService:Create(stroke, info, { Transparency = 1 }):Play()
		end
		task.delay(1.2, function()
			bit:Destroy()
		end)
	end
end

local function showRankUp(payload: any)
	local banner, title, rewards = rankBanner.Frame, rankBanner.Title, rankBanner.Rewards
	if not (banner and title and rewards) or type(payload) ~= "table" then
		return
	end
	rankBanner.Token += 1
	local token = rankBanner.Token
	local rank = if type(payload.Rank) == "number" then payload.Rank else W.LocalRank()
	local info = W.RankInfo(rank)
	local rankTitle = if type(payload.Title) == "string" then payload.Title else info.Title
	title.Text = "RANK UP! " .. W.Escape(string.upper(rankTitle))
	local parts = {}
	if type(payload.Scrolls) == "number" and payload.Scrolls > 0 then
		table.insert(parts, "+" .. payload.Scrolls .. " scrolls")
	end
	if type(payload.Yen) == "number" and payload.Yen > 0 then
		table.insert(parts, "+" .. Format.Yen(payload.Yen))
	end
	table.insert(parts, "Unlocked: " .. info.Unlocks)
	rewards.Text = W.Escape(table.concat(parts, "  ·  "))
	banner.Position = UDim2.fromScale(-1, 0.3)
	banner.Visible = true
	Kit.PlaySound("RankUp")
	local slideIn = TweenService:Create(banner, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0, 0.3) })
	slideIn:Play()
	slideIn.Completed:Once(function()
		if token == rankBanner.Token then
			goldBurst(banner)
		end
	end)
	task.delay(2.8, function()
		if token ~= rankBanner.Token then
			return
		end
		local out = TweenService:Create(banner, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromScale(1, 0.3) })
		out:Play()
		out.Completed:Once(function()
			if token == rankBanner.Token then
				banner.Visible = false
			end
		end)
	end)
end

-- KO overlay (5.8) ------------------------------------------------------------------------

local ko = {
	Root = nil :: Frame?,
	Panel = nil :: Frame?,
	Scale = nil :: UIScale?,
	Killer = nil :: TextLabel?,
	Stamp = nil :: TextLabel?,
	Countdown = nil :: TextLabel?,
	Tip = nil :: TextLabel?,
	Token = 0,
}

local function hideKO()
	ko.Token += 1
	local root = ko.Root
	if root then
		root.Visible = false
	end
	local hud = Controllers and Controllers.HUDController
	if hud and hud.SetVisible then
		hud.SetVisible(true)
	end
end

local function buildKO()
	local root = Kit.Frame("KOOverlay", koGui, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), UITheme.Ink)
	root.BackgroundTransparency = 0.35
	root.Visible = false
	root.Active = true
	local panel = Kit.Frame("Panel", root, UDim2.fromScale(0.5, 0.45), UDim2.fromScale(0.5, 0.5), UITheme.Paper, Vector2.new(0.5, 0.5))
	panel.Rotation = -4
	Kit.InkStroke(panel, 6)
	Kit.Aspect(panel, 1.7)
	local scale = Instance.new("UIScale")
	scale.Parent = panel
	-- Speed lines (manga panel feel)
	for i = 1, 6 do
		local line = Kit.Frame("Line" .. i, panel, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1.2, 0.012), UITheme.Ink, Vector2.new(0.5, 0.5))
		line.Rotation = i * 30
		line.BackgroundTransparency = 0.85
	end
	local title = Kit.Label("KO", panel, "K.O.", UDim2.fromScale(0.05, 0.02), UDim2.fromScale(0.9, 0.48), "Title", UITheme.Bars.HP, 140)
	local tl = title:FindFirstChildOfClass("UITextSizeConstraint")
	if tl then
		tl.MaxTextSize = 140
	end
	local titleStroke = title:FindFirstChildOfClass("UIStroke")
	if titleStroke then
		titleStroke.Thickness = 4
	end
	local killer = Kit.Label("Killer", panel, "", UDim2.fromScale(0.05, 0.5), UDim2.fromScale(0.9, 0.13), "BodyBold", UITheme.Ink, 30)
	local stamp = Kit.Label("Stamp", panel, "", UDim2.fromScale(0.62, 0.02), UDim2.fromScale(0.36, 0.16), "Title", UITheme.Buttons.Primary[2], 40)
	stamp.Rotation = 12
	local countdown = Kit.Label("Countdown", panel, "", UDim2.fromScale(0.05, 0.66), UDim2.fromScale(0.9, 0.12), "BodyBold", UITheme.Ink, 26)
	local tip = Kit.Label("Tip", root, "", UDim2.fromScale(0.5, 0.88), UDim2.fromScale(0.6, 0.05), "Body", UITheme.Paper, 22)
	tip.AnchorPoint = Vector2.new(0.5, 0)
	ko.Root, ko.Panel, ko.Scale, ko.Killer, ko.Stamp, ko.Countdown, ko.Tip = root, panel, scale, killer, stamp, countdown, tip
end

local function showKO(payload: any)
	local root, panel, scale, killer, stamp, countdown, tip = ko.Root, ko.Panel, ko.Scale, ko.Killer, ko.Stamp, ko.Countdown, ko.Tip
	if not (root and panel and scale and killer and stamp and countdown and tip) or type(payload) ~= "table" then
		return
	end
	ko.Token += 1
	local token = ko.Token
	local killerName = if type(payload.KillerName) == "string" and payload.KillerName ~= "" then payload.KillerName else "someone"
	killer.Text = "Knocked out by " .. W.Escape(killerName)
	stamp.Text = if type(payload.Stamp) == "string" then W.Escape(payload.Stamp) else ""
	tip.Text = TIPS[math.random(1, #TIPS)]
	local respawnIn = if type(payload.RespawnIn) == "number" then payload.RespawnIn else 5
	local endsAt = os.clock() + respawnIn
	root.Visible = true
	local hud = Controllers and Controllers.HUDController
	if hud and hud.SetVisible then
		hud.SetVisible(false)
	end
	-- The manga panel slams in.
	scale.Scale = 3
	panel.Rotation = -12
	Kit.PlaySound("KO")
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 1 }):Play()
	TweenService:Create(panel, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Rotation = -4 }):Play()
	task.delay(0.18, function()
		-- impact shake
		for i = 1, 6 do
			if token ~= ko.Token then
				return
			end
			panel.Position = UDim2.fromScale(0.5 + (if i % 2 == 0 then 0.006 else -0.006), 0.45 + (if i % 3 == 0 then 0.006 else -0.004))
			task.wait(0.03)
		end
		panel.Position = UDim2.fromScale(0.5, 0.45)
	end)
	task.spawn(function()
		while token == ko.Token do
			local remaining = endsAt - os.clock()
			if remaining <= 0 then
				break
			end
			countdown.Text = string.format("Waking up in the Nurse's Office… %d", math.ceil(remaining))
			task.wait(0.1)
		end
		if token == ko.Token then
			countdown.Text = "Waking up in the Nurse's Office…"
			-- Safety: hide even if the respawn is delayed.
			task.delay(4, function()
				if token == ko.Token then
					hideKO()
				end
			end)
		end
	end)
end

-- Login reward ---------------------------------------------------------------------------

local login = { Panel = nil :: Frame?, Scale = nil :: UIScale?, Row = nil :: Frame?, Info = nil :: TextLabel? }

local function rewardText(reward: any): string
	if type(reward) ~= "table" then
		return "?"
	end
	local parts = {}
	if type(reward.Yen) == "number" then
		table.insert(parts, Format.Yen(reward.Yen))
	end
	if type(reward.Scrolls) == "number" then
		table.insert(parts, "📜" .. reward.Scrolls)
	end
	if type(reward.CapsuleTokens) == "number" then
		table.insert(parts, "🎟" .. reward.CapsuleTokens)
	end
	if reward.Badge then
		table.insert(parts, "🏅")
	end
	return table.concat(parts, " ")
end

local function buildLogin()
	local panel, scale = popupPanel("LoginReward", UDim2.fromScale(0.5, 0.45), UDim2.fromScale(0.56, 0.42), 2.3)
	header(panel, "DAILY LOGIN", 0.18)
	local info = Kit.Label("Info", panel, "", UDim2.fromScale(0.05, 0.21), UDim2.fromScale(0.9, 0.1), "BodyBold", UITheme.Paper, 22)
	local row = Kit.Frame("Days", panel, UDim2.fromScale(0.04, 0.35), UDim2.fromScale(0.92, 0.36))
	local list = Kit.List(row, 0.012, true)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	local ok = Kit.Button(panel, "CLAIM", "Success", UDim2.fromScale(0.5, 0.76), UDim2.fromScale(0.3, 0.18), Vector2.new(0.5, 0))
	ok.Activated:Connect(function()
		Kit.PlaySound("Purchase")
		hidePanel(panel, scale)
	end)
	login.Panel, login.Scale, login.Row, login.Info = panel, scale, row, info
end

local function showLogin(payload: any)
	local panel, scale, row, info = login.Panel, login.Scale, login.Row, login.Info
	if not (panel and scale and row and info) or type(payload) ~= "table" then
		return
	end
	local count = #Economy.LoginRewards
	local day = if type(payload.Day) == "number" then payload.Day else 1
	local cycleDay = ((math.floor(day) - 1) % count) + 1
	local streak = if type(payload.Streak) == "number" then payload.Streak else day
	info.Text = string.format("Day %d of %d  ·  Streak: %d day%s", cycleDay, count, streak, if streak == 1 then "" else "s")
	Kit.ClearChildren(row)
	local width = (1 - 0.012 * (count - 1)) / count
	for i = 1, count do
		local reward = if i == cycleDay and type(payload.Reward) == "table" then payload.Reward else Economy.LoginRewards[i]
		local isToday = i == cycleDay
		local color = if isToday then UITheme.Gold elseif i < cycleDay then UITheme.Panel else UITheme.PanelLight
		local cell = W.Row(row, "Day" .. i, UDim2.new(), UDim2.fromScale(width, 1), color)
		cell.LayoutOrder = i
		local textColor = if isToday then UITheme.Ink else UITheme.Paper
		Kit.Label("Day", cell, "DAY " .. i, UDim2.fromScale(0.05, 0.05), UDim2.fromScale(0.9, 0.25), "Title", textColor, 22)
		Kit.Label("Reward", cell, rewardText(reward), UDim2.fromScale(0.05, 0.35), UDim2.fromScale(0.9, 0.4), "BodyBold", textColor, 18)
		if i < cycleDay then
			Kit.Label("Check", cell, "✓", UDim2.fromScale(0.05, 0.72), UDim2.fromScale(0.9, 0.25), "BodyBold", "#5FE08A", 20)
		end
		if isToday then
			local stroke = cell:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Thickness = 4
			end
			W.Pop(cell, 1.2)
		end
	end
	showPanel(panel, scale)
end

-- Tournament banner ------------------------------------------------------------------------

local tourney = { Frame = nil :: Frame?, Title = nil :: TextLabel?, Line = nil :: TextLabel?, Match = nil :: any, Token = 0, Payload = nil :: any }

local function buildTourney()
	local frame = Kit.Panel("TourneyBanner", gui, UDim2.fromScale(0.07, 0.145), UDim2.fromScale(0.2, 0.065))
	Kit.Aspect(frame, 5.4)
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = Kit.Hex(UITheme.Gold)
	end
	frame.Visible = false
	local title = Kit.Label("Title", frame, "TOURNAMENT", UDim2.fromScale(0.04, 0.04), UDim2.fromScale(0.92, 0.46), "Title", UITheme.Gold, 26, Enum.TextXAlignment.Left)
	local line = Kit.Label("Line", frame, "", UDim2.fromScale(0.04, 0.5), UDim2.fromScale(0.92, 0.44), "BodyBold", UITheme.Paper, 18, Enum.TextXAlignment.Left)
	tourney.Frame, tourney.Title, tourney.Line = frame, title, line
end

local function renderTourney()
	local frame, title, line = tourney.Frame, tourney.Title, tourney.Line
	local payload = tourney.Payload
	if not (frame and title and line) or type(payload) ~= "table" then
		return
	end
	local state: string = if type(payload.State) == "string" then payload.State else "Idle"
	local players = if type(payload.Players) == "table" then #payload.Players else 0
	local needed = if type(payload.Needed) == "number" then payload.Needed else GameConfig.Tournament.MinPlayers
	local message = if type(payload.Message) == "string" and payload.Message ~= "" then payload.Message else nil
	if state == "Signup" then
		title.Text = string.format("TOURNAMENT · SIGN-UP %d/%d", players, needed)
		line.Text = W.Escape(message or "Join at the Gym sign-up board!")
	elseif state == "Running" then
		local match = payload.Match
		if type(match) == "table" then
			local a = tostring(match.A or "?")
			local b = tostring(match.B or "?")
			local timer = if type(match.EndsAt) == "number" then "  " .. Format.Duration(W.Remaining(match.EndsAt)) else ""
			title.Text = "TOURNAMENT · LIVE"
			line.Text = W.Escape(a .. " vs " .. b) .. W.Colored(timer, UITheme.Bars.Posture)
		else
			title.Text = "TOURNAMENT · LIVE"
			line.Text = W.Escape(message or "Next match starting…")
		end
	elseif state == "Finished" then
		title.Text = "TOURNAMENT · CHAMPION"
		local winner: string? = nil
		local bracket = payload.Bracket
		if type(bracket) == "table" and #bracket > 0 then
			local final = bracket[#bracket]
			if type(final) == "table" and type(final[1]) == "table" and final[1].Winner then
				winner = tostring(final[1].Winner)
			end
		end
		line.Text = W.Escape(message or (if winner then "🏆 " .. winner .. " wins!" else "The tournament is over."))
	end
end

local function orText(value: any, fallback: string): string
	return if type(value) == "string" and value ~= "" then value else fallback
end

local function onTourney(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local frame = tourney.Frame
	if not frame then
		return
	end
	local previous = tourney.Payload
	tourney.Payload = payload
	tourney.Token += 1
	local token = tourney.Token
	local state: string = if type(payload.State) == "string" then payload.State else "Idle"
	if state == "Idle" then
		frame.Visible = false
		return
	end
	if not frame.Visible then
		W.Pop(frame, 1.2)
	end
	frame.Visible = true
	renderTourney()
	local previousState: string = if type(previous) == "table" and type(previous.State) == "string" then previous.State else ""
	local changed = state ~= previousState
	if changed and state == "Signup" then
		toast("A tournament is open! Sign up at the Gym.", "gold", 4)
	elseif changed and state == "Finished" then
		toast(orText(payload.Message, "The tournament is over!"), "gold", 5)
		task.delay(10, function()
			if token == tourney.Token then
				frame.Visible = false
			end
		end)
	end
	if state == "Running" then
		task.spawn(function()
			while token == tourney.Token do
				renderTourney()
				task.wait(0.5)
			end
		end)
	end
end

-- Tutorial overlay (FTUE) ------------------------------------------------------------------

local tutorial = {
	Card = nil :: Frame?,
	Text = nil :: TextLabel?,
	Picker = nil :: Frame?,
	Cards = nil :: Frame?,
	Busy = false,
}

local function buildTutorial()
	local card = Kit.Panel("TutorialCard", gui, UDim2.fromScale(0.5, 0.97), UDim2.fromScale(0.4, 0.13), Vector2.new(0.5, 1))
	Kit.Aspect(card, 5.5)
	card.Visible = false
	local stroke = card:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = Kit.Hex(UITheme.Sakura)
	end
	Kit.Label("Tag", card, "TRANSFER DAY", UDim2.fromScale(0.03, 0.06), UDim2.fromScale(0.5, 0.28), "Title", UITheme.Sakura, 24, Enum.TextXAlignment.Left)
	local text = Kit.Label("Text", card, "", UDim2.fromScale(0.03, 0.36), UDim2.fromScale(0.72, 0.58), "BodyBold", UITheme.Paper, 24, Enum.TextXAlignment.Left)
	local skip = Kit.Button(card, "SKIP TUTORIAL", "Ghost", UDim2.fromScale(0.97, 0.5), UDim2.fromScale(0.21, 0.5), Vector2.new(1, 0.5))
	skip.Activated:Connect(function()
		Net.Event("Tutorial_Skip"):FireServer()
		PopupController.HideTutorial()
	end)

	local picker = Kit.Frame("StylePicker", gui, UDim2.fromScale(0.5, 0.42), UDim2.fromScale(0.62, 0.5), nil, Vector2.new(0.5, 0.5))
	Kit.Aspect(picker, 2.2)
	picker.Visible = false
	local pickTitle = Kit.Label("Title", picker, "PICK YOUR FIGHTING STYLE", UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.16), "Title", UITheme.Paper, 54)
	pickTitle.Rotation = -2
	local cards = Kit.Frame("Cards", picker, UDim2.fromScale(0, 0.2), UDim2.fromScale(1, 0.8))
	local list = Kit.List(cards, 0.03, true)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	tutorial.Card, tutorial.Text, tutorial.Picker, tutorial.Cards = card, text, picker, cards
end

local function showStyleChoices(choices: { any })
	local picker, cards = tutorial.Picker, tutorial.Cards
	if not (picker and cards) then
		return
	end
	Kit.ClearChildren(cards)
	local valid = {}
	for _, id in choices do
		if type(id) == "string" and Styles.Styles[id] then
			table.insert(valid, Styles.Styles[id])
		end
	end
	if #valid == 0 then
		picker.Visible = false
		return
	end
	local width = (1 - 0.03 * (#valid - 1)) / #valid
	for i, style in valid do
		local card = Instance.new("TextButton")
		card.Name = style.Id
		card.Text = ""
		card.AutoButtonColor = false
		card.Size = UDim2.fromScale(width, 1)
		card.BackgroundColor3 = Kit.Hex(UITheme.Panel)
		card.LayoutOrder = i
		card.Parent = cards
		Kit.Corner(card, 0.08)
		Kit.InkStroke(card, 4)
		Kit.Juice(card)
		local band = Kit.Frame("Band", card, UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.38), style.Color)
		Kit.Corner(band, 0.15)
		Kit.Label("Icon", band, style.Icon, UDim2.fromScale(0.25, 0.08), UDim2.fromScale(0.5, 0.84), "Body", UITheme.Paper, 64)
		Kit.Label("Name", card, string.upper(style.DisplayName), UDim2.fromScale(0.05, 0.41), UDim2.fromScale(0.9, 0.17), "Title", UITheme.Paper, 40)
		Kit.Label("Passive", card, W.Colored(W.Escape(style.Passive.Name), UITheme.Bars.Posture), UDim2.fromScale(0.05, 0.6), UDim2.fromScale(0.9, 0.1), "BodyBold", UITheme.Paper, 22)
		Kit.Label("Desc", card, W.Escape(style.Passive.Description), UDim2.fromScale(0.06, 0.71), UDim2.fromScale(0.88, 0.2), "Body", UITheme.Muted, 20)
		local id = style.Id
		card.Activated:Connect(function()
			if tutorial.Busy then
				return
			end
			tutorial.Busy = true
			local ok, message = W.Invoke(Net.Function("Tutorial_PickStyle"), id)
			tutorial.Busy = false
			if ok then
				picker.Visible = false
				toast("You fight with " .. style.DisplayName .. "!", "good")
			else
				toast(if type(message) == "string" then message else "Couldn't pick that style. Try again.", "bad")
			end
		end)
	end
	picker.Visible = true
	W.Pop(picker, 0.8)
end

function PopupController.HideTutorial()
	local card, picker = tutorial.Card, tutorial.Picker
	if card then
		card.Visible = false
	end
	if picker then
		picker.Visible = false
	end
end

local function onTutorial(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local card, text, picker = tutorial.Card, tutorial.Text, tutorial.Picker
	if not (card and text and picker) then
		return
	end
	if payload.Done == true or payload.Step == "Done" then
		PopupController.HideTutorial()
		return
	end
	text.Text = if type(payload.Text) == "string" then W.Escape(payload.Text) else ""
	if not card.Visible then
		card.Visible = true
	end
	W.Pop(card, 1.08)
	if payload.Step == "PickStyle" then
		showStyleChoices(if type(payload.Choices) == "table" then payload.Choices else Styles.StarterIds)
	else
		picker.Visible = false
	end
end

-- Lifecycle ----------------------------------------------------------------------------

function PopupController.Init(controllers: any)
	Controllers = controllers
	Net.Event("Challenge_Incoming").OnClientEvent:Connect(function(payload: any)
		if type(payload) == "table" then
			whenReady(function()
				showChallenge(payload)
			end)
		end
	end)
	Net.Event("Challenge_Update").OnClientEvent:Connect(function(payload: any)
		whenReady(function()
			onChallengeUpdate(payload)
		end)
	end)
	Net.Event("RankUp").OnClientEvent:Connect(function(payload: any)
		whenReady(function()
			showRankUp(payload)
		end)
	end)
	Net.Event("KO_Screen").OnClientEvent:Connect(function(payload: any)
		whenReady(function()
			showKO(payload)
		end)
	end)
	Net.Event("LoginReward").OnClientEvent:Connect(function(payload: any)
		whenReady(function()
			showLogin(payload)
		end)
	end)
	Net.Event("Tourney_Update").OnClientEvent:Connect(function(payload: any)
		whenReady(function()
			onTourney(payload)
		end)
	end)
	Net.Event("Tutorial_Update").OnClientEvent:Connect(function(payload: any)
		whenReady(function()
			onTutorial(payload)
		end)
	end)
end

function PopupController.Start()
	local playerGui = player:WaitForChild("PlayerGui")
	gui = W.Overlay(playerGui, "Popups", 40)
	koGui = W.Overlay(playerGui, "KOScreen", 60)
	koGui.ScreenInsets = Enum.ScreenInsets.None -- the K.O. dimmer covers the whole screen
	buildTourney()
	buildTutorial()
	buildChallenge()
	buildStarter()
	buildLogin()
	buildRankBanner()
	buildKO()

	player.CharacterAdded:Connect(function()
		hideKO()
	end)

	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId: number, productId: number, purchased: boolean)
		if userId == player.UserId and purchased and productId == Monetization.DeveloperProducts.StarterPack.Id then
			local panel, scale = starter.Panel, starter.Scale
			if panel and scale then
				hidePanel(panel, scale)
			end
		end
	end)

	ready = true
	local pending = queue
	queue = {}
	for _, fn in pending do
		task.spawn(fn)
	end
end

return PopupController
