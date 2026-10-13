-- Debug tools to test progression quickly. Only available in Studio, to the experience
-- owner and to Config/Admin.UserIds. Every command is validated server-side.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AdminConfig = require(Shared.Config.Admin)
local Artifacts = require(Shared.Config.Artifacts)
local Mutations = require(Shared.Config.Mutations)
local Economy = require(Shared.Config.Economy)
local Profile = require(Shared.Logic.Profile)
local Items = require(Shared.Logic.Items)
local Inventory = require(Shared.Logic.Inventory)
local Simulation = require(Shared.Logic.Simulation)
local State = require(Shared.Logic.State)

local Services = script.Parent
local Net = require(Services.Net)
local Sessions = require(Services.Sessions)
local Plots = require(Services.Plots)

local Admin = {}

function Admin.isAdmin(player: Player): boolean
	if AdminConfig.AllowInStudio and RunService:IsStudio() then
		return true
	end
	if AdminConfig.AllowCreator and game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
		return true
	end
	return table.find(AdminConfig.UserIds, player.UserId) ~= nil
end

local function isPositive(value: any, max: number): boolean
	return type(value) == "number" and value == value and value > 0 and value <= max
end

local commands: { [string]: (session: Sessions.Session, arg: any) -> (boolean, any) } = {}

commands.energy = function(session, amount)
	if not isPositive(amount, 1e15) then
		return false, "BadRequest"
	end
	Inventory.earn(session.profile, amount)
	Sessions.replicate(session)
	return true, { energy = session.profile.energy }
end

commands.shards = function(session, amount)
	if not isPositive(amount, 1e6) then
		return false, "BadRequest"
	end
	session.profile.shards += math.floor(amount)
	Sessions.replicate(session)
	return true, { shards = session.profile.shards }
end

-- arg = "artifactId|mutation|stars" (an item key)
commands.give = function(session, key)
	local item = Items.parse(key)
	if not item then
		return false, "InvalidItem"
	end
	Inventory.discover(session.profile, item, Sessions.now())
	Inventory.add(session.profile, key, 1)
	Plots.refreshShowcase(session)
	Sessions.replicate(session)
	return true, { key = key }
end

-- Gives one plain copy of every artifact (collection testing).
commands.giveAll = function(session)
	for _, artifact in Artifacts.List do
		local item = { id = artifact.id, mut = "", stars = 1 }
		Inventory.discover(session.profile, item, Sessions.now())
		Inventory.add(session.profile, Items.keyOf(item), 1)
	end
	for _, mutation in Mutations.List do
		local item = { id = "scrap_cube", mut = mutation.id, stars = 1 }
		Inventory.discover(session.profile, item, Sessions.now())
		Inventory.add(session.profile, Items.keyOf(item), 1)
	end
	Plots.refreshShowcase(session)
	Sessions.replicate(session)
	return true, {}
end

-- Simulates `seconds` of production (max 24h) in one step.
commands.warp = function(session, seconds)
	if not isPositive(seconds, 86400) then
		return false, "BadRequest"
	end
	local before = session.profile.energy
	local now = Sessions.now()
	Simulation.tick(session.profile, session.runtime, seconds, now, session.rng)
	for machineId in session.profile.machines do
		local state = session.profile.machines[machineId]
		state.chargeAt -= seconds
		State.updateCharges(session.profile, machineId, Sessions.production(session), now)
	end
	Sessions.replicate(session)
	return true, { gained = session.profile.energy - before }
end

commands.charges = function(session)
	for machineId, state in session.profile.machines do
		local cap = State.chargeCap(session.profile, machineId)
		if cap > 0 then
			state.charges = cap
		end
	end
	Sessions.replicate(session)
	return true, {}
end

commands.reset = function(session)
	Sessions.replaceProfile(session, Profile.new(Sessions.now()))
	return true, {}
end

commands.status = function(session)
	local production = Sessions.production(session)
	return true,
		{
			eps = production.total,
			luckBonus = production.luckBonus,
			storage = State.capacity(session.profile),
			maxLuck = Economy.MaxLuck,
		}
end

function Admin.start()
	Net.on("Admin", function(player, command, arg)
		if not Admin.isAdmin(player) then
			return false, "NotAllowed"
		end
		local session = Sessions.get(player)
		if not session then
			return false, "NotReady"
		end
		local fn = commands[command]
		if not fn then
			return false, "BadRequest"
		end
		return fn(session, arg)
	end)
	Sessions.Started:Connect(function(session)
		session.player:SetAttribute("IsAdmin", Admin.isAdmin(session.player))
	end)
end

return Admin
