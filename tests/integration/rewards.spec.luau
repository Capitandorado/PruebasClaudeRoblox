-- Offline progress and daily rewards end to end: server, DataStore and the real client UI.

local Fixture = require("../lib/Fixture")
local DataStore = require("../mock/DataStore")

local function errorsText(rt)
	local lines = {}
	for _, err in rt:errors() do
		table.insert(lines, err.trace)
	end
	return table.concat(lines, "\n")
end

local function startProducing(rt, player)
	Fixture.request(rt, player, "Admin", "give", "ion_battery||1")
	local placed = Fixture.request(rt, player, "Place", 1, "ion_battery||1")
	assert(placed.ok, tostring(placed.err))
end

return function(t)
	t.test("returning players get offline progress and a welcome-back summary", function()
		local backend = DataStore.newBackend()
		local rt = Fixture.server({ backend = backend, isStudio = true })
		local Economy = Fixture.require(rt, "Config.Economy")
		local player = Fixture.join(rt, { userId = 5101 })
		startProducing(rt, player)
		rt:run(3, 0.25)
		rt:removePlayer(player)
		rt:run(2, 0.1)
		local saved = rt:asServer(function()
			return rt:requireIn("server", rt.services.ServerScriptService.Server.Services.Data)._peek(5101)
		end)
		local savedEnergy = saved.data.energy
		local away = Economy.OfflineMinSeconds + 900
		rt:run(away, 5)

		local again = Fixture.join(rt, { userId = 5101, noClient = false })
		rt:run(1, 0.1)
		local session = Fixture.session(rt, again)
		t.ok(session.profile.energy > savedEnergy + 1, "offline energy credited")
		local popup = rt:findDescendant(again.PlayerGui, "WelcomeBack")
		t.ok(popup ~= nil, "welcome-back popup shown")
		local energyLabel = rt:findDescendant(popup, "Energy")
		t.ok(string.find(energyLabel.Text, "+", 1, true) ~= nil, energyLabel.Text)
		rt:click(rt:findDescendant(popup, "Continue"))
		rt:run(0.3, 0.1)
		t.eq(rt:findDescendant(again.PlayerGui, "WelcomeBack"), nil, "dismissed")
		t.eq(#rt:errors(), 0, errorsText(rt))
	end)

	t.test("quick rejoins give nothing and show no popup", function()
		local backend = DataStore.newBackend()
		local rt = Fixture.server({ backend = backend, isStudio = true })
		local player = Fixture.join(rt, { userId = 5102 })
		startProducing(rt, player)
		rt:run(3, 0.25)
		rt:removePlayer(player)
		rt:run(30, 1)
		local again = Fixture.join(rt, { userId = 5102, noClient = false })
		rt:run(1, 0.1)
		t.eq(rt:findDescendant(again.PlayerGui, "WelcomeBack"), nil)
		t.eq(#rt:errors(), 0, errorsText(rt))
	end)

	t.test("the debug panel can simulate time away", function()
		local rt = Fixture.server({ isStudio = true })
		local player = Fixture.join(rt, { userId = 5103, noClient = false })
		startProducing(rt, player)
		local response = Fixture.request(rt, player, "Admin", "away", 7200)
		t.ok(response.ok, tostring(response.err))
		t.ok(response.data.gained > 0)
		rt:run(0.5, 0.1)
		t.ok(rt:findDescendant(player.PlayerGui, "WelcomeBack") ~= nil, "popup shown")
		t.eq(#rt:errors(), 0, errorsText(rt))
	end)

	t.test("daily rewards are claimed from Quests → Daily, including crates", function()
		local rt = Fixture.server({ isStudio = true })
		local player = Fixture.join(rt, { userId = 5104, noClient = false })
		local session = Fixture.session(rt, player)
		local ui = player.PlayerGui.VoidFactoryUI
		rt:run(1.5, 0.1)
		local badge = rt:findDescendant(ui, "QuestsButton"):FindFirstChild("Badge")
		t.ok(badge.Visible, "menu badge shows the reward is ready")
		rt:click(rt:findDescendant(ui, "QuestsButton"))
		rt:run(0.3, 0.1)
		local window = rt:findDescendant(ui, "Window_Quests")
		rt:click(rt:findDescendant(window, "DailyTab"))
		rt:run(0.3, 0.1)
		local claim = rt:findDescendant(window, "ClaimDaily")
		t.ok(rt:findDescendant(window, "DailyPage").Visible)
		t.eq(claim.Text, "CLAIM DAY 1")
		rt:click(claim)
		rt:run(0.5, 0.1)
		t.eq(session.profile.daily.streak, 1)
		t.ok(session.profile.energy > 0, "energy reward")
		t.eq(claim:GetAttribute("Disabled"), true, "no second claim today")
		t.ok(not badge.Visible, "badge cleared")

		-- Days 2 and 3 (the debug panel moves the last claim back a day).
		for day = 2, 3 do
			t.ok(Fixture.request(rt, player, "Admin", "nextDay", true).ok)
			rt:run(1.2, 0.1)
			t.eq(claim.Text, "CLAIM DAY " .. day)
			rt:click(claim)
			rt:run(0.5, 0.1)
		end
		t.eq(session.profile.daily.streak, 3)
		t.eq(session.profile.stats.boxesOpened, 1, "day 3 opened a Daily Crate")
		t.eq(rt:findDescendant(ui, "Window_Quests").Visible, false, "window closed for the reveal")
		rt:run(8, 1 / 30)
		local items = 0
		for _, count in session.profile.inventory do
			items += count
		end
		t.eq(items, 1, "crate artifact in the inventory")
		t.eq(#rt:errors(), 0, errorsText(rt))
	end)

	t.test("returning players are shown the daily reward when they join", function()
		local backend = DataStore.newBackend()
		local rt = Fixture.server({ backend = backend, isStudio = true })
		local DailyConfig = Fixture.require(rt, "Config.Daily")
		local player = Fixture.join(rt, { userId = 5105 })
		local session = Fixture.session(rt, player)
		local today = math.floor(rt:asServer(function()
			return workspace:GetServerTimeNow()
		end) / DailyConfig.DaySeconds)
		session.profile.daily = { day = today - 1, streak = 2, claims = 2 }
		rt:removePlayer(player)
		rt:run(2, 0.1)
		local again = Fixture.join(rt, { userId = 5105, noClient = false })
		rt:run(2, 0.1)
		local window = rt:findDescendant(again.PlayerGui, "Window_Quests")
		t.ok(window ~= nil and window.Visible, "Quests window opened")
		t.ok(rt:findDescendant(window, "DailyPage").Visible, "on the Daily tab")
		t.eq(rt:findDescendant(window, "ClaimDaily").Text, "CLAIM DAY 3")
		t.eq(#rt:errors(), 0, errorsText(rt))
	end)
end
