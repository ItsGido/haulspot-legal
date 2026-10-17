--!nocheck
-- Prints MapData as JSON (used to regenerate the blueprint map image). Run: .tools/luau tools/export-mapdata.luau
local MapData = require("../src/shared/Map/MapData")
local function enc(v)
	local t = type(v)
	if t == "number" then return tostring(v)
	elseif t == "string" then return string.format("%q", v)
	elseif t == "boolean" then return tostring(v)
	elseif t == "table" then
		if #v > 0 or next(v) == nil then
			local parts = {}
			for _, x in ipairs(v) do table.insert(parts, enc(x)) end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local parts = {}
		for k, x in pairs(v) do
			if type(x) ~= "function" then table.insert(parts, string.format("%q", tostring(k)) .. ":" .. enc(x)) end
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return "null"
end
print(enc({ Ground = MapData.Ground, Zones = MapData.Zones, Buildings = MapData.Buildings, Interactables = MapData.Interactables, TurfWalls = MapData.TurfWalls, Spawns = MapData.Spawns }))
