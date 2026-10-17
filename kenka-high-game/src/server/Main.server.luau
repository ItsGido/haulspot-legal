--!strict
-- Server entry point. Loads every ModuleScript in Services, then:
--   1. calls Service.Init(Services) on each (must not yield; wire up references and remotes here)
--   2. calls Service.Start() on each in its own thread (loops, player hooks, yielding work)
-- A service may set `Priority` (lower starts first, default 100). MapService and DataService go first.

local servicesFolder = script.Parent:WaitForChild("Services")

local Services: { [string]: any } = {}
local ordered = {}

for _, module in servicesFolder:GetChildren() do
	if module:IsA("ModuleScript") then
		local ok, service = pcall(require, module)
		if ok then
			Services[module.Name] = service
			table.insert(ordered, { Name = module.Name, Service = service })
		else
			warn(string.format("[Kenka] Failed to load service %s: %s", module.Name, tostring(service)))
		end
	end
end

table.sort(ordered, function(a, b)
	local pa = a.Service.Priority or 100
	local pb = b.Service.Priority or 100
	if pa == pb then
		return a.Name < b.Name
	end
	return pa < pb
end)

for _, entry in ordered do
	if type(entry.Service.Init) == "function" then
		local ok, err = pcall(entry.Service.Init, Services)
		if not ok then
			warn(string.format("[Kenka] %s.Init failed: %s", entry.Name, tostring(err)))
		end
	end
end

for _, entry in ordered do
	if type(entry.Service.Start) == "function" then
		task.spawn(function()
			local ok, err = pcall(entry.Service.Start)
			if not ok then
				warn(string.format("[Kenka] %s.Start failed: %s", entry.Name, tostring(err)))
			end
		end)
	end
end

print(string.format("[Kenka] Server started with %d services", #ordered))
