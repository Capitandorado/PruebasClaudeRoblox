-- Robux store: receipts (idempotent, saved before granting), Game Passes, boosts, Studio
-- test purchases, codes, collection milestones and the Store window.

local Fixture = require("../lib/Fixture")
local DataStore = require("../mock/DataStore")
local roblox = require("@lune/roblox")

local Enum = roblox.Enum

local function errorsText(rt)
	local lines = {}
	for _, err in rt:errors() do
		table.insert(lines, err.trace)
	end
	return table.concat(lines, "\n")
end

-- Test ids for the placeholders in Config/Monetization (real ids come from the dashboard).
local PASS_IDS = {
	vip = 1001,
	double_energy = 1002,
	lucky_charm = 1003,
	turbo_fabricator = 1004,
	mega_storage = 1005,
	night_owl = 1006,
}
local PRODUCT_IDS = {
	energy_small = 2001,
	energy_medium = 2002,
	energy_large = 2003,
	boost_energy = 2004,
	boost_luck = 2005,
	refill = 2006,
}

local function configured()
	return {
		["Shared.Config.Monetization"] = function(config)
			for _, pass in config.Passes do
				pass.id = PASS_IDS[pass.key]
			end
			for _, product in config.Products do
				product.id = PRODUCT_IDS[product.key]
			end
		end,
	}
end

local function producing(rt, player)
	Fixture.request(rt, player, "Admin", "give", "ion_battery||1")
	assert(Fixture.request(rt, player, "Place", 1, "ion_battery||1").ok)
end

return function(t)
	t.test("energy packs are granted once per receipt and saved before confirming", function()
		local backend = DataStore.newBackend()
		local rt = Fixture.server({ backend = backend, modulePatches = configured() })
		local player = Fixture.join(rt, { userId = 7101 })
		local session = Fixture.session(rt, player)
		local before = session.profile.energy
		local decision, purchaseId = rt:completeProductPurchase(player, PRODUCT_IDS.energy_small)
		t.eq(decision, Enum.ProductPurchaseDecision.PurchaseGranted)
		local gained = session.profile.energy - before
		t.ok(gained >= 5000, "at least the pack's minimum: " .. gained)
		-- Roblox retries the same receipt (e.g. it did not see our answer): nothing new.
		local again = rt:completeProductPurchase(player, PRODUCT_IDS.energy_small, purchaseId)
		t.eq(again, Enum.ProductPurchaseDecision.PurchaseGranted)
		t.eq(session.profile.energy - before, gained, "not granted twice")
		local record = rt:asServer(function()
			return rt:requireIn("server", rt.services.ServerScriptService.Server.Services.Data)._peek(7101)
		end)
		t.ok(table.find(record.data.receipts, purchaseId) ~= nil, "receipt stored with the grant")
		t.eq(#rt:errors(), 0, errorsText(rt))
	end)

	t.test("receipts wait for the player and ignore unknown products", function()
		local rt = Fixture.server({ modulePatches = configured() })
		local player = Fixture.join(rt, { userId = 7102 })
		t.eq(
			rt:completeProductPurchase(player, 999999),
			Enum.ProductPurchaseDecision.NotProcessedYet,
			"unknown product"
		)
		rt:removePlayer(player)
		rt:run(1, 0.1)
		t.eq(
			rt:completeProductPurchase(player, PRODUCT_IDS.energy_small),
			Enum.ProductPurchaseDecision.NotProcessedYet,
			"player not in this server: Roblox retries later"
		)
	end)

	t.test("boosts double production while playing, stack, and run out", function()
		local rt = Fixture.server({ isStudio = true, modulePatches = configured() })
		local player = Fixture.join(rt, { userId = 7103 })
		local session = Fixture.session(rt, player)
		producing(rt, player)
		local Sessions = rt:requireIn("server", rt.services.ServerScriptService.Server.Services.Sessions)
		local base = rt:asServer(function()
			return Sessions.production(session).total
		end)
		rt:completeProductPurchase(player, PRODUCT_IDS.boost_energy)
		local boosted = rt:asServer(function()
			return Sessions.production(session).total
		end)
		t.near(boosted, base * 2, 1e-6, "x2 Energy")
		rt:completeProductPurchase(player, PRODUCT_IDS.boost_energy)
		t.eq(session.profile.boosts.energy, 3600, "stacked to an hour")
		rt:run(3605, 5)
		t.eq(session.profile.boosts.energy, nil, "expired")
		local after = rt:asServer(function()
			return Sessions.production(session).total
		end)
		t.near(after, base, 1e-6, "back to normal")
		t.eq(#rt:errors(), 0, errorsText(rt))
	end)

	t.test("game passes apply when bought and are re-checked on join", function()
		local backend = DataStore.newBackend()
		local rt = Fixture.server({ backend = backend, modulePatches = configured() })
		local player = Fixture.join(rt, { userId = 7104 })
		local session = Fixture.session(rt, player)
		local State = Fixture.require(rt, "Logic.State")
		local capacity = State.capacity(session.profile)
		rt:completePassPurchase(player, PASS_IDS.mega_storage, true)
		t.eq(State.capacity(session.profile), capacity + 100, "Mega Storage")
		rt:completePassPurchase(player, PASS_IDS.vip, true)
		local sign = rt:find(rt.workspace, "VoidFactory.Plots.Plot_" .. session.plot .. ".SignPole.Sign.Owner")
		t.ok(string.find(sign.Text, "👑", 1, true) ~= nil, "VIP crown on the sign: " .. sign.Text)
		rt:completePassPurchase(player, PASS_IDS.double_energy, false)
		t.eq(session.profile.passes.double_energy, nil, "cancelled prompt grants nothing")
		-- Rejoin: Roblox says the VIP pass was refunded, Mega Storage still owned.
		rt.marketplace.ownedPasses[7104][PASS_IDS.vip] = nil
		rt:removePlayer(player)
		rt:run(1, 0.1)
		local again = Fixture.join(rt, { userId = 7104 })
		rt:run(1, 0.1)
		local profile = Fixture.session(rt, again).profile
		t.eq(profile.passes.vip, nil, "refunded pass removed")
		t.eq(profile.passes.mega_storage, true)
		t.eq(#rt:errors(), 0, errorsText(rt))
	end)

	t.test("passes owned before joining are detected; check errors keep the saved state", function()
		local backend = DataStore.newBackend()
		local rt = Fixture.server({ backend = backend, modulePatches = configured() })
		rt.marketplace.ownedPasses[7105] = { [PASS_IDS.double_energy] = true }
		local player = Fixture.join(rt, { userId = 7105 })
		rt:run(1, 0.1)
		local session = Fixture.session(rt, player)
		t.eq(session.profile.passes.double_energy, true, "bought on the website")
		rt:removePlayer(player)
		rt:run(1, 0.1)
		rt.marketplace.failOwnership = true
		local again = Fixture.join(rt, { userId = 7105 })
		rt:run(5, 0.25)
		t.eq(Fixture.session(rt, again).profile.passes.double_energy, true, "kept while Roblox is unreachable")
		t.eq(#rt:errors(), 0, errorsText(rt))
	end)

	t.test("Studio test purchases work only in Studio", function()
		local studio = Fixture.server({ isStudio = true })
		local player = Fixture.join(studio, { userId = 7106 })
		local session = Fixture.session(studio, player)
		local response = Fixture.request(studio, player, "StudioPurchase", "boost_luck")
		t.ok(response.ok, tostring(response.err))
		t.eq(session.profile.boosts.luck, 1800)
		t.ok(Fixture.request(studio, player, "StudioPurchase", "turbo_fabricator").ok)
		t.eq(Fixture.request(studio, player, "StudioPurchase", "turbo_fabricator").err, "AlreadyOwned")
		t.eq(Fixture.request(studio, player, "StudioPurchase", "nope").err, "BadRequest")

		local live = Fixture.server({})
		local livePlayer = Fixture.join(live, { userId = 7107 })
		t.eq(Fixture.request(live, livePlayer, "StudioPurchase", "boost_luck").err, "NotAllowed")
	end)

	t.test("codes work once and milestones pay out when the collection grows", function()
		local rt = Fixture.server({ isStudio = true })
		local player = Fixture.join(rt, { userId = 7108 })
		local session = Fixture.session(rt, player)
		local redeemed = Fixture.request(rt, player, "RedeemCode", "voidfactory")
		t.ok(redeemed.ok, tostring(redeemed.err))
		t.ok(session.profile.energy >= 2500)
		t.eq(Fixture.request(rt, player, "RedeemCode", "VOIDFACTORY").err, "CodeUsed")
		t.eq(Fixture.request(rt, player, "RedeemCode", "NOTACODE").err, "InvalidCode")
		local crate = Fixture.request(rt, player, "RedeemCode", "CRATE")
		t.ok(crate.ok and #crate.data.results == 1, "crate code opened a Daily Crate")

		t.eq(Fixture.request(rt, player, "ClaimMilestone", "artifacts_6").err, "MilestoneLocked")
		for _, key in { "scrap_cube||1", "ion_battery||1", "glow_shard||1" } do
			Fixture.request(rt, player, "Admin", "give", key)
		end
		local claimed = Fixture.request(rt, player, "ClaimMilestone", "artifacts_3")
		t.ok(claimed.ok, tostring(claimed.err))
		t.eq(Fixture.request(rt, player, "ClaimMilestone", "artifacts_3").err, "AlreadyClaimed")
		t.eq(#rt:errors(), 0, errorsText(rt))
	end)

	t.test("collection rewards are claimed from Collection → Rewards", function()
		local rt = Fixture.server({ isStudio = true })
		local player = Fixture.join(rt, { userId = 7112, noClient = false })
		rt:run(1, 0.1)
		for _, key in { "scrap_cube||1", "ion_battery||1", "glow_shard||1" } do
			Fixture.request(rt, player, "Admin", "give", key)
		end
		rt:run(1.2, 0.1)
		local ui = player.PlayerGui.VoidFactoryUI
		local button = rt:findDescendant(ui, "CollectionButton")
		t.ok(button.Badge.Visible, "menu badge: a reward is ready")
		rt:click(button)
		rt:run(0.3, 0.1)
		local window = rt:findDescendant(ui, "Window_Collection")
		rt:click(rt:findDescendant(window, "RewardsTab"))
		rt:run(0.3, 0.1)
		local row = rt:findDescendant(window, "artifacts_3")
		t.eq(row.Action.Text, "CLAIM")
		rt:click(row.Action)
		rt:run(0.6, 0.1)
		t.eq(Fixture.session(rt, player).profile.milestones.artifacts_3, true)
		t.eq(rt:findDescendant(window, "artifacts_3").Action.Text, "CLAIMED ✓")
		t.ok(not button.Badge.Visible, "badge cleared")
		t.eq(#rt:errors(), 0, errorsText(rt))
	end)

	t.test("the Store window lists priced items and prompts purchases", function()
		local rt = Fixture.server({ modulePatches = configured() })
		rt.marketplace.prices[PASS_IDS.vip] = 299
		local player = Fixture.join(rt, { userId = 7109, noClient = false })
		rt:run(1, 0.1)
		local ui = player.PlayerGui.VoidFactoryUI
		rt:click(rt:findDescendant(ui, "StoreButton"))
		rt:run(1, 0.1)
		local window = rt:findDescendant(ui, "Window_Store")
		t.ok(window.Visible, "store open")
		local vip = rt:findDescendant(window, "vip")
		t.eq(vip.Action.Text, "R$ 299", "price from Roblox")
		rt:click(vip.Action)
		rt:run(0.2, 0.1)
		local prompt = rt.marketplace.prompts[1]
		t.ok(prompt ~= nil and prompt.kind == "pass" and prompt.id == PASS_IDS.vip, "purchase prompt shown")
		rt:completePassPurchase(player, PASS_IDS.vip, true)
		rt:run(1, 0.1)
		t.eq(rt:findDescendant(window, "vip").Action.Text, "OWNED ✓")
		rt:click(rt:findDescendant(window, "BoostsTab"))
		rt:run(0.5, 0.1)
		t.ok(rt:findDescendant(window, "boost_energy") ~= nil, "boosts listed")
		rt:click(rt:findDescendant(window, "CodesTab"))
		rt:run(0.3, 0.1)
		local input = rt:findDescendant(window, "CodeInput")
		input.Text = "lucky"
		rt:click(rt:findDescendant(window, "Redeem"))
		rt:run(0.5, 0.1)
		t.ok(string.find(rt:findDescendant(window, "CodeResult").Text, "✓", 1, true) ~= nil, "code redeemed")
		t.eq(#rt:errors(), 0, errorsText(rt))
	end)

	t.test("unconfigured items are hidden on live servers and testable in Studio", function()
		local live = Fixture.server({})
		local player = Fixture.join(live, { userId = 7110, noClient = false })
		live:run(1, 0.1)
		live:click(live:findDescendant(player.PlayerGui, "StoreButton"))
		live:run(0.5, 0.1)
		local window = live:findDescendant(player.PlayerGui, "Window_Store")
		t.eq(live:findDescendant(window, "vip"), nil, "no dead buttons for items without an id")

		local studio = Fixture.server({ isStudio = true })
		local tester = Fixture.join(studio, { userId = 7111, noClient = false })
		studio:run(1, 0.1)
		studio:click(studio:findDescendant(tester.PlayerGui, "StoreButton"))
		studio:run(0.5, 0.1)
		local studioWindow = studio:findDescendant(tester.PlayerGui, "Window_Store")
		local row = studio:findDescendant(studioWindow, "double_energy")
		t.eq(row.Action.Text, "Test (Studio)")
		studio:click(row.Action)
		studio:run(1, 0.1)
		t.eq(Fixture.session(studio, tester).profile.passes.double_energy, true, "granted for testing")
		t.eq(#studio:errors(), 0, errorsText(studio))
	end)
end
