-- Robux store (Game Passes, boosts and packs) and promo codes. Purchases are prompted with
-- MarketplaceService; what they give is applied by the server (Services/Monetization).
-- Items whose id is still 0 are hidden on live servers and testable for free in Studio.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Monetization = require(Shared.Config.Monetization)
local Format = require(Shared.Util.Format)
local State = require(Shared.Logic.State)
local Purchases = require(Shared.Logic.Actions.Purchases)

local Client = script.Parent.Parent.Parent
local Remote = require(Client.Core.Remote)
local Store = require(Client.Core.Store)
local Sound = require(Client.Core.Sound)
local Theme = require(script.Parent.Parent.Theme)
local C = require(script.Parent.Parent.Components)
local Widgets = require(script.Parent.Parent.Widgets)

local Colors = Theme.Colors
local GOLD = Color3.fromRGB(255, 196, 64)
local DARK = Color3.fromRGB(60, 30, 0)

local prices: { [number]: string } = {}
local fetching: { [number]: boolean } = {}

local function available(id: number): boolean
	return id > 0 or RunService:IsStudio()
end

-- "R$ 199" once known (fetched once per id), "R$ …" meanwhile.
local function priceText(id: number, infoType: Enum.InfoType, onLoaded: () -> ()): string
	if id <= 0 then
		return "Test (Studio)"
	end
	if prices[id] then
		return prices[id]
	end
	if not fetching[id] then
		fetching[id] = true
		task.spawn(function()
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfoAsync(id, infoType)
			end)
			if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
				prices[id] = "R$ " .. Format.commas(info.PriceInRobux)
				onLoaded()
			else
				fetching[id] = nil
			end
		end)
	end
	return "R$ …"
end

return {
	name = "Store",
	title = "Store",
	icon = "🛒",
	size = Vector2.new(620, 470),
	build = function(content: Frame, app: any)
		local currentTab = "Passes"
		local header = C.text({
			Name = "Header",
			Text = "",
			TextSize = 14,
			TextColor3 = Colors.TextDim,
			Size = UDim2.new(1, 0, 0, 20),
			Position = UDim2.fromOffset(0, 40),
			Parent = content,
		})
		local list = C.scroll({
			Name = "List",
			Size = UDim2.new(1, 0, 1, -66),
			Position = UDim2.fromOffset(0, 66),
			Parent = content,
		})
		C.list(Enum.FillDirection.Vertical, 8).Parent = list
		C.padding(4).Parent = list
		local codesPage = C.new("Frame", {
			Name = "CodesPage",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, -66),
			Position = UDim2.fromOffset(0, 66),
			Visible = false,
			Parent = content,
		})

		local refresh: () -> ()

		local function buy(kind: string, key: string, id: number)
			Sound.play("UIClick")
			if id > 0 then
				local player = Players.LocalPlayer
				if kind == "pass" then
					MarketplaceService:PromptGamePassPurchase(player, id)
				else
					MarketplaceService:PromptProductPurchase(player, id)
				end
				return
			end
			local response = Remote.request("StudioPurchase", key)
			if not response.ok then
				app.showError(response.err)
			end
		end

		local function renderPasses(profile: any)
			header.Text = "Permanent upgrades for your factory. They keep working after rebirths."
			for order, pass in Monetization.Passes do
				if not available(pass.id) then
					continue
				end
				local owned = State.hasPass(profile, pass.key)
				local _, button = Widgets.row(list, {
					name = pass.key,
					title = pass.icon .. "  " .. pass.name,
					description = pass.description,
					accent = GOLD,
					layoutOrder = order,
				})
				if owned then
					C.setButton(button, "OWNED ✓", false, Colors.Good)
				else
					C.setButton(button, priceText(pass.id, Enum.InfoType.GamePass, refresh), true, GOLD)
					button.TextColor3 = DARK
					C.onClick(button, function()
						buy("pass", pass.key, pass.id)
					end)
				end
			end
		end

		local function renderProducts(profile: any)
			local active = {}
			for key, boost in Monetization.Boosts do
				local remaining = State.boostRemaining(profile, key)
				if remaining > 0 then
					table.insert(active, boost.icon .. " " .. boost.name .. " " .. Format.duration(remaining))
				end
			end
			header.Text = if #active > 0
				then "Active: " .. table.concat(active, "   •   ")
				else "Boosts run while you play and stack. Energy packs scale with your factory."
			for order, product in Monetization.Products do
				if not available(product.id) then
					continue
				end
				local description = product.description
				if product.kind == "energy" then
					description ..= "  Now: ⚡" .. Format.number(Purchases.energyFor(profile, product))
				end
				local _, button = Widgets.row(list, {
					name = product.key,
					title = product.icon .. "  " .. product.name,
					description = description,
					accent = if product.kind == "boost" then Colors.Accent2 else Colors.Energy,
					layoutOrder = order,
				})
				C.setButton(button, priceText(product.id, Enum.InfoType.Product, refresh), true, GOLD)
				button.TextColor3 = DARK
				C.onClick(button, function()
					buy("product", product.key, product.id)
				end)
			end
		end

		-- Codes -------------------------------------------------------------------------
		C.text({
			Name = "CodesTitle",
			Text = "Have a code? Redeem it for free rewards.",
			FontFace = Theme.Fonts.Bold,
			TextSize = 18,
			Size = UDim2.new(1, 0, 0, 26),
			Parent = codesPage,
		})
		local input: TextBox = C.new("TextBox", {
			Name = "CodeInput",
			PlaceholderText = "Enter code",
			Text = "",
			ClearTextOnFocus = false,
			FontFace = Theme.Fonts.Bold,
			TextSize = 20,
			TextColor3 = Colors.Text,
			PlaceholderColor3 = Colors.TextDim,
			BackgroundColor3 = Colors.Card,
			Size = UDim2.new(1, -180, 0, 48),
			Position = UDim2.fromOffset(0, 40),
			Children = { C.corner(Theme.SmallCorner), C.stroke() },
			Parent = codesPage,
		})
		local codeResult = C.text({
			Name = "CodeResult",
			Text = "",
			TextSize = 15,
			TextColor3 = Colors.TextDim,
			Size = UDim2.new(1, 0, 0, 44),
			Position = UDim2.fromOffset(0, 98),
			Parent = codesPage,
		})
		C.text({
			Name = "CodesHint",
			Text = "New codes are posted on the game's page and social links. Each code works once per player.",
			TextSize = 13,
			TextColor3 = Colors.TextDim,
			Size = UDim2.new(1, 0, 0, 40),
			Position = UDim2.fromOffset(0, 150),
			Parent = codesPage,
		})
		C.button({
			name = "Redeem",
			text = "REDEEM",
			color = Colors.Good,
			textColor = Color3.fromRGB(10, 40, 20),
			size = UDim2.fromOffset(168, 48),
			position = UDim2.new(1, -168, 0, 40),
			parent = codesPage,
			onClick = function()
				local code = string.gsub(input.Text, "%s", "")
				if code == "" then
					return
				end
				local response = Remote.request("RedeemCode", string.upper(code))
				if response.ok then
					Sound.play("QuestComplete")
					codeResult.Text = "✓ " .. response.data.text
					codeResult.TextColor3 = Colors.Good
					input.Text = ""
				else
					Sound.play("Error")
					codeResult.Text = app.errorText(response.err)
					codeResult.TextColor3 = Colors.Bad
				end
			end,
		})

		local signature = ""
		refresh = function()
			local profile = Store.profile
			if not profile then
				return
			end
			list.Visible = currentTab ~= "Codes"
			header.Visible = currentTab ~= "Codes"
			codesPage.Visible = currentTab == "Codes"
			if currentTab == "Codes" then
				return
			end
			local parts = { currentTab }
			for key in profile.passes do
				table.insert(parts, key)
			end
			for key, remaining in profile.boosts do
				table.insert(parts, key .. math.floor(remaining))
			end
			for id, price in prices do
				table.insert(parts, id .. price)
			end
			if currentTab == "Boosts" then
				table.insert(parts, Format.number(Store.production().total))
			end
			local nextSignature = table.concat(parts, "|")
			if nextSignature == signature then
				return
			end
			signature = nextSignature
			C.clear(list, true)
			if currentTab == "Passes" then
				renderPasses(profile)
			else
				renderProducts(profile)
			end
		end

		local selectTab = Widgets.tabs(content, { "Passes", "Boosts", "Codes" }, function(name)
			currentTab = name
			signature = ""
			refresh()
		end)
		selectTab(currentTab)

		local watching = nil
		return {
			frame = content,
			refresh = refresh,
			onOpen = function(args: any)
				if type(args) == "table" and type(args.tab) == "string" then
					currentTab = args.tab
					selectTab(currentTab)
				end
				signature = ""
				watching = Store.watch({ "passes", "boosts", "energy" }, refresh)
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
