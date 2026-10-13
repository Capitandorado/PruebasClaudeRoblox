-- Machine shop and plot expansions.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Machines = require(Shared.Config.Machines)
local PlotConfig = require(Shared.Config.Plot)
local Format = require(Shared.Util.Format)
local MachineStats = require(Shared.Logic.MachineStats)
local State = require(Shared.Logic.State)

local Client = script.Parent.Parent.Parent
local Remote = require(Client.Core.Remote)
local Store = require(Client.Core.Store)
local Sound = require(Client.Core.Sound)
local Theme = require(script.Parent.Parent.Theme)
local C = require(script.Parent.Parent.Components)
local Widgets = require(script.Parent.Parent.Widgets)

local Colors = Theme.Colors

local function pct(value: number): string
	return string.format("%d%%", math.floor(value * 100 + 0.5))
end

-- One-line summary of what a machine does at `level`.
local function machineStats(profile: any, machine: Machines.Machine, level: number): string
	local production = Store.production()
	if machine.kind == "fabricator" then
		local parts = {}
		local interval = MachineStats.getStat(machine.id, "chargeInterval", level)
		if interval > 0 then
			table.insert(
				parts,
				string.format("Free box every %.1fs", interval / State.speedFactor(profile, production))
			)
			table.insert(parts, "holds " .. MachineStats.getStat(machine.id, "chargeCap", level))
		end
		local cost = MachineStats.getStat(machine.id, "boxCost", level)
		if cost > 0 then
			table.insert(parts, "⚡" .. Format.number(cost) .. "/box")
		end
		table.insert(parts, string.format("luck x%.2f", MachineStats.getStat(machine.id, "luck", level)))
		return table.concat(parts, " • ")
	elseif machine.kind == "printer" then
		return string.format(
			"Opens a box every %.1fs",
			MachineStats.getStat(machine.id, "autoInterval", level) / State.speedFactor(profile, production)
		)
	elseif machine.kind == "booster" then
		return "+" .. pct(MachineStats.getStat(machine.id, "productionBonus", level)) .. " factory output"
	elseif machine.kind == "fusion" then
		return "Fusion cost -" .. pct(MachineStats.getStat(machine.id, "fusionDiscount", level))
	end
	return ""
end

return {
	name = "Shop",
	title = "Machines",
	icon = "🏭",
	size = Vector2.new(600, 470),
	build = function(content: Frame, app: any)
		local currentTab = "Machines"
		local list = C.scroll({
			Name = "List",
			Size = UDim2.new(1, 0, 1, -42),
			Position = UDim2.fromOffset(0, 42),
			Parent = content,
		})
		C.list(Enum.FillDirection.Vertical, 8).Parent = list
		C.padding(4).Parent = list

		local function act(action: string, ...: any)
			local response = Remote.request(action, ...)
			if response.ok then
				Sound.play(if action == "BuyMachine" or action == "BuyExpansion" then "Unlock" else "Upgrade")
			else
				app.showError(response.err)
			end
		end

		local function renderMachines(profile: any)
			for order, machine in Machines.List do
				local state = profile.machines[machine.id]
				local level = if state then state.level else 1
				local description = machine.description .. "\n" .. machineStats(profile, machine, level)
				local title = machine.name
					.. (if state then "  •  Lv " .. state.level .. "/" .. machine.maxLevel else "")
				local _, button = Widgets.row(list, {
					name = machine.id,
					title = title,
					description = description,
					accent = machine.color,
					layoutOrder = order,
				})
				button.Parent.Size = UDim2.new(1, -8, 0, 86)
				if not state then
					if profile.rebirths < machine.rebirthRequired then
						C.setButton(button, "Rebirth " .. machine.rebirthRequired .. " needed", false)
					else
						C.setButton(
							button,
							"Buy ⚡" .. Format.number(machine.cost),
							profile.energy >= machine.cost,
							Colors.Good
						)
						C.onClick(button, function()
							act("BuyMachine", machine.id)
						end)
					end
				else
					local cost = MachineStats.upgradeCost(machine.id, state.level)
					if cost then
						C.setButton(
							button,
							"Upgrade ⚡" .. Format.number(cost),
							profile.energy >= cost,
							Colors.Accent2
						)
						C.onClick(button, function()
							act("UpgradeMachine", machine.id)
						end)
					else
						C.setButton(button, "MAX", false)
					end
				end
			end
		end

		local function renderExpansion(profile: any)
			local current = PlotConfig.getExpansion(profile.expansion)
			local cost = State.expansionCost(profile)
			local description = string.format(
				"Current layout: %d x %d = %d pedestals.",
				current.columns,
				current.rows,
				current.columns * current.rows
			)
			if cost then
				local nextLayout = PlotConfig.getExpansion(profile.expansion + 1)
				description ..= string.format(
					"\nNext: %d x %d = %d pedestals.",
					nextLayout.columns,
					nextLayout.rows,
					nextLayout.columns * nextLayout.rows
				)
			end
			local _, button = Widgets.row(list, {
				name = "Expansion",
				title = "Plot expansion  •  level " .. profile.expansion .. "/" .. PlotConfig.MaxExpansionLevel,
				description = description,
				accent = Colors.Energy,
				layoutOrder = 1,
			})
			if cost then
				C.setButton(button, "Expand ⚡" .. Format.number(cost), profile.energy >= cost, Colors.Good)
				C.onClick(button, function()
					act("BuyExpansion")
				end)
			else
				C.setButton(button, "MAX", false)
			end
			-- Grid preview: unlocked (green), next expansion (gold), locked (dark).
			local preview = C.new("Frame", {
				Name = "GridPreview",
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(PlotConfig.Columns * 34, PlotConfig.Rows * 34),
				LayoutOrder = 2,
				Parent = list,
			})
			C.new("UIGridLayout", {
				CellSize = UDim2.fromOffset(30, 30),
				CellPadding = UDim2.fromOffset(4, 4),
				SortOrder = Enum.SortOrder.LayoutOrder,
				Parent = preview,
			})
			for slot = 1, PlotConfig.TotalSlots do
				local unlocked = PlotConfig.isSlotUnlocked(slot, profile.expansion)
				local nextUnlocked = cost ~= nil and PlotConfig.isSlotUnlocked(slot, profile.expansion + 1)
				C.new("Frame", {
					Name = "Cell" .. slot,
					LayoutOrder = slot,
					BackgroundColor3 = if unlocked
						then Colors.Good
						elseif nextUnlocked then Colors.Energy
						else Colors.Disabled,
					BackgroundTransparency = if unlocked then 0.1 else 0.4,
					Children = { C.corner(6) },
					Parent = preview,
				})
			end
		end

		local function refresh()
			local profile = Store.profile
			if not profile then
				return
			end
			C.clear(list, true)
			if currentTab == "Machines" then
				renderMachines(profile)
			else
				renderExpansion(profile)
			end
		end

		local selectTab = Widgets.tabs(content, { "Machines", "Expansion" }, function(name)
			currentTab = name
			refresh()
		end)
		selectTab(currentTab)

		local watching = nil
		return {
			frame = content,
			refresh = refresh,
			onOpen = function(args: any)
				if type(args) == "table" and args.tab then
					currentTab = args.tab
					selectTab(currentTab)
				end
				watching = Store.watch({ "energy", "machines", "expansion", "rebirths" }, refresh)
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
