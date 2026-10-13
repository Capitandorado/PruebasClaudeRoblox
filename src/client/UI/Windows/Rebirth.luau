-- Rebirth (reset for permanent bonuses) and the Void Shard perk shop.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rebirth = require(Shared.Config.Rebirth)
local Format = require(Shared.Util.Format)
local State = require(Shared.Logic.State)

local Client = script.Parent.Parent.Parent
local Remote = require(Client.Core.Remote)
local Store = require(Client.Core.Store)
local Sound = require(Client.Core.Sound)
local Theme = require(script.Parent.Parent.Theme)
local C = require(script.Parent.Parent.Components)
local Widgets = require(script.Parent.Parent.Widgets)

local Colors = Theme.Colors

return {
	name = "Rebirth",
	title = "Rebirth",
	icon = "♻️",
	size = Vector2.new(560, 470),
	build = function(content: Frame, app: any)
		local currentTab = "Rebirth"
		local confirmUntil = 0
		local body = C.new("Frame", {
			Name = "Body",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, -42),
			Position = UDim2.fromOffset(0, 42),
			Parent = content,
		})

		local function renderRebirth(profile: any)
			local cost = Rebirth.cost(profile.rebirths)
			local shards = Rebirth.shardReward(profile.rebirths)
			local nextMult = Rebirth.productionMultiplier(profile.rebirths + 1)
			C.text({
				Name = "Title",
				Text = "Rebirth #" .. (profile.rebirths + 1),
				FontFace = Theme.Fonts.Display,
				TextSize = 22,
				Size = UDim2.new(1, 0, 0, 30),
				Parent = body,
			})
			C.text({
				Name = "Requirement",
				Text = string.format(
					"Requires ⚡ %s  (you have ⚡ %s)",
					Format.number(cost),
					Format.number(profile.energy)
				),
				TextSize = 15,
				Size = UDim2.new(1, 0, 0, 22),
				Position = UDim2.fromOffset(0, 34),
				Parent = body,
			})
			local _, setBar =
				C.progress({ Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 60), Parent = body })
			setBar(profile.energy / cost, if profile.energy >= cost then Colors.Good else Colors.Energy)
			local text = {
				"YOU GET",
				string.format("  💠 +%d Void Shards (spend them on permanent perks)", shards),
				string.format(
					"  ⚡ Permanent production x%.1f (now x%.1f)",
					nextMult,
					Rebirth.productionMultiplier(profile.rebirths)
				),
				profile.rebirths == 0 and "  🔓 Unlocks the Void Forge (Void & Secret artifacts)" or "",
				"",
				"RESETS: Energy, machines, upgrades and plot expansions",
				"KEEPS: every artifact, your collection, shards and perks",
			}
			C.text({
				Name = "Details",
				Text = table.concat(text, "\n"),
				TextSize = 15,
				TextColor3 = Colors.TextDim,
				TextYAlignment = Enum.TextYAlignment.Top,
				Size = UDim2.new(1, 0, 0, 170),
				Position = UDim2.fromOffset(0, 86),
				Parent = body,
			})
			local confirming = os.clock() < confirmUntil
			local button = C.button({
				name = "RebirthButton",
				text = if confirming then "CLICK AGAIN TO CONFIRM" else "REBIRTH",
				color = if confirming then Colors.Bad else Colors.Accent2,
				size = UDim2.new(1, 0, 0, 56),
				position = UDim2.new(0, 0, 1, -60),
				textSize = 22,
				parent = body,
			})
			C.setButton(button, nil, profile.energy >= cost)
			C.onClick(button, function()
				if os.clock() >= confirmUntil then
					confirmUntil = os.clock() + 4
					C.setButton(button, "CLICK AGAIN TO CONFIRM", nil, Colors.Bad)
					return
				end
				confirmUntil = 0
				local response = Remote.request("Rebirth")
				if response.ok then
					Sound.play("Rebirth")
					app.toast("Rebirth complete! +" .. response.data.shards .. " Void Shards", "success")
				else
					app.showError(response.err)
				end
			end)
		end

		local function renderPerks(profile: any)
			C.text({
				Name = "Balance",
				Text = "💠 " .. profile.shards .. " Void Shards",
				TextSize = 16,
				TextColor3 = Colors.Shards,
				Size = UDim2.new(1, 0, 0, 24),
				Parent = body,
			})
			local list = C.scroll({
				Name = "List",
				Size = UDim2.new(1, 0, 1, -28),
				Position = UDim2.fromOffset(0, 28),
				Parent = body,
			})
			C.list(Enum.FillDirection.Vertical, 8).Parent = list
			C.padding(4).Parent = list
			for order, perk in Rebirth.Perks do
				local level = profile.perks[perk.id] or 0
				local cost = State.perkCost(profile, perk.id)
				local _, button = Widgets.row(list, {
					name = perk.id,
					title = perk.name .. "  •  Lv " .. level .. "/" .. perk.maxLevel,
					description = perk.description,
					accent = Colors.Shards,
					layoutOrder = order,
				})
				if cost then
					C.setButton(button, "💠 " .. cost, profile.shards >= cost, Colors.Accent2)
					C.onClick(button, function()
						local response = Remote.request("BuyPerk", perk.id)
						if response.ok then
							Sound.play("Upgrade")
						else
							app.showError(response.err)
						end
					end)
				else
					C.setButton(button, "MAX", false)
				end
			end
		end

		local function refresh()
			local profile = Store.profile
			if not profile then
				return
			end
			C.clear(body)
			if currentTab == "Rebirth" then
				renderRebirth(profile)
			else
				renderPerks(profile)
			end
		end

		local selectTab = Widgets.tabs(content, { "Rebirth", "Perks" }, function(name)
			currentTab = name
			refresh()
		end)
		selectTab(currentTab)

		local watching = nil
		return {
			frame = content,
			refresh = refresh,
			onOpen = function()
				watching = Store.watch({ "rebirths", "shards", "perks", "energy" }, refresh)
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
