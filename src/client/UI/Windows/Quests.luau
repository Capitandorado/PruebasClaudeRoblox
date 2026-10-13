-- Active quests with progress and rewards.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Quests = require(Shared.Config.Quests)
local Format = require(Shared.Util.Format)
local Progression = require(Shared.Logic.Actions.Progression)

local Client = script.Parent.Parent.Parent
local Remote = require(Client.Core.Remote)
local Store = require(Client.Core.Store)
local Sound = require(Client.Core.Sound)
local Theme = require(script.Parent.Parent.Theme)
local C = require(script.Parent.Parent.Components)

local Colors = Theme.Colors

return {
	name = "Quests",
	title = "Quests",
	icon = "📜",
	size = Vector2.new(540, 400),
	build = function(content: Frame, app: any)
		local list = C.new(
			"Frame",
			{ Name = "List", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -30), Parent = content }
		)
		C.list(Enum.FillDirection.Vertical, 10).Parent = list
		local footer = C.text({
			Name = "Footer",
			Text = "",
			TextSize = 13,
			TextColor3 = Colors.TextDim,
			Size = UDim2.new(1, 0, 0, 24),
			Position = UDim2.new(0, 0, 1, -24),
			Parent = content,
		})

		local function refresh()
			local profile = Store.profile
			if not profile then
				return
			end
			C.clear(list, true)
			local eps = Store.production().total
			for index, questState in profile.quests.active do
				local def = Quests.ById[questState.id]
				if not def then
					continue
				end
				local progress = Progression.questProgress(profile, questState)
				local done = progress >= questState.target
				local card = C.new("Frame", {
					Name = "Quest" .. index,
					LayoutOrder = index,
					BackgroundColor3 = Colors.Card,
					Size = UDim2.new(1, -4, 0, 96),
					Children = {
						C.corner(Theme.SmallCorner),
						C.stroke(if done then Colors.Good else Colors.Stroke),
					},
					Parent = list,
				})
				C.padding(10).Parent = card
				local targetText = if def.stat == "energyEarned"
					then Format.number(questState.target)
					else tostring(questState.target)
				C.text({
					Name = "Text",
					Text = string.format(def.text, targetText),
					FontFace = Theme.Fonts.Bold,
					TextSize = 16,
					TextTruncate = Enum.TextTruncate.AtEnd,
					Size = UDim2.new(1, -150, 0, 22),
					Parent = card,
				})
				C.text({
					Name = "Reward",
					Text = "Reward: ⚡ " .. Format.number(Progression.questReward(profile, questState.id, eps)),
					TextSize = 14,
					TextColor3 = Colors.Energy,
					Size = UDim2.new(1, -150, 0, 20),
					Position = UDim2.fromOffset(0, 26),
					Parent = card,
				})
				local _, setBar =
					C.progress({ Size = UDim2.new(1, -150, 0, 12), Position = UDim2.new(0, 0, 1, -16), Parent = card })
				setBar(progress / questState.target, if done then Colors.Good else Colors.Accent)
				C.text({
					Name = "Progress",
					Text = Format.number(math.min(progress, questState.target)) .. " / " .. Format.number(
						questState.target
					),
					TextSize = 12,
					TextColor3 = Colors.TextDim,
					Size = UDim2.new(1, -150, 0, 16),
					Position = UDim2.new(0, 0, 1, -34),
					Parent = card,
				})
				local claim = C.button({
					name = "Claim",
					text = if done then "CLAIM" else "In progress",
					color = if done then Colors.Good else Colors.PanelLight,
					textColor = if done then Color3.fromRGB(10, 40, 20) else Colors.TextDim,
					size = UDim2.fromOffset(130, 44),
					position = UDim2.new(1, -130, 0.5, -22),
					textSize = 16,
					parent = card,
				})
				C.setButton(claim, nil, done)
				C.onClick(claim, function()
					local response = Remote.request("ClaimQuest", index)
					if response.ok then
						Sound.play("QuestComplete")
						app.toast("Quest complete! +⚡" .. Format.number(response.data.reward), "success")
					else
						app.showError(response.err)
					end
				end)
			end
			footer.Text = "Quests completed: "
				.. profile.quests.completed
				.. "   •   Rewards scale with your production."
		end

		local watching = nil
		return {
			frame = content,
			refresh = refresh,
			onOpen = function()
				watching = Store.watch({ "quests", "stats" }, refresh)
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
