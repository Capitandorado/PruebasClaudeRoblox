-- Helpers shared by test suites.

local Runtime = require("../mock/Runtime")

local Fixture = {}

-- A runtime with the project loaded but no scripts running: for requiring modules.
function Fixture.modules(options)
	local runtime = Runtime.new(options)
	runtime:loadSourcemap("sourcemap.json")
	return runtime
end

function Fixture.shared(runtime)
	return runtime.services.ReplicatedStorage:FindFirstChild("Shared")
end

-- Requires Shared.<path> in the server VM, e.g. Fixture.require(rt, "Logic.Roller").
function Fixture.require(runtime, path)
	local target = Fixture.shared(runtime)
	for name in string.gmatch(path, "[^%.]+") do
		target = target:FindFirstChild(name)
		assert(target, "module not found: " .. path)
	end
	return runtime:requireIn("server", target)
end

-- A runtime with the server running (plots built, remotes created).
function Fixture.server(options)
	local runtime = Runtime.new(options)
	runtime:loadSourcemap("sourcemap.json")
	runtime:startServer()
	runtime:run(0.5)
	return runtime
end

function Fixture.remotes(runtime)
	return runtime.services.ReplicatedStorage:FindFirstChild("Remotes")
end

-- Sends a request exactly like the client does and returns the response table.
function Fixture.request(runtime, player, action, ...)
	local args = table.pack(...)
	local remote = Fixture.remotes(runtime):FindFirstChild("Request")
	return runtime:asClient(player, function()
		return remote:InvokeServer(action, table.unpack(args, 1, args.n))
	end)
end

-- Adds a player and waits until the server has a ready session (Full state sent).
function Fixture.join(runtime, options)
	options = options or {}
	if options.noClient == nil then
		options.noClient = true
	end
	local player = runtime:addPlayer(options)
	local states = {}
	if options.noClient then
		local stateRemote = Fixture.remotes(runtime):FindFirstChild("State")
		local notifyRemote = Fixture.remotes(runtime):FindFirstChild("Notify")
		runtime:asClient(player, function()
			stateRemote.OnClientEvent:Connect(function(kind, payload)
				table.insert(states, { kind = kind, payload = payload })
			end)
			notifyRemote.OnClientEvent:Connect(function(kind, payload)
				table.insert(states, { kind = "notify:" .. kind, payload = payload })
			end)
		end)
	end
	runtime:runUntil(function()
		for _, entry in states do
			if entry.kind == "Full" then
				return true
			end
		end
		return not options.noClient
	end, 10)
	runtime:run(0.3)
	return player, states
end

-- Server-side session of a player.
function Fixture.session(runtime, player)
	local sessions = runtime:requireIn("server", runtime.services.ServerScriptService.Server.Services.Sessions)
	return sessions.get(player)
end

-- Deterministic RNG compatible with Roblox's Random:NextNumber().
function Fixture.rng(seed)
	local state = (seed or 1) % 2147483646 + 1
	return {
		NextNumber = function()
			state = (state * 16807) % 2147483647
			return (state - 1) / 2147483646
		end,
	}
end

-- RNG that returns a fixed sequence (then repeats the last value).
function Fixture.sequence(values)
	local index = 0
	return {
		NextNumber = function()
			index = math.min(index + 1, #values)
			return values[index]
		end,
	}
end

return Fixture
