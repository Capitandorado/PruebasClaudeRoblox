-- Global upgrades bought with Energy (luck, speed, storage).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Upgrades = require(Shared.Config.Upgrades)
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

local ACCENTS = { luck = Colors.Good, speed = Colors.Accent, storage = Colors.Energy }

local function effectText(upgradeId: string, level: number): string
	local upgrade = Upgrades.get(upgradeId)
	if not upgrade then
		return ""
	end
	local total = upgrade.perLevel * level
	if upgradeId == "storage" then
		return "+" .. total .. " slots"
	end
	return "+" .. math.floor(total * 100 + 0.5) .. "%"
end

return {
	name = "Upgrades",
	title = "Upgrades",
	icon = "⬆️",
	size = Vector2.new(560, 380),
	build = function(content: Frame, app: any)
		local list = C.scroll({ Name = "List", Parent = content })
		C.list(Enum.FillDirection.Vertical, 8).Parent = list
		C.padding(4).Parent = list

		local function refresh()
			local profile = Store.profile
			if not profile then
				return
			end
			C.clear(list, true)
			for order, upgrade in Upgrades.List do
				local level = profile.upgrades[upgrade.id] or 0
				local cost = State.upgradeCost(profile, upgrade.id)
				local description = upgrade.description
					.. "\nNow: "
					.. effectText(upgrade.id, level)
					.. (if cost then "  →  " .. effectText(upgrade.id, level + 1) else "")
				local _, button = Widgets.row(list, {
					name = upgrade.id,
					title = upgrade.name .. "  •  Lv " .. level .. "/" .. upgrade.maxLevel,
					description = description,
					accent = ACCENTS[upgrade.id],
					layoutOrder = order,
				})
				if cost then
					C.setButton(button, "⚡" .. Format.number(cost), profile.energy >= cost, Colors.Accent2)
					C.onClick(button, function()
						local response = Remote.request("BuyUpgrade", upgrade.id)
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
			local luckLine = C.text({
				Name = "Summary",
				Text = string.format(
					"Storage: %d/%d   •   Starter box luck: x%.2f",
					State.inventoryCount(profile),
					State.capacity(profile),
					State.luck(profile, "starter_fabricator", Store.production())
				),
				TextColor3 = Colors.TextDim,
				TextSize = 14,
				LayoutOrder = 99,
				Parent = list,
			})
			luckLine.Size = UDim2.new(1, -8, 0, 24)
		end

		local function signature(): string
			local profile = Store.profile
			if not profile then
				return ""
			end
			local parts = { tostring(State.inventoryCount(profile)), tostring(State.capacity(profile)) }
			for _, upgrade in Upgrades.List do
				local cost = State.upgradeCost(profile, upgrade.id)
				table.insert(
					parts,
					string.format(
						"%s:%d:%s",
						upgrade.id,
						profile.upgrades[upgrade.id] or 0,
						tostring(cost ~= nil and profile.energy >= cost)
					)
				)
			end
			table.insert(parts, string.format("%.2f", State.luck(profile, "starter_fabricator", Store.production())))
			return table.concat(parts, "|")
		end
		local guardedRefresh = C.guarded(signature, refresh)

		local watching = nil
		return {
			frame = content,
			refresh = function()
				guardedRefresh(true)
			end,
			onOpen = function()
				watching = Store.watch({ "energy", "upgrades", "inventory", "perks", "placed" }, function()
					guardedRefresh()
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
