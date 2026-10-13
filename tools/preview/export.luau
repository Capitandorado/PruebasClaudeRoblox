-- Exports the geometry of the procedural models (built by the real game code inside the
-- mock runtime) to JSON for tools/preview/render.py.
--   lune run tools/preview/export.luau <out.json>

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Fixture = require("../../tests/lib/Fixture")

local out = process.args[1] or "build/preview.json"

local function dump(root)
	local parts = {}
	local descendants = root:GetDescendants()
	if root:IsA("BasePart") then
		table.insert(descendants, root)
	end
	for _, part in descendants do
		if part:IsA("BasePart") and part.Transparency < 0.98 then
			local shape = "Block"
			if part.ClassName == "WedgePart" then
				shape = "Wedge"
			elseif part:IsA("Part") then
				shape = tostring(part.Shape):match("%.(%w+)$") or "Block"
			end
			local c = { part.CFrame:GetComponents() }
			local color = part.Color
			table.insert(parts, {
				shape = shape,
				cf = c,
				size = { part.Size.X, part.Size.Y, part.Size.Z },
				color = { color.R, color.G, color.B },
				alpha = 1 - part.Transparency,
				material = tostring(part.Material):match("%.(%w+)$"),
			})
		end
	end
	return parts
end

local result = { artifacts = {}, machines = {}, plot = nil }

-- Single models.
local rt = Fixture.modules()
local Artifacts = Fixture.require(rt, "Config.Artifacts")
local Machines = Fixture.require(rt, "Config.Machines")
local ArtifactModels = Fixture.require(rt, "Visuals.ArtifactModels")
local MachineModels = Fixture.require(rt, "Visuals.MachineModels")
rt:asServer(function()
	for _, artifact in Artifacts.List do
		table.insert(result.artifacts, { id = artifact.id, name = artifact.name, rarity = artifact.rarity, parts = dump(ArtifactModels.build(artifact.id)) })
	end
	for _, mutation in { "Gold", "Neon", "Rainbow", "Corrupted" } do
		table.insert(result.artifacts, {
			id = "reactor_core:" .. mutation,
			name = mutation .. " Reactor Core",
			rarity = mutation,
			parts = dump(ArtifactModels.build("reactor_core", { mutation = mutation, stars = 3 })),
		})
	end
	for _, machine in Machines.List do
		table.insert(result.machines, { id = machine.id, name = machine.name, parts = dump(MachineModels.build(machine.id)) })
	end
end)

-- A late-game plot: everything bought, every pedestal filled.
local server = Fixture.server({ isStudio = true })
local player = Fixture.join(server, { userId = 1 })
local session = Fixture.session(server, player)
local profile = session.profile
profile.expansion = 5
profile.rebirths = 1
for _, machine in Machines.List do
	profile.machines[machine.id] = { level = 3, charges = 0, chargeAt = 0 }
end
local fill = {
	"the_singularity||1", "void_nucleus|Rainbow|2", "astral_compass||1", "halo_reactor|Gold|1",
	"the_anomaly||1", "gravity_well||3", "chrono_turbine||1", "entropy_engine|Neon|1",
	"reactor_core||2", "prism_lens||1", "echo_duplicator||1", "flux_coil||1",
}
for slot = 1, 24 do
	profile.placed[tostring(slot)] = fill[(slot - 1) % #fill + 1]
	local id = string.match(fill[(slot - 1) % #fill + 1], "^([^|]+)")
	profile.collection[id] = { count = 1, muts = {}, stars = 1, first = 0 }
end
local plots = server:requireIn("server", server.services.ServerScriptService.Server.Services.Plots)
server:asServer(function()
	plots.refresh(session)
end)
local plotModel = server:find(server.workspace, "VoidFactory.Plots.Plot_" .. session.plot)
local origin = { plotModel.PrimaryPart.CFrame:GetComponents() }
result.plot = { origin = origin, parts = dump(plotModel) }

fs.writeFile(out, serde.encode("json", result))
print(string.format("exported %d artifacts, %d machines, %d plot parts -> %s", #result.artifacts, #result.machines, #result.plot.parts, out))
