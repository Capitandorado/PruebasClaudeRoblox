-- Visual identity of the interface: deep-space panels, neon accents, rounded shapes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Assets = require(ReplicatedStorage:WaitForChild("Shared").Config.Assets)

local Theme = {}

Theme.Colors = {
	Background = Color3.fromRGB(14, 12, 28),
	Panel = Color3.fromRGB(24, 22, 44),
	PanelLight = Color3.fromRGB(36, 33, 64),
	Card = Color3.fromRGB(31, 29, 56),
	CardHover = Color3.fromRGB(44, 40, 78),
	Stroke = Color3.fromRGB(90, 80, 160),
	Text = Color3.fromRGB(240, 238, 255),
	TextDim = Color3.fromRGB(165, 160, 200),
	Accent = Color3.fromRGB(90, 220, 255),
	Accent2 = Color3.fromRGB(175, 95, 255),
	Energy = Color3.fromRGB(255, 214, 70),
	Shards = Color3.fromRGB(200, 120, 255),
	Good = Color3.fromRGB(90, 230, 140),
	Warning = Color3.fromRGB(255, 180, 60),
	Bad = Color3.fromRGB(255, 80, 100),
	Disabled = Color3.fromRGB(70, 68, 92),
}

Theme.Fonts = {
	-- Window titles, banners, rarity names: chunky cartoon capitals.
	Display = Font.new(Assets.Fonts.Title, Enum.FontWeight.Regular),
	Title = Font.new(Assets.Fonts.Title, Enum.FontWeight.Regular),
	-- Numbers, buttons and names: round and bold.
	Bold = Font.new(Assets.Fonts.Cartoon, Enum.FontWeight.Regular),
	Number = Font.new(Assets.Fonts.Cartoon, Enum.FontWeight.Regular),
	-- Body text stays in a plain readable font.
	SemiBold = Font.new(Assets.Fonts.UI, Enum.FontWeight.Bold),
	Regular = Font.new(Assets.Fonts.UI, Enum.FontWeight.Medium),
}

-- Thick dark outline for text and borders ("candy" style).
Theme.Outline = Color3.fromRGB(24, 12, 40)

Theme.Corner = 14
Theme.SmallCorner = 10
Theme.CandyCorner = 18
-- Design resolution: the whole UI is authored for this size and scaled with UIScale.
Theme.DesignSize = Vector2.new(1280, 720)

return Theme
