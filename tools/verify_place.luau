-- Opens the built place file and checks that every script is present and compiles.
-- Usage: lune run tools/verify_place.luau [build/VoidFactory.rbxl]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local path = process.args[1] or "build/VoidFactory.rbxl"
local game = roblox.deserializePlace(fs.readFile(path))

local counts = { Script = 0, LocalScript = 0, ModuleScript = 0 }
local failures = 0
for _, instance in game:GetDescendants() do
	if counts[instance.ClassName] then
		counts[instance.ClassName] += 1
		local ok, err = pcall(luau.compile, instance.Source)
		if not ok then
			failures += 1
			print("COMPILE ERROR in " .. instance:GetFullName() .. ": " .. tostring(err))
		end
	end
end

local function exists(fullPath: string): boolean
	local current = game
	for name in string.gmatch(fullPath, "[^%.]+") do
		current = current:FindFirstChild(name)
		if not current then
			return false
		end
	end
	return true
end

local required = {
	"ServerScriptService.Server",
	"ServerScriptService.Server.Services.Net",
	"ReplicatedStorage.Shared.Config.Artifacts",
	"ReplicatedStorage.Shared.Logic.Roller",
	"StarterPlayer.StarterPlayerScripts.Client",
	"StarterPlayer.StarterPlayerScripts.Client.UI.Hud",
}
for _, fullPath in required do
	if not exists(fullPath) then
		failures += 1
		print("MISSING " .. fullPath)
	end
end

print(string.format("%s: %d Scripts, %d LocalScripts, %d ModuleScripts, %d problems", path, counts.Script, counts.LocalScript, counts.ModuleScript, failures))
process.exit(if failures > 0 then 1 else 0)
