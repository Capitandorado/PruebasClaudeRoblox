--!strict
--[[
	HUD
	===
	Construye la interfaz del jugador por código (sin assets):
	- Dinero en la parte superior.
	- Panel de inventario con las semillas (seleccionables) y los frutos.
	- Botón "Plantar" para plantar la semilla seleccionada.
	- Avisos temporales enviados por el servidor.

	Este módulo sólo DIBUJA. No decide nada: el botón Plantar únicamente avisa
	al script principal, que envía la petición al servidor para que la valide.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local SeedConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SeedConfig"))

export type Inventory = {
	Seeds: { [string]: number },
	Fruits: { [string]: number },
}

local HUD = {}

-- Colores de la interfaz.
local PANEL_COLOR = Color3.fromRGB(30, 32, 40)
local ITEM_COLOR = Color3.fromRGB(50, 54, 66)
local SELECTED_COLOR = Color3.fromRGB(70, 130, 80)
local TEXT_COLOR = Color3.fromRGB(240, 240, 240)
local MONEY_COLOR = Color3.fromRGB(120, 255, 120)

local gui: ScreenGui
local moneyLabel: TextLabel
local seedList: ScrollingFrame
local fruitList: ScrollingFrame
local fruitTotalLabel: TextLabel
local plantButton: TextButton
local panel: Frame
local notifyLabel: TextLabel

local selectedSeedId: string? = nil
local currentInventory: Inventory = { Seeds = {}, Fruits = {} }
local plantCallback: ((seedId: string) -> ())? = nil
local notifyToken = 0

--------------------------------------------------------------------------------
-- Utilidades de construcción
--------------------------------------------------------------------------------

local function corner(parent: Instance, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = parent
end

local function padding(parent: Instance, pixels: number)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, pixels)
	p.PaddingBottom = UDim.new(0, pixels)
	p.PaddingLeft = UDim.new(0, pixels)
	p.PaddingRight = UDim.new(0, pixels)
	p.Parent = parent
end

local function makeLabel(props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = TEXT_COLOR
	label.TextScaled = true
	for key, value in props do
		(label :: any)[key] = value
	end
	return label
end

local function makeList(parent: Instance, name: string, position: UDim2, size: UDim2): ScrollingFrame
	local list = Instance.new("ScrollingFrame")
	list.Name = name
	list.Position = position
	list.Size = size
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	list.Parent = parent
	return list
end

local function clearList(list: ScrollingFrame)
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

--------------------------------------------------------------------------------
-- Refresco del inventario
--------------------------------------------------------------------------------

local function refreshPlantButton()
	local enabled = selectedSeedId ~= nil
	plantButton.AutoButtonColor = enabled
	plantButton.BackgroundColor3 = if enabled then Color3.fromRGB(60, 170, 80) else Color3.fromRGB(80, 80, 80)
	if selectedSeedId then
		local seed = SeedConfig.get(selectedSeedId)
		plantButton.Text = `Plantar {if seed then seed.DisplayName else ""}`
	else
		plantButton.Text = "Selecciona una semilla"
	end
end

local function rebuildLists()
	-- Si ya no quedan semillas del tipo seleccionado, se deselecciona.
	if selectedSeedId and (currentInventory.Seeds[selectedSeedId] or 0) <= 0 then
		selectedSeedId = nil
	end

	clearList(seedList)
	clearList(fruitList)

	local fruitTotal = 0
	for order, seedId in SeedConfig.getSortedIds() do
		local seed = SeedConfig.Seeds[seedId]
		local rarity = SeedConfig.getRarity(seed.Rarity)

		-- Semillas: botones seleccionables.
		local seedCount = currentInventory.Seeds[seedId] or 0
		if seedCount > 0 then
			local button = Instance.new("TextButton")
			button.Name = seedId
			button.LayoutOrder = order
			button.Size = UDim2.new(1, -8, 0, 34)
			button.BackgroundColor3 = if seedId == selectedSeedId then SELECTED_COLOR else ITEM_COLOR
			button.Text = ""
			corner(button, 6)

			local stripe = Instance.new("Frame")
			stripe.Size = UDim2.new(0, 6, 1, 0)
			stripe.BackgroundColor3 = rarity.Color
			stripe.BorderSizePixel = 0
			stripe.Parent = button
			corner(stripe, 3)

			makeLabel({
				Size = UDim2.new(1, -16, 1, -8),
				Position = UDim2.fromOffset(12, 4),
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = `{seed.DisplayName} x{seedCount}  ·  {rarity.DisplayName}`,
				Parent = button,
			})

			button.Activated:Connect(function()
				selectedSeedId = if selectedSeedId == seedId then nil else seedId
				rebuildLists()
			end)
			button.Parent = seedList
		end

		-- Frutos: sólo informativos (se venden en el puesto de venta).
		local fruitCount = currentInventory.Fruits[seedId] or 0
		if fruitCount > 0 then
			fruitTotal += fruitCount * seed.SellValue
			local row = Instance.new("Frame")
			row.Name = seedId
			row.LayoutOrder = order
			row.Size = UDim2.new(1, -8, 0, 28)
			row.BackgroundColor3 = ITEM_COLOR
			corner(row, 6)

			makeLabel({
				Size = UDim2.new(1, -16, 1, -8),
				Position = UDim2.fromOffset(8, 4),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = rarity.Color,
				Text = `Fruto de {seed.DisplayName} x{fruitCount}  (${seed.SellValue} c/u)`,
				Parent = row,
			})
			row.Parent = fruitList
		end
	end

	fruitTotalLabel.Text = if fruitTotal > 0
		then `Valor total: ${fruitTotal} — véndelos en el puesto`
		else "Sin frutos. ¡Cosecha tus plantas!"

	refreshPlantButton()
end

--------------------------------------------------------------------------------
-- Construcción de la interfaz
--------------------------------------------------------------------------------

local function build()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	gui = Instance.new("ScreenGui")
	gui.Name = "CultivoHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Dinero -------------------------------------------------------------
	local moneyFrame = Instance.new("Frame")
	moneyFrame.Name = "Money"
	moneyFrame.AnchorPoint = Vector2.new(0.5, 0)
	moneyFrame.Position = UDim2.new(0.5, 0, 0, 8)
	moneyFrame.Size = UDim2.fromOffset(200, 44)
	moneyFrame.BackgroundColor3 = PANEL_COLOR
	moneyFrame.BackgroundTransparency = 0.15
	corner(moneyFrame, 10)
	padding(moneyFrame, 6)
	moneyFrame.Parent = gui

	moneyLabel = makeLabel({
		Size = UDim2.fromScale(1, 1),
		TextColor3 = MONEY_COLOR,
		Text = "$0",
		Parent = moneyFrame,
	})

	-- Panel de inventario --------------------------------------------------
	panel = Instance.new("Frame")
	panel.Name = "Inventory"
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.Position = UDim2.new(0, 12, 1, -12)
	panel.Size = UDim2.fromOffset(320, 400)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.BackgroundTransparency = 0.1
	corner(panel, 10)
	padding(panel, 10)
	panel.Parent = gui

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(320, 400)
	sizeConstraint.Parent = panel

	makeLabel({
		Size = UDim2.new(1, 0, 0, 26),
		Text = "Inventario  (tecla I)",
		Parent = panel,
	})

	makeLabel({
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(180, 220, 255),
		Text = "Semillas",
		Parent = panel,
	})
	seedList = makeList(panel, "Seeds", UDim2.fromOffset(0, 56), UDim2.new(1, 0, 0, 130))

	makeLabel({
		Position = UDim2.fromOffset(0, 192),
		Size = UDim2.new(1, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(255, 220, 150),
		Text = "Frutos",
		Parent = panel,
	})
	fruitList = makeList(panel, "Fruits", UDim2.fromOffset(0, 216), UDim2.new(1, 0, 0, 90))

	fruitTotalLabel = makeLabel({
		Position = UDim2.fromOffset(0, 310),
		Size = UDim2.new(1, 0, 0, 18),
		TextColor3 = Color3.fromRGB(200, 200, 200),
		Font = Enum.Font.Gotham,
		Text = "",
		Parent = panel,
	})

	plantButton = Instance.new("TextButton")
	plantButton.Name = "PlantButton"
	plantButton.AnchorPoint = Vector2.new(0, 1)
	plantButton.Position = UDim2.fromScale(0, 1)
	plantButton.Size = UDim2.new(1, 0, 0, 40)
	plantButton.Font = Enum.Font.GothamBold
	plantButton.TextScaled = true
	plantButton.TextColor3 = TEXT_COLOR
	corner(plantButton, 8)
	padding(plantButton, 6)
	plantButton.Activated:Connect(function()
		if selectedSeedId and plantCallback then
			plantCallback(selectedSeedId)
		end
	end)
	plantButton.Parent = panel

	-- Avisos ---------------------------------------------------------------
	notifyLabel = makeLabel({
		Name = "Notification",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 60),
		Size = UDim2.fromOffset(500, 32),
		TextStrokeTransparency = 0.3,
		Visible = false,
		Parent = gui,
	})

	-- Tecla I para mostrar/ocultar el inventario.
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.I then
			panel.Visible = not panel.Visible
		end
	end)

	gui.Parent = playerGui
	rebuildLists()
end

--------------------------------------------------------------------------------
-- API pública
--------------------------------------------------------------------------------

function HUD.init()
	build()
end

function HUD.setMoney(amount: number)
	moneyLabel.Text = `${amount}`
end

function HUD.setInventory(inventory: Inventory)
	currentInventory = inventory
	rebuildLists()
end

-- Registra la función a la que se llama al pulsar "Plantar".
function HUD.onPlant(callback: (seedId: string) -> ())
	plantCallback = callback
end

-- Muestra un aviso durante unos segundos.
function HUD.notify(message: string, color: Color3?)
	notifyToken += 1
	local token = notifyToken
	notifyLabel.Text = message
	notifyLabel.TextColor3 = color or TEXT_COLOR
	notifyLabel.Visible = true
	task.delay(3, function()
		if notifyToken == token then
			notifyLabel.Visible = false
		end
	end)
end

return HUD
