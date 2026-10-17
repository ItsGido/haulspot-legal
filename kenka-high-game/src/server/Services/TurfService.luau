--!strict
-- Turf war (blueprint 1.8 After School, the turf walls of section 3 and the turf rows of section 8).
--
-- During After School (DayCycleService.IsTurfWar) every second, for each turf wall:
--   * count living, non-downed, non-AFK crew members within Crews.CaptureRadius, grouped by crew
--   * one crew (not the owner)      -> progress += 100 / CaptureSeconds x min(members, CaptureMaxMultiplier)
--     (if another crew had progress, it is pushed back to 0 first; the owner alone pushes progress back)
--   * two or more crews             -> contested: paused, the wall flashes both colors
--   * nobody                        -> progress decays by CaptureDecayPerSecond
-- At 100 the crew owns the turf until the next After School begins. Owning crews earn
-- Economy.TurfIncomePerMinute per turf for every online, active member.
-- Turf_Update is broadcast every second during the war and on any change otherwise.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Crews = require(ReplicatedStorage.Shared.Config.Crews)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Ranks = require(ReplicatedStorage.Shared.Config.Ranks)
local UITheme = require(ReplicatedStorage.Shared.Config.UITheme)
local MapData = require(ReplicatedStorage.Shared.Map.MapData)
local Net = require(ReplicatedStorage.Shared.Util.Net)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Notify = require(script.Parent.Parent.Systems.Notify)

local TurfService = {}
TurfService.Priority = 45

TurfService.OwnershipChanged = Signal.new() -- (turfId, newCrewId?, oldCrewId?)

local TICK = 1
local ACTIVE_WINDOW = 120 -- seconds without moving or acting before a player counts as AFK
local MOVE_EPSILON = 0.5 -- studs

type Turf = {
	Id: string,
	Name: string,
	Position: Vector3,
	Wall: BasePart?,
	BaseColor: Color3,
	Owner: string?,
	OwnerName: string?,
	OwnerColor: string?,
	OwnerEmblem: string?,
	Capturing: string?,
	CapturingName: string?,
	CapturingColor: string?,
	Progress: number,
	Contested: boolean,
	ContestColors: { string },
	StatusLabel: TextLabel?,
	StatusBar: Frame?,
}

local Services: any
local turfs: { [string]: Turf } = {}
local lastPosition: { [Player]: Vector3 } = {}
local lastActive: { [Player]: number } = {}
local turfUpdate = Net.Event("Turf_Update")
local wasWar = false
local dirty = false
local flash = false

-- Helpers -----------------------------------------------------------------------------

local function crewOf(player: Player): string?
	local crewService = Services.CrewService
	if crewService and crewService.GetCrewId then
		return crewService.GetCrewId(player)
	end
	return nil
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function isActive(player: Player): boolean
	return os.clock() - (lastActive[player] or 0) <= ACTIVE_WINDOW
end

local function canCapture(player: Player): boolean
	local character = player.Character
	if not character then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end
	if character:GetAttribute("Downed") == true then
		return false
	end
	local combat = Services.CombatService
	if combat and combat.IsDowned then
		local ok, downed = pcall(combat.IsDowned, player)
		if ok and downed then
			return false
		end
	end
	return isActive(player)
end

local function crewLook(members: { Player }): (string, string, string)
	-- Read the crew's display from a member's attributes (set by CrewService).
	for _, member in members do
		local name = member:GetAttribute("CrewName")
		if type(name) == "string" then
			local color = member:GetAttribute("CrewColor")
			local emblem = member:GetAttribute("CrewEmblem")
			return name, if type(color) == "string" then color else UITheme.Sakura, if type(emblem) == "string" then emblem else ""
		end
	end
	return "A crew", UITheme.Sakura, ""
end

local function safeColor(hex: string?): Color3
	if type(hex) == "string" then
		local ok, color = pcall(Color3.fromHex, hex)
		if ok then
			return color
		end
	end
	return Color3.fromHex(UITheme.Sakura)
end

-- Wall visuals ------------------------------------------------------------------------

local function clearOwnerGui(wall: BasePart)
	for _, child in wall:GetChildren() do
		if child.Name == "TurfOwner" then
			child:Destroy()
		end
	end
end

local function paintWall(turf: Turf)
	local wall = turf.Wall
	if not wall then
		return
	end
	clearOwnerGui(wall)
	if not turf.Owner then
		wall.Color = turf.BaseColor
		return
	end
	wall.Color = safeColor(turf.OwnerColor)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Name = "TurfOwner"
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 20
		gui.LightInfluence = 0
		local emblem = Instance.new("TextLabel")
		emblem.BackgroundTransparency = 1
		emblem.Size = UDim2.fromScale(0.3, 0.9)
		emblem.Position = UDim2.fromScale(0.03, 0.05)
		emblem.Text = turf.OwnerEmblem or ""
		emblem.Font = UITheme.Fonts.BodyBold
		emblem.TextScaled = true
		emblem.TextColor3 = Color3.fromHex(UITheme.Paper)
		emblem.TextStrokeTransparency = 0
		emblem.Parent = gui
		local name = Instance.new("TextLabel")
		name.BackgroundTransparency = 1
		name.Size = UDim2.fromScale(0.64, 0.6)
		name.Position = UDim2.fromScale(0.34, 0.2)
		name.Text = string.upper(turf.OwnerName or "")
		name.Font = UITheme.Fonts.Title
		name.TextScaled = true
		name.TextColor3 = Color3.fromHex(UITheme.Paper)
		name.TextStrokeTransparency = 0
		name.Parent = gui
		gui.Parent = wall
	end
end

local function buildStatus(turf: Turf)
	local wall = turf.Wall
	if not wall then
		return
	end
	local oldLabel = wall:FindFirstChild("Label")
	if oldLabel and oldLabel:IsA("BillboardGui") then
		oldLabel.Enabled = false -- MapService's greybox label; the status board replaces it
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "TurfStatus"
	gui.Size = UDim2.new(14, 0, 3.6, 0)
	gui.StudsOffset = Vector3.new(0, wall.Size.Y / 2 + 3, 0)
	gui.MaxDistance = 300
	gui.AlwaysOnTop = false
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 0.62)
	label.RichText = true
	label.TextScaled = true
	label.Font = UITheme.Fonts.Button
	label.TextColor3 = Color3.fromHex(UITheme.Paper)
	label.TextStrokeTransparency = 0
	label.Text = turf.Name
	label.Parent = gui
	local back = Instance.new("Frame")
	back.Name = "Bar"
	back.Position = UDim2.fromScale(0.1, 0.7)
	back.Size = UDim2.fromScale(0.8, 0.22)
	back.BackgroundColor3 = Color3.fromHex(UITheme.Ink)
	back.BorderSizePixel = 0
	back.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = back
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = back
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = Color3.fromHex(UITheme.Sakura)
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.5, 0)
	fillCorner.Parent = fill
	fill.Parent = back
	back.Parent = gui
	gui.Parent = wall
	turf.StatusLabel = label
	turf.StatusBar = back
end

local function escape(text: string): string
	return (text:gsub("[<>&]", ""))
end

local function updateStatus(turf: Turf, war: boolean)
	local label, bar = turf.StatusLabel, turf.StatusBar
	if not label or not bar then
		return
	end
	local owner = if turf.Owner
		then string.format('<font color="%s">%s %s</font>', turf.OwnerColor or UITheme.Sakura, turf.OwnerEmblem or "", escape(turf.OwnerName or ""))
		else '<font color="#A9ADBD">Unclaimed</font>'
	local line = turf.Name .. "\n" .. owner
	if war and turf.Contested then
		line = turf.Name .. '\n<font color="#E4322B">CONTESTED</font>'
	elseif war and turf.Capturing then
		line = string.format('%s\n<font color="%s">%s capturing %d%%</font>', turf.Name, turf.CapturingColor or UITheme.Sakura, escape(turf.CapturingName or ""), math.floor(turf.Progress))
	end
	label.Text = line
	bar.Visible = war and turf.Progress > 0
	local fill = bar:FindFirstChild("Fill") :: Frame?
	if fill then
		fill.Size = UDim2.fromScale(math.clamp(turf.Progress / 100, 0, 1), 1)
		fill.BackgroundColor3 = safeColor(turf.CapturingColor)
	end
	-- Contested walls flash both crews' colors.
	local wall = turf.Wall
	if wall then
		if war and turf.Contested and #turf.ContestColors >= 2 then
			wall.Color = safeColor(turf.ContestColors[if flash then 1 else 2])
		elseif turf.Owner then
			wall.Color = safeColor(turf.OwnerColor)
		else
			wall.Color = turf.BaseColor
		end
	end
end

-- State ----------------------------------------------------------------------------------

local function payload(): any
	local list = {}
	for id, turf in turfs do
		list[id] = {
			Name = turf.Name,
			OwnerCrewId = turf.Owner,
			OwnerName = turf.OwnerName,
			OwnerColor = turf.OwnerColor,
			OwnerEmblem = turf.OwnerEmblem,
			CapturingName = turf.CapturingName,
			CapturingColor = turf.CapturingColor,
			Progress = math.floor(turf.Progress * 10) / 10,
			Contested = turf.Contested,
		}
	end
	local active = false
	if Services.DayCycleService then
		active = Services.DayCycleService.IsTurfWar()
	end
	return { Active = active, Turfs = list }
end

local function broadcast()
	dirty = false
	turfUpdate:FireAllClients(payload())
end

local function refreshCrew(crewId: string?)
	local crewService = Services.CrewService
	if crewId and crewService and crewService.BroadcastCrew then
		task.spawn(crewService.BroadcastCrew, crewId)
	end
end

local function setOwner(turf: Turf, crewId: string?, name: string?, color: string?, emblem: string?)
	local old = turf.Owner
	turf.Owner = crewId
	turf.OwnerName = if crewId then name else nil
	turf.OwnerColor = if crewId then color else nil
	turf.OwnerEmblem = if crewId then emblem else nil
	paintWall(turf)
	dirty = true
	if old ~= crewId then
		TurfService.OwnershipChanged:Fire(turf.Id, crewId, old)
		refreshCrew(old)
		refreshCrew(crewId)
	end
end

local function clearCapture(turf: Turf)
	turf.Capturing = nil
	turf.CapturingName = nil
	turf.CapturingColor = nil
	turf.Progress = 0
	turf.Contested = false
	table.clear(turf.ContestColors)
end

local function reward(turf: Turf, crewId: string, members: { Player })
	local total = 0
	for _, member in members do
		if member.Parent == Players then
			local rep = Services.RepService
			if rep and rep.AddRep then
				task.spawn(rep.AddRep, member, Ranks.TurfCaptureReward, "Turf")
				total += Ranks.TurfCaptureReward
			end
			local questService = Services.QuestService
			if questService and questService.Progress then
				task.spawn(questService.Progress, member, "CaptureTurf")
			end
			Services.DataService.Update(member, { "Stats" }, function(profile: any)
				profile.Stats.TurfCaptures = (profile.Stats.TurfCaptures or 0) + 1
			end)
			Notify.Send(member, string.format("You took %s! +%d Rep", turf.Name, Ranks.TurfCaptureReward), "gold")
		end
	end
	local crewService = Services.CrewService
	if crewService and crewService.AddCrewRep then
		crewService.AddCrewRep(crewId, total, 1)
	end
end

local function capture(turf: Turf, crewId: string, members: { Player })
	local name, color, emblem = crewLook(members)
	local previous = turf.Owner
	clearCapture(turf)
	setOwner(turf, crewId, name, color, emblem)
	Notify.All(string.format("%s %s took %s!", emblem, name, turf.Name), "crew", 5)
	if previous and Services.CrewService and Services.CrewService.GetOnlineMembers then
		Notify.Many(Services.CrewService.GetOnlineMembers(previous), "Your crew lost " .. turf.Name .. "!", "bad")
	end
	reward(turf, crewId, members)
end

local function stepTurf(turf: Turf)
	local groups: { [string]: { Player } } = {}
	local present: { string } = {}
	for _, player in Players:GetPlayers() do
		local crewId = crewOf(player)
		local root = rootOf(player)
		if crewId and root and (root.Position - turf.Position).Magnitude <= Crews.CaptureRadius and canCapture(player) then
			local group = groups[crewId]
			if not group then
				local created = {}
				groups[crewId] = created
				table.insert(present, crewId)
				group = created
			end
			table.insert(group :: { Player }, player)
		end
	end

	if #present == 0 then
		turf.Contested = false
		if turf.Progress > 0 then
			turf.Progress = math.max(0, turf.Progress - Crews.CaptureDecayPerSecond * TICK)
			if turf.Progress == 0 then
				clearCapture(turf)
			end
		end
		return
	end

	if #present > 1 then
		turf.Contested = true
		table.clear(turf.ContestColors)
		for i = 1, math.min(2, #present) do
			local _, color = crewLook(groups[present[i]])
			table.insert(turf.ContestColors, color)
		end
		return
	end

	turf.Contested = false
	table.clear(turf.ContestColors)
	local crewId = present[1]
	local members = groups[crewId]
	local rate = (100 / Crews.CaptureSeconds) * math.min(#members, Crews.CaptureMaxMultiplier) * TICK
	if crewId == turf.Owner or (turf.Capturing and turf.Capturing ~= crewId and turf.Progress > 0) then
		-- Defenders (or a rival crew) push the current capture back first.
		turf.Progress = math.max(0, turf.Progress - rate)
		if turf.Progress == 0 then
			clearCapture(turf)
		end
		return
	end
	if turf.Capturing ~= crewId then
		local name, color = crewLook(members)
		turf.Capturing = crewId
		turf.CapturingName = name
		turf.CapturingColor = color
		turf.Progress = 0
	end
	turf.Progress = math.min(100, turf.Progress + rate)
	if turf.Progress >= 100 then
		capture(turf, crewId, members)
	end
end

local function trackActivity()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root then
			local last = lastPosition[player]
			if not last or (root.Position - last).Magnitude > MOVE_EPSILON then
				lastActive[player] = now
			end
			lastPosition[player] = root.Position
		end
	end
end

local function tick()
	trackActivity()
	local war = Services.DayCycleService and Services.DayCycleService.IsTurfWar() or false
	flash = not flash
	if war then
		for _, turf in turfs do
			stepTurf(turf)
			updateStatus(turf, true)
		end
		broadcast()
	elseif wasWar then
		-- The war just ended: captures in progress are lost, ownership stays until the next After School.
		for _, turf in turfs do
			clearCapture(turf)
			updateStatus(turf, false)
		end
		broadcast()
	elseif dirty then
		for _, turf in turfs do
			updateStatus(turf, false)
		end
		broadcast()
	end
	wasWar = war
end

local function resetOwnership()
	for _, turf in turfs do
		clearCapture(turf)
		setOwner(turf, nil)
		updateStatus(turf, false)
	end
	dirty = true
end

local function payIncome()
	for _, player in Players:GetPlayers() do
		local crewId = crewOf(player)
		if crewId and isActive(player) then
			local held = #TurfService.GetTurfsHeld(crewId)
			if held > 0 then
				local amount = math.floor(Economy.TurfIncomePerMinute * held * (Crews.IncomeIntervalSeconds / 60))
				local added = Services.DataService.AddYen(player, amount, "Turf")
				if added > 0 then
					Notify.Send(player, string.format("Turf income +¥%d (%d turf%s)", added, held, if held == 1 then "" else "s"), "gold", 3)
				end
			end
		end
	end
end

-- Public API -----------------------------------------------------------------------------

function TurfService.GetTurfsHeld(crewId: string): { string }
	local held = {}
	for _, id in Crews.TurfIds do
		local turf = turfs[id]
		if turf and turf.Owner == crewId then
			table.insert(held, id)
		end
	end
	return held
end

function TurfService.GetOwner(turfId: string): string?
	local turf = turfs[turfId]
	return if turf then turf.Owner else nil
end

function TurfService.GetState(): any
	return payload()
end

-- Lifecycle -------------------------------------------------------------------------------

function TurfService.Init(services: any)
	Services = services
end

function TurfService.Start()
	local mapFolder = Services.MapService and Services.MapService.GetMapFolder()
	local wallsFolder = mapFolder and mapFolder:FindFirstChild("TurfWalls")
	for _, id in Crews.TurfIds do
		local pos = MapData.TurfWalls[id]
		local found = wallsFolder and wallsFolder:FindFirstChild(id)
		local wall: BasePart? = if found and found:IsA("BasePart") then found else nil
		local position = if wall then wall.Position elseif pos then Vector3.new(pos[1], 5, pos[2]) else nil
		if position then
			local turf: Turf = {
				Id = id,
				Name = Crews.TurfNames[id] or id,
				Position = position,
				Wall = wall,
				BaseColor = if wall then wall.Color else Color3.fromHex(UITheme.Sakura),
				Owner = nil,
				OwnerName = nil,
				OwnerColor = nil,
				OwnerEmblem = nil,
				Capturing = nil,
				CapturingName = nil,
				CapturingColor = nil,
				Progress = 0,
				Contested = false,
				ContestColors = {},
				StatusLabel = nil,
				StatusBar = nil,
			}
			turfs[id] = turf
			buildStatus(turf)
			updateStatus(turf, false)
		end
	end

	if Services.DayCycleService then
		Services.DayCycleService.PeriodChanged:Connect(function(new: any, old: any)
			if old and new.Id == "AfterSchool" then
				resetOwnership()
				Notify.All("⚔ The turf war has begun! All turf is up for grabs.", "bad", 5)
			end
		end)
	end
	local crewService = Services.CrewService
	if crewService and crewService.CrewDisbanded then
		crewService.CrewDisbanded:Connect(function(crewId: string)
			for _, turf in turfs do
				if turf.Owner == crewId then
					setOwner(turf, nil)
				end
				if turf.Capturing == crewId then
					clearCapture(turf)
				end
			end
		end)
	end
	local combat = Services.CombatService
	if combat and combat.HitLanded and combat.HitLanded.Connect then
		combat.HitLanded:Connect(function(attacker: any)
			local player = if typeof(attacker) == "Instance" then Players:GetPlayerFromCharacter(attacker) else nil
			if player then
				lastActive[player] = os.clock()
			end
		end)
	end

	Players.PlayerAdded:Connect(function(player)
		lastActive[player] = os.clock()
		turfUpdate:FireClient(player, payload())
	end)
	for _, player in Players:GetPlayers() do
		lastActive[player] = os.clock()
		turfUpdate:FireClient(player, payload())
	end
	Players.PlayerRemoving:Connect(function(player)
		lastPosition[player] = nil
		lastActive[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(Crews.IncomeIntervalSeconds)
			xpcall(payIncome, function(err: any)
				warn("[TurfService] Income failed: " .. tostring(err))
			end)
		end
	end)

	wasWar = Services.DayCycleService and Services.DayCycleService.IsTurfWar() or false
	while true do
		task.wait(TICK)
		xpcall(tick, function(err: any)
			warn("[TurfService] Tick failed: " .. tostring(err))
		end)
	end
end

return TurfService
