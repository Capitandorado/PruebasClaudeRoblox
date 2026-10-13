-- Leaderboards: live in-server rankings plus global ones (OrderedDataStore) for best
-- production and discoveries. Global data is pushed at most every PushInterval per player
-- (and when they leave), fetched every FetchInterval, cached, and shown on the hub boards.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Artifacts = require(Shared.Config.Artifacts)
local Mutations = require(Shared.Config.Mutations)
local Format = require(Shared.Util.Format)
local Build = require(Shared.Util.Build)
local Assets = require(Shared.Config.Assets)

local Services = script.Parent
local Sessions = require(Services.Sessions)
local Data = require(Services.Data)
local World = require(Services.World)

local Leaderboards = {}

Leaderboards.PushInterval = 120
Leaderboards.FetchInterval = 180
Leaderboards.Size = 10

type BoardDef = {
	id: string,
	title: string,
	store: string,
	value: (profile: any) -> number,
	display: (value: number) -> string,
}

local function discoveries(profile: any): number
	local count = 0
	for artifactId, entry in profile.collection do
		if Artifacts.get(artifactId) then
			count += 1
			for mutationId in entry.muts do
				if Mutations.get(mutationId) then
					count += 1
				end
			end
		end
	end
	return count
end
Leaderboards.discoveries = discoveries

local BOARDS: { BoardDef } = {
	{
		id = "production",
		title = "⚡ Best production",
		store = "VoidFactory_TopProduction_v1",
		value = function(profile)
			return math.floor(math.min(profile.bestEps, 2 ^ 53))
		end,
		display = function(value)
			return Format.number(value) .. "/s"
		end,
	},
	{
		id = "discoveries",
		title = "📖 Discoveries",
		store = "VoidFactory_TopDiscoveries_v1",
		value = discoveries,
		display = function(value)
			return tostring(value) .. " found"
		end,
	},
}

local stores: { [string]: OrderedDataStore } = {}
local enabled = false
local globalCache: { any }? = nil
local lastPush: { [number]: number } = {}
local pushed: { [string]: number } = {}
local nameCache: { [number]: string } = {}
local boardGuis: { [string]: Frame } = {}

local function nameOf(userId: number): string
	local player = Players:GetPlayerByUserId(userId)
	if player then
		return player.DisplayName
	end
	local cached = nameCache[userId]
	if cached then
		return cached
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = if ok and type(name) == "string" then name else "Player " .. userId
	nameCache[userId] = result
	return result
end

local function push(session: any)
	if not enabled then
		return
	end
	lastPush[session.userId] = os.clock()
	local key = tostring(session.userId)
	for _, board in BOARDS do
		local value = board.value(session.profile)
		local cacheKey = board.id .. ":" .. key
		if value > 0 and pushed[cacheKey] ~= value then
			local ok, err = pcall(function()
				stores[board.id]:SetAsync(key, value)
			end)
			if ok then
				pushed[cacheKey] = value
			else
				warn("[Leaderboards] push failed: " .. tostring(err))
			end
		end
	end
end

local function fetch()
	if not enabled then
		return
	end
	local result = {}
	for _, board in BOARDS do
		local ok, pages = pcall(function()
			return stores[board.id]:GetSortedAsync(false, Leaderboards.Size)
		end)
		local entries = {}
		if ok and pages then
			local okPage, page = pcall(function()
				return pages:GetCurrentPage()
			end)
			if okPage then
				for rank, entry in page do
					local userId = tonumber(entry.key)
					if userId then
						table.insert(entries, {
							rank = rank,
							userId = userId,
							name = nameOf(userId),
							value = entry.value,
							display = board.display(entry.value),
						})
					end
				end
			end
		else
			warn("[Leaderboards] fetch failed: " .. tostring(pages))
		end
		table.insert(result, { id = board.id, title = board.title, entries = entries })
	end
	globalCache = result
end

-- Physical boards on the hub ------------------------------------------------------------

local function buildBoards()
	local root = World.folder()
	local hub = root and root:FindFirstChild("Hub")
	if not hub then
		return
	end
	for index, board in BOARDS do
		local side = if index == 1 then -1 else 1
		local part = Build.part({
			Name = "Board_" .. board.id,
			Size = Vector3.new(14, 10, 0.6),
			CFrame = CFrame.new(side * 17, 6, -18) * CFrame.Angles(0, math.rad(side * -20), 0),
			Color = Color3.fromRGB(20, 18, 36),
			Material = Enum.Material.Metal,
			CanCollide = true,
			Parent = hub,
		})
		local surface = Instance.new("SurfaceGui")
		surface.Face = Enum.NormalId.Back
		surface.CanvasSize = Vector2.new(560, 400)
		surface.LightInfluence = 0
		surface.Parent = part
		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundColor3 = Color3.fromRGB(18, 14, 36)
		frame.Parent = surface
		local title =
			Build.label(frame, board.title .. " — global", Color3.fromRGB(255, 220, 120), UDim2.new(1, 0, 0, 50))
		title.Name = "Title"
		title.FontFace = Font.new(Assets.Fonts.Display, Enum.FontWeight.Regular)
		for rank = 1, Leaderboards.Size do
			local row = Build.label(
				frame,
				"",
				Color3.new(1, 1, 1),
				UDim2.new(1, -20, 0, 32),
				UDim2.new(0, 10, 0, 56 + (rank - 1) * 34)
			)
			row.Name = "Row" .. rank
			row.TextXAlignment = Enum.TextXAlignment.Left
		end
		boardGuis[board.id] = frame
	end
end

local function updateBoards()
	local boards: { any } = globalCache or {}
	for _, board in boards do
		local frame = boardGuis[board.id]
		if frame then
			for rank = 1, Leaderboards.Size do
				local row = frame:FindFirstChild("Row" .. rank) :: TextLabel?
				local entry = board.entries[rank]
				if row then
					row.Text = if entry then string.format("%d. %s  —  %s", rank, entry.name, entry.display) else ""
				end
			end
		end
	end
	if not enabled then
		for _, frame in boardGuis do
			local row = frame:FindFirstChild("Row1") :: TextLabel?
			if row then
				row.Text = "Global leaderboards need a published game with API services."
			end
		end
	end
end

function Leaderboards.markDirty(session: any)
	lastPush[session.userId] = 0
end

function Leaderboards.snapshot()
	local server = {}
	for _, session in Sessions.all() do
		table.insert(server, {
			userId = session.userId,
			name = session.player.DisplayName,
			eps = Sessions.production(session).total,
			discoveries = discoveries(session.profile),
			rebirths = session.profile.rebirths,
		})
	end
	table.sort(server, function(a, b)
		return a.eps > b.eps
	end)
	local total = #Artifacts.List * (1 + #Mutations.List)
	return { server = server, global = globalCache, totalArtifacts = #Artifacts.List, totalDiscoveries = total }
end

function Leaderboards.init()
	if Data.mode == "memory" then
		enabled = false
		return
	end
	enabled = true
	for _, board in BOARDS do
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore(board.store .. Data.storeSuffix())
		end)
		if ok then
			stores[board.id] = store
		else
			enabled = false
		end
	end
end

function Leaderboards.start()
	buildBoards()
	updateBoards()
	Sessions.Ending:Connect(function(session)
		task.spawn(push, session)
		lastPush[session.userId] = nil
	end)
	task.spawn(function()
		local sinceFetch = Leaderboards.FetchInterval - 15
		while true do
			task.wait(5)
			sinceFetch += 5
			for _, session in Sessions.all() do
				local last = lastPush[session.userId]
				if last == nil then
					lastPush[session.userId] = os.clock() - Leaderboards.PushInterval + 30
				elseif os.clock() - last >= Leaderboards.PushInterval then
					task.spawn(push, session)
				end
			end
			if sinceFetch >= Leaderboards.FetchInterval then
				sinceFetch = 0
				fetch()
				updateBoards()
			end
		end
	end)
end

return Leaderboards
