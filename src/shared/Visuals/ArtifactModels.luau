--!strict
-- Procedural 3D models for every artifact. Each `shape` has its own silhouette; rarity adds
-- light and particles, mutations change materials/colours, stars add orbiting beads.
-- Models are built around the origin (~3.5 studs tall) and anchored; callers PivotTo them.
-- Used by the server (pedestals, showcase) and the client (box reveals, previews).

local Shared = script.Parent.Parent
local Artifacts = require(Shared.Config.Artifacts)
local Rarities = require(Shared.Config.Rarities)
local Mutations = require(Shared.Config.Mutations)
local Build = require(Shared.Util.Build)

local ArtifactModels = {}

type Artifact = Artifacts.Artifact
type ShapeBuilder = (model: Model, artifact: Artifact) -> ()

local N = Enum.Material

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

local function darker(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

local shapes: { [string]: ShapeBuilder } = {}

shapes.ScrapCube = function(model, a)
	Build.part({
		Name = "Body",
		Size = Vector3.new(2.2, 2.2, 2.2),
		Color = a.primary,
		Material = N.Metal,
		Parent = model,
	})
	for _, face in { Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis, Vector3.yAxis } do
		local size = Vector3.new(1.5, 1.5, 1.5) - face:Abs() * 1.4
		Build.part({
			Name = "Plate",
			Size = size,
			CFrame = CFrame.new(face * 1.12),
			Color = darker(a.primary, 0.25),
			Material = N.DiamondPlate,
			Parent = model,
		})
	end
	for _, x in { -1, 1 } do
		Build.part({
			Name = "Strip",
			Size = Vector3.new(0.15, 2.3, 0.15),
			CFrame = at(x * 1.1, 0, 1.1),
			Color = a.secondary,
			Material = N.Neon,
			Parent = model,
		})
	end
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			Build.sphere({
				Name = "Bolt",
				Diameter = 0.35,
				CFrame = at(x * 1.05, 1.05, z * 1.05),
				Color = Color3.fromRGB(70, 70, 80),
				Material = N.Metal,
				Parent = model,
			})
		end
	end
end

shapes.Shard = function(model, a)
	local crystals = {
		{ size = Vector3.new(0.7, 3, 0.7), cf = at(0, 0.2, 0) * CFrame.Angles(0, math.rad(45), math.rad(4)) },
		{ size = Vector3.new(0.5, 2, 0.5), cf = at(0.6, -0.3, 0.2) * CFrame.Angles(0, math.rad(20), math.rad(-25)) },
		{
			size = Vector3.new(0.5, 1.8, 0.5),
			cf = at(-0.55, -0.4, -0.2) * CFrame.Angles(math.rad(10), math.rad(70), math.rad(28)),
		},
		{ size = Vector3.new(0.4, 1.3, 0.4), cf = at(0.1, -0.6, -0.6) * CFrame.Angles(math.rad(-30), 0, math.rad(8)) },
	}
	for index, crystal in crystals do
		Build.part({
			Name = "Crystal" .. index,
			Size = crystal.size,
			CFrame = crystal.cf,
			Color = a.primary,
			Material = N.Glass,
			Transparency = 0.25,
			Parent = model,
		})
		Build.part({
			Name = "Core" .. index,
			Size = crystal.size * Vector3.new(0.45, 0.8, 0.45),
			CFrame = crystal.cf,
			Color = a.secondary,
			Material = N.Neon,
			Parent = model,
		})
	end
	Build.part({
		Name = "Base",
		Size = Vector3.new(1.6, 0.3, 1.6),
		CFrame = at(0, -1.1, 0),
		Color = Color3.fromRGB(50, 55, 70),
		Material = N.Slate,
		Parent = model,
	})
end

shapes.Battery = function(model, a)
	Build.cylinder({
		Name = "Body",
		Height = 2.6,
		Diameter = 1.6,
		Color = a.primary,
		Material = N.Metal,
		Parent = model,
	})
	Build.cylinder({
		Name = "Band",
		Height = 0.35,
		Diameter = 1.7,
		CFrame = at(0, 0.4, 0),
		Color = a.secondary,
		Material = N.Neon,
		Parent = model,
	})
	Build.cylinder({
		Name = "Band2",
		Height = 0.2,
		Diameter = 1.7,
		CFrame = at(0, -0.4, 0),
		Color = a.secondary,
		Material = N.Neon,
		Parent = model,
	})
	Build.cylinder({
		Name = "Cap",
		Height = 0.3,
		Diameter = 1.75,
		CFrame = at(0, 1.35, 0),
		Color = Color3.fromRGB(200, 200, 210),
		Material = N.Metal,
		Parent = model,
	})
	Build.cylinder({
		Name = "Terminal",
		Height = 0.4,
		Diameter = 0.5,
		CFrame = at(0, 1.7, 0),
		Color = Color3.fromRGB(230, 200, 80),
		Material = N.Metal,
		Parent = model,
	})
	Build.cylinder({
		Name = "Bottom",
		Height = 0.3,
		Diameter = 1.75,
		CFrame = at(0, -1.35, 0),
		Color = Color3.fromRGB(200, 200, 210),
		Material = N.Metal,
		Parent = model,
	})
end

shapes.Coil = function(model, a)
	Build.cylinder({ Name = "Core", Height = 3, Diameter = 0.6, Color = a.secondary, Material = N.Neon, Parent = model })
	for index, y in { -1, -0.35, 0.3, 0.95 } do
		Build.ring(model, at(0, y, 0) * CFrame.Angles(0, index * 0.4, 0), 0.75, 0.22, 10, a.primary, N.Metal)
	end
	Build.cylinder({
		Name = "Top",
		Height = 0.25,
		Diameter = 1.2,
		CFrame = at(0, 1.5, 0),
		Color = darker(a.primary, 0.4),
		Material = N.Metal,
		Parent = model,
	})
	Build.cylinder({
		Name = "Base",
		Height = 0.25,
		Diameter = 1.4,
		CFrame = at(0, -1.5, 0),
		Color = darker(a.primary, 0.4),
		Material = N.Metal,
		Parent = model,
	})
end

shapes.Reactor = function(model, a)
	Build.sphere({ Name = "Core", Diameter = 1.5, Color = a.secondary, Material = N.Neon, Parent = model })
	for index = 1, 6 do
		local angle = index / 6 * math.pi * 2
		Build.part({
			Name = "Bar",
			Size = Vector3.new(0.18, 2.8, 0.18),
			CFrame = at(math.cos(angle) * 1.05, 0, math.sin(angle) * 1.05),
			Color = a.primary,
			Material = N.Metal,
			Parent = model,
		})
	end
	Build.ring(model, at(0, 1.35, 0), 1.05, 0.2, 12, a.primary, N.Metal)
	Build.ring(model, at(0, -1.35, 0), 1.05, 0.2, 12, a.primary, N.Metal)
	Build.ring(model, at(0, 0, 0), 1.25, 0.12, 14, a.secondary, N.Neon)
end

shapes.Prism = function(model, a)
	local half = 0.9
	Build.part({
		Class = "WedgePart",
		Name = "PrismA",
		Size = Vector3.new(1.8, 2.4, half),
		CFrame = at(0, 0, half / 2) * CFrame.Angles(0, math.pi, 0),
		Color = a.primary,
		Material = N.Glass,
		Transparency = 0.2,
		Parent = model,
	})
	Build.part({
		Class = "WedgePart",
		Name = "PrismB",
		Size = Vector3.new(1.8, 2.4, half),
		CFrame = at(0, 0, -half / 2),
		Color = a.primary,
		Material = N.Glass,
		Transparency = 0.2,
		Parent = model,
	})
	Build.part({
		Name = "Beam",
		Size = Vector3.new(2.6, 0.12, 0.12),
		CFrame = at(0, -0.2, 0),
		Color = a.secondary,
		Material = N.Neon,
		Parent = model,
	})
	Build.ring(model, at(0, 1.6, 0) * CFrame.Angles(math.rad(20), 0, 0), 0.8, 0.12, 12, a.secondary, N.Neon)
	Build.part({
		Name = "Base",
		Size = Vector3.new(2, 0.25, 1.4),
		CFrame = at(0, -1.3, 0),
		Color = Color3.fromRGB(60, 60, 80),
		Material = N.Metal,
		Parent = model,
	})
end

shapes.Duplicator = function(model, a)
	for _, x in { -0.8, 0.8 } do
		Build.part({
			Name = "Cell",
			Size = Vector3.new(1.2, 1.6, 1.2),
			CFrame = at(x, 0, 0),
			Color = a.primary,
			Material = N.Metal,
			Parent = model,
		})
		Build.part({
			Name = "Window",
			Size = Vector3.new(0.9, 1.1, 1.25),
			CFrame = at(x, 0.05, 0),
			Color = a.secondary,
			Material = N.Neon,
			Transparency = 0.15,
			Parent = model,
		})
		Build.part({
			Class = "WedgePart",
			Name = "Arrow",
			Size = Vector3.new(0.6, 0.6, 0.6),
			CFrame = at(x, 1.15, 0) * CFrame.Angles(0, if x < 0 then math.pi / 2 else -math.pi / 2, 0),
			Color = a.secondary,
			Material = N.Neon,
			Parent = model,
		})
	end
	Build.part({
		Name = "Bridge",
		Size = Vector3.new(0.5, 0.3, 0.3),
		CFrame = at(0, 0.3, 0),
		Color = a.secondary,
		Material = N.Neon,
		Parent = model,
	})
	Build.part({
		Name = "Base",
		Size = Vector3.new(3, 0.3, 1.5),
		CFrame = at(0, -0.95, 0),
		Color = darker(a.primary, 0.3),
		Material = N.Metal,
		Parent = model,
	})
end

shapes.GravityWell = function(model, a)
	Build.sphere({
		Name = "Core",
		Diameter = 1.4,
		Color = a.primary,
		Material = N.Glass,
		Transparency = 0.1,
		Parent = model,
	})
	Build.sphere({ Name = "Inner", Diameter = 0.8, Color = a.secondary, Material = N.Neon, Parent = model })
	Build.ring(model, CFrame.Angles(math.rad(25), 0, 0), 1.3, 0.12, 16, a.secondary, N.Neon)
	Build.ring(model, CFrame.Angles(math.rad(-30), math.rad(60), 0), 1.55, 0.1, 18, darker(a.secondary, 0.3), N.Neon)
	for index = 1, 3 do
		local angle = index / 3 * math.pi * 2
		Build.sphere({
			Name = "Moon",
			Diameter = 0.3,
			CFrame = at(math.cos(angle) * 1.55, math.sin(angle) * 0.6, math.sin(angle) * 1.2),
			Color = a.secondary,
			Material = N.Neon,
			Parent = model,
		})
	end
end

shapes.Entropy = function(model, a)
	local fragments = {
		{ 0, 0, 0, 1.2, 0, 0.3, 0.6 },
		{ 0.7, 0.5, 0.2, 0.7, 0.8, 0.2, 1.1 },
		{ -0.6, 0.6, -0.3, 0.8, 0.4, 1.0, 0.2 },
		{ 0.2, -0.7, 0.6, 0.6, 1.3, 0.7, 0.4 },
		{ -0.4, -0.5, -0.6, 0.7, 0.3, 1.4, 0.9 },
		{ 0.5, 1.1, -0.5, 0.45, 1.6, 0.5, 0.1 },
		{ -0.8, 0.0, 0.7, 0.5, 0.9, 0.1, 1.3 },
	}
	for index, f in fragments do
		local color = if index % 2 == 0 then a.secondary else a.primary
		Build.part({
			Name = "Fragment" .. index,
			Size = Vector3.new(f[4], f[4] * 1.3, f[4]),
			CFrame = at(f[1], f[2], f[3]) * CFrame.Angles(f[5], f[6], f[7]),
			Color = color,
			Material = if index % 2 == 0 then N.Neon else N.Granite,
			Parent = model,
		})
	end
	Build.sphere({
		Name = "Heart",
		Diameter = 0.9,
		Color = Color3.fromRGB(255, 255, 255),
		Material = N.Neon,
		Parent = model,
	})
end

shapes.Turbine = function(model, a)
	Build.cylinder({
		Name = "Hub",
		Height = 0.7,
		Diameter = 1,
		CFrame = CFrame.Angles(math.pi / 2, 0, 0),
		Color = a.secondary,
		Material = N.Neon,
		Parent = model,
	})
	for index = 1, 6 do
		local angle = index / 6 * math.pi * 2
		Build.part({
			Name = "Blade",
			Size = Vector3.new(0.35, 1.3, 0.12),
			CFrame = CFrame.Angles(0, 0, angle) * at(0, 0.95, 0) * CFrame.Angles(0, math.rad(25), 0),
			Color = a.primary,
			Material = N.Metal,
			Parent = model,
		})
	end
	Build.ring(model, CFrame.Angles(math.pi / 2, 0, 0), 1.7, 0.2, 18, a.primary, N.Metal)
	Build.ring(model, CFrame.Angles(math.pi / 2, 0, 0), 1.85, 0.08, 18, a.secondary, N.Neon)
	Build.part({
		Name = "Stand",
		Size = Vector3.new(0.4, 1.2, 0.4),
		CFrame = at(0, -1.5, 0),
		Color = darker(a.primary, 0.4),
		Material = N.Metal,
		Parent = model,
	})
end

shapes.Nucleus = function(model, a)
	Build.sphere({ Name = "Void", Diameter = 1.6, Color = a.primary, Material = N.Neon, Parent = model })
	Build.sphere({
		Name = "Shell",
		Diameter = 2.3,
		Color = a.secondary,
		Material = N.ForceField,
		Transparency = 0.1,
		Parent = model,
	})
	Build.ring(model, CFrame.Angles(math.rad(70), 0, 0), 1.6, 0.1, 18, a.secondary, N.Neon)
	Build.ring(model, CFrame.Angles(math.rad(70), math.rad(90), 0), 1.6, 0.1, 18, a.secondary, N.Neon)
end

shapes.Halo = function(model, a)
	Build.sphere({ Name = "Body", Diameter = 1.4, Color = a.primary, Material = N.Neon, Parent = model })
	Build.ring(model, at(0, 1.4, 0), 0.9, 0.18, 16, a.secondary, N.Neon)
	for _, side in { -1, 1 } do
		for index = 1, 3 do
			Build.part({
				Name = "Feather",
				Size = Vector3.new(1.4 - index * 0.25, 0.18, 0.5),
				CFrame = at(side * (0.9 + index * 0.25), 0.2 + index * 0.18, 0)
					* CFrame.Angles(0, 0, side * math.rad(20 + index * 8)),
				Color = Color3.fromRGB(255, 255, 255),
				Material = N.SmoothPlastic,
				Parent = model,
			})
		end
	end
	Build.cylinder({
		Name = "Pedestal",
		Height = 0.3,
		Diameter = 1.2,
		CFrame = at(0, -1.1, 0),
		Color = a.secondary,
		Material = N.Metal,
		Parent = model,
	})
end

shapes.Compass = function(model, a)
	Build.cylinder({
		Name = "Disk",
		Height = 0.25,
		Diameter = 2.4,
		CFrame = CFrame.Angles(math.pi / 2, 0, 0),
		Color = a.primary,
		Material = N.Metal,
		Parent = model,
	})
	for index = 1, 4 do
		local angle = index / 4 * math.pi * 2
		Build.part({
			Class = "WedgePart",
			Name = "StarPoint",
			Size = Vector3.new(0.2, 1.1, 0.5),
			CFrame = CFrame.Angles(0, 0, angle) * at(0, 1.55, 0.05),
			Color = a.secondary,
			Material = N.Neon,
			Parent = model,
		})
	end
	Build.part({
		Name = "Needle",
		Size = Vector3.new(0.18, 1.8, 0.12),
		CFrame = at(0, 0, 0.2) * CFrame.Angles(0, 0, math.rad(35)),
		Color = Color3.fromRGB(255, 80, 80),
		Material = N.Neon,
		Parent = model,
	})
	Build.ring(model, CFrame.Angles(math.pi / 2, 0, 0), 1.35, 0.12, 18, a.secondary, N.Neon)
	Build.ring(model, CFrame.Angles(0, 0, math.rad(90)), 1.6, 0.08, 18, darker(a.secondary, 0.2), N.Neon)
end

shapes.Singularity = function(model, a)
	Build.sphere({
		Name = "Horizon",
		Diameter = 1.5,
		Color = Color3.new(0, 0, 0),
		Material = N.SmoothPlastic,
		Parent = model,
	})
	local colors = { a.secondary, Color3.fromRGB(255, 60, 140), Color3.fromRGB(150, 70, 255) }
	for index, color in colors do
		Build.ring(
			model,
			CFrame.Angles(math.rad(12), 0, math.rad(8)),
			1.1 + index * 0.32,
			0.18,
			20 + index * 2,
			color,
			N.Neon
		)
	end
	Build.cylinder({
		Name = "Jet",
		Height = 4.2,
		Diameter = 0.12,
		Color = Color3.fromRGB(255, 255, 255),
		Material = N.Neon,
		Transparency = 0.2,
		Parent = model,
	})
end

shapes.Anomaly = function(model, a)
	local layers = {
		{ size = 1.8, color = a.primary, rot = CFrame.Angles(0, 0, 0), material = N.Neon, transparency = 0 },
		{
			size = 2.1,
			color = a.secondary,
			rot = CFrame.Angles(math.rad(45), math.rad(45), 0),
			material = N.ForceField,
			transparency = 0,
		},
		{
			size = 2.5,
			color = Color3.fromRGB(80, 255, 255),
			rot = CFrame.Angles(0, math.rad(30), math.rad(60)),
			material = N.Glass,
			transparency = 0.6,
		},
	}
	for index, layer in layers do
		Build.part({
			Name = "Layer" .. index,
			Size = Vector3.new(layer.size, layer.size, layer.size),
			CFrame = layer.rot,
			Color = layer.color,
			Material = layer.material,
			Transparency = layer.transparency,
			Parent = model,
		})
	end
	for index = 1, 6 do
		local angle = index / 6 * math.pi * 2
		Build.part({
			Name = "Glitch",
			Size = Vector3.new(0.3, 0.3, 0.3),
			CFrame = at(math.cos(angle) * 1.9, math.sin(angle * 2) * 0.8, math.sin(angle) * 1.9),
			Color = if index % 2 == 0 then a.secondary else Color3.new(1, 1, 1),
			Material = N.Neon,
			Parent = model,
		})
	end
end

ArtifactModels.Shapes = shapes

local function applyMutation(model: Model, mutationId: string)
	local mutation = Mutations.get(mutationId)
	if not mutation then
		return
	end
	model:SetAttribute("Mutation", mutationId)
	for _, part in model:GetDescendants() do
		if not part:IsA("BasePart") or part.Name == "Root" then
			continue
		end
		if mutationId == "Gold" then
			if part.Material ~= N.Neon then
				part.Color = Color3.fromRGB(255, 196, 50):Lerp(part.Color, 0.15)
				part.Material = N.Foil
				part.Reflectance = 0.25
			end
		elseif mutationId == "Neon" then
			if part.Material ~= N.Glass and part.Transparency < 0.5 then
				part.Material = N.Neon
			end
		elseif mutationId == "Rainbow" then
			part.Material = if part.Material == N.Neon then N.Neon else N.SmoothPlastic
			part:AddTag("RainbowMutation")
		elseif mutationId == "Corrupted" then
			local h, s, v = part.Color:ToHSV()
			part.Color = Color3.fromHSV((h * 0.1 + 0.97) % 1, math.max(s, 0.7), v * 0.45)
			if part.Material == N.Neon then
				part.Color = Color3.fromRGB(255, 20, 50)
			end
			part:AddTag("CorruptedMutation")
		end
	end
	local root = model.PrimaryPart
	if root then
		if mutationId == "Gold" then
			Build.particles(root, "Sparkles", Color3.fromRGB(255, 220, 90), 5)
		elseif mutationId == "Corrupted" then
			Build.particles(root, "Smoke", Color3.fromRGB(60, 0, 20), 4)
		elseif mutationId == "Rainbow" then
			Build.particles(root, "Sparkles", Color3.fromRGB(255, 255, 255), 6)
		end
	end
end

local function addStars(model: Model, stars: number)
	if stars <= 1 then
		return
	end
	local count = stars - 1
	for index = 1, count do
		local angle = index / count * math.pi * 2
		Build.part({
			Name = "Star",
			Size = Vector3.new(0.35, 0.35, 0.35),
			CFrame = at(math.cos(angle) * 1.9, -1.7, math.sin(angle) * 1.9)
				* CFrame.Angles(math.rad(45), 0, math.rad(45)),
			Color = Color3.fromRGB(255, 230, 120),
			Material = N.Neon,
			Parent = model,
		})
	end
end

local function addRarityAura(model: Model, artifact: Artifact)
	local rarity = Rarities.get(artifact.rarity)
	local root = model.PrimaryPart
	if not rarity or not root then
		return
	end
	local order = rarity.order
	Build.light(root, rarity.color, 0.6 + order * 0.25, 6 + order)
	if order >= Rarities.order("Epic") then
		Build.particles(root, "Sparkles", rarity.color, 2 + order)
	end
	if order >= Rarities.order("Mythic") then
		Build.particles(root, "Glow", rarity.color, 3)
		Build.ring(model, at(0, -1.9, 0), 1.6, 0.12, 20, rarity.color, N.Neon)
	end
end

export type BuildOptions = {
	mutation: string?,
	stars: number?,
	effects: boolean?,
}

-- Builds the model for an artifact id. Unknown ids get a neutral placeholder cube.
function ArtifactModels.build(artifactId: string, options: BuildOptions?): Model
	local opts: BuildOptions = options or {}
	local artifact = Artifacts.get(artifactId)
	local model = Build.model(artifactId)
	Build.root(model)
	if artifact then
		local builder = shapes[artifact.shape]
		if builder then
			builder(model, artifact)
		else
			Build.part({
				Name = "Body",
				Size = Vector3.new(2, 2, 2),
				Color = artifact.primary,
				Material = N.Neon,
				Parent = model,
			})
		end
		applyMutation(model, opts.mutation or "")
		addStars(model, opts.stars or 1)
		if opts.effects ~= false then
			addRarityAura(model, artifact)
		end
		model:SetAttribute("ArtifactId", artifactId)
		model:SetAttribute("Rarity", artifact.rarity)
	else
		Build.part({ Name = "Body", Size = Vector3.new(2, 2, 2), Color = Color3.fromRGB(120, 120, 120), Parent = model })
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanTouch = false
		end
	end
	return model
end

return ArtifactModels
