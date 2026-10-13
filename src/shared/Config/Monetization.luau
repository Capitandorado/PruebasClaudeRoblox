--!strict
-- Robux store: Game Passes (permanent) and Developer Products (consumable).
--
-- The `id` of each item is the asset id you get when you create it on the Creator
-- Dashboard (Monetization → Passes / Developer Products). They start at 0 because they only
-- exist once you create them for your experience:
--   * id = 0 on a live server  → the item is hidden (no buttons that do nothing).
--   * id = 0 in Studio         → shown with a "Test" button that grants it for free, so the
--                                whole store can be tried before creating anything.
-- Prices are set on the Creator Dashboard; the store reads them with GetProductInfoAsync.
-- `suggestedPrice` is only documentation (docs/PUBLISHING.md).

export type Pass = {
	key: string,
	id: number,
	name: string,
	icon: string,
	description: string,
	suggestedPrice: number,
}

export type Product = {
	key: string,
	id: number,
	name: string,
	icon: string,
	description: string,
	suggestedPrice: number,
	kind: "energy" | "boost" | "refill",
	-- energy: `seconds` of current production (at least `min`)
	seconds: number?,
	min: number?,
	-- boost: which boost and for how long (online play time)
	boost: string?,
	duration: number?,
}

export type Boost = { key: string, name: string, icon: string, multiplier: number }

local Monetization = {}

-- Effects of each pass are read by Logic/State, Logic/Offline and the server; keep the keys.
Monetization.PassEffects = {
	vip = { production = 0.25, luck = 0.1 },
	double_energy = { productionMult = 2 },
	lucky_charm = { luckMult = 1.5 },
	turbo_fabricator = { speed = 0.5, charges = 2 },
	mega_storage = { storage = 100 },
	night_owl = { offlineRate = 0.25, offlineHours = 16 },
}

Monetization.Passes = {
	{
		key = "vip",
		id = 0,
		name = "VIP",
		icon = "👑",
		description = "+25% Energy, +10% luck and a golden VIP sign on your plot.",
		suggestedPrice = 299,
	},
	{
		key = "double_energy",
		id = 0,
		name = "2x Energy",
		icon = "⚡",
		description = "Double Energy from every artifact, forever (offline too).",
		suggestedPrice = 249,
	},
	{
		key = "lucky_charm",
		id = 0,
		name = "Lucky Charm",
		icon = "🍀",
		description = "x1.5 luck on every box: rare tiers come much more often.",
		suggestedPrice = 199,
	},
	{
		key = "turbo_fabricator",
		id = 0,
		name = "Turbo Fabricator",
		icon = "🚀",
		description = "Fabricators and the Box Printer work 50% faster; +2 Starter box capacity.",
		suggestedPrice = 149,
	},
	{
		key = "mega_storage",
		id = 0,
		name = "Mega Storage",
		icon = "📦",
		description = "+100 inventory slots.",
		suggestedPrice = 99,
	},
	{
		key = "night_owl",
		id = 0,
		name = "Night Owl",
		icon = "🌙",
		description = "Offline production +25% and counted for up to 24 hours.",
		suggestedPrice = 99,
	},
} :: { Pass }

Monetization.Boosts = {
	energy = { key = "energy", name = "x2 Energy", icon = "⚡", multiplier = 2 },
	luck = { key = "luck", name = "x2 Luck", icon = "🍀", multiplier = 2 },
} :: { [string]: Boost }

Monetization.Products = {
	{
		key = "energy_small",
		id = 0,
		name = "Energy Crate",
		icon = "🔋",
		description = "15 minutes of your current production.",
		suggestedPrice = 25,
		kind = "energy",
		seconds = 900,
		min = 5000,
	},
	{
		key = "energy_medium",
		id = 0,
		name = "Energy Vault",
		icon = "🔋",
		description = "1 hour of your current production.",
		suggestedPrice = 79,
		kind = "energy",
		seconds = 3600,
		min = 25000,
	},
	{
		key = "energy_large",
		id = 0,
		name = "Energy Reactor",
		icon = "🔋",
		description = "4 hours of your current production.",
		suggestedPrice = 249,
		kind = "energy",
		seconds = 14400,
		min = 120000,
	},
	{
		key = "boost_energy",
		id = 0,
		name = "x2 Energy Boost",
		icon = "⚡",
		description = "Double production for 30 minutes of play (stacks).",
		suggestedPrice = 49,
		kind = "boost",
		boost = "energy",
		duration = 1800,
	},
	{
		key = "boost_luck",
		id = 0,
		name = "x2 Luck Boost",
		icon = "🍀",
		description = "Double luck for 30 minutes of play (stacks).",
		suggestedPrice = 49,
		kind = "boost",
		boost = "luck",
		duration = 1800,
	},
	{
		key = "refill",
		id = 0,
		name = "Instant Refill",
		icon = "🔄",
		description = "Fills every fabricator's boxes right now.",
		suggestedPrice = 15,
		kind = "refill",
	},
} :: { Product }

-- A boost can be stacked up to this many seconds.
Monetization.MaxBoostSeconds = 6 * 3600

local passByKey: { [string]: Pass } = {}
for _, pass in Monetization.Passes do
	passByKey[pass.key] = pass
end
local productByKey: { [string]: Product } = {}
for _, product in Monetization.Products do
	productByKey[product.key] = product
end

function Monetization.pass(key: string): Pass?
	return passByKey[key]
end

function Monetization.product(key: string): Product?
	return productByKey[key]
end

function Monetization.passById(id: number): Pass?
	if id == 0 then
		return nil
	end
	for _, pass in Monetization.Passes do
		if pass.id == id then
			return pass
		end
	end
	return nil
end

function Monetization.productById(id: number): Product?
	if id == 0 then
		return nil
	end
	for _, product in Monetization.Products do
		if product.id == id then
			return product
		end
	end
	return nil
end

return Monetization
