--!strict
-- The admin panel's server side (the panel is Controllers/AdminUI).
-- Admins are the owner of the game's group (Config.GROUP_ID), anyone in it
-- at Config.ADMIN_RANK or higher, the user who owns the place (if a user
-- owns it), and everyone in a Studio play test (Util/Ops.isAdmin). The
-- player attribute "Admin" shows the ADMIN button, but the client is never
-- trusted: every call on the Admin remote is rate-limited and checked here.
--
-- What the panel can do (all through the Admin remote):
--   "open"     -> this server's recent errors and who's in the server
--   "kick"     a player in this server, with a reason
--   "ban"      anyone by username or id, for a set time (Players:BanAsync)
--   "unban"    anyone (Players:UnbanAsync)
--   "volts"    give Volts to a player in this server
--   "boost"    give a boost (Config.BOOSTS) to a player in this server
--   "reset"    start someone's save again from nothing (the panel confirms)
--   "lookup"   anyone's saved data, read only
--   "testNotify" send yourself a "daily reward ready" notification now
--              (live servers only; Systems/Notifications.sendTest)
--   "testError" a test error on the server (the panel makes one on the
--              client too), to check error reporting
-- Every action is written to the AdminLog DataStore (Config.ADMIN.logStore),
-- one key per UTC day ("day_2026-10-25") holding a list of
-- { time, by, byName, action, target, targetName, detail }.

local DataStoreService = game:GetService("DataStoreService")
local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local BoostRules = require(ReplicatedStorage.Shared.Util.Boosts)
local Ops = require(ReplicatedStorage.Shared.Util.Ops)
local Boosts = require(script.Parent.Boosts)
local Errors = require(script.Parent.Errors)
local Notifications = require(script.Parent.Notifications)
local PlayerData = require(script.Parent.PlayerData)
local Sync = require(script.Parent.Sync)
local RateLimit = require(ServerScriptService.Server.Lib.RateLimit)

local SETTINGS = Config.ADMIN
local ATTRIBUTE = "Admin"
local LOOKUP_LINES = 80

local Admin = {}

type Check = { admin: boolean, at: number }
local checks: { [Player]: Check } = {}
local groupOwnerId: number? = nil
local groupOwnerAt = -math.huge

local remote: RemoteEvent

local logStore: DataStore? = nil
local logWarned = false

-- The owner of the group (looked up at most every rankRecheckSeconds).
local function ownerOfGroup(): number?
	if os.clock() - groupOwnerAt < SETTINGS.rankRecheckSeconds then
		return groupOwnerId
	end
	local ok, info = pcall(function()
		return GroupService:GetGroupInfoAsync(Config.GROUP_ID)
	end)
	if ok and typeof(info) == "table" and typeof(info.Owner) == "table" then
		local id = info.Owner.Id
		if typeof(id) == "number" then
			groupOwnerId = id
		end
	end
	groupOwnerAt = os.clock()
	return groupOwnerId
end

local function rankOf(player: Player): number
	local ok, rank = pcall(function()
		return (player :: any):GetRankInGroupAsync(Config.GROUP_ID)
	end)
	if ok and typeof(rank) == "number" then
		return rank
	end
	-- older engines only have the non-Async name
	local oldOk, oldRank = pcall(function()
		return (player :: any):GetRankInGroup(Config.GROUP_ID)
	end)
	return if oldOk and typeof(oldRank) == "number" then oldRank else 0
end

local function computeAdmin(player: Player): boolean
	local studio = RunService:IsStudio()
	return Ops.isAdmin({
		studio = studio,
		userId = player.UserId,
		placeOwnerId = if game.CreatorType == Enum.CreatorType.User then game.CreatorId else nil,
		groupOwnerId = if studio then nil else ownerOfGroup(),
		rank = if studio then 0 else rankOf(player),
	})
end

-- Is this player an admin? Checked on the server for every call; a rank
-- check is reused for Config.ADMIN.rankRecheckSeconds.
function Admin.isAdmin(player: Player): boolean
	local check = checks[player]
	if not check or os.clock() - check.at > SETTINGS.rankRecheckSeconds then
		local admin = computeAdmin(player)
		if player.Parent == nil then
			return false
		end
		check = { admin = admin, at = os.clock() }
		checks[player] = check
		player:SetAttribute(ATTRIBUTE, if admin then true else nil)
	end
	return (check :: Check).admin
end

-- Logging ------------------------------------------------------------------

local function writeLog(entry: { [string]: any })
	local store = logStore
	if not store then
		local ok, result = pcall(function()
			return DataStoreService:GetDataStore(SETTINGS.logStore)
		end)
		if not ok then
			if not logWarned then
				logWarned = true
				warn(`[Admin] can't open the AdminLog store: {result}`)
			end
			return
		end
		store = result
		logStore = result
	end
	local key = `day_{os.date("!%Y-%m-%d", entry.time)}`
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(key, function(old: any): any
			local list = if typeof(old) == "table" then old else {}
			table.insert(list, entry)
			while #list > SETTINGS.logPerDay do
				table.remove(list, 1)
			end
			return list
		end)
	end)
	if not ok and not logWarned then
		logWarned = true
		warn(
			`[Admin] couldn't write the AdminLog ({err}). In Studio: Game Settings > Security > Enable Studio Access to API Services`
		)
	end
end

-- Who did what to whom, and when. Printed to the server log too.
local function logAction(
	by: Player,
	action: string,
	targetId: number?,
	targetName: string?,
	detail: string
)
	local entry = {
		time = os.time(),
		by = by.UserId,
		byName = by.Name,
		action = action,
		target = targetId or 0,
		targetName = targetName or "",
		detail = detail,
	}
	print(`[Admin] {by.Name}: {action} {targetName or ""} {detail}`)
	task.spawn(writeLog, entry)
end

-- Replies ------------------------------------------------------------------

local function reply(player: Player, ok: boolean, text: string)
	remote:FireClient(player, "result", { ok = ok, text = text })
end

local function sendState(player: Player)
	local names = {}
	for _, other in Players:GetPlayers() do
		table.insert(names, other.Name)
	end
	table.sort(names)
	remote:FireClient(player, "state", { errors = Errors.recent(), players = names })
end

-- Targets ------------------------------------------------------------------

type Target = { userId: number, name: string, player: Player? }

-- A username or user id typed in the panel -> who that is.
local function resolve(text: unknown): (Target?, string?)
	local name, id = Ops.parseTarget(text)
	if not name then
		return nil, "type a username (or a user id)"
	end
	if id then
		local online = Players:GetPlayerByUserId(id)
		if online then
			return { userId = id, name = online.Name, player = online }, nil
		end
		local ok, found = pcall(function()
			return Players:GetNameFromUserIdAsync(id)
		end)
		if not ok or typeof(found) ~= "string" then
			return nil, `no Roblox user has the id {id}`
		end
		return { userId = id, name = found }, nil
	end
	local lower = string.lower(name)
	for _, other in Players:GetPlayers() do
		if string.lower(other.Name) == lower then
			return { userId = other.UserId, name = other.Name, player = other }, nil
		end
	end
	local ok, found = pcall(function()
		return Players:GetUserIdFromNameAsync(name)
	end)
	if not ok or typeof(found) ~= "number" then
		return nil, `no Roblox user is called {name}`
	end
	return { userId = found, name = name, player = Players:GetPlayerByUserId(found) }, nil
end

-- The group's owner and the place's owner can't be kicked, banned or reset.
local function protected(admin: Player, target: Target): string?
	if target.userId == admin.UserId then
		return "you can't do that to yourself"
	end
	if target.userId == ownerOfGroup() then
		return "that's the group's owner"
	end
	if game.CreatorType == Enum.CreatorType.User and target.userId == game.CreatorId then
		return "that's the game's owner"
	end
	return nil
end

-- Actions ------------------------------------------------------------------

type Args = { [string]: unknown }

local function kick(admin: Player, args: Args)
	local target, why = resolve(args.target)
	if not target then
		return reply(admin, false, why or "?")
	end
	local blocked = protected(admin, target)
	if blocked then
		return reply(admin, false, blocked)
	end
	local victim = target.player
	if not victim then
		return reply(admin, false, `{target.name} isn't in this server`)
	end
	local reason = Ops.cleanReason(args.reason) or ""
	logAction(admin, "kick", target.userId, target.name, reason)
	victim:Kick(if reason ~= "" then `Kicked by an admin: {reason}` else "Kicked by an admin")
	reply(admin, true, `Kicked {target.name}`)
end

local function ban(admin: Player, args: Args)
	local seconds = args.seconds
	if not Ops.isBanLength(seconds) then
		return reply(admin, false, "pick a ban length")
	end
	local target, why = resolve(args.target)
	if not target then
		return reply(admin, false, why or "?")
	end
	local blocked = protected(admin, target)
	if blocked then
		return reply(admin, false, blocked)
	end
	local length = seconds :: number
	local reason = Ops.cleanReason(args.reason) or ""
	local ok, err = pcall(function()
		Players:BanAsync({
			UserIds = { target.userId },
			ApplyToUniverse = true,
			Duration = length,
			DisplayReason = if reason ~= "" then reason else "Banned by an admin",
			PrivateReason = `by {admin.Name} ({admin.UserId}): {reason}`,
			ExcludeAltAccounts = false,
		})
	end)
	if not ok then
		return reply(admin, false, `Ban failed: {err}`)
	end
	logAction(admin, "ban", target.userId, target.name, `{Ops.banLabel(length)}: {reason}`)
	reply(admin, true, `Banned {target.name} ({Ops.banLabel(length)})`)
end

local function unban(admin: Player, args: Args)
	local target, why = resolve(args.target)
	if not target then
		return reply(admin, false, why or "?")
	end
	local ok, err = pcall(function()
		Players:UnbanAsync({ UserIds = { target.userId }, ApplyToUniverse = true })
	end)
	if not ok then
		return reply(admin, false, `Unban failed: {err}`)
	end
	logAction(admin, "unban", target.userId, target.name, "")
	reply(admin, true, `Unbanned {target.name}`)
end

-- A player in this server with a loaded profile, or why not.
local function liveTarget(args: Args): (Target?, string?)
	local target, why = resolve(args.target)
	if not target then
		return nil, why
	end
	if not target.player or not PlayerData.get(target.player) then
		return nil, `{target.name} isn't in this server`
	end
	return target, nil
end

local function giveVolts(admin: Player, args: Args)
	local amount = args.amount
	if
		typeof(amount) ~= "number"
		or amount ~= amount
		or amount < 1
		or amount > SETTINGS.maxVolts
	then
		return reply(admin, false, "type an amount from 1 to 1T")
	end
	local target, why = liveTarget(args)
	if not target then
		return reply(admin, false, why or "?")
	end
	local player = target.player :: Player
	local profile = PlayerData.get(player)
	if not profile then
		return reply(admin, false, `{target.name} isn't loaded yet`)
	end
	local volts = math.floor(amount)
	profile.volts += volts
	Sync.markDirty(player)
	logAction(admin, "volts", target.userId, target.name, `+{volts}`)
	reply(admin, true, `Gave {target.name} {volts} Volts`)
end

local function giveBoost(admin: Player, args: Args)
	local key, minutes = args.key, args.minutes
	if typeof(key) ~= "string" or not BoostRules.def(key) then
		return reply(admin, false, "pick a boost")
	end
	if typeof(minutes) ~= "number" or not table.find(SETTINGS.boostMinutes, minutes) then
		return reply(admin, false, "pick a boost length")
	end
	local target, why = liveTarget(args)
	if not target then
		return reply(admin, false, why or "?")
	end
	Boosts.grant(target.player :: Player, key, minutes * 60, true)
	logAction(admin, "boost", target.userId, target.name, `{key} {minutes} min`)
	reply(admin, true, `Gave {target.name} {key} for {minutes} min`)
end

local function reset(admin: Player, args: Args)
	if args.confirm ~= "RESET" then
		return reply(admin, false, "confirm the reset first")
	end
	local target, why = resolve(args.target)
	if not target then
		return reply(admin, false, why or "?")
	end
	local blocked = protected(admin, target)
	if blocked then
		return reply(admin, false, blocked)
	end
	local victim = target.player
	if victim and PlayerData.get(victim) then
		local saved = PlayerData.reset(victim)
		logAction(
			admin,
			"reset",
			target.userId,
			target.name,
			if saved then "live" else "live (not saved)"
		)
		victim:Kick("An admin reset your progress. Rejoin to start again.")
		return reply(
			admin,
			saved,
			if saved
				then `Reset {target.name} and sent them out`
				else `{target.name}'s reset couldn't be saved (Studio?)`
		)
	end
	local ok, note = PlayerData.resetSaved(target.userId)
	if ok then
		logAction(admin, "reset", target.userId, target.name, "saved")
		reply(admin, true, `Reset {target.name}'s save`)
	else
		reply(admin, false, `Couldn't reset {target.name}: {note}`)
	end
end

local function lookup(admin: Player, args: Args)
	local target, why = resolve(args.target)
	if not target then
		return reply(admin, false, why or "?")
	end
	local profile: any = nil
	local where = "saved data"
	if target.player and PlayerData.get(target.player) then
		profile = PlayerData.get(target.player)
		where = "in this server now"
	else
		local ok, saved = PlayerData.peek(target.userId)
		if not ok then
			return reply(admin, false, `Couldn't read {target.name}'s save`)
		end
		profile = saved
	end
	local lines = if profile then Ops.summary(profile, LOOKUP_LINES) else { "(no save yet)" }
	logAction(admin, "lookup", target.userId, target.name, "")
	remote:FireClient(admin, "lookup", {
		name = target.name,
		userId = target.userId,
		where = where,
		lines = lines,
	})
end

local ACTIONS: { [string]: (Player, Args) -> () } = {
	kick = kick,
	ban = ban,
	unban = unban,
	volts = giveVolts,
	boost = giveBoost,
	reset = reset,
	lookup = lookup,
}

local function onRequest(player: Player, action: unknown, args: unknown)
	if not RateLimit.allow(player, "Admin", 1, 5) then
		return
	end
	if typeof(action) ~= "string" then
		return
	end
	if args ~= nil and typeof(args) ~= "table" then
		return
	end
	if not Admin.isAdmin(player) then
		warn(`[Admin] {player.Name} ({player.UserId}) isn't an admin: ignored "{action}"`)
		return
	end
	if action == "open" then
		sendState(player)
		return
	elseif action == "testError" then
		logAction(player, "testError", nil, nil, "")
		Errors.testServerError(player)
		task.delay(0.5, sendState, player)
		return reply(player, true, "Test errors made: they show in ERRORS in a moment")
	elseif action == "testNotify" then
		logAction(player, "testNotify", player.UserId, player.Name, "")
		task.spawn(function()
			local ok, note = Notifications.sendTest(player)
			reply(player, ok, `Test notification: {note}`)
		end)
		return
	end
	local handler = ACTIONS[action]
	if not handler then
		return
	end
	local ok, err = pcall(handler, player, (args or {}) :: Args)
	if not ok then
		reply(player, false, `{action} failed: {err}`)
	end
end

function Admin.init()
	remote = Net.get("Admin")
	remote.OnServerEvent:Connect(onRequest)
	Players.PlayerRemoving:Connect(function(player: Player)
		checks[player] = nil
	end)
end

function Admin.start()
	local function check(player: Player)
		Admin.isAdmin(player)
	end
	Players.PlayerAdded:Connect(check)
	for _, player in Players:GetPlayers() do
		task.spawn(check, player)
	end
end

return Admin
