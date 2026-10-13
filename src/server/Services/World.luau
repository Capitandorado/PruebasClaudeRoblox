-- Builds the shared world: space lighting, the central hub island, bridges to every plot,
-- and rescues players who fall into the void.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Build = require(Shared.Util.Build)
local PlotConfig = require(Shared.Config.Plot)
local Assets = require(Shared.Config.Assets)

local World = {}

World.HubRadius = 40
World.VoidLevel = -60

local root: Folder = nil :: any

local NEON_CYAN = Color3.fromRGB(80, 220, 255)
local NEON_VIOLET = Color3.fromRGB(170, 90, 255)
local FLOOR = Color3.fromRGB(28, 26, 44)

function World.folder(): Folder
	return root
end

local function setupLighting()
	Lighting.ClockTime = 0
	Lighting.Brightness = 1.5
	Lighting.Ambient = Color3.fromRGB(46, 36, 82)
	Lighting.OutdoorAmbient = Color3.fromRGB(70, 56, 120)
	Lighting.EnvironmentDiffuseScale = 0.4
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.GlobalShadows = true
	Lighting.ExposureCompensation = 0.2

	local sky = Instance.new("Sky")
	sky.Name = "VoidSky"
	sky.StarCount = 5000
	sky.CelestialBodiesShown = false
	sky.Parent = Lighting

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.1
	atmosphere.Color = Color3.fromRGB(110, 80, 170)
	atmosphere.Decay = Color3.fromRGB(30, 14, 70)
	atmosphere.Glare = 0
	atmosphere.Haze = 1.5
	atmosphere.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.7
	bloom.Size = 28
	bloom.Threshold = 1.2
	bloom.Parent = Lighting

	local grading = Instance.new("ColorCorrectionEffect")
	grading.Name = "Grading"
	grading.Saturation = 0.15
	grading.Contrast = 0.08
	grading.TintColor = Color3.fromRGB(245, 240, 255)
	grading.Parent = Lighting
end

local function buildHub(parent: Instance)
	local hub = Build.model("Hub", parent)
	Build.cylinder({
		Name = "Island",
		Height = 6,
		Diameter = World.HubRadius * 2,
		CFrame = CFrame.new(0, -3, 0),
		Color = FLOOR,
		Material = Enum.Material.Slate,
		CanCollide = true,
		CastShadow = true,
		Parent = hub,
	})
	Build.ring(hub, CFrame.new(0, 0.05, 0), World.HubRadius - 0.6, 0.6, 48, NEON_CYAN)
	Build.ring(hub, CFrame.new(0, 0.05, 0), World.HubRadius * 0.55, 0.4, 36, NEON_VIOLET)
	-- Inverted crystal "roots" under the island.
	for index = 1, 7 do
		local angle = index / 7 * math.pi * 2
		local radius = 12 + (index % 3) * 8
		local height = 18 + (index % 4) * 6
		Build.part({
			Name = "Root",
			Size = Vector3.new(6, height, 6),
			CFrame = CFrame.new(math.cos(angle) * radius, -6 - height / 2, math.sin(angle) * radius)
				* CFrame.Angles(math.rad(8), angle, math.rad(6)),
			Color = Color3.fromRGB(40, 30, 70),
			Material = Enum.Material.Basalt,
			Parent = hub,
		})
	end
	-- Floating core with spinning rings (the client animates parts tagged "Spinner").
	local core = Build.part({
		Name = "Core",
		Size = Vector3.new(6, 9, 6),
		CFrame = CFrame.new(0, 14, 0) * CFrame.Angles(0, math.rad(45), 0),
		Color = NEON_VIOLET,
		Material = Enum.Material.Neon,
		Parent = hub,
	})
	Build.light(core, NEON_VIOLET, 3, 40)
	Build.particles(core, "Glow", NEON_VIOLET, 5)
	for index, radius in { 7, 9.5 } do
		local ringModel = Build.model("CoreRing" .. index, hub)
		Build.root(ringModel, CFrame.new(0, 14, 0))
		Build.ring(
			ringModel,
			CFrame.new(0, 14, 0) * CFrame.Angles(math.rad(20 * index), 0, 0),
			radius,
			0.4,
			28,
			if index == 1 then NEON_CYAN else NEON_VIOLET
		)
		ringModel:AddTag("Spinner")
		ringModel:SetAttribute("SpinSpeed", if index == 1 then 25 else -18)
	end
	Build.part({
		Name = "Pedestal",
		Size = Vector3.new(10, 2, 10),
		CFrame = CFrame.new(0, 1, 0),
		Color = Color3.fromRGB(45, 40, 70),
		Material = Enum.Material.Metal,
		CanCollide = true,
		Parent = hub,
	})
	local titleAnchor = Build.part({
		Name = "TitleAnchor",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(0, 24, 0),
		Transparency = 1,
		Parent = hub,
	})
	local title = Build.billboard(titleAnchor, UDim2.fromOffset(600, 140), Vector3.zero, 600)
	title.Name = "Title"
	local titleLabel = Build.label(title, "VOID FACTORY", Color3.fromRGB(235, 225, 255))
	titleLabel.FontFace = Font.new(Assets.Fonts.Display, Enum.FontWeight.Regular)
	local stroke = Instance.new("UIStroke")
	stroke.Color = NEON_VIOLET
	stroke.Thickness = 3
	stroke.Parent = titleLabel

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HubSpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.CFrame = CFrame.new(0, 0.5, World.HubRadius - 10)
	spawn.Color = NEON_CYAN
	spawn.Material = Enum.Material.Neon
	spawn.Transparency = 0.4
	spawn.CanCollide = false
	spawn.Parent = hub
	return hub
end

-- Glass walkway from the hub edge to the front of plot `index`.
local function buildBridge(parent: Instance, plotCFrame: CFrame, plotDepth: number)
	local frontCenter = plotCFrame * CFrame.new(0, 0, -plotDepth / 2)
	local direction = Vector3.new(frontCenter.Position.X, 0, frontCenter.Position.Z).Unit
	local startPoint = direction * (World.HubRadius - 1)
	local endPoint = frontCenter.Position
	local length = (endPoint - startPoint).Magnitude
	local center = (startPoint + endPoint) / 2
	local bridgeFrame = CFrame.lookAt(center, endPoint)
	local bridge = Build.model("Bridge", parent)
	Build.part({
		Name = "Deck",
		Size = Vector3.new(8, 1, length),
		CFrame = bridgeFrame * CFrame.new(0, -0.5, 0),
		Color = Color3.fromRGB(120, 200, 255),
		Material = Enum.Material.Glass,
		Transparency = 0.35,
		CanCollide = true,
		Parent = bridge,
	})
	for _, side in { -1, 1 } do
		Build.part({
			Name = "Rail",
			Size = Vector3.new(0.3, 0.3, length),
			CFrame = bridgeFrame * CFrame.new(side * 4, 0.6, 0),
			Color = NEON_CYAN,
			Material = Enum.Material.Neon,
			Parent = bridge,
		})
		local wall = Build.part({
			Name = "Guard",
			Size = Vector3.new(0.4, 3, length),
			CFrame = bridgeFrame * CFrame.new(side * 4, 1.5, 0),
			Transparency = 1,
			CanCollide = true,
			Parent = bridge,
		})
		wall.CanQuery = false
	end
	return bridge
end

-- CFrame of plot `index` (origin at the platform top centre, -Z facing the hub).
function World.plotCFrame(index: number): CFrame
	local angle = (index - 1) / PlotConfig.MaxPlots * math.pi * 2
	local position = Vector3.new(math.sin(angle) * PlotConfig.PlotRadius, 0, math.cos(angle) * PlotConfig.PlotRadius)
	return CFrame.lookAt(position, Vector3.new(0, 0, 0))
end

function World.hubSpawn(): CFrame
	return CFrame.new(0, 4, World.HubRadius - 10)
end

local rescueCallback: ((player: Player) -> CFrame?)? = nil

-- Plots registers a callback that returns where a falling player should be put back.
function World.setRescueTarget(callback: (player: Player) -> CFrame?)
	rescueCallback = callback
end

local function rescueLoop()
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.5 then
			return
		end
		elapsed = 0
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			if rootPart and rootPart:IsA("BasePart") and rootPart.Position.Y < World.VoidLevel then
				local target = (rescueCallback and rescueCallback(player)) or World.hubSpawn()
				rootPart.AssemblyLinearVelocity = Vector3.zero
				character:PivotTo(target)
			end
		end
	end)
end

function World.init()
	setupLighting()
	root = Instance.new("Folder")
	root.Name = "VoidFactory"
	root.Parent = workspace
	local plots = Instance.new("Folder")
	plots.Name = "Plots"
	plots.Parent = root
	buildHub(root)
	local bridges = Instance.new("Folder")
	bridges.Name = "Bridges"
	bridges.Parent = root
	for index = 1, PlotConfig.MaxPlots do
		buildBridge(bridges, World.plotCFrame(index), World.PlotDepth)
	end
end

function World.start()
	rescueLoop()
end

World.PlotWidth = 80
World.PlotDepth = 68

return World
