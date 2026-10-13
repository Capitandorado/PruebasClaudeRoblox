-- VOID FACTORY server entry point: loads every service, then initialises and starts them
-- in dependency order. Services never trust the client: see Services/Net.

local Services = script:WaitForChild("Services")

local ORDER = {
	"Net",
	"Analytics",
	"Data",
	"World",
	"Plots",
	"Sessions",
	"Leaderboards",
	"Game",
	"Monetization",
	"Simulation",
	"Admin",
}

local loaded = {}
for _, name in ORDER do
	local module = Services:FindFirstChild(name)
	if module then
		loaded[name] = require(module)
	end
end

for _, name in ORDER do
	local service = loaded[name]
	if service and service.init then
		service.init()
	end
end

for _, name in ORDER do
	local service = loaded[name]
	if service and service.start then
		service.start()
	end
end

print("[VoidFactory] server ready")
