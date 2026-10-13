-- Persistent player data (DataStoreService).
--
-- Safety rules
--   * Every read/write goes through UpdateAsync on a single record per player:
--       { schema, data = profile, lock = { jobId, time }, savedAt, saveCount }
--   * Session lock: a record locked by another live server is never loaded or overwritten.
--     A lock older than LockTimeout (crashed server) may be taken over. Autosaves refresh it.
--   * If data cannot be loaded, the player is kicked with a clear message instead of playing
--     on an empty profile that could later overwrite their real save.
--   * Profiles are validated (Shared/Logic/Profile.validate) before every save; an invalid
--     profile is never written.
--   * Saves for one player are serialised (never two at once) and retried with backoff.
--   * Studio without API access falls back to an in-memory store (warned in the output).

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Profile = require(Shared.Logic.Profile)

local Data = {}

Data.StoreName = "VoidFactory_Players_v1"
Data.Schema = 1
Data.LockTimeout = 150
Data.AutosaveInterval = 60
Data.LoadAttempts = 5
Data.LockWaitAttempts = 8
Data.LockWaitDelay = 5
Data.SaveAttempts = 3

Data.mode = "datastore" -- or "memory"
Data.Stats = { loads = 0, saves = 0, saveFailures = 0, lockWaits = 0, kicks = 0 }

local store: GlobalDataStore? = nil
local memory: { [string]: any } = {}
local saving: { [number]: boolean } = {}
local sessionProvider: (() -> { any })? = nil
local shuttingDown = false

local function key(userId: number): string
	return "u_" .. tostring(userId)
end

local function now(): number
	return os.time()
end

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

-- Runs UpdateAsync (or its in-memory equivalent) with the given transform.
local function update(recordKey: string, transform: (any) -> any): (boolean, any)
	if Data.mode == "memory" then
		local result = transform(deepCopy(memory[recordKey]))
		if result ~= nil then
			memory[recordKey] = deepCopy(result)
		end
		return true, result
	end
	if not store then
		return false, "DataStore unavailable"
	end
	return pcall(function()
		return (store :: GlobalDataStore):UpdateAsync(recordKey, transform)
	end)
end

local function waitWhileSaving(userId: number)
	local waited = 0
	while saving[userId] and waited < 30 do
		waited += task.wait(0.25)
	end
end

-- Loads (and locks) a player's profile. Returns nil if the player was kicked or left.
function Data.load(player: Player, sessionNow: number): Profile.Profile?
	local userId = player.UserId
	-- A previous session of this player on this server may still be writing its final save.
	waitWhileSaving(userId)
	local recordKey = key(userId)
	local jobId = game.JobId
	local lockWaits = 0
	local errors = 0
	while true do
		if not player.Parent then
			return nil
		end
		local lockedBy = nil
		local loaded = nil
		local ok, err = update(recordKey, function(record)
			lockedBy = nil
			loaded = nil
			if record ~= nil and type(record) ~= "table" then
				-- Unknown format: keep the raw value aside instead of discarding it.
				record = { schema = Data.Schema, corruptBackup = record, saveCount = 0 }
			end
			record = record or { schema = Data.Schema, saveCount = 0 }
			local lock = record.lock
			if
				type(lock) == "table"
				and lock.jobId ~= jobId
				and type(lock.time) == "number"
				and now() - lock.time < Data.LockTimeout
			then
				lockedBy = lock
				return nil -- leave the record untouched
			end
			record.lock = { jobId = jobId, time = now() }
			loaded = record
			return record
		end)
		if ok and loaded then
			Data.Stats.loads += 1
			local profile = Profile.reconcile((loaded :: any).data, sessionNow)
			if not player.Parent then
				-- Left while loading: release the lock we just took.
				Data.release(userId)
				return nil
			end
			return profile
		elseif ok and lockedBy then
			lockWaits += 1
			Data.Stats.lockWaits += 1
			if lockWaits >= Data.LockWaitAttempts then
				Data.Stats.kicks += 1
				player:Kick("Your data is still being saved on another server. Please rejoin in a moment.")
				return nil
			end
			task.wait(Data.LockWaitDelay)
		else
			errors += 1
			warn(string.format("[Data] load failed for %d (attempt %d): %s", userId, errors, tostring(err)))
			if errors >= Data.LoadAttempts then
				Data.Stats.kicks += 1
				player:Kick("We couldn't load your data (Roblox data servers are busy). Please rejoin.")
				return nil
			end
			task.wait(math.min(2 ^ errors, 16))
		end
	end
end

-- Writes `profile` for `userId`. `final` releases the session lock.
local function write(userId: number, profile: any, final: boolean): boolean
	local valid, reason = Profile.validate(profile)
	if not valid then
		warn(string.format("[Data] refusing to save invalid profile for %d: %s", userId, tostring(reason)))
		Data.Stats.saveFailures += 1
		return false
	end
	local snapshot = deepCopy(profile)
	local recordKey = key(userId)
	local jobId = game.JobId
	for attempt = 1, Data.SaveAttempts do
		local stolen = false
		local ok, err = update(recordKey, function(record)
			stolen = false
			if type(record) ~= "table" then
				record = { schema = Data.Schema, saveCount = 0 }
			end
			local lock = record.lock
			if
				type(lock) == "table"
				and lock.jobId ~= jobId
				and type(lock.time) == "number"
				and now() - lock.time < Data.LockTimeout
			then
				stolen = true
				return nil -- another server owns this player now: never overwrite its data
			end
			record.schema = Data.Schema
			record.data = snapshot
			record.savedAt = now()
			record.saveCount = (tonumber(record.saveCount) or 0) + 1
			record.lock = if final then nil else { jobId = jobId, time = now() }
			return record
		end)
		if ok then
			if stolen then
				warn(string.format("[Data] save for %d skipped: session owned by another server", userId))
				return false
			end
			Data.Stats.saves += 1
			return true
		end
		warn(string.format("[Data] save failed for %d (attempt %d): %s", userId, attempt, tostring(err)))
		if attempt < Data.SaveAttempts then
			task.wait(2 ^ attempt)
		end
	end
	Data.Stats.saveFailures += 1
	return false
end

-- Saves a session. Concurrent calls for the same player are serialised.
function Data.save(session: any, final: boolean?): boolean
	local userId = session.userId
	if session.finalSaved then
		return true
	end
	while saving[userId] do
		task.wait(0.1)
	end
	if session.finalSaved then
		return true
	end
	saving[userId] = true
	local ok, result = pcall(write, userId, session.profile, final == true)
	saving[userId] = nil
	local success = ok and result == true
	if not ok then
		warn("[Data] save crashed: " .. tostring(result))
	end
	session.lastSave = os.clock()
	if final then
		session.finalSaved = true
	end
	return success
end

-- Releases a lock without writing profile data (player left during loading).
function Data.release(userId: number)
	task.spawn(function()
		update(key(userId), function(record)
			if type(record) == "table" and type(record.lock) == "table" and record.lock.jobId == game.JobId then
				record.lock = nil
				return record
			end
			return nil
		end)
	end)
end

function Data.setSessionProvider(provider: () -> { any })
	sessionProvider = provider
end

local function budgetOk(): boolean
	if Data.mode == "memory" then
		return true
	end
	local ok, budget = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync)
	end)
	return not ok or budget >= 5
end

local function autosaveLoop()
	while not shuttingDown do
		task.wait(5)
		if shuttingDown or not sessionProvider then
			continue
		end
		for _, session in sessionProvider() do
			if shuttingDown then
				break
			end
			local last = session.lastSave or session.loadedClock or 0
			if os.clock() - last >= Data.AutosaveInterval and not saving[session.userId] and budgetOk() then
				task.spawn(Data.save, session, false)
			end
		end
	end
end

local function onClose()
	shuttingDown = true
	if not sessionProvider then
		return
	end
	local pending = 0
	for _, session in sessionProvider() do
		pending += 1
		task.spawn(function()
			Data.save(session, true)
			pending -= 1
		end)
	end
	-- Also wait for saves started by PlayerRemoving while the server was closing.
	local waited = 0
	while (pending > 0 or next(saving) ~= nil) and waited < 25 do
		waited += task.wait(0.25)
	end
end

function Data.init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Data.StoreName)
	end)
	if ok then
		store = result
	end
	if RunService:IsStudio() then
		-- Studio without "Enable Studio Access to API Services" errors on every request.
		local probeOk = ok and pcall(function()
			return (store :: GlobalDataStore):GetAsync("__probe")
		end)
		if not probeOk then
			Data.mode = "memory"
			warn(
				"[Data] DataStores are unavailable in this Studio session: progress is kept in memory only. "
					.. "Enable Game Settings > Security > 'Enable Studio Access to API Services' to test real saving."
			)
		end
	elseif not ok then
		-- Never fall back to memory on a live server: players would lose progress silently.
		-- Loads will fail and players get a clear "please rejoin" message instead.
		warn("[Data] DataStoreService unavailable: " .. tostring(result))
	end
end

function Data.start()
	task.spawn(autosaveLoop)
	game:BindToClose(onClose)
end

-- Test/debug helper: the raw stored record (memory mode or DataStore).
function Data._peek(userId: number): any
	if Data.mode == "memory" then
		return deepCopy(memory[key(userId)])
	end
	local okGet, value = pcall(function()
		return (store :: GlobalDataStore):GetAsync(key(userId))
	end)
	return if okGet then value else nil
end

return Data
