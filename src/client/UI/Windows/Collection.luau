-- Collection book (discoveries, variants, completion) and the transparent odds table.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Artifacts = require(Shared.Config.Artifacts)
local Boxes = require(Shared.Config.Boxes)
local Machines = require(Shared.Config.Machines)
local Mutations = require(Shared.Config.Mutations)
local Rarities = require(Shared.Config.Rarities)
local Format = require(Shared.Util.Format)
local Effects = require(Shared.Logic.Effects)
local Roller = require(Shared.Logic.Roller)
local State = require(Shared.Logic.State)

local Client = script.Parent.Parent.Parent
local Store = require(Client.Core.Store)
local Sound = require(Client.Core.Sound)
local Theme = require(script.Parent.Parent.Theme)
local C = require(script.Parent.Parent.Components)
local Widgets = require(script.Parent.Parent.Widgets)

local Colors = Theme.Colors

-- The machine that sells each box (luck is computed for it).
local function machineForBox(boxId: string): string
	for _, machine in Machines.List do
		if machine.box == boxId and machine.kind == "fabricator" then
			return machine.id
		end
	end
	return Machines.StarterId
end

return {
	name = "Collection",
	title = "Collection",
	icon = "📖",
	size = Vector2.new(640, 480),
	build = function(content: Frame, _app: any)
		local currentTab = "Artifacts"
		local currentBox = "basic"
		local selectedId: string? = nil

		local summary = C.text({
			Name = "Summary",
			Text = "",
			TextSize = 14,
			TextColor3 = Colors.TextDim,
			Size = UDim2.new(1, 0, 0, 20),
			Position = UDim2.fromOffset(0, 38),
			Parent = content,
		})
		local body = C.new("Frame", {
			Name = "Body",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, -62),
			Position = UDim2.fromOffset(0, 62),
			Parent = content,
		})

		local function renderArtifacts(profile: any)
			-- Completion counts the core catalog; event artifacts are a bonus.
			local discovered, variants, core = 0, 0, 0
			for _, artifact in Artifacts.List do
				if artifact.catalog ~= "core" then
					continue
				end
				core += 1
				local entry = profile.collection[artifact.id]
				if entry then
					discovered += 1
					for _ in entry.muts do
						variants += 1
					end
				end
			end
			local totalVariants = core * #Mutations.List
			local best = Rarities.List[profile.bestRarity]
			summary.Text = string.format(
				"Found %d/%d (%d%%)  •  Variants %d/%d  •  Best: %s  •  Bonus +%d%% production",
				discovered,
				core,
				math.floor(discovered / math.max(1, core) * 100 + 0.5),
				variants,
				totalVariants,
				if best then best.id else "—",
				math.floor(State.collectionBonus(profile) * 100 + 0.5)
			)
			local grid = C.scroll({ Name = "Grid", Size = UDim2.new(0.62, -6, 1, 0), Parent = body })
			C.new("UIGridLayout", {
				CellSize = UDim2.fromOffset(112, 96),
				CellPadding = UDim2.fromOffset(6, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
				Parent = grid,
			})
			C.padding(4).Parent = grid
			for order, artifact in Artifacts.List do
				local entry = profile.collection[artifact.id]
				local rarity = Rarities.get(artifact.rarity)
				local color = if rarity then rarity.color else Colors.Accent
				local card = C.new("TextButton", {
					Name = artifact.id,
					Text = "",
					AutoButtonColor = false,
					LayoutOrder = order,
					BackgroundColor3 = if entry then Colors.Card else Color3.fromRGB(16, 14, 30),
					Children = {
						C.corner(Theme.SmallCorner),
						C.stroke(color, if artifact.id == selectedId then 3 else 1.2, if entry then 0.2 else 0.7),
					},
					Parent = grid,
				})
				C.text({
					Name = "Name",
					Text = if entry then artifact.name else "???",
					FontFace = Theme.Fonts.Bold,
					TextSize = 14,
					TextXAlignment = Enum.TextXAlignment.Center,
					Size = UDim2.new(1, -8, 0, 34),
					Position = UDim2.fromOffset(4, 6),
					Parent = card,
				})
				C.text({
					Name = "Rarity",
					Text = artifact.rarity .. (if artifact.catalog ~= "core" then "  •  EVENT" else ""),
					TextSize = 12,
					TextColor3 = color,
					TextXAlignment = Enum.TextXAlignment.Center,
					Size = UDim2.new(1, -8, 0, 16),
					Position = UDim2.fromOffset(4, 42),
					Parent = card,
				})
				local dots = C.new("Frame", {
					Name = "Mutations",
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 14),
					Position = UDim2.new(0, 0, 1, -22),
					Parent = card,
				})
				C.list(Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Center).Parent = dots
				for mutOrder, mutation in Mutations.List do
					local owned = entry ~= nil and entry.muts[mutation.id] == true
					C.new("Frame", {
						Name = mutation.id,
						LayoutOrder = mutOrder,
						Size = UDim2.fromOffset(12, 12),
						BackgroundColor3 = if owned then mutation.color else Colors.Disabled,
						BackgroundTransparency = if owned then 0 else 0.5,
						Children = { C.corner(6) },
						Parent = dots,
					})
				end
				card.Activated:Connect(function()
					selectedId = artifact.id
					Sound.play("UIClick")
					C.clear(body)
					renderArtifacts(profile)
				end)
			end
			local info = C.new("Frame", {
				Name = "Info",
				BackgroundColor3 = Colors.Card,
				Size = UDim2.new(0.38, -6, 1, 0),
				Position = UDim2.new(0.62, 6, 0, 0),
				Children = { C.corner(Theme.SmallCorner) },
				Parent = body,
			})
			C.padding(10).Parent = info
			local selected = selectedId and Artifacts.get(selectedId)
			local entry = selected and profile.collection[selected.id]
			if selected and entry then
				local _, show = Widgets.preview(info, UDim2.new(1, 0, 0, 120))
				show({ id = selected.id, mut = "", stars = entry.stars })
				local lines = {
					selected.rarity .. "  •  found x" .. entry.count,
					"Base output ⚡" .. Format.number(selected.eps) .. "/s",
					"Best fusion: " .. string.rep("★", entry.stars - 1) .. (if entry.stars == 1 then "none" else ""),
					"",
					selected.lore,
				}
				for _, effect in selected.effects do
					table.insert(lines, "• " .. Effects.name(effect.type) .. ": " .. Effects.describe(effect))
				end
				C.text({
					Name = "Title",
					Text = selected.name,
					FontFace = Theme.Fonts.Bold,
					TextSize = 18,
					Size = UDim2.new(1, 0, 0, 24),
					Position = UDim2.fromOffset(0, 126),
					Parent = info,
				})
				C.text({
					Name = "Text",
					Text = table.concat(lines, "\n"),
					TextSize = 13,
					TextColor3 = Colors.TextDim,
					TextYAlignment = Enum.TextYAlignment.Top,
					Size = UDim2.new(1, 0, 1, -154),
					Position = UDim2.fromOffset(0, 152),
					Parent = info,
				})
			else
				C.text({
					Name = "Text",
					Text = if selected
						then "Not discovered yet.\nKeep opening boxes — check the Odds tab to see where it drops."
						else "Select a discovered artifact to read about it.",
					TextSize = 14,
					TextColor3 = Colors.TextDim,
					TextYAlignment = Enum.TextYAlignment.Top,
					Size = UDim2.fromScale(1, 1),
					Parent = info,
				})
			end
		end

		local function renderOdds(profile: any)
			local machineId = machineForBox(currentBox)
			local luck = State.luck(profile, machineId, Store.production())
			local box = Boxes.get(currentBox)
			summary.Text = string.format(
				"%s  •  your luck x%.2f (machine, upgrades, perks, artifacts)",
				if box then box.name else currentBox,
				luck
			)
			local selector = C.new(
				"Frame",
				{ Name = "BoxSelector", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 32), Parent = body }
			)
			C.list(Enum.FillDirection.Horizontal, 6).Parent = selector
			for order, entryBox in Boxes.List do
				C.button({
					name = entryBox.id,
					text = entryBox.name,
					color = if entryBox.id == currentBox
						then entryBox.color:Lerp(Color3.new(0, 0, 0), 0.3)
						else Colors.PanelLight,
					size = UDim2.fromOffset(120, 30),
					textSize = 14,
					layoutOrder = order,
					parent = selector,
					onClick = function()
						currentBox = entryBox.id
						C.clear(body)
						renderOdds(profile)
					end,
				})
			end
			local list = C.scroll({
				Name = "Rows",
				Size = UDim2.new(1, 0, 1, -38),
				Position = UDim2.fromOffset(0, 38),
				Parent = body,
			})
			C.list(Enum.FillDirection.Vertical, 2).Parent = list
			local function row(order: number, name: string, color: Color3, label: string, chance: number)
				local frame = C.new("Frame", {
					Name = "Row" .. order,
					LayoutOrder = order,
					BackgroundColor3 = if order % 2 == 0 then Colors.Card else Colors.Panel,
					Size = UDim2.new(1, -8, 0, 26),
					Children = { C.corner(4) },
					Parent = list,
				})
				C.text({
					Text = name,
					TextSize = 14,
					Size = UDim2.new(0.42, 0, 1, 0),
					Position = UDim2.fromOffset(8, 0),
					Parent = frame,
				})
				C.text({
					Text = label,
					TextSize = 13,
					TextColor3 = color,
					Size = UDim2.new(0.18, 0, 1, 0),
					Position = UDim2.fromScale(0.42, 0),
					Parent = frame,
				})
				C.text({
					Text = Format.percent(chance),
					TextSize = 14,
					Size = UDim2.new(0.18, 0, 1, 0),
					Position = UDim2.fromScale(0.6, 0),
					Parent = frame,
				})
				C.text({
					Text = Format.oneIn(chance),
					TextSize = 13,
					TextColor3 = Colors.TextDim,
					Size = UDim2.new(0.22, -8, 1, 0),
					Position = UDim2.fromScale(0.78, 0),
					Parent = frame,
				})
			end
			local order = 0
			for _, entry in Roller.getArtifactOdds(currentBox, luck) do
				order += 1
				local artifact = Artifacts.get(entry.id)
				local rarity = Rarities.get(entry.rarity)
				local known = profile.collection[entry.id] ~= nil
				row(
					order,
					if known and artifact then artifact.name else "???",
					if rarity then rarity.color else Colors.Text,
					entry.rarity,
					entry.chance
				)
			end
			order += 1
			C.text({
				Name = "MutationsHeader",
				Text = "Mutations (rolled separately on every box)",
				TextSize = 14,
				TextColor3 = Colors.Accent,
				LayoutOrder = order,
				Size = UDim2.new(1, -8, 0, 26),
				Parent = list,
			})
			for _, entry in Roller.getMutationOdds(currentBox) do
				order += 1
				local mutation = Mutations.get(entry.id)
				row(
					order,
					entry.id .. (if mutation then string.format(" (x%s)", tostring(mutation.mult)) else ""),
					if mutation then mutation.color else Colors.Text,
					"mutation",
					entry.chance
				)
			end
			order += 1
			C.text({
				Name = "Note",
				Text = "These numbers come from the same code the server uses to roll every box.",
				TextSize = 12,
				TextColor3 = Colors.TextDim,
				LayoutOrder = order,
				Size = UDim2.new(1, -8, 0, 30),
				Parent = list,
			})
		end

		local function refresh()
			local profile = Store.profile
			if not profile then
				return
			end
			C.clear(body)
			if currentTab == "Artifacts" then
				renderArtifacts(profile)
			else
				renderOdds(profile)
			end
		end

		local selectTab = Widgets.tabs(content, { "Artifacts", "Odds" }, function(name)
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
				watching =
					Store.watch({ "collection", "bestRarity", "upgrades", "perks", "placed", "machines" }, refresh)
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
