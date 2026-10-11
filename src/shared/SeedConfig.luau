--!strict
--[[
	SeedConfig
	==========
	Única fuente de verdad de las semillas del juego y sus rarezas.

	Para AÑADIR una semilla nueva basta con añadir una entrada a `SeedConfig.Seeds`
	con un Id único (sin espacios ni tildes). El resto del juego (cinta, plantas,
	inventario, venta) la utilizará automáticamente.

	Para EQUILIBRAR el juego, cambia los precios, tiempos y valores aquí o los
	pesos de aparición de cada rareza en `SeedConfig.Rarities`.

	Este módulo se usa tanto en el servidor como en el cliente, pero el cliente
	sólo lo emplea para mostrar información: toda decisión (precios, tiempos,
	ventas) se toma y se valida en el servidor.
]]

-- Id de rareza: "Common", "Rare", "Epic", "Legendary" o cualquiera que añadas
-- en SeedConfig.Rarities.
export type RarityId = string

export type RarityInfo = {
	Id: RarityId,
	DisplayName: string, -- Nombre que ve el jugador
	Color: Color3, -- Color con el que se muestra la rareza
	Weight: number, -- Peso relativo de aparición en la cinta
	Order: number, -- Para ordenar listas (1 = más común)
}

export type SeedInfo = {
	Id: string, -- Identificador interno único (se usa en inventario y remotes)
	DisplayName: string, -- Nombre visible
	Rarity: RarityId,
	Price: number, -- Coste de comprar la semilla en la cinta
	GrowTime: number, -- Segundos que tarda en madurar
	SellValue: number, -- Dinero que da cada fruto en el puesto de venta
	Color: Color3, -- Color del placeholder (semilla, planta y fruto)
}

local SeedConfig = {}

--------------------------------------------------------------------------------
-- RAREZAS
-- Los pesos no tienen por qué sumar 100: se normalizan automáticamente.
--------------------------------------------------------------------------------
SeedConfig.Rarities = {
	Common = {
		Id = "Common",
		DisplayName = "Común",
		Color = Color3.fromRGB(200, 200, 200),
		Weight = 70,
		Order = 1,
	},
	Rare = {
		Id = "Rare",
		DisplayName = "Rara",
		Color = Color3.fromRGB(70, 150, 255),
		Weight = 20,
		Order = 2,
	},
	Epic = {
		Id = "Epic",
		DisplayName = "Épica",
		Color = Color3.fromRGB(170, 80, 255),
		Weight = 8,
		Order = 3,
	},
	Legendary = {
		Id = "Legendary",
		DisplayName = "Legendaria",
		Color = Color3.fromRGB(255, 185, 30),
		Weight = 2,
		Order = 4,
	},
} :: { [RarityId]: RarityInfo }

--------------------------------------------------------------------------------
-- SEMILLAS
--------------------------------------------------------------------------------
local seedList: { SeedInfo } = {
	-- Comunes ---------------------------------------------------------------
	{
		Id = "BrotilloSolar",
		DisplayName = "Brotillo Solar",
		Rarity = "Common",
		Price = 10,
		GrowTime = 20,
		SellValue = 18,
		Color = Color3.fromRGB(255, 220, 90),
	},
	{
		Id = "NaboBurbuja",
		DisplayName = "Nabo Burbuja",
		Rarity = "Common",
		Price = 12,
		GrowTime = 25,
		SellValue = 22,
		Color = Color3.fromRGB(235, 140, 200),
	},
	{
		Id = "TrigoSusurro",
		DisplayName = "Trigo Susurro",
		Rarity = "Common",
		Price = 15,
		GrowTime = 30,
		SellValue = 28,
		Color = Color3.fromRGB(215, 180, 120),
	},

	-- Raras -----------------------------------------------------------------
	{
		Id = "FresaLunar",
		DisplayName = "Fresa Lunar",
		Rarity = "Rare",
		Price = 40,
		GrowTime = 45,
		SellValue = 95,
		Color = Color3.fromRGB(190, 210, 255),
	},
	{
		Id = "CalabazaTrueno",
		DisplayName = "Calabaza Trueno",
		Rarity = "Rare",
		Price = 55,
		GrowTime = 55,
		SellValue = 130,
		Color = Color3.fromRGB(255, 130, 40),
	},

	-- Épicas ----------------------------------------------------------------
	{
		Id = "RosaCristal",
		DisplayName = "Rosa de Cristal",
		Rarity = "Epic",
		Price = 120,
		GrowTime = 80,
		SellValue = 340,
		Color = Color3.fromRGB(120, 255, 240),
	},
	{
		Id = "MelonNebulosa",
		DisplayName = "Melón Nebulosa",
		Rarity = "Epic",
		Price = 150,
		GrowTime = 95,
		SellValue = 430,
		Color = Color3.fromRGB(110, 60, 200),
	},

	-- Legendarias -----------------------------------------------------------
	{
		Id = "MangoFenix",
		DisplayName = "Mango Fénix",
		Rarity = "Legendary",
		Price = 400,
		GrowTime = 150,
		SellValue = 1400,
		Color = Color3.fromRGB(255, 70, 30),
	},
}

-- Diccionario Id -> SeedInfo para búsquedas rápidas.
SeedConfig.Seeds = {} :: { [string]: SeedInfo }
-- Semillas agrupadas por rareza, para el sorteo de la cinta.
local seedsByRarity: { [RarityId]: { SeedInfo } } = {}

for _, seed in seedList do
	assert(SeedConfig.Seeds[seed.Id] == nil, "Id de semilla duplicado: " .. seed.Id)
	assert(SeedConfig.Rarities[seed.Rarity], "Rareza desconocida en " .. seed.Id)
	SeedConfig.Seeds[seed.Id] = seed

	local bucket = seedsByRarity[seed.Rarity]
	if not bucket then
		bucket = {}
		seedsByRarity[seed.Rarity] = bucket
	end
	table.insert(bucket, seed)
end

--------------------------------------------------------------------------------
-- FUNCIONES DE AYUDA
--------------------------------------------------------------------------------

-- Devuelve la información de una semilla o nil si el Id no existe.
-- Úsala siempre para validar Ids que llegan del cliente.
function SeedConfig.get(seedId: any): SeedInfo?
	if type(seedId) ~= "string" then
		return nil
	end
	return SeedConfig.Seeds[seedId]
end

function SeedConfig.getRarity(rarityId: RarityId): RarityInfo
	return SeedConfig.Rarities[rarityId]
end

-- Elige una rareza al azar según los pesos. Sólo tiene en cuenta rarezas que
-- tengan al menos una semilla definida.
function SeedConfig.rollRarity(rng: Random?): RarityId
	local random = rng or Random.new()
	local total = 0
	for rarityId, info in SeedConfig.Rarities do
		if seedsByRarity[rarityId] then
			total += info.Weight
		end
	end

	local roll = random:NextNumber() * total
	local fallback: RarityId = "Common"
	for rarityId, info in SeedConfig.Rarities do
		if seedsByRarity[rarityId] then
			fallback = rarityId
			roll -= info.Weight
			if roll <= 0 then
				return rarityId
			end
		end
	end
	return fallback
end

-- Elige una semilla aleatoria: primero la rareza y luego una semilla de esa rareza.
function SeedConfig.rollSeed(rng: Random?): SeedInfo
	local random = rng or Random.new()
	local bucket = seedsByRarity[SeedConfig.rollRarity(random)]
	return bucket[random:NextInteger(1, #bucket)]
end

-- Lista de todas las semillas ordenada por rareza y precio (útil para la UI).
function SeedConfig.getSortedIds(): { string }
	local ids = {}
	for id in SeedConfig.Seeds do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		local sa, sb = SeedConfig.Seeds[a], SeedConfig.Seeds[b]
		local ra, rb = SeedConfig.Rarities[sa.Rarity].Order, SeedConfig.Rarities[sb.Rarity].Order
		if ra ~= rb then
			return ra < rb
		end
		return sa.Price < sb.Price
	end)
	return ids
end

return SeedConfig
