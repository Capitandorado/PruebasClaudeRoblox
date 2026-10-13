-- Counts the parts each procedural model creates (performance budget check).
-- Usage: lune run tools/part_audit.luau

local Fixture = require("../tests/lib/Fixture")

local rt = Fixture.modules()
local Artifacts = Fixture.require(rt, "Config.Artifacts")
local Machines = Fixture.require(rt, "Config.Machines")
local ArtifactModels = Fixture.require(rt, "Visuals.ArtifactModels")
local MachineModels = Fixture.require(rt, "Visuals.MachineModels")

local function count(model)
	local parts, lights, emitters = 0, 0, 0
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			parts += 1
		elseif descendant:IsA("Light") then
			lights += 1
		elseif descendant:IsA("ParticleEmitter") then
			emitters += 1
		end
	end
	return parts, lights, emitters
end

local worst = 0
rt:asServer(function()
	print("Artifacts (parts / lights / emitters)")
	for _, artifact in Artifacts.List do
		local parts, lights, emitters = count(ArtifactModels.build(artifact.id))
		worst = math.max(worst, parts)
		print(string.format("  %-16s %3d / %d / %d", artifact.id, parts, lights, emitters))
	end
	print("Machines")
	for _, machine in Machines.List do
		local parts = count(MachineModels.build(machine.id))
		print(string.format("  %-18s %3d", machine.id, parts))
	end
end)
for _, line in rt:outputOf("print") do
	print(line)
end
print(string.format("Worst case plot (24 x worst artifact): %d parts", 24 * worst))
