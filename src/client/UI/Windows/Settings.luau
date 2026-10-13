-- Player settings (saved with the profile).

local Client = script.Parent.Parent.Parent
local Remote = require(Client.Core.Remote)
local Store = require(Client.Core.Store)
local Theme = require(script.Parent.Parent.Theme)
local C = require(script.Parent.Parent.Components)

local Colors = Theme.Colors

return {
	name = "Settings",
	title = "Settings",
	icon = "⚙️",
	size = Vector2.new(460, 360),
	build = function(content: Frame, app: any)
		local list = C.new(
			"Frame",
			{ Name = "List", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = content }
		)
		C.list(Enum.FillDirection.Vertical, 8).Parent = list
		local setters = {}
		local function setting(order: number, name: string, label: string)
			local profile = Store.profile
			local row, set = C.toggle(label, profile ~= nil and profile.settings[name] == true, function(value)
				local response = Remote.request("SetSetting", name, value)
				if not response.ok then
					app.showError(response.err)
				end
			end)
			row.Name = name
			row.LayoutOrder = order
			row.Parent = list
			setters[name] = set
		end
		setting(1, "sfx", "Sound effects")
		setting(2, "reducedEffects", "Reduce visual effects (better on low-end devices)")
		C.text({
			Name = "Help",
			LayoutOrder = 3,
			Text = "Tip: tap a pedestal to inspect or change it. Use AUTO to keep opening boxes. Visit other factories from the leaderboard.",
			TextSize = 14,
			TextColor3 = Colors.TextDim,
			Size = UDim2.new(1, 0, 0, 60),
			Parent = list,
		})
		C.text({
			Name = "Version",
			LayoutOrder = 4,
			Text = "VOID FACTORY v1.0",
			TextSize = 12,
			TextColor3 = Colors.TextDim,
			Parent = list,
		})

		local watching = nil
		return {
			frame = content,
			refresh = function()
				local profile = Store.profile
				if profile then
					for name, set in setters do
						set(profile.settings[name] == true)
					end
				end
			end,
			onOpen = function()
				watching = Store.watch({ "settings" }, function()
					local profile = Store.profile
					for name, set in setters do
						set(profile.settings[name] == true)
					end
				end)
			end,
			onClose = function()
				if watching then
					watching:Disconnect()
					watching = nil
				end
			end,
		}
	end,
}
