--!strict
-- Procedural models for machines. Every model is built on an 8x8 pad with its base at y = 0,
-- facing -Z (the front of the plot). An invisible "Output" part marks where boxes appear.

local Shared = script.Parent.Parent
local Machines = require(Shared.Config.Machines)
local Build = require(Shared.Util.Build)

local MachineModels = {}

local N = Enum.Material
local DARK = Color3.fromRGB(34, 36, 48)
local STEEL = Color3.fromRGB(120, 126, 140)

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

-- Groups animated parts in a sub-model the client animates (WorldFX): "Spinner" rotates
-- around its pivot, "Slider" moves back and forth along its local X axis.
local function animated(model: Model, name: string, tag: string, pivot: CFrame, attributes: { [string]: number }): Model
	local group = Build.model(name, model)
	Build.root(group, pivot)
	group:AddTag(tag)
	for key, value in attributes do
		group:SetAttribute(key, value)
	end
	return group
end

local function output(model: Model, position: Vector3)
	local part = Build.part({
		Name = "Output",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(position),
		Transparency = 1,
		Parent = model,
	})
	part.CanQuery = false
end

type Builder = (model: Model, color: Color3) -> ()
local builders: { [string]: Builder } = {}

builders.starter_fabricator = function(model, color)
	Build.part({
		Name = "Body",
		Size = Vector3.new(6, 4.5, 5),
		CFrame = at(0, 2.25, 0.5),
		Color = DARK,
		Material = N.Metal,
		CanCollide = true,
		Parent = model,
	})
	Build.part({
		Name = "Window",
		Size = Vector3.new(3.6, 2, 0.2),
		CFrame = at(0, 2.6, -2.05),
		Color = color,
		Material = N.Neon,
		Parent = model,
	})
	Build.part({
		Name = "Trim",
		Size = Vector3.new(6.2, 0.3, 5.2),
		CFrame = at(0, 4.6, 0.5),
		Color = color,
		Material = N.Neon,
		Parent = model,
	})
	Build.cylinder({
		Name = "Funnel",
		Height = 1.6,
		Diameter = 3,
		CFrame = at(0, 5.6, 0.5),
		Color = STEEL,
		Material = N.Metal,
		Parent = model,
	})
	Build.cylinder({
		Name = "FunnelRim",
		Height = 0.3,
		Diameter = 3.3,
		CFrame = at(0, 6.45, 0.5),
		Color = color,
		Material = N.Neon,
		Parent = model,
	})
	Build.part({
		Class = "WedgePart",
		Name = "Chute",
		Size = Vector3.new(3, 1, 2),
		CFrame = at(0, 0.5, -3) * CFrame.Angles(0, math.pi, 0),
		Color = STEEL,
		Material = N.DiamondPlate,
		Parent = model,
	})
	for _, x in { -2.6, 2.6 } do
		Build.part({
			Name = "Vent",
			Size = Vector3.new(0.3, 2.6, 3),
			CFrame = at(x, 2.3, 0.8),
			Color = Color3.fromRGB(20, 20, 26),
			Material = N.Metal,
			Parent = model,
		})
	end
	Build.light(model:FindFirstChild("Window") :: BasePart, color, 2, 12)
	output(model, Vector3.new(0, 7.5, -1))
end

builders.box_printer = function(model, color)
	Build.part({
		Name = "Body",
		Size = Vector3.new(7, 3, 4.5),
		CFrame = at(0, 1.5, 0.5),
		Color = DARK,
		Material = N.Metal,
		CanCollide = true,
		Parent = model,
	})
	Build.part({
		Name = "Rail",
		Size = Vector3.new(7, 0.4, 0.6),
		CFrame = at(0, 4.6, 0.5),
		Color = STEEL,
		Material = N.Metal,
		Parent = model,
	})
	for _, x in { -3.3, 3.3 } do
		Build.part({
			Name = "Post",
			Size = Vector3.new(0.5, 1.8, 0.6),
			CFrame = at(x, 3.8, 0.5),
			Color = STEEL,
			Material = N.Metal,
			Parent = model,
		})
	end
	local carriage = animated(model, "Carriage", "Slider", at(0, 3.9, 0.5), { SlideAmplitude = 2.3, SlideSpeed = 1.8 })
	Build.part({
		Name = "Head",
		Size = Vector3.new(1.4, 1, 1.2),
		CFrame = at(0, 3.9, 0.5),
		Color = color,
		Material = N.Metal,
		Parent = carriage,
	})
	Build.part({
		Name = "Nozzle",
		Size = Vector3.new(0.4, 0.6, 0.4),
		CFrame = at(0, 3.2, 0.5),
		Color = color,
		Material = N.Neon,
		Parent = carriage,
	})
	Build.part({
		Name = "Tray",
		Size = Vector3.new(5, 0.3, 2.4),
		CFrame = at(0, 1.2, -2.6),
		Color = STEEL,
		Material = N.DiamondPlate,
		Parent = model,
	})
	for _, x in { -2.5, 0, 2.5 } do
		Build.part({
			Name = "Stripe",
			Size = Vector3.new(1.2, 0.2, 0.1),
			CFrame = at(x, 2.4, -1.8),
			Color = color,
			Material = N.Neon,
			Parent = model,
		})
	end
	Build.light(carriage:FindFirstChild("Nozzle") :: BasePart, color, 2, 10)
	output(model, Vector3.new(0, 4.5, -2.6))
end

builders.overclocker = function(model, color)
	Build.cylinder({
		Name = "Base",
		Height = 1,
		Diameter = 5.5,
		CFrame = at(0, 0.5, 0),
		Color = DARK,
		Material = N.Metal,
		Parent = model,
	})
	Build.cylinder({
		Name = "Tower",
		Height = 6,
		Diameter = 3.4,
		CFrame = at(0, 4, 0),
		Color = STEEL,
		Material = N.Metal,
		Parent = model,
	})
	for _, y in { 2.4, 4, 5.6 } do
		Build.cylinder({
			Name = "Coil",
			Height = 0.4,
			Diameter = 3.8,
			CFrame = at(0, y, 0),
			Color = color,
			Material = N.Neon,
			Parent = model,
		})
	end
	Build.cylinder({
		Name = "Cap",
		Height = 0.6,
		Diameter = 4,
		CFrame = at(0, 7.3, 0),
		Color = DARK,
		Material = N.Metal,
		Parent = model,
	})
	local fan = animated(model, "Fan", "Spinner", at(0, 7.8, 0), { SpinSpeed = 320 })
	for index = 1, 4 do
		Build.part({
			Name = "FanBlade",
			Size = Vector3.new(3.2, 0.15, 0.7),
			CFrame = at(0, 7.8, 0) * CFrame.Angles(0, index / 4 * math.pi, math.rad(12)),
			Color = color,
			Material = N.Metal,
			Parent = fan,
		})
	end
	Build.light(model:FindFirstChild("Coil") :: BasePart, color, 2.5, 14)
	output(model, Vector3.new(0, 9, 0))
end

builders.fusion_chamber = function(model, color)
	Build.cylinder({
		Name = "Base",
		Height = 1.2,
		Diameter = 6,
		CFrame = at(0, 0.6, 0),
		Color = DARK,
		Material = N.Metal,
		Parent = model,
	})
	Build.sphere({
		Name = "Chamber",
		Diameter = 4.2,
		CFrame = at(0, 4, 0),
		Color = Color3.fromRGB(200, 220, 255),
		Material = N.Glass,
		Transparency = 0.55,
		Parent = model,
	})
	local core = Build.sphere({
		Name = "Core",
		Diameter = 1.6,
		CFrame = at(0, 4, 0),
		Color = color,
		Material = N.Neon,
		Parent = model,
	})
	core:AddTag("Pulse")
	for index = 1, 3 do
		local angle = index / 3 * math.pi * 2
		local base = Vector3.new(math.cos(angle) * 2.6, 1.2, math.sin(angle) * 2.6)
		local tip = Vector3.new(math.cos(angle) * 1.4, 4, math.sin(angle) * 1.4)
		local length = (tip - base).Magnitude
		Build.part({
			Name = "Prong",
			Size = Vector3.new(0.5, length, 0.5),
			CFrame = CFrame.lookAt((base + tip) / 2, tip) * CFrame.Angles(math.pi / 2, 0, 0),
			Color = STEEL,
			Material = N.Metal,
			Parent = model,
		})
		Build.sphere({
			Name = "Emitter",
			Diameter = 0.6,
			CFrame = CFrame.new(tip),
			Color = color,
			Material = N.Neon,
			Parent = model,
		})
	end
	Build.light(model:FindFirstChild("Core") :: BasePart, color, 3, 14)
	output(model, Vector3.new(0, 4, 0))
end

builders.lucky_fabricator = function(model, color)
	Build.part({
		Name = "Body",
		Size = Vector3.new(6, 4.5, 5),
		CFrame = at(0, 2.25, 0.5),
		Color = Color3.fromRGB(30, 60, 40),
		Material = N.Metal,
		CanCollide = true,
		Parent = model,
	})
	Build.part({
		Name = "Window",
		Size = Vector3.new(3.6, 2, 0.2),
		CFrame = at(0, 2.6, -2.05),
		Color = color,
		Material = N.Neon,
		Parent = model,
	})
	Build.part({
		Name = "Trim",
		Size = Vector3.new(6.2, 0.3, 5.2),
		CFrame = at(0, 4.6, 0.5),
		Color = Color3.fromRGB(255, 210, 80),
		Material = N.Neon,
		Parent = model,
	})
	local clover = animated(model, "Clover", "Spinner", at(0, 5.7, 0.5), { SpinSpeed = 45 })
	for index = 1, 4 do
		local angle = index / 4 * math.pi * 2 + math.pi / 4
		Build.sphere({
			Name = "Leaf",
			Diameter = 1.5,
			CFrame = at(math.cos(angle) * 0.75, 5.7, 0.5 + math.sin(angle) * 0.75),
			Color = color,
			Material = N.Neon,
			Parent = clover,
		})
	end
	Build.part({
		Name = "Stem",
		Size = Vector3.new(0.3, 1, 0.3),
		CFrame = at(0, 5, 0.5),
		Color = Color3.fromRGB(60, 160, 70),
		Material = N.SmoothPlastic,
		Parent = model,
	})
	Build.part({
		Class = "WedgePart",
		Name = "Chute",
		Size = Vector3.new(3, 1, 2),
		CFrame = at(0, 0.5, -3) * CFrame.Angles(0, math.pi, 0),
		Color = STEEL,
		Material = N.DiamondPlate,
		Parent = model,
	})
	Build.light(model:FindFirstChild("Window") :: BasePart, color, 2, 12)
	output(model, Vector3.new(0, 7.8, -1))
end

builders.void_forge = function(model, color)
	Build.part({
		Name = "Anvil",
		Size = Vector3.new(6, 1.6, 4),
		CFrame = at(0, 0.8, 0.5),
		Color = Color3.fromRGB(12, 10, 20),
		Material = N.Basalt,
		CanCollide = true,
		Parent = model,
	})
	Build.part({
		Name = "Obelisk",
		Size = Vector3.new(2.4, 6.5, 2.4),
		CFrame = at(0, 4.85, 1),
		Color = Color3.fromRGB(10, 8, 16),
		Material = N.Slate,
		Parent = model,
	})
	for index = 1, 5 do
		Build.part({
			Name = "Crack",
			Size = Vector3.new(0.15, 1 + (index % 3) * 0.6, 0.1),
			CFrame = at(-0.8 + index * 0.3, 2.5 + index * 0.9, -0.23)
				* CFrame.Angles(0, 0, math.rad((index % 2) * 40 - 20)),
			Color = color,
			Material = N.Neon,
			Parent = model,
		})
	end
	local halo = animated(model, "Halo", "Spinner", at(0, 6.5, 1), { SpinSpeed = -50 })
	Build.ring(halo, at(0, 6.5, 1) * CFrame.Angles(math.rad(15), 0, 0), 2.6, 0.25, 22, color, N.Neon)
	local rift = Build.sphere({
		Name = "Rift",
		Diameter = 1.4,
		CFrame = at(0, 8.8, 1),
		Color = color,
		Material = N.ForceField,
		Parent = model,
	})
	rift:AddTag("Pulse")
	Build.light(rift, color, 3, 16)
	Build.particles(rift, "Glow", color, 4)
	output(model, Vector3.new(0, 3.5, -2))
end

-- Builds a machine model. Its pivot is the centre of the pad top.
function MachineModels.build(machineId: string): Model
	local machine = Machines.get(machineId)
	local model = Build.model(machineId)
	Build.root(model, CFrame.new(0, 0.5, 0))
	local builder = builders[machineId]
	if machine and builder then
		builder(model, machine.color)
	else
		Build.part({
			Name = "Body",
			Size = Vector3.new(5, 5, 5),
			CFrame = at(0, 2.5, 0),
			Color = DARK,
			Material = N.Metal,
			Parent = model,
		})
		output(model, Vector3.new(0, 7, 0))
	end
	model:SetAttribute("MachineId", machineId)
	return model
end

-- Translucent hologram shown on pads whose machine is not bought yet.
function MachineModels.hologram(machineId: string): Model
	local machine = Machines.get(machineId)
	local color = if machine then machine.color else Color3.new(1, 1, 1)
	local model = MachineModels.build(machineId)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name ~= "Root" and descendant.Name ~= "Output" then
			descendant.Material = N.ForceField
			descendant.Color = color
			descendant.Transparency = 0.25
			descendant.CanCollide = false
		elseif descendant:IsA("ParticleEmitter") or descendant:IsA("Light") then
			descendant:Destroy()
		end
	end
	model:SetAttribute("Hologram", true)
	return model
end

return MachineModels
