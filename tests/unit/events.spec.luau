-- Timed events, event catalogs and the collection bonus.

local Fixture = require("../lib/Fixture")

return function(t)
	local rt = Fixture.modules()
	local function req(path)
		return Fixture.require(rt, path)
	end
	local EventsConfig = req("Config.Events")
	local Economy = req("Config.Economy")
	local Events = req("Logic.Events")
	local Roller = req("Logic.Roller")
	local Profile = req("Logic.Profile")
	local State = req("Logic.State")
	local Progression = req("Logic.Actions.Progression")

	local BASE = 1760000400 -- a multiple of the rotating period

	local function hasArtifact(boxId, id)
		for _, entry in Roller.getArtifactOdds(boxId, 1) do
			if entry.id == id then
				return true
			end
		end
		return false
	end

	t.test("rotating events run for the first part of every window, identically everywhere", function()
		local window = math.floor(BASE / EventsConfig.Period) * EventsConfig.Period
		local first = Events.modifiersAt(window + 10)
		local again = Events.modifiersAt(window + 20)
		t.eq(#first.active, 1, "one rotating event")
		t.eq(first.signature, again.signature, "deterministic")
		t.eq(first.endsAt, window + EventsConfig.Duration)
		local after = Events.modifiersAt(window + EventsConfig.Duration + 1)
		t.eq(#after.active, 0, "ended after its duration")
		-- Over many windows every rotating event shows up.
		local seen = {}
		for index = 0, 200 do
			local mods = Events.modifiersAt(window + index * EventsConfig.Period)
			seen[mods.signature] = true
		end
		for _, event in EventsConfig.Rotating do
			t.ok(seen[event.id], event.id .. " occurs")
		end
	end)

	t.test("event modifiers change luck, production and mutations", function()
		local profile = Profile.new(BASE)
		local production = State.computeProduction(profile)
		local baseLuck = State.luck(profile, "starter_fabricator", production)
		Events.set({
			luckMult = 2,
			productionMult = 3,
			speedBonus = 0,
			mutationMult = 2,
			catalogs = { core = true },
			active = {},
			signature = "test",
			endsAt = 0,
		})
		local boosted = State.computeProduction(profile)
		t.near(State.luck(profile, "starter_fabricator", boosted), baseLuck * 2, 1e-9)
		t.near(boosted.multiplier, production.multiplier * 3, 1e-9)
		local gold = 0
		for _, entry in Roller.getMutationOdds("basic") do
			if entry.id == "Gold" then
				gold = entry.chance
			end
		end
		t.near(gold, 0.06, 1e-12, "gold chance doubled")
		Events.set(nil)
	end)

	t.test("seasonal artifacts only drop during their event", function()
		Events.set(nil)
		t.eq(hasArtifact("basic", "frost_shard"), false, "not outside the event")
		local winter = EventsConfig.Scheduled[1]
		Events.refresh(winter.startsAt + 3600)
		t.ok(Events.catalogActive("winter"), "winter catalog active")
		t.ok(hasArtifact("basic", "frost_shard"), "drops during the event")
		local sum = 0
		for _, entry in Roller.getArtifactOdds("basic", 1) do
			sum += entry.chance
		end
		t.near(sum, 1, 1e-9, "odds still normalised")
		Events.refresh(winter.endsAt + 1)
		t.eq(hasArtifact("basic", "frost_shard"), false, "gone after the event")
		Events.set(nil)
	end)

	t.test("discovery quests ignore artifacts that cannot drop right now", function()
		Events.set(nil)
		local profile = Profile.new(BASE)
		local remaining = Progression.remainingDiscoveries(profile)
		local winter = EventsConfig.Scheduled[1]
		Events.refresh(winter.startsAt + 10)
		t.ok(Progression.remainingDiscoveries(profile) > remaining, "event adds discoverable variants")
		Events.set(nil)
	end)

	t.test("the collection gives a permanent production bonus", function()
		Events.set(nil)
		local profile = Profile.new(BASE)
		profile.placed["1"] = "scrap_cube||1"
		local before = State.computeProduction(profile).total
		profile.collection.scrap_cube = { count = 1, muts = { Gold = true }, stars = 1, first = BASE }
		profile.collection.glow_shard = { count = 1, muts = {}, stars = 1, first = BASE }
		local bonus = Economy.CollectionBonusPerArtifact * 2 + Economy.CollectionBonusPerVariant
		t.near(State.collectionBonus(profile), bonus, 1e-12)
		t.near(State.computeProduction(profile).total, before * (1 + bonus), 1e-9)
	end)
end
