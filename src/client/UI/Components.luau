-- Tiny UI toolkit: declarative instance creation plus the reusable widgets of the game.

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local C = {}

local Colors = Theme.Colors

-- Creates an instance, assigns properties and parents children.
-- Special keys: Children = { Instance }, Events = { EventName = fn }.
function C.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className :: any)
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			elseif key == "Children" then
				for _, child in value do
					child.Parent = instance
				end
			elseif key == "Events" then
				for eventName, handler in value do
					(instance :: any)[eventName]:Connect(handler)
				end
			else
				(instance :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function C.corner(radius: number?): UICorner
	return C.new("UICorner", { CornerRadius = UDim.new(0, radius or Theme.Corner) })
end

function C.stroke(color: Color3?, thickness: number?, transparency: number?): UIStroke
	return C.new("UIStroke", {
		Color = color or Colors.Stroke,
		Thickness = thickness or 1.5,
		Transparency = transparency or 0.2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function C.padding(all: number, horizontal: number?): UIPadding
	local h = horizontal or all
	return C.new("UIPadding", {
		PaddingTop = UDim.new(0, all),
		PaddingBottom = UDim.new(0, all),
		PaddingLeft = UDim.new(0, h),
		PaddingRight = UDim.new(0, h),
	})
end

function C.list(direction: Enum.FillDirection?, spacing: number?, align: Enum.HorizontalAlignment?): UIListLayout
	return C.new("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, spacing or 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
	})
end

function C.gradient(top: Color3, bottom: Color3, rotation: number?): UIGradient
	return C.new("UIGradient", {
		Color = ColorSequence.new(top, bottom),
		Rotation = rotation or 90,
	})
end

function C.text(props: { [string]: any }): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		TextColor3 = Colors.Text,
		FontFace = Theme.Fonts.SemiBold,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 22),
	}
	for key, value in props do
		defaults[key] = value
	end
	return C.new("TextLabel", defaults)
end

function C.tween(
	instance: Instance,
	time: number,
	goals: { [string]: any },
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
): Tween
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		goals
	)
	tween:Play()
	return tween
end

export type ButtonOptions = {
	text: string,
	color: Color3?,
	textColor: Color3?,
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	textSize: number?,
	font: Font?,
	name: string?,
	layoutOrder: number?,
	onClick: (() -> ())?,
	parent: Instance?,
}

-- Rounded button with hover/press feedback. `button:SetAttribute("Disabled", true)` greys it out.
function C.button(options: ButtonOptions): TextButton
	local color = options.color or Colors.Accent2
	local button: TextButton = C.new("TextButton", {
		Name = options.name or "Button",
		Size = options.size or UDim2.fromOffset(140, 40),
		Position = options.position or UDim2.new(),
		AnchorPoint = options.anchor or Vector2.zero,
		BackgroundColor3 = color,
		AutoButtonColor = false,
		Text = options.text,
		TextColor3 = options.textColor or Colors.Text,
		FontFace = options.font or Theme.Fonts.Bold,
		TextSize = options.textSize or 18,
		TextWrapped = true,
		LayoutOrder = options.layoutOrder or 0,
		Children = {
			C.corner(Theme.SmallCorner),
			C.gradient(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 210)),
		},
	})
	local scale = C.new("UIScale", { Parent = button })
	button:SetAttribute("BaseColor", color)
	local function refreshColor(hovered: boolean)
		local disabled = button:GetAttribute("Disabled") == true
		local base = button:GetAttribute("BaseColor") or color
		button.BackgroundColor3 = if disabled
			then Colors.Disabled
			elseif hovered then base:Lerp(Color3.new(1, 1, 1), 0.15)
			else base
		button.TextTransparency = if disabled then 0.35 else 0
	end
	button.MouseEnter:Connect(function()
		refreshColor(true)
	end)
	button.MouseLeave:Connect(function()
		refreshColor(false)
		C.tween(scale, 0.1, { Scale = 1 })
	end)
	button.MouseButton1Down:Connect(function()
		C.tween(scale, 0.08, { Scale = 0.94 })
	end)
	button.MouseButton1Up:Connect(function()
		C.tween(scale, 0.12, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	button:GetAttributeChangedSignal("Disabled"):Connect(function()
		refreshColor(false)
	end)
	button:GetAttributeChangedSignal("BaseColor"):Connect(function()
		refreshColor(false)
	end)
	if options.onClick then
		local onClick = options.onClick
		button.Activated:Connect(function()
			if button:GetAttribute("Disabled") ~= true then
				onClick()
			end
		end)
	end
	if options.parent then
		button.Parent = options.parent
	end
	return button
end

-- Connects a click handler that respects the "Disabled" attribute.
function C.onClick(button: TextButton, handler: () -> ())
	button.Activated:Connect(function()
		if button:GetAttribute("Disabled") ~= true then
			handler()
		end
	end)
end

function C.setButton(button: TextButton, text: string?, enabled: boolean?, color: Color3?)
	if text then
		button.Text = text
	end
	if color then
		button:SetAttribute("BaseColor", color)
	end
	if enabled ~= nil then
		button:SetAttribute("Disabled", not enabled)
	end
end

function C.panel(props: { [string]: any }): Frame
	local defaults = {
		BackgroundColor3 = Colors.Panel,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
	}
	for key, value in props do
		defaults[key] = value
	end
	local frame = C.new("Frame", defaults)
	C.corner().Parent = frame
	C.stroke().Parent = frame
	return frame
end

-- Horizontal progress bar; returns the container and a setter(alpha, color?).
function C.progress(props: { [string]: any }): (Frame, (alpha: number, color: Color3?) -> ())
	local defaults = {
		BackgroundColor3 = Color3.fromRGB(10, 8, 22),
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 10),
	}
	for key, value in props do
		defaults[key] = value
	end
	local bar = C.new("Frame", defaults)
	C.corner(6).Parent = bar
	local fill = C.new("Frame", {
		Name = "Fill",
		BackgroundColor3 = Colors.Accent,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Parent = bar,
	})
	C.corner(6).Parent = fill
	local function set(alpha: number, color: Color3?)
		fill.Size = UDim2.fromScale(math.clamp(alpha, 0, 1), 1)
		if color then
			fill.BackgroundColor3 = color
		end
	end
	return bar, set
end

function C.scroll(props: { [string]: any }): ScrollingFrame
	local defaults = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Colors.Stroke,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Size = UDim2.fromScale(1, 1),
	}
	for key, value in props do
		defaults[key] = value
	end
	return C.new("ScrollingFrame", defaults)
end

-- Toggle switch; returns the frame and a setter.
function C.toggle(label: string, initial: boolean, onChange: (boolean) -> ()): (Frame, (boolean) -> ())
	local row = C.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36) })
	C.text({ Text = label, Size = UDim2.new(1, -70, 1, 0), Parent = row })
	local track = C.new("TextButton", {
		Name = "Toggle",
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(54, 28),
		Position = UDim2.new(1, -54, 0.5, -14),
		BackgroundColor3 = Colors.Disabled,
		Parent = row,
	})
	C.corner(14).Parent = track
	local knob = C.new("Frame", {
		Size = UDim2.fromOffset(22, 22),
		Position = UDim2.fromOffset(3, 3),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = track,
	})
	C.corner(11).Parent = knob
	local value = initial
	local function set(newValue: boolean)
		value = newValue
		track.BackgroundColor3 = if value then Colors.Good else Colors.Disabled
		C.tween(knob, 0.15, { Position = UDim2.fromOffset(if value then 29 else 3, 3) })
	end
	set(initial)
	track.Activated:Connect(function()
		set(not value)
		onChange(value)
	end)
	return row, set
end

-- Returns a function that runs `fn` at most once per `interval` seconds (trailing call kept).
function C.debounce(fn: () -> (), interval: number): () -> ()
	local scheduled = false
	local last = -math.huge
	return function()
		if scheduled then
			return
		end
		local wait = math.max(0, interval - (os.clock() - last))
		scheduled = true
		task.delay(wait, function()
			scheduled = false
			last = os.clock()
			fn()
		end)
	end
end

-- Runs `render` only when `signature()` changed since the last render (avoids rebuilding a
-- window every second when nothing visible changed).
function C.guarded(signature: () -> string, render: () -> ()): (force: boolean?) -> ()
	local last: string? = nil
	return function(force: boolean?)
		local current = signature()
		if force or current ~= last then
			last = current
			render()
		end
	end
end

function C.clear(container: Instance, keepLayouts: boolean?)
	for _, child in container:GetChildren() do
		if
			keepLayouts
			and (
				child:IsA("UIGridStyleLayout")
				or child:IsA("UIPadding")
				or child:IsA("UICorner")
				or child:IsA("UIStroke")
			)
		then
			continue
		end
		child:Destroy()
	end
end

return C
