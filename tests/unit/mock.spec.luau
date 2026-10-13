-- Sanity checks for the mock runtime itself, so integration results can be trusted.

local Runtime = require("../mock/Runtime")

return function(t)
	t.test("rejects members that do not exist in Roblox", function()
		local rt = Runtime.new()
		rt:asServer(function()
			local part = Instance.new("Part")
			part.Anchored = true
			part.Color = Color3.new(1, 0, 0)
			t.errors(function()
				(part :: any).Colour = Color3.new(1, 0, 0)
			end, "not a valid member")
			t.errors(function()
				return (part :: any).Velocty
			end, "not a valid member")
			t.errors(function()
				part.Anchored = 1 :: any
			end, "bool expected")
			t.errors(function()
				Instance.new("NotARealClass")
			end, "Unable to create")
			part.Material = Enum.Material.Neon
			t.eq(part.Material, Enum.Material.Neon)
		end)
	end)

	t.test("hierarchy, signals and WaitForChild", function()
		local rt = Runtime.new()
		rt:asServer(function()
			local folder = Instance.new("Folder")
			folder.Parent = workspace
			local added = 0
			folder.ChildAdded:Connect(function()
				added += 1
			end)
			task.delay(1, function()
				local child = Instance.new("Part")
				child.Name = "Late"
				child.Parent = folder
			end)
			local child = folder:WaitForChild("Late", 5)
			t.ok(child ~= nil, "WaitForChild returned the child")
			t.eq(added, 1)
			t.eq(folder:WaitForChild("Missing", 0.5), nil)
			child:Destroy()
			t.eq(child.Parent, nil)
			t.errors(function()
				child.Parent = folder
			end, "locked")
		end)
	end)

	t.test("remote functions copy arguments and run in the server VM", function()
		local rt = Runtime.new()
		local remote
		rt:asServer(function()
			remote = Instance.new("RemoteFunction")
			remote.Parent = game:GetService("ReplicatedStorage")
			remote.OnServerInvoke = function(player, payload)
				t.ok(game:GetService("RunService"):IsServer())
				payload.mutated = true
				return { echo = payload.value, from = player.UserId }
			end
		end)
		local player = rt:addPlayer({ userId = 42, noClient = true })
		local payload = { value = 7 }
		local result = rt:asClient(player, function()
			t.ok(game:GetService("RunService"):IsClient())
			t.eq(game:GetService("Players").LocalPlayer, player)
			return remote:InvokeServer(payload)
		end)
		t.eq(result.echo, 7)
		t.eq(result.from, 42)
		t.eq(payload.mutated, nil, "server must not mutate the client's table")
	end)

	t.test("module caches are per VM", function()
		local rt = Runtime.new()
		rt:loadSourcemap("sourcemap.json")
		local module = rt.services.ReplicatedStorage.Shared.Config.Economy
		local serverCopy = rt:requireIn("server", module)
		local player = rt:addPlayer({ noClient = true })
		local clientCopy = rt:requireIn(player, module)
		t.ok(serverCopy ~= clientCopy, "server and client get different module instances")
	end)

	t.test("datastore round-trips JSON and rejects non-serialisable values", function()
		local rt = Runtime.new()
		rt:asServer(function()
			local store = game:GetService("DataStoreService"):GetDataStore("Test")
			store:SetAsync("k", { a = 1, list = { 1, 2, 3 } })
			local value = store:GetAsync("k")
			t.eq(value.list[3], 3)
			t.errors(function()
				store:SetAsync("bad", { v = Vector3.new(1, 2, 3) })
			end, "Cannot store")
			t.errors(function()
				store:SetAsync("nan", { v = 0 / 0 })
			end, "non%-finite")
			t.errors(function()
				store:SetAsync("mixed", { 1, 2, x = 3 })
			end, "mixed")
		end)
	end)
end
