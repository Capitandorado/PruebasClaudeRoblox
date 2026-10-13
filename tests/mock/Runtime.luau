-- Mock Roblox runtime: builds the DataModel from a Rojo sourcemap and runs the real game
-- scripts. The server and every client get their own VM (module cache, globals), remotes
-- copy their arguments like the network does, and time is fully simulated.

local roblox = require("@lune/roblox")
local luau = require("@lune/luau")
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local Scheduler = require("./Scheduler")
local Signal = require("./Signal")
local Instance = require("./Instance")
local Services = require("./Services")
local DataStore = require("./DataStore")

local internals = Instance.internals
local typeTags = Signal.typeTags

local Runtime = {}
Runtime.__index = Runtime

-- One scheduler / world shared by every runtime created in the process, so several
-- simulated servers can run side by side (session-lock tests).
local world = { scheduler = nil, rbx = roblox, runtime = nil }
-- The runtime that owns the running thread (several simulated servers may coexist).
function world.getRuntime()
	local context = world.scheduler and world.scheduler.current
	return (context and context.runtime) or world.runtime
end
local sharedScheduler = nil

local function mockTypeof(value)
	local tag = typeTags[value]
	if tag then
		return tag
	end
	return typeof(value)
end
Runtime.typeof = mockTypeof

-- Datatype shims that Lune does not provide ---------------------------------------------

local function makeTweenInfo()
	local TweenInfo = {}
	function TweenInfo.new(time, style, direction, repeatCount, reverses, delayTime)
		local info = {
			Time = time or 1,
			EasingStyle = style or roblox.Enum.EasingStyle.Quad,
			EasingDirection = direction or roblox.Enum.EasingDirection.Out,
			RepeatCount = repeatCount or 0,
			Reverses = reverses or false,
			DelayTime = delayTime or 0,
		}
		typeTags[info] = "TweenInfo"
		return table.freeze(info)
	end
	return table.freeze(TweenInfo)
end

local function makeRandom(scheduler)
	local RandomClass = {}
	RandomClass.__index = RandomClass
	local M = 2147483647
	local function nextRaw(self)
		self._state = (self._state * 16807) % M
		return self._state
	end
	function RandomClass:NextNumber(min, max)
		local unit = (nextRaw(self) - 1) / (M - 1)
		if min == nil then
			return unit
		end
		return min + (max - min) * unit
	end
	function RandomClass:NextInteger(min, max)
		assert(type(min) == "number" and type(max) == "number", "NextInteger expects two numbers")
		if max < min then
			error("invalid argument #2 to 'NextInteger' (interval is empty)", 2)
		end
		return min + math.floor(self:NextNumber() * (max - min + 1) - 1e-12)
	end
	function RandomClass:NextUnitVector()
		local v = roblox.Vector3.new(self:NextNumber(-1, 1), self:NextNumber(-1, 1), self:NextNumber(-1, 1))
		if v.Magnitude < 1e-6 then
			return roblox.Vector3.new(0, 1, 0)
		end
		return v.Unit
	end
	function RandomClass:Shuffle(t)
		for i = #t, 2, -1 do
			local j = self:NextInteger(1, i)
			t[i], t[j] = t[j], t[i]
		end
	end
	function RandomClass:Clone()
		local copy = setmetatable({ _state = self._state }, RandomClass)
		typeTags[copy] = "Random"
		return copy
	end
	local Random = {}
	local counter = 0
	function Random.new(seed)
		counter += 1
		local state = if seed then math.floor(math.abs(seed)) % (M - 1) + 1 else (counter * 7919 + 12345) % (M - 1) + 1
		local rng = setmetatable({ _state = state }, RandomClass)
		typeTags[rng] = "Random"
		return rng
	end
	return table.freeze(Random)
end

local function makeDateTime(scheduler)
	local DateTimeClass = {}
	DateTimeClass.__index = DateTimeClass
	local function fromMillis(ms)
		local dt =
			setmetatable({ UnixTimestampMillis = math.floor(ms), UnixTimestamp = math.floor(ms / 1000) }, DateTimeClass)
		typeTags[dt] = "DateTime"
		return dt
	end
	function DateTimeClass:ToIsoDate()
		return os.date("!%Y-%m-%dT%H:%M:%SZ", self.UnixTimestamp)
	end
	function DateTimeClass:FormatUniversalTime(format)
		return os.date("!%Y-%m-%d %H:%M:%S", self.UnixTimestamp) .. " (" .. tostring(format) .. ")"
	end
	function DateTimeClass:ToUniversalTime()
		local t = os.date("!*t", self.UnixTimestamp)
		return {
			Year = t.year,
			Month = t.month,
			Day = t.day,
			Hour = t.hour,
			Minute = t.min,
			Second = t.sec,
			Millisecond = 0,
		}
	end
	local DateTime = {}
	function DateTime.now()
		return fromMillis((scheduler.epoch + scheduler.clock) * 1000)
	end
	function DateTime.fromUnixTimestamp(seconds)
		return fromMillis(seconds * 1000)
	end
	function DateTime.fromUnixTimestampMillis(ms)
		return fromMillis(ms)
	end
	return table.freeze(DateTime)
end

-- Lune's CFrame.lookAt returns a flipped frame when the direction is parallel to the Z axis
-- (e.g. lookAt((0,0,150), origin)); Roblox does not. This matches the engine's behaviour.
local function makeCFrame()
	local CFrame = roblox.CFrame
	local Vector3 = roblox.Vector3
	local function lookAt(at, target, up)
		up = up or Vector3.new(0, 1, 0)
		local direction = target - at
		if direction.Magnitude < 1e-9 then
			return CFrame.new(at)
		end
		local look = direction.Unit
		local right = look:Cross(up)
		if right.Magnitude < 1e-6 then
			right = look:Cross(Vector3.new(0, 0, 1))
		end
		right = right.Unit
		local upVector = right:Cross(look).Unit
		return CFrame.fromMatrix(at, right, upVector, -look)
	end
	return setmetatable({ lookAt = lookAt }, { __index = CFrame })
end

-- Lune's ColorSequence.new(a, b) and NumberSequence.new(a, b) ignore `b`; Roblox builds a
-- two-keypoint gradient from it.
local function makeSequences()
	local function wrap(sequenceType, keypointType)
		local original = roblox[sequenceType]
		local function new(first, second, ...)
			if select("#", ...) == 0 and second ~= nil and type(first) ~= "table" then
				return original.new({ roblox[keypointType].new(0, first), roblox[keypointType].new(1, second) })
			end
			return original.new(first, second, ...)
		end
		return setmetatable({ new = new }, { __index = original })
	end
	return wrap("ColorSequence", "ColorSequenceKeypoint"), wrap("NumberSequence", "NumberSequenceKeypoint")
end

local function makeParams(typeName, defaults)
	local Params = {}
	function Params.new()
		local params = table.clone(defaults)
		typeTags[params] = typeName
		return params
	end
	return table.freeze(Params)
end

-- Network copy (what survives a RemoteEvent) --------------------------------------------

local function netCopy(runtime, value, seen)
	local kind = mockTypeof(value)
	if kind == "function" or kind == "thread" or kind == "userdata" then
		return nil
	elseif kind == "Instance" then
		return if internals[value].destroyed then nil else value
	elseif kind == "table" then
		seen = seen or {}
		if seen[value] then
			error("Cannot send cyclic tables over the network", 0)
		end
		seen[value] = true
		local copy = {}
		local length = #value
		local dropped = false
		for key, inner in value do
			local keyType = type(key)
			if keyType == "number" and length > 0 and key >= 1 and key <= length and key == math.floor(key) then
				copy[key] = netCopy(runtime, inner, seen)
			elseif keyType == "string" then
				if length > 0 then
					dropped = true
				else
					copy[key] = netCopy(runtime, inner, seen)
				end
			elseif keyType == "number" then
				if length > 0 then
					dropped = true
				else
					runtime:log(
						"netwarn",
						"Numeric dictionary key " .. tostring(key) .. " converted to string by the network"
					)
					copy[tostring(key)] = netCopy(runtime, inner, seen)
				end
			else
				dropped = true
			end
		end
		if dropped then
			runtime:log("netwarn", "Mixed table sent over the network: non-array keys were dropped")
		end
		seen[value] = nil
		return copy
	end
	return value
end

local function packCopy(runtime, ...)
	local packed = table.pack(...)
	for i = 1, packed.n do
		packed[i] = netCopy(runtime, packed[i])
	end
	return packed
end

-- Construction ------------------------------------------------------------------------

local SERVICE_NAMES = {
	"Workspace",
	"Players",
	"Lighting",
	"ReplicatedStorage",
	"ReplicatedFirst",
	"ServerScriptService",
	"ServerStorage",
	"StarterGui",
	"StarterPack",
	"StarterPlayer",
	"SoundService",
	"RunService",
}

function Runtime.new(options)
	options = options or {}
	-- Each runtime gets its own clock unless it must run side by side with another server.
	if not sharedScheduler or not options.shareScheduler then
		sharedScheduler = Scheduler.new()
		world.scheduler = sharedScheduler
	end
	local self = setmetatable({}, Runtime)
	self.scheduler = sharedScheduler
	self.scheduler.verbose = options.verbose == true
	self.verbose = options.verbose == true
	self.isStudio = options.isStudio == true
	self.dataStoreBackend = options.backend or DataStore.newBackend()
	self.messaging = options.messaging or { subscribers = {} }
	self.jobId = options.jobId or ("job-" .. tostring(math.random(1, 1e9)))
	self.output = {}
	self.sounds = {}
	self.closeCallbacks = {}
	self.clients = {}
	self.kicks = {}
	self.services = {}
	self.pendingClientEvents = {}
	self.characterAutoLoads = options.characterAutoLoads ~= false
	-- { ["Shared.Config.X"] = function(moduleValue) } applied in every VM after loading, matched
	-- against the end of the module's full name (tests use it to fill config placeholders).
	self.modulePatches = options.modulePatches or {}
	self.marketplace = {
		ownedPasses = {}, -- [userId] = { [passId] = true }
		prices = {},
		prompts = {},
		latency = 0.05,
		failOwnership = false,
		nextPurchaseId = 1,
	}

	world.runtime = self
	Instance.init(world)
	Services.init(world)
	DataStore.init(world)

	local game = Instance.create("DataModel")
	game.Name = "Game"
	internals[game].runtime = self
	Instance.setInternal(game, "JobId", self.jobId)
	Instance.setInternal(game, "PlaceId", options.placeId or 0)
	Instance.setInternal(game, "GameId", options.gameId or 0)
	Instance.setInternal(game, "CreatorId", options.creatorId or 0)
	Instance.setInternal(game, "PrivateServerId", "")
	self.game = game
	for _, name in SERVICE_NAMES do
		self:getService(name, true)
	end
	self.workspace = self.services.Workspace
	local camera = Instance.create("Camera")
	camera.Parent = self.workspace
	Instance.setInternal(self.workspace, "CurrentCamera", camera)
	self.camera = camera
	local starterPlayer = self.services.StarterPlayer
	Instance.create("StarterPlayerScripts", starterPlayer)
	Instance.create("StarterCharacterScripts", starterPlayer)

	self.serverVM = self:newVM("server")
	self.serverContext = { kind = "server", name = "server:" .. self.jobId, runtime = self, vm = self.serverVM }

	self.scheduler.listeners = self.scheduler.listeners or {}
	self.stepListener = function(dt)
		self:onStep(dt)
	end
	table.insert(self.scheduler.listeners, self.stepListener)
	self.scheduler.onStep = function(dt)
		for _, listener in self.scheduler.listeners do
			listener(dt)
		end
	end
	return self
end

function Runtime:getService(name, create)
	local existing = self.services[name]
	if existing then
		return existing
	end
	if not create then
		return nil
	end
	local Api = require("./Api")
	local info = Api.class(name)
	if not info or not info.isService then
		error(string.format("'%s' is not a valid Service name", tostring(name)), 3)
	end
	local service = Instance.create(name)
	service.Name = name
	service.Parent = self.game
	self.services[name] = service
	return service
end

function Runtime:log(kind, ...)
	local parts = table.pack(...)
	for i = 1, parts.n do
		parts[i] = tostring(parts[i])
	end
	local text = table.concat(parts, " ", 1, parts.n)
	local context = self.scheduler.current
	table.insert(self.output, { kind = kind, text = text, context = context and context.name or "test" })
	if self.verbose then
		print(string.format("[%s][%s] %s", kind, context and context.name or "test", text))
	end
end

function Runtime:recordSound(sound)
	table.insert(self.sounds, { id = sound.SoundId, name = sound.Name, time = self.scheduler.clock })
end

-- VMs ---------------------------------------------------------------------------------

function Runtime:newVM(name)
	local vm = { name = name, moduleCache = {}, G = {}, shared = {} }
	local scheduler = self.scheduler
	local runtime = self
	local env = {}
	env.math = math
	env.table = table
	env.coroutine = coroutine
	env.utf8 = utf8
	env.bit32 = bit32
	env.buffer = buffer
	env.debug = debug
	env.string = string
	env.os = {
		time = function(t)
			if t then
				return os.time(t)
			end
			return math.floor(scheduler.epoch + scheduler.clock)
		end,
		clock = function()
			return scheduler.clock
		end,
		date = function(format, t)
			return os.date(format, t or math.floor(scheduler.epoch + scheduler.clock))
		end,
		difftime = os.difftime,
	}
	env.print = function(...)
		runtime:log("print", ...)
	end
	env.warn = function(...)
		runtime:log("warn", ...)
	end
	env.error = error
	env.assert = assert
	env.pcall = pcall
	env.xpcall = xpcall
	env.select = select
	env.type = type
	env.tostring = tostring
	env.tonumber = tonumber
	env.pairs = pairs
	env.ipairs = ipairs
	env.next = next
	env.setmetatable = setmetatable
	env.getmetatable = getmetatable
	env.rawget = rawget
	env.rawset = rawset
	env.rawequal = rawequal
	env.rawlen = rawlen
	env.newproxy = newproxy
	env.gcinfo = gcinfo
	env.unpack = table.unpack
	env.typeof = mockTypeof
	env.game = self.game
	env.workspace = self.workspace
	env.Instance = table.freeze({
		new = function(className, parent)
			return Instance.new(className, parent)
		end,
	})
	for _, name in
		{
			"Vector3",
			"Vector2",
			"CFrame",
			"Color3",
			"BrickColor",
			"UDim",
			"UDim2",
			"NumberSequence",
			"NumberSequenceKeypoint",
			"ColorSequence",
			"ColorSequenceKeypoint",
			"NumberRange",
			"Rect",
			"Ray",
			"Region3",
			"Font",
			"Faces",
			"Axes",
			"PhysicalProperties",
			"Enum",
			"Vector3int16",
			"Vector2int16",
			"Content",
		}
	do
		env[name] = roblox[name]
	end
	env.CFrame = makeCFrame()
	env.ColorSequence, env.NumberSequence = makeSequences()
	env.TweenInfo = makeTweenInfo()
	env.Random = makeRandom(scheduler)
	env.DateTime = makeDateTime(scheduler)
	env.RaycastParams = makeParams("RaycastParams", {
		FilterDescendantsInstances = {},
		FilterType = roblox.Enum.RaycastFilterType.Exclude,
		IgnoreWater = false,
		CollisionGroup = "Default",
		RespectCanCollide = false,
	})
	env.OverlapParams = makeParams("OverlapParams", {
		FilterDescendantsInstances = {},
		FilterType = roblox.Enum.RaycastFilterType.Exclude,
		MaxParts = 0,
		CollisionGroup = "Default",
		RespectCanCollide = false,
	})
	env.task = table.freeze({
		spawn = function(fn, ...)
			return scheduler:spawn(fn, ...)
		end,
		defer = function(fn, ...)
			return scheduler:defer(fn, ...)
		end,
		delay = function(seconds, fn, ...)
			return scheduler:delay(seconds, fn, ...)
		end,
		wait = function(seconds)
			return scheduler:wait(seconds)
		end,
		cancel = function(thread)
			scheduler:cancel(thread)
		end,
		synchronize = function() end,
		desynchronize = function() end,
	})
	env.tick = function()
		return scheduler.epoch + scheduler.clock
	end
	env.time = function()
		return scheduler.clock
	end
	env.elapsedTime = env.time
	env._G = vm.G
	env.shared = vm.shared
	env.require = function(target)
		return runtime:require(vm, target)
	end
	vm.env = env
	return vm
end

-- Lune's fs functions yield to Lune's own scheduler, so sources must never be read from
-- inside a simulated thread: they are cached while the project loads (main thread).
local sourceCache = {}
local function cacheSource(path)
	if not sourceCache[path] then
		sourceCache[path] = fs.readFile(path)
	end
end
local function readSource(path)
	local source = sourceCache[path]
	if not source then
		error("Mock: source not preloaded: " .. tostring(path), 3)
	end
	return source
end

function Runtime:loadChunk(inst, vm)
	local data = internals[inst]
	if not data.sourcePath then
		error("Mock: script " .. Instance.getFullName(inst) .. " has no source", 2)
	end
	local env = setmetatable({ script = inst }, { __index = vm.env })
	return luau.load(readSource(data.sourcePath), {
		debugName = Instance.getFullName(inst),
		environment = env,
		injectGlobals = false,
	})
end

function Runtime:require(vm, target)
	if mockTypeof(target) ~= "Instance" then
		error("Attempted to call require with invalid argument(s).", 2)
	end
	local data = internals[target]
	if data.className ~= "ModuleScript" then
		error("Attempted to call require with a non-ModuleScript: " .. Instance.getFullName(target), 2)
	end
	local cached = vm.moduleCache[target]
	if cached then
		if cached.loading then
			error("Requested module was required recursively: " .. Instance.getFullName(target), 2)
		end
		if cached.failed then
			error("Requested module experienced an error while loading: " .. Instance.getFullName(target), 2)
		end
		return cached.value
	end
	cached = { loading = true }
	vm.moduleCache[target] = cached
	local chunk = self:loadChunk(target, vm)
	local results = table.pack(pcall(chunk))
	cached.loading = false
	if not results[1] then
		cached.failed = true
		error(results[2], 0)
	end
	if results.n ~= 2 then
		cached.failed = true
		error("Module code did not return exactly one value: " .. Instance.getFullName(target), 2)
	end
	cached.value = results[2]
	local fullName = Instance.getFullName(target)
	for suffix, patch in self.modulePatches do
		if fullName == suffix or string.sub(fullName, -(#suffix + 1)) == "." .. suffix then
			patch(cached.value)
		end
	end
	return cached.value
end

function Runtime:runScript(inst, context)
	local chunk = self:loadChunk(inst, context.vm)
	return self.scheduler:spawnIn(context, chunk)
end

-- Project loading -----------------------------------------------------------------------

local function scriptPathOf(node)
	for _, path in node.filePaths or {} do
		if string.match(path, "%.luau?$") then
			return path
		end
	end
	return nil
end

function Runtime:buildNode(node, parent)
	local existing = parent:FindFirstChild(node.name)
	local inst
	if existing and existing.ClassName == node.className then
		inst = existing
	else
		inst = Instance.create(node.className)
		inst.Name = node.name
	end
	local path = scriptPathOf(node)
	if path then
		cacheSource(path)
		internals[inst].sourcePath = path
	end
	for _, child in node.children or {} do
		self:buildNode(child, inst)
	end
	if inst.Parent ~= parent then
		inst.Parent = parent
	end
	return inst
end

function Runtime:loadSourcemap(path)
	local map = serde.decode("json", fs.readFile(path))
	for _, serviceNode in map.children or {} do
		local service = self:getService(serviceNode.className, true)
		for _, child in serviceNode.children or {} do
			self:buildNode(child, service)
		end
	end
end

function Runtime:startServer()
	local function runIn(container)
		for _, inst in Instance.descendants(container) do
			if internals[inst].className == "Script" and internals[inst].sourcePath and inst.Enabled then
				self:runScript(inst, self.serverContext)
			end
		end
	end
	runIn(self.services.ServerScriptService)
	runIn(self.workspace)
	self.scheduler:flushDeferred()
end

-- Players -------------------------------------------------------------------------------

function Runtime:spawnCharacter(player)
	local old = player.Character
	if old then
		old:Destroy()
	end
	local model = Instance.create("Model")
	model.Name = player.Name
	local root = Instance.create("Part")
	root.Name = "HumanoidRootPart"
	root.Size = roblox.Vector3.new(2, 2, 1)
	root.CFrame = roblox.CFrame.new(0, 10, 0)
	root.Parent = model
	local head = Instance.create("Part")
	head.Name = "Head"
	head.Size = roblox.Vector3.new(2, 1, 1)
	head.CFrame = roblox.CFrame.new(0, 11.5, 0)
	head.Parent = model
	local humanoid = Instance.create("Humanoid")
	humanoid.Parent = model
	model.PrimaryPart = root
	player.Character = model
	model.Parent = self.workspace
	Instance.getSignal(player, "CharacterAdded"):Fire(model)
	return model
end

function Runtime:addPlayer(options)
	options = options or {}
	local userId = options.userId or math.random(1, 1e9)
	local player = Instance.create("Player")
	player.Name = options.name or ("Player" .. userId)
	Instance.setInternal(player, "UserId", userId)
	Instance.setInternal(player, "DisplayName", options.displayName or player.Name)
	Instance.setInternal(player, "AccountAge", options.accountAge or 100)
	Instance.create("Backpack", player)
	local playerGui = Instance.create("PlayerGui", player)
	local playerScripts = Instance.create("PlayerScripts", player)

	local vm = self:newVM("client:" .. userId)
	local context = { kind = "client", name = "client:" .. userId, runtime = self, player = player, vm = vm }
	self.clients[player] = context

	player.Parent = self.services.Players
	Instance.getSignal(self.services.Players, "PlayerAdded"):Fire(player)

	-- Client boot: StarterGui and StarterPlayerScripts are copied, then LocalScripts run.
	for _, child in self.services.StarterGui:GetChildren() do
		local copy = child:Clone()
		if copy then
			copy.Parent = playerGui
		end
	end
	local starterScripts = self.services.StarterPlayer:FindFirstChildOfClass("StarterPlayerScripts")
	if starterScripts then
		for _, child in starterScripts:GetChildren() do
			local copy = child:Clone()
			if copy then
				copy.Parent = playerScripts
			end
		end
	end
	if not options.noClient then
		for _, inst in Instance.descendants(playerScripts) do
			if internals[inst].className == "LocalScript" and internals[inst].sourcePath and inst.Enabled then
				self:runScript(inst, context)
			end
		end
	end
	if self.characterAutoLoads then
		self.scheduler:delay(0.1, function()
			if player.Parent then
				self:spawnCharacter(player)
			end
		end)
	end
	self.scheduler:flushDeferred()
	return player
end

function Runtime:removePlayer(player)
	if not player.Parent then
		return
	end
	Instance.getSignal(self.services.Players, "PlayerRemoving"):Fire(player)
	self.scheduler:flushDeferred()
	local context = self.clients[player]
	if context then
		context.dead = true
	end
	if player.Character then
		player.Character:Destroy()
	end
	player.Parent = nil
end

function Runtime:kick(player, message)
	table.insert(self.kicks, { player = player, userId = player.UserId, message = message })
	self:log("kick", player.Name, message)
	self.scheduler:defer(function()
		self:removePlayer(player)
	end)
end

-- Remotes -------------------------------------------------------------------------------

local function contextOrError(self, kind, what)
	local context = self.scheduler.current
	if not context or context.kind ~= kind then
		error(what .. " can only be called from the " .. kind, 3)
	end
	if context.dead then
		error("client has disconnected", 3)
	end
	return context
end

function Runtime:fireServer(remote, ...)
	local context = contextOrError(self, "client", "FireServer")
	local args = packCopy(self, ...)
	local player = context.player
	self.scheduler:defer(function()
		if not player.Parent then
			return
		end
		Instance.getSignal(remote, "OnServerEvent"):fireFiltered(function(c)
			return c ~= nil and c.kind == "server" and c.runtime == self
		end, player, table.unpack(args, 1, args.n))
	end)
end

local function hasClientListener(remote, player)
	local signal = internals[remote].signals.OnClientEvent
	if not signal then
		return false
	end
	for _, connection in signal._connections do
		local c = connection._context
		if c and c.kind == "client" and c.player == player then
			return true
		end
	end
	return false
end

function Runtime:deliverClient(remote, player, args)
	if not player.Parent then
		return
	end
	if not hasClientListener(remote, player) then
		table.insert(self.pendingClientEvents, { remote = remote, player = player, args = args })
		return
	end
	Instance.getSignal(remote, "OnClientEvent"):fireFiltered(function(c)
		return c ~= nil and c.kind == "client" and c.player == player and not c.dead
	end, table.unpack(args, 1, args.n))
end

function Runtime:fireClient(remote, player, ...)
	contextOrError(self, "server", "FireClient")
	if mockTypeof(player) ~= "Instance" or player.ClassName ~= "Player" then
		error("FireClient: player argument must be a Player", 3)
	end
	local args = packCopy(self, ...)
	self.scheduler:defer(function()
		self:deliverClient(remote, player, args)
	end)
end

function Runtime:fireAllClients(remote, ...)
	contextOrError(self, "server", "FireAllClients")
	local args = packCopy(self, ...)
	self.scheduler:defer(function()
		for _, player in self.services.Players:GetPlayers() do
			self:deliverClient(remote, player, args)
		end
	end)
end

function Runtime:invokeServer(remote, ...)
	local context = contextOrError(self, "client", "InvokeServer")
	local args = packCopy(self, ...)
	local caller = coroutine.running()
	local scheduler = self.scheduler
	local waited = 0
	while not Instance.callback(remote, "OnServerInvoke") do
		if waited > 30 then
			error("InvokeServer: no OnServerInvoke callback after 30s", 2)
		end
		waited += scheduler:wait(0.1)
	end
	local callback = Instance.callback(remote, "OnServerInvoke")
	scheduler:spawnIn(self.serverContext, function()
		local results = table.pack(pcall(callback, context.player, table.unpack(args, 1, args.n)))
		local copied = { n = results.n, results[1] }
		for i = 2, results.n do
			copied[i] = netCopy(self, results[i])
		end
		scheduler:defer(function()
			scheduler:resume(caller, copied)
		end)
	end)
	local results = coroutine.yield()
	if not results[1] then
		error("Server error: " .. tostring(results[2]), 2)
	end
	return table.unpack(results, 2, results.n)
end

-- Messaging -----------------------------------------------------------------------------

function Runtime:publishMessage(topic, message)
	local subscribers = self.messaging.subscribers[topic] or {}
	local payload = { Data = netCopy(self, message), Sent = self.scheduler.epoch + self.scheduler.clock }
	for _, subscriber in subscribers do
		self.scheduler:delay(0.1, function()
			if subscriber.connected then
				self.scheduler:spawnIn(subscriber.context, subscriber.callback, payload)
			end
		end)
	end
end

function Runtime:subscribeMessage(topic, callback)
	self.messaging.subscribers[topic] = self.messaging.subscribers[topic] or {}
	local subscriber = { callback = callback, context = self.scheduler.current, connected = true }
	table.insert(self.messaging.subscribers[topic], subscriber)
	local connection = {
		Disconnect = function()
			subscriber.connected = false
		end,
	}
	typeTags[connection] = "RBXScriptConnection"
	return connection
end

-- Lifecycle ---------------------------------------------------------------------------

function Runtime:bindToClose(fn)
	table.insert(self.closeCallbacks, fn)
end

function Runtime:onStep(dt)
	local runService = self.services.RunService
	local data = internals[runService]
	local signals = data.signals
	if signals.Stepped then
		signals.Stepped:Fire(self.scheduler.clock, dt)
	end
	if signals.RenderStepped then
		signals.RenderStepped:fireFiltered(function(c)
			return c ~= nil and c.kind == "client" and not c.dead
		end, dt)
	end
	if signals.Heartbeat then
		signals.Heartbeat:fireFiltered(function(c)
			return c == nil or not c.dead
		end, dt)
	end
	if #self.pendingClientEvents > 0 then
		local pending = self.pendingClientEvents
		self.pendingClientEvents = {}
		for _, entry in pending do
			if self.scheduler.clock - (entry.queuedAt or self.scheduler.clock) < 60 then
				entry.queuedAt = entry.queuedAt or self.scheduler.clock
				self:deliverClient(entry.remote, entry.player, entry.args)
			end
		end
	end
end

-- CollectionService semantics: "instance added" fires when a tagged instance is (or becomes)
-- part of the DataModel, "removed" when it leaves it — not merely when the tag is set.
local function inGame(self, inst)
	local current = inst
	while current do
		if current == self.game then
			return true
		end
		current = internals[current].parent
	end
	return false
end

local function fireTags(self, inst, signalsKey)
	local collection = self.services.CollectionService
	if not collection then
		return
	end
	local signals = internals[collection][signalsKey]
	if not signals then
		return
	end
	local function visit(target)
		for tag in internals[target].tags do
			local signal = signals[tag]
			if signal then
				signal:Fire(target)
			end
		end
		for _, child in internals[target].children do
			visit(child)
		end
	end
	visit(inst)
end

function Runtime:onTagAdded(inst, tag)
	local collection = self.services.CollectionService
	if collection and inGame(self, inst) then
		local data = internals[collection]
		local signal = data.tagSignals and data.tagSignals[tag]
		if signal then
			signal:Fire(inst)
		end
	end
end

function Runtime:onReparent(inst, newParent)
	if newParent and inGame(self, inst) then
		fireTags(self, inst, "tagSignals")
	elseif newParent == nil then
		fireTags(self, inst, "tagRemovedSignals")
	end
end

-- Shuts the server down like Roblox does: every BindToClose callback runs (in parallel)
-- and the server waits up to 30 seconds for them.
function Runtime:shutdown()
	local remaining = #self.closeCallbacks
	for _, callback in self.closeCallbacks do
		self.scheduler:spawnIn(self.serverContext, function()
			callback()
			remaining -= 1
		end)
	end
	local waited = 0
	while remaining > 0 and waited < 30 do
		self.scheduler:step(0.1)
		waited += 0.1
	end
	return remaining == 0
end

-- Simulates a server crash: every thread of this server (and its clients) stops forever,
-- no BindToClose, no saves.
function Runtime:crash()
	self.serverContext.dead = true
	for _, context in self.clients do
		context.dead = true
	end
	local listeners = self.scheduler.listeners
	for index = #listeners, 1, -1 do
		if listeners[index] == self.stepListener then
			table.remove(listeners, index)
		end
	end
end

-- Test helpers --------------------------------------------------------------------------

function Runtime:step(dt)
	self.scheduler:step(dt or 1 / 30)
end

function Runtime:run(seconds, dt)
	self.scheduler:run(seconds, dt)
end

function Runtime:runUntil(predicate, timeout, dt)
	local waited = 0
	timeout = timeout or 10
	while not predicate() do
		if waited >= timeout then
			return false
		end
		self.scheduler:step(dt or 0.05)
		waited += dt or 0.05
	end
	return true
end

-- Gives a test function the globals of a VM (game, Instance, task, Vector3...) while
-- keeping its upvalues. Anything the VM does not define falls back to the test's globals.
local function bindEnv(fn, vm)
	local original = getfenv(fn)
	setfenv(
		fn,
		setmetatable({}, {
			__index = function(_, key)
				local value = vm.env[key]
				if value ~= nil then
					return value
				end
				return original[key]
			end,
		})
	)
	return fn
end

-- Runs `fn` inside a client VM (as that player's LocalScript would) and returns its results.
function Runtime:asClient(player, fn, timeout)
	local context = self.clients[player]
	assert(context, "player has no client context")
	bindEnv(fn, context.vm)
	local done, results = false, nil
	self.scheduler:spawnIn(context, function()
		results = table.pack(pcall(fn))
		done = true
	end)
	assert(
		self:runUntil(function()
			return done
		end, timeout or 30),
		"client call timed out"
	)
	if not results[1] then
		error(results[2], 2)
	end
	return table.unpack(results, 2, results.n)
end

function Runtime:asServer(fn, timeout)
	bindEnv(fn, self.serverVM)
	local done, results = false, nil
	self.scheduler:spawnIn(self.serverContext, function()
		results = table.pack(pcall(fn))
		done = true
	end)
	assert(
		self:runUntil(function()
			return done
		end, timeout or 30),
		"server call timed out"
	)
	if not results[1] then
		error(results[2], 2)
	end
	return table.unpack(results, 2, results.n)
end

-- Requires a ModuleScript in a given VM ("server" or a player) from test code.
function Runtime:requireIn(target, module)
	if target == "server" then
		return self:asServer(function()
			return self:require(self.serverVM, module)
		end)
	end
	local context = self.clients[target]
	return self:asClient(target, function()
		return self:require(context.vm, module)
	end)
end

function Runtime:click(button)
	Services.click(button)
	self.scheduler:flushDeferred()
end

function Runtime:find(root, path)
	local current = root
	for name in string.gmatch(path, "[^%.]+") do
		current = current and Instance.findFirstChild(current, name)
	end
	return current
end

function Runtime:findDescendant(root, name)
	return Instance.findFirstChild(root, name, true)
end

-- Completes a Game Pass prompt as Roblox would (ownership + server event).
function Runtime:completePassPurchase(player, passId, purchased)
	if purchased then
		self.marketplace.ownedPasses[player.UserId] = self.marketplace.ownedPasses[player.UserId] or {}
		self.marketplace.ownedPasses[player.UserId][passId] = true
	end
	local service = self.services.MarketplaceService
	self:asServer(function()
		Instance.getSignal(service, "PromptGamePassPurchaseFinished"):Fire(player, passId, purchased == true)
	end)
	self:run(0.3, 0.05)
end

-- Delivers a Developer Product receipt to the server's ProcessReceipt callback and returns
-- its decision. Pass the same `purchaseId` to simulate Roblox retrying a receipt.
function Runtime:completeProductPurchase(player, productId, purchaseId)
	if not purchaseId then
		purchaseId = "mock-purchase-" .. self.marketplace.nextPurchaseId
		self.marketplace.nextPurchaseId += 1
	end
	local service = self.services.MarketplaceService
	local callback = Instance.callback(service, "ProcessReceipt")
	assert(callback, "the server did not set MarketplaceService.ProcessReceipt")
	local decision = self:asServer(function()
		return callback({
			PlayerId = player.UserId,
			ProductId = productId,
			PurchaseId = purchaseId,
			CurrencySpent = self.marketplace.prices[productId] or 99,
			CurrencyType = "Robux",
			PlaceIdWherePurchased = 0,
		})
	end)
	return decision, purchaseId
end

function Runtime:errors()
	return self.scheduler.errors
end

function Runtime:clearErrors()
	table.clear(self.scheduler.errors)
end

function Runtime:outputOf(kind)
	local result = {}
	for _, entry in self.output do
		if entry.kind == kind then
			table.insert(result, entry.text)
		end
	end
	return result
end

return Runtime
