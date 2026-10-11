--!strict
--[[
	Tags
	====
	Nombres de las Tags de CollectionService usadas para identificar objetos
	del mapa. Si colocas tus propios modelos en Studio con estas Tags, el
	código los usará en lugar de generar placeholders.
]]

return {
	-- Part que hace de cinta transportadora. Las semillas avanzan en la
	-- dirección de su LookVector (eje -Z local), de un extremo al otro.
	Conveyor = "Conveyor",
	-- Cada semilla que hay sobre la cinta (las crea el servidor).
	ConveyorSeed = "ConveyorSeed",
	-- Model de una parcela. Debe contener una Part llamada "Base".
	Plot = "Plot",
	-- Part de un hueco de tierra (descendiente de un Model con Tag "Plot").
	PlotSlot = "PlotSlot",
	-- Planta que está creciendo en un hueco (la crea el servidor).
	Plant = "Plant",
	-- Part o Model del puesto de venta.
	SellStand = "SellStand",
}
