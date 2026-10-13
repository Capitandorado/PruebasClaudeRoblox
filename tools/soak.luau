-- Soak test: several players with the real UI play for a long simulated session (auto-open,
-- purchases, placement, windows, visits, rejoin) while instance counts are tracked to catch
-- leaks. Usage: lune run tools/soak.luau [minutes=30] [players=4]

local process = require("@lune/process")
local Fixture = require("../tests/lib/Fixture")
local DataStore = require("../tests/mock/DataStore")
local Instance = require("../tests/mock/Instance")

local minutes = tonumber(process.args[1]) or 30
local playerCount = tonumber(process.args[2]) or 4

local backend = DataStore.newBackend()
local rt = Fixture.server({ backend = backend, isStudio = true })
local players = {}
for index = 1, playerCount do
	players[index] = Fixture.join(rt, { userId = 2000 + index, name = "Soak" .. index, noClient = false })
end
rt:run(1, 0.1)

local function countDescendants(root)
	return #Instance.descendants(root)
end

local function snapshot()
	local guiCount = 0
	for _, player in players do
		if player.Parent then
			guiCount += countDescendants(player.PlayerGui)
		end
	end
	return { workspace = countDescendants(rt.workspace), gui = guiCount, timed = #rt.scheduler.timed }
end

local rng = Fixture.rng(99)
local windows = { "Inventory", "Collection", "Shop", "Upgrades", "Quests", "Rebirth", "Leaderboard", "Settings" }
local samples = {}
for minute = 1, minutes do
	for index, player in players do
		if not player.Parent then
			continue
		end
		local ui = player.PlayerGui:FindFirstChild("VoidFactoryUI")
		local roll = rng:NextNumber()
		if minute == 1 then
			rt:click(rt:findDescendant(ui, "AutoButton"))
		end
		Fixture.request(rt, player, "Admin", "energy", 5000 * minute)
		if roll < 0.3 then
			Fixture.request(rt, player, "AutoFill")
		elseif roll < 0.5 then
			for _, machine in { "box_printer", "overclocker", "fusion_chamber", "lucky_fabricator" } do
				Fixture.request(rt, player, "BuyMachine", machine)
			end
			Fixture.request(rt, player, "UpgradeMachine", "starter_fabricator")
		elseif roll < 0.6 then
			Fixture.request(rt, player, "BuyExpansion")
			Fixture.request(rt, player, "BuyUpgrade", "storage")
		elseif roll < 0.75 then
			local window = windows[math.floor(rng:NextNumber() * #windows) + 1]
			rt:click(rt:findDescendant(ui, window .. "Button"))
		elseif roll < 0.85 then
			local other = players[(index % #players) + 1]
			Fixture.request(rt, player, "Visit", other.UserId)
		else
			Fixture.request(rt, player, "GoHome")
			Fixture.request(rt, player, "SellRarity", "Common", 1)
		end
		for slot = 1, 3 do
			Fixture.request(rt, player, "ClaimQuest", slot)
		end
	end
	-- One player leaves and rejoins halfway through.
	if minute == math.floor(minutes / 2) then
		rt:removePlayer(players[1])
		rt:run(3, 0.25)
		players[1] = Fixture.join(rt, { userId = 2001, name = "Soak1", noClient = false })
		rt:click(rt:findDescendant(players[1].PlayerGui.VoidFactoryUI, "AutoButton"))
	end
	rt:run(60, 0.25)
	local sample = snapshot()
	table.insert(samples, sample)
	if minute % 5 == 0 or minute == 1 then
		print(
			string.format(
				"min %3d  workspace %6d  gui %6d  timers %4d  errors %d",
				minute,
				sample.workspace,
				sample.gui,
				sample.timed,
				#rt:errors()
			)
		)
	end
end

local opened = 0
for _, player in players do
	local session = Fixture.session(rt, player)
	opened += session.profile.stats.boxesOpened
end
print("boxes opened:", opened)
for _, err in rt:errors() do
	print("ERROR", err.context, err.trace)
	break
end
local warnings = {}
for _, entry in rt.output do
	if entry.kind == "warn" or entry.kind == "netwarn" then
		warnings[entry.text] = (warnings[entry.text] or 0) + 1
	end
end
for text, count in warnings do
	print(string.format("WARN x%d %s", count, text))
end
local first, last = samples[5] or samples[1], samples[#samples]
print(
	string.format(
		"growth after warm-up: workspace %+d, gui %+d",
		last.workspace - first.workspace,
		last.gui - first.gui
	)
)
print("shutdown ok:", rt:shutdown())
process.exit(if #rt:errors() > 0 then 1 else 0)
