-- Puts the local character back on its plot when it falls into the void. The client owns
-- its character's physics, so only it can also cancel the fall speed; the server's rescue
-- (Services/World) remains as a fallback a little lower.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PlotConfig = require(Shared.Config.Plot)

local Client = script.Parent.Parent
local Store = require(Client.Core.Store)

local Rescue = {}

Rescue.Level = PlotConfig.VoidLevel + PlotConfig.ClientRescueMargin

-- Where to land: the spawn pad of our own plot, facing the pedestals (or the hub).
function Rescue.target(): CFrame?
	local root = workspace:FindFirstChild("VoidFactory")
	local plots = root and root:FindFirstChild("Plots")
	local plot = plots and plots:FindFirstChild("Plot_" .. Store.plot)
	local pad = plot and plot:FindFirstChild("Spawn")
	if pad and pad:IsA("BasePart") then
		return pad.CFrame * CFrame.new(0, 4, 0) * CFrame.Angles(0, math.pi, 0)
	end
	local hub = root and root:FindFirstChild("Hub")
	local spawn = hub and hub:FindFirstChildWhichIsA("SpawnLocation")
	return if spawn then spawn.CFrame * CFrame.new(0, 4, 0) else nil
end

function Rescue.check()
	local character = Players.LocalPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") or rootPart.Position.Y >= Rescue.Level then
		return
	end
	local target = Rescue.target()
	if target then
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero
		character:PivotTo(target)
	end
end

function Rescue.start()
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= 0.2 then
			elapsed = 0
			Rescue.check()
		end
	end)
end

return Rescue
