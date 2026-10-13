--!strict
-- Robux purchases applied to a profile. Only the server calls these, after Roblox confirms
-- the purchase (ProcessReceipt / PromptGamePassPurchaseFinished) or for Studio test buys.
-- Receipts are remembered so a Developer Product is never granted twice.

local Shared = script.Parent.Parent.Parent
local Monetization = require(Shared.Config.Monetization)
local Machines = require(Shared.Config.Machines)
local Logic = script.Parent.Parent
local State = require(Logic.State)
local Inventory = require(Logic.Inventory)
local ProfileModule = require(Logic.Profile)

type Profile = any

local Purchases = {}

function Purchases.hasReceipt(profile: Profile, purchaseId: string): boolean
	return table.find(profile.receipts, purchaseId) ~= nil
end

function Purchases.recordReceipt(profile: Profile, purchaseId: string)
	table.insert(profile.receipts, purchaseId)
	while #profile.receipts > ProfileModule.MaxReceipts do
		table.remove(profile.receipts, 1)
	end
end

-- Energy given by an Energy pack: `seconds` of steady production, at least `min`.
function Purchases.energyFor(profile: Profile, product: Monetization.Product): number
	local eps = State.computeProduction(profile, 1, 1, true).total
	return math.floor(math.max(product.min or 0, eps * (product.seconds or 0)))
end

-- Applies a Developer Product. Returns a summary for the client.
function Purchases.applyProduct(profile: Profile, product: Monetization.Product, now: number): any
	local result: any = { key = product.key, name = product.name, icon = product.icon, kind = product.kind }
	if product.kind == "energy" then
		local amount = Purchases.energyFor(profile, product)
		Inventory.earn(profile, amount, false)
		result.energy = amount
	elseif product.kind == "boost" then
		local key = product.boost :: string
		local current = profile.boosts[key] or 0
		profile.boosts[key] = math.min(Monetization.MaxBoostSeconds, current + (product.duration or 0))
		result.boost = key
		result.remaining = profile.boosts[key]
	elseif product.kind == "refill" then
		for machineId, machineState in profile.machines do
			local machine = Machines.get(machineId)
			if machine and machine.kind == "fabricator" then
				local cap = State.chargeCap(profile, machineId)
				if cap > 0 then
					machineState.charges = cap
					machineState.chargeAt = now
				end
			end
		end
	end
	return result
end

-- Records ownership of a Game Pass. Returns false if it was already owned.
function Purchases.grantPass(profile: Profile, key: string): boolean
	if not Monetization.pass(key) or profile.passes[key] == true then
		return false
	end
	profile.passes[key] = true
	return true
end

return Purchases
