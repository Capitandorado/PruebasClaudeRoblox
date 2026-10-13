-- Pedestal interaction: tap/click a pedestal to inspect it, place or remove artifacts.
-- Works with mouse and touch (a tap is a short press that barely moved, so camera drags
-- never trigger it). All changes are requests; the server decides.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PlotConfig = require(Shared.Config.Plot)
local Rarities = require(Shared.Config.Rarities)
local Artifacts = require(Shared.Config.Artifacts)
local Format = require(Shared.Util.Format)
local Build = require(Shared.Util.Build)
local Items = require(Shared.Logic.Items)
local Effects = require(Shared.Logic.Effects)

local Client = script.Parent.Parent
local Remote = require(Client.Core.Remote)
local Store = require(Client.Core.Store)
local Sound = require(Client.Core.Sound)
local App = require(Client.UI.App)
local FactoryView = require(script.Parent.FactoryView)
local Theme = require(Client.UI.Theme)
local C = require(Client.UI.Components)

local Placement = {}

local Colors = Theme.Colors

Placement.activeKey = nil :: string?
local markers: { BasePart } = {}
local hudRef: any = nil

function Placement.setHud(hud: any)
	hudRef = hud
end

local function plotsFolder(): Instance?
	local root = workspace:FindFirstChild("VoidFactory")
	return root and root:FindFirstChild("Plots")
end

local function ownPlot(): Model?
	local plots = plotsFolder()
	return plots and plots:FindFirstChild("Plot_" .. Store.plot) :: Model?
end

local function clearMarkers()
	for _, marker in markers do
		marker:Destroy()
	end
	table.clear(markers)
end

local function showMarkers()
	clearMarkers()
	local plot = ownPlot()
	local profile = Store.profile
	if not plot or not profile then
		return
	end
	local slots = plot:FindFirstChild("Slots")
	for slot = 1, PlotConfig.TotalSlots do
		if PlotConfig.isSlotUnlocked(slot, profile.expansion) then
			local pedestal = slots and slots:FindFirstChild("Slot_" .. slot)
			local ring = pedestal and pedestal:FindFirstChild("Ring")
			if ring and ring:IsA("BasePart") then
				local occupied = profile.placed[tostring(slot)] ~= nil
				local marker = Build.part({
					Name = "PlacementMarker",
					Size = Vector3.new(0.4, 6, 6),
					CFrame = ring.CFrame * CFrame.new(0.3, 0, 0),
					Shape = Enum.PartType.Cylinder,
					Color = if occupied then Colors.Warning else Colors.Good,
					Material = Enum.Material.Neon,
					Transparency = 0.35,
					Parent = workspace,
				})
				marker.CanQuery = false
				table.insert(markers, marker)
			end
		end
	end
end

function Placement.cancel()
	Placement.activeKey = nil
	clearMarkers()
	FactoryView.preview(nil)
	if hudRef then
		hudRef.showPlacement(nil)
	end
end

-- Enters placement mode for an inventory item.
function Placement.begin(key: string)
	local item = Items.parse(key)
	if not item then
		return
	end
	Placement.activeKey = key
	App.closeWindow()
	showMarkers()
	FactoryView.preview(key)
	if hudRef then
		hudRef.showPlacement(
			"Tap a pedestal to place " .. Items.displayName(item) .. " — labels show the Energy/s change",
			Placement.cancel
		)
	end
end

function Placement.place(slot: number, key: string): boolean
	local response = Remote.request("Place", slot, key)
	if not response.ok then
		App.showError(response.err)
		return false
	end
	Sound.play("Place")
	local item = Items.parse(key)
	if item then
		App.toast("Placed " .. Items.displayName(item), "success")
	end
	return true
end

function Placement.remove(slot: number): boolean
	local response = Remote.request("Remove", slot)
	if not response.ok then
		App.showError(response.err)
		return false
	end
	Sound.play("UIClick")
	return true
end

-- Popup with pedestal details --------------------------------------------------------

local function closePopup()
	local overlay = App.layers.Overlay
	local popup = overlay and overlay:FindFirstChild("SlotPopup")
	if popup then
		popup:Destroy()
	end
end
Placement.closePopup = closePopup

local function describeSlot(key: string, slot: number, own: boolean): { string }
	local lines = {}
	local item = Items.parse(key)
	if not item then
		return lines
	end
	local artifact = Artifacts.get(item.id)
	if own then
		local production = Store.production()
		local eps = production and production.perSlot[slot] or 0
		table.insert(lines, "Output: ⚡ " .. Format.number(eps) .. "/s")
		local bonus = production and production.slotBonus[slot] or 0
		if math.abs(bonus) > 1e-9 then
			table.insert(lines, string.format("Neighbour bonus: %+d%%", math.floor(bonus * 100 + 0.5)))
		end
	else
		table.insert(lines, "Base output: ⚡ " .. Format.number(Items.baseEps(item)) .. "/s")
	end
	if artifact then
		for _, effect in artifact.effects do
			table.insert(lines, "• " .. Effects.name(effect.type) .. ": " .. Effects.describe(effect))
		end
	end
	return lines
end

function Placement.openPopup(slot: number, key: string?, own: boolean, locked: boolean?)
	closePopup()
	local overlay = App.layers.Overlay
	if not overlay then
		return
	end
	local popup = C.panel({
		Name = "SlotPopup",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -160),
		Size = UDim2.fromOffset(420, 200),
		Parent = overlay,
	})
	C.padding(12).Parent = popup
	local item = key and Items.parse(key)
	local rarity = item and Rarities.get(Items.rarityOf(item))
	local title = if item then Items.displayName(item) elseif locked then "Locked pedestal" else "Empty pedestal"
	C.text({
		Name = "Title",
		Text = title,
		FontFace = Theme.Fonts.Bold,
		TextSize = 22,
		TextColor3 = if rarity then rarity.color else Colors.Text,
		Size = UDim2.new(1, -40, 0, 28),
		Parent = popup,
	})
	C.button({
		name = "Close",
		text = "X",
		color = Colors.PanelLight,
		size = UDim2.fromOffset(30, 30),
		position = UDim2.new(1, -30, 0, 0),
		textSize = 16,
		parent = popup,
		onClick = closePopup,
	})
	local lines = if item and key
		then describeSlot(key, slot, own)
		elseif locked then { "Buy a plot expansion to unlock more pedestals." }
		else { "Place an artifact here to produce Energy." }
	if rarity then
		table.insert(lines, 1, rarity.id .. "  •  pedestal " .. slot)
	end
	C.text({
		Name = "Body",
		Text = table.concat(lines, "\n"),
		TextSize = 15,
		TextColor3 = Colors.TextDim,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, 0, 1, -80),
		Position = UDim2.fromOffset(0, 32),
		Parent = popup,
	})
	if own and not locked then
		local row = C.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 40),
			Position = UDim2.new(0, 0, 1, -40),
			Parent = popup,
		})
		C.list(Enum.FillDirection.Horizontal, 8).Parent = row
		if item then
			C.button({
				name = "Remove",
				text = "Take back",
				color = Colors.Bad,
				size = UDim2.fromOffset(130, 38),
				textSize = 16,
				parent = row,
				onClick = function()
					if Placement.remove(slot) then
						closePopup()
					end
				end,
			})
		end
		C.button({
			name = "Choose",
			text = if item then "Swap" else "Choose artifact",
			color = Colors.Accent2,
			size = UDim2.fromOffset(170, 38),
			textSize = 16,
			parent = row,
			onClick = function()
				closePopup()
				App.openWindow("Inventory", { pickForSlot = slot })
			end,
		})
	elseif locked then
		local button = C.button({
			name = "Expand",
			text = "Open expansions",
			color = Colors.Accent2,
			size = UDim2.fromOffset(170, 38),
			position = UDim2.new(0, 0, 1, -40),
			textSize = 16,
			parent = popup,
			onClick = function()
				closePopup()
				App.openWindow("Shop", { tab = "Expansion" })
			end,
		})
		button.Name = "Expand"
	end
end

-- Input -------------------------------------------------------------------------------

local function raycastPedestal(screenPosition: Vector3): BasePart?
	local camera = workspace.CurrentCamera
	local plots = plotsFolder()
	if not camera or not plots then
		return nil
	end
	local ray = camera:ScreenPointToRay(screenPosition.X, screenPosition.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { plots }
	local result = workspace:Raycast(ray.Origin, ray.Direction * 400, params)
	if not result then
		return nil
	end
	-- The ray hits the pedestal's visible parts (base, ring, artifact); walk up to its slot.
	local current: Instance? = result.Instance
	while current and current ~= plots do
		if string.match(current.Name, "^Slot_%d+$") then
			local hitbox = current:FindFirstChild("Hitbox")
			return if hitbox and hitbox:IsA("BasePart") then hitbox else nil
		end
		current = current.Parent
	end
	return nil
end

-- Handles a click on a pedestal hitbox (also used by tests).
function Placement.handlePedestal(hitbox: BasePart)
	local slot = hitbox:GetAttribute("SlotIndex") :: number
	local plotIndex = hitbox:GetAttribute("PlotIndex") :: number
	local own = plotIndex == Store.plot
	local locked = hitbox:GetAttribute("Locked") == true
	local key = hitbox:GetAttribute("ItemKey") :: string?
	if Placement.activeKey then
		if not own then
			App.toast("You can only build on your own plot.", "warning")
			return
		end
		if locked then
			App.toast("That pedestal is locked. Expand your plot!", "warning")
			return
		end
		local placing = Placement.activeKey :: string
		if Placement.place(slot, placing) then
			Placement.cancel()
		end
		return
	end
	Placement.openPopup(slot, key, own, locked)
end

function Placement.start()
	local pressStart: Vector3? = nil
	local pressTime = 0
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			pressStart = input.Position
			pressTime = os.clock()
		end
	end)
	UserInputService.InputEnded:Connect(function(input, processed)
		if processed or not pressStart then
			return
		end
		if
			input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end
		local moved = (input.Position - pressStart).Magnitude
		pressStart = nil
		if moved > 14 or os.clock() - pressTime > 0.5 then
			return
		end
		local hitbox = raycastPedestal(input.Position)
		if hitbox then
			Placement.handlePedestal(hitbox)
		end
	end)
	-- Roblox keeps Esc for its own menu, so placement also cancels with Q / Backspace /
	-- gamepad B, and whenever the Roblox menu opens. The banner has a Cancel button too.
	local cancelKeys = {
		[Enum.KeyCode.Escape] = true,
		[Enum.KeyCode.Q] = true,
		[Enum.KeyCode.Backspace] = true,
		[Enum.KeyCode.ButtonB] = true,
	}
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and cancelKeys[input.KeyCode] then
			Placement.cancel()
			closePopup()
		end
	end)
	GuiService.MenuOpened:Connect(function()
		Placement.cancel()
		closePopup()
	end)
	-- Markers follow the profile while in placement mode.
	Store.watch({ "placed", "expansion" }, function()
		if Placement.activeKey then
			showMarkers()
		end
	end)
	RunService.RenderStepped:Connect(function()
		if #markers > 0 then
			local alpha = 0.3 + math.abs(math.sin(os.clock() * 3)) * 0.4
			for _, marker in markers do
				marker.Transparency = alpha
			end
		end
	end)
end

return Placement
