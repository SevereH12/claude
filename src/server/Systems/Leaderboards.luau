--!strict
-- Leaderboards (the rules are Util/Leaderboards; the boards are
-- Config.LEADERBOARDS.boards): all-time Volts, bolts caught, Ascension
-- level and the longest login streak. Each board is an OrderedDataStore
-- (StormBottler_LB_<key>, keyed by UserId).
--   * Writing: each player's values every writeEverySeconds (only the ones
--     that changed) and when they leave, with pcall and a few retries.
--   * Reading: every readEverySeconds this server reads every board's top
--     50, looks up the names, and keeps them. Every player gets them (the
--     Leaderboards remote: the TOP tab in the REWARDS panel), with their own
--     values for the "You:" line.
--   * The board at world 1's spawn (tagged Leaderboards.BOARD_TAG, built by
--     World/Kit.leaderboard) shows the first board's top 10.
-- Studio without API access can't read or write them (the log says so
-- once).

local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserService = game:GetService("UserService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local LeaderboardRules = require(ReplicatedStorage.Shared.Util.Leaderboards)
local Types = require(ReplicatedStorage.Shared.Types)
local PlayerData = require(script.Parent.PlayerData)

local SETTINGS = Config.LEADERBOARDS
local TICK = 15 -- seconds between checks for values to write
local RETRIES = 3
local SHUTDOWN_WAIT = if RunService:IsStudio() then 5 else 25 -- seconds a closing server waits for the last writes

local Leaderboards = {}

type Written = { values: { [string]: number }, at: { [string]: number } }

local remote: RemoteEvent
local stores: { [string]: OrderedDataStore } = {}
local cache: { [string]: { Types.LeaderboardEntry } } = {}
-- per player: what was last written, and when (os.clock())
local written: { [Player]: Written } = {}
-- per player: their values when they left (the profile is gone by then)
local latest: { [Player]: { [string]: number } } = {}
local leavingWrites = 0 -- last writes of players leaving, still going
local names: { [number]: string } = {}
local warned: { [string]: boolean } = {}

local function warnOnce(key: string, message: string)
	if not warned[key] then
		warned[key] = true
		warn(`[Leaderboards] {message}`)
	end
end

local function storeFor(key: string): OrderedDataStore?
	local existing = stores[key]
	if existing then
		return existing
	end
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(SETTINGS.storePrefix .. key)
	end)
	if not ok then
		warnOnce(
			"open",
			`can't open the leaderboard stores ({result}). In Studio: Game Settings > Security > Enable Studio Access to API Services`
		)
		return nil
	end
	stores[key] = result
	return result
end

-- Runs fn with pcall, retrying with backoff. True if it worked.
local function withRetry(what: string, fn: () -> ()): boolean
	for attempt = 1, RETRIES do
		local ok, err = pcall(fn :: any)
		if ok then
			return true
		end
		if attempt == RETRIES then
			warnOnce(what, `{what} failed: {err}`)
		else
			task.wait(LeaderboardRules.backoff(attempt))
		end
	end
	return false
end

-- Writes this player's changed values (all of them now if `force`).
local function writePlayer(player: Player, force: boolean)
	local profile = PlayerData.get(player)
	local values = if profile then LeaderboardRules.values(profile) else latest[player]
	if not values then
		return
	end
	local record = written[player]
	if not record then
		record = { values = {}, at = {} }
		written[player] = record
	end
	local now = os.clock()
	local userId = player.UserId
	for _, board in SETTINGS.boards do
		local value = values[board.key]
		local last = record.values[board.key]
		if
			LeaderboardRules.shouldWrite(
				value,
				last,
				record.at[board.key] or -math.huge,
				now,
				SETTINGS.writeEverySeconds,
				force
			)
		then
			local store = storeFor(board.key)
			if not store or userId <= 0 then
				continue
			end
			local ok = withRetry(`writing {board.key}`, function()
				store:SetAsync(tostring(userId), value)
			end)
			if ok then
				record.values[board.key] = value
				record.at[board.key] = now
			end
		end
	end
end

-- Display names for these user ids (from players here, a cache, or one
-- batched lookup); unknown ones get "Player <id>".
local function lookUpNames(ids: { number })
	local missing: { number } = {}
	for _, id in ids do
		local here = Players:GetPlayerByUserId(id)
		if here then
			names[id] = here.DisplayName
		elseif not names[id] and id > 0 then
			table.insert(missing, id)
		end
	end
	if #missing == 0 then
		return
	end
	local ok, infos = pcall(function()
		return UserService:GetUserInfosByUserIdsAsync(missing)
	end)
	if ok and typeof(infos) == "table" then
		for _, info in infos do
			if typeof(info) == "table" and typeof(info.Id) == "number" then
				names[info.Id] = if typeof(info.DisplayName) == "string"
					then info.DisplayName
					else tostring(info.Username)
			end
		end
	elseif not ok then
		warnOnce("names", `name lookup failed: {infos}`)
	end
end

-- Reads one board's top rows, or nil if it couldn't.
local function readBoard(key: string): { Types.LeaderboardEntry }?
	local store = storeFor(key)
	if not store then
		return nil
	end
	local page: any = nil
	local ok = withRetry(`reading {key}`, function()
		local pages = store:GetSortedAsync(false, SETTINGS.top)
		page = pages:GetCurrentPage()
	end)
	if not ok or typeof(page) ~= "table" then
		return nil
	end
	local entries: { Types.LeaderboardEntry } = {}
	local ids: { number } = {}
	for _, item in page do
		local id = tonumber(item.key)
		if id and typeof(item.value) == "number" then
			table.insert(entries, { userId = id, name = "", value = item.value })
			table.insert(ids, id)
		end
	end
	lookUpNames(ids)
	for _, entry in entries do
		entry.name = names[entry.userId] or `Player {entry.userId}`
	end
	return entries
end

-- The board at the spawn: the first board's top rows.
local function updateBoards()
	local first = SETTINGS.boards[1]
	local entries = cache[first.key] or {}
	for _, board in CollectionService:GetTagged(LeaderboardRules.BOARD_TAG) do
		for _, gui in board:GetChildren() do
			if not gui:IsA("SurfaceGui") then
				continue
			end
			for index = 1, SETTINGS.boardRows do
				local row = gui:FindFirstChild(`Row{index}`)
				if row and row:IsA("TextLabel") then
					local entry = entries[index]
					row.Text = if entry
						then `{index}. {entry.name}  {LeaderboardRules.format(
							first.key,
							entry.value
						)}`
						else `{index}. ---`
				end
			end
		end
	end
end

-- Sends one player the boards and their own values.
local function sendTo(player: Player)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	local view: Types.LeaderboardView = {
		boards = cache,
		mine = LeaderboardRules.values(profile),
	}
	remote:FireClient(player, view)
end

local function sendAll()
	for _, player in Players:GetPlayers() do
		sendTo(player)
	end
	updateBoards()
end

local function refresh()
	for _, board in SETTINGS.boards do
		local entries = readBoard(board.key)
		if entries then
			cache[board.key] = entries
		end
	end
	sendAll()
end

function Leaderboards.init()
	remote = Net.get("Leaderboards")
	PlayerData.Loaded:Connect(function(player: Player)
		sendTo(player)
	end)
	PlayerData.Leaving:Connect(function(player: Player, profile: Types.Profile)
		latest[player] = LeaderboardRules.values(profile)
		leavingWrites += 1
		task.spawn(function()
			writePlayer(player, true)
			written[player] = nil
			latest[player] = nil
			leavingWrites -= 1
		end)
	end)
	-- a closing server waits (a little) for the last writes of everyone
	-- leaving (PlayerData fires Leaving for them when it closes)
	game:BindToClose(function()
		local deadline = os.clock() + SHUTDOWN_WAIT
		while leavingWrites > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
	CollectionService:GetInstanceAddedSignal(LeaderboardRules.BOARD_TAG):Connect(function()
		task.defer(updateBoards) -- the map was rebuilt: fill the new board
	end)
end

function Leaderboards.start()
	task.spawn(function()
		while true do
			refresh()
			task.wait(SETTINGS.readEverySeconds)
		end
	end)
	while true do
		task.wait(TICK)
		for _, player in Players:GetPlayers() do
			if PlayerData.get(player) then
				task.spawn(writePlayer, player, false)
			end
		end
	end
end

return Leaderboards
