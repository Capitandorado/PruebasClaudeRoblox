-- DataStoreService mock with a backend that several simulated servers can share
-- (to test session locking) and failure injection (to test retries and safety).
-- Values are JSON round-tripped exactly like the real service would serialise them.

local serde = require("@lune/serde")
local Instance = require("./Instance")

local DataStore = {}

local internals = Instance.internals
local M = Instance.Methods

local world = {}
function DataStore.init(env)
	world = env
end

local MAX_SIZE = 4194304

function DataStore.newBackend()
	return {
		stores = {},
		ordered = {},
		-- failure injection
		failNext = 0, -- fail the next N requests
		failFilter = nil, -- function(op, storeName, key) -> error string or nil
		disabled = false, -- emulate Studio without API access
		latency = 0.05,
		requests = {},
	}
end

local function checkSerializable(value, path, seen)
	local kind = typeof(value)
	if kind == "table" then
		seen = seen or {}
		if seen[value] then
			error("Cannot store cyclic tables in DataStore (" .. path .. ")", 0)
		end
		seen[value] = true
		local hasArray = value[1] ~= nil
		local hasDict = false
		for key, inner in value do
			if type(key) == "string" then
				hasDict = true
			elseif type(key) ~= "number" then
				error("Cannot store table with " .. typeof(key) .. " keys in DataStore (" .. path .. ")", 0)
			elseif not hasArray then
				error("Cannot store dictionary with number keys in DataStore (" .. path .. ")", 0)
			end
			checkSerializable(inner, path .. "." .. tostring(key), seen)
		end
		if hasArray and hasDict then
			error("Cannot store mixed tables in DataStore (" .. path .. ")", 0)
		end
		seen[value] = nil
	elseif kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			error("Cannot store non-finite number in DataStore (" .. path .. ")", 0)
		end
	elseif kind ~= "string" and kind ~= "boolean" and kind ~= "nil" then
		error("Cannot store " .. kind .. " in DataStore (" .. path .. ")", 0)
	end
end

local function encode(value)
	if value == nil then
		return nil
	end
	checkSerializable(value, "value")
	local text = serde.encode("json", value)
	if #text > MAX_SIZE then
		error("104: Cannot store value: exceeds 4MB limit", 0)
	end
	return text
end

local function decode(text)
	if text == nil then
		return nil
	end
	return serde.decode("json", text)
end

local function request(store, op, key)
	local backend = store.backend
	if not coroutine.isyieldable() then
		error("DataStore requests must be made from a yieldable thread", 3)
	end
	if type(key) ~= "string" or #key == 0 or #key > 50 then
		error("101: Key name can't be empty or longer than 50 characters", 3)
	end
	table.insert(backend.requests, { op = op, store = store.name, key = key, time = world.scheduler.clock })
	world.scheduler:wait(backend.latency)
	if backend.disabled then
		error("502: API Services rejected request with error. Error code: 0 Reason: Studio access to APIs is not allowed.", 3)
	end
	if backend.failNext > 0 then
		backend.failNext -= 1
		error("503: Mock DataStore failure (" .. op .. ")", 3)
	end
	if backend.failFilter then
		local message = backend.failFilter(op, store.name, key)
		if message then
			error(message, 3)
		end
	end
end

local function storeTable(backend, kind, name, scope)
	local bucketName = name .. "/" .. (scope or "global")
	local bucket = backend[kind][bucketName]
	if not bucket then
		bucket = { values = {}, versions = {} }
		backend[kind][bucketName] = bucket
	end
	return bucket
end

local function keyInfo(bucket, key)
	return {
		Version = tostring(bucket.versions[key] or 0),
		CreatedTime = 0,
		UpdatedTime = 0,
		GetUserIds = function()
			return {}
		end,
		GetMetadata = function()
			return {}
		end,
	}
end

local function newStore(className, kind, name, scope)
	local runtime = world.getRuntime()
	local inst = Instance.create(className)
	inst.Name = name
	internals[inst].store = {
		backend = runtime.dataStoreBackend,
		bucket = storeTable(runtime.dataStoreBackend, kind, name, scope),
		name = name,
		ordered = kind == "ordered",
	}
	return inst
end

local function bump(bucket, key)
	bucket.versions[key] = (bucket.versions[key] or 0) + 1
end

M.GlobalDataStore = {
	GetAsync = function(self, key)
		local store = internals[self].store
		request(store, "GetAsync", key)
		return decode(store.bucket.values[key]), keyInfo(store.bucket, key)
	end,
	SetAsync = function(self, key, value)
		local store = internals[self].store
		request(store, "SetAsync", key)
		if store.ordered and (type(value) ~= "number" or value ~= math.floor(value)) then
			error("OrderedDataStore values must be integers", 2)
		end
		store.bucket.values[key] = encode(value)
		bump(store.bucket, key)
		return tostring(store.bucket.versions[key])
	end,
	UpdateAsync = function(self, key, transform)
		local store = internals[self].store
		request(store, "UpdateAsync", key)
		local current = decode(store.bucket.values[key])
		local result = transform(current, keyInfo(store.bucket, key))
		if result == nil then
			return nil
		end
		if store.ordered and (type(result) ~= "number" or result ~= math.floor(result)) then
			error("OrderedDataStore values must be integers", 2)
		end
		store.bucket.values[key] = encode(result)
		bump(store.bucket, key)
		return decode(store.bucket.values[key]), keyInfo(store.bucket, key)
	end,
	RemoveAsync = function(self, key)
		local store = internals[self].store
		request(store, "RemoveAsync", key)
		local old = decode(store.bucket.values[key])
		store.bucket.values[key] = nil
		return old
	end,
	IncrementAsync = function(self, key, delta)
		local store = internals[self].store
		request(store, "IncrementAsync", key)
		local current = decode(store.bucket.values[key]) or 0
		local value = current + (delta or 1)
		store.bucket.values[key] = encode(value)
		bump(store.bucket, key)
		return value
	end,
}

M.OrderedDataStore = {
	GetSortedAsync = function(self, ascending, pageSize, minValue, maxValue)
		local store = internals[self].store
		request(store, "GetSortedAsync", "sorted")
		local entries = {}
		for key, text in store.bucket.values do
			local value = decode(text)
			if (minValue == nil or value >= minValue) and (maxValue == nil or value <= maxValue) then
				table.insert(entries, { key = key, value = value })
			end
		end
		table.sort(entries, function(a, b)
			if a.value == b.value then
				return a.key < b.key
			end
			if ascending then
				return a.value < b.value
			end
			return a.value > b.value
		end)
		local pages = Instance.create("DataStorePages")
		internals[pages].pageData = { entries = entries, pageSize = math.clamp(pageSize or 50, 1, 100), index = 1 }
		return pages
	end,
}

M.Pages = {
	GetCurrentPage = function(self)
		local pageData = internals[self].pageData
		local page = {}
		for i = pageData.index, math.min(#pageData.entries, pageData.index + pageData.pageSize - 1) do
			table.insert(page, pageData.entries[i])
		end
		return page
	end,
	AdvanceToNextPageAsync = function(self)
		local pageData = internals[self].pageData
		pageData.index += pageData.pageSize
		world.scheduler:wait(0.05)
	end,
}
Instance.Getters.Pages = {
	IsFinished = function(self)
		local pageData = internals[self].pageData
		return pageData.index + pageData.pageSize > #pageData.entries
	end,
}

M.DataStoreService = {
	GetDataStore = function(self, name, scope)
		if type(name) ~= "string" or #name == 0 or #name > 50 then
			error("DataStore name can't be empty or longer than 50 characters", 2)
		end
		return newStore("DataStore", "stores", name, scope)
	end,
	GetGlobalDataStore = function(self)
		return newStore("DataStore", "stores", "__global", nil)
	end,
	GetOrderedDataStore = function(self, name, scope)
		return newStore("OrderedDataStore", "ordered", name, scope)
	end,
	GetRequestBudgetForRequestType = function()
		return 100
	end,
}

return DataStore
