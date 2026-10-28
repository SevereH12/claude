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
local HintRules = require(ReplicatedStorage.Shared.Util.Hints)
local QuestRules = require(ReplicatedStorage.Shared.Util.Quests)
local ResearchMath = require(ReplicatedStorage.Shared.Util.Research)
local SettingsRules = require(ReplicatedStorage.Shared.Util.Settings)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local StatRules = require(ReplicatedStorage.Shared.Util.Stats)
local TutorialRules = require(ReplicatedStorage.Shared.Util.Tutorial)
local Types = require(ReplicatedStorage.Shared.Types)

local STORE_NAME = "StormBottler_PlayerData"
local CURRENT_VERSION = 19
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
	isNew: boolean, -- there was no saved profile before this visit (Systems/Invites)
	wipe: boolean?, -- an admin reset it: every save from now writes a new profile
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
	onboardStep = 0,
	boltColour = 0,
	purchases = {},
	trialUsed = false,
	boosts = {},
	dailyStreak = 0,
	lastDailyDay = 0,
	giftedPasses = {},
	receivedGiftIds = {},
	giftCredits = {},
	glints = {},
	settings = SettingsRules.defaults(),
	stats = StatRules.new(),
	quests = QuestRules.new(),
	logClaimed = {},
	ascension = 0,
	tutorialStep = TutorialRules.WALK, -- a new player starts the tutorial
	loginRun = 0,
	bestLoginRun = 0,
	notifyAsked = false,
	notifyYes = false,
	playtime = { day = 0, seconds = 0, claimed = {} },
	invitedBy = 0,
	hintsSeen = {}, -- a new player gets every gameplay tip (after the tutorial)
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
	-- the onboarding funnel (Systems/Analytics) starts from step 0
	[4] = function(data: any): any
		data.onboardStep = 0
		return data
	end,
	-- Bolt Colours (prompt 8): no colour picked yet
	[5] = function(data: any): any
		data.boltColour = 0
		return data
	end,
	-- Volts packs and the free 2x Volts trial (prompt 8 part C)
	[6] = function(data: any): any
		data.purchases = {}
		data.trialUsed = false
		return data
	end,
	-- timed boosts and the login streak (prompt 9)
	[7] = function(data: any): any
		data.boosts = {}
		data.dailyStreak = 0
		data.lastDailyDay = 0
		return data
	end,
	-- gifting (prompt 10)
	[8] = function(data: any): any
		data.giftedPasses = {}
		data.receivedGiftIds = {}
		data.giftCredits = {}
		return data
	end,
	-- researcher ranks and Glints (prompt 13): each researcher's rank is
	-- the tier of the zone they're posted to now (0 at the Office), so
	-- nobody is pushed out of their zone; their data stays, and their
	-- level is kept or raised to what that data gives at that rank
	[9] = function(data: any): any
		data.glints = {}
		if typeof(data.researchers) == "table" then
			for _, save in data.researchers do
				if typeof(save) == "table" then
					local zone = if typeof(save.post) == "string"
						then Config.ZONES[save.post]
						else nil
					save.rank = if zone then ResearchMath.zoneTier(zone) else 0
					local fieldData = if typeof(save.data) == "number" then save.data else 0
					local level = if typeof(save.level) == "number" then save.level else 1
					save.level = math.max(level, ResearchMath.levelFor(fieldData, save.rank))
				end
			end
		end
		return data
	end,
	-- sound settings (prompt 11)
	[10] = function(data: any): any
		data.settings = { musicVolume = 1, sfxVolume = 1, ambienceVolume = 1, muted = false }
		return data
	end,
	-- the full SETTINGS panel (prompt 14): the sound volumes carry over,
	-- everything else starts at its default
	[11] = function(data: any): any
		data.settings = SettingsRules.sanitize(data.settings)
		return data
	end,
	-- stat counters and quests (prompt 16): counting starts now, except
	-- lifetime Volts earned, which is what they've earned so far; quests
	-- are picked when the profile loads
	[12] = function(data: any): any
		data.stats = StatRules.new()
		if typeof(data.totalVolts) == "number" and data.totalVolts > 0 then
			data.stats.lifetime[StatRules.VOLTS_EARNED] = data.totalVolts
		end
		data.quests = QuestRules.new()
		return data
	end,
	-- the Storm Log (prompt 16 part B): it's worked out from the stat
	-- counters, so only claimed row rewards are new (none yet)
	[13] = function(data: any): any
		data.logClaimed = {}
		return data
	end,
	-- Ascension (prompt 16 part C): nobody has ascended yet
	[14] = function(data: any): any
		data.ascension = 0
		return data
	end,
	-- the new-player tutorial (prompt 17): anyone who has owned a Vial or
	-- better (or ascended) never sees it; a saved player still on the Jar
	-- starts it from step 1
	[15] = function(data: any): any
		local tier = if typeof(data.bottleTier) == "number" then data.bottleTier else 1
		local level = if typeof(data.ascension) == "number" then data.ascension else 0
		data.tutorialStep = if TutorialRules.isOldPlayer({ bottleTier = tier, ascension = level })
			then TutorialRules.DONE
			else TutorialRules.WALK
		return data
	end,
	-- leaderboards and notifications (prompt 17 part B): the login run
	-- starts from the streak day they're on (the best guess we have), and
	-- nobody has been asked about notifications yet
	[16] = function(data: any): any
		local streak = if typeof(data.dailyStreak) == "number" then data.dailyStreak else 0
		data.loginRun = streak
		data.bestLoginRun = streak
		data.notifyAsked = false
		return data
	end,
	-- after the October 2026 review: playtime gifts count per UTC day
	-- (none played yet), reminders need a YES (we don't know what those
	-- already asked answered, so they keep getting them: Roblox drops them
	-- for anyone who said no), and nobody has an inviter waiting to be paid
	[17] = function(data: any): any
		data.playtime = { day = 0, seconds = 0, claimed = {} }
		data.notifyYes = data.notifyAsked == true
		data.invitedBy = 0
		return data
	end,
	-- gameplay tips (after the tutorial): the tips for things a player has
	-- clearly done already (hired a researcher, bought boots, claimed a
	-- daily reward, ...) count as seen; they get the rest
	[18] = function(data: any): any
		data.hintsSeen = HintRules.alreadyUsed(data)
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

-- Fires when a player leaves, just before their profile's last save
-- (PlayerData.get no longer finds it after this).
PlayerData.Leaving = Signal.new() :: Signal.Signal<Player, Types.Profile>

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

local function keyForId(userId: number): string
	return `player_{userId}`
end

local function keyFor(player: Player): string
	return keyForId(player.UserId)
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
): (ClaimResult, Types.Profile?, boolean)
	local outcome: ClaimResult = "error"
	local profile: Types.Profile? = nil
	local isNew = false

	local ok = withRetry(3, function()
		dataStore:UpdateAsync(keyFor(player), function(old: any): any
			-- this function can run more than once; reset results every time
			outcome, profile, isNew = "error", nil, false
			if old ~= nil and typeof(old) ~= "table" then
				return nil -- unknown format: refuse rather than overwrite
			end
			if old and heldByOther(old.lock, sessionId) then
				outcome = "locked"
				return nil
			end
			isNew = not (old and typeof(old.data) == "table")
			local data = if old and typeof(old.data) == "table"
				then migrate(old.data)
				else deepCopy(DEFAULT_PROFILE)
			outcome, profile = "ok", data
			local record: Record = { data = data, lock = newLock(sessionId) }
			return record
		end)
	end)

	if not ok then
		return "error", nil, false
	end
	return outcome, profile, isNew
end

-- Writes the profile. release = true also clears the lock (player left).
-- True if it was written.
local function save(session: Session, release: boolean): boolean
	local dataStore = store
	if not session.canSave or not dataStore then
		return false
	end
	local data = deepCopy(if session.wipe then DEFAULT_PROFILE else session.profile)
	local player = session.player
	local wrote = false

	local ok = withRetry(if release then 5 else 2, function()
		dataStore:UpdateAsync(keyFor(player), function(old: any): any
			-- this function can run more than once; reset the result every time
			wrote = false
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
			wrote = true
			return record
		end)
	end)
	return ok and wrote
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
		isNew = true,
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
	local isNew = false
	for attempt = 1, LOCKED_RETRIES do
		local result, loaded, fresh = claim(dataStore, player, sessionId)
		if result == "ok" then
			profile = loaded
			isNew = fresh
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

	local session: Session =
		{ id = sessionId, player = player, profile = profile, canSave = true, isNew = isNew }

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
	PlayerData.Leaving:Fire(player, session.profile)
	release(session)
end

-- The server is closing. BindToClose can run before PlayerRemoving, so
-- this does the "player is leaving" step itself (the last leaderboard
-- write, the reminders, the last AFK pay) before the final save.
local function onShutdown()
	for player, session in sessions do
		sessions[player] = nil
		task.spawn(function()
			PlayerData.Leaving:Fire(player, session.profile)
			release(session)
		end)
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

-- True if the player had no saved profile before this visit (a brand-new
-- player; a temporary Studio profile counts as new).
function PlayerData.isNew(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and session.isNew
end

-- Someone's saved profile, read only: for a player who may not be in this
-- server (Systems/Gifts checks what they own). Returns false if it couldn't
-- be read, and true with nil if they have no save yet.
function PlayerData.peek(userId: number): (boolean, Types.Profile?)
	local dataStore = store
	if not dataStore then
		return false, nil
	end
	local ok, record = pcall(function()
		return dataStore:GetAsync(keyForId(userId))
	end)
	if not ok then
		return false, nil
	end
	if typeof(record) ~= "table" or typeof(record.data) ~= "table" then
		return true, nil
	end
	local migrated, profile = pcall(migrate, record.data)
	return migrated, if migrated then profile else nil
end

-- Saves the player's profile now (Systems/Receipts saves a purchase before
-- confirming it). True if it was written; false if it failed, or for a
-- temporary Studio profile, which never saves.
function PlayerData.saveNow(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and save(session, false)
end

-- Admin reset (Systems/Admin) of a player in this server: their profile is
-- saved as a brand-new one now and when they leave (the admin system then
-- kicks them, so nothing in this session uses the old profile again).
-- True if it was written (a temporary Studio profile never saves).
function PlayerData.reset(player: Player): boolean
	local session = sessions[player]
	if not session then
		return false
	end
	session.wipe = true
	return save(session, false)
end

-- Admin reset of a player who isn't in this server. Refuses (false, why)
-- while another server holds their save, so it can't fight a live session.
function PlayerData.resetSaved(userId: number): (boolean, string)
	local dataStore = store
	if not dataStore then
		return false, "DataStores aren't available here"
	end
	local outcome = "error"
	local ok = withRetry(2, function()
		dataStore:UpdateAsync(keyForId(userId), function(old: any): any
			outcome = "error"
			if old ~= nil and typeof(old) ~= "table" then
				return nil
			end
			if old and heldByOther(old.lock, "") then
				outcome = "locked"
				return nil
			end
			outcome = "ok"
			local record: Record = { data = deepCopy(DEFAULT_PROFILE), lock = nil }
			return record
		end)
	end)
	if not ok then
		return false, "couldn't write the save"
	elseif outcome == "locked" then
		return false, "they're playing in another server right now"
	elseif outcome ~= "ok" then
		return false, "their save is in an unknown format"
	end
	return true, "reset"
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
