--!strict
-- Collects connections, instances, threads and functions, and cleans them all up at once.

local Cleaner = {}
Cleaner.__index = Cleaner

export type Cleaner = typeof(setmetatable({} :: { _items: { any } }, Cleaner))

function Cleaner.new(): Cleaner
	return setmetatable({ _items = {} }, Cleaner)
end

function Cleaner.Add<T>(self: Cleaner, item: T): T
	table.insert(self._items, item)
	return item
end

function Cleaner.Clean(self: Cleaner)
	local items = self._items
	self._items = {}
	for i = #items, 1, -1 do
		local item = items[i]
		local kind = typeof(item)
		if kind == "RBXScriptConnection" then
			(item :: RBXScriptConnection):Disconnect()
		elseif kind == "Instance" then
			(item :: Instance):Destroy()
		elseif kind == "thread" then
			pcall(task.cancel, item :: thread)
		elseif kind == "function" then
			(item :: () -> ())()
		elseif kind == "table" and type((item :: any).Disconnect) == "function" then
			(item :: any):Disconnect()
		elseif kind == "table" and type((item :: any).Destroy) == "function" then
			(item :: any):Destroy()
		end
	end
end

Cleaner.Destroy = Cleaner.Clean

return Cleaner
