-- Client-side world animation: floating artifacts, spinning rings, rainbow/corrupted
-- mutations, Void Surge ambience and the "reduce effects" switch. Everything here is local
-- and cosmetic; it runs in a single RenderStepped connection with distance culling.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local Client = script.Parent.Parent
local Store = require(Client.Core.Store)
local Remote = require(Client.Core.Remote)
local Sound = require(Client.Core.Sound)
local App = require(Client.UI.App)

local WorldFX = {}

local ANIMATE_DISTANCE = 140
local MAX_ANIMATED = 60

type Floating = { model: Model, base: CFrame, phase: number }

local floating: { [Model]: Floating } = {}
local spinners: { [Model]: CFrame } = {}
local reduced = false

local function trackFloating(model: Instance)
	if model:IsA("Model") and not floating[model] then
		floating[model] = { model = model, base = model:GetPivot(), phase = math.random() * math.pi * 2 }
	end
end

local function trackSpinner(model: Instance)
	if model:IsA("Model") and not spinners[model] then
		spinners[model] = model:GetPivot()
	end
end

local function setVfx(enabled: boolean)
	for _, emitter in CollectionService:GetTagged("VFX") do
		if emitter:IsA("ParticleEmitter") then
			emitter.Enabled = enabled
		end
	end
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	if bloom then
		bloom.Intensity = if enabled then 0.7 else 0.3
	end
end

local function applySettings()
	local profile = Store.profile
	local nowReduced = profile ~= nil and profile.settings.reducedEffects == true
	if nowReduced ~= reduced then
		reduced = nowReduced
		setVfx(not reduced)
	end
end

local surgeTint: ColorCorrectionEffect? = nil

local function updateSurge()
	local surging = Store.isSurging()
	if surging and not surgeTint then
		local tint = Instance.new("ColorCorrectionEffect")
		tint.Name = "SurgeTint"
		tint.TintColor = Color3.fromRGB(230, 200, 255)
		tint.Saturation = 0.3
		tint.Parent = Lighting
		surgeTint = tint
	elseif not surging and surgeTint then
		surgeTint:Destroy()
		surgeTint = nil
	end
end

function WorldFX.start()
	for _, model in CollectionService:GetTagged("FloatingArtifact") do
		trackFloating(model)
	end
	CollectionService:GetInstanceAddedSignal("FloatingArtifact"):Connect(trackFloating)
	CollectionService:GetInstanceRemovedSignal("FloatingArtifact"):Connect(function(model)
		floating[model :: Model] = nil
	end)
	for _, model in CollectionService:GetTagged("Spinner") do
		trackSpinner(model)
	end
	CollectionService:GetInstanceAddedSignal("Spinner"):Connect(trackSpinner)
	CollectionService:GetInstanceAddedSignal("VFX"):Connect(function(emitter)
		if reduced and emitter:IsA("ParticleEmitter") then
			emitter.Enabled = false
		end
	end)
	Store.watch({ "settings" }, applySettings)
	Store.watch({ "runtime" }, updateSurge)

	Remote.NotifyReceived:Connect(function(kind, payload)
		if kind == "Surge" and type(payload) == "table" then
			if payload.active then
				App.toast("🌀 VOID SURGE! Production multiplied and boxes recharged!", "success")
				Sound.play("RevealVoid")
			end
		elseif kind == "Toast" and type(payload) == "table" and type(payload.text) == "string" then
			App.toast(payload.text, payload.kind)
		end
	end)

	local clock = 0
	local hueClock = 0
	RunService.RenderStepped:Connect(function(dt)
		clock += dt
		local camera = workspace.CurrentCamera
		local cameraPosition = if camera then camera.CFrame.Position else Vector3.zero
		for model, base in spinners do
			if not model.Parent then
				spinners[model] = nil
				continue
			end
			local speed = (model:GetAttribute("SpinSpeed") or 20) :: number
			model:PivotTo(base * CFrame.Angles(0, math.rad(clock * speed), 0))
		end
		if reduced then
			return
		end
		local animated = 0
		for model, entry in floating do
			if not model.Parent then
				floating[model] = nil
				continue
			end
			if animated >= MAX_ANIMATED then
				break
			end
			if (entry.base.Position - cameraPosition).Magnitude < ANIMATE_DISTANCE then
				animated += 1
				local bob = math.sin(clock * 1.6 + entry.phase) * 0.35
				model:PivotTo(entry.base * CFrame.new(0, bob, 0) * CFrame.Angles(0, clock * 0.8 + entry.phase, 0))
			end
		end
		hueClock += dt
		if hueClock > 0.05 then
			hueClock = 0
			local hue = (clock * 0.25) % 1
			for _, part in CollectionService:GetTagged("RainbowMutation") do
				if part:IsA("BasePart") then
					part.Color = Color3.fromHSV((hue + part.Position.Y * 0.05) % 1, 0.85, 1)
				end
			end
			for _, part in CollectionService:GetTagged("CorruptedMutation") do
				if part:IsA("BasePart") then
					part.Transparency = if math.random() < 0.06 then 0.6 else 0
				end
			end
		end
	end)
end

return WorldFX
