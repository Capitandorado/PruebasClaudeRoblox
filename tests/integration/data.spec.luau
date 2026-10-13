-- Persistence: saving, rejoining, session locks across servers, failures and shutdown.

local Fixture = require("../lib/Fixture")
local DataStore = require("../mock/DataStore")

local function dataModule(rt)
	return rt:requireIn("server", rt.services.ServerScriptService.Server.Services.Data)
end

-- Reads the stored record from inside the server (DataStore calls yield).
local function peek(rt, userId)
	local data = dataModule(rt)
	return rt:asServer(function()
		return data._peek(userId)
	end)
end

local function errorsText(rt)
	local lines = {}
	for _, err in rt:errors() do
		table.insert(lines, err.trace)
	end
	return table.concat(lines, "\n")
end

return function(t)
	t.test("progress survives leaving and rejoining", function()
		local backend = DataStore.newBackend()
		local rt = Fixture.server({ backend = backend, jobId = "A" })
		local player = Fixture.join(rt, { userId = 401 })
		local session = Fixture.session(rt, player)
		local opened = Fixture.request(rt, player, "OpenBox", "starter_fabricator")
		t.ok(opened.ok, tostring(opened.err))
		local key = opened.data.grants[1].key
		t.ok(Fixture.request(rt, player, "Place", 1, key).ok)
		rt:run(5, 0.25)
		local energy = session.profile.energy
		t.ok(energy > 0, "earned energy")
		rt:removePlayer(player)
		rt:run(2, 0.1)
		local record = peek(rt, 401)
		t.ok(record ~= nil and record.data ~= nil, "record saved")
		t.eq(record.lock, nil, "lock released on leave")
		t.eq(record.data.placed["1"], key)

		t.near(record.data.energy, energy, 1e-6, "energy saved at leave time")
		local again = Fixture.join(rt, { userId = 401 })
		local restored = Fixture.session(rt, again)
		t.eq(restored.profile.placed["1"], key, "placed artifact restored")
		t.ok(
			restored.profile.energy >= energy - 1e-6,
			string.format(
				"energy restored (and producing again): saved %s, now %s, clock %s",
				tostring(energy),
				tostring(restored.profile.energy),
				tostring(rt.scheduler.clock)
			)
		)
		t.eq(restored.profile.stats.boxesOpened, 1)
		t.eq(#rt:errors(), 0, errorsText(rt))
	end)

	t.test("a second server waits for the session lock, then loads the latest save", function()
		local backend = DataStore.newBackend()
		local serverA = Fixture.server({ backend = backend, jobId = "A" })
		local playerA = Fixture.join(serverA, { userId = 402 })
		local sessionA = Fixture.session(serverA, playerA)
		Fixture.request(serverA, playerA, "Admin", "energy", 1)
		sessionA.profile.energy = 777
		local serverB = Fixture.server({ backend = backend, jobId = "B", shareScheduler = true })
		local playerB = serverB:addPlayer({ userId = 402, noClient = true })
		serverB:run(6, 0.25)
		t.eq(Fixture.session(serverB, playerB), nil, "B must not load while A holds the lock")
		t.ok(dataModule(serverB).Stats.lockWaits >= 1, "B waited on the lock")
		-- The player finally leaves A (teleport / disconnect): A saves and releases.
		serverA:removePlayer(playerA)
		serverB:runUntil(function()
			return Fixture.session(serverB, playerB) ~= nil
		end, 30, 0.25)
		local sessionB = Fixture.session(serverB, playerB)
		t.ok(sessionB ~= nil, "B loaded after the lock was released")
		t.eq(sessionB.profile.energy, 777, "B sees A's final save")
		t.eq(#serverB.kicks, 0)
	end)

	t.test("a crashed server's stale lock blocks briefly, then expires", function()
		local backend = DataStore.newBackend()
		local crashed = Fixture.server({ backend = backend, jobId = "crashed" })
		local ghost = Fixture.join(crashed, { userId = 403 })
		Fixture.session(crashed, ghost).profile.energy = 50
		crashed:run(65, 0.5) -- one autosave happens, then the server crashes (never saves again)
		local data = dataModule(crashed)
		crashed:crash()
		t.ok(data.Stats.saves >= 1, "autosave ran")
		local fresh = Fixture.server({ backend = backend, jobId = "fresh", shareScheduler = true })
		local player = fresh:addPlayer({ userId = 403, noClient = true })
		fresh:run(45, 0.5)
		t.eq(#fresh.kicks, 1, "kicked while the lock looks alive")
		t.ok(string.find(fresh.kicks[1].message, "another server") ~= nil)
		fresh:run(120, 1)
		local again = Fixture.join(fresh, { userId = 403 })
		local session = Fixture.session(fresh, again)
		t.ok(session ~= nil, "stale lock taken over")
		t.eq(session.profile.energy, 50, "last autosave restored")
		local _ = player
	end)

	t.test("transient DataStore errors are retried; persistent ones never overwrite data", function()
		local backend = DataStore.newBackend()
		local rt = Fixture.server({ backend = backend, jobId = "A" })
		backend.failNext = 2
		local player = Fixture.join(rt, { userId = 404 })
		rt:runUntil(function()
			return Fixture.session(rt, player) ~= nil
		end, 20, 0.25)
		t.ok(Fixture.session(rt, player) ~= nil, "loaded after retries")
		Fixture.session(rt, player).profile.energy = 1234
		rt:removePlayer(player)
		rt:run(2, 0.1)

		backend.failNext = 1000
		local unlucky = rt:addPlayer({ userId = 404, noClient = true })
		rt:run(60, 0.5)
		t.eq(#rt.kicks, 1, "kicked when data can't load")
		t.eq(Fixture.session(rt, unlucky), nil)
		backend.failNext = 0
		local record = peek(rt, 404)
		t.eq(record.data.energy, 1234, "stored data untouched")
	end)

	t.test("invalid profiles are never written", function()
		local backend = DataStore.newBackend()
		local rt = Fixture.server({ backend = backend, jobId = "A" })
		local player = Fixture.join(rt, { userId = 405 })
		local session = Fixture.session(rt, player)
		session.profile.energy = 500
		rt:run(65, 0.5)
		t.eq(peek(rt, 405).data.energy, 500, "autosaved")
		session.profile.energy = 0 / 0
		rt:removePlayer(player)
		rt:run(2, 0.1)
		t.eq(peek(rt, 405).data.energy, 500, "NaN profile refused, last good save kept")
		t.ok(#rt:outputOf("warn") > 0)
	end)

	t.test("shutdown saves every player and releases locks", function()
		local backend = DataStore.newBackend()
		local rt = Fixture.server({ backend = backend, jobId = "A" })
		local players = {}
		for index = 1, 3 do
			players[index] = Fixture.join(rt, { userId = 410 + index })
			Fixture.session(rt, players[index]).profile.energy = index * 100
		end
		t.ok(rt:shutdown(), "BindToClose finished in time")
		for index = 1, 3 do
			local record = peek(rt, 410 + index)
			t.eq(record.data.energy, index * 100)
			t.eq(record.lock, nil)
		end
	end)

	t.test("shutdown waits for a leaving player's save queued behind an autosave", function()
		-- The race depends on how the polling loops line up, so try several timings.
		for step = 0, 9 do
			local backend = DataStore.newBackend()
			local rt = Fixture.server({ backend = backend, jobId = "A" })
			local player = Fixture.join(rt, { userId = 415 })
			local session = Fixture.session(rt, player)
			session.profile.energy = 777
			backend.latency = 1 + step * 0.03
			local data = dataModule(rt)
			rt:asServer(function()
				task.spawn(data.save, session, false) -- autosave in progress
			end)
			rt:run(0.3, 0.05)
			rt:removePlayer(player) -- final save now waits for the autosave
			t.ok(rt:shutdown(), "BindToClose finished in time")
			backend.latency = 0.05
			local record = peek(rt, 415)
			t.eq(record.data.energy, 777)
			t.eq(record.lock, nil, "final save released the lock (latency " .. 1 + step * 0.03 .. ")")
		end
	end)

	t.test("Studio sessions save to their own stores, never to live data", function()
		local backend = DataStore.newBackend()
		local live = Fixture.server({ backend = backend, jobId = "live" })
		t.eq(dataModule(live).StoreName, "VoidFactory_Players_v1")
		local studio = Fixture.server({ backend = backend, jobId = "", isStudio = true })
		t.eq(dataModule(studio).StoreName, "VoidFactory_Players_v1_Studio")
	end)

	t.test("Studio without API access falls back to memory and still works", function()
		local backend = DataStore.newBackend()
		backend.disabled = true
		local rt = Fixture.server({ backend = backend, jobId = "studio", isStudio = true })
		t.eq(dataModule(rt).mode, "memory")
		local player = Fixture.join(rt, { userId = 406 })
		Fixture.session(rt, player).profile.energy = 42
		rt:removePlayer(player)
		rt:run(1, 0.1)
		local again = Fixture.join(rt, { userId = 406 })
		t.eq(Fixture.session(rt, again).profile.energy, 42, "kept for the Studio session")
		local warned = false
		for _, text in rt:outputOf("warn") do
			if string.find(text, "Studio Access to API Services", 1, true) then
				warned = true
			end
		end
		t.ok(warned, "developer warned about Studio API access")
	end)

	t.test("leaving during a slow load releases the lock", function()
		local backend = DataStore.newBackend()
		backend.latency = 2
		local rt = Fixture.server({ backend = backend, jobId = "A" })
		local player = rt:addPlayer({ userId = 407, noClient = true })
		rt:run(1, 0.1)
		rt:removePlayer(player)
		rt:run(10, 0.25)
		local record = peek(rt, 407)
		t.ok(record == nil or record.lock == nil, "no dangling lock")
	end)
end
