-- Kenka High world layout (blueprint section 2). Pure data: plain numbers, no Roblox types,
-- so it can be unit tested and used by both the runtime MapBuilder and the zone system.
-- North = -Z. Ground top is Y = 0. Units are studs.

export type Zone = {
	Name: string,
	Type: string, -- "Green" | "Yellow" | "Red" | "Road" | "Water"
	X: number,
	Z: number,
	SizeX: number,
	SizeZ: number,
	MinY: number?,
	MaxY: number?,
	Turf: string?, -- turf id; turf zones turn Red during After School
}

export type Building = {
	Name: string,
	X: number,
	Z: number,
	SizeX: number,
	Height: number,
	SizeZ: number,
	BaseY: number,
}

export type Interactable = {
	Id: string,
	Kind: string, -- see INTERACTABLE KINDS below
	X: number,
	Y: number,
	Z: number,
	Action: string, -- ProximityPrompt ActionText
	Object: string, -- ProximityPrompt ObjectText
	Hold: number?, -- HoldDuration
	Target: { number }?, -- teleport target X, Y, Z
	Shop: string?, -- shop id for Kind "Shop"
	Job: string?, -- job id for Kind "Job"
}

--[[ INTERACTABLE KINDS and the service that handles them:
	"RumorBoard"  QuestService (opens the Rumors app)
	"Fountain"    ShopService (coin toss)
	"Mirror"      CosmeticsService (character creator)
	"Teleport"    MapService (rooftop stairs)
	"Class"       ClassService (class minigame)
	"Dojo"        StyleService (Style screen)
	"Tournament"  TournamentService (sign up)
	"Shop"        ShopService (opens a shop)
	"Job"         JobService (starts a job)
	"Capsule"     CapsuleService (opens Capsule Corner)
	"Bathhouse"   ShopService (free buff)
	"Station"     MapService (info toast)
	"CrewHQ"      CrewService (enter the crew HQ)
]]

local MapData = {}

-- Compact layout (v2): about 500 x 470 studs so 20 players keep running into each other.
-- Gate to station is ~15 s on foot, anywhere to anywhere under ~20 s.
MapData.Ground = { X = 0, Z = 35, SizeX = 500, SizeZ = 470 }

MapData.Spawns = {
	Courtyard = { 0, 3, -15 },
	NurseRespawn = { -55, 3, -76 },
	Station = { 0, 3, 216 },
}

-- Zones, checked smallest-area-first. Anywhere outside every zone counts as DefaultZoneType.
MapData.DefaultZoneType = "Yellow"
MapData.Zones = {
	{ Name = "Kawa-dori", Type = "Road", X = 0, Z = 70, SizeX = 480, SizeZ = 18 },
	{ Name = "Gate Street", Type = "Road", X = 0, Z = 130, SizeX = 18, SizeZ = 260 },
	{ Name = "School Courtyard", Type = "Yellow", X = 0, Z = -40, SizeX = 120, SizeZ = 80 },
	{ Name = "Back Lot", Type = "Red", X = 0, Z = -160, SizeX = 140, SizeZ = 50 },
	{ Name = "School Field", Type = "Yellow", X = -170, Z = -40, SizeX = 100, SizeZ = 90 },
	{ Name = "Gym Arena", Type = "Yellow", X = -150, Z = -150, SizeX = 80, SizeZ = 60 },
	{ Name = "Basketball Court", Type = "Red", X = 150, Z = -155, SizeX = 60, SizeZ = 44 },
	{ Name = "Shotengai", Type = "Yellow", X = 0, Z = 150, SizeX = 60, SizeZ = 140, Turf = "T1" },
	{ Name = "Riverbank", Type = "Red", X = 205, Z = 60, SizeX = 70, SizeZ = 340, Turf = "T2" },
	{ Name = "River Channel", Type = "Water", X = 205, Z = 60, SizeX = 18, SizeZ = 340, Turf = "T2" },
	{ Name = "Kawa-dori Bridge", Type = "Yellow", X = 205, Z = 70, SizeX = 70, SizeZ = 18, MaxY = 6 },
	{ Name = "Hinode Park", Type = "Yellow", X = -140, Z = 150, SizeX = 100, SizeZ = 100, Turf = "T3" },
	{ Name = "Docks", Type = "Red", X = -165, Z = 230, SizeX = 130, SizeZ = 60, Turf = "T4" },
	{ Name = "Neon Alley", Type = "Yellow", X = 105, Z = 150, SizeX = 80, SizeZ = 70, Turf = "T5" },
	{ Name = "Station Plaza", Type = "Green", X = 0, Z = 238, SizeX = 100, SizeZ = 40 },
	{ Name = "Rooftop", Type = "Red", X = 0, Z = -105, SizeX = 160, SizeZ = 40, MinY = 50 },
	-- Safe pockets in front of shops, jobs, class, dojo and the nurse (players use prompts here).
	{ Name = "Shop Fronts West", Type = "Green", X = -12, Z = 140, SizeX = 6, SizeZ = 110 },
	{ Name = "Shop Fronts East", Type = "Green", X = 12, Z = 140, SizeX = 6, SizeZ = 110 },
	{ Name = "Nurse's Office", Type = "Green", X = -55, Z = -78, SizeX = 24, SizeZ = 12 },
	{ Name = "West Wing Classrooms", Type = "Green", X = -62, Z = -40, SizeX = 10, SizeZ = 90 },
	{ Name = "East Wing Clubs", Type = "Green", X = 62, Z = -40, SizeX = 10, SizeZ = 90 },
	{ Name = "Dojo", Type = "Green", X = 145, Z = -62, SizeX = 50, SizeZ = 28 },
	{ Name = "Gym Entrance", Type = "Green", X = -150, Z = -113, SizeX = 30, SizeZ = 8 },
	{ Name = "Pixel Den Entrance", Type = "Green", X = 105, Z = 120, SizeX = 30, SizeZ = 8 },
} :: { Zone }

MapData.Buildings = {
	{ Name = "Main School Building", X = 0, Z = -105, SizeX = 160, Height = 52, SizeZ = 40, BaseY = 0 },
	{ Name = "Clock Tower", X = 0, Z = -115, SizeX = 16, Height = 18, SizeZ = 16, BaseY = 52 },
	{ Name = "West Wing", X = -85, Z = -40, SizeX = 36, Height = 30, SizeZ = 100, BaseY = 0 },
	{ Name = "East Wing (Clubs)", X = 85, Z = -40, SizeX = 36, Height = 30, SizeZ = 100, BaseY = 0 },
	{ Name = "Gym Bleachers", X = -150, Z = -186, SizeX = 80, Height = 8, SizeZ = 8, BaseY = 0 },
	{ Name = "Dojo", X = 145, Z = -75, SizeX = 44, Height = 18, SizeZ = 36, BaseY = 0 },
	{ Name = "Bike Shed", X = -45, Z = -178, SizeX = 30, Height = 10, SizeZ = 10, BaseY = 0 },
	{ Name = "Train Station", X = 0, Z = 240, SizeX = 90, Height = 20, SizeZ = 30, BaseY = 0 },
	{ Name = "Ichiban Bowl", X = -22, Z = 95, SizeX = 14, Height = 14, SizeZ = 18, BaseY = 0 },
	{ Name = "Konbini 24", X = 22, Z = 95, SizeX = 14, Height = 12, SizeZ = 18, BaseY = 0 },
	{ Name = "Tailor Tanaka", X = -22, Z = 125, SizeX = 14, Height = 14, SizeZ = 18, BaseY = 0 },
	{ Name = "Capsule Corner", X = 22, Z = 125, SizeX = 14, Height = 14, SizeZ = 18, BaseY = 0 },
	{ Name = "Speedy Cycles", X = -22, Z = 155, SizeX = 14, Height = 12, SizeZ = 18, BaseY = 0 },
	{ Name = "Sento", X = 22, Z = 155, SizeX = 14, Height = 16, SizeZ = 18, BaseY = 0 },
	{ Name = "Kissa Hoshi", X = -22, Z = 185, SizeX = 14, Height = 12, SizeZ = 18, BaseY = 0 },
	{ Name = "Pharmacy", X = 22, Z = 185, SizeX = 14, Height = 12, SizeZ = 18, BaseY = 0 },
	{ Name = "Pixel Den Arcade", X = 105, Z = 135, SizeX = 28, Height = 16, SizeZ = 20, BaseY = 0 },
	{ Name = "Warehouse 1", X = -215, Z = 250, SizeX = 26, Height = 18, SizeZ = 20, BaseY = 0 },
	{ Name = "Warehouse 2", X = -180, Z = 250, SizeX = 26, Height = 18, SizeZ = 20, BaseY = 0 },
	{ Name = "Warehouse 3", X = -145, Z = 250, SizeX = 26, Height = 18, SizeZ = 20, BaseY = 0 },
	{ Name = "Warehouse 4", X = -110, Z = 250, SizeX = 26, Height = 18, SizeZ = 20, BaseY = 0 },
} :: { Building }

MapData.Interactables = {
	{ Id = "RumorBoard", Kind = "RumorBoard", X = 30, Y = 3, Z = -60, Action = "Read Rumors", Object = "Rumor Board" },
	{ Id = "Fountain", Kind = "Fountain", X = 0, Y = 3, Z = -40, Action = "Toss a coin (¥10)", Object = "Fountain" },
	{ Id = "NurseMirror", Kind = "Mirror", X = -55, Y = 3, Z = -80, Action = "Customize", Object = "Nurse's Office Mirror" },
	{ Id = "RoofStairsUp", Kind = "Teleport", X = 30, Y = 3, Z = -80, Action = "Go to the rooftop", Object = "Stairs (RED ZONE above)", Target = { 30, 55, -100 } },
	{ Id = "RoofStairsDown", Kind = "Teleport", X = 30, Y = 55, Z = -110, Action = "Go downstairs", Object = "Stairs", Target = { 30, 3, -76 } },
	{ Id = "ClassWest1", Kind = "Class", X = -62, Y = 3, Z = -65, Action = "Take Class", Object = "Classroom 1-A" },
	{ Id = "ClassWest2", Kind = "Class", X = -62, Y = 3, Z = -15, Action = "Take Class", Object = "Classroom 1-B" },
	{ Id = "Sensei", Kind = "Dojo", X = 145, Y = 3, Z = -52, Action = "Train", Object = "Sensei" },
	{ Id = "GymSignup", Kind = "Tournament", X = -150, Y = 3, Z = -113, Action = "Join Tournament", Object = "Gym Sign-up Board" },
	{ Id = "VendingMachine", Kind = "Shop", X = 30, Y = 3, Z = -150, Action = "Buy a drink", Object = "Vending Machine", Shop = "VendingMachine" },
	{ Id = "IchibanBowl", Kind = "Shop", X = -12, Y = 3, Z = 90, Action = "Order food", Object = "Ichiban Bowl", Shop = "IchibanBowl" },
	{ Id = "RamenJob", Kind = "Job", X = -12, Y = 3, Z = 100, Action = "Start shift", Object = "Ramen Delivery", Job = "RamenDelivery" },
	{ Id = "Konbini24", Kind = "Shop", X = 12, Y = 3, Z = 90, Action = "Shop", Object = "Konbini 24", Shop = "Konbini24" },
	{ Id = "KonbiniJob", Kind = "Job", X = 12, Y = 3, Z = 100, Action = "Start shift", Object = "Konbini Shift", Job = "KonbiniShift" },
	{ Id = "TailorTanaka", Kind = "Shop", X = -12, Y = 3, Z = 125, Action = "Browse", Object = "Tailor Tanaka", Shop = "TailorTanaka" },
	{ Id = "CapsuleCorner", Kind = "Capsule", X = 12, Y = 3, Z = 125, Action = "Roll capsules", Object = "Capsule Corner" },
	{ Id = "SpeedyCycles", Kind = "Shop", X = -12, Y = 3, Z = 155, Action = "Browse", Object = "Speedy Cycles", Shop = "SpeedyCycles" },
	{ Id = "Sento", Kind = "Bathhouse", X = 12, Y = 3, Z = 155, Action = "Take a bath", Object = "Sento", Hold = 2 },
	{ Id = "KissaHoshi", Kind = "Shop", X = -12, Y = 3, Z = 185, Action = "Order", Object = "Kissa Hoshi", Shop = "KissaHoshi" },
	{ Id = "Pharmacy", Kind = "Shop", X = 12, Y = 3, Z = 185, Action = "Shop", Object = "Pharmacy", Shop = "Pharmacy" },
	{ Id = "ArcadeJob", Kind = "Job", X = 112, Y = 3, Z = 120, Action = "Start shift", Object = "Arcade Attendant", Job = "ArcadeAttendant" },
	{ Id = "Station", Kind = "Station", X = 0, Y = 3, Z = 221, Action = "Read timetable", Object = "Train Station" },
	{ Id = "CrewHQ1", Kind = "CrewHQ", X = -215, Y = 3, Z = 236, Action = "Enter Crew HQ", Object = "Warehouse 1" },
	{ Id = "CrewHQ2", Kind = "CrewHQ", X = -180, Y = 3, Z = 236, Action = "Enter Crew HQ", Object = "Warehouse 2" },
	{ Id = "CrewHQ3", Kind = "CrewHQ", X = -145, Y = 3, Z = 236, Action = "Enter Crew HQ", Object = "Warehouse 3" },
	{ Id = "CrewHQ4", Kind = "CrewHQ", X = -110, Y = 3, Z = 236, Action = "Enter Crew HQ", Object = "Warehouse 4" },
} :: { Interactable }

-- Turf graffiti walls (X, Z). TurfService builds capture logic around these.
MapData.TurfWalls = {
	T1 = { -20, 208 },
	T2 = { 215, 88 },
	T3 = { -140, 150 },
	T4 = { -165, 215 },
	T5 = { 105, 175 },
}

-- Practice dummies next to the dojo (X, Z). Hitting them gives mastery XP, no Rep.
MapData.Dummies = { { 130, -42 }, { 145, -42 }, { 160, -42 } }

-- Crew HQ interiors are built at runtime this far below the map, one slot per active crew.
MapData.CrewHQOrigin = { 0, -2000, 0 }
MapData.CrewHQSpacing = 200

function MapData.GetInteractable(id: string): Interactable?
	for _, item in MapData.Interactables do
		if item.Id == id then
			return item
		end
	end
	return nil
end

return MapData
