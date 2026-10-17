--!strict
-- Crew app (blueprint 5.5).
--   No crew: Create Crew (name, 12 color swatches, 40-emblem grid, cost) + crews in this server (Request to Join).
--   In a crew: header (emblem, name, members, weekly Rep, turfs), roster with role actions, join requests,
--   invite list (online players without a crew), Leave / Disband with a confirm step.
-- All requests go through CrewController.Action (Crew_Action remote); the server re-validates everything.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Crews = require(ReplicatedStorage.Shared.Config.Crews)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Ranks = require(ReplicatedStorage.Shared.Config.Ranks)
local UITheme = require(ReplicatedStorage.Shared.Config.UITheme)
local Kit = require(script.Parent.Parent.Kit)

local Screen = {}
Screen.Name = "Crew"

local CONFIRM_SECONDS = 4
local ROLE_COLORS = { Leader = UITheme.Gold, Lieutenant = UITheme.Sakura, Member = UITheme.Muted }
local ONLINE = "#5FE08A"
local OFFLINE = "#5A5E6B"

local localPlayer = Players.LocalPlayer
local Controllers: any
local currentWindow: Kit.Window? = nil
local content: Frame? = nil
local statusLabel: TextLabel? = nil

local state = {
	Name = "",
	Color = 1,
	Emblem = 1,
	ServerCrews = {} :: { any },
	Confirm = nil :: string?,
	ConfirmUntil = 0,
	Busy = false,
}

local render: () -> ()

-- Helpers -------------------------------------------------------------------------------

local function esc(text: any): string
	return (tostring(text):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function commas(n: number): string
	local text = tostring(math.floor(math.abs(n)))
	local result = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if result:sub(1, 1) == "," then
		result = result:sub(2)
	end
	return result
end

local function myRank(): number
	local rank = localPlayer:GetAttribute("Rank")
	return if type(rank) == "number" then rank else 1
end

local function myYen(): number
	local yen = localPlayer:GetAttribute("Yen")
	return if type(yen) == "number" then yen else 0
end

local function getSummary(): any?
	local controller = Controllers and Controllers.CrewController
	return if controller then controller.GetSummary() else nil
end

local function setStatus(text: string, ok: boolean?)
	local label = statusLabel
	if label then
		label.Text = text
		label.TextColor3 = Color3.fromHex(if ok == false then "#FF5A4F" elseif ok then ONLINE else UITheme.Muted)
	end
end

local function isOpen(): boolean
	local w = currentWindow
	return w ~= nil and w.Gui.Enabled
end

local function fetchServerCrews()
	local controller = Controllers and Controllers.CrewController
	if not controller then
		return
	end
	task.spawn(function()
		local ok, result = controller.Action("ListServer")
		if ok and type(result) == "table" then
			state.ServerCrews = result
			if isOpen() and getSummary() == nil then
				render()
			end
		end
	end)
end

local function act(action: string, args: any?, after: (() -> ())?)
	local controller = Controllers and Controllers.CrewController
	if not controller or state.Busy then
		return
	end
	state.Busy = true
	state.Confirm = nil
	setStatus("Working...", nil)
	task.spawn(function()
		local ok, result = controller.Action(action, args)
		state.Busy = false
		if type(result) == "string" then
			setStatus(result, ok)
		elseif ok then
			setStatus("Done.", true)
		else
			setStatus("Something went wrong.", false)
		end
		if after then
			after()
		end
		if isOpen() then
			render()
		end
	end)
end

-- Two-click confirm. Returns true when the second click lands within CONFIRM_SECONDS.
local function confirm(key: string): boolean
	if state.Confirm == key and os.clock() < state.ConfirmUntil then
		state.Confirm = nil
		return true
	end
	state.Confirm = key
	state.ConfirmUntil = os.clock() + CONFIRM_SECONDS
	setStatus("Tap again to confirm.", nil)
	render()
	task.delay(CONFIRM_SECONDS, function()
		if state.Confirm == key and os.clock() >= state.ConfirmUntil then
			state.Confirm = nil
			if isOpen() then
				render()
			end
		end
	end)
	return false
end

local function confirming(key: string): boolean
	return state.Confirm == key and os.clock() < state.ConfirmUntil
end

local function section(parent: Instance, name: string, position: UDim2, size: UDim2): Frame
	local panel = Kit.Panel(name, parent, position, size, nil, UITheme.PanelLight)
	local corner = panel:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0.03, 0)
	end
	return panel
end

-- A list row whose height follows its width (Scale-only sizing that works inside scrolling frames).
local function row(parent: Instance, name: string, order: number, aspect: number): Frame
	local r = Kit.Frame(name, parent, UDim2.new(), UDim2.fromScale(0.98, 0), UITheme.Panel)
	r.LayoutOrder = order
	r.Size = UDim2.fromScale(0.98, 1)
	Kit.Aspect(r, aspect)
	Kit.Corner(r, 0.2)
	Kit.InkStroke(r, 2)
	return r
end

local function scroll(parent: Instance, name: string, position: UDim2, size: UDim2): ScrollingFrame
	local s = Kit.Scroll(name, parent, position, size)
	local layout = Kit.List(s, 0.015)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.01, 0)
	pad.PaddingBottom = UDim.new(0.01, 0)
	pad.Parent = s
	return s
end

local function smallButton(parent: Instance, text: string, style: string, position: UDim2, size: UDim2, onClick: () -> ()): TextButton
	local b = Kit.Button(parent, text, style, position, size)
	b.Activated:Connect(function()
		if style ~= "Disabled" then
			onClick()
		end
	end)
	return b
end

-- No crew: create + browse ------------------------------------------------------------------

local function renderCreate(root: Frame)
	local panel = section(root, "Create", UDim2.fromScale(0, 0), UDim2.fromScale(0.57, 1))
	Kit.Label("Title", panel, "CREATE CREW", UDim2.fromScale(0.04, 0.015), UDim2.fromScale(0.92, 0.08), "Title", UITheme.Sakura, 40, Enum.TextXAlignment.Left)

	local box = Instance.new("TextBox")
	box.Name = "NameBox"
	box.Position = UDim2.fromScale(0.04, 0.11)
	box.Size = UDim2.fromScale(0.92, 0.085)
	box.BackgroundColor3 = Color3.fromHex(UITheme.Ink)
	box.BorderSizePixel = 0
	box.ClearTextOnFocus = false
	box.Font = UITheme.Fonts.BodyBold
	box.PlaceholderText = string.format("Crew name (%d-%d letters)", Crews.NameMin, Crews.NameMax)
	box.PlaceholderColor3 = Color3.fromHex(UITheme.Muted)
	box.Text = state.Name
	box.TextColor3 = Color3.fromHex(UITheme.Paper)
	box.TextScaled = true
	box.TextXAlignment = Enum.TextXAlignment.Left
	Kit.TextLimit(box, UITheme.TextMax.Body)
	Kit.Corner(box, 0.2)
	Kit.InkStroke(box, 2)
	local boxPad = Instance.new("UIPadding")
	boxPad.PaddingLeft = UDim.new(0.03, 0)
	boxPad.PaddingTop = UDim.new(0.15, 0)
	boxPad.PaddingBottom = UDim.new(0.15, 0)
	boxPad.Parent = box
	box.Parent = panel

	Kit.Label("ColorLabel", panel, "COLOR", UDim2.fromScale(0.04, 0.21), UDim2.fromScale(0.5, 0.045), "BodyBold", UITheme.Muted, 18, Enum.TextXAlignment.Left)
	local swatches = Kit.Frame("Swatches", panel, UDim2.fromScale(0.04, 0.26), UDim2.fromScale(0.92, 0.075))
	local swatchLayout = Kit.List(swatches, 0.0055, true)
	swatchLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	for i, hex in Crews.Colors do
		local swatch = Instance.new("TextButton")
		swatch.Name = "Swatch" .. i
		swatch.LayoutOrder = i
		swatch.Text = ""
		swatch.AutoButtonColor = false
		swatch.Size = UDim2.fromScale(0.078, 1)
		swatch.BackgroundColor3 = Color3.fromHex(hex)
		Kit.Aspect(swatch, 1)
		Kit.Corner(swatch, 0.25)
		Kit.InkStroke(swatch, if i == state.Color then 4 else 2, if i == state.Color then UITheme.Paper else UITheme.PanelStroke)
		swatch.Parent = swatches
		swatch.Activated:Connect(function()
			state.Color = i
			render()
		end)
	end

	Kit.Label("EmblemLabel", panel, "EMBLEM", UDim2.fromScale(0.04, 0.35), UDim2.fromScale(0.5, 0.045), "BodyBold", UITheme.Muted, 18, Enum.TextXAlignment.Left)
	local grid = Kit.Frame("Emblems", panel, UDim2.fromScale(0.04, 0.4), UDim2.fromScale(0.92, 0.34))
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromScale(0.094, 0.22)
	gridLayout.CellPadding = UDim2.fromScale(0.006, 0.04)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid
	local selectedColor = Crews.Colors[state.Color] or UITheme.Sakura
	for i, emblem in Crews.Emblems do
		local selected = i == state.Emblem
		local cell = Instance.new("TextButton")
		cell.Name = "Emblem" .. i
		cell.LayoutOrder = i
		cell.AutoButtonColor = false
		cell.Text = emblem
		cell.Font = UITheme.Fonts.BodyBold
		cell.TextScaled = true
		cell.TextColor3 = Color3.fromHex(if selected then UITheme.Ink else selectedColor)
		cell.BackgroundColor3 = Color3.fromHex(if selected then selectedColor else UITheme.Panel)
		Kit.Corner(cell, 0.2)
		Kit.InkStroke(cell, if selected then 3 else 1.5, if selected then UITheme.Paper else UITheme.PanelStroke)
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0.12, 0)
		pad.PaddingBottom = UDim.new(0.12, 0)
		pad.Parent = cell
		cell.Parent = grid
		cell.Activated:Connect(function()
			state.Emblem = i
			render()
		end)
	end

	local preview = Kit.Label(
		"Preview",
		panel,
		"",
		UDim2.fromScale(0.04, 0.76),
		UDim2.fromScale(0.92, 0.06),
		"BodyBold",
		UITheme.Paper,
		22,
		Enum.TextXAlignment.Left
	)
	local cost = Economy.CrewCreateCost
	local function updatePreview()
		local name = if state.Name ~= "" then esc(state.Name) else "Your Crew"
		preview.Text = string.format(
			'<font color="%s">%s %s</font>   <font color="%s">Cost ¥%s</font>',
			selectedColor,
			Crews.Emblems[state.Emblem] or "",
			name,
			UITheme.Gold,
			commas(cost)
		)
	end
	updatePreview()
	box:GetPropertyChangedSignal("Text"):Connect(function()
		local length = utf8.len(box.Text)
		local cut = utf8.offset(box.Text, Crews.NameMax + 1)
		if length and length > Crews.NameMax and cut then
			box.Text = box.Text:sub(1, cut - 1)
			return -- the Text change fires this handler again
		end
		state.Name = box.Text
		updatePreview()
	end)

	local rank, yen = myRank(), myYen()
	local text, style = "CREATE CREW", "Sakura"
	if rank < Crews.MinRank then
		local title = Ranks.List[Crews.MinRank] and Ranks.List[Crews.MinRank].Title or ""
		text, style = string.format("RANK %d (%s) NEEDED", Crews.MinRank, string.upper(title)), "Disabled"
	elseif yen < cost then
		text, style = "NEED ¥" .. commas(cost - yen) .. " MORE", "Disabled"
	elseif state.Busy then
		text, style = "...", "Disabled"
	end
	smallButton(panel, text, style, UDim2.fromScale(0.15, 0.85), UDim2.fromScale(0.7, 0.11), function()
		local name = state.Name:gsub("^%s+", ""):gsub("%s+$", "")
		local length = utf8.len(name) or #name
		if length < Crews.NameMin or length > Crews.NameMax then
			setStatus(string.format("Names are %d to %d characters.", Crews.NameMin, Crews.NameMax), false)
			return
		end
		act("Create", { Name = name, Color = state.Color, Emblem = state.Emblem })
	end)

	-- Crews in this server
	local list = section(root, "ServerCrews", UDim2.fromScale(0.59, 0), UDim2.fromScale(0.41, 1))
	Kit.Label("Title", list, "CREWS HERE", UDim2.fromScale(0.05, 0.015), UDim2.fromScale(0.6, 0.08), "Title", UITheme.Sakura, 40, Enum.TextXAlignment.Left)
	smallButton(list, "↻", "Ghost", UDim2.fromScale(0.8, 0.02), UDim2.fromScale(0.15, 0.07), fetchServerCrews)
	local rows = scroll(list, "Rows", UDim2.fromScale(0.03, 0.11), UDim2.fromScale(0.94, 0.87))
	if #state.ServerCrews == 0 then
		local empty = Kit.Label("Empty", rows, "No crews in this server yet. Start one!", UDim2.new(), UDim2.fromScale(0.95, 0.1), "Body", UITheme.Muted, 20)
		empty.LayoutOrder = 1
	end
	for i, crew in state.ServerCrews do
		local r = row(rows, "Crew" .. i, i, 4.2)
		Kit.Label("Emblem", r, esc(crew.Emblem or ""), UDim2.fromScale(0.02, 0.1), UDim2.fromScale(0.15, 0.8), "BodyBold", crew.Color or UITheme.Sakura, 48)
		Kit.Label("Name", r, esc(crew.Name or "?"), UDim2.fromScale(0.19, 0.1), UDim2.fromScale(0.46, 0.46), "BodyBold", crew.Color or UITheme.Paper, 22, Enum.TextXAlignment.Left)
		Kit.Label(
			"Count",
			r,
			string.format("%d/%d members · %d here", crew.Members or 0, crew.MaxMembers or Crews.MaxMembers, crew.Online or 0),
			UDim2.fromScale(0.19, 0.56),
			UDim2.fromScale(0.46, 0.34),
			"Body",
			UITheme.Muted,
			16,
			Enum.TextXAlignment.Left
		)
		local label, buttonStyle = "REQUEST", "Sakura"
		if crew.Full then
			label, buttonStyle = string.format("FULL (%d/%d)", crew.MaxMembers or Crews.MaxMembers, crew.MaxMembers or Crews.MaxMembers), "Disabled"
		elseif rank < Crews.MinRank then
			label, buttonStyle = "RANK " .. Crews.MinRank, "Disabled"
		end
		smallButton(r, label, buttonStyle, UDim2.fromScale(0.67, 0.18), UDim2.fromScale(0.31, 0.64), function()
			act("RequestJoin", { CrewId = crew.Id })
		end)
	end
end

-- In a crew ------------------------------------------------------------------------------------

local function renderCrew(root: Frame, summary: any)
	local myRole = summary.MyRole or "Member"
	local isLeader = myRole == "Leader"
	local isOfficer = isLeader or myRole == "Lieutenant"
	local crewColor = summary.Color or UITheme.Sakura

	-- Header
	local header = section(root, "Header", UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.17))
	local headerStroke = header:FindFirstChildOfClass("UIStroke")
	if headerStroke then
		headerStroke.Color = Color3.fromHex(UITheme.Sakura)
	end
	local emblem = Kit.Label("Emblem", header, esc(summary.Emblem or ""), UDim2.fromScale(0.01, 0.06), UDim2.fromScale(0.09, 0.88), "BodyBold", crewColor, 64)
	Kit.TextStroke(emblem, 2)
	Kit.Label("Name", header, esc(summary.Name or ""), UDim2.fromScale(0.11, 0.05), UDim2.fromScale(0.6, 0.5), "Title", crewColor, 48, Enum.TextXAlignment.Left)
	local turfNames = {}
	for _, turfId in summary.TurfsHeld or {} do
		table.insert(turfNames, Crews.TurfNames[turfId] or tostring(turfId))
	end
	Kit.Label(
		"Stats",
		header,
		string.format(
			"Members <b>%d/%d</b>  ·  Weekly Rep <b>%s</b>  ·  Turf <b>%s</b>",
			#(summary.Members or {}),
			summary.MaxMembers or Crews.MaxMembers,
			commas(summary.WeeklyRep or 0),
			if #turfNames > 0 then esc(table.concat(turfNames, ", ")) else "none"
		),
		UDim2.fromScale(0.11, 0.58),
		UDim2.fromScale(0.87, 0.36),
		"Body",
		UITheme.Paper,
		20,
		Enum.TextXAlignment.Left
	)
	local badge = Kit.Label("MyRole", header, string.upper(myRole), UDim2.fromScale(0.78, 0.08), UDim2.fromScale(0.2, 0.36), "Button", ROLE_COLORS[myRole] or UITheme.Muted, 24, Enum.TextXAlignment.Right)
	badge.Name = "MyRole"

	-- Roster
	local rosterPanel = section(root, "Roster", UDim2.fromScale(0, 0.19), UDim2.fromScale(0.6, 0.81))
	Kit.Label("Title", rosterPanel, "ROSTER", UDim2.fromScale(0.04, 0.015), UDim2.fromScale(0.5, 0.08), "Title", UITheme.Sakura, 36, Enum.TextXAlignment.Left)
	local roster = scroll(rosterPanel, "Rows", UDim2.fromScale(0.02, 0.11), UDim2.fromScale(0.96, 0.87))
	for i, member in summary.Members or {} do
		local r = row(roster, "Member" .. i, i, 7.5)
		local dot = Kit.Frame("Online", r, UDim2.fromScale(0.02, 0.5), UDim2.fromScale(0.03, 0.3), if member.Online then ONLINE else OFFLINE, Vector2.new(0, 0.5))
		Kit.Aspect(dot, 1)
		Kit.Corner(dot, 1)
		local isMe = member.UserId == localPlayer.UserId
		Kit.Label("Name", r, esc(member.Name) .. (if isMe then " (you)" else ""), UDim2.fromScale(0.07, 0.15), UDim2.fromScale(0.38, 0.7), "BodyBold", if member.Online then UITheme.Paper else UITheme.Muted, 22, Enum.TextXAlignment.Left)
		local roleColor = ROLE_COLORS[member.Role] or UITheme.Muted
		local pill = Kit.Frame("Role", r, UDim2.fromScale(0.46, 0.2), UDim2.fromScale(0.18, 0.6), UITheme.Ink)
		Kit.Corner(pill, 0.5)
		Kit.InkStroke(pill, 2, roleColor)
		Kit.Label("Text", pill, string.upper(member.Role or ""), UDim2.fromScale(0.05, 0.1), UDim2.fromScale(0.9, 0.8), "Button", roleColor, 16)

		if not isMe and isOfficer then
			local buttons: { { Text: string, Style: string, Action: string, Confirm: boolean } } = {}
			if isLeader then
				if member.Role == "Member" then
					table.insert(buttons, { Text = "▲", Style = "Success", Action = "Promote", Confirm = false })
				elseif member.Role == "Lieutenant" then
					table.insert(buttons, { Text = "♛", Style = "Premium", Action = "Promote", Confirm = true })
					table.insert(buttons, { Text = "▼", Style = "Secondary", Action = "Demote", Confirm = false })
				end
				table.insert(buttons, { Text = "KICK", Style = "Primary", Action = "Kick", Confirm = true })
			elseif member.Role == "Member" then
				table.insert(buttons, { Text = "KICK", Style = "Primary", Action = "Kick", Confirm = true })
			end
			local x = 0.99
			for j = #buttons, 1, -1 do
				local spec = buttons[j]
				local width = if spec.Text == "KICK" then 0.13 else 0.08
				x -= width + 0.01
				local confirmKey = spec.Action .. ":" .. tostring(member.UserId)
				local text = if spec.Confirm and confirming(confirmKey) then "SURE?" else spec.Text
				local style = if state.Busy then "Disabled" else spec.Style
				smallButton(r, text, style, UDim2.fromScale(x, 0.15), UDim2.fromScale(width, 0.7), function()
					if spec.Confirm and not confirm(confirmKey) then
						return
					end
					act(spec.Action, { UserId = member.UserId })
				end)
			end
		end
	end

	-- Requests + invites
	local side = section(root, "Side", UDim2.fromScale(0.62, 0.19), UDim2.fromScale(0.38, 0.81))
	Kit.Label("Title", side, "RECRUIT", UDim2.fromScale(0.05, 0.015), UDim2.fromScale(0.6, 0.08), "Title", UITheme.Sakura, 36, Enum.TextXAlignment.Left)
	local list = scroll(side, "Rows", UDim2.fromScale(0.03, 0.11), UDim2.fromScale(0.94, 0.72))
	local order = 0
	local function heading(text: string)
		order += 1
		local h = Kit.Label("Heading" .. order, list, text, UDim2.new(), UDim2.fromScale(0.95, 0.07), "BodyBold", UITheme.Muted, 18, Enum.TextXAlignment.Left)
		h.LayoutOrder = order
	end

	if not isOfficer then
		heading("Only the leader and lieutenants can invite or accept requests.")
	else
		local full = #(summary.Members or {}) >= (summary.MaxMembers or Crews.MaxMembers)
		local pending = summary.Requests or {}
		if #pending > 0 then
			heading("JOIN REQUESTS")
			for _, request in pending do
				order += 1
				local r = row(list, "Request" .. order, order, 4.5)
				Kit.Label("Name", r, esc(request.Name), UDim2.fromScale(0.04, 0.15), UDim2.fromScale(0.56, 0.7), "BodyBold", UITheme.Paper, 20, Enum.TextXAlignment.Left)
				smallButton(r, if full then "FULL" else "ACCEPT", if full or state.Busy then "Disabled" else "Success", UDim2.fromScale(0.62, 0.15), UDim2.fromScale(0.35, 0.7), function()
					act("AcceptRequest", { UserId = request.UserId })
				end)
			end
		end
		heading("INVITE PLAYERS HERE")
		local any = false
		for _, other in Players:GetPlayers() do
			local crewId = other:GetAttribute("CrewId")
			if other ~= localPlayer and (crewId == nil or crewId == "") then
				any = true
				order += 1
				local rank = other:GetAttribute("Rank")
				local rankNumber = if type(rank) == "number" then rank else 1
				local entry = Ranks.List[rankNumber] or Ranks.List[1]
				local r = row(list, "Invite" .. order, order, 4.5)
				Kit.Label("Name", r, esc(other.DisplayName), UDim2.fromScale(0.04, 0.08), UDim2.fromScale(0.56, 0.5), "BodyBold", UITheme.Paper, 20, Enum.TextXAlignment.Left)
				Kit.Label("Rank", r, entry.Title, UDim2.fromScale(0.04, 0.56), UDim2.fromScale(0.56, 0.36), "Body", entry.Color, 16, Enum.TextXAlignment.Left)
				local text, style = "INVITE", "Sakura"
				if rankNumber < Crews.MinRank then
					text, style = "RANK " .. Crews.MinRank, "Disabled"
				elseif full then
					text, style = "FULL", "Disabled"
				elseif state.Busy then
					style = "Disabled"
				end
				smallButton(r, text, style, UDim2.fromScale(0.62, 0.15), UDim2.fromScale(0.35, 0.7), function()
					act("Invite", { UserId = other.UserId })
				end)
			end
		end
		if not any then
			heading("Everyone here is already in a crew.")
		end
	end

	-- Leave / Disband
	local leaveText = if confirming("Leave") then "SURE?" else "LEAVE"
	local leaveSize = if isLeader then UDim2.fromScale(0.44, 0.11) else UDim2.fromScale(0.9, 0.11)
	smallButton(side, leaveText, if state.Busy then "Disabled" else "Secondary", UDim2.fromScale(0.05, 0.86), leaveSize, function()
		if confirm("Leave") then
			act("Leave")
		end
	end)
	if isLeader then
		local disbandText = if confirming("Disband") then "SURE?" else "DISBAND"
		smallButton(side, disbandText, if state.Busy then "Disabled" else "Primary", UDim2.fromScale(0.51, 0.86), UDim2.fromScale(0.44, 0.11), function()
			if confirm("Disband") then
				act("Disband", nil, fetchServerCrews)
			end
		end)
	end
end

function render()
	local root = content
	if not root then
		return
	end
	Kit.ClearChildren(root)
	local summary = getSummary()
	if summary then
		renderCrew(root, summary)
	else
		renderCreate(root)
	end
end

-- Screen contract ----------------------------------------------------------------------------

function Screen.Build(playerGui: Instance, controllers: any): Kit.Window
	Controllers = controllers
	local window = Kit.Window(playerGui, "Crew", "CREW", UDim2.fromScale(0.9, 0.86))
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MaxSize = Vector2.new(1100, 720)
	sizeLimit.Parent = window.Root
	-- Sakura header for the social app
	local gradient = window.Header:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient.Color = ColorSequence.new(Color3.fromHex(UITheme.Buttons.Sakura[1]), Color3.fromHex(UITheme.Buttons.Sakura[2]))
	end

	content = Kit.Frame("Content", window.Body, UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.92))
	statusLabel = Kit.Label("Status", window.Body, "", UDim2.fromScale(0, 0.93), UDim2.fromScale(1, 0.07), "BodyBold", UITheme.Muted, 20)
	currentWindow = window

	local crewController = controllers.CrewController
	if crewController and crewController.Changed then
		crewController.Changed:Connect(function(summary: any?)
			if isOpen() then
				if summary == nil then
					fetchServerCrews()
				end
				render()
			end
		end)
	end
	local function onRoster()
		if isOpen() then
			task.defer(render)
		end
	end
	Players.PlayerAdded:Connect(onRoster)
	Players.PlayerRemoving:Connect(onRoster)
	return window
end

function Screen.Open(_window: Kit.Window, _data: any?)
	state.Confirm = nil
	setStatus("", nil)
	render()
	if getSummary() == nil then
		fetchServerCrews()
	end
end

return Screen
