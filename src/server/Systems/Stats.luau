--!strict
-- Stat counters (the rules and key names are Util/Stats). Systems call
-- Stats.add(player, key, n) next to their Analytics calls; Stats.caught and
-- Stats.sold add the several counters a catch or a sale moves. Playtime
-- counts here, one minute at a time, and so do scheduled events seen.
-- Stats.visited and Stats.saw keep the Storm Log's "visited" and "seen"
-- counters (Systems/Movement, Systems/StormCycle call them).
-- Counters and quests start a new day together: Stats.refresh rolls both
-- over (and picks new quests) whenever the UTC day or week has changed. A
-- day is the same one the login streak uses, so Studio's TEST "Next day"
-- starts a new quest day too.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuestRules = require(ReplicatedStorage.Shared.Util.Quests)
local RewardRules = require(ReplicatedStorage.Shared.Util.Rewards)
local StatRules = require(ReplicatedStorage.Shared.Util.Stats)
local Types = require(ReplicatedStorage.Shared.Types)
local Weather = require(ReplicatedStorage.Shared.Util.Weather)
local PlayerData = require(script.Parent.PlayerData)
local Sync = require(script.Parent.Sync)

local PLAYTIME_STEP = 60 -- seconds between playtime minutes

local Stats = {}

-- Today's UTC day number for this player (Studio's "Next day" adds days).
function Stats.today(player: Player): number
	local session = Sync.rewards[player]
	return RewardRules.today(os.time()) + (if session then session.dayOffset else 0)
end

-- Starts a new day (or week) of counters and quests if it's time. Returns
-- the profile, ready to use.
function Stats.refresh(player: Player): Types.Profile?
	local profile = PlayerData.get(player)
	if not profile then
		return nil
	end
	local changed = QuestRules.refresh(
		profile.quests,
		profile.stats,
		player.UserId,
		Stats.today(player),
		profile,
		next(profile.researchers) ~= nil
	)
	if changed then
		Sync.markDirty(player)
	end
	return profile
end

-- Adds `n` to one counter (lifetime, today and this week).
function Stats.add(player: Player, key: string, n: number)
	local profile = Stats.refresh(player)
	if not profile or n <= 0 then
		return
	end
	StatRules.add(profile.stats, key, n, Stats.today(player))
	Sync.markDirty(player)
end

-- A caught bolt: overall, by type, by zone and by type in that zone, and a
-- filled bottle if this catch filled it.
function Stats.caught(
	player: Player,
	boltType: Types.BoltType?,
	zoneId: string,
	filledBottle: boolean
)
	local kind = boltType or "Normal"
	Stats.add(player, StatRules.BOLTS, 1)
	Stats.add(player, StatRules.typeKey(kind), 1)
	Stats.add(player, StatRules.zoneKey(zoneId), 1)
	Stats.add(player, StatRules.typeZoneKey(kind, zoneId), 1)
	if filledBottle then
		Stats.add(player, StatRules.BOTTLES_FILLED, 1)
	end
end

-- A sale: one sale, the Volts it paid, and a full bottle sold if it was full.
function Stats.sold(player: Player, earned: number, fullBottle: boolean)
	Stats.add(player, StatRules.SALES, 1)
	Stats.add(player, StatRules.VOLTS_EARNED, earned)
	if fullBottle then
		Stats.add(player, StatRules.FULL_BOTTLES_SOLD, 1)
	end
end

-- A "visited" counter (the Storm Log's Places page): set to 1 the first
-- time, then left alone. Cheap to call often (Systems/Movement calls it
-- every check).
function Stats.visited(player: Player, key: string)
	local profile = PlayerData.get(player)
	if profile and (profile.stats.lifetime[key] or 0) == 0 then
		Stats.add(player, key, 1)
	end
end

-- A "seen" counter (the Storm Log's Weather page): counts once per UTC
-- day the player was here for it. Cheap to call often.
function Stats.saw(player: Player, key: string)
	local profile = Stats.refresh(player)
	if profile and (profile.stats.today[key] or 0) == 0 then
		Stats.add(player, key, 1)
	end
end

-- Any scheduled event on now counts as seen.
local function seeEvents(player: Player)
	for _, on in Weather.liveEvents() do
		Stats.saw(player, StatRules.eventKey(on.event.name))
	end
end

function Stats.init()
	PlayerData.Loaded:Connect(function(player: Player)
		Stats.refresh(player)
		seeEvents(player)
	end)
end

-- A minute of playtime for everyone in game (this also starts the new day
-- for players who are online at midnight).
function Stats.start()
	while true do
		task.wait(PLAYTIME_STEP)
		for _, player in Players:GetPlayers() do
			Stats.add(player, StatRules.PLAYTIME_MINUTES, 1)
			seeEvents(player)
		end
	end
end

return Stats
