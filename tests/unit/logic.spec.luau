-- Unit tests for the pure game logic in ReplicatedStorage.Shared.Logic.

local Fixture = require("../lib/Fixture")

return function(t)
	local rt = Fixture.modules()
	local function req(path)
		return Fixture.require(rt, path)
	end
	local Artifacts = req("Config.Artifacts")
	local Rarities = req("Config.Rarities")
	local Boxes = req("Config.Boxes")
	local Machines = req("Config.Machines")
	local Mutations = req("Config.Mutations")
	local Plot = req("Config.Plot")
	local Economy = req("Config.Economy")
	local Quests = req("Config.Quests")
	local Rebirth = req("Config.Rebirth")
	local MachineStats = req("Logic.MachineStats")
	local Items = req("Logic.Items")
	local Roller = req("Logic.Roller")
	local Effects = req("Logic.Effects")
	local Production = req("Logic.Production")
	local Profile = req("Logic.Profile")
	local State = req("Logic.State")
	local Simulation = req("Logic.Simulation")
	local BoxActions = req("Logic.Actions.Boxes")
	local Factory = req("Logic.Actions.Factory")
	local Shop = req("Logic.Actions.Shop")
	local Fusion = req("Logic.Actions.Fusion")
	local Progression = req("Logic.Actions.Progression")

	local NOW = 1760000000

	local function newProfile()
		return Profile.new(NOW)
	end

	local function production(profile)
		return State.computeProduction(profile)
	end

	t.describe("catalog", function()
		t.test("has about 15 well-formed artifacts covering every rarity", function()
			t.ok(#Artifacts.List >= 15, "at least 15 artifacts")
			local seen = {}
			for _, artifact in Artifacts.List do
				t.ok(not seen[artifact.id], "unique id " .. artifact.id)
				seen[artifact.id] = true
				t.ok(Rarities.isValid(artifact.rarity), "valid rarity for " .. artifact.id)
				t.ok(artifact.weight > 0 and artifact.eps > 0 and artifact.value > 0, "positive stats " .. artifact.id)
				for _, effect in artifact.effects do
					t.ok(Effects.Types[effect.type] ~= nil, "known effect " .. effect.type)
				end
			end
			for _, rarity in Rarities.List do
				t.ok(Artifacts.ByRarity[rarity.id] and #Artifacts.ByRarity[rarity.id] > 0, "artifact in " .. rarity.id)
			end
		end)

		t.test("box tables only reference known rarities and machines reference known boxes", function()
			for _, box in Boxes.List do
				for rarityId, weight in box.rarityWeights do
					t.ok(Rarities.isValid(rarityId), box.id .. " rarity " .. rarityId)
					t.ok(weight >= 0, "non-negative weight")
				end
			end
			for _, machine in Machines.List do
				if machine.box then
					t.ok(Boxes.get(machine.box) ~= nil, machine.id .. " box")
				end
			end
		end)

		t.test("every rarity is obtainable from some box", function()
			for _, rarity in Rarities.List do
				local found = false
				for _, box in Boxes.List do
					if (box.rarityWeights[rarity.id] or 0) > 0 then
						found = true
					end
				end
				t.ok(found, rarity.id .. " obtainable")
			end
		end)
	end)

	t.describe("items", function()
		t.test("keys round-trip and reject malformed input", function()
			local key = Items.key("scrap_cube", "Gold", 2)
			t.eq(key, "scrap_cube|Gold|2")
			local item = Items.parse(key)
			t.eq(item.id, "scrap_cube")
			t.eq(item.mut, "Gold")
			t.eq(item.stars, 2)
			t.eq(Items.keyOf(item), key)
			for _, bad in
				{
					"scrap_cube||0",
					"scrap_cube||6",
					"scrap_cube||01",
					"nope||1",
					"scrap_cube|Plaid|1",
					"scrap_cube|1",
					5,
					nil,
					"scrap_cube||1.5",
					string.rep("x", 200),
				}
			do
				t.eq(Items.parse(bad), nil, "rejects " .. tostring(bad))
			end
		end)

		t.test("multipliers combine stars and mutations", function()
			local plain = Items.parse("ion_battery||1")
			local gold3 = Items.parse("ion_battery|Gold|3")
			t.eq(Items.baseEps(plain), 6)
			t.eq(Items.baseEps(gold3), 6 * 2 * Economy.StarMultipliers[3])
			t.eq(Items.sellValue(gold3), math.floor(25 * 2 * Economy.StarMultipliers[3]))
		end)
	end)

	t.describe("roller", function()
		t.test("odds are normalised for every box and luck level", function()
			for _, box in Boxes.List do
				for _, luck in { 1, 1.5, 3, 10, 25, 1000 } do
					local sum = 0
					for _, entry in Roller.getArtifactOdds(box.id, luck) do
						t.ok(entry.chance > 0, "positive chance")
						sum += entry.chance
					end
					t.near(sum, 1, 1e-9, box.id .. " artifact odds at luck " .. luck)
					local raritySum = 0
					for _, entry in Roller.getRarityOdds(box.id, luck) do
						raritySum += entry.chance
					end
					t.near(raritySum, 1, 1e-9, box.id .. " rarity odds")
				end
			end
		end)

		t.test("luck shifts odds toward rarer tiers and is capped", function()
			local function chanceOf(odds, rarity)
				for _, entry in odds do
					if entry.rarity == rarity then
						return entry.chance
					end
				end
				return 0
			end
			local base = Roller.getRarityOdds("basic", 1)
			local lucky = Roller.getRarityOdds("basic", 3)
			t.ok(
				chanceOf(lucky, "Legendary") > chanceOf(base, "Legendary") * 2.2,
				"legendary boosted (x3 weight, renormalised)"
			)
			t.ok(chanceOf(lucky, "Common") < chanceOf(base, "Common"), "common reduced")
			local capped = Roller.getRarityOdds("basic", Economy.MaxLuck)
			local over = Roller.getRarityOdds("basic", Economy.MaxLuck * 100)
			t.near(chanceOf(over, "Divine"), chanceOf(capped, "Divine"), 1e-12, "luck capped")
			-- NaN luck must not poison the odds.
			t.near(chanceOf(Roller.getRarityOdds("basic", 0 / 0), "Common"), chanceOf(base, "Common"), 1e-12)
		end)

		t.test("void and secret artifacts only drop from the void box", function()
			for _, boxId in { "basic", "lucky" } do
				for _, entry in Roller.getArtifactOdds(boxId, Economy.MaxLuck) do
					t.ok(entry.rarity ~= "Void" and entry.rarity ~= "Secret", boxId .. " never drops " .. entry.rarity)
				end
			end
		end)

		t.test("rolled frequencies match the published odds", function()
			local rng = Fixture.rng(12345)
			local rolls = 200000
			local counts = {}
			for _ = 1, rolls do
				local id = Roller.rollArtifact("basic", 1, rng)
				counts[id] = (counts[id] or 0) + 1
			end
			for _, entry in Roller.getArtifactOdds("basic", 1) do
				local expected = entry.chance * rolls
				local sigma = math.sqrt(rolls * entry.chance * (1 - entry.chance))
				local observed = counts[entry.id] or 0
				t.ok(
					math.abs(observed - expected) <= 5 * sigma + 2,
					string.format("%s observed %d expected %.1f", entry.id, observed, expected)
				)
			end
		end)

		t.test("mutation rolls follow their configured chances", function()
			local rng = Fixture.rng(777)
			local rolls = 100000
			local counts = {}
			for _ = 1, rolls do
				local mut = Roller.rollMutation("basic", rng)
				counts[mut] = (counts[mut] or 0) + 1
			end
			for _, entry in Roller.getMutationOdds("basic") do
				local expected = entry.chance * rolls
				local sigma = math.sqrt(rolls * entry.chance * (1 - entry.chance))
				t.ok(math.abs((counts[entry.id] or 0) - expected) <= 5 * sigma + 2, "mutation " .. entry.id)
			end
			-- The void box doubles mutation chances.
			local voidGold, basicGold = 0, 0
			for _, entry in Roller.getMutationOdds("void") do
				if entry.id == "Gold" then
					voidGold = entry.chance
				end
			end
			for _, entry in Roller.getMutationOdds("basic") do
				if entry.id == "Gold" then
					basicGold = entry.chance
				end
			end
			t.near(voidGold, basicGold * 2, 1e-12)
		end)
	end)

	t.describe("production", function()
		local function place(map)
			local placed = {}
			for slot, key in map do
				placed[slot] = Items.parse(key)
			end
			return placed
		end

		t.test("sums artifact output with multipliers", function()
			local result = Production.compute({
				placed = place({ [1] = "scrap_cube||1", [2] = "ion_battery|Gold|1" }),
				machineBonus = 0.2,
				rebirthMult = 1.5,
				perkBonus = 0.1,
			})
			local expected = (1 + 6 * 2) * 1.2 * 1.5 * 1.1
			t.near(result.total, expected, 1e-9)
		end)

		t.test("reactor boosts everything, gravity well boosts neighbours only", function()
			-- Slots 1 and 2 are neighbours, slot 3 is two columns away from slot 1.
			local result = Production.compute({
				placed = place({
					[1] = "gravity_well||1",
					[2] = "scrap_cube||1",
					[3] = "glow_shard||1",
					[8] = "reactor_core||1",
				}),
			})
			local mult = 1.10
			t.near(result.perSlot[2], 1 * 1.35 * mult, 1e-9, "neighbour of gravity well")
			t.near(result.perSlot[3], 2 * mult, 1e-9, "not a neighbour")
			t.near(result.perSlot[8], 18 * mult, 1e-9, "reactor itself not adjacent to well")
			t.near(result.globalBonus, 0.10, 1e-12)
		end)

		t.test("corrupted mutation drains adjacent pedestals", function()
			local result = Production.compute({
				placed = place({ [1] = "scrap_cube|Corrupted|1", [2] = "glow_shard||1" }),
			})
			t.near(result.perSlot[1], 1 * 5, 1e-9)
			t.near(result.perSlot[2], 2 * (1 - 0.15), 1e-9)
		end)

		t.test("speed bonuses respect the cap and the interval floors", function()
			local profile = newProfile()
			profile.upgrades.speed = 10
			profile.machines.starter_fabricator.level = 10
			profile.machines.box_printer = Profile.newMachineState("box_printer", NOW)
			profile.machines.box_printer.level = 10
			for slot = 1, 6 do
				profile.placed[tostring(slot)] = "chrono_turbine||1"
			end
			local production = State.computeProduction(profile)
			t.ok(State.speedFactor(profile, production) <= 1 + Economy.MaxSpeedBonus + 1e-9, "speed capped")
			t.ok(
				State.chargeInterval(profile, "starter_fabricator", production) >= Economy.MinChargeInterval,
				"charge floor"
			)
			t.ok(State.printerInterval(profile, production) >= Economy.MinPrinterInterval, "printer floor")
		end)

		t.test("luck, duplicate and speed effects are aggregated and capped", function()
			local placed = {}
			for slot = 1, 12 do
				placed[slot] = Items.parse("echo_duplicator||1")
			end
			placed[13] = Items.parse("prism_lens||1")
			placed[14] = Items.parse("flux_coil||1")
			local result = Production.compute({ placed = placed })
			t.eq(result.duplicateChance, Economy.MaxDuplicateChance)
			t.near(result.luckBonus, Artifacts.get("prism_lens").effects[1].amount, 1e-12)
			t.near(result.speedBonus, Artifacts.get("flux_coil").effects[1].amount, 1e-12)
		end)

		t.test("singularity scales with distinct effect types", function()
			local result = Production.compute({
				placed = place({
					[1] = "the_singularity||1",
					[3] = "reactor_core||1",
					[5] = "prism_lens||1",
					[13] = "flux_coil||1",
				}),
			})
			-- Effect types present: global_mult, luck, speed (singularity excluded) => 3 * 12% + reactor 10%.
			t.near(result.globalBonus, 0.10 + 3 * 0.12, 1e-12)
		end)

		t.test("entropy averages to its expected value", function()
			local result = Production.compute({ placed = place({ [1] = "entropy_engine||1" }) })
			t.near(result.total, 160 * 1.75, 1e-9)
			t.eq(#result.entropy, 1)
			local rng = Fixture.rng(99)
			local sum, samples = 0, 20000
			for _ = 1, samples do
				sum += Production.sample(result, 1, rng)
			end
			t.near(sum / samples, 160 * 1.75, 160 * 0.05)
		end)
	end)

	t.describe("boxes", function()
		t.test("starter fabricator uses charges and recharges over time", function()
			local profile = newProfile()
			local cap = State.chargeCap(profile, "starter_fabricator")
			local prod = production(profile)
			for _ = 1, cap do
				local ok, result = BoxActions.open(
					profile,
					"starter_fabricator",
					{ now = NOW, rng = Fixture.rng(1), production = prod }
				)
				t.ok(ok, tostring(result))
				t.eq(result.paid, 0)
			end
			local ok, err =
				BoxActions.open(profile, "starter_fabricator", { now = NOW, rng = Fixture.rng(1), production = prod })
			t.eq(ok, false)
			t.eq(err, "NoCharges")
			local interval = State.chargeInterval(profile, "starter_fabricator", prod)
			ok = BoxActions.open(
				profile,
				"starter_fabricator",
				{ now = NOW + interval * 1.01, rng = Fixture.rng(2), production = prod }
			)
			t.ok(ok, "one charge after one interval")
			t.eq(profile.stats.boxesOpened, cap + 1)
			t.eq(State.inventoryCount(profile), cap + 1)
		end)

		t.test("paid boxes cost energy and refuse when broke", function()
			local profile = newProfile()
			profile.machines.lucky_fabricator = Profile.newMachineState("lucky_fabricator", NOW)
			local prod = production(profile)
			local ok, err =
				BoxActions.open(profile, "lucky_fabricator", { now = NOW, rng = Fixture.rng(3), production = prod })
			t.eq(ok, false)
			t.eq(err, "NotEnoughEnergy")
			local price = State.boxCost(profile, "lucky_fabricator")
			t.ok(price > 0, "lucky boxes have a price")
			profile.energy = price + 100
			local ok2, result =
				BoxActions.open(profile, "lucky_fabricator", { now = NOW, rng = Fixture.rng(3), production = prod })
			t.ok(ok2)
			t.eq(result.paid, price)
			t.ok(profile.energy >= 100, "paid exactly the price (plus any auto-sale)")
			-- The price follows the best production of the run, never the current one.
			profile.runBestEps = 1e6
			t.ok(State.boxCost(profile, "lucky_fabricator") > price, "price scales with best production")
		end)

		t.test("rejects machines that are not owned or cannot open boxes", function()
			local profile = newProfile()
			local prod = production(profile)
			t.eq(
				select(
					2,
					BoxActions.open(profile, "lucky_fabricator", { now = NOW, rng = Fixture.rng(1), production = prod })
				),
				"NotOwned"
			)
			t.eq(
				select(
					2,
					BoxActions.open(profile, "overclocker", { now = NOW, rng = Fixture.rng(1), production = prod })
				),
				"InvalidMachine"
			)
			t.eq(
				select(2, BoxActions.open(profile, "hax", { now = NOW, rng = Fixture.rng(1), production = prod })),
				"InvalidMachine"
			)
		end)

		t.test("full inventory blocks opening; duplicates and auto-sell work", function()
			local profile = newProfile()
			profile.inventory["scrap_cube||1"] = State.capacity(profile)
			local prod = production(profile)
			t.eq(
				select(
					2,
					BoxActions.open(
						profile,
						"starter_fabricator",
						{ now = NOW, rng = Fixture.rng(1), production = prod }
					)
				),
				"InventoryFull"
			)

			local fresh = newProfile()
			local dupProduction = table.clone(production(fresh))
			dupProduction.duplicateChance = 1
			local ok, result = BoxActions.open(
				fresh,
				"starter_fabricator",
				{ now = NOW, rng = Fixture.sequence({ 0.01, 0.99, 0.0 }), production = dupProduction }
			)
			t.ok(ok)
			t.eq(result.duplicated, true)
			t.eq(#result.grants, 2)
			t.eq(State.inventoryCount(fresh), 2)

			-- Auto-sell never sells a brand new discovery, but does sell repeats.
			local seller = newProfile()
			seller.settings.autoSell.Common = true
			local prodSeller = production(seller)
			local _, first = BoxActions.open(
				seller,
				"starter_fabricator",
				{ now = NOW, rng = Fixture.sequence({ 0.01, 0.99, 0.99 }), production = prodSeller }
			)
			t.eq(first.grants[1].sold, false, "first copy kept")
			t.eq(first.grants[1].newArtifact, true)
			local _, second = BoxActions.open(
				seller,
				"starter_fabricator",
				{ now = NOW, rng = Fixture.sequence({ 0.01, 0.99, 0.99 }), production = prodSeller }
			)
			t.eq(second.grants[1].sold, true, "repeat auto-sold")
			t.eq(seller.energy, 4)
		end)
	end)

	t.describe("factory", function()
		t.test("place, swap and remove keep item counts consistent", function()
			local profile = newProfile()
			profile.inventory["scrap_cube||1"] = 2
			profile.inventory["glow_shard||1"] = 1
			t.ok(Factory.place(profile, 1, "scrap_cube||1"))
			t.eq(profile.inventory["scrap_cube||1"], 1)
			local ok, result = Factory.place(profile, 1, "glow_shard||1")
			t.ok(ok)
			t.eq(result.swapped, "scrap_cube||1")
			t.eq(profile.inventory["scrap_cube||1"], 2)
			t.eq(profile.inventory["glow_shard||1"], nil)
			t.ok(Factory.remove(profile, 1))
			t.eq(profile.inventory["glow_shard||1"], 1)
			t.eq(profile.placed["1"], nil)
		end)

		t.test("rejects locked slots, missing items and bad input", function()
			local profile = newProfile()
			profile.inventory["scrap_cube||1"] = 1
			t.eq(select(2, Factory.place(profile, 4, "scrap_cube||1")), "InvalidSlot", "column 4 locked at start")
			t.eq(select(2, Factory.place(profile, 0, "scrap_cube||1")), "InvalidSlot")
			t.eq(select(2, Factory.place(profile, 1.5, "scrap_cube||1")), "InvalidSlot")
			t.eq(select(2, Factory.place(profile, 1, "glow_shard||1")), "NotInInventory")
			t.eq(select(2, Factory.place(profile, 1, "glow_shard||9")), "InvalidItem")
			t.eq(select(2, Factory.remove(profile, 2)), "EmptySlot")
			t.eq(#Plot.unlockedSlots(0), 6)
		end)

		t.test("auto-fill places the best artifacts first", function()
			local profile = newProfile()
			profile.inventory["scrap_cube||1"] = 10
			profile.inventory["reactor_core||1"] = 1
			profile.inventory["ion_battery||1"] = 2
			local ok, result = Factory.autoFill(profile)
			t.ok(ok)
			t.eq(result.placed, 6)
			local placedKeys = {}
			for _, key in profile.placed do
				placedKeys[key] = (placedKeys[key] or 0) + 1
			end
			t.eq(placedKeys["reactor_core||1"], 1)
			t.eq(placedKeys["ion_battery||1"], 2)
			t.eq(placedKeys["scrap_cube||1"], 3)
			t.eq(profile.inventory["scrap_cube||1"], 7)
		end)
	end)

	t.describe("shop", function()
		t.test("machines, upgrades and expansions charge the right price", function()
			local profile = newProfile()
			t.eq(select(2, Shop.buyMachine(profile, "box_printer", NOW)), "NotEnoughEnergy")
			profile.energy = 1e7
			local printerCost = Machines.get("box_printer").cost
			t.ok(Shop.buyMachine(profile, "box_printer", NOW))
			t.eq(profile.energy, 1e7 - printerCost)
			t.eq(select(2, Shop.buyMachine(profile, "box_printer", NOW)), "AlreadyOwned")
			t.eq(select(2, Shop.buyMachine(profile, "void_forge", NOW)), "NeedsRebirth")
			local before = profile.energy
			local ok, result = Shop.upgradeMachine(profile, "box_printer")
			t.ok(ok)
			t.eq(result.cost, MachineStats.upgradeCost("box_printer", 1))
			t.eq(profile.energy, before - result.cost)
			t.eq(profile.machines.box_printer.level, 2)
			local luckCost = State.upgradeCost(profile, "luck")
			t.ok(Shop.buyUpgrade(profile, "luck"))
			t.eq(profile.upgrades.luck, 1)
			t.ok(State.upgradeCost(profile, "luck") > luckCost, "cost grows")
			t.ok(Shop.buyExpansion(profile))
			t.eq(profile.expansion, 1)
			t.eq(#Plot.unlockedSlots(profile.expansion), 9)
		end)

		t.test("selling validates amounts", function()
			local profile = newProfile()
			profile.inventory["reactor_core||1"] = 3
			t.eq(select(2, Shop.sell(profile, "reactor_core||1", 0)), "InvalidAmount")
			t.eq(select(2, Shop.sell(profile, "reactor_core||1", 1.5)), "InvalidAmount")
			t.eq(select(2, Shop.sell(profile, "reactor_core||1", 4)), "NotInInventory")
			t.ok(Shop.sell(profile, "reactor_core||1", 2))
			t.eq(profile.energy, 240)
			t.eq(profile.inventory["reactor_core||1"], 1)
		end)

		t.test("sellRarity keeps mutated and starred items", function()
			local profile = newProfile()
			profile.inventory["scrap_cube||1"] = 5
			profile.inventory["scrap_cube|Gold|1"] = 1
			profile.inventory["scrap_cube||2"] = 1
			local ok, result = Shop.sellRarity(profile, "Common", 1)
			t.ok(ok)
			t.eq(result.sold, 4)
			t.eq(profile.inventory["scrap_cube||1"], 1)
			t.eq(profile.inventory["scrap_cube|Gold|1"], 1)
			t.eq(profile.inventory["scrap_cube||2"], 1)
		end)
	end)

	t.describe("fusion", function()
		t.test("needs the chamber and three identical copies", function()
			local profile = newProfile()
			profile.inventory["ion_battery||1"] = 3
			profile.energy = 1e6
			t.eq(select(2, Fusion.fuse(profile, "ion_battery||1", NOW)), "NeedsFusionChamber")
			profile.machines.fusion_chamber = Profile.newMachineState("fusion_chamber", NOW)
			local ok, result = Fusion.fuse(profile, "ion_battery||1", NOW)
			t.ok(ok)
			t.eq(result.key, "ion_battery||2")
			t.eq(profile.inventory["ion_battery||1"], nil)
			t.eq(profile.inventory["ion_battery||2"], 1)
			t.eq(select(2, Fusion.fuse(profile, "ion_battery||2", NOW)), "NeedThreeCopies")
			profile.inventory["ion_battery||5"] = 3
			t.eq(select(2, Fusion.fuse(profile, "ion_battery||5", NOW)), "MaxStars")
		end)
	end)

	t.describe("progression", function()
		t.test("rebirth resets the run but keeps artifacts and collection", function()
			local profile = newProfile()
			profile.energy = Rebirth.cost(0)
			profile.expansion = 3
			profile.machines.box_printer = Profile.newMachineState("box_printer", NOW)
			profile.upgrades.luck = 4
			profile.placed["16"] = "reactor_core||1" -- slot 16 is row 3, column 4
			profile.placed["1"] = "scrap_cube||1"
			profile.collection.reactor_core = { count = 1, muts = {}, stars = 1, first = NOW }
			local ok, result = Progression.rebirth(profile, NOW)
			t.ok(ok)
			t.eq(profile.rebirths, 1)
			t.eq(result.shards, 2)
			t.eq(profile.energy, 0)
			t.eq(profile.expansion, 0)
			t.eq(profile.machines.box_printer, nil)
			t.ok(profile.machines.starter_fabricator ~= nil)
			t.eq(profile.upgrades.luck, nil)
			t.eq(profile.placed["16"], nil, "locked pedestal emptied")
			t.eq(profile.inventory["reactor_core||1"], 1, "artifact returned")
			t.eq(profile.placed["1"], "scrap_cube||1", "unlocked pedestal kept")
			t.ok(profile.collection.reactor_core ~= nil, "collection kept")
			t.ok(Progression.rebirthCost(profile) > Rebirth.cost(0), "next rebirth costs more")
			t.eq(select(2, Progression.rebirth(profile, NOW)), "NotEnoughEnergy")
		end)

		t.test("perks cost shards and stack", function()
			local profile = newProfile()
			profile.shards = 3
			t.ok(Progression.buyPerk(profile, "efficiency"))
			t.ok(Progression.buyPerk(profile, "efficiency"))
			t.eq(profile.shards, 0)
			t.eq(select(2, Progression.buyPerk(profile, "efficiency")), "NotEnoughShards")
			t.near(State.computeProduction(profile).multiplier, 1.3, 1e-12)
		end)

		t.test("head start perk gives energy after rebirth", function()
			local profile = newProfile()
			profile.perks.headstart = 2
			profile.energy = Rebirth.cost(0)
			t.ok(Progression.rebirth(profile, NOW))
			t.eq(profile.energy, 2500 * 4)
		end)

		t.test("quests only track stats that cost time, items or Energy", function()
			local allowed = {
				boxesOpened = true,
				energyEarned = true,
				foundRare = true,
				foundEpic = true,
				itemsSold = true,
				fusions = true,
				upgradesBought = true,
				discoveries = true,
			}
			for _, quest in Quests.List do
				t.ok(allowed[quest.stat], quest.id .. " uses a non-farmable stat (" .. quest.stat .. ")")
			end
			-- Placing and removing the same artifact never advances a quest.
			local profile = newProfile()
			profile.inventory["scrap_cube||1"] = 1
			Progression.ensureQuests(profile, Fixture.rng(1))
			local before = {}
			for index, questState in profile.quests.active do
				before[index] = Progression.questProgress(profile, questState)
			end
			for _ = 1, 50 do
				Factory.place(profile, 1, "scrap_cube||1")
				Factory.remove(profile, 1)
			end
			for index, questState in profile.quests.active do
				t.eq(Progression.questProgress(profile, questState), before[index], "no progress from place spam")
			end
		end)

		t.test("discovery quests disappear once the collection is complete", function()
			local profile = newProfile()
			for _, artifact in Artifacts.List do
				local muts = {}
				for _, mutation in Mutations.List do
					muts[mutation.id] = true
				end
				profile.collection[artifact.id] = { count = 1, muts = muts, stars = 1, first = NOW }
			end
			t.eq(Progression.remainingDiscoveries(profile), 0)
			t.eq(Progression.questAvailable(profile, "discover"), false)
			for _ = 1, 20 do
				profile.quests.active = {}
				Progression.ensureQuests(profile, Fixture.rng(_))
				for _, questState in profile.quests.active do
					t.ok(questState.id ~= "discover", "discover quest not offered")
				end
			end
		end)

		t.test("quests fill the board, track progress and pay out", function()
			local profile = newProfile()
			local rng = Fixture.rng(5)
			t.ok(Progression.ensureQuests(profile, rng))
			t.eq(#profile.quests.active, Quests.ActiveCount)
			local quest = profile.quests.active[1]
			local def = Quests.ById[quest.id]
			t.eq(select(2, Progression.claimQuest(profile, 1, 0, rng)), "QuestIncomplete")
			profile.stats[def.stat] += quest.target
			local ok, result = Progression.claimQuest(profile, 1, 0, rng)
			t.ok(ok)
			t.eq(result.reward, def.rewardBase)
			t.eq(profile.energy, def.rewardBase)
			t.eq(#profile.quests.active, Quests.ActiveCount, "board refilled")
			t.eq(profile.quests.completed, 1)
			t.eq(select(2, Progression.claimQuest(profile, 9, 0, rng)), "InvalidQuest")
		end)
	end)

	t.describe("profile", function()
		t.test("reconcile turns garbage into a valid profile", function()
			for _, garbage in { nil, 5, "x", {}, { energy = "lots" }, { inventory = 5, placed = { 1, 2, 3 } } } do
				local profile = Profile.reconcile(garbage, NOW)
				t.ok(Profile.validate(profile), "valid from " .. tostring(garbage))
			end
		end)

		t.test("reconcile sanitises values and keeps unknown artifacts aside", function()
			local raw = {
				version = 1,
				energy = 0 / 0,
				rebirths = 3.7,
				inventory = {
					["scrap_cube||1"] = 4,
					["removed_thing||1"] = 2,
					["scrap_cube||1|x"] = 1,
					["glow_shard||1"] = -5,
				},
				placed = { ["1"] = "glow_shard||1", ["20"] = "scrap_cube||1", ["2"] = "ghost||1" },
				machines = { starter_fabricator = { level = 99, charges = 3, chargeAt = NOW }, fake = { level = 1 } },
				upgrades = { luck = 2, hack = 50 },
				settings = { sfx = false, autoSell = { Common = true, Legendary = true } },
			}
			local profile = Profile.reconcile(raw, NOW)
			t.eq(profile.energy, 0)
			t.eq(profile.rebirths, 3)
			t.eq(profile.inventory["scrap_cube||1"], 5, "4 + 1 returned from locked slot 20")
			t.eq(profile.orphaned["removed_thing||1"], 2)
			t.eq(profile.orphaned["ghost||1"], 1)
			t.eq(profile.placed["1"], "glow_shard||1")
			t.eq(profile.placed["20"], nil)
			t.eq(profile.machines.starter_fabricator.level, Machines.get("starter_fabricator").maxLevel)
			t.eq(profile.machines.fake, nil)
			t.eq(profile.upgrades.luck, 2)
			t.eq(profile.upgrades.hack, nil)
			t.eq(profile.settings.sfx, false)
			t.eq(profile.settings.autoSell.Common, true)
			t.eq(profile.settings.autoSell.Legendary, nil)
		end)

		t.test("validate rejects corrupted profiles", function()
			local profile = newProfile()
			profile.energy = math.huge
			t.eq((Profile.validate(profile)), false)
			profile.energy = 0
			profile.machines = {}
			t.eq((Profile.validate(profile)), false)
		end)
	end)

	t.describe("simulation", function()
		t.test("tick integrates production over time", function()
			local profile = newProfile()
			profile.placed["1"] = "ion_battery||1"
			profile.placed["2"] = "scrap_cube||1"
			local runtime = Simulation.newRuntime()
			local rng = Fixture.rng(1)
			for second = 1, 10 do
				Simulation.tick(profile, runtime, 1, NOW + second, rng)
			end
			t.near(profile.energy, 70, 1e-9)
			t.near(profile.stats.energyEarned, 70, 1e-9)
		end)

		t.test("box printer opens boxes on its interval", function()
			local profile = newProfile()
			profile.machines.box_printer = Profile.newMachineState("box_printer", NOW)
			local runtime = Simulation.newRuntime()
			local rng = Fixture.rng(2)
			local printed = 0
			local interval = State.printerInterval(profile, State.computeProduction(profile))
			local seconds = math.floor(interval * 3) + 1
			for second = 0, seconds do
				local events = Simulation.tick(profile, runtime, 1, NOW + second, rng)
				printed += #events.printed
			end
			t.eq(printed, 3, string.format("%.1fs interval over %ds", interval, seconds))
			t.eq(State.inventoryCount(profile), 3)
		end)

		t.test("the anomaly triggers a void surge that multiplies output", function()
			local profile = newProfile()
			profile.placed["1"] = "the_anomaly||1"
			local runtime = Simulation.newRuntime()
			local rng = Fixture.rng(3)
			local started, ended = 0, 0
			local surgeEps = 0
			for second = 0, 340 do
				local events = Simulation.tick(profile, runtime, 1, NOW + second, rng)
				if events.surgeStarted then
					started += 1
					surgeEps = Simulation.getProduction(profile, runtime, NOW + second).total
				end
				if events.surgeEnded then
					ended += 1
				end
			end
			t.eq(started, 1)
			t.eq(ended, 1)
			t.near(surgeEps, 90000 * 3, 1e-6)
		end)
	end)
end
