--!strict
-- Lightweight in-process signal for communication between modules on the same machine.

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

function Signal.Fire(self: Signal, ...: any)
	for _, handler in table.clone(self._handlers) do
		task.spawn(handler, ...)
	end
end

function Signal.DisconnectAll(self: Signal)
	table.clear(self._handlers)
end

return Signal
