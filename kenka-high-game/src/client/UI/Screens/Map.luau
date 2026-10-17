--!strict
-- Map (blueprint 5.6): zones, buildings, turf owners, you (arrow), crewmates (sakura dots), the Banchō
-- (gold crown), and shop/job markers. Tap a marker (or a row in the list) to set a waypoint beam in the
-- world; tap it again or walk within 10 studs to clear it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UITheme = require(ReplicatedStorage.Shared.Config.UITheme)
local Crews = require(ReplicatedStorage.Shared.Config.Crews)
local MapData = require(ReplicatedStorage.Shared.Map.MapData)
local Kit = require(script.Parent.Parent.Kit)
local W = require(script.Parent.Parent.HudWidgets)

local Map = {}
Map.Name = "Map"

local player = Players.LocalPlayer
local Controllers: any
local ARRIVE_DISTANCE = 10

-- Square map bounds from the ground plate.
local SIDE = math.max(MapData.Ground.SizeX, MapData.Ground.SizeZ)
local MIN_X = MapData.Ground.X - SIDE / 2
local MIN_Z = MapData.Ground.Z - SIDE / 2

local function toUV(x: number, z: number): UDim2
	return UDim2.fromScale(math.clamp((x - MIN_X) / SIDE, 0, 1), math.clamp((z - MIN_Z) / SIDE, 0, 1))
end

local KIND_GLYPHS: { [string]: string } = {
	Shop = "🛒",
	Job = "💼",
	Capsule = "🎰",
	Dojo = "🥋",
	RumorBoard = "📜",
	Mirror = "🪞",
	Tournament = "🏆",
	Class = "📚",
	Bathhouse = "♨",
	Station = "🚉",
	CrewHQ = "🚩",
	Fountain = "⛲",
}
local SKIP_IDS: { [string]: boolean } = { CrewHQ2 = true, CrewHQ3 = true, CrewHQ4 = true, ClassWest2 = true }

type Marker = { Id: string, Name: string, Kind: string, Position: Vector3 }

local markers: { Marker } = {}
for _, item in MapData.Interactables do
	if KIND_GLYPHS[item.Kind] and not SKIP_IDS[item.Id] then
		local name = item.Object
		if item.Kind == "CrewHQ" then
			name = "Crew HQ (Docks)"
		elseif item.Kind == "Class" then
			name = "Classrooms"
		end
		table.insert(markers, { Id = item.Id, Name = name, Kind = item.Kind, Position = Vector3.new(item.X, item.Y, item.Z) })
	end
end
table.sort(markers, function(a, b)
	return a.Name < b.Name
end)

-- UI refs
local mapFrame: Frame = nil :: any
local arrow: TextLabel = nil :: any
local crownIcon: TextLabel = nil :: any
local waypointLabel: TextLabel = nil :: any
local clearButton: TextButton = nil :: any
local markerButtons: { [string]: TextButton } = {}
local turfMarkers: { [string]: { Frame: Frame, Label: TextLabel, Stroke: UIStroke } } = {}
local crewDots: { [Player]: Frame } = {}
local updater: thread? = nil

-- Waypoint state (lives outside the window so it persists while the map is closed)
type Waypoint = { Id: string, Name: string, Position: Vector3, Part: BasePart, Beam: Beam }
local waypoint: Waypoint? = nil
local waypointConn: RBXScriptConnection? = nil

local function rootPart(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function refreshMarkerHighlight()
	for id, button in markerButtons do
		local stroke = button:FindFirstChildOfClass("UIStroke")
		local active = waypoint ~= nil and (waypoint :: Waypoint).Id == id
		if stroke then
			stroke.Color = Kit.Hex(if active then UITheme.Gold else UITheme.PanelStroke)
			stroke.Thickness = if active then 3 else 2
		end
		button.BackgroundColor3 = Kit.Hex(if active then UITheme.Gold else UITheme.Panel)
	end
	if waypointLabel then
		local current = waypoint
		waypointLabel.Text = if current then "📍 " .. W.Escape(current.Name) else "Tap a marker to set a waypoint"
		clearButton.Visible = current ~= nil
	end
end

local function clearWaypoint()
	local current = waypoint
	waypoint = nil
	if waypointConn then
		waypointConn:Disconnect()
		waypointConn = nil
	end
	if current then
		current.Part:Destroy()
	end
	local root = rootPart()
	local attachment = root and root:FindFirstChild("KenkaWaypointAttachment")
	if attachment then
		attachment:Destroy()
	end
	refreshMarkerHighlight()
end

local function setWaypoint(marker: Marker)
	if waypoint and (waypoint :: Waypoint).Id == marker.Id then
		clearWaypoint()
		W.Toast(Controllers, "Waypoint cleared.", "info")
		return
	end
	clearWaypoint()

	local part = Instance.new("Part")
	part.Name = "KenkaWaypoint"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.one
	part.Position = marker.Position + Vector3.new(0, 1, 0)
	local target = Instance.new("Attachment")
	target.Name = "Target"
	target.Parent = part
	local beam = Instance.new("Beam")
	beam.Attachment1 = target
	beam.FaceCamera = true
	beam.Width0 = 0.5
	beam.Width1 = 0.5
	beam.Segments = 12
	beam.LightEmission = 1
	beam.Color = ColorSequence.new(Kit.Hex(UITheme.Gold))
	beam.Transparency = NumberSequence.new(0.25)
	beam.Parent = part
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.AlwaysOnTop = true
	billboard.Size = UDim2.fromOffset(180, 44)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
	billboard.LightInfluence = 0
	billboard.Parent = part
	local distanceLabel = Kit.Label("Text", billboard, "", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), "BodyBold", UITheme.Gold, 22)
	Kit.TextStroke(distanceLabel, 2)
	part.Parent = workspace

	local current: Waypoint = { Id = marker.Id, Name = marker.Name, Position = part.Position, Part = part, Beam = beam }
	waypoint = current
	waypointConn = RunService.Heartbeat:Connect(function()
		local root = rootPart()
		if not root then
			beam.Enabled = false
			return
		end
		local attachment = root:FindFirstChild("KenkaWaypointAttachment")
		if not attachment then
			local created = Instance.new("Attachment")
			created.Name = "KenkaWaypointAttachment"
			created.Parent = root
			attachment = created
		end
		beam.Attachment0 = attachment :: Attachment
		beam.Enabled = true
		local distance = (root.Position - current.Position).Magnitude
		distanceLabel.Text = string.format("📍 %s · %dm", W.Escape(current.Name), math.floor(distance))
		if distance <= ARRIVE_DISTANCE then
			clearWaypoint()
			W.Toast(Controllers, "You've arrived at " .. current.Name .. ".", "good")
		end
	end)
	refreshMarkerHighlight()
	W.Toast(Controllers, "Waypoint set: " .. marker.Name, "info")
end

-- Drawing --------------------------------------------------------------------------

local function zoneColor(zoneType: string): string
	return (UITheme.Zones :: any)[zoneType] or W.ZoneExtra[zoneType] or UITheme.PanelLight
end

local function drawStatic()
	local zones: { MapData.Zone } = table.clone(MapData.Zones)
	table.sort(zones, function(a: MapData.Zone, b: MapData.Zone)
		return a.SizeX * a.SizeZ > b.SizeX * b.SizeZ
	end)
	for i, zone in zones do
		if not zone.MinY then
			local frame = Kit.Frame("Zone_" .. zone.Name, mapFrame, toUV(zone.X, zone.Z), UDim2.fromScale(zone.SizeX / SIDE, zone.SizeZ / SIDE), zoneColor(zone.Type), Vector2.new(0.5, 0.5))
			frame.BackgroundTransparency = if zone.Type == "Road" then 0.1 else 0.45
			frame.ZIndex = 1 + math.min(i, 30)
			if zone.Turf then
				local stroke = Kit.InkStroke(frame, 2, UITheme.Sakura)
				stroke.Transparency = 0.2
			end
			if zone.SizeX * zone.SizeZ >= 9000 and zone.Type ~= "Road" and zone.Type ~= "Water" then
				local label = Kit.Label("Name", frame, W.Escape(zone.Name), UDim2.fromScale(0.05, 0.05), UDim2.fromScale(0.9, 0.22), "BodyBold", UITheme.Paper, 13)
				label.ZIndex = 40
				Kit.TextStroke(label, 1)
			end
		end
	end
	for _, building in MapData.Buildings do
		if building.BaseY <= 0 then
			local frame = Kit.Frame("Building_" .. building.Name, mapFrame, toUV(building.X, building.Z), UDim2.fromScale(building.SizeX / SIDE, building.SizeZ / SIDE), UITheme.Ink, Vector2.new(0.5, 0.5))
			frame.BackgroundTransparency = 0.15
			frame.ZIndex = 35
			Kit.InkStroke(frame, 1)
		end
	end
	-- Turf emblems at the graffiti walls
	for _, id in Crews.TurfIds do
		local pos = (MapData.TurfWalls :: any)[id]
		if pos then
			local chip = Kit.Frame("Turf_" .. id, mapFrame, toUV(pos[1], pos[2]), UDim2.fromScale(0.05, 0.05), UITheme.Panel, Vector2.new(0.5, 0.5))
			chip.ZIndex = 45
			Kit.Corner(chip, 1)
			Kit.Aspect(chip, 1)
			local stroke = Kit.InkStroke(chip, 2)
			local label = Kit.Label("Emblem", chip, id, UDim2.fromScale(0.1, 0.1), UDim2.fromScale(0.8, 0.8), "Title", UITheme.Paper, 20)
			label.ZIndex = 46
			turfMarkers[id] = { Frame = chip, Label = label, Stroke = stroke }
		end
	end
	-- Interactable markers
	for _, marker in markers do
		local button = Instance.new("TextButton")
		button.Name = "Marker_" .. marker.Id
		button.AnchorPoint = Vector2.new(0.5, 0.5)
		button.Position = toUV(marker.Position.X, marker.Position.Z)
		button.Size = UDim2.fromScale(0.036, 0.036)
		button.BackgroundColor3 = Kit.Hex(UITheme.Panel)
		button.Text = KIND_GLYPHS[marker.Kind] or "•"
		button.TextScaled = true
		button.Font = UITheme.Fonts.Body
		button.TextColor3 = Kit.Hex(UITheme.Paper)
		button.AutoButtonColor = false
		button.ZIndex = 50
		button.Parent = mapFrame
		Kit.Corner(button, 1)
		Kit.Aspect(button, 1)
		Kit.InkStroke(button, 2)
		markerButtons[marker.Id] = button
		button.Activated:Connect(function()
			setWaypoint(marker)
		end)
	end
end

local function refreshTurf()
	local hud = Controllers and Controllers.HUDController
	local state = if hud and hud.GetTurfState then hud.GetTurfState() else nil
	local turfs = if type(state) == "table" and type(state.Turfs) == "table" then state.Turfs else {}
	for id, entry in turfMarkers do
		local t = turfs[id]
		if type(t) == "table" and type(t.OwnerName) == "string" then
			entry.Frame.BackgroundColor3 = Kit.Hex(W.ColorHex(t.OwnerColor, UITheme.Sakura))
			entry.Label.Text = if type(t.OwnerEmblem) == "string" then W.Escape(t.OwnerEmblem) else id
		else
			entry.Frame.BackgroundColor3 = Kit.Hex(UITheme.Panel)
			entry.Label.Text = id
		end
		local contested = type(t) == "table" and t.Contested == true
		entry.Stroke.Color = Kit.Hex(if contested then UITheme.Bars.Posture else UITheme.PanelStroke)
		entry.Stroke.Thickness = if contested then 3 else 2
	end
end

local function yawDegrees(look: Vector3): number
	return math.deg(math.atan2(look.X, -look.Z))
end

local function updateDynamic()
	local root = rootPart()
	if root then
		arrow.Visible = true
		arrow.Position = toUV(root.Position.X, root.Position.Z)
		arrow.Rotation = yawDegrees(root.CFrame.LookVector)
	else
		local camera = workspace.CurrentCamera
		arrow.Visible = camera ~= nil
		if camera then
			arrow.Position = toUV(camera.Focus.Position.X, camera.Focus.Position.Z)
			arrow.Rotation = yawDegrees(camera.CFrame.LookVector)
		end
	end

	-- Crewmates
	local myCrew = player:GetAttribute("CrewId")
	local seen: { [Player]: boolean } = {}
	if type(myCrew) == "string" and myCrew ~= "" then
		for _, other in Players:GetPlayers() do
			if other ~= player and other:GetAttribute("CrewId") == myCrew then
				local character = other.Character
				local otherRoot = character and character:FindFirstChild("HumanoidRootPart")
				if otherRoot and otherRoot:IsA("BasePart") then
					seen[other] = true
					local dot = crewDots[other]
					if not dot then
						local created = Kit.Frame("Crew_" .. other.Name, mapFrame, UDim2.new(), UDim2.fromScale(0.022, 0.022), UITheme.Sakura, Vector2.new(0.5, 0.5))
						created.ZIndex = 60
						Kit.Corner(created, 1)
						Kit.Aspect(created, 1)
						Kit.InkStroke(created, 2)
						crewDots[other] = created
						dot = created
					end
					(dot :: Frame).Position = toUV(otherRoot.Position.X, otherRoot.Position.Z)
				end
			end
		end
	end
	for other, dot in crewDots do
		if not seen[other] then
			dot:Destroy()
			crewDots[other] = nil
		end
	end

	-- Crown holder
	local holderId = ReplicatedStorage:GetAttribute("CrownHolderId")
	local holder = if type(holderId) == "number" and holderId > 0 then Players:GetPlayerByUserId(holderId) else nil
	local holderCharacter = holder and holder.Character
	local holderRoot = holderCharacter and holderCharacter:FindFirstChild("HumanoidRootPart")
	if holderRoot and holderRoot:IsA("BasePart") then
		crownIcon.Visible = true
		crownIcon.Position = toUV(holderRoot.Position.X, holderRoot.Position.Z)
	else
		crownIcon.Visible = false
	end
end

local function legendRow(parent: Instance, order: number, color: string, text: string)
	local row = Kit.Frame("Legend" .. order, parent, UDim2.new(), UDim2.fromScale(0.48, 0.3))
	row.LayoutOrder = order
	local dot = Kit.Frame("Dot", row, UDim2.fromScale(0, 0.5), UDim2.fromScale(0.16, 0.7), color, Vector2.new(0, 0.5))
	Kit.Corner(dot, 1)
	Kit.Aspect(dot, 1, true)
	Kit.InkStroke(dot, 1.5)
	Kit.Label("Text", row, text, UDim2.fromScale(0.22, 0), UDim2.fromScale(0.78, 1), "BodyBold", UITheme.Paper, 16, Enum.TextXAlignment.Left)
end

function Map.Build(playerGui: Instance, controllers: any): Kit.Window
	Controllers = controllers
	local window = Kit.Window(playerGui, "Map", "MAP · KENKA TOWN", UDim2.fromScale(0.8, 0.9))
	W.ShapeWindow(window, 1.45)
	local body = window.Body

	mapFrame = Kit.Frame("MapPanel", body, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), "#2B2E3C")
	Kit.Aspect(mapFrame, 1, true)
	Kit.InkStroke(mapFrame, 3)
	Kit.Corner(mapFrame, 0.02)
	mapFrame.ClipsDescendants = true

	drawStatic()

	crownIcon = Kit.Label("Crown", mapFrame, "♛", UDim2.new(), UDim2.fromScale(0.05, 0.05), "Number", UITheme.Gold, 40)
	crownIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	crownIcon.ZIndex = 70
	Kit.TextStroke(crownIcon, 2)
	crownIcon.Visible = false

	arrow = Kit.Label("You", mapFrame, "▲", UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.045, 0.045), "Number", UITheme.Paper, 40)
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.ZIndex = 80
	Kit.TextStroke(arrow, 2.5, UITheme.Buttons.Primary[2])
	Kit.Aspect(arrow, 1)

	-- Side panel: waypoint, legend, destinations list
	local side = Kit.Panel("Side", body, UDim2.fromScale(1, 0), UDim2.fromScale(0.37, 1), Vector2.new(1, 0), UITheme.PanelLight)
	local sc = side:FindFirstChildOfClass("UICorner")
	if sc then
		sc.CornerRadius = UDim.new(0.04, 0)
	end
	Kit.Label("WaypointTitle", side, "WAYPOINT", UDim2.fromScale(0.06, 0.015), UDim2.fromScale(0.88, 0.06), "Title", UITheme.Gold, 28, Enum.TextXAlignment.Left)
	waypointLabel = Kit.Label("Waypoint", side, "", UDim2.fromScale(0.06, 0.075), UDim2.fromScale(0.6, 0.07), "BodyBold", UITheme.Paper, 18, Enum.TextXAlignment.Left)
	clearButton = Kit.Button(side, "CLEAR", "Ghost", UDim2.fromScale(0.94, 0.075), UDim2.fromScale(0.28, 0.07), Vector2.new(1, 0))
	clearButton.Activated:Connect(function()
		clearWaypoint()
	end)

	local legend = Kit.Frame("Legend", side, UDim2.fromScale(0.06, 0.16), UDim2.fromScale(0.88, 0.15))
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromScale(0.48, 0.3)
	grid.CellPadding = UDim2.fromScale(0.04, 0.03)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = legend
	legendRow(legend, 1, UITheme.Zones.Green, "Safe")
	legendRow(legend, 2, UITheme.Zones.Yellow, "Caution")
	legendRow(legend, 3, UITheme.Zones.Red, "Open fights")
	legendRow(legend, 4, UITheme.Sakura, "Crewmate")
	legendRow(legend, 5, UITheme.Paper, "You ▲")
	legendRow(legend, 6, UITheme.Gold, "Banchō ♛")

	Kit.Label("PlacesTitle", side, "PLACES", UDim2.fromScale(0.06, 0.33), UDim2.fromScale(0.88, 0.05), "Title", UITheme.Paper, 24, Enum.TextXAlignment.Left)
	local scroll = Kit.Scroll("Places", side, UDim2.fromScale(0.04, 0.39), UDim2.fromScale(0.92, 0.59))
	Kit.List(scroll, 0.01)
	local rowHeight = W.ScrollRows(scroll, #markers, 0.1, 0.012)
	for i, marker in markers do
		local row = Kit.Button(scroll, (KIND_GLYPHS[marker.Kind] or "•") .. " " .. marker.Name, "Ghost", UDim2.new(), UDim2.fromScale(0.96, rowHeight))
		row.LayoutOrder = i
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.Activated:Connect(function()
			setWaypoint(marker)
		end)
	end

	local hud = controllers.HUDController
	if hud and hud.TurfChanged then
		hud.TurfChanged:Connect(function()
			if window.Gui.Enabled then
				refreshTurf()
			end
		end)
	end
	refreshMarkerHighlight()
	return window
end

function Map.Open(_window: Kit.Window, _data: any?)
	refreshTurf()
	refreshMarkerHighlight()
	updateDynamic()
	if updater then
		pcall(task.cancel, updater)
	end
	updater = task.spawn(function()
		while true do
			task.wait(0.1)
			updateDynamic()
		end
	end)
end

function Map.Close(_window: Kit.Window)
	if updater then
		pcall(task.cancel, updater)
		updater = nil
	end
end

return Map
