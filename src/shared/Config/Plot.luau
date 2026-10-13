--!strict
-- Plot layout. Pedestals live on a COLUMNS x ROWS grid; expansions unlock bigger rectangles.
-- Slot index = (row - 1) * COLUMNS + column, so adjacency is stable across expansions.

export type Expansion = {
	columns: number,
	rows: number,
	cost: number,
}

local Plot = {}

Plot.Columns = 6
Plot.Rows = 4
Plot.SlotSpacing = 8
Plot.MaxPlots = 8
Plot.PlotRadius = 150

-- Index 1 is the free starting layout (expansion level 0).
Plot.Expansions = {
	{ columns = 3, rows = 2, cost = 0 },
	{ columns = 3, rows = 3, cost = 800 },
	{ columns = 4, rows = 3, cost = 7500 },
	{ columns = 4, rows = 4, cost = 45000 },
	{ columns = 5, rows = 4, cost = 250000 },
	{ columns = 6, rows = 4, cost = 1500000 },
} :: { Expansion }

Plot.MaxExpansionLevel = #Plot.Expansions - 1
Plot.TotalSlots = Plot.Columns * Plot.Rows

function Plot.slotIndex(column: number, row: number): number
	return (row - 1) * Plot.Columns + column
end

function Plot.slotPosition(index: number): (number, number)
	local column = ((index - 1) % Plot.Columns) + 1
	local row = math.floor((index - 1) / Plot.Columns) + 1
	return column, row
end

function Plot.getExpansion(level: number): Expansion
	local clamped = math.clamp(level, 0, Plot.MaxExpansionLevel)
	return Plot.Expansions[clamped + 1]
end

function Plot.isSlotUnlocked(index: number, expansionLevel: number): boolean
	if index < 1 or index > Plot.TotalSlots or index ~= math.floor(index) then
		return false
	end
	local expansion = Plot.getExpansion(expansionLevel)
	local column, row = Plot.slotPosition(index)
	return column <= expansion.columns and row <= expansion.rows
end

function Plot.unlockedSlots(expansionLevel: number): { number }
	local slots = {}
	for index = 1, Plot.TotalSlots do
		if Plot.isSlotUnlocked(index, expansionLevel) then
			table.insert(slots, index)
		end
	end
	return slots
end

-- Orthogonal neighbours that exist on the grid (locked or not).
function Plot.neighbours(index: number): { number }
	local column, row = Plot.slotPosition(index)
	local result = {}
	if column > 1 then
		table.insert(result, Plot.slotIndex(column - 1, row))
	end
	if column < Plot.Columns then
		table.insert(result, Plot.slotIndex(column + 1, row))
	end
	if row > 1 then
		table.insert(result, Plot.slotIndex(column, row - 1))
	end
	if row < Plot.Rows then
		table.insert(result, Plot.slotIndex(column, row + 1))
	end
	return result
end

return Plot
