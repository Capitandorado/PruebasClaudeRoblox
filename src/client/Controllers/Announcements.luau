-- Server-wide announcements for extraordinary finds and rebirths. Queued and shown one at
-- a time so they stand out without flooding the screen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rarities = require(Shared.Config.Rarities)
local Items = require(Shared.Logic.Items)

local Client = script.Parent.Parent
local Remote = require(Client.Core.Remote)
local App = require(Client.UI.App)
local Theme = require(Client.UI.Theme)
local C = require(Client.UI.Components)

local Announcements = {}

local MAX_QUEUE = 4
local SHOW_TIME = 3.6

local queue: { { text: string, color: Color3, secret: boolean } } = {}
local showing = false

local function show(entry: { text: string, color: Color3, secret: boolean })
	local overlay = App.layers.Overlay
	if not overlay then
		return
	end
	local banner = C.panel({
		Name = "Announcement",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -80),
		Size = UDim2.fromOffset(640, 58),
		BackgroundColor3 = if entry.secret then Color3.fromRGB(30, 0, 8) else Theme.Colors.Panel,
		Parent = overlay,
	})
	local stroke = banner:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = entry.color
		stroke.Thickness = 3
	end
	C.paint(banner, entry.color:Lerp(Theme.Colors.Panel, 0.7), Theme.Colors.Panel, 0)
	C.text({
		Name = "Text",
		Text = entry.text,
		FontFace = Theme.Fonts.Bold,
		TextSize = 20,
		TextColor3 = Theme.Colors.Text,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, -20, 1, 0),
		Position = UDim2.fromOffset(10, 0),
		Parent = banner,
	})
	C.tween(banner, 0.35, { Position = UDim2.new(0.5, 0, 0, 120) }, Enum.EasingStyle.Back)
	task.wait(SHOW_TIME)
	C.tween(banner, 0.25, { Position = UDim2.new(0.5, 0, 0, -80) })
	task.wait(0.26)
	banner:Destroy()
end

local function pump()
	if showing then
		return
	end
	showing = true
	task.spawn(function()
		while #queue > 0 do
			local entry = table.remove(queue, 1)
			if entry then
				show(entry)
			end
		end
		showing = false
	end)
end

function Announcements.push(text: string, color: Color3, secret: boolean?)
	if #queue >= MAX_QUEUE then
		table.remove(queue, 1)
	end
	table.insert(queue, { text = text, color = color, secret = secret == true })
	pump()
end

local function onAnnounce(payload: any)
	if type(payload) ~= "table" or type(payload.name) ~= "string" then
		return
	end
	if payload.rebirths then
		Announcements.push(
			string.format("♻ %s reached Rebirth %d!", payload.name, payload.rebirths),
			Theme.Colors.Shards
		)
		return
	end
	local item = Items.parse(payload.key)
	local rarity = item and Rarities.get(Items.rarityOf(item))
	if not item or not rarity then
		return
	end
	local prefix = if rarity.id == "Secret" then "‼️ SECRET" else "🌟 " .. string.upper(rarity.id)
	local text = string.format(
		"%s: %s found %s%s",
		prefix,
		payload.name,
		Items.displayName(item),
		if payload.newArtifact then " for the first time!" else "!"
	)
	Announcements.push(text, rarity.color, rarity.id == "Secret" or rarity.id == "Void")
end

function Announcements.start()
	Remote.NotifyReceived:Connect(function(kind, payload)
		if kind == "Announce" then
			onAnnounce(payload)
		end
	end)
end

return Announcements
