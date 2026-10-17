--!strict
-- Crew HQ interiors (blueprint Z16 Docks). Used only by CrewService.
-- Each active crew gets a private room built lazily under MapData.CrewHQOrigin, one slot of
-- MapData.CrewHQSpacing studs per crew. A room is removed after IDLE_SECONDS with nobody inside.
--
-- The HQ sits outside every MapData zone, so ZoneService treats it as Yellow (no open fights).
--
--   CrewHQ.Init(teleport)                       teleport(player, cframe) = MapService.Teleport
--   CrewHQ.Enter(player, crewId, info, returnCFrame)
--   CrewHQ.UpdateInfo(crewId, info)             refresh the sign, banner and roster if the room exists
--   CrewHQ.Remove(crewId)                       eject everyone and destroy the room (disband)
--   CrewHQ.Eject(player)                        send a player inside any HQ back to the docks
--   CrewHQ.PlayerLeft(player)
-- info = { Name, ColorHex, Glyph, Banner: boolean, Roster = { { Name, Role, Online } } }

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapData = require(ReplicatedStorage.Shared.Map.MapData)
local UITheme = require(ReplicatedStorage.Shared.Config.UITheme)

local CrewHQ = {}

local IDLE_SECONDS = 120 -- remove an interior after 2 minutes with no members inside
local CHECK_INTERVAL = 10
local ROOM_SIZE = 60
local WALL_HEIGHT = 20
local EXIT_RANGE = 12

export type Info = {
	Name: string,
	ColorHex: string,
	Glyph: string,
	Banner: boolean,
	Roster: { { Name: string, Role: string, Online: boolean } },
}

type Room = {
	Slot: number,
	Origin: Vector3,
	Model: Model,
	EmptySince: number?,
	SignEmblem: TextLabel,
	SignName: TextLabel,
	RosterText: TextLabel,
	Accents: { BasePart },
	BannerFolder: Folder,
}

local rooms: { [string]: Room } = {}
local returnPoints: { [Player]: CFrame } = {}
local teleportFn: ((Player, CFrame) -> ())? = nil
local folder: Folder? = nil

local function getFolder(): Folder
	local existing = folder
	if existing and existing.Parent then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "CrewHQs"
	created.Parent = workspace
	folder = created
	return created
end

local function teleport(player: Player, cframe: CFrame)
	local fn = teleportFn
	if fn then
		fn(player, cframe)
	else
		local character = player.Character
		if character then
			character:PivotTo(cframe)
		end
	end
end

local function defaultReturn(): CFrame
	for _, item in MapData.Interactables do
		if item.Kind == "CrewHQ" then
			return CFrame.new(item.X, item.Y + 2, item.Z - 6)
		end
	end
	local spawn = MapData.Spawns.Courtyard
	return CFrame.new(spawn[1], spawn[2] + 3, spawn[3])
end

local function freeSlot(): number
	local used = {}
	for _, room in rooms do
		used[room.Slot] = true
	end
	local slot = 0
	while used[slot] do
		slot += 1
	end
	return slot
end

local function slotOrigin(slot: number): Vector3
	local o = MapData.CrewHQOrigin
	return Vector3.new(o[1] + slot * MapData.CrewHQSpacing, o[2], o[3])
end

local function part(name: string, parent: Instance, size: Vector3, position: Vector3, color: string, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.Position = position
	p.Color = Color3.fromHex(color)
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function surfaceGui(parent: BasePart, face: Enum.NormalId): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	gui.Parent = parent
	return gui
end

local function textLabel(parent: Instance, text: string, position: UDim2, size: UDim2, font: Enum.Font, color: string): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = position
	l.Size = size
	l.Text = text
	l.Font = font
	l.TextScaled = true
	l.TextWrapped = true
	l.RichText = true
	l.TextColor3 = Color3.fromHex(color)
	l.TextStrokeTransparency = 0
	l.Parent = parent
	return l
end

local function isInside(room: Room, position: Vector3): boolean
	local d = position - room.Origin
	local half = ROOM_SIZE / 2 + 2
	return math.abs(d.X) <= half and math.abs(d.Z) <= half and d.Y >= -5 and d.Y <= WALL_HEIGHT + 10
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function rosterText(info: Info): string
	local lines = {}
	for _, member in info.Roster do
		local dot = if member.Online then '<font color="#5FE08A">●</font>' else '<font color="#5A5E6B">●</font>'
		local role = if member.Role == "Leader" then " ♛" elseif member.Role == "Lieutenant" then " ★" else ""
		local name = member.Name:gsub("[<>&]", "")
		table.insert(lines, dot .. " " .. name .. role)
	end
	return table.concat(lines, "\n")
end

local function buildBanner(room: Room, info: Info)
	room.BannerFolder:ClearAllChildren()
	if not info.Banner then
		return
	end
	for _, x in { -20, 20 } do
		local cloth = part("Banner", room.BannerFolder, Vector3.new(7, 15, 0.4), room.Origin + Vector3.new(x, 11, -ROOM_SIZE / 2 + 0.6), info.ColorHex, Enum.Material.Fabric)
		cloth.CanCollide = false
		local gui = surfaceGui(cloth, Enum.NormalId.Back)
		textLabel(gui, info.Glyph, UDim2.fromScale(0.1, 0.25), UDim2.fromScale(0.8, 0.5), UITheme.Fonts.BodyBold, UITheme.Paper)
	end
end

local function applyInfo(room: Room, info: Info)
	room.SignEmblem.Text = info.Glyph
	room.SignEmblem.TextColor3 = Color3.fromHex(info.ColorHex)
	room.SignName.Text = string.upper((info.Name:gsub("[<>&]", "")))
	room.SignName.TextColor3 = Color3.fromHex(info.ColorHex)
	room.RosterText.Text = rosterText(info)
	for _, accent in room.Accents do
		accent.Color = Color3.fromHex(info.ColorHex)
	end
	buildBanner(room, info)
end

local function exitPlayer(player: Player)
	teleport(player, returnPoints[player] or defaultReturn())
	returnPoints[player] = nil
end

local function build(crewId: string, info: Info): Room
	local slot = freeSlot()
	local origin = slotOrigin(slot)
	local model = Instance.new("Model")
	model.Name = "HQ_" .. crewId

	local half = ROOM_SIZE / 2
	local floor = part("Floor", model, Vector3.new(ROOM_SIZE, 2, ROOM_SIZE), origin, "#2A2C33", Enum.Material.Concrete)
	floor:SetAttribute("ZoneType", "Green") -- marker only; ZoneService reads MapData, so the HQ counts as Yellow
	floor:SetAttribute("CrewId", crewId)
	model.PrimaryPart = floor
	local wallY = origin.Y + 1 + WALL_HEIGHT / 2
	part("WallN", model, Vector3.new(ROOM_SIZE + 4, WALL_HEIGHT, 2), Vector3.new(origin.X, wallY, origin.Z - half - 1), "#3B3E48", Enum.Material.Brick)
	part("WallS", model, Vector3.new(ROOM_SIZE + 4, WALL_HEIGHT, 2), Vector3.new(origin.X, wallY, origin.Z + half + 1), "#3B3E48", Enum.Material.Brick)
	part("WallW", model, Vector3.new(2, WALL_HEIGHT, ROOM_SIZE), Vector3.new(origin.X - half - 1, wallY, origin.Z), "#3B3E48", Enum.Material.Brick)
	part("WallE", model, Vector3.new(2, WALL_HEIGHT, ROOM_SIZE), Vector3.new(origin.X + half + 1, wallY, origin.Z), "#3B3E48", Enum.Material.Brick)
	local ceiling = part("Ceiling", model, Vector3.new(ROOM_SIZE + 4, 2, ROOM_SIZE + 4), Vector3.new(origin.X, origin.Y + 2 + WALL_HEIGHT, origin.Z), "#1C1E2B")
	local light = Instance.new("PointLight")
	light.Range = 60
	light.Brightness = 2
	light.Color = Color3.fromHex("#FFE8D0")
	light.Parent = ceiling

	-- Neon accent strips in the crew color along the floor edges
	local accents: { BasePart } = {}
	for _, offset in { Vector3.new(0, 1.1, -half + 1), Vector3.new(0, 1.1, half - 1) } do
		local strip = part("Accent", model, Vector3.new(ROOM_SIZE - 2, 0.2, 0.6), origin + offset, info.ColorHex, Enum.Material.Neon)
		strip.CanCollide = false
		table.insert(accents, strip)
	end

	-- Big emblem sign on the north wall (facing into the room)
	local sign = part("Sign", model, Vector3.new(24, 13, 0.6), Vector3.new(origin.X, origin.Y + 11, origin.Z - half + 0.4), UITheme.Ink)
	local signGui = surfaceGui(sign, Enum.NormalId.Back)
	local signEmblem = textLabel(signGui, info.Glyph, UDim2.fromScale(0.25, 0.04), UDim2.fromScale(0.5, 0.68), UITheme.Fonts.BodyBold, info.ColorHex)
	local signName = textLabel(signGui, info.Name, UDim2.fromScale(0.05, 0.72), UDim2.fromScale(0.9, 0.24), UITheme.Fonts.Title, info.ColorHex)

	-- Roster board on the east wall (facing west, into the room)
	local board = part("RosterBoard", model, Vector3.new(0.6, 14, 22), Vector3.new(origin.X + half - 0.4, origin.Y + 10, origin.Z), UITheme.Panel)
	local boardGui = surfaceGui(board, Enum.NormalId.Left)
	textLabel(boardGui, "ROSTER", UDim2.fromScale(0.05, 0.02), UDim2.fromScale(0.9, 0.12), UITheme.Fonts.Title, UITheme.Sakura)
	local roster = textLabel(boardGui, "", UDim2.fromScale(0.06, 0.16), UDim2.fromScale(0.88, 0.8), UITheme.Fonts.BodyBold, UITheme.Paper)
	roster.TextScaled = false
	roster.TextSize = 34
	roster.TextXAlignment = Enum.TextXAlignment.Left
	roster.TextYAlignment = Enum.TextYAlignment.Top

	-- Exit pad near the south wall
	local pad = part("ExitPad", model, Vector3.new(8, 0.4, 8), Vector3.new(origin.X, origin.Y + 1.2, origin.Z + half - 7), UITheme.Sakura, Enum.Material.Neon)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Leave HQ"
	prompt.ObjectText = "Exit"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = pad
	prompt.Triggered:Connect(function(player: Player)
		local root = rootOf(player)
		if root and (root.Position - pad.Position).Magnitude <= EXIT_RANGE then
			exitPlayer(player)
		end
	end)

	local bannerFolder = Instance.new("Folder")
	bannerFolder.Name = "Banners"
	bannerFolder.Parent = model

	model.Parent = getFolder()
	local room: Room = {
		Slot = slot,
		Origin = origin,
		Model = model,
		EmptySince = nil,
		SignEmblem = signEmblem,
		SignName = signName,
		RosterText = roster,
		Accents = accents,
		BannerFolder = bannerFolder,
	}
	applyInfo(room, info)
	return room
end

local function destroy(crewId: string)
	local room = rooms[crewId]
	if not room then
		return
	end
	rooms[crewId] = nil
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root and isInside(room, root.Position) then
			exitPlayer(player)
		end
	end
	room.Model:Destroy()
end

-- Public API -----------------------------------------------------------------

function CrewHQ.Init(teleport: (Player, CFrame) -> ())
	teleportFn = teleport
end

function CrewHQ.Enter(player: Player, crewId: string, info: Info, returnCFrame: CFrame?)
	local room = rooms[crewId]
	if not room then
		local built = build(crewId, info)
		rooms[crewId] = built
		room = built
	else
		applyInfo(room, info)
	end
	local r = room :: Room
	r.EmptySince = nil
	returnPoints[player] = returnCFrame or defaultReturn()
	local spot = r.Origin + Vector3.new(0, 5, 12)
	teleport(player, CFrame.lookAt(spot, spot + Vector3.new(0, 0, -1)))
end

function CrewHQ.UpdateInfo(crewId: string, info: Info)
	local room = rooms[crewId]
	if room then
		applyInfo(room, info)
	end
end

function CrewHQ.Remove(crewId: string)
	destroy(crewId)
end

function CrewHQ.IsBuilt(crewId: string): boolean
	return rooms[crewId] ~= nil
end

-- Returns the crew id of the HQ the player is standing in, if any.
function CrewHQ.GetRoomOf(player: Player): string?
	local root = rootOf(player)
	if not root then
		return nil
	end
	for crewId, room in rooms do
		if isInside(room, root.Position) then
			return crewId
		end
	end
	return nil
end

function CrewHQ.Eject(player: Player)
	if CrewHQ.GetRoomOf(player) then
		exitPlayer(player)
	end
end

function CrewHQ.PlayerLeft(player: Player)
	returnPoints[player] = nil
end

-- Idle cleanup loop. Call once from CrewService.Start (it yields forever).
function CrewHQ.Run()
	while true do
		task.wait(CHECK_INTERVAL)
		local now = os.clock()
		for crewId, room in rooms do
			local occupied = false
			for _, player in Players:GetPlayers() do
				local root = rootOf(player)
				if root and isInside(room, root.Position) then
					occupied = true
					break
				end
			end
			if occupied then
				room.EmptySince = nil
			else
				local since = room.EmptySince or now
				room.EmptySince = since
				if now - since >= IDLE_SECONDS then
					destroy(crewId)
				end
			end
		end
	end
end

return CrewHQ
