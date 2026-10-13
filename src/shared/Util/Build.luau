--!strict
-- Small helpers to assemble procedural models from parts.

local Assets = require(script.Parent.Parent.Config.Assets)

local Build = {}

export type PartProps = {
	Name: string?,
	Size: Vector3?,
	CFrame: CFrame?,
	Color: Color3?,
	Material: Enum.Material?,
	Shape: Enum.PartType?,
	Transparency: number?,
	Reflectance: number?,
	CanCollide: boolean?,
	CastShadow: boolean?,
	Class: string?,
	Parent: Instance?,
}

function Build.part(props: PartProps): BasePart
	local part = Instance.new((props.Class or "Part") :: any) :: BasePart
	part.Name = props.Name or "Part"
	part.Anchored = true
	part.Size = props.Size or Vector3.new(1, 1, 1)
	part.CFrame = props.CFrame or CFrame.new()
	part.Color = props.Color or Color3.new(1, 1, 1)
	part.Material = props.Material or Enum.Material.SmoothPlastic
	part.Transparency = props.Transparency or 0
	part.Reflectance = props.Reflectance or 0
	part.CanCollide = if props.CanCollide == nil then false else props.CanCollide
	part.CastShadow = if props.CastShadow == nil then false else props.CastShadow
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if props.Shape and part:IsA("Part") then
		part.Shape = props.Shape
	end
	if props.Parent then
		part.Parent = props.Parent
	end
	return part
end

function Build.model(name: string, parent: Instance?): Model
	local model = Instance.new("Model")
	model.Name = name
	if parent then
		model.Parent = parent
	end
	return model
end

-- Invisible anchor used as the model's PrimaryPart/pivot.
function Build.root(model: Model, cframe: CFrame?, size: Vector3?): BasePart
	local root = Build.part({
		Name = "Root",
		Size = size or Vector3.new(1, 1, 1),
		CFrame = cframe or CFrame.new(),
		Transparency = 1,
		Parent = model,
	})
	root.CanQuery = false
	model.PrimaryPart = root
	return root
end

-- Cylinder standing upright (Roblox cylinders extend along their X axis).
function Build.cylinder(props: PartProps & { Height: number, Diameter: number }): BasePart
	local cframe = (props.CFrame or CFrame.new()) * CFrame.Angles(0, 0, math.pi / 2)
	local copy = table.clone(props) :: any
	copy.Size = Vector3.new(props.Height, props.Diameter, props.Diameter)
	copy.CFrame = cframe
	copy.Shape = Enum.PartType.Cylinder
	copy.Height = nil
	copy.Diameter = nil
	return Build.part(copy)
end

function Build.sphere(props: PartProps & { Diameter: number }): BasePart
	local copy = table.clone(props) :: any
	copy.Size = Vector3.new(props.Diameter, props.Diameter, props.Diameter)
	copy.Shape = Enum.PartType.Ball
	copy.Diameter = nil
	return Build.part(copy)
end

-- Ring of block segments lying in the local XZ plane of `cframe`.
function Build.ring(
	parent: Instance,
	cframe: CFrame,
	radius: number,
	thickness: number,
	segments: number,
	color: Color3,
	material: Enum.Material?
): { BasePart }
	local parts = {}
	local segmentLength = 2 * math.pi * radius / segments * 1.08
	for index = 1, segments do
		local angle = (index - 1) / segments * math.pi * 2
		local segmentCFrame = cframe * CFrame.Angles(0, angle, 0) * CFrame.new(radius, 0, 0)
		table.insert(
			parts,
			Build.part({
				Name = "Ring",
				Size = Vector3.new(thickness, thickness, segmentLength),
				CFrame = segmentCFrame,
				Color = color,
				Material = material or Enum.Material.Neon,
				Parent = parent,
			})
		)
	end
	return parts
end

function Build.light(parent: Instance, color: Color3, brightness: number, range: number): PointLight
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Shadows = false
	light.Parent = parent
	return light
end

export type ParticlePreset = "Sparkles" | "Smoke" | "Glow" | "Fire"

-- Particle emitters are tagged "VFX" so the client can mute them with "Reduce effects".
function Build.particles(parent: Instance, preset: ParticlePreset, color: Color3, rate: number?): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = preset .. "Particles"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Rate = rate or 6
	emitter.Lifetime = NumberRange.new(0.8, 1.6)
	emitter.Speed = NumberRange.new(0.5, 1.5)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-90, 90)
	if preset == "Sparkles" then
		emitter.Texture = Assets.Textures.Sparkles
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(1, 0),
		})
	elseif preset == "Smoke" then
		emitter.Texture = Assets.Textures.Smoke
		emitter.LightEmission = 0
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.6),
			NumberSequenceKeypoint.new(1, 1.6),
		})
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.4),
			NumberSequenceKeypoint.new(1, 1),
		})
	elseif preset == "Fire" then
		emitter.Texture = Assets.Textures.Fire
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.8),
			NumberSequenceKeypoint.new(1, 0.1),
		})
		emitter.Acceleration = Vector3.new(0, 3, 0)
	else
		emitter.Texture = Assets.Textures.Glow
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.2),
			NumberSequenceKeypoint.new(1, 0),
		})
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
	end
	emitter:AddTag("VFX")
	emitter.Parent = parent
	return emitter
end

function Build.billboard(parent: Instance, size: UDim2, offset: Vector3, maxDistance: number?): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Size = size
	gui.StudsOffsetWorldSpace = offset
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = maxDistance or 80
	gui.ResetOnSpawn = false
	gui.Parent = parent
	return gui
end

function Build.label(parent: Instance, text: string, color: Color3, size: UDim2?, position: UDim2?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = size or UDim2.fromScale(1, 1)
	label.Position = position or UDim2.fromScale(0, 0)
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.FontFace = Font.new(Assets.Fonts.UI, Enum.FontWeight.Heavy)
	label.TextStrokeTransparency = 0.4
	label.Parent = parent
	return label
end

return Build
