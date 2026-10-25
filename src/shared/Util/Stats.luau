--!strict
-- Stat counters: one place that counts what players do (Systems/Stats
-- adds to them; quests, the Storm Log and Ascension read them). Pure: no
-- Roblox services, so tools/harness/test_quests.luau can test it.
--
-- Every counter is kept three times:
--   * lifetime: never resets
--   * today: starts again each UTC day
--   * thisWeek: starts again each Monday 00:00 UTC
--
-- The key names below are what other code reads, so they stay as they are.

local Types = require(script.Parent.Parent.Types)

local Stats = {}

-- Bolts caught, every kind, everywhere.
Stats.BOLTS = "boltsCaught"
-- Sales (one per payout, any size), and Volts earned from sales and the AFK
-- Lounge (rewards don't count, so quest rewards can't fill Volts quests).
Stats.SALES = "sales"
Stats.VOLTS_EARNED = "voltsEarned"
-- Bottles filled to the top by a catch, and sales of a full bottle.
Stats.BOTTLES_FILLED = "bottlesFilled"
Stats.FULL_BOTTLES_SOLD = "fullBottlesSold"
-- Minutes in game (counted once a minute while the profile is loaded).
Stats.PLAYTIME_MINUTES = "playtimeMinutes"
-- Researcher promotions, and gifts sent to other players.
Stats.PROMOTIONS = "researcherPromotions"
Stats.GIFTS_SENT = "giftsSent"

-- Bolts caught of one type: "boltsCaught.Golden" ("Normal" for the rest).
function Stats.typeKey(boltType: string): string
	return `{Stats.BOLTS}.{boltType}`
end

-- Bolts caught in one zone: "boltsCaught.zone.Mesa".
function Stats.zoneKey(zoneId: string): string
	return `{Stats.BOLTS}.zone.{zoneId}`
end

-- Bolts of one type caught in one zone: "boltsCaught.Golden.Mesa".
function Stats.typeZoneKey(boltType: string, zoneId: string): string
	return `{Stats.BOLTS}.{boltType}.{zoneId}`
end

local DAY = 24 * 60 * 60

-- The UTC day number (the same as Util/Rewards.today).
function Stats.dayOf(unixTime: number): number
	return unixTime // DAY
end

-- The week number of a UTC day; weeks start on Monday. Day 0 (1 Jan 1970)
-- was a Thursday, so Monday 5 Jan 1970 (day 4) starts week 1.
function Stats.weekOf(day: number): number
	return (day + 3) // 7
end

-- Seconds until the next Monday 00:00 UTC.
function Stats.untilNextWeek(unixTime: number): number
	local day = Stats.dayOf(unixTime)
	local nextMonday = (Stats.weekOf(day) + 1) * 7 - 3
	return nextMonday * DAY - unixTime
end

-- A fresh set of counters (a new player, or the save migration).
function Stats.new(): Types.StatsSave
	return { lifetime = {}, today = {}, thisWeek = {}, day = 0, week = 0 }
end

-- Starts today's (and this week's) counters again if `day` is a new day
-- (or week). Returns true if anything was reset.
function Stats.roll(save: Types.StatsSave, day: number): boolean
	local changed = false
	if save.day ~= day then
		save.day = day
		save.today = {}
		changed = true
	end
	local week = Stats.weekOf(day)
	if save.week ~= week then
		save.week = week
		save.thisWeek = {}
		changed = true
	end
	return changed
end

-- Adds `n` to a counter in all three sets, on UTC day `day`.
function Stats.add(save: Types.StatsSave, key: string, n: number, day: number)
	Stats.roll(save, day)
	save.lifetime[key] = (save.lifetime[key] or 0) + n
	save.today[key] = (save.today[key] or 0) + n
	save.thisWeek[key] = (save.thisWeek[key] or 0) + n
end

-- A counter's value in one set (0 if it has never counted).
function Stats.get(set: { [string]: number }, key: string): number
	return set[key] or 0
end

return Stats
