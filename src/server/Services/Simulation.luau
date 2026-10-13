-- One Heartbeat connection drives every player's factory: production, the Box Printer and
-- Void Surges are integrated once per Economy.TickInterval for all sessions.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Simulation = require(Shared.Logic.Simulation)
local Format = require(Shared.Util.Format)

local Services = script.Parent
local Net = require(Services.Net)
local Sessions = require(Services.Sessions)
local Plots = require(Services.Plots)
local Game = require(Services.Game)

local SimulationService = {}

local TICK_SECTIONS = { "energy", "lifetimeEnergy", "runEnergy", "stats", "bestEps", "runBestEps", "playTime" }
local PRINT_SECTIONS = {
	"energy",
	"lifetimeEnergy",
	"runEnergy",
	"stats",
	"inventory",
	"collection",
	"bestRarity",
	"bestEps",
	"runBestEps",
	"playTime",
}

local function tickSession(session: Sessions.Session, dt: number, now: number)
	local events = Simulation.tick(session.profile, session.runtime, dt, now, session.rng)
	local production = Sessions.production(session)
	if #events.printed > 0 then
		Sessions.replicate(session, PRINT_SECTIONS)
		for _, result in events.printed do
			Net.notify(session.player, "Printed", result)
			Game.announceGrants(session, result)
		end
	elseif events.surgeStarted then
		Sessions.replicate(session, { "energy", "lifetimeEnergy", "runEnergy", "stats", "machines" })
	else
		Sessions.replicate(session, TICK_SECTIONS)
	end
	if events.printerBlocked then
		Net.notify(session.player, "Toast", { text = "Box Printer paused: inventory full", kind = "warning" })
	end
	if events.surgeStarted then
		Plots.setSurge(session, true)
		Net.notify(session.player, "Surge", { active = true, endsAt = session.runtime.surgeEndsAt })
	elseif events.surgeEnded then
		Plots.setSurge(session, false)
		Net.notify(session.player, "Surge", { active = false })
	end
	Plots.updateSign(session, production.total)
	local leaderstats = session.player:FindFirstChild("leaderstats")
	if leaderstats then
		local eps = leaderstats:FindFirstChild("Energy/s")
		if eps and eps:IsA("StringValue") then
			local text = Format.number(production.total)
			if eps.Value ~= text then
				eps.Value = text
			end
		end
		local rebirths = leaderstats:FindFirstChild("Rebirths")
		if rebirths and rebirths:IsA("IntValue") then
			rebirths.Value = session.profile.rebirths
		end
	end
end

-- Advances every session by `dt` seconds (also used by the admin time-warp).
function SimulationService.step(dt: number)
	local now = Sessions.now()
	for _, session in Sessions.all() do
		local ok, err = pcall(tickSession, session, dt, now)
		if not ok then
			warn("[Simulation] tick failed for " .. session.player.Name .. ": " .. tostring(err))
		end
	end
end

function SimulationService.start()
	Sessions.Started:Connect(function(session)
		local leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		local eps = Instance.new("StringValue")
		eps.Name = "Energy/s"
		eps.Value = "0"
		eps.Parent = leaderstats
		local rebirths = Instance.new("IntValue")
		rebirths.Name = "Rebirths"
		rebirths.Value = session.profile.rebirths
		rebirths.Parent = leaderstats
		leaderstats.Parent = session.player
	end)
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < Economy.TickInterval then
			return
		end
		local step = math.min(accumulator, Economy.TickInterval * 5)
		accumulator = 0
		SimulationService.step(step)
	end)
end

return SimulationService
