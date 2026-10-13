-- Debug panel (Studio / owner only; the server re-checks permissions on every command).

local Client = script.Parent.Parent.Parent
local Remote = require(Client.Core.Remote)
local Theme = require(script.Parent.Parent.Theme)
local C = require(script.Parent.Parent.Components)

local Colors = Theme.Colors

local COMMANDS = {
	{ "+1K Energy", "energy", 1000 },
	{ "+100K Energy", "energy", 100000 },
	{ "+10M Energy", "energy", 1e7 },
	{ "+1B Energy", "energy", 1e9 },
	{ "+5 Shards", "shards", 5 },
	{ "Warp 10 min", "warp", 600 },
	{ "Warp 1 hour", "warp", 3600 },
	{ "Fill boxes", "charges", true },
	{ "Give 1 of each", "giveAll", true },
	{ "Give Anomaly", "give", "the_anomaly||1" },
	{ "Give Rainbow Nucleus", "give", "void_nucleus|Rainbow|1" },
	{ "Reset my data", "reset", true },
}

return {
	name = "Admin",
	title = "Debug tools",
	icon = "🛠️",
	size = Vector2.new(520, 380),
	build = function(content: Frame, app: any)
		local grid = C.new(
			"Frame",
			{ Name = "Grid", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -40), Parent = content }
		)
		C.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(156, 44),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = grid,
		})
		local output = C.text({
			Name = "Output",
			Text = "Commands run on the server and are validated there.",
			TextSize = 13,
			TextColor3 = Colors.TextDim,
			Size = UDim2.new(1, 0, 0, 34),
			Position = UDim2.new(0, 0, 1, -34),
			Parent = content,
		})
		for order, command in COMMANDS do
			C.button({
				name = command[2] .. order,
				text = command[1],
				color = if command[2] == "reset" then Colors.Bad else Colors.PanelLight,
				size = UDim2.fromOffset(156, 44),
				textSize = 14,
				layoutOrder = order,
				parent = grid,
				onClick = function()
					local response = Remote.request("Admin", command[2], command[3])
					if response.ok then
						output.Text = "OK: " .. command[1]
						if command[2] == "warp" then
							output.Text ..= string.format(" (+%.0f Energy)", response.data.gained)
						end
					else
						app.showError(response.err)
						output.Text = "Failed: " .. tostring(response.err)
					end
				end,
			})
		end
		return { frame = content }
	end,
}
