-- Deterministic coroutine scheduler with a simulated clock.
-- Every thread remembers the "context" (server VM or a client VM) it was created in, so
-- signals, remotes and Players.LocalPlayer behave per VM even though everything runs in
-- one Lune process.

local Scheduler = {}
Scheduler.__index = Scheduler

function Scheduler.new()
	local self = setmetatable({}, Scheduler)
	self.clock = 0
	self.epoch = 1760000000
	self.timed = {}
	self.deferred = {}
	self.contexts = setmetatable({}, { __mode = "k" })
	self.current = nil
	self.errors = {}
	self.onStep = nil
	self.verbose = false
	return self
end

function Scheduler:now()
	return self.clock
end

function Scheduler:contextOf(thread)
	return self.contexts[thread]
end

function Scheduler:resume(thread, ...)
	if coroutine.status(thread) ~= "suspended" then
		return false
	end
	local context = self.contexts[thread]
	if context and context.dead then
		return false
	end
	local previous = self.current
	if context ~= nil then
		self.current = context
	end
	local ok, err = coroutine.resume(thread, ...)
	self.current = previous
	if not ok then
		local trace = debug.traceback(thread, tostring(err))
		local contextName = if context then context.name else "?"
		table.insert(self.errors, { context = contextName, message = tostring(err), trace = trace })
		if self.verbose then
			print("[mock error][" .. contextName .. "] " .. tostring(err) .. "\n" .. trace)
		end
	end
	return ok
end

function Scheduler:create(fn, context)
	local thread = if type(fn) == "thread" then fn else coroutine.create(fn)
	if self.contexts[thread] == nil then
		self.contexts[thread] = context or self.current
	end
	return thread
end

function Scheduler:spawn(fn, ...)
	local thread = self:create(fn)
	self:resume(thread, ...)
	return thread
end

function Scheduler:spawnIn(context, fn, ...)
	local thread = self:create(fn, context)
	self:resume(thread, ...)
	return thread
end

function Scheduler:defer(fn, ...)
	local thread = self:create(fn)
	table.insert(self.deferred, { thread = thread, args = table.pack(...) })
	return thread
end

function Scheduler:delay(seconds, fn, ...)
	local thread = self:create(fn)
	table.insert(self.timed, {
		thread = thread,
		at = self.clock + math.max(0, seconds or 0),
		args = table.pack(...),
	})
	return thread
end

-- Yields the running thread for `seconds` of simulated time. Returns elapsed time.
function Scheduler:wait(seconds)
	local thread = coroutine.running()
	if not coroutine.isyieldable() or self.contexts[thread] == nil then
		-- Yielding a thread the scheduler does not own (e.g. the test's main thread) would
		-- silently end the Lune process, so fail loudly instead.
		error("Mock: yielding outside a simulated thread (wrap the call in runtime:asServer/asClient)", 2)
	end
	local start = self.clock
	table.insert(self.timed, {
		thread = thread,
		at = self.clock + math.max(seconds or 0, 1 / 60),
		start = start,
	})
	return coroutine.yield()
end

-- Suspends the running thread until `resumeFn` is called. Returns what resumeFn passes.
function Scheduler:suspend()
	if not coroutine.isyieldable() then
		error("attempt to yield from a non-yieldable context", 3)
	end
	return coroutine.yield()
end

function Scheduler:cancel(thread)
	for i = #self.timed, 1, -1 do
		if self.timed[i].thread == thread then
			table.remove(self.timed, i)
		end
	end
	for i = #self.deferred, 1, -1 do
		if self.deferred[i].thread == thread then
			table.remove(self.deferred, i)
		end
	end
	if coroutine.status(thread) == "suspended" then
		coroutine.close(thread)
	end
end

function Scheduler:flushDeferred()
	local guard = 0
	while #self.deferred > 0 do
		guard += 1
		if guard > 100000 then
			error("deferred thread loop did not settle")
		end
		local entry = table.remove(self.deferred, 1)
		self:resume(entry.thread, table.unpack(entry.args, 1, entry.args.n))
	end
end

function Scheduler:step(dt)
	self.clock += dt
	if self.onStep then
		self.onStep(dt)
	end
	self:flushDeferred()
	local guard = 0
	while true do
		guard += 1
		if guard > 100000 then
			error("timed thread loop did not settle")
		end
		local bestIndex, best = nil, nil
		for index, entry in self.timed do
			if entry.at <= self.clock and (best == nil or entry.at < best.at) then
				bestIndex, best = index, entry
			end
		end
		if not best then
			break
		end
		table.remove(self.timed, bestIndex)
		if best.args then
			self:resume(best.thread, table.unpack(best.args, 1, best.args.n))
		else
			self:resume(best.thread, self.clock - (best.start or self.clock))
		end
		self:flushDeferred()
	end
end

function Scheduler:run(seconds, dt)
	dt = dt or 1 / 10
	local target = self.clock + seconds
	while self.clock + 1e-9 < target do
		self:step(math.min(dt, target - self.clock))
	end
end

return Scheduler
