-- "What should I do next?": picks one goal from the player's state for the goal bar, the
-- button highlight and the world arrow (Controllers/Guide). Pure function of the profile.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Machines = require(Shared.Config.Machines)
local Milestones = require(Shared.Config.Milestones)
local PlotConfig = require(Shared.Config.Plot)
local RebirthConfig = require(Shared.Config.Rebirth)
local Format = require(Shared.Util.Format)
local State = require(Shared.Logic.State)
local Daily = require(Shared.Logic.Actions.Daily)
local Rewards = require(Shared.Logic.Actions.Rewards)

export type Goal = {
	id: string,
	text: string,
	progress: number?, -- 0..1, shown as a bar
	window: string?, -- opened when the goal bar is tapped
	tab: string?,
	highlight: string?, -- name of the HUD button to make glow
	arrow: boolean?, -- point at an empty pedestal in the world
}

local Goals = {}

local function costGoal(profile: any, id: string, label: string, cost: number, window: string, tab: string?): Goal
	local ready = profile.energy >= cost
	return {
		id = id,
		text = if ready
			then "✅ " .. label .. " — you can afford it now!"
			else string.format(
				"🎯 Next: %s   ⚡%s / %s",
				label,
				Format.number(profile.energy),
				Format.number(cost)
			),
		progress = math.clamp(profile.energy / cost, 0, 1),
		window = window,
		tab = tab,
		highlight = if ready then (if window == "Rebirth" then "RebirthButton" else "ShopButton") else nil,
	}
end

function Goals.current(profile: any, now: number): Goal?
	if not profile then
		return nil
	end
	-- First steps of the core loop.
	if profile.stats.boxesOpened == 0 then
		return {
			id = "open",
			text = "👋 Welcome! Press OPEN BOX to fabricate your first artifact.",
			highlight = "OpenButton",
		}
	end
	if next(profile.placed) == nil then
		if next(profile.inventory) ~= nil then
			return {
				id = "place",
				text = "👇 Place it: tap the glowing pedestal, or 🎒 Items → Auto-place best.",
				arrow = true,
				window = "Inventory",
				highlight = "InventoryButton",
			}
		end
		return { id = "open", text = "Press OPEN BOX to get an artifact to place.", highlight = "OpenButton" }
	end
	-- Rewards waiting to be claimed.
	if (profile.daily.claims > 0 or profile.stats.boxesOpened >= 10) and Daily.status(profile, now).available then
		return {
			id = "daily",
			text = "🎁 Your daily reward is ready! Tap to claim it.",
			window = "Quests",
			tab = "Daily",
			highlight = "QuestsButton",
		}
	end
	for _, milestone in Milestones.List do
		if Rewards.milestoneReady(profile, milestone) then
			return {
				id = "milestone",
				text = "📖 Collection reward ready: " .. Rewards.describe(profile, milestone.reward),
				window = "Collection",
				tab = "Rewards",
				highlight = "CollectionButton",
			}
		end
	end
	-- The next purchase: the Box Printer first, then the cheapest machine or expansion.
	local printer = Machines.get("box_printer")
	if printer and not profile.machines.box_printer then
		return costGoal(profile, "printer", "Box Printer (opens boxes for you)", printer.cost, "Shop")
	end
	local best: Goal? = nil
	local bestCost = math.huge
	for _, machine in Machines.List do
		if
			not profile.machines[machine.id]
			and profile.rebirths >= machine.rebirthRequired
			and machine.cost < bestCost
		then
			bestCost = machine.cost
			best = costGoal(profile, "machine", machine.name, machine.cost, "Shop")
		end
	end
	local expansionCost = State.expansionCost(profile)
	if expansionCost and expansionCost < bestCost then
		bestCost = expansionCost
		local added = #PlotConfig.unlockedSlots(profile.expansion + 1) - #PlotConfig.unlockedSlots(profile.expansion)
		best = costGoal(
			profile,
			"expansion",
			string.format("Expand your plot (+%d pedestals)", added),
			expansionCost,
			"Shop",
			"Expansion"
		)
	end
	local rebirthCost = RebirthConfig.cost(profile.rebirths)
	if best and bestCost <= rebirthCost then
		return best
	end
	local goal = costGoal(
		profile,
		"rebirth",
		string.format("Rebirth (production x%.1f forever)", RebirthConfig.productionMultiplier(profile.rebirths + 1)),
		rebirthCost,
		"Rebirth"
	)
	return goal
end

return Goals
