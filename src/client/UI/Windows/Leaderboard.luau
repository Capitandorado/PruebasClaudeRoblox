-- Leaderboards (this server and global) with factory visits.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Util.Format)

local Client = script.Parent.Parent.Parent
local Remote = require(Client.Core.Remote)
local Sound = require(Client.Core.Sound)
local Theme = require(script.Parent.Parent.Theme)
local C = require(script.Parent.Parent.Components)
local Widgets = require(script.Parent.Parent.Widgets)

local Colors = Theme.Colors

return {
	name = "Leaderboard",
	title = "Leaderboards",
	icon = "🏆",
	size = Vector2.new(600, 460),
	build = function(content: Frame, app: any)
		local currentTab = "Server"
		local snapshot: any = nil
		local list = C.scroll({
			Name = "List",
			Size = UDim2.new(1, 0, 1, -42),
			Position = UDim2.fromOffset(0, 42),
			Parent = content,
		})
		C.list(Enum.FillDirection.Vertical, 4).Parent = list

		local function header(order: number, columns: { string })
			local frame = C.new("Frame", {
				Name = "Header",
				LayoutOrder = order,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, -8, 0, 22),
				Parent = list,
			})
			local widths = { 0.08, 0.36, 0.2, 0.18, 0.18 }
			local x = 0
			for index, text in columns do
				C.text({
					Text = text,
					TextSize = 12,
					TextColor3 = Colors.TextDim,
					Size = UDim2.new(widths[index], 0, 1, 0),
					Position = UDim2.fromScale(x, 0),
					Parent = frame,
				})
				x += widths[index]
			end
		end

		local function renderServer()
			header(0, { "#", "Player", "⚡/s", "Found", "" })
			local localId = Players.LocalPlayer.UserId
			for rank, entry in snapshot.server do
				local row = C.new("Frame", {
					Name = "Row" .. rank,
					LayoutOrder = rank,
					BackgroundColor3 = if entry.userId == localId then Colors.CardHover else Colors.Card,
					Size = UDim2.new(1, -8, 0, 40),
					Children = { C.corner(6) },
					Parent = list,
				})
				C.text({
					Text = tostring(rank),
					FontFace = Theme.Fonts.Bold,
					TextSize = 16,
					Size = UDim2.new(0.08, 0, 1, 0),
					Position = UDim2.fromOffset(8, 0),
					Parent = row,
				})
				C.text({
					Text = entry.name .. (if entry.rebirths > 0 then "  ♻" .. entry.rebirths else ""),
					TextSize = 15,
					Size = UDim2.new(0.36, 0, 1, 0),
					Position = UDim2.fromScale(0.08, 0),
					Parent = row,
				})
				C.text({
					Text = Format.number(entry.eps),
					TextSize = 15,
					TextColor3 = Colors.Energy,
					Size = UDim2.new(0.2, 0, 1, 0),
					Position = UDim2.fromScale(0.44, 0),
					Parent = row,
				})
				C.text({
					Text = entry.discoveries .. "/" .. snapshot.totalArtifacts,
					TextSize = 15,
					Size = UDim2.new(0.18, 0, 1, 0),
					Position = UDim2.fromScale(0.64, 0),
					Parent = row,
				})
				if entry.userId ~= localId then
					C.button({
						name = "Visit",
						text = "Visit",
						color = Colors.Accent,
						textColor = Color3.fromRGB(10, 20, 40),
						size = UDim2.fromOffset(80, 30),
						position = UDim2.new(1, -88, 0.5, -15),
						textSize = 14,
						parent = row,
						onClick = function()
							local response = Remote.request("Visit", entry.userId)
							if response.ok then
								Sound.play("UIClick")
								app.toast(
									"Visiting " .. response.data.name .. "'s factory. Use 🏠 to go back.",
									"info"
								)
								app.VisitChanged:Fire(response.data.name)
								app.closeWindow()
							else
								app.showError(response.err)
							end
						end,
					})
				end
			end
		end

		local function renderGlobal()
			local global = snapshot.global
			if not global then
				C.text({
					Name = "Unavailable",
					Text = "Global leaderboards are loading or unavailable (they need a published game with API services).",
					TextSize = 14,
					TextColor3 = Colors.TextDim,
					Size = UDim2.new(1, -8, 0, 60),
					Parent = list,
				})
				return
			end
			local order = 0
			for _, board in global do
				order += 1
				C.text({
					Name = board.id,
					Text = board.title,
					FontFace = Theme.Fonts.Bold,
					TextSize = 16,
					TextColor3 = Colors.Accent,
					LayoutOrder = order,
					Size = UDim2.new(1, -8, 0, 26),
					Parent = list,
				})
				for rank, entry in board.entries do
					order += 1
					local row = C.new("Frame", {
						Name = board.id .. rank,
						LayoutOrder = order,
						BackgroundColor3 = Colors.Card,
						Size = UDim2.new(1, -8, 0, 30),
						Children = { C.corner(6) },
						Parent = list,
					})
					C.text({
						Text = rank .. ".  " .. entry.name,
						TextSize = 14,
						Size = UDim2.new(0.6, 0, 1, 0),
						Position = UDim2.fromOffset(10, 0),
						Parent = row,
					})
					C.text({
						Text = entry.display,
						TextSize = 14,
						TextColor3 = Colors.Energy,
						TextXAlignment = Enum.TextXAlignment.Right,
						Size = UDim2.new(0.4, -14, 1, 0),
						Position = UDim2.fromScale(0.6, 0),
						Parent = row,
					})
				end
			end
		end

		local function render()
			C.clear(list, true)
			if not snapshot then
				C.text({ Name = "Loading", Text = "Loading...", TextColor3 = Colors.TextDim, Parent = list })
				return
			end
			if currentTab == "Server" then
				renderServer()
			else
				renderGlobal()
			end
		end

		local function refresh()
			local response = Remote.request("GetLeaderboard")
			if response.ok then
				snapshot = response.data
			end
			render()
		end

		local selectTab = Widgets.tabs(content, { "Server", "Global" }, function(name)
			currentTab = name
			render()
		end)
		selectTab(currentTab)

		return { frame = content, refresh = refresh }
	end,
}
