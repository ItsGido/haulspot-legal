-- KENKA HIGH: greybox map builder (generated from blueprint.md, section 2)
-- Paste into Roblox Studio > View > Command Bar in a fresh Baseplate and press Enter.
-- Ctrl+Z undoes the whole build. Running it again replaces the previous build.
-- North = -Z. Ground top is Y = 0. Units are studs.

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local recording = ChangeHistoryService:TryBeginRecording("Build Kenka High Greybox")

local ZONE_COLORS = {
	Green = "#3BC46B",
	Yellow = "#F4C542",
	Red = "#E4322B",
	Road = "#3A3D48",
	Water = "#3FA7FF",
	Event = "#7A5CFF",
}

-- Zone plates. Type: Green (no combat), Yellow (duels only), Red (open fights), Road, Water.
-- Each plate gets attributes ZoneType, ZoneName and TurfId for the ZoneService to read.
local ZONES = {
	{ Name = "Kawa-dori", Type = "Road", X = 0, Z = 70, SizeX = 480, SizeZ = 18, Turf = "" },
	{ Name = "Gate Street", Type = "Road", X = 0, Z = 130, SizeX = 18, SizeZ = 260, Turf = "" },
	{ Name = "School Courtyard", Type = "Yellow", X = 0, Z = -40, SizeX = 120, SizeZ = 80, Turf = "" },
	{ Name = "Back Lot", Type = "Red", X = 0, Z = -160, SizeX = 140, SizeZ = 50, Turf = "" },
	{ Name = "School Field", Type = "Yellow", X = -170, Z = -40, SizeX = 100, SizeZ = 90, Turf = "" },
	{ Name = "Gym Arena", Type = "Event", X = -150, Z = -150, SizeX = 80, SizeZ = 60, Turf = "" },
	{ Name = "Basketball Court", Type = "Red", X = 150, Z = -155, SizeX = 60, SizeZ = 44, Turf = "" },
	{ Name = "Shotengai", Type = "Yellow", X = 0, Z = 150, SizeX = 60, SizeZ = 140, Turf = "T1" },
	{ Name = "Riverbank", Type = "Red", X = 205, Z = 60, SizeX = 70, SizeZ = 340, Turf = "T2" },
	{ Name = "River Channel", Type = "Water", X = 205, Z = 60, SizeX = 18, SizeZ = 340, Turf = "" },
	{ Name = "Kawa-dori Bridge", Type = "Yellow", X = 205, Z = 70, SizeX = 70, SizeZ = 18, Turf = "" },
	{ Name = "Hinode Park", Type = "Yellow", X = -140, Z = 150, SizeX = 100, SizeZ = 100, Turf = "T3" },
	{ Name = "Docks", Type = "Red", X = -165, Z = 230, SizeX = 130, SizeZ = 60, Turf = "T4" },
	{ Name = "Neon Alley", Type = "Yellow", X = 105, Z = 150, SizeX = 80, SizeZ = 70, Turf = "T5" },
	{ Name = "Station Plaza", Type = "Green", X = 0, Z = 238, SizeX = 100, SizeZ = 40, Turf = "" },
	{ Name = "Shop Fronts West", Type = "Green", X = -12, Z = 140, SizeX = 6, SizeZ = 110, Turf = "" },
	{ Name = "Shop Fronts East", Type = "Green", X = 12, Z = 140, SizeX = 6, SizeZ = 110, Turf = "" },
	{ Name = "Nurse's Office", Type = "Green", X = -55, Z = -78, SizeX = 24, SizeZ = 12, Turf = "" },
	{ Name = "West Wing Classrooms", Type = "Green", X = -62, Z = -40, SizeX = 10, SizeZ = 90, Turf = "" },
	{ Name = "East Wing Clubs", Type = "Green", X = 62, Z = -40, SizeX = 10, SizeZ = 90, Turf = "" },
	{ Name = "Dojo", Type = "Green", X = 145, Z = -62, SizeX = 50, SizeZ = 28, Turf = "" },
	{ Name = "Gym Entrance", Type = "Green", X = -150, Z = -113, SizeX = 30, SizeZ = 8, Turf = "" },
	{ Name = "Pixel Den Entrance", Type = "Green", X = 105, Z = 120, SizeX = 30, SizeZ = 8, Turf = "" },
}

-- Buildings are solid greybox blocks for scale. Interiors get built in the art pass.
local BUILDINGS = {
	{ Name = "Main School Building", Zone = "Green", X = 0, Z = -105, SizeX = 160, Height = 52, SizeZ = 40, BaseY = 0 },
	{ Name = "Clock Tower", Zone = "Green", X = 0, Z = -115, SizeX = 16, Height = 18, SizeZ = 16, BaseY = 52 },
	{ Name = "West Wing", Zone = "Green", X = -85, Z = -40, SizeX = 36, Height = 30, SizeZ = 100, BaseY = 0 },
	{ Name = "East Wing (Clubs)", Zone = "Green", X = 85, Z = -40, SizeX = 36, Height = 30, SizeZ = 100, BaseY = 0 },
	{ Name = "Gym Bleachers", Zone = "Green", X = -150, Z = -186, SizeX = 80, Height = 8, SizeZ = 8, BaseY = 0 },
	{ Name = "Dojo", Zone = "Green", X = 145, Z = -75, SizeX = 44, Height = 18, SizeZ = 36, BaseY = 0 },
	{ Name = "Bike Shed", Zone = "Green", X = -45, Z = -178, SizeX = 30, Height = 10, SizeZ = 10, BaseY = 0 },
	{ Name = "Train Station", Zone = "Green", X = 0, Z = 240, SizeX = 90, Height = 20, SizeZ = 30, BaseY = 0 },
	{ Name = "Ichiban Bowl", Zone = "Green", X = -22, Z = 95, SizeX = 14, Height = 14, SizeZ = 18, BaseY = 0 },
	{ Name = "Konbini 24", Zone = "Green", X = 22, Z = 95, SizeX = 14, Height = 12, SizeZ = 18, BaseY = 0 },
	{ Name = "Tailor Tanaka", Zone = "Green", X = -22, Z = 125, SizeX = 14, Height = 14, SizeZ = 18, BaseY = 0 },
	{ Name = "Capsule Corner", Zone = "Green", X = 22, Z = 125, SizeX = 14, Height = 14, SizeZ = 18, BaseY = 0 },
	{ Name = "Speedy Cycles", Zone = "Green", X = -22, Z = 155, SizeX = 14, Height = 12, SizeZ = 18, BaseY = 0 },
	{ Name = "Sento", Zone = "Green", X = 22, Z = 155, SizeX = 14, Height = 16, SizeZ = 18, BaseY = 0 },
	{ Name = "Kissa Hoshi", Zone = "Green", X = -22, Z = 185, SizeX = 14, Height = 12, SizeZ = 18, BaseY = 0 },
	{ Name = "Pharmacy", Zone = "Green", X = 22, Z = 185, SizeX = 14, Height = 12, SizeZ = 18, BaseY = 0 },
	{ Name = "Pixel Den Arcade", Zone = "Green", X = 105, Z = 135, SizeX = 28, Height = 16, SizeZ = 20, BaseY = 0 },
	{ Name = "Warehouse 1", Zone = "Green", X = -215, Z = 250, SizeX = 26, Height = 18, SizeZ = 20, BaseY = 0 },
	{ Name = "Warehouse 2", Zone = "Green", X = -180, Z = 250, SizeX = 26, Height = 18, SizeZ = 20, BaseY = 0 },
	{ Name = "Warehouse 3", Zone = "Green", X = -145, Z = 250, SizeX = 26, Height = 18, SizeZ = 20, BaseY = 0 },
	{ Name = "Warehouse 4", Zone = "Green", X = -110, Z = 250, SizeX = 26, Height = 18, SizeZ = 20, BaseY = 0 },
}

-- Points of interest and turf graffiti walls.
local POINTS = {
	{ Name = "Rumor Board", Kind = "poi", X = 30, Z = -60 },
	{ Name = "Fountain", Kind = "poi", X = 0, Z = -40 },
	{ Name = "Nurse's Office", Kind = "poi", X = -55, Z = -80 },
	{ Name = "Rooftop stairs", Kind = "poi", X = 30, Z = -80 },
	{ Name = "Class", Kind = "poi", X = -62, Z = -65 },
	{ Name = "Sensei (Dojo)", Kind = "poi", X = 145, Z = -52 },
	{ Name = "Tournament sign-up", Kind = "poi", X = -150, Z = -113 },
	{ Name = "Vending", Kind = "poi", X = 30, Z = -150 },
	{ Name = "Turf T1", Kind = "turf", X = -20, Z = 208 },
	{ Name = "Turf T2", Kind = "turf", X = 215, Z = 88 },
	{ Name = "Turf T3", Kind = "turf", X = -140, Z = 150 },
	{ Name = "Turf T4", Kind = "turf", X = -165, Z = 215 },
	{ Name = "Turf T5", Kind = "turf", X = 105, Z = 175 },
}

local old = workspace:FindFirstChild("KenkaHighMap")
if old then
	old:Destroy()
end
local baseplate = workspace:FindFirstChild("Baseplate")
if baseplate then
	baseplate.Transparency = 1
	baseplate.CanCollide = false
end

local map = Instance.new("Folder")
map.Name = "KenkaHighMap"
map.Parent = workspace

local function makeFolder(name)
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = map
	return folder
end

local zonesFolder = makeFolder("Zones")
local buildingsFolder = makeFolder("Buildings")
local pointsFolder = makeFolder("Points")

local function addLabel(part, text, height)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromOffset(240, 44)
	gui.StudsOffset = Vector3.new(0, height, 0)
	gui.MaxDistance = 600
	gui.AlwaysOnTop = true
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.BuilderSansBold
	label.TextColor3 = Color3.fromHex("#F5F1E8")
	label.TextStrokeTransparency = 0
	label.Parent = gui
	gui.Parent = part
end

local function addPart(name, parent, size, position, hex, transparency)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.Position = position
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.fromHex(hex)
	part.Transparency = transparency or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Ground
addPart("Ground", map, Vector3.new(500, 2, 470), Vector3.new(0, -1, 35), "#23262F")

-- Zone plates are stacked a little to avoid z-fighting: roads lowest, water and bridges highest.
local LAYER = { Road = 0.05, Green = 0.1, Yellow = 0.1, Red = 0.1, Water = 0.15 }
for _, zone in ZONES do
	local thickness = 0.1
	local y = LAYER[zone.Type] or 0.1
	if zone.Name:find("Bridge") then
		y = 0.2
	end
	local plate = addPart(zone.Name, zonesFolder, Vector3.new(zone.SizeX, thickness, zone.SizeZ),
		Vector3.new(zone.X, y, zone.Z), ZONE_COLORS[zone.Type])
	plate:SetAttribute("ZoneType", zone.Type)
	plate:SetAttribute("ZoneName", zone.Name)
	if zone.Turf ~= "" then
		plate:SetAttribute("TurfId", zone.Turf)
	end
	if zone.Type ~= "Road" and zone.Type ~= "Water" then
		local text = zone.Name .. " (" .. zone.Type .. ")"
		if zone.Turf ~= "" then
			text ..= " [" .. zone.Turf .. "]"
		end
		addLabel(plate, text, 6)
	end
end

for _, building in BUILDINGS do
	local center = Vector3.new(building.X, building.BaseY + building.Height / 2, building.Z)
	local block = addPart(building.Name, buildingsFolder,
		Vector3.new(building.SizeX, building.Height, building.SizeZ), center, "#8C92A4", 0.25)
	local outline = Instance.new("SelectionBox")
	outline.Adornee = block
	outline.LineThickness = 0.3
	outline.Color3 = Color3.fromHex(ZONE_COLORS[building.Zone] or "#FFFFFF")
	outline.Parent = block
	addLabel(block, building.Name, building.Height / 2 + 4)
end

-- Rooftop red zone on top of the main school building (Y = 52)
local roof = addPart("Rooftop", zonesFolder, Vector3.new(240, 0.2, 60), Vector3.new(0, 52.1, -170), ZONE_COLORS.Red)
roof:SetAttribute("ZoneType", "Red")
roof:SetAttribute("ZoneName", "Rooftop")
addLabel(roof, "Rooftop (Red)", 6)

for _, point in POINTS do
	if point.Kind == "turf" then
		local wall = addPart(point.Name .. " Wall", pointsFolder, Vector3.new(20, 10, 2),
			Vector3.new(point.X, 5, point.Z), "#FF9EC4")
		wall:SetAttribute("TurfId", point.Name:sub(-2))
		wall:SetAttribute("CaptureRadius", 25)
		addLabel(wall, point.Name .. " graffiti wall", 8)
	else
		local marker = addPart(point.Name, pointsFolder, Vector3.new(3, 6, 3),
			Vector3.new(point.X, 3, point.Z), "#FFD23F")
		marker.Material = Enum.Material.Neon
		marker.CanCollide = false
		addLabel(marker, point.Name, 5)
	end
end

local spawn = Instance.new("SpawnLocation")
spawn.Name = "CourtyardSpawn"
spawn.Anchored = true
spawn.Size = Vector3.new(12, 1, 12)
spawn.Position = Vector3.new(0, 0.5, -30)
spawn.Color = Color3.fromHex("#5FE08A")
spawn.Duration = 0
spawn.Parent = map

if recording then
	ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
end
print(string.format("Kenka High greybox built: %d zones, %d buildings, %d points", #ZONES, #BUILDINGS, #POINTS))
