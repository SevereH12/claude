--!strict
-- Owns every player's saved data. Gameplay code never touches DataStores:
-- it calls PlayerData.get(player) and edits the in-memory profile, and this
-- module saves it (autosave, on leave, and on server shutdown).
--
-- Session locking: each play session writes its own id into the record when
-- it loads, and only that session may save until it releases the lock. This
-- stops the "rejoin fast on another server" item/coin duplication trick.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Types = require(ReplicatedStorage.Shared.Types)

local STORE_NAME = "StormBottler_PlayerData"
local CURRENT_VERSION = 4
-- A lock older than this belongs to a server that crashed; it may be taken.
local LOCK_STALE_SECONDS = Config.AUTOSAVE_INTERVAL * 3
local LOCKED_RETRIES = 5
local LOCKED_RETRY_WAIT = 4
local SHUTDOWN_TIMEOUT = if RunService:IsStudio() then 5 else 25

local SERVER_ID = if game.JobId ~= ""
	then game.JobId
	else `studio-{HttpService:GenerateGUID(false)}`

type Lock = { session: string, server: string, time: number }
type Record = { data: Types.Profile, lock: Lock? }

type Session = {
	id: string,
	player: Player,
	profile: Types.Profile,
	canSave: boolean, -- false for a temporary Studio profile
}

local DEFAULT_PROFILE: Types.Profile = {
	version = CURRENT_VERSION,
	volts = 0,
	totalVolts = 0,
	bottleTier = 1,
	bootTier = 1,
	chargeCount = 0,
	chargeValue = 0,
	researchers = {},
	tankCount = 0,
	tankValue = 0,
}

-- MIGRATIONS[n] turns a version-n profile into version n+1. When the profile
-- shape changes: bump CURRENT_VERSION, add a step here, update DEFAULT_PROFILE.
local MIGRATIONS: { [number]: (any) -> any } = {
	[1] = function(data: any): any
		data.researchers = {}
		data.tankCount = 0
		data.tankValue = 0
		return data
	end,
	[2] = function(data: any): any
		data.bootTier = 1
		return data
	end,
	-- the Vial was inserted as bottle tier 2: everything from the old
	-- tier 2 (Flask) up moves one place
	[3] = function(data: any): any
		if typeof(data.bottleTier) == "number" and data.bottleTier >= 2 then
			data.bottleTier += 1
		end
		return data
	end,
}

local storeOk, storeResult = pcall(function()
	return DataStoreService:GetDataStore(STORE_NAME)
end)
local store: DataStore? = if storeOk then storeResult else nil

local sessions: { [Player]: Session } = {}
local pendingReleases = 0

local PlayerData = {}

-- Fires once a player's profile is ready to use.
PlayerData.Loaded = Signal.new() :: Signal.Signal<Player, Types.Profile>

local function deepCopy<T>(value: T): T
	if typeof(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value :: any do
		copy[k] = deepCopy(v)
	end
	return copy :: any
end

local function keyFor(player: Player): string
	return `player_{player.UserId}`
end

local function migrate(data: any): Types.Profile
	if typeof(data.version) ~= "number" then
		data.version = 1
	end
	while data.version < CURRENT_VERSION do
		local step = MIGRATIONS[data.version]
		if not step then
			error(`missing migration from v{data.version}`)
		end
		data = step(data)
		data.version += 1
	end
	-- fill in any field added since this profile was saved
	for key, value in DEFAULT_PROFILE :: any do
		if data[key] == nil then
			data[key] = deepCopy(value)
		end
	end
	return data
end

-- Exposed for tools/harness tests of the migration steps.
PlayerData.migrate = migrate

-- Runs fn with pcall, retrying with exponential backoff.
local function withRetry(attempts: number, fn: () -> ()): boolean
	local delaySeconds = 1
	for attempt = 1, attempts do
		local ok, err = pcall(fn :: any)
		if ok then
			return true
		end
		warn(`[PlayerData] attempt {attempt}/{attempts} failed: {err}`)
		if attempt < attempts then
			task.wait(delaySeconds)
			delaySeconds = math.min(delaySeconds * 2, 16)
		end
	end
	return false
end

local function newLock(sessionId: string): Lock
	return { session = sessionId, server = SERVER_ID, time = os.time() }
end

-- True if a different session (on any server, including this one) holds a
-- fresh lock. A player who rejoins this same server waits for their previous
-- session's final save too.
local function heldByOther(lock: any, sessionId: string): boolean
	return typeof(lock) == "table"
		and lock.session ~= sessionId
		and typeof(lock.time) == "number"
		and os.time() - lock.time < LOCK_STALE_SECONDS
end

type ClaimResult = "ok" | "locked" | "error"

-- Loads the profile and writes this server's lock in one atomic UpdateAsync.
local function claim(
	dataStore: DataStore,
	player: Player,
	sessionId: string
): (ClaimResult, Types.Profile?)
	local outcome: ClaimResult = "error"
	local profile: Types.Profile? = nil

	local ok = withRetry(3, function()
		dataStore:UpdateAsync(keyFor(player), function(old: any): any
			-- this function can run more than once; reset results every time
			outcome, profile = "error", nil
			if old ~= nil and typeof(old) ~= "table" then
				return nil -- unknown format: refuse rather than overwrite
			end
			if old and heldByOther(old.lock, sessionId) then
				outcome = "locked"
				return nil
			end
			local data = if old and typeof(old.data) == "table"
				then migrate(old.data)
				else deepCopy(DEFAULT_PROFILE)
			outcome, profile = "ok", data
			local record: Record = { data = data, lock = newLock(sessionId) }
			return record
		end)
	end)

	if not ok then
		return "error", nil
	end
	return outcome, profile
end

-- Writes the profile. release = true also clears the lock (player left).
local function save(session: Session, release: boolean)
	local dataStore = store
	if not session.canSave or not dataStore then
		return
	end
	local data = deepCopy(session.profile)
	local player = session.player

	withRetry(if release then 5 else 2, function()
		dataStore:UpdateAsync(keyFor(player), function(old: any): any
			-- only the session holding the lock may write
			if
				typeof(old) ~= "table"
				or typeof(old.lock) ~= "table"
				or old.lock.session ~= session.id
			then
				warn(`[PlayerData] skipped save for {player.Name}: lock not held by this session`)
				return nil
			end
			local record: Record = {
				data = data,
				lock = if release then nil else newLock(session.id),
			}
			return record
		end)
	end)
end

local function release(session: Session)
	pendingReleases += 1
	save(session, true)
	pendingReleases -= 1
end

local function startAutosave(session: Session)
	local player = session.player
	-- stagger players so they don't all save on the same tick
	task.wait(player.UserId % Config.AUTOSAVE_INTERVAL)
	while sessions[player] == session do
		save(session, false)
		task.wait(Config.AUTOSAVE_INTERVAL)
	end
end

local function useTemporaryProfile(player: Player)
	warn(
		"[PlayerData] DataStores unavailable in Studio: using a temporary profile, progress will NOT save. "
			.. "To test saving: Game Settings > Security > Enable Studio Access to API Services."
	)
	local session: Session = {
		id = HttpService:GenerateGUID(false),
		player = player,
		profile = deepCopy(DEFAULT_PROFILE),
		canSave = false,
	}
	sessions[player] = session
	PlayerData.Loaded:Fire(player, session.profile)
end

local function onPlayerAdded(player: Player)
	local dataStore = store
	if not dataStore then
		if RunService:IsStudio() then
			useTemporaryProfile(player)
		else
			player:Kick("Couldn't load your data. Please rejoin.")
		end
		return
	end

	local sessionId = HttpService:GenerateGUID(false)
	local profile: Types.Profile? = nil
	for attempt = 1, LOCKED_RETRIES do
		local result, loaded = claim(dataStore, player, sessionId)
		if result == "ok" then
			profile = loaded
			break
		elseif result == "error" then
			if RunService:IsStudio() then
				useTemporaryProfile(player)
			else
				-- never play on a default profile: its first save would wipe real data
				player:Kick("Couldn't load your data. Please rejoin.")
			end
			return
		end
		-- "locked": another session is still saving this player
		if player.Parent == nil then
			return
		end
		if attempt < LOCKED_RETRIES then
			task.wait(LOCKED_RETRY_WAIT)
		end
	end

	if not profile then
		player:Kick("Your data is still saving from another server. Please rejoin in a moment.")
		return
	end

	local session: Session = { id = sessionId, player = player, profile = profile, canSave = true }

	-- left while we were loading: hand the lock straight back
	if player.Parent == nil then
		release(session)
		return
	end

	sessions[player] = session
	PlayerData.Loaded:Fire(player, profile)
	task.spawn(startAutosave, session)
end

local function onPlayerRemoving(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	sessions[player] = nil
	release(session)
end

local function onShutdown()
	for player, session in sessions do
		sessions[player] = nil
		task.spawn(release, session)
	end
	local deadline = os.clock() + SHUTDOWN_TIMEOUT
	while pendingReleases > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end

-- The player's live profile, or nil if it isn't loaded (yet).
function PlayerData.get(player: Player): Types.Profile?
	local session = sessions[player]
	return if session then session.profile else nil
end

function PlayerData.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	game:BindToClose(onShutdown)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return PlayerData
