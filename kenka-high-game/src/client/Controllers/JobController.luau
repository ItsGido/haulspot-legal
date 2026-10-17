--!strict
-- Job HUD (blueprint section 6.4): job name, objective and timer, a waypoint beam from the character
-- to the current ramen drop or the nearest arcade token, the Konbini Shift rhythm minigame and a
-- cancel button. Server payloads are documented at the top of JobService.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local UITheme = require(ReplicatedStorage.Shared.Config.UITheme)
local Format = require(ReplicatedStorage.Shared.Logic.Format)
local Net = require(ReplicatedStorage.Shared.Util.Net)
local Kit = require(script.Parent.Parent.UI.Kit)

local JobController = {}

local player = Players.LocalPlayer

-- Konbini minigame feel (client-only presentation; the server checks counts and duration).
local NOTE_LEAD = 2 -- seconds before the first note reaches the line
local NOTE_JITTER = 0.3 -- fraction of the spacing each note may shift
local FALL_TIME = 1.6 -- seconds a note takes to fall from the top to the hit line
local HIT_WINDOW = 0.16 -- seconds either side of the line that count as a hit
local STRAY_WINDOW = 0.5 -- a press with no note in range ruins the next note within this many seconds
local HIT_LINE = 0.85 -- hit line height inside the lane (fraction from the top)
local SUBMIT_DELAY = 0.5
local RESULT_SECONDS = 4
local BEAM_COLOR = "#FFE066"

type JobState = {
	JobId: string,
	Name: string,
	EndsAt: number,
	Data: any,
}

local current: JobState? = nil
local hud: ScreenGui
local hudPanel: Frame
local nameLabel: TextLabel
local objectiveLabel: TextLabel
local timerLabel: TextLabel
local cancelButton: TextButton
local hideToken = 0

-- Waypoint -------------------------------------------------------------------------------

local waypointPart: Part? = nil
local waypointAttachment: Attachment? = nil
local beacon: Part? = nil
local beam: Beam? = nil

local function ensureWaypoint()
	if waypointPart then
		return
	end
	local part = Instance.new("Part")
	part.Name = "EconomyJobWaypoint"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Parent = workspace.CurrentCamera
	local attachment = Instance.new("Attachment")
	attachment.Parent = part
	local column = Instance.new("Part")
	column.Name = "EconomyJobBeacon"
	column.Anchored = true
	column.CanCollide = false
	column.CanQuery = false
	column.CanTouch = false
	column.Material = Enum.Material.Neon
	column.Color = Color3.fromHex(BEAM_COLOR)
	column.Transparency = 0.45
	column.Shape = Enum.PartType.Cylinder
	column.Size = Vector3.new(40, 1.2, 1.2)
	column.Parent = workspace.CurrentCamera
	local newBeam = Instance.new("Beam")
	newBeam.Name = "EconomyJobBeam"
	newBeam.Attachment1 = attachment
	newBeam.Color = ColorSequence.new(Color3.fromHex(BEAM_COLOR))
	newBeam.LightEmission = 1
	newBeam.FaceCamera = true
	newBeam.Width0 = 0.5
	newBeam.Width1 = 0.5
	newBeam.Segments = 12
	newBeam.Transparency = NumberSequence.new(0.35)
	newBeam.Parent = part
	waypointPart, waypointAttachment, beacon, beam = part, attachment, column, newBeam
end

local function hideWaypoint()
	if beam then
		beam.Enabled = false
	end
	if beacon then
		beacon.Transparency = 1
	end
end

local function showWaypoint(target: Vector3)
	ensureWaypoint()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") or not waypointPart or not beam or not beacon then
		hideWaypoint()
		return
	end
	local from = root:FindFirstChild("EconomyJobBeamAttachment")
	if not from then
		local created = Instance.new("Attachment")
		created.Name = "EconomyJobBeamAttachment"
		created.Parent = root
		from = created
	end
	beam.Attachment0 = from :: Attachment
	beam.Enabled = true
	waypointPart.Position = target
	beacon.CFrame = CFrame.new(target + Vector3.new(0, 20, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	beacon.Transparency = 0.45
	local _ = waypointAttachment
end

local function currentTarget(state: JobState): Vector3?
	local data = state.Data
	if type(data) ~= "table" then
		return nil
	end
	if state.JobId == "RamenDelivery" and type(data.Drops) == "table" then
		return data.Drops[data.Index or 1]
	end
	if state.JobId == "ArcadeAttendant" and type(data.Tokens) == "table" then
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local origin = if root and root:IsA("BasePart") then root.Position else Vector3.zero
		local best: Vector3? = nil
		local bestDistance = math.huge
		for _, position in data.Tokens do
			if typeof(position) == "Vector3" then
				local distance = (position - origin).Magnitude
				if distance < bestDistance then
					best, bestDistance = position, distance
				end
			end
		end
		return best
	end
	return nil
end

-- HUD -------------------------------------------------------------------------------------

local function buildHud()
	local gui = Instance.new("ScreenGui")
	gui.Name = "JobHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 5
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")
	hud = gui

	hudPanel = Kit.Panel("JobPanel", gui, UDim2.fromScale(0.5, 0.11), UDim2.fromScale(0.36, 0.12), Vector2.new(0.5, 0))
	Kit.Padding(hudPanel, 0.04)
	nameLabel = Kit.Label("JobName", hudPanel, "JOB", UDim2.fromScale(0, 0), UDim2.fromScale(0.62, 0.45), "Title", UITheme.Gold, 30, Enum.TextXAlignment.Left)
	timerLabel = Kit.Label("Timer", hudPanel, "0:00", UDim2.fromScale(0.62, 0), UDim2.fromScale(0.16, 0.45), "Number", UITheme.Paper, 28)
	objectiveLabel = Kit.Label("Objective", hudPanel, "", UDim2.fromScale(0, 0.5), UDim2.fromScale(0.78, 0.5), "Body", UITheme.Paper, 20, Enum.TextXAlignment.Left)
	cancelButton = Kit.Button(hudPanel, "QUIT", "Ghost", UDim2.fromScale(1, 0.5), UDim2.fromScale(0.2, 0.8), Vector2.new(1, 0.5))
	cancelButton.Activated:Connect(function()
		Net.Event("Job_Cancel"):FireServer()
	end)
end

local function objectiveText(state: JobState): string
	local data = state.Data or {}
	if state.JobId == "RamenDelivery" then
		local total = if type(data.Drops) == "table" then #data.Drops else Economy.RamenDropsPerRun
		return string.format("Deliver bowl %d/%d · follow the beam", math.min(data.Index or 1, total), total)
	elseif state.JobId == "ArcadeAttendant" then
		return string.format("Collect tokens: %d/%d", data.Collected or 0, data.Total or Economy.ArcadeTokensPerRun)
	elseif state.JobId == "KonbiniShift" then
		return "Scan items to the beat! (Space / tap SCAN)"
	end
	return ""
end

local function refreshHud()
	local state = current
	if not state then
		return
	end
	hideToken += 1
	hud.Enabled = true
	nameLabel.Text = state.Name
	nameLabel.TextColor3 = Kit.Hex(UITheme.Gold)
	objectiveLabel.Text = objectiveText(state)
	cancelButton.Visible = true
end

local function showResult(title: string, text: string, color: string)
	hideToken += 1
	local token = hideToken
	hud.Enabled = true
	nameLabel.Text = title
	nameLabel.TextColor3 = Kit.Hex(color)
	objectiveLabel.Text = text
	timerLabel.Text = ""
	cancelButton.Visible = false
	task.delay(RESULT_SECONDS, function()
		if hideToken == token and not current then
			hud.Enabled = false
		end
	end)
end

-- Konbini rhythm minigame ---------------------------------------------------------------

type Note = { Time: number, Frame: Frame, Judged: boolean }

local game_: {
	Gui: ScreenGui,
	Lane: Frame,
	Stats: TextLabel,
	Feedback: TextLabel,
	Notes: { Note },
	Start: number,
	Hits: number,
	Misses: number,
	Done: boolean,
	Connection: RBXScriptConnection?,
}? = nil

local function endMinigame()
	local g = game_
	if not g then
		return
	end
	game_ = nil
	if g.Connection then
		g.Connection:Disconnect()
	end
	ContextActionService:UnbindAction("EconomyKonbiniHit")
	g.Gui:Destroy()
end

local function flash(text: string, color: string)
	local g = game_
	if not g then
		return
	end
	g.Feedback.Text = text
	g.Feedback.TextColor3 = Kit.Hex(color)
	g.Feedback.TextTransparency = 0
	TweenService:Create(g.Feedback, TweenInfo.new(0.35), { TextTransparency = 1 }):Play()
end

local function judge(note: Note, hit: boolean)
	local g = game_
	if not g or note.Judged then
		return
	end
	note.Judged = true
	note.Frame.Visible = false
	if hit then
		g.Hits += 1
		flash("SCAN!", UITheme.Buttons.Success[1])
		Kit.PlaySound("Click")
	else
		g.Misses += 1
		flash("MISS", UITheme.Buttons.Primary[1])
	end
	g.Stats.Text = string.format("Scanned %d · Missed %d", g.Hits, g.Misses)
end

local function press()
	local g = game_
	if not g or g.Done then
		return
	end
	local t = os.clock() - g.Start
	for _, note in g.Notes do
		if not note.Judged and math.abs(note.Time - t) <= HIT_WINDOW then
			judge(note, true)
			return
		end
	end
	-- Stray press: spamming costs the next customer.
	for _, note in g.Notes do
		if not note.Judged and note.Time - t > 0 and note.Time - t <= STRAY_WINDOW then
			judge(note, false)
			return
		end
	end
end

local function startMinigame(data: any)
	endMinigame()
	local noteCount = if type(data.Notes) == "number" then math.clamp(math.floor(data.Notes), 1, 200) else 40
	local seconds = if type(data.Seconds) == "number" then math.clamp(data.Seconds, 10, 300) else 60

	local gui = Instance.new("ScreenGui")
	gui.Name = "KonbiniGame"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 12
	gui.Parent = player:WaitForChild("PlayerGui")

	local panel = Kit.Panel("Register", gui, UDim2.fromScale(0.5, 0.6), UDim2.fromScale(0.3, 0.62), Vector2.new(0.5, 0.5))
	Kit.Aspect(panel, 0.62)
	Kit.Label("Title", panel, "KONBINI REGISTER", UDim2.fromScale(0.05, 0.02), UDim2.fromScale(0.9, 0.08), "Title", UITheme.Paper, 36)
	local lane = Kit.Frame("Lane", panel, UDim2.fromScale(0.2, 0.11), UDim2.fromScale(0.6, 0.6), UITheme.PanelLight)
	Kit.Corner(lane, 0.08)
	Kit.InkStroke(lane, 2)
	lane.ClipsDescendants = true
	local line = Kit.Frame("HitLine", lane, UDim2.fromScale(0, HIT_LINE), UDim2.fromScale(1, 0.025), UITheme.Buttons.Primary[1], Vector2.new(0, 0.5))
	line.ZIndex = 2
	local stats = Kit.Label("Stats", panel, "Scanned 0 · Missed 0", UDim2.fromScale(0.05, 0.72), UDim2.fromScale(0.9, 0.06), "BodyBold", UITheme.Paper, 20)
	local feedback = Kit.Label("Feedback", lane, "", UDim2.fromScale(0, 0.6), UDim2.fromScale(1, 0.15), "Title", UITheme.Paper, 40)
	feedback.ZIndex = 3
	local scan = Kit.Button(panel, "SCAN", "Success", UDim2.fromScale(0.1, 0.79), UDim2.fromScale(0.8, 0.13))
	Kit.Label("Hint", panel, "Space · click · tap when the item hits the red line", UDim2.fromScale(0.05, 0.93), UDim2.fromScale(0.9, 0.05), "Body", UITheme.Muted, 16)

	local rng = Random.new()
	local spacing = (seconds - NOTE_LEAD - 1) / math.max(1, noteCount - 1)
	local notes: { Note } = {}
	local itemColors = { "#FFD23F", "#3FA7FF", "#FF9EC4", "#5FE08A" }
	for i = 1, noteCount do
		local jitter = if i == 1 or i == noteCount then 0 else rng:NextNumber(-NOTE_JITTER, NOTE_JITTER) * spacing
		local frame = Kit.Frame("Item" .. i, lane, UDim2.fromScale(0.5, -0.1), UDim2.fromScale(0.7, 0.07), itemColors[(i % #itemColors) + 1], Vector2.new(0.5, 0.5))
		Kit.Corner(frame, 0.3)
		Kit.InkStroke(frame, 2)
		frame.Visible = false
		table.insert(notes, { Time = NOTE_LEAD + (i - 1) * spacing + jitter, Frame = frame, Judged = false })
	end

	local g = {
		Gui = gui,
		Lane = lane,
		Stats = stats,
		Feedback = feedback,
		Notes = notes,
		Start = os.clock(),
		Hits = 0,
		Misses = 0,
		Done = false,
		Connection = nil :: RBXScriptConnection?,
	}
	game_ = g
	scan.Activated:Connect(press)
	ContextActionService:BindActionAtPriority("EconomyKonbiniHit", function(_name, state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			press()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Space, Enum.KeyCode.ButtonA, Enum.KeyCode.ButtonR2)

	g.Connection = RunService.RenderStepped:Connect(function()
		if game_ ~= g then
			return
		end
		local t = os.clock() - g.Start
		local pending = 0
		for _, note in g.Notes do
			if not note.Judged then
				pending += 1
				local untilHit = note.Time - t
				if untilHit < -HIT_WINDOW then
					judge(note, false)
				elseif untilHit <= FALL_TIME then
					note.Frame.Visible = true
					note.Frame.Position = UDim2.fromScale(0.5, HIT_LINE * (1 - untilHit / FALL_TIME))
				end
			end
		end
		if pending == 0 and not g.Done then
			g.Done = true
			local duration = os.clock() - g.Start
			task.delay(SUBMIT_DELAY, function()
				if game_ == g then
					Net.Event("Job_Submit"):FireServer("KonbiniShift", { Hits = g.Hits, Misses = g.Misses, Duration = duration + SUBMIT_DELAY })
					endMinigame()
				end
			end)
		end
	end)
end

-- Server updates ------------------------------------------------------------------------

local function onJobUpdate(payload: any)
	if type(payload) ~= "table" or type(payload.JobId) ~= "string" then
		return
	end
	local config = (Economy.Jobs :: any)[payload.JobId]
	local name = if config then config.Name else payload.JobId
	local data = if type(payload.Data) == "table" then payload.Data else {}
	if payload.State == "Started" then
		current = { JobId = payload.JobId, Name = name, EndsAt = data.EndsAt or 0, Data = data }
		refreshHud()
		if payload.JobId == "KonbiniShift" then
			startMinigame(data)
		end
	elseif payload.State == "Progress" then
		local state = current
		if state and state.JobId == payload.JobId then
			for key, value in data do
				state.Data[key] = value
			end
			refreshHud()
		end
	elseif payload.State == "Finished" then
		current = nil
		endMinigame()
		hideWaypoint()
		showResult(
			if data.Gold then "GOLD SHIFT!" else "SHIFT DONE!",
			"+" .. Format.Yen(tonumber(data.Pay) or 0) .. (if data.Gold then " · gold bonus" else ""),
			if data.Gold then UITheme.Gold else UITheme.Buttons.Success[1]
		)
		Kit.PlaySound("Purchase")
	elseif payload.State == "Cancelled" then
		current = nil
		endMinigame()
		hideWaypoint()
		showResult("JOB CANCELLED", tostring(data.Reason or ""), UITheme.Buttons.Primary[1])
	end
end

function JobController.GetActiveJob(): string?
	return if current then current.JobId else nil
end

function JobController.Init(_controllers: any)
	Net.Event("Job_Update").OnClientEvent:Connect(onJobUpdate)
end

function JobController.Start()
	buildHud()
	RunService.Heartbeat:Connect(function()
		local state = current
		if not state then
			return
		end
		timerLabel.Text = Format.Duration(state.EndsAt - workspace:GetServerTimeNow())
		local target = currentTarget(state)
		if target then
			showWaypoint(target)
		else
			hideWaypoint()
		end
	end)
end

return JobController
