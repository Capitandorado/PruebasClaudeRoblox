-- Game-specific widgets shared by several windows.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Artifacts = require(Shared.Config.Artifacts)
local Mutations = require(Shared.Config.Mutations)
local Rarities = require(Shared.Config.Rarities)
local Format = require(Shared.Util.Format)
local Items = require(Shared.Logic.Items)
local ArtifactModels = require(Shared.Visuals.ArtifactModels)

local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)

local Widgets = {}

local Colors = Theme.Colors

-- Inventory/collection card for an item. `count` nil hides the counter.
function Widgets.itemCard(
	item: Items.Item,
	count: number?,
	options: { selected: boolean?, layoutOrder: number?, onClick: (() -> ())? }?
): TextButton
	local opts = options or {}
	local artifact = Artifacts.get(item.id)
	local rarity = Rarities.get(Items.rarityOf(item))
	local color = if rarity then rarity.color else Colors.Accent
	local card: TextButton = C.new("TextButton", {
		Name = Items.keyOf(item),
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = if opts.selected then Colors.CardHover else Colors.Card,
		LayoutOrder = opts.layoutOrder or 0,
		Children = { C.corner(Theme.SmallCorner) },
	})
	local stroke = C.stroke(color, if opts.selected then 3 else 1.5, if opts.selected then 0 else 0.35)
	stroke.Parent = card
	C.new("Frame", {
		Name = "Band",
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 6),
		Children = { C.corner(3) },
		Parent = card,
	})
	C.text({
		Name = "Name",
		Text = if artifact then artifact.name else item.id,
		TextSize = 14,
		FontFace = Theme.Fonts.Bold,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, -8, 0, 34),
		Position = UDim2.fromOffset(4, 10),
		Parent = card,
	})
	C.text({
		Name = "Rarity",
		Text = (rarity and rarity.id or "")
			.. (if item.stars > 1 then "  " .. string.rep("★", item.stars - 1) else ""),
		TextSize = 12,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, -8, 0, 16),
		Position = UDim2.fromOffset(4, 46),
		Parent = card,
	})
	if item.mut ~= "" then
		local mutation = Mutations.get(item.mut)
		C.text({
			Name = "Mutation",
			Text = string.upper(item.mut),
			TextSize = 12,
			FontFace = Theme.Fonts.Bold,
			TextColor3 = if mutation then mutation.color else Colors.Text,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, -8, 0, 16),
			Position = UDim2.fromOffset(4, 62),
			Parent = card,
		})
	end
	C.text({
		Name = "Eps",
		Text = "⚡" .. Format.number(Items.baseEps(item)) .. "/s",
		TextSize = 13,
		TextColor3 = Colors.Energy,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, -8, 0, 16),
		Position = UDim2.new(0, 4, 1, -22),
		Parent = card,
	})
	if count and count > 1 then
		local badge = C.new("Frame", {
			Name = "CountBadge",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 4, 0, -6),
			Size = UDim2.fromOffset(34, 18),
			BackgroundColor3 = color:Lerp(Colors.Panel, 0.35),
			ZIndex = 3,
			Children = { C.corner(9) },
			Parent = card,
		})
		C.text({
			Name = "Count",
			Text = "x" .. count,
			TextSize = 12,
			FontFace = Theme.Fonts.Bold,
			TextColor3 = Colors.Text,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 3,
			Parent = badge,
		})
	end
	if opts.onClick then
		card.Activated:Connect(opts.onClick)
	end
	return card
end

-- 3D preview of an artifact. Returns the viewport and a function to change the item.
function Widgets.preview(parent: Instance, size: UDim2, position: UDim2?): (ViewportFrame, (item: Items.Item?) -> ())
	local viewport: ViewportFrame = C.new("ViewportFrame", {
		Name = "Preview",
		Size = size,
		Position = position or UDim2.new(),
		BackgroundColor3 = Color3.fromRGB(12, 10, 26),
		Ambient = Color3.fromRGB(150, 140, 190),
		LightColor = Color3.fromRGB(255, 255, 255),
		LightDirection = Vector3.new(-1, -1, -1),
		Children = { C.corner(Theme.SmallCorner) },
		Parent = parent,
	})
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	local current: Model? = nil
	local function show(item: Items.Item?)
		if current then
			current:Destroy()
			current = nil
		end
		if not item then
			return
		end
		local model = ArtifactModels.build(item.id, { mutation = item.mut, stars = item.stars, effects = false })
		model:PivotTo(CFrame.new())
		model.Parent = viewport
		current = model
		camera.CFrame = CFrame.lookAt(Vector3.new(4.5, 2.5, 7), Vector3.new(0, 0, 0))
	end
	return viewport, show
end

-- Row of tab buttons. Returns a setter that highlights the selected tab.
function Widgets.tabs(parent: Instance, names: { string }, onSelect: (name: string) -> ()): (string) -> ()
	local row = C.new("Frame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 34),
		Parent = parent,
	})
	C.list(Enum.FillDirection.Horizontal, 6).Parent = row
	local buttons = {}
	local function selectTab(name: string)
		for tabName, button in buttons do
			C.setButton(button, nil, true, if tabName == name then Colors.Accent2 else Colors.PanelLight)
		end
	end
	for order, name in names do
		buttons[name] = C.button({
			name = name .. "Tab",
			text = name,
			color = Colors.PanelLight,
			size = UDim2.fromOffset(130, 32),
			textSize = 15,
			layoutOrder = order,
			parent = row,
			onClick = function()
				selectTab(name)
				onSelect(name)
			end,
		})
	end
	return selectTab
end

-- Standard row: title + description on the left, action button on the right.
function Widgets.row(
	parent: Instance,
	options: { name: string, title: string, description: string, accent: Color3?, layoutOrder: number? }
): (Frame, TextButton)
	local row = C.new("Frame", {
		Name = options.name,
		BackgroundColor3 = Colors.Card,
		Size = UDim2.new(1, -8, 0, 74),
		LayoutOrder = options.layoutOrder or 0,
		Children = { C.corner(Theme.SmallCorner) },
		Parent = parent,
	})
	C.new("Frame", {
		Name = "Accent",
		BackgroundColor3 = options.accent or Colors.Accent,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 6, 1, -16),
		Position = UDim2.fromOffset(8, 8),
		Children = { C.corner(3) },
		Parent = row,
	})
	C.text({
		Name = "Title",
		Text = options.title,
		FontFace = Theme.Fonts.Bold,
		TextSize = 17,
		Size = UDim2.new(1, -190, 0, 22),
		Position = UDim2.fromOffset(22, 8),
		Parent = row,
	})
	C.text({
		Name = "Description",
		Text = options.description,
		TextSize = 13,
		TextColor3 = Colors.TextDim,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, -190, 1, -34),
		Position = UDim2.fromOffset(22, 30),
		Parent = row,
	})
	local button = C.button({
		name = "Action",
		text = "",
		color = Colors.Accent2,
		size = UDim2.fromOffset(150, 44),
		position = UDim2.new(1, -160, 0.5, -22),
		textSize = 15,
		parent = row,
	})
	return row, button
end

return Widgets
