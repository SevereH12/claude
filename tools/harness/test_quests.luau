--!nocheck
-- Stat counters and quests (shared/Util/Stats, Util/Quests): the day and
-- week resets (Monday UTC), deterministic picking, scaling with progress,
-- each template's completion check, claiming, the daily reroll, the Studio
-- "complete quest" tool and the save migration.
--   lune run tools/harness/test_quests.luau
local World = require("./World")

local world = World.new("src")
local Config = world:require("ReplicatedStorage.Shared.Config")
local Stats = world:require("ReplicatedStorage.Shared.Util.Stats")
local Quests = world:require("ReplicatedStorage.Shared.Util.Quests")
local PlayerData = world:require("ServerScriptService.Server.Systems.PlayerData")

local failures = 0
local function check(condition, message)
	if not condition then
		failures += 1
		print("FAIL: " .. message)
	end
end

local DAY = 86400

-- weeks start on Monday (UTC) --------------------------------------------------
-- 1 Jan 1970 (day 0) was a Thursday; 5 Jan 1970 (day 4) a Monday
check(Stats.weekOf(0) == Stats.weekOf(3), "Thursday to Sunday are one week")
check(Stats.weekOf(4) == Stats.weekOf(3) + 1, "Monday starts a new week")
check(Stats.weekOf(10) == Stats.weekOf(4), "Monday to Sunday are one week")
check(Stats.weekOf(11) == Stats.weekOf(4) + 1, "and the next Monday starts the next")
-- 2026-10-26 is a Monday: day 20752
local monday = 20752
check(Stats.weekOf(monday) == Stats.weekOf(monday - 1) + 1, "a real Monday starts a week")
check(
	Stats.untilNextWeek((monday - 1) * DAY + 3600) == 23 * 3600,
	"Sunday 01:00 is 23 h from the next week"
)
check(Stats.untilNextWeek(monday * DAY) == 7 * DAY, "Monday 00:00 is a whole week from the next")
check(Stats.dayOf(monday * DAY + 5) == monday, "a day is a UTC calendar day")

-- counters: lifetime, today and this week ----------------------------------------
local stats = Stats.new()
Stats.add(stats, Stats.BOLTS, 5, monday + 2) -- Wednesday
check(stats.lifetime.boltsCaught == 5 and stats.today.boltsCaught == 5, "counts in every set")
check(stats.thisWeek.boltsCaught == 5, "and this week")
Stats.add(stats, Stats.BOLTS, 3, monday + 3) -- Thursday
check(stats.today.boltsCaught == 3, "a new day starts today's counters again")
check(
	stats.thisWeek.boltsCaught == 8 and stats.lifetime.boltsCaught == 8,
	"the week and lifetime keep counting"
)
Stats.add(stats, Stats.BOLTS, 1, monday + 3)
check(stats.today.boltsCaught == 4, "the same day keeps counting")
Stats.add(stats, Stats.BOLTS, 2, monday + 7) -- next Monday
check(
	stats.thisWeek.boltsCaught == 2 and stats.today.boltsCaught == 2,
	"Monday starts the week again"
)
check(stats.lifetime.boltsCaught == 11, "lifetime never resets")
check(not Stats.roll(stats, monday + 7), "rolling on the same day changes nothing")
check(Stats.get(stats.today, "nothing") == 0, "an unused counter is 0")
check(
	Stats.typeKey("Golden") == "boltsCaught.Golden"
		and Stats.zoneKey("Mesa") == "boltsCaught.zone.Mesa"
		and Stats.typeZoneKey("Golden", "Mesa") == "boltsCaught.Golden.Mesa",
	"counter key names"
)

-- picking: deterministic per player and day ---------------------------------------
local early = { bottleTier = 1, bootTier = 1 }
local late = { bottleTier = #Config.BOTTLES, bootTier = #Config.BOOTS }
local function keys(list)
	local out = {}
	for _, quest in list do
		table.insert(out, quest.key .. ":" .. (quest.zone or "") .. ":" .. quest.target)
	end
	return table.concat(out, ",")
end
local a = Quests.pick(12345, "daily", monday, early, false, {})
local b = Quests.pick(12345, "daily", monday, early, false, {})
check(#a == Config.QUESTS.daily, `{Config.QUESTS.daily} daily quests`)
check(keys(a) == keys(b), "the same player gets the same quests that day")
local distinct = {}
for _, quest in a do
	check(not distinct[quest.key], `no template twice in a day ({quest.key})`)
	distinct[quest.key] = true
	check(quest.key ~= "Promote", "no daily promote quest")
end
local differs = false
for day = monday + 1, monday + 6 do
	if keys(Quests.pick(12345, "daily", day, early, false, {})) ~= keys(a) then
		differs = true
	end
end
check(differs, "other days give other quests")
local others = false
for userId = 1, 6 do
	if keys(Quests.pick(userId, "daily", monday, early, false, {})) ~= keys(a) then
		others = true
	end
end
check(others, "other players get other quests")
local weekly = Quests.pick(12345, "weekly", Stats.weekOf(monday), early, true, {})
check(#weekly == Config.QUESTS.weekly, `{Config.QUESTS.weekly} weekly quest`)
-- a promote quest only comes to players with a researcher
for userId = 1, 60 do
	for _, quest in Quests.pick(userId, "weekly", 100, early, false, {}) do
		check(quest.key ~= "Promote", "no promote quest without a researcher")
	end
end
-- every template is picked by someone
local seen = {}
for userId = 1, 200 do
	for _, quest in Quests.pick(userId, "daily", monday, late, true, {}) do
		seen[quest.key] = true
	end
	for _, quest in Quests.pick(userId, "weekly", 100, late, true, {}) do
		seen[quest.key] = true
	end
end
for _, template in Config.QUESTS.templates do
	check(seen[template.key], `{template.key} quests get picked`)
end
-- a zone quest names a zone they can enter
for userId = 1, 100 do
	for _, quest in Quests.pick(userId, "daily", monday, early, false, {}) do
		if quest.key == "CatchZone" then
			local zone = Config.ZONES[quest.zone]
			check(
				zone and zone.requiresBottle <= 1 and not zone.premium,
				"an early zone quest is in an open zone"
			)
		end
	end
end

-- scaling ------------------------------------------------------------------------------
local catch = Quests.template("Catch")
check(
	Quests.amount(catch, "daily", early) == catch.daily,
	"catch quests start at their base amount"
)
check(Quests.amount(catch, "daily", late) > catch.daily, "catch quests grow with the bottle")
check(
	Quests.amount(catch, "weekly", early) > Quests.amount(catch, "daily", early),
	"weekly asks for more"
)
local volts = Quests.template("Volts")
local earlyVolts = Quests.amount(volts, "daily", early)
local lateVolts = Quests.amount(volts, "daily", late)
check(earlyVolts > 0 and lateVolts > earlyVolts * 10, "Volts quests grow with the grinding rate")
local perMinute = Quests.voltsPerMinute(late)
check(
	math.abs(lateVolts - perMinute * volts.daily) <= perMinute * volts.daily * 0.06,
	"a Volts quest is that many minutes of grinding (rounded)"
)
check(
	Quests.amount(Quests.template("Sell"), "daily", late) == Quests.template("Sell").daily,
	"sell quests stay the same"
)

-- the weekly reward is about five daily ones
local weeklyCharges = Config.QUESTS.weeklyReward.charges or 0
local dailyCharges = 0
for _, template in Config.QUESTS.templates do
	dailyCharges = math.max(dailyCharges, template.reward.charges or 0)
end
check(weeklyCharges >= 3 * dailyCharges, "the weekly quest pays several daily ones")

-- each template's completion check ------------------------------------------------
local cases = {
	{ key = "Catch", stat = Stats.BOLTS },
	{ key = "CatchZone", zone = "Mesa", stat = Stats.zoneKey("Mesa") },
	{ key = "Sell", stat = Stats.FULL_BOTTLES_SOLD },
	{ key = "Golden", stat = Stats.typeKey("Golden") },
	{ key = "Volts", stat = Stats.VOLTS_EARNED },
	{ key = "Play", stat = Stats.PLAYTIME_MINUTES },
	{ key = "Promote", stat = Stats.PROMOTIONS },
}
for _, case in cases do
	local counters = Stats.new()
	Stats.add(counters, case.stat, 2, monday) -- before the quest was picked
	local quest = {
		key = case.key,
		zone = case.zone,
		target = 3,
		base = counters.today[case.stat],
		claimed = false,
	}
	check(Quests.statKey(quest) == case.stat, `{case.key} watches {case.stat}`)
	check(not Quests.isComplete(quest, counters.today), `{case.key}: not done at the start`)
	Stats.add(counters, case.stat, 2, monday)
	check(Quests.progressOf(quest, counters.today) == 2, `{case.key}: only what came after counts`)
	Stats.add(counters, Stats.BOLTS .. ".other", 5, monday)
	check(not Quests.isComplete(quest, counters.today), `{case.key}: other counters don't count`)
	Stats.add(counters, case.stat, 5, monday)
	check(Quests.isComplete(quest, counters.today), `{case.key}: done at its target`)
	check(Quests.progressOf(quest, counters.today) == 3, `{case.key}: progress stops at the target`)
	check(Quests.describe(quest) ~= "", `{case.key} has words`)
end
check(
	Quests.describe({ key = "Golden", target = 1 }) == "Catch a golden bolt",
	"golden quest words"
)
check(
	Quests.describe({ key = "CatchZone", zone = "Mesa", target = 40 }) == "Catch 40 bolts in Mesa",
	"zone quest words"
)

-- refresh, claim and the resets at the day and week edges ---------------------------
local save = Quests.new()
local counters = Stats.new()
check(Quests.refresh(save, counters, 777, monday + 2, early, false), "a new save picks quests")
check(
	#save.daily == Config.QUESTS.daily and #save.weekly == Config.QUESTS.weekly,
	"daily and weekly picked"
)
local weekKeys = keys(save.weekly)
check(not Quests.refresh(save, counters, 777, monday + 2, early, false), "the same day keeps them")
local first = save.daily[1]
Stats.add(counters, Quests.statKey(first), first.target, monday + 2)
check(Quests.claim(save, counters, "daily", 1) == first, "a done quest can be claimed")
check(Quests.claim(save, counters, "daily", 1) == nil, "but only once")
check(
	Quests.claim(save, counters, "daily", 2) == nil
		or Quests.isComplete(save.daily[2], counters.today),
	"an unfinished quest can't be claimed"
)
check(Quests.claim(save, counters, "daily", 9) == nil, "a missing quest can't be claimed")
check(
	Quests.refresh(save, counters, 777, monday + 3, early, false),
	"the next day picks new quests"
)
check(not save.daily[1].claimed, "new quests aren't claimed")
check(keys(save.weekly) == weekKeys, "the weekly quest stays all week")
check(counters.today[Quests.statKey(first)] == nil, "today's counters started again")
Quests.refresh(save, counters, 777, monday + 7, early, false)
check(save.week == Stats.weekOf(monday + 7), "Monday picks a new weekly quest")
check(next(counters.thisWeek) == nil, "and starts the week's counters again")

-- the free reroll: once a day, unfinished quests only ----------------------------------
local day = monday + 7
local before = save.daily[2].key
check(Quests.canReroll(save, counters, "daily", 2, day), "today's reroll is there")
check(Quests.reroll(save, counters, "daily", 2, 777, day, early, false), "reroll swaps a quest")
check(save.daily[2].key ~= before, "for a different one")
local unique = {}
for _, quest in save.daily do
	check(not unique[quest.key], "still no template twice")
	unique[quest.key] = true
end
check(not Quests.canReroll(save, counters, "daily", 1, day), "only one reroll a day")
check(not Quests.reroll(save, counters, "weekly", 1, 777, day, early, false), "the weekly one too")
check(Quests.view(save, counters, day).rerollReady == false, "the client sees it's used")
check(Quests.canReroll(save, counters, "weekly", 1, day + 1), "a new day brings a new reroll")
local doneQuest = save.daily[1]
Stats.add(counters, Quests.statKey(doneQuest), doneQuest.target, day + 1)
Quests.refresh(save, counters, 777, day + 1, early, false)
doneQuest = save.daily[1]
Stats.add(counters, Quests.statKey(doneQuest), doneQuest.target, day + 1)
check(
	not Quests.canReroll(save, counters, "daily", 1, day + 1),
	"a finished quest can't be rerolled"
)

-- the Studio "complete quest" tool and the view -------------------------------------
local fresh = Quests.new()
local freshStats = Stats.new()
Quests.refresh(fresh, freshStats, 42, monday, early, false)
check(Quests.testComplete(fresh, freshStats), "complete quest finishes one")
local view = Quests.view(fresh, freshStats, monday)
check(view.daily[1].progress == view.daily[1].target, "the first daily quest shows done")
check(view.daily[2].progress == 0 and not view.daily[2].claimed, "the others don't")
check(view.rerollReady, "a fresh day has its reroll")
for _ = 1, 10 do
	Quests.testComplete(fresh, freshStats)
end
check(not Quests.testComplete(fresh, freshStats), "nothing left to complete")
check(Quests.isComplete(fresh.weekly[1], freshStats.thisWeek), "the weekly one too")
check(
	Quests.reward(fresh.weekly[1].key, "weekly").charges == Config.QUESTS.weeklyReward.charges,
	"the weekly reward"
)
check(
	Quests.reward("Catch", "daily").charges == Quests.template("Catch").reward.charges,
	"a daily quest's reward"
)

-- the save migration -------------------------------------------------------------------
local migrated = PlayerData.migrate({ version = 12, volts = 10, totalVolts = 5000, bottleTier = 1 })
check(migrated.version == 13, "v12 saves become v13")
check(
	migrated.stats.lifetime[Stats.VOLTS_EARNED] == 5000,
	"lifetime Volts earned starts at what they'd earned"
)
check(
	next(migrated.stats.today) == nil and next(migrated.stats.thisWeek) == nil,
	"today and this week start empty"
)
check(migrated.quests.day == 0 and #migrated.quests.daily == 0, "quests get picked when they load")
local fromOld = PlayerData.migrate({ version = 1, volts = 0, bottleTier = 1 })
check(
	typeof(fromOld.stats) == "table" and typeof(fromOld.quests) == "table",
	"old saves get counters and quests"
)

if failures > 0 then
	error(`{failures} quest checks failed`)
end
print("quest checks passed")
