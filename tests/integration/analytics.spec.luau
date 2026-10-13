-- Analytics: onboarding funnel, aggregated economy events, progression and custom events.

local Fixture = require("../lib/Fixture")
local DataStore = require("../mock/DataStore")

local function errorsText(rt)
	local lines = {}
	for _, err in rt:errors() do
		table.insert(lines, err.trace)
	end
	return table.concat(lines, "\n")
end

local function count(list, prefix)
	local total = 0
	for _, text in list do
		if string.sub(text, 1, #prefix) == prefix then
			total += 1
		end
	end
	return total
end

return function(t)
	t.test("a new player's first session walks the onboarding funnel once, in order", function()
		local rt = Fixture.server({ isStudio = true })
		local player = Fixture.join(rt, { userId = 6101 })
		local opened = Fixture.request(rt, player, "OpenBox", "starter_fabricator")
		t.ok(opened.ok, tostring(opened.err))
		t.ok(Fixture.request(rt, player, "Place", 1, opened.data.grants[1].key).ok)
		Fixture.request(rt, player, "OpenBox", "starter_fabricator")
		Fixture.request(rt, player, "Admin", "energy", 1e6)
		t.ok(Fixture.request(rt, player, "BuyMachine", "box_printer").ok)
		t.ok(Fixture.request(rt, player, "BuyExpansion").ok)
		local funnel = {}
		for _, text in rt:outputOf("analytics") do
			if string.sub(text, 1, 10) == "Onboarding" then
				table.insert(funnel, text)
			end
		end
		t.eq(
			table.concat(funnel, ", "),
			table.concat({
				"Onboarding 1 Joined",
				"Onboarding 2 OpenedFirstBox",
				"Onboarding 3 PlacedFirstArtifact",
				"Onboarding 4 BoughtBoxPrinter",
				"Onboarding 5 FirstExpansion",
			}, ", ")
		)
		t.eq(#rt:errors(), 0, errorsText(rt))
	end)

	t.test("returning players are not counted in the onboarding funnel", function()
		local backend = DataStore.newBackend()
		local rt = Fixture.server({ backend = backend, isStudio = true })
		local player = Fixture.join(rt, { userId = 6102 })
		Fixture.request(rt, player, "OpenBox", "starter_fabricator")
		rt:run(3, 0.5)
		rt:removePlayer(player)
		rt:run(2, 0.1)
		local before = count(rt:outputOf("analytics"), "Onboarding")
		local again = Fixture.join(rt, { userId = 6102 })
		Fixture.request(rt, again, "OpenBox", "starter_fabricator")
		t.eq(count(rt:outputOf("analytics"), "Onboarding"), before, "no new funnel steps")
		t.eq(#rt:errors(), 0, errorsText(rt))
	end)

	t.test("economy events are aggregated and flushed once a minute", function()
		local rt = Fixture.server({ isStudio = true })
		local player = Fixture.join(rt, { userId = 6103 })
		Fixture.request(rt, player, "Admin", "give", "ion_battery||1")
		Fixture.request(rt, player, "Place", 1, "ion_battery||1")
		Fixture.request(rt, player, "Admin", "energy", 1e6)
		t.ok(Fixture.request(rt, player, "UpgradeMachine", "starter_fabricator").ok)
		t.ok(Fixture.request(rt, player, "UpgradeMachine", "starter_fabricator").ok)
		rt:run(61, 1)
		local events = rt:outputOf("analytics")
		t.eq(count(events, "Economy Sink Energy"), 1, "two upgrades, one aggregated event")
		t.eq(count(events, "Economy Source Energy"), 1, "production summed into one event")
		local upgrade = nil
		for _, text in events do
			if string.find(text, "MachineUpgrade:starter_fabricator", 1, true) then
				upgrade = text
			end
		end
		t.ok(upgrade ~= nil and string.find(upgrade, "Shop", 1, true) ~= nil, tostring(upgrade))
		rt:run(61, 1)
		t.eq(count(rt:outputOf("analytics"), "Economy Sink Energy"), 1, "nothing new to send")
		t.eq(#rt:errors(), 0, errorsText(rt))
	end)

	t.test("rebirths, perks and daily claims are reported", function()
		local rt = Fixture.server({ isStudio = true })
		local player = Fixture.join(rt, { userId = 6104 })
		local Rebirth = Fixture.require(rt, "Config.Rebirth")
		Fixture.request(rt, player, "Admin", "energy", Rebirth.cost(0) + 1)
		t.ok(Fixture.request(rt, player, "Rebirth").ok)
		t.ok(Fixture.request(rt, player, "BuyPerk", "efficiency").ok)
		t.ok(Fixture.request(rt, player, "ClaimDaily").ok)
		rt:run(61, 1)
		local events = rt:outputOf("analytics")
		t.eq(count(events, "Progression Rebirth 1"), 1)
		t.eq(count(events, "Economy Source Shards"), 1)
		t.eq(count(events, "Economy Sink Shards"), 1)
		t.eq(count(events, "Custom DailyStreak 1"), 1)
		t.eq(count(events, "Economy Source Energy"), 1, "daily reward (no production yet)")
		t.eq(#rt:errors(), 0, errorsText(rt))
	end)
end
