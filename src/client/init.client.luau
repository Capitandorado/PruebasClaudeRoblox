-- VOID FACTORY client entry point.

local Client = script

local Remote = require(Client.Core.Remote)
local Store = require(Client.Core.Store)
local App = require(Client.UI.App)
local Hud = require(Client.UI.Hud)
local Box = require(Client.Controllers.Box)
local Placement = require(Client.Controllers.Placement)
local WorldFX = require(Client.Controllers.WorldFX)
local Prompts = require(Client.Controllers.Prompts)
local Announcements = require(Client.Controllers.Announcements)
local FactoryView = require(Client.Controllers.FactoryView)
local Rewards = require(Client.Controllers.Rewards)
local Rescue = require(Client.Controllers.Rescue)
local Celebrate = require(Client.Controllers.Celebrate)

-- The store must listen before the remotes deliver the first (queued) state.
Store.start()
Remote.start()
App.start()

for _, window in Client.UI.Windows:GetChildren() do
	if window:IsA("ModuleScript") then
		App.registerWindow(require(window))
	end
end

Hud.start()
Placement.setHud(Hud)
Box.start()
Placement.start()
WorldFX.start()
Prompts.start()
Announcements.start()
FactoryView.start()
Rewards.start()
Rescue.start()
Celebrate.start()

App.WindowChanged:Connect(function()
	Placement.closePopup()
end)
