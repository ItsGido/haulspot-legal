--!strict
-- Minimal signal: Connect / Once / Fire / Wait. Handlers run in their own thread.

export type Connection = { Disconnect: (self: Connection) -> (), Connected: boolean }

local Signal = {}
Signal.__index = Signal

export type Signal = typeof(setmetatable({} :: { _handlers: { [any]: (...any) -> () } }, Signal))

function Signal.new(): Signal
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal.Connect(self: Signal, handler: (...any) -> ()): Connection
	local key = {}
	self._handlers[key] = handler
	local connection = { Connected = true } :: any
	function connection.Disconnect(conn)
		conn.Connected = false
		self._handlers[key] = nil
	end
	return connection
end

function Signal.Once(self: Signal, handler: (...any) -> ()): Connection
	local connection: Connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		handler(...)
	end)
	return connection
end

function Signal.Fire(self: Signal, ...: any)
	for _, handler in self._handlers do
		task.spawn(handler, ...)
	end
end

function Signal.Wait(self: Signal): ...any
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal.DisconnectAll(self: Signal)
	table.clear(self._handlers)
end

return Signal
