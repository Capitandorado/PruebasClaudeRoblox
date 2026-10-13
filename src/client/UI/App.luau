-- Root of the interface: ScreenGui, responsive scaling, window manager, toasts and the
-- announcement banner. Windows live in UI/Windows and register themselves here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Messages = require(Shared.Config.Messages)
local Signal = require(Shared.Util.Signal)

local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local Sound = require(script.Parent.Parent.Core.Sound)

local App = {}

App.WindowChanged = Signal.new()
App.VisitChanged = Signal.new() -- (name: string?) while visiting another factory

App.gui = nil :: ScreenGui?
App.layers = {} :: { [string]: Frame }

local Colors = Theme.Colors

export type WindowHandle = {
	frame: Frame,
	refresh: (() -> ())?,
	onOpen: ((args: any) -> ())?,
	onClose: (() -> ())?,
}

export type WindowDef = {
	name: string,
	title: string,
	icon: string,
	size: Vector2?,
	build: (content: Frame, app: any) -> WindowHandle,
}

local windowDefs: { [string]: WindowDef } = {}
local windowHandles: { [string]: WindowHandle } = {}
local windowFrames: { [string]: Frame } = {}
local openWindow: string? = nil

local function computeScale(viewport: Vector2): number
	local scale = math.min(viewport.X / Theme.DesignSize.X, viewport.Y / Theme.DesignSize.Y)
	return math.clamp(scale, 0.55, 1.3)
end

function App.isNarrow(): boolean
	local camera = workspace.CurrentCamera
	return camera ~= nil and camera.ViewportSize.X < 900
end

local function layer(name: string, zIndex: number): Frame
	local frame = C.new("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = zIndex,
		Parent = App.gui,
	})
	App.layers[name] = frame
	return frame
end

function App.start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = C.new("ScreenGui", {
		Name = "VoidFactoryUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	App.gui = gui
	local uiScale = C.new("UIScale", { Parent = gui })
	local camera = workspace.CurrentCamera
	local function rescale()
		if camera then
			uiScale.Scale = computeScale(camera.ViewportSize)
		end
	end
	rescale()
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	end
	layer("Hud", 1)
	layer("Windows", 5)
	layer("Overlay", 10)
	local toasts = C.new("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 118),
		Size = UDim2.fromOffset(300, 320),
		BackgroundTransparency = 1,
		Parent = App.layers.Overlay,
	})
	C.list(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Right).Parent = toasts
	gui.Parent = playerGui
end

-- Toasts --------------------------------------------------------------------------------

local TOAST_COLORS = {
	info = Colors.Accent,
	success = Colors.Good,
	warning = Colors.Warning,
	error = Colors.Bad,
}

function App.toast(text: string, kind: string?)
	local overlay = App.layers.Overlay
	local container = overlay and overlay:FindFirstChild("Toasts")
	if not container then
		return
	end
	local color = TOAST_COLORS[kind or "info"] or Colors.Accent
	local existing = {}
	for _, child in container:GetChildren() do
		if child:IsA("Frame") then
			table.insert(existing, child)
		end
	end
	if #existing >= 4 then
		existing[1]:Destroy()
	end
	local toast = C.panel({
		Name = "Toast",
		Size = UDim2.fromOffset(300, 46),
		BackgroundColor3 = Colors.Panel,
		Parent = container,
	})
	C.new("Frame", {
		Size = UDim2.new(0, 5, 1, -12),
		Position = UDim2.fromOffset(6, 6),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Children = { C.corner(3) },
		Parent = toast,
	})
	C.text({
		Name = "Text",
		Text = text,
		TextSize = 16,
		Size = UDim2.new(1, -24, 1, 0),
		Position = UDim2.fromOffset(18, 0),
		Parent = toast,
	})
	local scale = C.new("UIScale", { Scale = 0.6, Parent = toast })
	C.tween(scale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(3.2, function()
		if toast.Parent then
			C.tween(scale, 0.15, { Scale = 0.01 })
			task.wait(0.16)
			toast:Destroy()
		end
	end)
end

-- Shows the friendly message for a failed server response.
function App.showError(err: string?)
	App.toast(Messages[err or ""] or Messages.ServerError, "error")
	Sound.play("Error")
end

-- Windows -------------------------------------------------------------------------------

function App.registerWindow(def: WindowDef)
	windowDefs[def.name] = def
end

local function buildWindow(name: string): Frame
	local def = windowDefs[name]
	local size = def.size or Vector2.new(560, 460)
	local frame = C.panel({
		Name = "Window_" .. name,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 10),
		Size = UDim2.fromOffset(size.X, size.Y),
		Visible = false,
		BackgroundColor3 = Colors.Panel,
		Parent = App.layers.Windows,
	})
	C.gradient(Color3.fromRGB(255, 255, 255), Color3.fromRGB(205, 200, 235)).Parent = frame
	C.new("UISizeConstraint", { MaxSize = Vector2.new(size.X, size.Y) }).Parent = frame
	C.new("UIScale", { Name = "PopScale", Parent = frame })
	local header = C.new("Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 52),
		Parent = frame,
	})
	C.text({
		Name = "Title",
		Text = def.icon .. "  " .. string.upper(def.title),
		FontFace = Theme.Fonts.Display,
		TextSize = 20,
		Size = UDim2.new(1, -70, 1, 0),
		Position = UDim2.fromOffset(18, 0),
		Parent = header,
	})
	C.button({
		name = "Close",
		text = "✕",
		color = Colors.Bad,
		size = UDim2.fromOffset(36, 36),
		position = UDim2.new(1, -46, 0, 8),
		textSize = 18,
		parent = header,
		onClick = function()
			App.closeWindow()
		end,
	})
	local content = C.new("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 54),
		Size = UDim2.new(1, -28, 1, -66),
		ClipsDescendants = true,
		Parent = frame,
	})
	windowHandles[name] = def.build(content, App)
	windowFrames[name] = frame
	return frame
end

function App.openWindow(name: string, args: any?)
	if not windowDefs[name] then
		return
	end
	if openWindow and openWindow ~= name then
		App.closeWindow(true)
	end
	local frame = windowFrames[name] or buildWindow(name)
	local handle = windowHandles[name]
	openWindow = name
	frame.Visible = true
	local popScale = frame:FindFirstChild("PopScale") :: UIScale
	popScale.Scale = 0.85
	C.tween(popScale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
	if handle.onOpen then
		handle.onOpen(args)
	end
	if handle.refresh then
		handle.refresh()
	end
	Sound.play("UIClick")
	App.WindowChanged:Fire(name)
end

function App.closeWindow(silent: boolean?)
	if not openWindow then
		return
	end
	local name = openWindow
	openWindow = nil
	local frame = windowFrames[name]
	local handle = windowHandles[name]
	if frame then
		frame.Visible = false
	end
	if handle and handle.onClose then
		handle.onClose()
	end
	if not silent then
		App.WindowChanged:Fire(nil)
	end
end

function App.toggleWindow(name: string)
	if openWindow == name then
		App.closeWindow()
	else
		App.openWindow(name)
	end
end

function App.currentWindow(): string?
	return openWindow
end

function App.refreshWindow(name: string?)
	local target = name or openWindow
	if target and target == openWindow then
		local handle = windowHandles[target]
		if handle and handle.refresh then
			handle.refresh()
		end
	end
end

function App.windowFrame(name: string): Frame?
	return windowFrames[name]
end

return App
