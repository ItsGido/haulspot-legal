--!strict
-- Client entry point. Loads every ModuleScript in Controllers, calls Init(Controllers) on each,
-- then Start() on each in its own thread. Same pattern as the server. Lower Priority starts first.

local controllersFolder = script.Parent:WaitForChild("Controllers")

local Controllers: { [string]: any } = {}
local ordered = {}

for _, module in controllersFolder:GetChildren() do
	if module:IsA("ModuleScript") then
		local ok, controller = pcall(require, module)
		if ok then
			Controllers[module.Name] = controller
			table.insert(ordered, { Name = module.Name, Controller = controller })
		else
			warn(string.format("[Kenka] Failed to load controller %s: %s", module.Name, tostring(controller)))
		end
	end
end

table.sort(ordered, function(a, b)
	local pa = a.Controller.Priority or 100
	local pb = b.Controller.Priority or 100
	if pa == pb then
		return a.Name < b.Name
	end
	return pa < pb
end)

for _, entry in ordered do
	if type(entry.Controller.Init) == "function" then
		local ok, err = pcall(entry.Controller.Init, Controllers)
		if not ok then
			warn(string.format("[Kenka] %s.Init failed: %s", entry.Name, tostring(err)))
		end
	end
end

for _, entry in ordered do
	if type(entry.Controller.Start) == "function" then
		task.spawn(function()
			local ok, err = pcall(entry.Controller.Start)
			if not ok then
				warn(string.format("[Kenka] %s.Start failed: %s", entry.Name, tostring(err)))
			end
		end)
	end
end
