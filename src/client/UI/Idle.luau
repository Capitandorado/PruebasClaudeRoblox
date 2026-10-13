-- Idle animations that keep the main buttons "breathing": a slow, endless scale pulse and,
-- every few seconds, a band of light sweeping across them (the Glint frame that
-- C.candyButton creates). Both stop while "reduced effects" is on; the glint also waits
-- while the button is disabled, so it only calls attention to things you can do.
--
-- The pulse uses its own UIScale on the button's holder frame. A GuiObject applies only one
-- UIScale, so the press/hover UIScale lives on the button itself and the two multiply.

local Client = script.Parent.Parent
local Store = require(Client.Core.Store)
local C = require(script.Parent.Components)

local Idle = {}

local function reduced(): boolean
	return Store.profile ~= nil and Store.profile.settings.reducedEffects == true
end

-- Scales `target` between 1 and 1 + amount forever (until it is destroyed).
function Idle.breathe(target: GuiObject, amount: number?, period: number?): UIScale
	local scale = C.new("UIScale", { Name = "Breathe", Parent = target })
	local size = amount or 0.05
	local half = (period or 1.6) / 2
	task.spawn(function()
		while target.Parent do
			if reduced() then
				scale.Scale = 1
				task.wait(0.5)
			else
				C.tween(scale, half, { Scale = 1 + size }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
				task.wait(half)
				C.tween(scale, half, { Scale = 1 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
				task.wait(half)
			end
		end
	end)
	return scale
end

-- Sweeps the button's Glint once (left to right).
function Idle.shine(button: GuiObject)
	local glint = button:FindFirstChild("Glint")
	local gradient = glint and glint:FindFirstChildOfClass("UIGradient")
	if not gradient then
		return
	end
	gradient.Offset = Vector2.new(-1, 0)
	C.tween(gradient, 0.65, { Offset = Vector2.new(1, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
end

-- Shines every `minGap`..`maxGap` seconds while the button is usable.
function Idle.glint(button: GuiObject, minGap: number?, maxGap: number?)
	local random = Random.new()
	task.spawn(function()
		while button.Parent do
			task.wait(random:NextNumber(minGap or 3.5, maxGap or 6.5))
			if button.Parent and not reduced() and button:GetAttribute("Disabled") ~= true then
				Idle.shine(button)
			end
		end
	end)
end

return Idle
