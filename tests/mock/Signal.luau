-- RBXScriptSignal / RBXScriptConnection mock. Handlers run in new threads, in the context
-- (VM) of whoever connected them. `fireFiltered` lets remotes target a single client.

local Signal = {}
Signal.__index = Signal

local Connection = {}
Connection.__index = Connection

local typeTags = setmetatable({}, { __mode = "k" })
Signal.typeTags = typeTags

function Connection:Disconnect()
	if not self.Connected then
		return
	end
	self.Connected = false
	local list = self._signal._connections
	local index = table.find(list, self)
	if index then
		table.remove(list, index)
	end
end

function Signal.new(scheduler, name)
	local self = setmetatable({
		_scheduler = scheduler,
		_connections = {},
		_waiting = {},
		_name = name or "Signal",
	}, Signal)
	typeTags[self] = "RBXScriptSignal"
	return self
end

function Signal:Connect(fn)
	assert(type(fn) == "function", "Attempt to connect failed: Passed value is not a function")
	local connection = setmetatable({
		Connected = true,
		_fn = fn,
		_signal = self,
		_context = self._scheduler.current,
	}, Connection)
	typeTags[connection] = "RBXScriptConnection"
	table.insert(self._connections, connection)
	return connection
end

function Signal:Once(fn)
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		fn(...)
	end)
	return connection
end

function Signal:ConnectParallel(fn)
	return self:Connect(fn)
end

function Signal:Wait()
	local thread = coroutine.running()
	table.insert(self._waiting, { thread = thread, context = self._scheduler.current })
	return coroutine.yield()
end

function Signal:fireFiltered(filter, ...)
	local scheduler = self._scheduler
	for _, connection in table.clone(self._connections) do
		if connection.Connected and (filter == nil or filter(connection._context)) then
			scheduler:spawnIn(connection._context, connection._fn, ...)
		end
	end
	local waiting = self._waiting
	self._waiting = {}
	for _, entry in waiting do
		if filter == nil or filter(entry.context) then
			scheduler:resume(entry.thread, ...)
		else
			table.insert(self._waiting, entry)
		end
	end
end

function Signal:Fire(...)
	self:fireFiltered(nil, ...)
end

function Signal:hasConnections()
	return #self._connections > 0
end

function Signal:DisconnectAll()
	for _, connection in table.clone(self._connections) do
		connection:Disconnect()
	end
end

return Signal
