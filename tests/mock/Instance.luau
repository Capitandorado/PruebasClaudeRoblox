-- Instance mock validated against the Roblox API database.
-- Reading or writing a member that does not exist on the class raises the same kind of
-- error the engine would ("X is not a valid member of Part"), property assignments are
-- type-checked, events are real signals and methods are implemented as needed.

local Api = require("./Api")
local Signal = require("./Signal")

local Instance = {}

local internals = setmetatable({}, { __mode = "k" })
local typeTags = Signal.typeTags
Instance.internals = internals

-- Extension points (filled here and by Services.luau): ClassName -> { member -> fn }.
local Methods = {}
local Getters = {}
local Setters = {}
local ClassDefaults = {}
Instance.Methods = Methods
Instance.Getters = Getters
Instance.Setters = Setters
Instance.ClassDefaults = ClassDefaults

local world = {} -- { scheduler, rbx (Lune roblox lib), getRuntime }
function Instance.init(env)
	world = env
end

local function currentRuntime()
	return world.getRuntime and world.getRuntime()
end

local chains = {}
local function chainOf(className)
	local chain = chains[className]
	if chain then
		return chain
	end
	chain = {}
	local current = className
	while current and current ~= "" and current ~= "<<<ROOT>>>" do
		table.insert(chain, current)
		local info = Api.class(current)
		current = info and info.superclass
	end
	chains[className] = chain
	return chain
end

local function findHook(hooks, className, key)
	for _, name in chainOf(className) do
		local classHooks = hooks[name]
		if classHooks then
			local hook = classHooks[key]
			if hook ~= nil then
				return hook
			end
		end
	end
	return nil
end

local function isInstance(value)
	return typeTags[value] == "Instance"
end
Instance.isInstance = isInstance

local function getFullName(inst)
	local data = internals[inst]
	local parts = {}
	local current = inst
	while current do
		local d = internals[current]
		if d.className == "DataModel" then
			break
		end
		table.insert(parts, 1, d.props.Name)
		current = d.parent
	end
	if #parts == 0 then
		return data.props.Name
	end
	return table.concat(parts, ".")
end
Instance.getFullName = getFullName

local function memberError(inst, key, level)
	local data = internals[inst]
	error(
		string.format('%s is not a valid member of %s "%s"', tostring(key), data.className, getFullName(inst)),
		level or 3
	)
end

-- Signals -----------------------------------------------------------------------------

local function getSignal(data, name)
	local signal = data.signals[name]
	if not signal then
		signal = Signal.new(world.scheduler, data.className .. "." .. name)
		data.signals[name] = signal
	end
	return signal
end
Instance.getSignal = function(inst, name)
	return getSignal(internals[inst], name)
end

local function fireIfExists(data, name, ...)
	local signal = data.signals[name]
	if signal then
		signal:Fire(...)
	end
end

local function propertyChanged(inst, data, key)
	fireIfExists(data, "Changed", key)
	local signal = data.propSignals[key]
	if signal then
		signal:Fire()
	end
end

-- Defaults ----------------------------------------------------------------------------

local GenericDefaults = {
	Visible = true,
	Enabled = true,
	Archivable = true,
	CanCollide = true,
	CanTouch = true,
	CanQuery = true,
	CastShadow = true,
	AutoButtonColor = true,
	ResetOnSpawn = true,
	Volume = 0.5,
	PlaybackSpeed = 1,
	Brightness = 1,
	Range = 8,
	TextSize = 14,
	MaxActivationDistance = 10,
	Transparency = 0,
	LineHeight = 1,
	Scale = 1,
	TimeScale = 1,
	Lifetime = nil,
}

local defaultCache = {}

local function datatypeDefault(typeName)
	local rbx = world.rbx
	if typeName == "Vector3" then
		return rbx.Vector3.new(0, 0, 0)
	elseif typeName == "Vector2" then
		return rbx.Vector2.new(0, 0)
	elseif typeName == "CFrame" then
		return rbx.CFrame.new()
	elseif typeName == "Color3" then
		return rbx.Color3.new(0.64, 0.64, 0.65)
	elseif typeName == "UDim2" then
		return rbx.UDim2.new(0, 0, 0, 0)
	elseif typeName == "UDim" then
		return rbx.UDim.new(0, 0)
	elseif typeName == "NumberSequence" then
		return rbx.NumberSequence.new(0)
	elseif typeName == "ColorSequence" then
		return rbx.ColorSequence.new(rbx.Color3.new(1, 1, 1))
	elseif typeName == "NumberRange" then
		return rbx.NumberRange.new(0)
	elseif typeName == "BrickColor" then
		return rbx.BrickColor.new("Medium stone grey")
	elseif typeName == "Rect" then
		return rbx.Rect.new(0, 0, 0, 0)
	elseif typeName == "Font" then
		return rbx.Font.new("rbxasset://fonts/families/SourceSansPro.json")
	elseif typeName == "Content" or typeName == "ContentId" then
		return ""
	end
	return nil
end

local function defaultValue(className, key, prop)
	local cacheKey = className .. "." .. key
	local cached = defaultCache[cacheKey]
	if cached ~= nil then
		return cached
	end
	local value = nil
	for _, name in chainOf(className) do
		local defaults = ClassDefaults[name]
		if defaults and defaults[key] ~= nil then
			value = defaults[key]
			if type(value) == "function" then
				value = value()
			end
			break
		end
	end
	-- Generic defaults are primitives: never use them for typed properties (for example
	-- UIGradient.Transparency is a NumberSequence, not a number).
	if value == nil and prop.category == "Primitive" then
		value = GenericDefaults[key]
	end
	if value == nil then
		if prop.category == "Primitive" then
			if prop.typeName == "bool" then
				value = false
			elseif prop.typeName == "string" then
				value = ""
			else
				value = 0
			end
		elseif prop.category == "DataType" then
			value = datatypeDefault(prop.typeName)
		elseif prop.category == "Enum" then
			local ok, items = pcall(function()
				return world.rbx.Enum[prop.typeName]:GetEnumItems()
			end)
			-- Lune's GetEnumItems order is not stable between runs: take the item with the
			-- lowest value, which is the engine default for almost every enum property.
			if ok and items and items[1] then
				local lowest = items[1]
				for _, item in items do
					if item.Value < lowest.Value then
						lowest = item
					end
				end
				value = lowest
			end
		end
	end
	if value ~= nil then
		defaultCache[cacheKey] = value
	end
	return value
end

-- Type checking -------------------------------------------------------------------------

local function enumFrom(typeName, value, key)
	local rbx = world.rbx
	local enumType = rbx.Enum[typeName]
	if typeof(value) == "EnumItem" then
		if not string.find(tostring(value), "Enum." .. typeName .. ".", 1, true) then
			error(
				string.format("Unable to assign property %s. Enum.%s expected, got %s", key, typeName, tostring(value)),
				4
			)
		end
		return value
	elseif type(value) == "string" then
		local ok, item = pcall(function()
			return enumType[value]
		end)
		if not ok or item == nil then
			error(
				string.format('Unable to assign property %s. Invalid value "%s" for enum %s', key, value, typeName),
				4
			)
		end
		return item
	elseif type(value) == "number" then
		for _, item in enumType:GetEnumItems() do
			if item.Value == value then
				return item
			end
		end
		error(string.format("Unable to assign property %s. Invalid value %d for enum %s", key, value, typeName), 4)
	end
	error(string.format("Unable to assign property %s. EnumItem expected, got %s", key, typeof(value)), 4)
end

local function coerce(className, key, prop, value)
	local category, typeName = prop.category, prop.typeName
	if category == "Primitive" then
		if typeName == "bool" then
			if type(value) ~= "boolean" then
				error(string.format("Unable to assign property %s. bool expected, got %s", key, typeof(value)), 4)
			end
		elseif typeName == "string" then
			if type(value) == "number" then
				return tostring(value)
			elseif type(value) ~= "string" then
				error(string.format("Unable to assign property %s. string expected, got %s", key, typeof(value)), 4)
			end
		else
			if type(value) == "string" and tonumber(value) then
				value = tonumber(value)
			end
			if type(value) ~= "number" then
				error(string.format("Unable to assign property %s. number expected, got %s", key, typeof(value)), 4)
			end
			if value ~= value then
				error(string.format("Unable to assign property %s. NaN is not a valid value", key), 4)
			end
			if typeName == "int" or typeName == "int64" then
				value = if value >= 0 then math.floor(value) else math.ceil(value)
			end
		end
		return value
	elseif category == "DataType" then
		if typeName == "Content" or typeName == "ContentId" then
			if type(value) ~= "string" and typeof(value) ~= "Content" then
				error(string.format("Unable to assign property %s. Content expected, got %s", key, typeof(value)), 4)
			end
			return value
		end
		if typeName == "ProtectedString" or typeName == "BinaryString" or typeName == "SharedString" then
			return value
		end
		if typeName == "Font" and typeof(value) == "Font" then
			return value
		end
		if typeof(value) ~= typeName then
			error(string.format("Unable to assign property %s. %s expected, got %s", key, typeName, typeof(value)), 4)
		end
		return value
	elseif category == "Enum" then
		return enumFrom(typeName, value, key)
	elseif category == "Class" then
		if value ~= nil then
			if not isInstance(value) then
				error(string.format("Unable to assign property %s. Object expected, got %s", key, typeof(value)), 4)
			end
			local valueClass = internals[value].className
			if typeName ~= "" and not Api.isA(valueClass, typeName) then
				error(string.format("Unable to assign property %s. %s expected, got %s", key, typeName, valueClass), 4)
			end
		end
		return value
	end
	return value
end

-- Hierarchy ---------------------------------------------------------------------------

local function isDescendantOf(inst, ancestor)
	local current = internals[inst].parent
	while current do
		if current == ancestor then
			return true
		end
		current = internals[current].parent
	end
	return false
end

local function forEachDescendant(inst, fn)
	for _, child in internals[inst].children do
		fn(child)
		forEachDescendant(child, fn)
	end
end

local function setParent(inst, data, newParent)
	if data.parentLocked then
		error(
			string.format(
				"The Parent property of %s is locked, current parent: NULL, new parent %s",
				data.props.Name,
				if newParent then internals[newParent].props.Name else "NULL"
			),
			3
		)
	end
	if newParent ~= nil and not isInstance(newParent) then
		error("Unable to assign property Parent. Object expected, got " .. typeof(newParent), 3)
	end
	if newParent == inst or (newParent and isDescendantOf(newParent, inst)) then
		error(
			string.format(
				"Attempt to set parent of %s to %s would result in circular reference",
				getFullName(inst),
				getFullName(newParent)
			),
			3
		)
	end
	if data.parent == newParent then
		return
	end
	local old = data.parent
	if old then
		local oldData = internals[old]
		local current = old
		while current do
			local d = internals[current]
			if d.signals.DescendantRemoving then
				d.signals.DescendantRemoving:Fire(inst)
			end
			current = d.parent
		end
		local index = table.find(oldData.children, inst)
		if index then
			table.remove(oldData.children, index)
		end
		data.parent = nil
		fireIfExists(oldData, "ChildRemoved", inst)
	end
	data.parent = newParent
	if newParent then
		local newData = internals[newParent]
		table.insert(newData.children, inst)
		fireIfExists(newData, "ChildAdded", inst)
		local current = newParent
		while current do
			local d = internals[current]
			local signal = d.signals.DescendantAdded
			if signal then
				signal:Fire(inst)
				forEachDescendant(inst, function(descendant)
					signal:Fire(descendant)
				end)
			end
			current = d.parent
		end
	end
	fireIfExists(data, "AncestryChanged", inst, newParent)
	propertyChanged(inst, data, "Parent")
	local rt = currentRuntime()
	if rt and rt.onReparent then
		rt:onReparent(inst, newParent)
	end
end

-- Metatable -----------------------------------------------------------------------------

local meta = {}

meta.__index = function(self, key)
	local data = internals[self]
	if type(key) ~= "string" then
		error("invalid member key " .. tostring(key), 2)
	end
	local className = data.className
	local getter = findHook(Getters, className, key)
	if getter then
		return getter(self, data)
	end
	if key == "Parent" then
		return data.parent
	elseif key == "Name" then
		return data.props.Name
	elseif key == "ClassName" then
		return className
	end
	local info = data.info
	local prop = info.props[key]
	if prop then
		local value = data.props[key]
		if value == nil then
			value = defaultValue(className, key, prop)
		end
		return value
	end
	if info.functions[key] then
		local method = findHook(Methods, className, key)
		if method then
			return method
		end
		return function()
			error(string.format("Mock: %s:%s() is not implemented in the mock runtime", className, key), 2)
		end
	end
	if info.events[key] then
		return getSignal(data, key)
	end
	if info.callbacks[key] then
		error(string.format("%s is a callback member of %s; you can only set the callback value", key, className), 2)
	end
	for _, child in data.children do
		if internals[child].props.Name == key then
			return child
		end
	end
	memberError(self, key, 3)
end

meta.__newindex = function(self, key, value)
	local data = internals[self]
	local className = data.className
	if key == "Parent" then
		setParent(self, data, value)
		return
	end
	local setter = findHook(Setters, className, key)
	if setter then
		setter(self, data, value)
		propertyChanged(self, data, key)
		return
	end
	local info = data.info
	if key == "Name" then
		if type(value) == "number" then
			value = tostring(value)
		end
		if type(value) ~= "string" then
			error("Unable to assign property Name. string expected, got " .. typeof(value), 2)
		end
		data.props.Name = value
		propertyChanged(self, data, key)
		return
	end
	if info.callbacks[key] then
		if value ~= nil and type(value) ~= "function" then
			error(string.format("Unable to assign callback %s. function expected", key), 2)
		end
		data.callbacks[key] = value
		return
	end
	local prop = info.props[key]
	if not prop then
		if info.functions[key] or info.events[key] then
			error(string.format("Unable to assign %s: it is not a property of %s", key, className), 2)
		end
		memberError(self, key, 3)
	end
	if prop.readonly and not data.allowReadonly then
		error(string.format("Unable to assign property %s. Property is read only", key), 2)
	end
	local coerced = coerce(className, key, prop, value)
	if data.props[key] == coerced then
		return
	end
	data.props[key] = coerced
	propertyChanged(self, data, key)
end

meta.__tostring = function(self)
	return internals[self].props.Name
end

-- Construction ------------------------------------------------------------------------

function Instance.create(className, parent)
	local info = Api.class(className)
	if not info then
		error(string.format('Unable to create an Instance of type "%s"', tostring(className)), 3)
	end
	local proxy = setmetatable({}, meta)
	internals[proxy] = {
		className = className,
		info = info,
		props = { Name = className },
		children = {},
		parent = nil,
		attributes = {},
		tags = {},
		signals = {},
		propSignals = {},
		attrSignals = {},
		callbacks = {},
		destroyed = false,
	}
	typeTags[proxy] = "Instance"
	if parent ~= nil then
		proxy.Parent = parent
	end
	return proxy
end

function Instance.new(className, parent)
	local info = Api.class(className)
	if not info then
		error(string.format('Unable to create an Instance of type "%s"', tostring(className)), 2)
	end
	if info.notCreatable or info.isService then
		error(string.format('Unable to create an Instance of type "%s"', className), 2)
	end
	return Instance.create(className, parent)
end

-- Sets a read-only property from inside the mock (UserId, AbsoluteSize, ...).
function Instance.setInternal(inst, key, value)
	local data = internals[inst]
	data.props[key] = value
	propertyChanged(inst, data, key)
end

function Instance.callback(inst, key)
	return internals[inst].callbacks[key]
end

-- Base methods ------------------------------------------------------------------------

local function findFirstChild(inst, name, recursive)
	for _, child in internals[inst].children do
		if internals[child].props.Name == name then
			return child
		end
	end
	if recursive then
		for _, child in internals[inst].children do
			local found = findFirstChild(child, name, true)
			if found then
				return found
			end
		end
	end
	return nil
end

local function descendants(inst, result)
	for _, child in internals[inst].children do
		table.insert(result, child)
		descendants(child, result)
	end
	return result
end

local function destroy(inst)
	local data = internals[inst]
	if data.destroyed then
		return
	end
	fireIfExists(data, "Destroying")
	for _, child in table.clone(data.children) do
		destroy(child)
	end
	if data.parent then
		setParent(inst, data, nil)
	end
	data.destroyed = true
	data.parentLocked = true
	for _, signal in data.signals do
		signal:DisconnectAll()
	end
	for _, signal in data.propSignals do
		signal:DisconnectAll()
	end
	local rt = currentRuntime()
	if rt and rt.onDestroy then
		rt:onDestroy(inst)
	end
end

local function clone(inst)
	local data = internals[inst]
	if inst.Archivable == false then
		return nil
	end
	local copy = Instance.create(data.className)
	local copyData = internals[copy]
	for key, value in data.props do
		copyData.props[key] = value
	end
	for key, value in data.attributes do
		copyData.attributes[key] = value
	end
	for tag in data.tags do
		copyData.tags[tag] = true
	end
	copyData.source = data.source
	copyData.sourcePath = data.sourcePath
	local childMap = {}
	for _, child in data.children do
		local childCopy = clone(child)
		if childCopy then
			childMap[child] = childCopy
			childCopy.Parent = copy
		end
	end
	-- Re-point Class-typed properties (e.g. Model.PrimaryPart) at the cloned children.
	for key, value in copyData.props do
		if isInstance(value) then
			local remapped = nil
			for original, cloned in childMap do
				if original == value then
					remapped = cloned
				end
			end
			if not remapped then
				for _, originalDesc in descendants(inst, {}) do
					if originalDesc == value then
						local path = {}
						local current = value
						while current ~= inst do
							table.insert(path, 1, internals[current].props.Name)
							current = internals[current].parent
						end
						local target = copy
						for _, name in path do
							target = target and findFirstChild(target, name)
						end
						remapped = target
					end
				end
			end
			if remapped then
				copyData.props[key] = remapped
			end
		end
	end
	local rt = currentRuntime()
	if rt and rt.onClone then
		rt:onClone(inst, copy)
	end
	return copy
end

local VALID_ATTRIBUTE_TYPES = {
	string = true,
	boolean = true,
	number = true,
	UDim = true,
	UDim2 = true,
	BrickColor = true,
	Color3 = true,
	Vector2 = true,
	Vector3 = true,
	CFrame = true,
	NumberSequence = true,
	ColorSequence = true,
	NumberRange = true,
	Rect = true,
	Font = true,
	EnumItem = true,
}

Methods.Instance = {
	FindFirstChild = function(self, name, recursive)
		return findFirstChild(self, name, recursive)
	end,
	FindFirstChildOfClass = function(self, className)
		for _, child in internals[self].children do
			if internals[child].className == className then
				return child
			end
		end
		return nil
	end,
	FindFirstChildWhichIsA = function(self, className, recursive)
		for _, child in internals[self].children do
			if Api.isA(internals[child].className, className) then
				return child
			end
		end
		if recursive then
			for _, desc in descendants(self, {}) do
				if Api.isA(internals[desc].className, className) then
					return desc
				end
			end
		end
		return nil
	end,
	FindFirstAncestor = function(self, name)
		local current = internals[self].parent
		while current do
			if internals[current].props.Name == name then
				return current
			end
			current = internals[current].parent
		end
		return nil
	end,
	FindFirstAncestorOfClass = function(self, className)
		local current = internals[self].parent
		while current do
			if internals[current].className == className then
				return current
			end
			current = internals[current].parent
		end
		return nil
	end,
	FindFirstAncestorWhichIsA = function(self, className)
		local current = internals[self].parent
		while current do
			if Api.isA(internals[current].className, className) then
				return current
			end
			current = internals[current].parent
		end
		return nil
	end,
	FindFirstDescendant = function(self, name)
		return findFirstChild(self, name, true)
	end,
	WaitForChild = function(self, name, timeout)
		local existing = findFirstChild(self, name)
		if existing then
			return existing
		end
		local scheduler = world.scheduler
		local thread = coroutine.running()
		local done = false
		local connection
		local function finish(value)
			if done then
				return
			end
			done = true
			if connection then
				connection:Disconnect()
			end
			scheduler:resume(thread, value)
		end
		connection = getSignal(internals[self], "ChildAdded"):Connect(function(child)
			if internals[child].props.Name == name then
				finish(child)
			end
		end)
		if timeout then
			scheduler:delay(timeout, function()
				finish(nil)
			end)
		else
			scheduler:delay(5, function()
				local rt = currentRuntime()
				if not done and rt then
					rt:log(
						"warn",
						string.format("Infinite yield possible on '%s:WaitForChild(\"%s\")'", getFullName(self), name)
					)
				end
			end)
		end
		return coroutine.yield()
	end,
	GetChildren = function(self)
		return table.clone(internals[self].children)
	end,
	GetDescendants = function(self)
		return descendants(self, {})
	end,
	IsA = function(self, className)
		return Api.isA(internals[self].className, className)
	end,
	IsDescendantOf = function(self, ancestor)
		return isDescendantOf(self, ancestor)
	end,
	IsAncestorOf = function(self, descendant)
		return isDescendantOf(descendant, self)
	end,
	Destroy = function(self)
		destroy(self)
	end,
	ClearAllChildren = function(self)
		for _, child in table.clone(internals[self].children) do
			destroy(child)
		end
	end,
	Clone = function(self)
		return clone(self)
	end,
	GetFullName = function(self)
		return getFullName(self)
	end,
	GetAttribute = function(self, name)
		return internals[self].attributes[name]
	end,
	SetAttribute = function(self, name, value)
		if type(name) ~= "string" or #name == 0 or #name > 100 or string.find(name, "[^%w_]") then
			error("Attribute name is invalid: " .. tostring(name), 2)
		end
		if value ~= nil and not VALID_ATTRIBUTE_TYPES[typeof(value)] then
			error(typeof(value) .. " is not a supported attribute type", 2)
		end
		if type(value) == "number" and value ~= value then
			error("NaN is not a supported attribute value", 2)
		end
		local data = internals[self]
		if data.attributes[name] == value then
			return
		end
		data.attributes[name] = value
		local signal = data.attrSignals[name]
		if signal then
			signal:Fire()
		end
		fireIfExists(data, "AttributeChanged", name)
	end,
	GetAttributes = function(self)
		return table.clone(internals[self].attributes)
	end,
	GetAttributeChangedSignal = function(self, name)
		local data = internals[self]
		local signal = data.attrSignals[name]
		if not signal then
			signal = Signal.new(world.scheduler, "AttributeChanged:" .. name)
			data.attrSignals[name] = signal
		end
		return signal
	end,
	GetPropertyChangedSignal = function(self, key)
		local data = internals[self]
		if not data.info.props[key] and key ~= "Parent" and key ~= "Name" then
			error(string.format("%s is not a valid property name.", tostring(key)), 2)
		end
		local signal = data.propSignals[key]
		if not signal then
			signal = Signal.new(world.scheduler, "PropertyChanged:" .. key)
			data.propSignals[key] = signal
		end
		return signal
	end,
	AddTag = function(self, tag)
		internals[self].tags[tag] = true
		local rt = currentRuntime()
		if rt and rt.onTagAdded then
			rt:onTagAdded(self, tag)
		end
	end,
	RemoveTag = function(self, tag)
		internals[self].tags[tag] = nil
	end,
	HasTag = function(self, tag)
		return internals[self].tags[tag] == true
	end,
	GetTags = function(self)
		local result = {}
		for tag in internals[self].tags do
			table.insert(result, tag)
		end
		return result
	end,
	GetDebugId = function(self)
		return tostring(self)
	end,
}

Instance.descendants = function(inst)
	return descendants(inst, {})
end
Instance.findFirstChild = findFirstChild
Instance.destroy = destroy

return Instance
