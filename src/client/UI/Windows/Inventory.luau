-- Inventory: browse artifacts, place them, sell them, fuse duplicates, manage auto-sell.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Artifacts = require(Shared.Config.Artifacts)
local Economy = require(Shared.Config.Economy)
local Mutations = require(Shared.Config.Mutations)
local Rarities = require(Shared.Config.Rarities)
local Format = require(Shared.Util.Format)
local Items = require(Shared.Logic.Items)
local Effects = require(Shared.Logic.Effects)
local State = require(Shared.Logic.State)
local Fusion = require(Shared.Logic.Actions.Fusion)

local Client = script.Parent.Parent.Parent
local Remote = require(Client.Core.Remote)
local Store = require(Client.Core.Store)
local Sound = require(Client.Core.Sound)
local Placement = require(Client.Controllers.Placement)
local Theme = require(script.Parent.Parent.Theme)
local C = require(script.Parent.Parent.Components)
local Widgets = require(script.Parent.Parent.Widgets)

local Colors = Theme.Colors

local function sortedItems(profile: any): { { key: string, item: Items.Item, count: number } }
	local list = {}
	for key, count in profile.inventory do
		local item = Items.parse(key)
		if item then
			table.insert(list, { key = key, item = item, count = count })
		end
	end
	table.sort(list, function(a, b)
		local ra, rb = Rarities.order(Items.rarityOf(a.item)), Rarities.order(Items.rarityOf(b.item))
		if ra ~= rb then
			return ra > rb
		end
		local ea, eb = Items.baseEps(a.item), Items.baseEps(b.item)
		if ea ~= eb then
			return ea > eb
		end
		return a.key < b.key
	end)
	return list
end

return {
	name = "Inventory",
	title = "Inventory",
	icon = "🎒",
	size = Vector2.new(640, 470),
	build = function(content: Frame, app: any)
		local selectedKey: string? = nil
		local pickForSlot: number? = nil

		local header = C.new(
			"Frame",
			{ Name = "Header", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), Parent = content }
		)
		local capacityLabel =
			C.text({ Name = "Capacity", Text = "", TextSize = 16, Size = UDim2.new(0, 200, 1, 0), Parent = header })
		local actions = C.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -200, 1, 0),
			Position = UDim2.fromOffset(200, 0),
			Parent = header,
		})
		local actionLayout = C.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Right)
		actionLayout.Parent = actions
		local function request(action: string, ...: any)
			local response = Remote.request(action, ...)
			if not response.ok then
				app.showError(response.err)
			else
				Sound.play("Purchase")
			end
			return response
		end
		C.button({
			name = "AutoFill",
			text = "Auto-place best",
			color = Colors.Accent,
			textColor = Color3.fromRGB(10, 20, 40),
			size = UDim2.fromOffset(150, 32),
			textSize = 14,
			parent = actions,
			onClick = function()
				local response = request("AutoFill")
				if response.ok then
					app.toast("Placed " .. response.data.placed .. " artifacts", "success")
				end
			end,
		})
		C.button({
			name = "SellCommons",
			text = "Sell extra Commons",
			color = Colors.Warning,
			textColor = Color3.fromRGB(40, 20, 0),
			size = UDim2.fromOffset(160, 32),
			textSize = 14,
			parent = actions,
			onClick = function()
				local response = request("SellRarity", "Common", 1)
				if response.ok then
					app.toast(
						"Sold " .. response.data.sold .. " for ⚡" .. Format.number(response.data.value),
						"success"
					)
				end
			end,
		})

		local pickBanner = C.text({
			Name = "PickBanner",
			Text = "",
			TextSize = 15,
			TextColor3 = Colors.Accent,
			Size = UDim2.new(1, 0, 0, 20),
			Position = UDim2.fromOffset(0, 36),
			Visible = false,
			Parent = content,
		})

		local grid = C.scroll({
			Name = "Grid",
			Size = UDim2.new(0.58, -6, 1, -100),
			Position = UDim2.fromOffset(0, 58),
			Parent = content,
		})
		C.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(108, 118),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = grid,
		})
		C.padding(4).Parent = grid
		local empty = C.text({
			Name = "Empty",
			Text = "No artifacts yet. Open boxes to find some!",
			TextColor3 = Colors.TextDim,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(0.58, 0, 0, 60),
			Position = UDim2.fromOffset(0, 120),
			Visible = false,
			Parent = content,
		})

		local detail = C.new("Frame", {
			Name = "Detail",
			BackgroundColor3 = Colors.Card,
			Size = UDim2.new(0.42, -6, 1, -100),
			Position = UDim2.new(0.58, 6, 0, 58),
			Children = { C.corner(Theme.SmallCorner) },
			Parent = content,
		})
		C.padding(8).Parent = detail
		local _, showPreview = Widgets.preview(detail, UDim2.new(1, 0, 0, 86))
		local detailName = C.text({
			Name = "Name",
			Text = "",
			FontFace = Theme.Fonts.Bold,
			TextSize = 17,
			Size = UDim2.new(1, 0, 0, 22),
			Position = UDim2.fromOffset(0, 90),
			Parent = detail,
		})
		local detailBody = C.text({
			Name = "Body",
			Text = "Select an artifact.",
			TextSize = 12,
			TextColor3 = Colors.TextDim,
			TextYAlignment = Enum.TextYAlignment.Top,
			Size = UDim2.new(1, 0, 1, -194),
			Position = UDim2.fromOffset(0, 114),
			Parent = detail,
		})
		local buttons = C.new("Frame", {
			Name = "Buttons",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 74),
			Position = UDim2.new(0, 0, 1, -74),
			Parent = detail,
		})
		local buttonGrid = C.new("UIGridLayout", {
			CellSize = UDim2.new(0.5, -4, 0, 34),
			CellPadding = UDim2.fromOffset(6, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		})
		buttonGrid.Parent = buttons
		local placeButton = C.button({
			name = "Place",
			text = "Place",
			color = Colors.Good,
			textColor = Color3.fromRGB(10, 40, 20),
			textSize = 15,
			layoutOrder = 1,
			parent = buttons,
		})
		local sellButton = C.button({
			name = "Sell",
			text = "Sell 1",
			color = Colors.Warning,
			textColor = Color3.fromRGB(40, 20, 0),
			textSize = 15,
			layoutOrder = 2,
			parent = buttons,
		})
		local sellAllButton = C.button({
			name = "SellAll",
			text = "Sell all",
			color = Colors.Bad,
			textSize = 15,
			layoutOrder = 3,
			parent = buttons,
		})
		local fuseButton = C.button({
			name = "Fuse",
			text = "Fuse",
			color = Colors.Accent2,
			textSize = 15,
			layoutOrder = 4,
			parent = buttons,
		})

		local autoRow = C.new("Frame", {
			Name = "AutoSell",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 34),
			Position = UDim2.new(0, 0, 1, -36),
			Parent = content,
		})
		C.list(Enum.FillDirection.Horizontal, 6).Parent = autoRow
		C.text({ Text = "Auto-sell repeats:", TextSize = 14, Size = UDim2.fromOffset(130, 34), Parent = autoRow })
		local autoButtons: { [string]: TextButton } = {}
		for order, rarityId in { "Common", "Uncommon", "Rare" } do
			autoButtons[rarityId] = C.button({
				name = "Auto" .. rarityId,
				text = rarityId,
				color = Colors.PanelLight,
				size = UDim2.fromOffset(110, 30),
				textSize = 14,
				layoutOrder = order,
				parent = autoRow,
				onClick = function()
					local profile = Store.profile
					local enabled = not (profile and profile.settings.autoSell[rarityId])
					local response = Remote.request("SetAutoSell", rarityId, enabled)
					if not response.ok then
						app.showError(response.err)
					end
				end,
			})
		end

		local function selectedItem(): Items.Item?
			return if selectedKey then Items.parse(selectedKey) else nil
		end

		local function refreshDetail()
			local profile = Store.profile
			local item = selectedItem()
			local count = if selectedKey and profile then profile.inventory[selectedKey] or 0 else 0
			if not item or count <= 0 then
				selectedKey = nil
				showPreview(nil)
				detailName.Text = ""
				detailBody.Text = "Select an artifact to see its details."
				for _, button in { placeButton, sellButton, sellAllButton, fuseButton } do
					C.setButton(button, nil, false)
				end
				return
			end
			local artifact = Artifacts.get(item.id)
			local rarity = Rarities.get(Items.rarityOf(item))
			showPreview(item)
			detailName.Text = Items.displayName(item)
			detailName.TextColor3 = if rarity then rarity.color else Colors.Text
			local lines = {
				(rarity and rarity.id or "") .. "  •  owned x" .. count,
				"Output: ⚡ " .. Format.number(Items.baseEps(item)) .. "/s  (before bonuses)",
				"Sell value: ⚡ " .. Format.number(Items.sellValue(item)),
			}
			if item.mut ~= "" then
				local mutation = Mutations.get(item.mut)
				if mutation then
					table.insert(lines, item.mut .. ": " .. mutation.description)
				end
			end
			if artifact then
				for _, effect in artifact.effects do
					table.insert(lines, "• " .. Effects.name(effect.type) .. ": " .. Effects.describe(effect))
				end
			end
			detailBody.Text = table.concat(lines, "\n")
			C.setButton(placeButton, if pickForSlot then "Place on #" .. pickForSlot else "Place", true)
			C.setButton(sellButton, "Sell 1", true)
			C.setButton(sellAllButton, "Sell all (" .. count .. ")", true)
			local canFuse, reason = Fusion.canFuse(profile, selectedKey :: string)
			local fuseText = "Fuse 3 → ★"
			if reason == "NeedsFusionChamber" then
				fuseText = "Fuse 🔒"
				table.insert(lines, "Fusion needs the Fusion Chamber.")
				detailBody.Text = table.concat(lines, "\n")
			elseif reason == "MaxStars" then
				fuseText = "Max stars"
			elseif item.stars < Economy.MaxStars then
				fuseText = "Fuse ⚡" .. Format.number(State.fusionCost(profile, item))
			end
			C.setButton(fuseButton, fuseText, canFuse)
		end

		local function refreshGrid()
			local profile = Store.profile
			if not profile then
				return
			end
			C.clear(grid, true)
			local list = sortedItems(profile)
			for order, entry in list do
				Widgets.itemCard(entry.item, entry.count, {
					selected = entry.key == selectedKey,
					layoutOrder = order,
					onClick = function()
						selectedKey = entry.key
						Sound.play("UIClick")
						refreshGrid()
						refreshDetail()
					end,
				}).Parent =
					grid
			end
			empty.Visible = #list == 0
			capacityLabel.Text = string.format("Storage %d/%d", State.inventoryCount(profile), State.capacity(profile))
			capacityLabel.TextColor3 = if State.freeSpace(profile) <= 0 then Colors.Bad else Colors.Text
			for rarityId, button in autoButtons do
				local enabled = profile.settings.autoSell[rarityId] == true
				C.setButton(
					button,
					rarityId .. (if enabled then " ✓" else ""),
					true,
					if enabled then Colors.Good else Colors.PanelLight
				)
			end
		end

		C.onClick(placeButton, function()
			local key = selectedKey
			if not key then
				return
			end
			if pickForSlot then
				if Placement.place(pickForSlot, key) then
					pickForSlot = nil
					app.closeWindow()
				end
			else
				Placement.begin(key)
			end
		end)
		C.onClick(sellButton, function()
			if selectedKey then
				local response = request("Sell", selectedKey, 1)
				if response.ok then
					app.toast("Sold for ⚡" .. Format.number(response.data.value), "success")
				end
			end
		end)
		C.onClick(sellAllButton, function()
			local profile = Store.profile
			if selectedKey and profile then
				local count = profile.inventory[selectedKey] or 0
				if count > 0 then
					local response = request("Sell", selectedKey, count)
					if response.ok then
						app.toast("Sold " .. count .. " for ⚡" .. Format.number(response.data.value), "success")
					end
				end
			end
		end)
		C.onClick(fuseButton, function()
			if selectedKey then
				local response = Remote.request("Fuse", selectedKey)
				if response.ok then
					Sound.play("Fusion")
					selectedKey = response.data.key
					local item = Items.parse(response.data.key)
					app.toast("Fused into " .. (if item then Items.displayName(item) else "?") .. "!", "success")
				else
					app.showError(response.err)
				end
			end
		end)

		local watching = nil
		return {
			frame = content,
			refresh = function()
				refreshGrid()
				refreshDetail()
			end,
			onOpen = function(args: any)
				pickForSlot = if type(args) == "table" then args.pickForSlot else nil
				pickBanner.Visible = pickForSlot ~= nil
				pickBanner.Text = if pickForSlot then "Choose an artifact for pedestal #" .. pickForSlot else ""
				local refreshAll = C.debounce(function()
					refreshGrid()
					refreshDetail()
				end, 0.4)
				watching = {
					Store.watch({ "inventory", "settings", "machines" }, refreshAll),
					Store.watch({ "energy" }, refreshDetail),
				}
			end,
			onClose = function()
				pickForSlot = nil
				if watching then
					for _, connection in watching do
						connection:Disconnect()
					end
					watching = nil
				end
			end,
		}
	end,
}
