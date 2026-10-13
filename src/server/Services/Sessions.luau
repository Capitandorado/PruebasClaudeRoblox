-- Player sessions: profile + per-player simulation runtime + RNG + plot.
-- Owns the player lifecycle and replicates the profile mirror to the owning client.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Profile = require(Shared.Logic.Profile)
local Simulation = require(Shared.Logic.Simulation)
local Progression = require(Shared.Logic.Actions.Progression)
local Signal = require(Shared.Util.Signal)

local Services = script.Parent
local Net = require(Services.Net)
local Plots = require(Services.Plots)

export type Session = {
	player: Player,
	userId: number,
	profile: Profile.Profile,
	runtime: Simulation.Runtime,
	rng: any, -- Random (typed loosely: Luau classes are not structural)
	plot: number,
	ready: boolean,
	joinedAt: number,
}

local Sessions = {}

Sessions.Started = Signal.new()
Sessions.Ending = Signal.new()

local sessions: { [Player]: Session } = {}

-- Profile loading is pluggable so persistence (Services/Data) can take over.
Sessions.loader = nil :: ((player: Player, now: number) -> Profile.Profile?)?
Sessions.saver = nil :: ((session: Session, final: boolean) -> ())?

function Sessions.now(): number
	return workspace:GetServerTimeNow()
end

function Sessions.get(player: Player): Session?
	local session = sessions[player]
	if session and session.ready then
		return session
	end
	return nil
end

function Sessions.all(): { Session }
	local result = {}
	for _, session in sessions do
		if session.ready then
			table.insert(result, session)
		end
	end
	return result
end

function Sessions.byUserId(userId: number): Session?
	for _, session in sessions do
		if session.ready and session.userId == userId then
			return session
		end
	end
	return nil
end

function Sessions.production(session: Session)
	return Simulation.getProduction(session.profile, session.runtime, Sessions.now())
end

function Sessions.markDirty(session: Session)
	session.runtime.dirty = true
end

local ALL_SECTIONS = {
	"energy",
	"lifetimeEnergy",
	"runEnergy",
	"rebirths",
	"shards",
	"inventory",
	"placed",
	"machines",
	"upgrades",
	"perks",
	"expansion",
	"collection",
	"stats",
	"quests",
	"settings",
	"bestRarity",
	"bestEps",
	"playTime",
}
Sessions.AllSections = ALL_SECTIONS

local function runtimeInfo(session: Session)
	local runtime = session.runtime
	return {
		surgeEndsAt = runtime.surgeEndsAt,
		surgeNextAt = runtime.surgeNextAt or 0,
		printerAt = runtime.printerAt or 0,
	}
end

-- Sends the listed profile sections (all of them when `sections` is nil).
function Sessions.replicate(session: Session, sections: { string }?)
	local patch = {}
	local list: { string } = sections or ALL_SECTIONS
	for _, key in list do
		patch[key] = (session.profile :: any)[key]
	end
	patch.runtime = runtimeInfo(session)
	Net.state(session.player, "Patch", patch)
end

function Sessions.replicateFull(session: Session)
	local profile = table.clone(session.profile) :: any
	profile.orphaned = nil
	Net.state(session.player, "Full", {
		profile = profile,
		runtime = runtimeInfo(session),
		plot = session.plot,
		userId = session.userId,
	})
end

local function onPlayerAdded(player: Player)
	if sessions[player] then
		return
	end
	local now = Sessions.now()
	local profile
	if Sessions.loader then
		profile = Sessions.loader(player, now)
		if not profile then
			return -- the loader kicked the player (data unavailable)
		end
	else
		profile = Profile.new(now)
	end
	if not player.Parent then
		return
	end
	local session: Session = {
		player = player,
		userId = player.UserId,
		profile = profile,
		runtime = Simulation.newRuntime(),
		rng = Random.new(),
		plot = 0,
		ready = false,
		joinedAt = now,
	}
	sessions[player] = session
	Progression.ensureQuests(profile, session.rng)
	local plot = Plots.assign(session)
	if not plot then
		sessions[player] = nil
		player:Kick("This server is full. Please join another server.")
		return
	end
	session.plot = plot
	session.ready = true
	Sessions.replicateFull(session)
	Sessions.Started:Fire(session)
end

local function onPlayerRemoving(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	session.ready = false
	Sessions.Ending:Fire(session)
	if Sessions.saver then
		Sessions.saver(session, true)
	end
	Plots.release(session)
	sessions[player] = nil
end

function Sessions.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

-- Replaces a session's profile (admin reset) and re-syncs everything.
function Sessions.replaceProfile(session: Session, profile: Profile.Profile)
	session.profile = profile
	session.runtime = Simulation.newRuntime()
	Progression.ensureQuests(profile, session.rng)
	Plots.refresh(session)
	Sessions.replicateFull(session)
end

-- Test hook: every session, including ones still loading.
function Sessions._raw()
	return sessions
end

return Sessions
