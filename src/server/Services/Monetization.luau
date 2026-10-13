-- Robux store on the server: Game Pass ownership, Developer Product receipts and Studio test
-- purchases. Everything a purchase gives is applied here, never on the client.
--
-- Developer Products follow Roblox's receipt contract: the grant is recorded in the profile
-- together with the PurchaseId and saved before answering PurchaseGranted, so a purchase is
-- never lost (Roblox retries NotProcessedYet) and never granted twice (the id is remembered).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MonetizationConfig = require(Shared.Config.Monetization)
local Purchases = require(Shared.Logic.Actions.Purchases)

local Services = script.Parent
local Net = require(Services.Net)
local Sessions = require(Services.Sessions)
local Data = require(Services.Data)
local Plots = require(Services.Plots)
local Analytics = require(Services.Analytics)

local Monetization = {}

Monetization.OwnershipAttempts = 3

local SECTIONS = { "energy", "lifetimeEnergy", "runEnergy", "machines", "passes", "boosts" }

local function announce(session: Sessions.Session, summary: any)
	Net.notify(session.player, "Purchased", summary)
	Net.effect("Purchase", { plot = session.plot, userId = session.userId })
end

-- Applies everything a pass changes (production, capacity, VIP sign...).
local function passChanged(session: Sessions.Session)
	Sessions.markDirty(session)
	Sessions.replicate(session, SECTIONS)
	Plots.refreshOwner(session)
end

function Monetization.grantPass(session: Sessions.Session, pass: MonetizationConfig.Pass): boolean
	if not Purchases.grantPass(session.profile, pass.key) then
		return false
	end
	passChanged(session)
	announce(session, { key = pass.key, name = pass.name, icon = pass.icon, kind = "pass" })
	return true
end

-- Applies a Developer Product once per purchase id. Returns the summary sent to the client.
function Monetization.grantProduct(session: Sessions.Session, product: MonetizationConfig.Product, purchaseId: string)
	local profile = session.profile
	if Purchases.hasReceipt(profile, purchaseId) then
		return nil
	end
	local summary = Purchases.applyProduct(profile, product, Sessions.now())
	Purchases.recordReceipt(profile, purchaseId)
	Sessions.markDirty(session)
	Sessions.replicate(session, SECTIONS)
	announce(session, summary)
	if summary.energy then
		Analytics.earn(session.player, summary.energy, "IAP", "Product:" .. product.key)
	end
	Analytics.custom(session.player, "RobuxPurchase:" .. product.key, nil)
	return summary
end

function Monetization.processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local product = MonetizationConfig.productById(tonumber(receipt.ProductId) or 0)
	if not product then
		warn("[Monetization] receipt for an unknown product id: " .. tostring(receipt.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local player = Players:GetPlayerByUserId(tonumber(receipt.PlayerId) or 0)
	local session = player and Sessions.get(player)
	if not session then
		-- Not here (or still loading): Roblox retries when the player joins again.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	Monetization.grantProduct(session, product, tostring(receipt.PurchaseId))
	-- Only confirm once the grant is safely stored.
	if Data.save(session, false) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

-- Re-checks every configured pass with Roblox. On errors the saved ownership is kept.
function Monetization.refreshPasses(session: Sessions.Session)
	local changed = false
	for _, pass in MonetizationConfig.Passes do
		if pass.id <= 0 then
			continue
		end
		for attempt = 1, Monetization.OwnershipAttempts do
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(session.userId, pass.id)
			end)
			if ok then
				local current = session.profile.passes[pass.key] == true
				if owns ~= current then
					(session.profile.passes :: any)[pass.key] = if owns then true else nil
					changed = true
				end
				break
			elseif attempt < Monetization.OwnershipAttempts then
				task.wait(attempt)
			end
		end
		if not session.player.Parent then
			return
		end
	end
	if changed then
		passChanged(session)
	end
end

-- Studio only: grants an item without Robux so the store can be tried before the passes
-- and products exist on the Creator Dashboard (ids are 0 until then).
function Monetization.testPurchase(session: Sessions.Session, key: any): (boolean, any)
	if not RunService:IsStudio() then
		return false, "NotAllowed"
	end
	if type(key) ~= "string" then
		return false, "BadRequest"
	end
	local pass = MonetizationConfig.pass(key)
	if pass then
		if not Monetization.grantPass(session, pass) then
			return false, "AlreadyOwned"
		end
		return true, { key = key }
	end
	local product = MonetizationConfig.product(key)
	if product then
		local summary = Monetization.grantProduct(session, product, "studio-" .. tostring(os.clock()))
		return true, summary
	end
	return false, "BadRequest"
end

function Monetization.start()
	MarketplaceService.ProcessReceipt = Monetization.processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		local pass = MonetizationConfig.passById(passId)
		local session = Sessions.get(player)
		if pass and session then
			Monetization.grantPass(session, pass)
		end
	end)
	Sessions.Started:Connect(function(session)
		task.spawn(Monetization.refreshPasses, session)
	end)
	Net.on("StudioPurchase", function(player, key)
		local session = Sessions.get(player)
		if not session then
			return false, "NotReady"
		end
		return Monetization.testPurchase(session, key)
	end)
end

return Monetization
