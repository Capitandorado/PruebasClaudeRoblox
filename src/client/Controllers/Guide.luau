-- Visual pointers for the current goal (UI/Goals): a pulsing golden ring around the HUD
-- button to press and, while the first artifact waits to be placed, a bouncing arrow over
-- an empty pedestal of your plot.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PlotConfig = require(Shared.Config.Plot)

local Client = script.Parent.Parent
local Store = require(Client.Core.Store)
local App = require(Client.UI.App)
local Hud = require(Client.UI.Hud)
local Goals = require(Client.UI.Goals)
local Theme = require(Client.UI.Theme)
local C = require(Client.UI.Components)

local Guide = {}

local GOLD = Color3.fromRGB(255, 214, 70)

local glow: Frame? = nil
local arrow: BillboardGui? = nil
local arrowSlot: number? = nil

function Guide.highlight(name: string?)
	local current = glow
	if current and current.Parent and name and current.Parent.Name == name then
		return
	end
	if current then
		current:Destroy()
		glow = nil
	end
	local gui = App.gui
	local target = name and gui and gui:FindFirstChild(name, true)
	if not target or not target:IsA("GuiObject") then
		return
	end
	local ring = C.new("Frame", {
		Name = "GuideGlow",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 10, 1, 10),
		Position = UDim2.fromOffset(-5, -5),
		ZIndex = target.ZIndex + 2,
		Children = { C.corner(Theme.Corner) },
		Parent = target,
	})
	local stroke = C.new("UIStroke", { Color = GOLD, Thickness = 3, Transparency = 0, Parent = ring })
	TweenService:Create(
		stroke,
		TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Transparency = 0.75, Thickness = 1.5 }
	):Play()
	glow = ring
end

local function emptyPedestal(): BasePart?
	local profile = Store.profile
	local root = workspace:FindFirstChild("VoidFactory")
	local plots = root and root:FindFirstChild("Plots")
	local plot = plots and plots:FindFirstChild("Plot_" .. Store.plot)
	local slots = plot and plot:FindFirstChild("Slots")
	if not profile or not slots then
		return nil
	end
	for _, slot in PlotConfig.unlockedSlots(profile.expansion) do
		if not profile.placed[tostring(slot)] then
			local pedestal = slots:FindFirstChild("Slot_" .. slot)
			local hitbox = pedestal and pedestal:FindFirstChild("Hitbox")
			if hitbox and hitbox:IsA("BasePart") then
				arrowSlot = slot
				return hitbox
			end
		end
	end
	return nil
end

function Guide.pointAtPedestal(enabled: boolean)
	if not enabled then
		if arrow then
			arrow:Destroy()
			arrow = nil
		end
		return
	end
	local target = emptyPedestal()
	if not target then
		return
	end
	if arrow and arrow.Adornee == target then
		return
	end
	if arrow then
		arrow:Destroy()
	end
	local gui = C.new("BillboardGui", {
		Name = "GuideArrow",
		Adornee = target,
		Size = UDim2.fromScale(4, 4),
		StudsOffsetWorldSpace = Vector3.new(0, 7, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 200,
		ResetOnSpawn = false,
		Parent = workspace,
	})
	C.text({
		Name = "Arrow",
		Text = "⬇",
		TextScaled = true,
		TextColor3 = GOLD,
		TextStrokeTransparency = 0,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	})
	TweenService:Create(
		gui,
		TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ StudsOffsetWorldSpace = Vector3.new(0, 5.5, 0) }
	):Play()
	arrow = gui
end

-- The pedestal the arrow points at (tests).
function Guide.arrowSlot(): number?
	return if arrow then arrowSlot else nil
end

local function refresh()
	local goal = Goals.current(Store.profile, Store.now())
	Guide.highlight(goal and goal.highlight)
	Guide.pointAtPedestal(goal ~= nil and goal.arrow == true)
end

function Guide.start()
	Hud.GoalChanged:Connect(refresh)
	Store.watch({ "placed", "expansion", "inventory", "energy" }, refresh)
end

return Guide
