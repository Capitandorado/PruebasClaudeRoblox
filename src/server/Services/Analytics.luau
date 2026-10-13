-- Product analytics through Roblox's AnalyticsService (Creator Dashboard → Analytics):
-- the first-session onboarding funnel, Energy/Shards sources and sinks, rebirth progression
-- and the daily streak. Server-only and best effort: a failing call never affects gameplay.
-- Economy events are aggregated per player and flushed once a minute, so auto-opening or
-- production ticks never flood the analytics limits.

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")

local Analytics = {}

Analytics.FlushInterval = 60
-- At most this many economy events per player per flush; the rest waits for the next one.
Analytics.MaxEventsPerFlush = 8

-- First-session funnel, in order. Steps are only logged for players whose first session
-- this is, and each step once.
Analytics.OnboardingSteps = {
	"Joined",
	"OpenedFirstBox",
	"PlacedFirstArtifact",
	"BoughtBoxPrinter",
	"FirstExpansion",
	"FirstRebirth",
}
local stepIndex: { [string]: number } = {}
for index, name in Analytics.OnboardingSteps do
	stepIndex[name] = index
end

type Flow = "Source" | "Sink"
type Pending = { flow: Flow, currency: string, transaction: string, sku: string, amount: number }
type State = { onboarding: boolean, steps: { [number]: boolean }, pending: { [string]: Pending }, order: { string } }

local states: { [Player]: State } = {}
local warned: { [string]: boolean } = {}

local function call(method: string, ...: any)
	local args = table.pack(...)
	local ok, err = pcall(function()
		(AnalyticsService :: any)[method](AnalyticsService, table.unpack(args, 1, args.n))
	end)
	if not ok and not warned[method] then
		warned[method] = true
		warn("[Analytics] " .. method .. " failed: " .. tostring(err))
	end
end

local function stateOf(player: Player): State?
	return states[player]
end

-- Called once the player's profile is loaded. `firstSession` = a brand-new profile.
function Analytics.joined(player: Player, firstSession: boolean)
	states[player] = { onboarding = firstSession, steps = {}, pending = {}, order = {} }
	if firstSession then
		Analytics.step(player, "Joined")
	end
end

function Analytics.step(player: Player, name: string)
	local state = stateOf(player)
	local index = stepIndex[name]
	if not state or not index or not state.onboarding or state.steps[index] then
		return
	end
	state.steps[index] = true
	call("LogOnboardingFunnelStepEvent", player, index, name)
end

-- Queues an economy flow; amounts with the same flow/currency/transaction/sku are summed.
function Analytics.economy(
	player: Player,
	flow: Flow,
	currency: string,
	amount: number,
	transaction: string,
	sku: string
)
	local state = stateOf(player)
	if not state or type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return
	end
	local key = table.concat({ flow, currency, transaction, sku }, "|")
	local pending = state.pending[key]
	if not pending then
		pending = { flow = flow, currency = currency, transaction = transaction, sku = sku, amount = 0 }
		state.pending[key] = pending
		table.insert(state.order, key)
	end
	pending.amount += amount
end

function Analytics.earn(player: Player, amount: number, transaction: string, sku: string)
	Analytics.economy(player, "Source", "Energy", amount, transaction, sku)
end

function Analytics.spend(player: Player, amount: number, transaction: string, sku: string)
	Analytics.economy(player, "Sink", "Energy", amount, transaction, sku)
end

function Analytics.progression(player: Player, path: string, level: number)
	if stateOf(player) then
		call("LogProgressionCompleteEvent", player, path, level, path .. " " .. level)
	end
end

function Analytics.custom(player: Player, name: string, value: number?)
	if stateOf(player) then
		call("LogCustomEvent", player, name, value)
	end
end

-- Sends the queued economy events. `balances` gives each currency's current balance.
function Analytics.flush(player: Player, balances: { [string]: number })
	local state = stateOf(player)
	if not state then
		return
	end
	local sent = 0
	while #state.order > 0 and sent < Analytics.MaxEventsPerFlush do
		local key = table.remove(state.order, 1) :: string
		local pending = state.pending[key]
		state.pending[key] = nil
		local amount = math.floor(pending.amount)
		if amount >= 1 then
			sent += 1
			call(
				"LogEconomyEvent",
				player,
				Enum.AnalyticsEconomyFlowType[pending.flow],
				pending.currency,
				amount,
				math.max(0, math.floor(balances[pending.currency] or 0)),
				pending.transaction,
				pending.sku
			)
		end
	end
end

function Analytics.left(player: Player, balances: { [string]: number })
	Analytics.flush(player, balances)
	states[player] = nil
end

-- Test hook.
function Analytics._state(player: Player)
	return states[player]
end

function Analytics.start()
	Players.PlayerRemoving:Connect(function(player)
		-- Sessions flushes with the final balances first; this only drops leftovers.
		task.defer(function()
			states[player] = nil
		end)
	end)
end

return Analytics
