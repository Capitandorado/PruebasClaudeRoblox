--!strict
--[[
	GameConfig
	==========
	Parámetros generales de la partida (economía inicial, cinta, parcelas...).
	Los datos de cada semilla están en SeedConfig.
]]

local GameConfig = {}

-- Economía --------------------------------------------------------------------
-- Suficiente para comprar 2 semillas comunes (la común más cara cuesta 15).
GameConfig.StartingMoney = 30
-- Nombre del valor que aparece en el leaderstats.
GameConfig.MoneyStatName = "Dinero"

-- Cinta transportadora ---------------------------------------------------------
GameConfig.Conveyor = {
	SpawnInterval = 3, -- Segundos entre semilla y semilla
	Speed = 4, -- Studs por segundo
	MaxSeeds = 25, -- Límite de seguridad de semillas simultáneas
	-- Tamaño y posición de la cinta generada si no existe una en el mapa.
	Size = Vector3.new(8, 1, 70),
	Position = Vector3.new(0, 1, 0),
}

-- Parcelas -------------------------------------------------------------------
GameConfig.Plots = {
	MaxPlots = 6, -- Número de parcelas (= jugadores con parcela)
	StartingSlots = 4, -- Huecos de tierra con los que empieza cada parcela
	Size = Vector3.new(28, 1, 28), -- Tamaño de la base generada
	SlotSize = Vector3.new(6, 1, 6), -- Tamaño de cada hueco generado
	SlotSpacing = 9, -- Distancia entre huecos generados
	-- Distancia máxima (en horizontal) desde el centro de la parcela para que
	-- el servidor acepte una petición de plantar.
	MaxPlantDistance = 26,
}

-- Crecimiento ----------------------------------------------------------------
-- Escala visual de la planta en cada fase. La última fase = planta madura.
GameConfig.GrowthStageScales = { 0.25, 0.5, 0.75, 1 }
-- Cada cuánto (segundos) el servidor actualiza el crecimiento de las plantas.
GameConfig.GrowthTickInterval = 0.25

-- Antitrampas / límites -------------------------------------------------------
-- Tiempo mínimo entre peticiones del cliente para plantar.
GameConfig.PlantCooldown = 0.3

-- Puesto de venta --------------------------------------------------------------
GameConfig.SellStandPosition = Vector3.new(0, 0.5, -48)

return GameConfig
