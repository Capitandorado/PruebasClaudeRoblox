-- Exports the real client GUI (built by the game's UI code in the mock runtime) for several
-- scenes, so tools/preview/render_ui.py can draw approximate screenshots.
--   lune run tools/preview/export_ui.luau build/ui.json

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local Fixture = require("../../tests/lib/Fixture")
local Instance = require("../../tests/mock/Instance")

local out = process.args[1] or "build/ui.json"

local function enumName(value)
	return tostring(value):match("%.(%w+)$")
end

local function udim2(value)
	return { value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset }
end

local function color(value)
	return { value.R, value.G, value.B }
end

local function export(inst)
	local node = { class = inst.ClassName, name = inst.Name, children = {} }
	if inst:IsA("GuiObject") then
		node.visible = inst.Visible
		node.size = udim2(inst.Size)
		node.pos = udim2(inst.Position)
		node.anchor = { inst.AnchorPoint.X, inst.AnchorPoint.Y }
		node.bg = color(inst.BackgroundColor3)
		node.bgT = inst.BackgroundTransparency
		node.z = inst.ZIndex
		node.order = inst.LayoutOrder
		node.clips = inst.ClipsDescendants or inst:IsA("ScrollingFrame")
		if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
			node.text = inst.Text
			node.textColor = color(inst.TextColor3)
			node.textT = inst.TextTransparency
			node.textSize = inst.TextSize
			node.textScaled = inst.TextScaled
			node.wrapped = inst.TextWrapped
			node.xAlign = enumName(inst.TextXAlignment)
			node.yAlign = enumName(inst.TextYAlignment)
		end
	elseif inst:IsA("LayerCollector") then
		node.visible = inst.Enabled
	end
	for _, child in inst:GetChildren() do
		if child:IsA("UIListLayout") then
			node.layout = {
				type = "list",
				fill = enumName(child.FillDirection),
				padding = { child.Padding.Scale, child.Padding.Offset },
				hAlign = enumName(child.HorizontalAlignment),
				vAlign = enumName(child.VerticalAlignment),
			}
		elseif child:IsA("UIGridLayout") then
			node.layout = {
				type = "grid",
				fill = enumName(child.FillDirection),
				cell = udim2(child.CellSize),
				cellPad = udim2(child.CellPadding),
				maxCells = child.FillDirectionMaxCells,
				hAlign = enumName(child.HorizontalAlignment),
				vAlign = enumName(child.VerticalAlignment),
			}
		elseif child:IsA("UIPadding") then
			node.padding = { child.PaddingTop.Offset, child.PaddingBottom.Offset, child.PaddingLeft.Offset, child.PaddingRight.Offset }
		elseif child:IsA("UICorner") then
			node.corner = child.CornerRadius.Offset
		elseif child:IsA("UIStroke") then
			node.stroke = { color = color(child.Color), thickness = child.Thickness, t = child.Transparency }
		elseif child:IsA("UIScale") then
			node.scale = child.Scale
		elseif child:IsA("UISizeConstraint") then
			node.maxSize = { child.MaxSize.X, child.MaxSize.Y }
		elseif child:IsA("GuiObject") then
			table.insert(node.children, export(child))
		end
	end
	return node
end

local scenes = {}

local function scene(name, viewport, setup)
	local rt = Fixture.server({ isStudio = true })
	Instance.setInternal(rt.camera, "ViewportSize", roblox.Vector2.new(viewport[1], viewport[2]))
	local player = Fixture.join(rt, { userId = 4242, name = "Builder", noClient = false })
	rt:run(1, 0.1)
	local ui = player.PlayerGui:FindFirstChild("VoidFactoryUI")
	if setup then
		setup(rt, player, ui)
	end
	rt:run(0.6, 0.05)
	table.insert(scenes, { name = name, viewport = viewport, tree = export(ui) })
	if #rt:errors() > 0 then
		print("errors in scene " .. name .. ": " .. rt:errors()[1].trace)
	end
end

local function progress(rt, player)
	for _, key in { "reactor_core||1", "gravity_well||1", "ion_battery|Gold|2", "scrap_cube||1", "prism_lens||1" } do
		Fixture.request(rt, player, "Admin", "give", key)
	end
	Fixture.request(rt, player, "Admin", "give", "scrap_cube||1")
	Fixture.request(rt, player, "Place", 1, "reactor_core||1")
	Fixture.request(rt, player, "Place", 2, "gravity_well||1")
	Fixture.request(rt, player, "Admin", "energy", 45000)
	Fixture.request(rt, player, "OpenBox", "starter_fabricator")
	rt:run(0.5, 0.1)
end

local function openWindow(name, tab)
	return function(rt, player, ui)
		progress(rt, player)
		rt:click(rt:findDescendant(ui, name .. "Button"))
		rt:run(0.5, 0.1)
		if tab then
			rt:click(rt:findDescendant(rt:findDescendant(ui, "Window_" .. name), tab .. "Tab"))
			rt:run(0.3, 0.1)
		end
		if name == "Inventory" then
			local window = rt:findDescendant(ui, "Window_Inventory")
			local card = rt:findDescendant(window, "reactor_core||1") or rt:findDescendant(window, "prism_lens||1")
			if card then
				rt:click(card)
			end
		end
	end
end

scene("hud_new_player_desktop", { 1280, 720 }, nil)
scene("hud_desktop", { 1280, 720 }, progress)
scene("hud_phone", { 812, 375 }, progress)
scene("reveal_desktop", { 1280, 720 }, function(rt, player, ui)
	progress(rt, player)
	rt:click(rt:findDescendant(ui, "OpenButton"))
	rt:run(1.0, 1 / 30)
end)
for _, entry in {
	{ "Inventory" },
	{ "Collection" },
	{ "Collection", "Odds" },
	{ "Shop" },
	{ "Upgrades" },
	{ "Quests" },
	{ "Rebirth" },
	{ "Leaderboard" },
	{ "Settings" },
	{ "Admin" },
} do
	scene("window_" .. entry[1] .. (entry[2] and ("_" .. entry[2]) or ""), { 1280, 720 }, openWindow(entry[1], entry[2]))
end
scene("window_Inventory_phone", { 812, 375 }, openWindow("Inventory"))
scene("window_Shop_phone", { 812, 375 }, openWindow("Shop"))

fs.writeFile(out, serde.encode("json", { scenes = scenes }))
print(string.format("exported %d UI scenes -> %s", #scenes, out))
