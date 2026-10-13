-- Engine behaviour for the classes and services the game uses.
-- Anything not implemented here still exists (validated by the API database) but raises a
-- clear "not implemented in the mock runtime" error when called.

local serde = require("@lune/serde")
local Api = require("./Api")
local Instance = require("./Instance")
local Signal = require("./Signal")

local Services = {}

local M, G, S, D = Instance.Methods, Instance.Getters, Instance.Setters, Instance.ClassDefaults
local internals = Instance.internals
local typeTags = Signal.typeTags

local world = {}
function Services.init(env)
	world = env
end

local function rbx()
	return world.rbx
end

local function scheduler()
	return world.scheduler
end

local function runtime()
	return world.getRuntime()
end

local function currentContext()
	return world.scheduler.current
end

local function isA(inst, className)
	return Api.isA(internals[inst].className, className)
end

-- Parts & models ------------------------------------------------------------------------

D.BasePart = {
	Size = function()
		return rbx().Vector3.new(4, 1, 2)
	end,
	Color = function()
		return rbx().Color3.fromRGB(163, 162, 165)
	end,
	Material = function()
		return rbx().Enum.Material.Plastic
	end,
	Anchored = false,
}
D.Part = {
	Shape = function()
		return rbx().Enum.PartType.Block
	end,
}
D.Camera = {
	ViewportSize = function()
		return rbx().Vector2.new(1280, 720)
	end,
	FieldOfView = 70,
}
D.Humanoid = { Health = 100, MaxHealth = 100, WalkSpeed = 16, JumpPower = 50 }
D.Lighting = { ClockTime = 14, Brightness = 2 }
D.Workspace = { Gravity = 196.2 }
D.GuiObject = {
	Size = function()
		return rbx().UDim2.fromOffset(100, 100)
	end,
	BackgroundColor3 = function()
		return rbx().Color3.fromRGB(255, 255, 255)
	end,
}
-- Roblox centres text by default (the enums' first items are Left/Top, so set them explicitly).
local function centreDefaults(text)
	return {
		Text = text,
		TextXAlignment = function()
			return rbx().Enum.TextXAlignment.Center
		end,
		TextYAlignment = function()
			return rbx().Enum.TextYAlignment.Center
		end,
		BorderSizePixel = 1,
	}
end
-- Layouts start top-left and sort by LayoutOrder in Roblox.
D.UIGridStyleLayout = {
	HorizontalAlignment = function()
		return rbx().Enum.HorizontalAlignment.Left
	end,
	VerticalAlignment = function()
		return rbx().Enum.VerticalAlignment.Top
	end,
	SortOrder = function()
		return rbx().Enum.SortOrder.LayoutOrder
	end,
}
D.TextLabel = centreDefaults("Label")
D.TextButton = centreDefaults("Button")
D.TextBox = centreDefaults("TextBox")
D.Sound = { TimeLength = 1 }
D.ScreenGui = {
	ZIndexBehavior = function()
		return rbx().Enum.ZIndexBehavior.Sibling
	end,
}

local function cframeOf(data)
	return data.props.CFrame or rbx().CFrame.new()
end

local function expectType(key, value, typeName)
	if typeof(value) ~= typeName then
		error(string.format("Unable to assign property %s. %s expected, got %s", key, typeName, typeof(value)), 4)
	end
end

G.BasePart = {
	Position = function(_, data)
		return cframeOf(data).Position
	end,
	Orientation = function(_, data)
		local x, y, z = cframeOf(data):ToOrientation()
		return rbx().Vector3.new(math.deg(x), math.deg(y), math.deg(z))
	end,
	Rotation = function(_, data)
		local x, y, z = cframeOf(data):ToEulerAnglesXYZ()
		return rbx().Vector3.new(math.deg(x), math.deg(y), math.deg(z))
	end,
}

S.BasePart = {
	CFrame = function(_, data, value)
		expectType("CFrame", value, "CFrame")
		data.props.CFrame = value
	end,
	Position = function(_, data, value)
		expectType("Position", value, "Vector3")
		local cf = cframeOf(data)
		data.props.CFrame = rbx().CFrame.new(value) * (cf - cf.Position)
	end,
	Orientation = function(_, data, value)
		expectType("Orientation", value, "Vector3")
		local cf = cframeOf(data)
		data.props.CFrame = rbx().CFrame.new(cf.Position)
			* rbx().CFrame.fromOrientation(math.rad(value.X), math.rad(value.Y), math.rad(value.Z))
	end,
	Size = function(_, data, value)
		expectType("Size", value, "Vector3")
		data.props.Size =
			rbx().Vector3.new(math.max(0.001, value.X), math.max(0.001, value.Y), math.max(0.001, value.Z))
	end,
	BrickColor = function(_, data, value)
		expectType("BrickColor", value, "BrickColor")
		data.props.BrickColor = value
		data.props.Color = value.Color
	end,
}

local function partsOf(inst)
	local parts = {}
	if isA(inst, "BasePart") then
		table.insert(parts, inst)
	end
	for _, desc in Instance.descendants(inst) do
		if isA(desc, "BasePart") then
			table.insert(parts, desc)
		end
	end
	return parts
end

local function boundingBox(inst)
	local parts = partsOf(inst)
	if #parts == 0 then
		return nil, rbx().Vector3.new(0, 0, 0)
	end
	local V3 = rbx().Vector3
	local minV = V3.new(math.huge, math.huge, math.huge)
	local maxV = V3.new(-math.huge, -math.huge, -math.huge)
	for _, part in parts do
		local cf, size = part.CFrame, part.Size
		for _, sx in { -0.5, 0.5 } do
			for _, sy in { -0.5, 0.5 } do
				for _, sz in { -0.5, 0.5 } do
					local corner = cf:PointToWorldSpace(V3.new(size.X * sx, size.Y * sy, size.Z * sz))
					minV = V3.new(math.min(minV.X, corner.X), math.min(minV.Y, corner.Y), math.min(minV.Z, corner.Z))
					maxV = V3.new(math.max(maxV.X, corner.X), math.max(maxV.Y, corner.Y), math.max(maxV.Z, corner.Z))
				end
			end
		end
	end
	return rbx().CFrame.new((minV + maxV) / 2), maxV - minV
end

local function getPivot(inst)
	local data = internals[inst]
	if isA(inst, "BasePart") then
		return cframeOf(data)
	end
	local primary = data.props.PrimaryPart
	if primary and not internals[primary].destroyed then
		return primary.CFrame
	end
	if data.props.WorldPivot then
		return data.props.WorldPivot
	end
	local cf = boundingBox(inst)
	return cf or rbx().CFrame.new()
end

local function pivotTo(inst, target)
	expectType("CFrame", target, "CFrame")
	local data = internals[inst]
	if isA(inst, "BasePart") then
		inst.CFrame = target
		return
	end
	local current = getPivot(inst)
	local delta = target * current:Inverse()
	for _, part in partsOf(inst) do
		part.CFrame = delta * part.CFrame
	end
	if not data.props.PrimaryPart then
		data.props.WorldPivot = target
	end
end

M.PVInstance = {
	GetPivot = function(self)
		return getPivot(self)
	end,
	PivotTo = function(self, target)
		pivotTo(self, target)
	end,
}

G.Model = {
	WorldPivot = function(self)
		return getPivot(self)
	end,
}

S.Model = {
	WorldPivot = function(_, data, value)
		expectType("WorldPivot", value, "CFrame")
		data.props.WorldPivot = value
	end,
}

M.Model = {
	GetBoundingBox = function(self)
		local cf, size = boundingBox(self)
		return cf or rbx().CFrame.new(), size
	end,
	GetExtentsSize = function(self)
		local _, size = boundingBox(self)
		return size
	end,
	SetPrimaryPartCFrame = function(self, cf)
		if not self.PrimaryPart then
			error("Model:SetPrimaryPartCFrame() failed because no PrimaryPart has been set", 2)
		end
		pivotTo(self, cf)
	end,
	GetPrimaryPartCFrame = function(self)
		return self.PrimaryPart and self.PrimaryPart.CFrame
	end,
	MoveTo = function(self, position)
		local pivot = getPivot(self)
		pivotTo(self, rbx().CFrame.new(position) * (pivot - pivot.Position))
	end,
	GetScale = function(self)
		return internals[self].scale or 1
	end,
	ScaleTo = function(self, scale)
		local data = internals[self]
		local current = data.scale or 1
		local factor = scale / current
		local pivot = getPivot(self)
		for _, part in partsOf(self) do
			local rel = pivot:ToObjectSpace(part.CFrame)
			part.Size = part.Size * factor
			part.CFrame = pivot * (rel - rel.Position + rel.Position * factor)
		end
		data.scale = scale
	end,
}

-- GUI -----------------------------------------------------------------------------------

local function viewportSize()
	local rt = world.getRuntime and world.getRuntime()
	local camera = rt and rt.camera
	return if camera then camera.ViewportSize else rbx().Vector2.new(1280, 720)
end

local function absoluteSize(inst)
	local data = internals[inst]
	if isA(inst, "LayerCollector") then
		if isA(inst, "ScreenGui") then
			return viewportSize()
		end
		local size = data.props.Size
		if size and typeof(size) == "UDim2" then
			return rbx().Vector2.new(size.X.Offset, size.Y.Offset)
		end
		return rbx().Vector2.new(200, 50)
	end
	local parent = data.parent
	local parentSize = viewportSize()
	if parent and (isA(parent, "GuiObject") or isA(parent, "LayerCollector")) then
		parentSize = absoluteSize(parent)
	end
	local size = inst.Size
	return rbx().Vector2.new(size.X.Scale * parentSize.X + size.X.Offset, size.Y.Scale * parentSize.Y + size.Y.Offset)
end

local function absolutePosition(inst)
	local data = internals[inst]
	local parent = data.parent
	if not parent or not isA(parent, "GuiObject") then
		local position = inst.Position
		local vp = viewportSize()
		return rbx().Vector2.new(
			position.X.Scale * vp.X + position.X.Offset,
			position.Y.Scale * vp.Y + position.Y.Offset
		)
	end
	local parentPosition = absolutePosition(parent)
	local parentSize = absoluteSize(parent)
	local position = inst.Position
	return rbx().Vector2.new(
		parentPosition.X + position.X.Scale * parentSize.X + position.X.Offset,
		parentPosition.Y + position.Y.Scale * parentSize.Y + position.Y.Offset
	)
end

G.GuiObject = {
	AbsoluteSize = function(self)
		return absoluteSize(self)
	end,
	AbsolutePosition = function(self)
		return absolutePosition(self)
	end,
	AbsoluteRotation = function(self)
		return self.Rotation
	end,
}
G.LayerCollector = {
	AbsoluteSize = function(self)
		return absoluteSize(self)
	end,
	AbsolutePosition = function()
		return rbx().Vector2.new(0, 0)
	end,
}

local function textBounds(self)
	local text = self.Text
	local size = self.TextSize
	return rbx().Vector2.new((utf8.len(text) or #text) * size * 0.55, size)
end
G.TextLabel = { TextBounds = textBounds }
G.TextButton = { TextBounds = textBounds }
G.TextBox = { TextBounds = textBounds }

local function guiActivate(self)
	Instance.getSignal(self, "Activated"):Fire()
	Instance.getSignal(self, "MouseButton1Click"):Fire()
end
Services.click = guiActivate

-- Remotes & bindables -------------------------------------------------------------------

M.RemoteEvent = {
	FireServer = function(self, ...)
		runtime():fireServer(self, ...)
	end,
	FireClient = function(self, player, ...)
		runtime():fireClient(self, player, ...)
	end,
	FireAllClients = function(self, ...)
		runtime():fireAllClients(self, ...)
	end,
}
M.UnreliableRemoteEvent = M.RemoteEvent
M.RemoteFunction = {
	InvokeServer = function(self, ...)
		return runtime():invokeServer(self, ...)
	end,
	InvokeClient = function()
		error("Mock: InvokeClient is intentionally unsupported (unsafe pattern)", 2)
	end,
}
M.BindableEvent = {
	Fire = function(self, ...)
		Instance.getSignal(self, "Event"):Fire(...)
	end,
}
M.BindableFunction = {
	Invoke = function(self, ...)
		local callback = Instance.callback(self, "OnInvoke")
		if not callback then
			error("BindableFunction has no OnInvoke callback", 2)
		end
		return callback(...)
	end,
}

-- Players -------------------------------------------------------------------------------

G.Players = {
	LocalPlayer = function()
		local context = currentContext()
		return if context and context.kind == "client" then context.player else nil
	end,
}

M.Players = {
	GetPlayers = function(self)
		local result = {}
		for _, child in internals[self].children do
			if internals[child].className == "Player" then
				table.insert(result, child)
			end
		end
		return result
	end,
	GetPlayerByUserId = function(self, userId)
		for _, child in internals[self].children do
			if internals[child].className == "Player" and child.UserId == userId then
				return child
			end
		end
		return nil
	end,
	GetPlayerFromCharacter = function(self, character)
		for _, child in internals[self].children do
			if internals[child].className == "Player" and child.Character == character then
				return child
			end
		end
		return nil
	end,
	GetUserThumbnailAsync = function(_, userId)
		return string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", userId), true
	end,
	GetNameFromUserIdAsync = function(_, userId)
		return "Player" .. tostring(userId)
	end,
}

M.Player = {
	Kick = function(self, message)
		runtime():kick(self, message)
	end,
	LoadCharacter = function(self)
		runtime():spawnCharacter(self)
	end,
	GetMouse = function(self)
		local data = internals[self]
		if not data.mouse then
			data.mouse = Instance.create("PlayerMouse")
		end
		return data.mouse
	end,
	IsInGroup = function()
		return false
	end,
	GetRankInGroup = function()
		return 0
	end,
	DistanceFromCharacter = function(self, point)
		local character = self.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		return if root then (root.Position - point).Magnitude else 0
	end,
	GetJoinData = function()
		return {}
	end,
}

-- Run service, workspace, camera --------------------------------------------------------

M.RunService = {
	IsServer = function()
		local context = currentContext()
		return context == nil or context.kind == "server"
	end,
	IsClient = function()
		local context = currentContext()
		return context ~= nil and context.kind == "client"
	end,
	IsStudio = function()
		return runtime().isStudio == true
	end,
	IsRunning = function()
		return true
	end,
	IsRunMode = function()
		return false
	end,
	IsEdit = function()
		return false
	end,
	BindToRenderStep = function(self, name, _priority, fn)
		local data = internals[self]
		data.renderBindings = data.renderBindings or {}
		local context = currentContext()
		local key = (context and context.name or "?") .. ":" .. name
		if data.renderBindings[key] then
			data.renderBindings[key]:Disconnect()
		end
		data.renderBindings[key] = Instance.getSignal(self, "RenderStepped"):Connect(fn)
	end,
	UnbindFromRenderStep = function(self, name)
		local data = internals[self]
		local context = currentContext()
		local key = (context and context.name or "?") .. ":" .. name
		if data.renderBindings and data.renderBindings[key] then
			data.renderBindings[key]:Disconnect()
			data.renderBindings[key] = nil
		end
	end,
}

M.Workspace = {
	GetServerTimeNow = function()
		return scheduler().epoch + scheduler().clock
	end,
	Raycast = function()
		return nil
	end,
	GetPartBoundsInBox = function()
		return {}
	end,
	GetPartBoundsInRadius = function()
		return {}
	end,
	GetPartsInPart = function()
		return {}
	end,
	GetRealPhysicsFPS = function()
		return 60
	end,
}
G.Workspace = {
	DistributedGameTime = function()
		return scheduler().clock
	end,
}

M.Camera = {
	ScreenPointToRay = function(self)
		local cf = self.CFrame
		return rbx().Ray.new(cf.Position, cf.LookVector)
	end,
	ViewportPointToRay = function(self)
		local cf = self.CFrame
		return rbx().Ray.new(cf.Position, cf.LookVector)
	end,
	WorldToViewportPoint = function()
		return rbx().Vector3.new(640, 360, 10), true
	end,
	WorldToScreenPoint = function()
		return rbx().Vector3.new(640, 360, 10), true
	end,
}

M.Humanoid = {
	MoveTo = function() end,
	ChangeState = function() end,
	GetState = function()
		return rbx().Enum.HumanoidStateType.Running
	end,
	TakeDamage = function(self, amount)
		self.Health = math.max(0, self.Health - amount)
	end,
	UnequipTools = function() end,
}
S.Humanoid = {
	Health = function(self, data, value)
		local maxHealth = data.props.MaxHealth or 100
		local health = math.clamp(value, 0, maxHealth)
		local wasAlive = (data.props.Health or 100) > 0
		data.props.Health = health
		if wasAlive and health <= 0 then
			Instance.getSignal(self, "Died"):Fire()
		end
	end,
}

-- Media & effects -------------------------------------------------------------------------

M.Sound = {
	Play = function(self)
		local data = internals[self]
		data.props.Playing = true
		data.playCount = (data.playCount or 0) + 1
		if runtime() then
			runtime():recordSound(self)
		end
		Instance.getSignal(self, "Played"):Fire(self.SoundId)
	end,
	Stop = function(self)
		internals[self].props.Playing = false
		Instance.getSignal(self, "Stopped"):Fire(self.SoundId)
	end,
	Pause = function(self)
		internals[self].props.Playing = false
	end,
	Resume = function(self)
		internals[self].props.Playing = true
	end,
}
G.Sound = {
	IsPlaying = function(_, data)
		return data.props.Playing == true
	end,
	IsLoaded = function()
		return true
	end,
}
M.SoundService = {
	PlayLocalSound = function(_, sound)
		if runtime() then
			runtime():recordSound(sound)
		end
	end,
}
M.ParticleEmitter = {
	Emit = function(self, count)
		local data = internals[self]
		data.emitted = (data.emitted or 0) + (count or 16)
	end,
	Clear = function() end,
}

local TWEENABLE = {
	number = true,
	boolean = true,
	Vector3 = true,
	Vector2 = true,
	CFrame = true,
	Color3 = true,
	UDim2 = true,
	UDim = true,
	NumberRange = true,
	Rect = true,
	EnumItem = true,
}

M.TweenService = {
	Create = function(_, target, info, goals)
		if not Instance.isInstance(target) then
			error("TweenService:Create: Argument 1 must be an Instance", 2)
		end
		if typeTags[info] ~= "TweenInfo" then
			error("TweenService:Create: Argument 2 must be a TweenInfo", 2)
		end
		if type(goals) ~= "table" then
			error("TweenService:Create: Argument 3 must be a table", 2)
		end
		local targetData = internals[target]
		for key, value in goals do
			local prop = targetData.info.props[key]
			if not prop then
				error(
					string.format(
						"TweenService:Create property named '%s' cannot be tweened due to type mismatch (property is a 'nil', but given type is '%s')",
						key,
						typeof(value)
					),
					2
				)
			end
			if not TWEENABLE[typeof(value)] then
				error(string.format("TweenService:Create property named '%s' cannot be tweened", key), 2)
			end
		end
		local tween = Instance.create("Tween")
		local data = internals[tween]
		data.target = target
		data.goals = goals
		data.tweenInfo = info
		return tween
	end,
	GetValue = function(_, alpha)
		return alpha
	end,
}

M.Tween = {
	Play = function(self)
		local data = internals[self]
		data.playing = true
		data.generation = (data.generation or 0) + 1
		local generation = data.generation
		local info = data.tweenInfo
		local function finish()
			if not data.playing or data.generation ~= generation then
				return
			end
			local target = data.target
			if internals[target].destroyed then
				return
			end
			for key, value in data.goals do
				target[key] = value
			end
			data.playing = false
			Instance.getSignal(self, "Completed"):Fire(rbx().Enum.PlaybackState.Completed)
		end
		if info.RepeatCount < 0 or info.Reverses and info.RepeatCount ~= 0 then
			-- Infinite or ping-pong tweens never complete: apply goals immediately.
			local target = data.target
			for key, value in data.goals do
				target[key] = value
			end
			return
		end
		local duration = (info.Time + info.DelayTime) * (info.RepeatCount + 1)
		scheduler():delay(duration, finish)
	end,
	Pause = function(self)
		internals[self].playing = false
	end,
	Cancel = function(self)
		local data = internals[self]
		if data.playing then
			data.playing = false
			Instance.getSignal(self, "Completed"):Fire(rbx().Enum.PlaybackState.Cancelled)
		end
	end,
}

M.Debris = {
	AddItem = function(_, item, lifetime)
		scheduler():delay(lifetime or 10, function()
			if Instance.isInstance(item) and not internals[item].destroyed then
				Instance.destroy(item)
			end
		end)
	end,
}

-- Data & utility services ---------------------------------------------------------------

local function jsonSafe(value, seen)
	local kind = typeof(value)
	if kind == "table" then
		seen = seen or {}
		if seen[value] then
			error("Can't convert to JSON: cyclic table", 0)
		end
		seen[value] = true
		for key, inner in value do
			if type(key) ~= "string" and type(key) ~= "number" then
				error("Can't convert to JSON: invalid key type " .. typeof(key), 0)
			end
			jsonSafe(inner, seen)
		end
		seen[value] = nil
	elseif kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			error("Can't convert to JSON: number is not finite", 0)
		end
	elseif kind ~= "string" and kind ~= "boolean" and kind ~= "nil" then
		error("Can't convert to JSON: unsupported type " .. kind, 0)
	end
end
Services.jsonSafe = jsonSafe

M.HttpService = {
	JSONEncode = function(_, value)
		jsonSafe(value)
		return serde.encode("json", value)
	end,
	JSONDecode = function(_, text)
		return serde.decode("json", text)
	end,
	GenerateGUID = function(_, wrap)
		local hex = "0123456789ABCDEF"
		local parts = {}
		for _, length in { 8, 4, 4, 4, 12 } do
			local chunk = {}
			for _ = 1, length do
				local index = math.random(1, 16)
				table.insert(chunk, string.sub(hex, index, index))
			end
			table.insert(parts, table.concat(chunk))
		end
		local guid = table.concat(parts, "-")
		return if wrap == false then guid else "{" .. guid .. "}"
	end,
	UrlEncode = function(_, text)
		return (string.gsub(text, "[^%w%-_%.~]", function(c)
			return string.format("%%%02X", string.byte(c))
		end))
	end,
}

M.CollectionService = {
	GetTagged = function(_, tag)
		local result = {}
		local game = runtime().game
		for _, inst in Instance.descendants(game) do
			if internals[inst].tags[tag] then
				table.insert(result, inst)
			end
		end
		return result
	end,
	AddTag = function(_, inst, tag)
		inst:AddTag(tag)
	end,
	RemoveTag = function(_, inst, tag)
		inst:RemoveTag(tag)
	end,
	HasTag = function(_, inst, tag)
		return inst:HasTag(tag)
	end,
	GetTags = function(_, inst)
		return inst:GetTags()
	end,
	GetInstanceAddedSignal = function(self, tag)
		local data = internals[self]
		data.tagSignals = data.tagSignals or {}
		if not data.tagSignals[tag] then
			data.tagSignals[tag] = Signal.new(scheduler(), "TagAdded:" .. tag)
		end
		return data.tagSignals[tag]
	end,
	GetInstanceRemovedSignal = function(self, tag)
		local data = internals[self]
		data.tagRemovedSignals = data.tagRemovedSignals or {}
		if not data.tagRemovedSignals[tag] then
			data.tagRemovedSignals[tag] = Signal.new(scheduler(), "TagRemoved:" .. tag)
		end
		return data.tagRemovedSignals[tag]
	end,
}

D.UserInputService = { TouchEnabled = false, KeyboardEnabled = true, MouseEnabled = true, GamepadEnabled = false }
M.UserInputService = {
	GetMouseLocation = function()
		return rbx().Vector2.new(640, 360)
	end,
	IsKeyDown = function()
		return false
	end,
	IsMouseButtonPressed = function()
		return false
	end,
	GetLastInputType = function()
		return rbx().Enum.UserInputType.MouseButton1
	end,
	GetFocusedTextBox = function()
		return nil
	end,
}

M.ContextActionService = {
	BindAction = function() end,
	BindActionAtPriority = function() end,
	UnbindAction = function() end,
}

M.GuiService = {
	GetGuiInset = function()
		return rbx().Vector2.new(0, 58), rbx().Vector2.new(0, 0)
	end,
	IsTenFootInterface = function()
		return false
	end,
}

M.TextService = {
	GetTextSize = function(_, text, size)
		return rbx().Vector2.new(#text * size * 0.55, size)
	end,
}

local coreGuiDisabled = {}
M.StarterGui = {
	SetCoreGuiEnabled = function(_, coreGuiType, enabled)
		coreGuiDisabled[tostring(coreGuiType)] = enabled == false or nil
	end,
	GetCoreGuiEnabled = function(_, coreGuiType)
		return not coreGuiDisabled[tostring(coreGuiType)]
	end,
	SetCore = function() end,
	GetCore = function()
		return nil
	end,
}

M.Lighting = {
	GetMinutesAfterMidnight = function(self)
		return self.ClockTime * 60
	end,
	SetMinutesAfterMidnight = function(self, minutes)
		self.ClockTime = minutes / 60
	end,
}

M.MessagingService = {
	PublishAsync = function(_, topic, message)
		runtime():publishMessage(topic, message)
	end,
	SubscribeAsync = function(_, topic, callback)
		return runtime():subscribeMessage(topic, callback)
	end,
}

M.DataModel = {
	GetService = function(self, name)
		return internals[self].runtime:getService(name, true)
	end,
	FindService = function(self, name)
		return internals[self].runtime:getService(name, false)
	end,
	BindToClose = function(_, fn)
		runtime():bindToClose(fn)
	end,
	IsLoaded = function()
		return true
	end,
}
M.ServiceProvider = {
	GetService = M.DataModel.GetService,
	FindService = M.DataModel.FindService,
}

M.ProximityPromptService = {}

-- AnalyticsService: server-only, argument types as documented; every event is recorded in
-- the runtime output under "analytics" so tests can assert on it.
local function analyticsArgs(method, player, checks)
	local context = currentContext()
	if context and context.kind ~= "server" then
		error("AnalyticsService:" .. method .. " can only be called from the server", 3)
	end
	if not (Instance.isInstance(player) and isA(player, "Player")) then
		error("AnalyticsService:" .. method .. ": Argument 1 must be a Player", 3)
	end
	for index, check in checks do
		local value, expected, optional = check[1], check[2], check[3]
		if not (value == nil and optional) and type(value) ~= expected then
			error(string.format("AnalyticsService:%s: Argument %d must be a %s", method, index + 1, expected), 3)
		end
	end
end
M.AnalyticsService = {
	LogOnboardingFunnelStepEvent = function(_, player, step, stepName, customFields)
		analyticsArgs("LogOnboardingFunnelStepEvent", player, {
			{ step, "number" },
			{ stepName, "string", true },
			{ customFields, "table", true },
		})
		if step < 1 or step ~= math.floor(step) then
			error("AnalyticsService:LogOnboardingFunnelStepEvent: step must be a positive integer", 2)
		end
		runtime():log("analytics", "Onboarding", step, stepName)
	end,
	LogEconomyEvent = function(
		_,
		player,
		flowType,
		currencyType,
		amount,
		endingBalance,
		transactionType,
		itemSku,
		customFields
	)
		analyticsArgs("LogEconomyEvent", player, {
			{ flowType, "userdata" },
			{ currencyType, "string" },
			{ amount, "number" },
			{ endingBalance, "number" },
			{ transactionType, "string" },
			{ itemSku, "string", true },
			{ customFields, "table", true },
		})
		if flowType.EnumType ~= rbx().Enum.AnalyticsEconomyFlowType then
			error("AnalyticsService:LogEconomyEvent: Argument 2 must be an AnalyticsEconomyFlowType", 2)
		end
		if amount <= 0 or amount ~= amount then
			error("AnalyticsService:LogEconomyEvent: amount must be positive", 2)
		end
		runtime():log("analytics", "Economy", flowType.Name, currencyType, amount, transactionType, itemSku or "")
	end,
	LogProgressionCompleteEvent = function(_, player, path, level, levelName, customFields)
		analyticsArgs("LogProgressionCompleteEvent", player, {
			{ path, "string" },
			{ level, "number" },
			{ levelName, "string", true },
			{ customFields, "table", true },
		})
		runtime():log("analytics", "Progression", path, level)
	end,
	LogCustomEvent = function(_, player, eventName, value, customFields)
		analyticsArgs("LogCustomEvent", player, {
			{ eventName, "string" },
			{ value, "number", true },
			{ customFields, "table", true },
		})
		runtime():log("analytics", "Custom", eventName, value or "")
	end,
}

return Services
