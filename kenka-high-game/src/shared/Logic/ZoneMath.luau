--!strict
-- Which zone is a position in? Pure function over MapData-shaped zones.

export type ZoneLike = {
	Name: string,
	Type: string,
	X: number,
	Z: number,
	SizeX: number,
	SizeZ: number,
	MinY: number?,
	MaxY: number?,
	Turf: string?,
}

export type ZoneResult = {
	Name: string,
	BaseType: string, -- "Green" | "Yellow" | "Red" (Road counts as the default, Water as Red)
	Type: string, -- effective type after the turf war rule
	Turf: string?,
}

local ZoneMath = {}

local function contains(zone: ZoneLike, x: number, y: number, z: number): boolean
	if math.abs(x - zone.X) > zone.SizeX / 2 or math.abs(z - zone.Z) > zone.SizeZ / 2 then
		return false
	end
	if zone.MinY and y < zone.MinY then
		return false
	end
	if zone.MaxY and y > zone.MaxY then
		return false
	end
	return true
end

local function baseType(zoneType: string, default: string): string
	if zoneType == "Road" then
		return default
	elseif zoneType == "Water" then
		return "Red"
	end
	return zoneType
end

-- Finds the zone at (x, y, z). Roads only count when nothing else contains the point.
-- Among the rest, the smallest zone wins, so small safe pockets override big areas.
-- turfWarActive: during After School, turf zones are Red unless the pocket itself is Green.
function ZoneMath.Find(zones: { ZoneLike }, x: number, y: number, z: number, defaultType: string, turfWarActive: boolean): ZoneResult
	local best: ZoneLike? = nil
	local bestArea = math.huge
	local road: ZoneLike? = nil
	local turf: string? = nil
	for _, zone in zones do
		if contains(zone, x, y, z) then
			if zone.Turf and not turf then
				turf = zone.Turf
			end
			if zone.Type == "Road" then
				road = road or zone
			else
				local area = zone.SizeX * zone.SizeZ
				if area < bestArea then
					best = zone
					bestArea = area
				end
			end
		end
	end

	local chosen = best or road
	local name = if chosen then chosen.Name else "Streets"
	local base = if chosen then baseType(chosen.Type, defaultType) else defaultType
	local effective = base
	if turfWarActive and turf and base ~= "Green" then
		effective = "Red"
	end
	return { Name = name, BaseType = base, Type = effective, Turf = turf }
end

-- Can two players fight here? Both must be in a zone that allows open fighting.
function ZoneMath.AllowsOpenFight(a: string, b: string): boolean
	return a == "Red" and b == "Red"
end

-- Duels are allowed anywhere except Green zones.
function ZoneMath.AllowsDuel(a: string, b: string): boolean
	return a ~= "Green" and b ~= "Green"
end

return ZoneMath
