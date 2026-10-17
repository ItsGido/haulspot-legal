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

MapData.Ground = { X = 0, Z = 50, SizeX = 900, SizeZ = 860 }

MapData.Spawns = {
	Courtyard = { 0, 3, -30 },
	NurseRespawn = { -90, 3, -120 },
	Station = { 0, 3, 385 },
}

-- Zones, checked smallest-area-first. Anywhere outside every zone counts as DefaultZoneType.
MapData.DefaultZoneType = "Yellow"
MapData.Zones = {
	{ Name = "Kawa-dori", Type = "Road", X = 0, Z = 120, SizeX = 840, SizeZ = 24 },
	{ Name = "Gate Street", Type = "Road", X = 0, Z = 190, SizeX = 24, SizeZ = 380 },
	{ Name = "School Courtyard", Type = "Yellow", X = 0, Z = -70, SizeX = 200, SizeZ = 120 },
	{ Name = "Back Lot", Type = "Red", X = 0, Z = -260, SizeX = 200, SizeZ = 80 },
	{ Name = "School Field", Type = "Yellow", X = -300, Z = -60, SizeX = 200, SizeZ = 140 },
	{ Name = "Basketball Court", Type = "Red", X = 240, Z = -230, SizeX = 90, SizeZ = 60 },
	{ Name = "Shotengai", Type = "Yellow", X = 0, Z = 250, SizeX = 80, SizeZ = 220, Turf = "T1" },
	{ Name = "Riverbank", Type = "Red", X = 360, Z = 100, SizeX = 120, SizeZ = 560, Turf = "T2" },
	{ Name = "River Channel", Type = "Water", X = 360, Z = 100, SizeX = 30, SizeZ = 560, Turf = "T2" },
	{ Name = "Kawa-dori Bridge", Type = "Yellow", X = 360, Z = 120, SizeX = 120, SizeZ = 24, MaxY = 6 },
	{ Name = "Hinode Park", Type = "Yellow", X = -230, Z = 220, SizeX = 160, SizeZ = 160, Turf = "T3" },
	{ Name = "Docks", Type = "Red", X = -300, Z = 410, SizeX = 220, SizeZ = 120, Turf = "T4" },
	{ Name = "Neon Alley", Type = "Yellow", X = 170, Z = 260, SizeX = 120, SizeZ = 100, Turf = "T5" },
	{ Name = "Station Plaza", Type = "Green", X = 0, Z = 420, SizeX = 140, SizeZ = 50 },
	{ Name = "Rooftop", Type = "Red", X = 0, Z = -170, SizeX = 240, SizeZ = 60, MinY = 50 },
	-- Safe pockets in front of shops, jobs, class, dojo and the nurse (players use prompts here).
	{ Name = "Shop Fronts West", Type = "Green", X = -24, Z = 245, SizeX = 16, SizeZ = 170 },
	{ Name = "Shop Fronts East", Type = "Green", X = 24, Z = 245, SizeX = 16, SizeZ = 170 },
	{ Name = "Nurse's Office", Type = "Green", X = -90, Z = -122, SizeX = 30, SizeZ = 16 },
	{ Name = "West Wing Classrooms", Type = "Green", X = -108, Z = -70, SizeX = 14, SizeZ = 120 },
	{ Name = "East Wing Clubs", Type = "Green", X = 108, Z = -70, SizeX = 14, SizeZ = 120 },
	{ Name = "Dojo", Type = "Green", X = 240, Z = -82, SizeX = 70, SizeZ = 40 },
	{ Name = "Gym Entrance", Type = "Green", X = -260, Z = -178, SizeX = 40, SizeZ = 14 },
	{ Name = "Pixel Den Entrance", Type = "Green", X = 170, Z = 224, SizeX = 40, SizeZ = 10 },
	{ Name = "Capsule Corner", Type = "Green", X = 17, Z = 220, SizeX = 10, SizeZ = 24 },
} :: { Zone }

MapData.Buildings = {
	{ Name = "Main School Building", X = 0, Z = -170, SizeX = 240, Height = 52, SizeZ = 60, BaseY = 0 },
	{ Name = "Clock Tower", X = 0, Z = -185, SizeX = 20, Height = 20, SizeZ = 20, BaseY = 52 },
	{ Name = "West Wing", X = -140, Z = -70, SizeX = 50, Height = 36, SizeZ = 160, BaseY = 0 },
	{ Name = "East Wing (Clubs)", X = 140, Z = -70, SizeX = 50, Height = 36, SizeZ = 160, BaseY = 0 },
	{ Name = "Gym", X = -260, Z = -230, SizeX = 120, Height = 40, SizeZ = 90, BaseY = 0 },
	{ Name = "Dojo", X = 240, Z = -100, SizeX = 60, Height = 20, SizeZ = 50, BaseY = 0 },
	{ Name = "Bike Shed", X = -70, Z = -290, SizeX = 40, Height = 12, SizeZ = 12, BaseY = 0 },
	{ Name = "Train Station", X = 0, Z = 420, SizeX = 140, Height = 24, SizeZ = 50, BaseY = 0 },
	{ Name = "Ichiban Bowl", X = -30, Z = 170, SizeX = 20, Height = 14, SizeZ = 24, BaseY = 0 },
	{ Name = "Konbini 24", X = 30, Z = 170, SizeX = 20, Height = 12, SizeZ = 24, BaseY = 0 },
	{ Name = "Tailor Tanaka", X = -30, Z = 220, SizeX = 20, Height = 14, SizeZ = 24, BaseY = 0 },
	{ Name = "Capsule Corner", X = 30, Z = 220, SizeX = 20, Height = 14, SizeZ = 24, BaseY = 0 },
	{ Name = "Speedy Cycles", X = -30, Z = 270, SizeX = 20, Height = 12, SizeZ = 24, BaseY = 0 },
	{ Name = "Sento", X = 30, Z = 270, SizeX = 20, Height = 16, SizeZ = 24, BaseY = 0 },
	{ Name = "Kissa Hoshi", X = -30, Z = 320, SizeX = 20, Height = 12, SizeZ = 24, BaseY = 0 },
	{ Name = "Pharmacy", X = 30, Z = 320, SizeX = 20, Height = 12, SizeZ = 24, BaseY = 0 },
	{ Name = "Pixel Den Arcade", X = 170, Z = 245, SizeX = 40, Height = 20, SizeZ = 30, BaseY = 0 },
	{ Name = "Warehouse 1", X = -385, Z = 440, SizeX = 40, Height = 24, SizeZ = 40, BaseY = 0 },
	{ Name = "Warehouse 2", X = -330, Z = 440, SizeX = 40, Height = 24, SizeZ = 40, BaseY = 0 },
	{ Name = "Warehouse 3", X = -275, Z = 440, SizeX = 40, Height = 24, SizeZ = 40, BaseY = 0 },
	{ Name = "Warehouse 4", X = -220, Z = 440, SizeX = 40, Height = 24, SizeZ = 40, BaseY = 0 },
} :: { Building }

MapData.Interactables = {
	{ Id = "RumorBoard", Kind = "RumorBoard", X = 40, Y = 3, Z = -100, Action = "Read Rumors", Object = "Rumor Board" },
	{ Id = "Fountain", Kind = "Fountain", X = 0, Y = 3, Z = -60, Action = "Toss a coin (¥10)", Object = "Fountain" },
	{ Id = "NurseMirror", Kind = "Mirror", X = -90, Y = 3, Z = -127, Action = "Customize", Object = "Nurse's Office Mirror" },
	{ Id = "RoofStairsUp", Kind = "Teleport", X = 40, Y = 3, Z = -136, Action = "Go to the rooftop", Object = "Stairs (RED ZONE above)", Target = { 40, 55, -160 } },
	{ Id = "RoofStairsDown", Kind = "Teleport", X = 40, Y = 55, Z = -168, Action = "Go downstairs", Object = "Stairs", Target = { 40, 3, -128 } },
	{ Id = "ClassWest1", Kind = "Class", X = -108, Y = 3, Z = -100, Action = "Take Class", Object = "Classroom 1-A" },
	{ Id = "ClassWest2", Kind = "Class", X = -108, Y = 3, Z = -40, Action = "Take Class", Object = "Classroom 1-B" },
	{ Id = "Sensei", Kind = "Dojo", X = 240, Y = 3, Z = -70, Action = "Train", Object = "Sensei" },
	{ Id = "GymSignup", Kind = "Tournament", X = -260, Y = 3, Z = -179, Action = "Join Tournament", Object = "Gym Sign-up Board" },
	{ Id = "VendingMachine", Kind = "Shop", X = 40, Y = 3, Z = -226, Action = "Buy a drink", Object = "Vending Machine", Shop = "VendingMachine" },
	{ Id = "IchibanBowl", Kind = "Shop", X = -18, Y = 3, Z = 164, Action = "Order food", Object = "Ichiban Bowl", Shop = "IchibanBowl" },
	{ Id = "RamenJob", Kind = "Job", X = -18, Y = 3, Z = 176, Action = "Start shift", Object = "Ramen Delivery", Job = "RamenDelivery" },
	{ Id = "Konbini24", Kind = "Shop", X = 18, Y = 3, Z = 164, Action = "Shop", Object = "Konbini 24", Shop = "Konbini24" },
	{ Id = "KonbiniJob", Kind = "Job", X = 18, Y = 3, Z = 176, Action = "Start shift", Object = "Konbini Shift", Job = "KonbiniShift" },
	{ Id = "TailorTanaka", Kind = "Shop", X = -18, Y = 3, Z = 220, Action = "Browse", Object = "Tailor Tanaka", Shop = "TailorTanaka" },
	{ Id = "CapsuleCorner", Kind = "Capsule", X = 18, Y = 3, Z = 220, Action = "Roll capsules", Object = "Capsule Corner" },
	{ Id = "SpeedyCycles", Kind = "Shop", X = -18, Y = 3, Z = 270, Action = "Browse", Object = "Speedy Cycles", Shop = "SpeedyCycles" },
	{ Id = "Sento", Kind = "Bathhouse", X = 18, Y = 3, Z = 270, Action = "Take a bath", Object = "Sento", Hold = 2 },
	{ Id = "KissaHoshi", Kind = "Shop", X = -18, Y = 3, Z = 320, Action = "Order", Object = "Kissa Hoshi", Shop = "KissaHoshi" },
	{ Id = "Pharmacy", Kind = "Shop", X = 18, Y = 3, Z = 320, Action = "Shop", Object = "Pharmacy", Shop = "Pharmacy" },
	{ Id = "ArcadeJob", Kind = "Job", X = 178, Y = 3, Z = 225, Action = "Start shift", Object = "Arcade Attendant", Job = "ArcadeAttendant" },
	{ Id = "Station", Kind = "Station", X = 0, Y = 3, Z = 392, Action = "Read timetable", Object = "Train Station" },
	{ Id = "CrewHQ1", Kind = "CrewHQ", X = -385, Y = 3, Z = 416, Action = "Enter Crew HQ", Object = "Warehouse 1" },
	{ Id = "CrewHQ2", Kind = "CrewHQ", X = -330, Y = 3, Z = 416, Action = "Enter Crew HQ", Object = "Warehouse 2" },
	{ Id = "CrewHQ3", Kind = "CrewHQ", X = -275, Y = 3, Z = 416, Action = "Enter Crew HQ", Object = "Warehouse 3" },
	{ Id = "CrewHQ4", Kind = "CrewHQ", X = -220, Y = 3, Z = 416, Action = "Enter Crew HQ", Object = "Warehouse 4" },
} :: { Interactable }

-- Turf graffiti walls (X, Z). TurfService builds capture logic around these.
MapData.TurfWalls = {
	T1 = { 0, 345 },
	T2 = { 380, 150 },
	T3 = { -230, 220 },
	T4 = { -300, 390 },
	T5 = { 170, 290 },
}

-- Practice dummies next to the dojo (X, Z). Hitting them gives half mastery XP, no Rep.
MapData.Dummies = { { 222, -58 }, { 240, -58 }, { 258, -58 } }

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
