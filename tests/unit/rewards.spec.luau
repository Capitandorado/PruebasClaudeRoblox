-- Offline progress and daily rewards (pure logic).

local Fixture = require("../lib/Fixture")

return function(t)
	local rt = Fixture.modules()
	local function req(path)
		return Fixture.require(rt, path)
	end
	local Economy = req("Config.Economy")
	local DailyConfig = req("Config.Daily")
	local Rarities = req("Config.Rarities")
	local Profile = req("Logic.Profile")
	local State = req("Logic.State")
	local Items = req("Logic.Items")
	local Offline = req("Logic.Offline")
	local Daily = req("Logic.Actions.Daily")

	local NOW = 1760000000
	local DAY = DailyConfig.DaySeconds

	local function producingProfile()
		local profile = Profile.new(NOW)
		profile.placed["1"] = "ion_battery||1"
		profile.placed["2"] = "scrap_cube||1"
		return profile
	end

	local function steadyEps(profile)
		return State.computeProduction(profile, 1, 1).total
	end

	t.describe("offline progress", function()
		t.test("nothing for new profiles or short absences", function()
			local profile = producingProfile()
			t.eq(Offline.apply(profile, NOW, Fixture.rng(1)), nil, "never online")
			profile.lastOnline = NOW - (Economy.OfflineMinSeconds - 1)
			t.eq(Offline.apply(profile, NOW, Fixture.rng(1)), nil, "under the minimum")
			t.eq(profile.energy, 0)
		end)

		t.test("pays a share of steady production for the time away", function()
			local profile = producingProfile()
			profile.lastOnline = NOW - 3600
			local eps = steadyEps(profile)
			local result = Offline.apply(profile, NOW, Fixture.rng(1))
			t.ok(result ~= nil)
			t.eq(result.seconds, 3600)
			t.eq(result.rate, Economy.OfflineRate)
			t.eq(result.energy, math.floor(eps * 3600 * Economy.OfflineRate))
			t.eq(profile.energy, result.energy, "credited")
			t.eq(profile.runEnergy, result.energy, "counts toward rebirth")
			t.eq(profile.lastOnline, NOW, "stamped so it cannot be claimed twice")
			t.eq(Offline.apply(profile, NOW + 10, Fixture.rng(1)), nil)
		end)

		t.test("is capped in time and raised by Night Shift", function()
			local profile = producingProfile()
			profile.lastOnline = NOW - 3 * 86400
			local result = Offline.apply(profile, NOW, Fixture.rng(1))
			t.eq(result.seconds, Economy.OfflineMaxHours * 3600, "capped")
			t.eq(result.away, 3 * 86400)
			profile.perks.nightshift = 2
			t.near(Offline.rate(profile), Economy.OfflineRate + 0.2, 1e-9)
			profile.perks.nightshift = 99
			t.eq(Offline.rate(profile), Economy.OfflineMaxRate, "rate capped")
		end)

		t.test("the Box Printer banks a few boxes, never more than storage allows", function()
			local profile = producingProfile()
			profile.machines.box_printer = { level = 1, charges = 0, chargeAt = NOW }
			profile.lastOnline = NOW - 7200
			local result = Offline.apply(profile, NOW, Fixture.rng(3))
			t.eq(#result.grants, Economy.PrinterBacklog)
			t.eq(profile.stats.boxesOpened, Economy.PrinterBacklog)

			local full = producingProfile()
			full.machines.box_printer = { level = 1, charges = 0, chargeAt = NOW }
			full.inventory["scrap_cube||1"] = State.capacity(full) - 1
			full.lastOnline = NOW - 7200
			local partial = Offline.apply(full, NOW, Fixture.rng(3))
			t.eq(#partial.grants, 1, "stops when storage is full")
		end)

		t.test("reconcile keeps lastOnline and daily data sane", function()
			local profile = Profile.reconcile({
				lastOnline = NOW + 5000,
				daily = { day = 1e12, streak = -4, claims = "x" },
			}, NOW)
			t.eq(profile.lastOnline, NOW, "future timestamps clamp to now")
			t.eq(profile.daily.day, math.floor(NOW / DAY), "future days clamp to today")
			t.eq(profile.daily.streak, 0)
			t.eq(profile.daily.claims, 0)
		end)
	end)

	t.describe("daily rewards", function()
		local function context(eps, seed)
			return {
				now = NOW,
				rng = Fixture.rng(seed or 1),
				production = { total = eps, duplicateChance = 0, luckBonus = 0 },
			}
		end

		t.test("first claim starts the streak; a second claim the same day is refused", function()
			local profile = Profile.new(NOW)
			local status = Daily.status(profile, NOW)
			t.ok(status.available)
			t.eq(status.index, 1)
			local ok, result = Daily.claim(profile, NOW, context(0))
			t.ok(ok, tostring(result))
			t.eq(result.energy, DailyConfig.Rewards[1].min, "floor for players without production")
			t.eq(profile.energy, result.energy)
			t.eq(profile.daily.streak, 1)
			local again, err = Daily.claim(profile, NOW + 60, context(0))
			t.eq(again, false)
			t.eq(err, "AlreadyClaimed")
			local later = Daily.status(profile, NOW)
			t.eq(later.available, false)
			t.ok(later.nextIn > 0 and later.nextIn <= DAY)
		end)

		t.test("consecutive days grow the streak; a missed day restarts it", function()
			local profile = Profile.new(NOW)
			Daily.claim(profile, NOW, context(0))
			Daily.claim(profile, NOW + DAY, context(0))
			t.eq(profile.daily.streak, 2)
			local skipped = Daily.status(profile, NOW + 3 * DAY)
			t.eq(skipped.streak, 1, "streak lost after skipping a day")
			t.eq(skipped.index, 1)
		end)

		t.test("energy rewards scale with production", function()
			local reward = DailyConfig.Rewards[2]
			t.eq(Daily.energyFor(reward, 0), reward.min)
			t.eq(Daily.energyFor(reward, 1000), 1000 * reward.seconds)
		end)

		t.test("crate days roll Rare or better and need free storage", function()
			local profile = Profile.new(NOW)
			for day = 1, 2 do
				Daily.claim(profile, NOW + (day - 1) * DAY, context(0))
			end
			profile.inventory["scrap_cube||1"] = State.capacity(profile)
			local blocked, err = Daily.claim(profile, NOW + 2 * DAY, context(0))
			t.eq(blocked, false)
			t.eq(err, "InventoryFull")
			profile.inventory["scrap_cube||1"] = nil
			local ok, result = Daily.claim(profile, NOW + 2 * DAY, context(0, 7))
			t.ok(ok, tostring(result))
			t.eq(result.day, 3)
			t.eq(#result.results, 1)
			local grant = result.results[1].grants[1]
			local item = Items.parse(grant.key)
			t.ok(Rarities.order(Items.rarityOf(item)) >= Rarities.order("Rare"), "crate rolled " .. grant.key)
			t.eq(profile.inventory[grant.key], 1)
		end)

		t.test("the track repeats after day 7", function()
			local profile = Profile.new(NOW)
			for day = 1, 8 do
				local ok, err = Daily.claim(profile, NOW + (day - 1) * DAY, context(100, day))
				t.ok(ok, "day " .. day .. ": " .. tostring(err))
			end
			t.eq(profile.daily.streak, 8)
			t.eq(Daily.status(profile, NOW + 8 * DAY).index, 2)
			t.eq(profile.daily.claims, 8)
		end)
	end)
end
