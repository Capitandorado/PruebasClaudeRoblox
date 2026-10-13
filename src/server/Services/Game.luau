-- Action handlers: every client request ends here after validation and rate limiting.
-- Handlers call the pure game logic (Shared/Logic) on the session's profile, then update the
-- plot visuals, replicate the changed profile sections and fire cosmetic effects.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rarities = require(Shared.Config.Rarities)
local Items = require(Shared.Logic.Items)
local BoxActions = require(Shared.Logic.Actions.Boxes)
local Factory = require(Shared.Logic.Actions.Factory)
local Shop = require(Shared.Logic.Actions.Shop)
local Fusion = require(Shared.Logic.Actions.Fusion)
local Progression = require(Shared.Logic.Actions.Progression)
local Daily = require(Shared.Logic.Actions.Daily)
local Rewards = require(Shared.Logic.Actions.Rewards)

local Services = script.Parent
local Net = require(Services.Net)
local Sessions = require(Services.Sessions)
local Plots = require(Services.Plots)
local Leaderboards = require(Services.Leaderboards)
local Analytics = require(Services.Analytics)

local Game = {}

type Session = Sessions.Session

local WALLET = { "energy", "lifetimeEnergy", "runEnergy", "stats" }

local function sections(...: { string } | string): { string }
	local result = {}
	for _, part in { ... } do
		if type(part) == "table" then
			for _, name in part do
				table.insert(result, name)
			end
		else
			table.insert(result, part)
		end
	end
	return result
end

local function handle(action: string, fn: (session: Session, ...any) -> (boolean, any))
	Net.on(action, function(player, ...)
		local session = Sessions.get(player)
		if not session then
			return false, "NotReady"
		end
		return fn(session, ...)
	end)
end

-- Box results: announcements and world effects ---------------------------------------

-- Server-wide announcements must stand out without flooding the screen: only Mythic and
-- above, or a Legendary found for the first time, with a global cooldown (the very rarest
-- tiers always go through).
Game.AnnounceCooldown = 4
local lastAnnounce = -math.huge

function Game.shouldAnnounce(rarity: Rarities.Rarity, newArtifact: boolean, now: number): boolean
	if rarity.announce ~= "server" then
		return false
	end
	local important = rarity.order >= Rarities.order("Mythic") or newArtifact
	if not important then
		return false
	end
	if rarity.order >= Rarities.order("Void") then
		return true
	end
	return now - lastAnnounce >= Game.AnnounceCooldown
end

function Game.announceGrants(session: Session, result: any)
	local bestOrder = 0
	for _, grant in result.grants do
		if grant.newArtifact or grant.newVariant then
			-- New discoveries raise the collection bonus: recompute production.
			Sessions.markDirty(session)
		end
		local item = Items.parse(grant.key)
		if not item then
			continue
		end
		local rarity = Rarities.get(Items.rarityOf(item))
		if not rarity then
			continue
		end
		bestOrder = math.max(bestOrder, rarity.order)
		local now = os.clock()
		if rarity.order >= Rarities.order("Mythic") then
			Analytics.custom(session.player, "MythicOrBetterFound", rarity.order)
		end
		if Game.shouldAnnounce(rarity, grant.newArtifact == true, now) then
			lastAnnounce = now
			Net.notifyAll("Announce", {
				name = session.player.DisplayName,
				userId = session.userId,
				key = grant.key,
				rarity = rarity.id,
				newArtifact = grant.newArtifact,
			})
		end
	end
	if bestOrder >= Rarities.order("Rare") then
		Net.effect("Reveal", {
			plot = session.plot,
			machineId = result.machineId,
			rarity = Rarities.List[bestOrder].id,
			userId = session.userId,
		})
	end
	if result.grants[1] and result.grants[1].newArtifact then
		Plots.refreshShowcase(session)
	end
end

local BOX_SECTIONS = sections(WALLET, "inventory", "machines", "collection", "bestRarity")

function Game.start()
	handle("OpenBox", function(session, machineId)
		local ok, result = BoxActions.open(session.profile, machineId, {
			now = Sessions.now(),
			rng = session.rng,
			production = Sessions.production(session),
		})
		if not ok then
			return false, result
		end
		Sessions.replicate(session, BOX_SECTIONS)
		Game.announceGrants(session, result)
		Analytics.spend(session.player, result.paid, "Gameplay", "Box:" .. machineId)
		if session.profile.stats.boxesOpened == 1 then
			Analytics.step(session.player, "OpenedFirstBox")
		end
		return true, result
	end)

	handle("Place", function(session, slot, key)
		local ok, result = Factory.place(session.profile, slot, key)
		if not ok then
			return false, result
		end
		Analytics.step(session.player, "PlacedFirstArtifact")
		Sessions.markDirty(session)
		Plots.refreshSlots(session)
		Sessions.replicate(session, sections("inventory", "placed", "stats"))
		return true, result
	end)

	handle("Remove", function(session, slot)
		local ok, result = Factory.remove(session.profile, slot)
		if not ok then
			return false, result
		end
		Sessions.markDirty(session)
		Plots.refreshSlots(session)
		Sessions.replicate(session, sections("inventory", "placed"))
		return true, result
	end)

	handle("AutoFill", function(session)
		local ok, result = Factory.autoFill(session.profile)
		if not ok then
			return false, result
		end
		Analytics.step(session.player, "PlacedFirstArtifact")
		Sessions.markDirty(session)
		Plots.refreshSlots(session)
		Sessions.replicate(session, sections("inventory", "placed", "stats"))
		return true, result
	end)

	handle("ClearPlot", function(session)
		local ok, result = Factory.clear(session.profile)
		if not ok then
			return false, result
		end
		Sessions.markDirty(session)
		Plots.refreshSlots(session)
		Sessions.replicate(session, sections("inventory", "placed"))
		return true, result
	end)

	handle("Sell", function(session, key, amount)
		local ok, result = Shop.sell(session.profile, key, amount)
		if not ok then
			return false, result
		end
		Analytics.earn(session.player, result.value, "Gameplay", "Sell")
		Sessions.replicate(session, sections(WALLET, "inventory"))
		return true, result
	end)

	handle("SellRarity", function(session, rarityId, keep)
		local ok, result = Shop.sellRarity(session.profile, rarityId, keep)
		if not ok then
			return false, result
		end
		Analytics.earn(session.player, result.value, "Gameplay", "Sell")
		Sessions.replicate(session, sections(WALLET, "inventory"))
		return true, result
	end)

	handle("SetAutoSell", function(session, rarityId, enabled)
		local ok, result = Shop.setAutoSell(session.profile, rarityId, enabled)
		if not ok then
			return false, result
		end
		Sessions.replicate(session, sections("settings"))
		return true, result
	end)

	handle("BuyMachine", function(session, machineId)
		local ok, result = Shop.buyMachine(session.profile, machineId, Sessions.now())
		if not ok then
			return false, result
		end
		Analytics.spend(session.player, result.cost, "Shop", "Machine:" .. machineId)
		if machineId == "box_printer" then
			Analytics.step(session.player, "BoughtBoxPrinter")
		end
		Sessions.markDirty(session)
		Plots.refreshMachines(session)
		Sessions.replicate(session, sections(WALLET, "machines"))
		Net.effect("Purchase", { plot = session.plot, machineId = machineId, userId = session.userId })
		return true, result
	end)

	handle("UpgradeMachine", function(session, machineId)
		local ok, result = Shop.upgradeMachine(session.profile, machineId)
		if not ok then
			return false, result
		end
		Analytics.spend(session.player, result.cost, "Shop", "MachineUpgrade:" .. machineId)
		Sessions.markDirty(session)
		Plots.refreshMachines(session)
		Sessions.replicate(session, sections(WALLET, "machines"))
		return true, result
	end)

	handle("BuyUpgrade", function(session, upgradeId)
		local ok, result = Shop.buyUpgrade(session.profile, upgradeId)
		if not ok then
			return false, result
		end
		Analytics.spend(session.player, result.cost, "Shop", "Upgrade:" .. upgradeId)
		Sessions.markDirty(session)
		Sessions.replicate(session, sections(WALLET, "upgrades"))
		return true, result
	end)

	handle("BuyExpansion", function(session)
		local ok, result = Shop.buyExpansion(session.profile)
		if not ok then
			return false, result
		end
		Analytics.spend(session.player, result.cost, "Shop", "Expansion")
		Analytics.step(session.player, "FirstExpansion")
		Plots.refreshExpansion(session)
		Sessions.replicate(session, sections(WALLET, "expansion"))
		Net.effect("Unlock", { plot = session.plot, level = result.level, userId = session.userId })
		return true, result
	end)

	handle("Fuse", function(session, key)
		local ok, result = Fusion.fuse(session.profile, key, Sessions.now())
		if not ok then
			return false, result
		end
		Analytics.spend(session.player, result.cost, "Gameplay", "Fusion")
		Sessions.markDirty(session)
		Sessions.replicate(session, sections(WALLET, "inventory", "collection"))
		return true, result
	end)

	handle("Rebirth", function(session)
		local ok, result = Progression.rebirth(session.profile, Sessions.now())
		if not ok then
			return false, result
		end
		Analytics.economy(session.player, "Source", "Shards", result.shards, "Gameplay", "Rebirth")
		Analytics.progression(session.player, "Rebirth", result.rebirths)
		Analytics.step(session.player, "FirstRebirth")
		Progression.ensureQuests(session.profile, session.rng)
		Sessions.markDirty(session)
		session.runtime.printerAt = nil
		Plots.refresh(session)
		Sessions.replicateFull(session)
		Net.notifyAll("Announce", {
			name = session.player.DisplayName,
			userId = session.userId,
			rebirths = result.rebirths,
		})
		Net.effect("Rebirth", { plot = session.plot, userId = session.userId })
		Leaderboards.markDirty(session)
		return true, result
	end)

	handle("BuyPerk", function(session, perkId)
		local ok, result = Progression.buyPerk(session.profile, perkId)
		if not ok then
			return false, result
		end
		Analytics.economy(session.player, "Sink", "Shards", result.cost, "Shop", "Perk:" .. perkId)
		Sessions.markDirty(session)
		Sessions.replicate(session, sections("shards", "perks"))
		return true, result
	end)

	handle("ClaimQuest", function(session, index)
		local eps = Sessions.production(session).total
		local ok, result = Progression.claimQuest(session.profile, index, eps, session.rng)
		if not ok then
			return false, result
		end
		Analytics.earn(session.player, result.reward, "Gameplay", "Quest")
		Sessions.replicate(session, sections(WALLET, "quests"))
		return true, result
	end)

	handle("ClaimDaily", function(session)
		local now = Sessions.now()
		local ok, result = Daily.claim(session.profile, now, {
			now = now,
			rng = session.rng,
			production = Sessions.production(session),
		})
		if not ok then
			return false, result
		end
		Sessions.replicate(session, sections(BOX_SECTIONS, "daily"))
		for _, boxResult in result.results do
			Game.announceGrants(session, boxResult)
		end
		Analytics.earn(session.player, result.energy, "TimedReward", "Daily")
		Analytics.custom(session.player, "DailyStreak", result.streak)
		return true, result
	end)

	-- Codes and collection milestones share the reward format (Logic/Actions/Rewards).
	local REWARD_SECTIONS = sections(BOX_SECTIONS, "shards", "boosts", "codes", "milestones")
	local function rewarded(session: Session, summary: any, sku: string)
		Sessions.markDirty(session)
		Sessions.replicate(session, REWARD_SECTIONS)
		for _, boxResult in summary.results do
			Game.announceGrants(session, boxResult)
		end
		Analytics.earn(session.player, summary.energy, "Gameplay", sku)
		if summary.shards then
			Analytics.economy(session.player, "Source", "Shards", summary.shards, "Gameplay", sku)
		end
	end

	handle("RedeemCode", function(session, code)
		local now = Sessions.now()
		local ok, result = Rewards.redeemCode(session.profile, code, now, {
			now = now,
			rng = session.rng,
			production = Sessions.production(session),
		})
		if not ok then
			return false, result
		end
		rewarded(session, result, "Code")
		return true, result
	end)

	handle("ClaimMilestone", function(session, id)
		local now = Sessions.now()
		local ok, result = Rewards.claimMilestone(session.profile, id, {
			now = now,
			rng = session.rng,
			production = Sessions.production(session),
		})
		if not ok then
			return false, result
		end
		rewarded(session, result, "Milestone")
		return true, result
	end)

	handle("SetSetting", function(session, name, value)
		if name ~= "sfx" and name ~= "reducedEffects" then
			return false, "BadRequest"
		end
		session.profile.settings[name] = value
		Sessions.replicate(session, sections("settings"))
		return true, { name = name, value = value }
	end)

	handle("Visit", function(session, userId)
		local target = Sessions.byUserId(userId)
		if not target then
			return false, "InvalidTarget"
		end
		Plots.teleport(session.player, target.plot)
		return true, { plot = target.plot, name = target.player.DisplayName, userId = target.userId }
	end)

	handle("GoHome", function(session)
		Plots.teleport(session.player, session.plot)
		return true, { plot = session.plot }
	end)

	handle("GetLeaderboard", function(_session)
		return true, Leaderboards.snapshot()
	end)
end

return Game
