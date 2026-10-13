-- In-server leaderboards: production per second, discoveries and rebirths.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Artifacts = require(Shared.Config.Artifacts)

local Services = script.Parent
local Sessions = require(Services.Sessions)

local Leaderboards = {}

local function discoveries(profile: any): number
	local count = 0
	for artifactId in profile.collection do
		if Artifacts.get(artifactId) then
			count += 1
		end
	end
	return count
end

function Leaderboards.markDirty(_session: any) end

function Leaderboards.snapshot()
	local server = {}
	for _, session in Sessions.all() do
		table.insert(server, {
			userId = session.userId,
			name = session.player.DisplayName,
			eps = Sessions.production(session).total,
			discoveries = discoveries(session.profile),
			rebirths = session.profile.rebirths,
		})
	end
	table.sort(server, function(a, b)
		return a.eps > b.eps
	end)
	return { server = server, global = nil, totalArtifacts = #Artifacts.List }
end

return Leaderboards
