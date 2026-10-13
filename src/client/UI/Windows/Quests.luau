-- Active quests with progress and rewards, and the daily reward track.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Quests = require(Shared.Config.Quests)
local DailyConfig = require(Shared.Config.Daily)
local Format = require(Shared.Util.Format)
local Progression = require(Shared.Logic.Actions.Progression)
local Daily = require(Shared.Logic.Actions.Daily)

local Client = script.Parent.Parent.Parent
local Remote = require(Client.Core.Remote)
local Store = require(Client.Core.Store)
local Sound = require(Client.Core.Sound)
local Box = require(Client.Controllers.Box)
local Theme = require(script.Parent.Parent.Theme)
local C = require(script.Parent.Parent.Components)
local Widgets = require(script.Parent.Parent.Widgets)

local Colors = Theme.Colors

local function rewardText(reward: DailyConfig.Reward, eps: number): string
	local parts = {}
	if reward.crates > 0 then
		table.insert(parts, reward.crates .. (if reward.crates == 1 then " Crate" else " Crates"))
	end
	local energy = Daily.energyFor(reward, eps)
	if energy > 0 then
		table.insert(parts, "⚡" .. Format.number(energy))
	end
	return table.concat(parts, "\n+")
end

return {
	name = "Quests",
	title = "Quests",
	icon = "📜",
	size = Vector2.new(560, 460),
	build = function(content: Frame, app: any)
		local currentTab = "Quests"
		local questsPage = C.new("Frame", {
			Name = "QuestsPage",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, -40),
			Position = UDim2.fromOffset(0, 40),
			Parent = content,
		})
		local dailyPage = C.new("Frame", {
			Name = "DailyPage",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, -40),
			Position = UDim2.fromOffset(0, 40),
			Visible = false,
			Parent = content,
		})
		local list = C.new(
			"Frame",
			{ Name = "List", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -30), Parent = questsPage }
		)
		C.list(Enum.FillDirection.Vertical, 10).Parent = list
		local footer = C.text({
			Name = "Footer",
			Text = "",
			TextSize = 13,
			TextColor3 = Colors.TextDim,
			Size = UDim2.new(1, 0, 0, 24),
			Position = UDim2.new(0, 0, 1, -24),
			Parent = questsPage,
		})

		-- Daily page ---------------------------------------------------------------------
		local streakLabel = C.text({
			Name = "Streak",
			Text = "",
			FontFace = Theme.Fonts.Bold,
			TextSize = 20,
			Size = UDim2.new(1, 0, 0, 26),
			Parent = dailyPage,
		})
		local statusLabel = C.text({
			Name = "Status",
			Text = "",
			TextSize = 15,
			TextColor3 = Colors.TextDim,
			Size = UDim2.new(1, 0, 0, 22),
			Position = UDim2.fromOffset(0, 28),
			Parent = dailyPage,
		})
		local track = C.new("Frame", {
			Name = "Track",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 112),
			Position = UDim2.fromOffset(0, 60),
			Parent = dailyPage,
		})
		C.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center).Parent = track
		local claimButton = C.button({
			name = "ClaimDaily",
			text = "CLAIM",
			color = Colors.Good,
			textColor = Color3.fromRGB(10, 40, 20),
			size = UDim2.fromOffset(260, 50),
			anchor = Vector2.new(0.5, 0),
			position = UDim2.new(0.5, 0, 0, 186),
			textSize = 18,
			parent = dailyPage,
		})
		C.text({
			Name = "Info",
			Text = "Claim once per day (UTC) to grow your streak; missing a day restarts it at Day 1. "
				.. "Daily Crates hold Rare or better artifacts (odds in 📖 Collection → Odds).",
			TextSize = 13,
			TextColor3 = Colors.TextDim,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, -20, 0, 54),
			Position = UDim2.fromOffset(10, 248),
			Parent = dailyPage,
		})

		local dailySignature = ""
		local function refreshDaily(force: boolean?)
			local profile = Store.profile
			if not profile then
				return
			end
			local status = Daily.status(profile, Store.now())
			local eps = Store.production().total
			if status.available then
				statusLabel.Text = if status.streak == 1 and profile.daily.streak > 1
					then "Streak lost — starting again at Day 1. Today's reward is ready!"
					else "Today's reward is ready!"
				C.setButton(claimButton, "CLAIM DAY " .. status.index, true, Colors.Good)
			else
				statusLabel.Text = "Next reward in " .. Format.duration(status.nextIn)
				C.setButton(claimButton, "Come back tomorrow", false)
			end
			local current = if status.available then status.streak - 1 else status.streak
			streakLabel.Text = if current > 0
				then "🔥 " .. current .. "-day streak"
				else "🔥 Start your streak today!"
			local signature = table.concat({ tostring(status.available), status.index, Format.number(eps) }, "|")
			if signature == dailySignature and not force then
				return
			end
			dailySignature = signature
			C.clear(track, true)
			local claimedUpTo = if status.available then status.index - 1 else status.index
			for day, reward in DailyConfig.Rewards do
				local claimed = day <= claimedUpTo
				local today = status.available and day == status.index
				local tile = C.new("Frame", {
					Name = "Day" .. day,
					LayoutOrder = day,
					BackgroundColor3 = if today then Colors.CardHover else Colors.Card,
					BackgroundTransparency = if claimed then 0.4 else 0,
					Size = UDim2.fromOffset(70, 112),
					Children = {
						C.corner(Theme.SmallCorner),
						C.stroke(
							if today then Colors.Energy elseif claimed then Colors.Good else Colors.Stroke,
							if today then 2.5 else 1
						),
					},
					Parent = track,
				})
				C.text({
					Name = "Label",
					Text = "Day " .. day,
					TextSize = 12,
					TextColor3 = Colors.TextDim,
					TextXAlignment = Enum.TextXAlignment.Center,
					Size = UDim2.new(1, 0, 0, 16),
					Position = UDim2.fromOffset(0, 6),
					Parent = tile,
				})
				C.text({
					Name = "Icon",
					Text = if reward.crates > 0 then "🎁" else "⚡",
					TextSize = 26,
					TextXAlignment = Enum.TextXAlignment.Center,
					Size = UDim2.new(1, 0, 0, 32),
					Position = UDim2.fromOffset(0, 22),
					Parent = tile,
				})
				C.text({
					Name = "Amount",
					Text = rewardText(reward, eps),
					TextSize = 12,
					FontFace = Theme.Fonts.Bold,
					TextColor3 = if reward.crates > 0 then Color3.fromRGB(255, 200, 120) else Colors.Energy,
					TextXAlignment = Enum.TextXAlignment.Center,
					Size = UDim2.new(1, -6, 0, 32),
					Position = UDim2.fromOffset(3, 56),
					Parent = tile,
				})
				C.text({
					Name = "State",
					Text = if claimed then "✓" elseif today then "TODAY" else "",
					TextSize = 12,
					FontFace = Theme.Fonts.Bold,
					TextColor3 = if claimed then Colors.Good else Colors.Energy,
					TextXAlignment = Enum.TextXAlignment.Center,
					Size = UDim2.new(1, 0, 0, 16),
					Position = UDim2.new(0, 0, 1, -20),
					Parent = tile,
				})
			end
		end

		C.onClick(claimButton, function()
			local response = Remote.request("ClaimDaily")
			if not response.ok then
				app.showError(response.err)
				return
			end
			local data = response.data
			Sound.play("QuestComplete")
			local text = "Day " .. data.day .. " reward claimed!"
			if data.energy > 0 then
				text ..= " +⚡" .. Format.number(data.energy)
			end
			app.toast(text, "success")
			if type(data.results) == "table" and #data.results > 0 then
				app.closeWindow()
				Box.playResults(data.results)
			end
		end)

		local function refreshQuests()
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

		local function refresh()
			questsPage.Visible = currentTab == "Quests"
			dailyPage.Visible = currentTab == "Daily"
			if currentTab == "Quests" then
				refreshQuests()
			else
				refreshDaily(true)
			end
		end

		local selectTab = Widgets.tabs(content, { "Quests", "Daily" }, function(name)
			currentTab = name
			refresh()
		end)
		selectTab(currentTab)

		local watching = nil
		local open = false
		return {
			frame = content,
			refresh = refresh,
			onOpen = function(args: any)
				if type(args) == "table" and (args.tab == "Quests" or args.tab == "Daily") then
					currentTab = args.tab
					selectTab(currentTab)
				end
				watching = Store.watch({ "quests", "stats", "daily" }, function(changed)
					if currentTab == "Quests" then
						refreshQuests()
					elseif changed.daily or changed.all then
						refreshDaily(true)
					end
				end)
				open = true
				-- Countdown to the next daily reward.
				task.spawn(function()
					while open do
						if currentTab == "Daily" then
							refreshDaily()
						end
						task.wait(1)
					end
				end)
			end,
			onClose = function()
				open = false
				if watching then
					watching:Disconnect()
					watching = nil
				end
			end,
		}
	end,
}
