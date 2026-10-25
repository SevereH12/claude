--!nocheck
-- Stat counters and quests (shared/Util/Stats, Util/Quests): the day and
-- week resets (Monday UTC), deterministic picking, scaling with progress,
-- each template's completion check, claiming, the daily reroll, the Studio
-- "complete quest" tool and the save migration; the Storm Log (Util/StormLog):
-- its pages, row and page completion, claiming, the bonus and its cap; and
-- Ascension (Util/Ascension): the requirements, what resets and what stays,
-- and its bonus stacking with passes, events and the Log.
--   lune run tools/harness/test_quests.luau
local World = require("./World")

local world = World.new("src")
local Config = world:require("ReplicatedStorage.Shared.Config")
local Stats = world:require("ReplicatedStorage.Shared.Util.Stats")
local Quests = world:require("ReplicatedStorage.Shared.Util.Quests")
local PlayerData = world:require("ServerScriptService.Server.Systems.PlayerData")
local StormLog = world:require("ReplicatedStorage.Shared.Util.StormLog")
local Passes = world:require("ReplicatedStorage.Shared.Util.Passes")
local Research = world:require("ReplicatedStorage.Shared.Util.Research")
local Ascension = world:require("ReplicatedStorage.Shared.Util.Ascension")

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

-- the Storm Log -------------------------------------------------------------------------
local function near(a, b)
	return math.abs(a - b) < 1e-9
end
local pages = StormLog.pages()
local pageIds = {}
for _, page in pages do
	pageIds[page.id] = page
end
check(#pages == 4, "four pages")
check(
	pageIds.Bolts and pageIds.Places and pageIds.Team and pageIds.Weather,
	"Bolts, Places, Team and Weather"
)
local zoneCount = 0
for _ in Config.ZONES do
	zoneCount += 1
end
check(#pageIds.Bolts.rows == zoneCount, "a Bolts row per zone")
for _, row in pageIds.Bolts.rows do
	check(#row.entries == 1 + #Config.BOLT_TYPES, `{row.id}: every bolt type`)
end
check(#pageIds.Places.rows == #Config.WORLDS, "a Places row per world")
local placeEntries = 0
for _, row in pageIds.Places.rows do
	placeEntries += #row.entries
end
check(placeEntries == #Config.WORLDS + zoneCount, "every world and zone is a place")
check(#pageIds.Team.rows == #Config.RESEARCHERS, "a Team row per researcher")
for _, row in pageIds.Team.rows do
	check(#row.entries == Research.maxRank() + 1, `{row.id}: hired plus every rank`)
end
check(
	#pageIds.Weather.rows[1].entries == 1 + #Config.EVENTS,
	"Weather: the Supercell and every event"
)
local ids = {}
local unique = true
for _, page in pages do
	for _, row in page.rows do
		check(row.page == page.id, `{row.id} names its page`)
		for _, entry in row.entries do
			unique = unique and not ids[entry.id]
			ids[entry.id] = true
			check(#entry.hint > 0, `{entry.id} has a hint`)
		end
	end
end
check(unique, "entry ids are unique")

-- nothing found yet
local lifetime = {}
local researchers = {}
local found = StormLog.found(lifetime, researchers)
check(next(found) == nil, "a new player has found nothing")
check(#StormLog.pagesDone(found) == 0, "and finished no page")

-- a row: every bolt type in Mesa
local mesa = StormLog.row("Bolts:Mesa")
check(mesa ~= nil, "Mesa has a Bolts row")
lifetime[Stats.typeZoneKey("Normal", "Mesa")] = 3
lifetime[Stats.zoneKey("Mesa")] = 4 -- Systems/Stats.caught counts the zone too
lifetime[Stats.typeZoneKey("Golden", "Mesa")] = 1
found = StormLog.found(lifetime, researchers)
check(found["Bolts:Golden:Mesa"] and found["Bolts:Normal:Mesa"], "caught bolts are found")
check(not found["Bolts:Golden:Shoreline"], "but only in the zone they were caught in")
check(not StormLog.rowDone(mesa, found), "half a row isn't done")
local claimed = {}
check(StormLog.claim(claimed, "Bolts:Mesa", found) == nil, "an unfinished row can't be claimed")
for _, def in Config.BOLT_TYPES do
	lifetime[Stats.typeZoneKey(def.key, "Mesa")] = 1
end
found = StormLog.found(lifetime, researchers)
check(StormLog.rowDone(mesa, found), "every bolt type in Mesa finishes the row")
check(not StormLog.pageDone(pageIds.Bolts, found), "one row isn't the page")
check(StormLog.canClaim("Bolts:Mesa", found, claimed), "a finished row can be claimed")
local reward = StormLog.claim(claimed, "Bolts:Mesa", found)
check(reward == pageIds.Bolts.reward, "it pays its page's row reward")
check(claimed["Bolts:Mesa"] == true, "and is marked claimed")
check(StormLog.claim(claimed, "Bolts:Mesa", found) == nil, "only once")
check(StormLog.claim(claimed, "Bolts:Nowhere", found) == nil, "an unknown row pays nothing")

-- places: a catch in a zone counts as visiting it and its world
found = StormLog.found(lifetime, researchers)
check(
	found["Places:zone:Mesa"] and found["Places:world:Bay"],
	"catching in Mesa visits it (and the Bay)"
)
lifetime[Stats.visitZoneKey("Yard")] = 1
found = StormLog.found(lifetime, researchers)
check(found["Places:zone:Yard"] and found["Places:world:Voltcliff"], "standing in a zone visits it")
check(not found["Places:world:Stormspire"], "a world you haven't been to isn't found")

-- team: a researcher's ranks so far
researchers.Forecaster = { level = 1, data = 0, post = "Office", rank = 2 }
found = StormLog.found(lifetime, researchers)
check(found["Team:Forecaster:0"] and found["Team:Forecaster:2"], "hired and promoted to rank 2")
check(not found["Team:Forecaster:3"], "but not rank 3 yet")
check(not found["Team:RodTech:0"], "a researcher you haven't hired isn't found")

-- weather
lifetime[Stats.SUPERCELLS_SEEN] = 1
found = StormLog.found(lifetime, researchers)
check(found["Weather:Supercell"], "a Supercell seen is found")

-- a whole page, and the bonus
for _, row in pageIds.Bolts.rows do
	for _, entry in row.entries do
		lifetime[entry.stats[1]] = 1
	end
end
found = StormLog.found(lifetime, researchers)
check(StormLog.pageDone(pageIds.Bolts, found), "every bolt in every zone finishes the page")
local done = StormLog.pagesDone(found)
check(#done == 1 and done[1] == "Bolts", "one page done")
local owned = StormLog.withPages({}, found)
check(owned[Passes.LOG_PAGE .. "Bolts"] == true, "a finished page marks the sale effects")
check(near(Passes.sellMultiplier(owned), 1.02), "one page: +2% Volts")
check(
	near(Passes.sellMultiplier(StormLog.withPages({ DoubleVolts = true }, found)), 2.04),
	"it stacks with 2x Volts"
)
check(next(StormLog.withPages({}, {})) == nil, "no page done: nothing added")
check(near(StormLog.bonus(1), 0.02) and near(StormLog.bonus(4), 0.08), "+2% a page")
check(near(StormLog.bonus(10), Config.STORM_LOG.maxBonus), "never more than the cap")
local all = {}
for _, page in pages do
	all[Passes.LOG_PAGE .. page.id] = true
end
check(near(Passes.sellMultiplier(all), 1.08), "every page: +8%")
check(near(Passes.logBonus(all), Config.STORM_LOG.maxBonus), "which is the cap")
local partial = 0
local foundCount, totalCount = StormLog.pageProgress(pageIds.Places, found)
partial = foundCount
check(partial > 0 and partial < totalCount, "page progress counts the entries found")

-- the client's view, and the Studio "+Log entry" tool
local view = StormLog.view(found, claimed)
local backFound, backClaimed = StormLog.fromView(view)
local same = true
for id in found do
	same = same and backFound[id] == true
end
for id in backFound do
	same = same and found[id] == true
end
check(same and backClaimed["Bolts:Mesa"], "the view carries what's found and claimed")
local entry, key = StormLog.nextTestEntry(found)
check(entry ~= nil and key ~= nil and not found[entry.id], "the test tool picks a missing entry")
lifetime[key] = 1
check(StormLog.found(lifetime, researchers)[entry.id], "and its counter finds it")

-- Ascension ------------------------------------------------------------------------------
local top = #Config.BOTTLES
local A = Config.ASCENSION
check(A.baseCost == 10_000_000, "the first Ascension costs 10M Volts")
check(Ascension.cost(0) == A.baseCost and Ascension.cost(2) == 3 * A.baseCost, "baseCost x (level + 1)")
check(
	not Ascension.canAscend({ volts = 1e15, bottleTier = top - 1, ascension = 0 }),
	"not without the top bottle"
)
check(
	not Ascension.canAscend({ volts = A.baseCost - 1, bottleTier = top, ascension = 0 }),
	"not without the Volts"
)
check(
	Ascension.canAscend({ volts = A.baseCost, bottleTier = top, ascension = 0 }),
	"the top bottle and baseCost Volts: ready"
)
check(
	not Ascension.canAscend({ volts = A.baseCost, bottleTier = top, ascension = 1 }),
	"level 1 to 2 needs twice as much"
)

local function fullProfile()
	local profile = PlayerData.migrate({ version = 1, volts = 0, bottleTier = 1 })
	profile.volts = 25_000_000
	profile.totalVolts = 90_000_000
	profile.bottleTier = top
	profile.bootTier = #Config.BOOTS
	profile.chargeCount = 400
	profile.chargeValue = 12345
	profile.tankCount = 50
	profile.tankValue = 999
	profile.researchers = { Chemist = { post = "Office", data = 300, level = 4, rank = 2 } }
	profile.glints = { 5, 10 }
	profile.giftedPasses = { VIP = true }
	profile.logClaimed = { someRow = true }
	profile.dailyStreak = 4
	profile.lastDailyDay = 20000
	profile.boosts = { DoubleVolts = 60 }
	profile.settings.musicVolume = 0.3
	profile.stats.lifetime.boltsCaught = 777
	return profile
end
local ascender = fullProfile()
local questsBefore = ascender.quests
check(Ascension.ascend(ascender) == 1, "ascending gives level 1")
check(ascender.ascension == 1, "and saves it")
check(ascender.volts == 0 and ascender.bottleTier == 1 and ascender.bootTier == 1, "Volts, bottle and boots reset")
check(
	ascender.chargeCount == 0 and ascender.chargeValue == 0 and ascender.tankCount == 0 and ascender.tankValue == 0,
	"bottle contents and the tank reset"
)
check(ascender.totalVolts == 90_000_000, "lifetime earnings stay")
check(
	ascender.researchers.Chemist.level == 4 and ascender.researchers.Chemist.rank == 2,
	"researchers keep their ranks and levels"
)
check(ascender.glints[2] == 10, "Glints stay")
check(ascender.giftedPasses.VIP and ascender.boosts.DoubleVolts == 60, "gifts and boosts stay")
check(ascender.logClaimed.someRow and ascender.quests == questsBefore, "the Log and quests stay")
check(ascender.dailyStreak == 4 and ascender.lastDailyDay == 20000, "the reward streak stays")
check(ascender.settings.musicVolume == 0.3, "settings stay")
check(ascender.stats.lifetime.boltsCaught == 777, "stats stay")
check(Ascension.ascend(ascender) == nil and ascender.ascension == 1, "can't ascend again straight away")
local notReady = fullProfile()
notReady.bottleTier = top - 1
check(Ascension.ascend(notReady) == nil and notReady.volts == 25_000_000, "a refused Ascension changes nothing")

-- the bonus: +50% per level, added up, multiplying with everything else
check(near(Passes.sellMultiplier({}), 1), "level 0: no bonus")
check(near(Passes.sellMultiplier(Passes.withAscension({}, 1)), 1.5), "level 1: +50%")
check(near(Passes.sellMultiplier(Passes.withAscension({}, 3)), 2.5), "level 3: +150% (added, not 1.5^3)")
check(next(Passes.withAscension({}, 0)) == nil, "level 0 adds no mark")
check(
	near(Passes.sellMultiplier(Passes.withAscension({ DoubleVolts = true }, 2)), 4),
	"2x Volts x (1 + 1.0) at level 2"
)
local stack = Passes.withAscension({ DoubleVolts = true, VIP = true }, 1)
stack[Passes.EVENT .. Config.EVENTS[1].name] = true
stack[Passes.SERVER_SURGE] = true
stack[Passes.LOG_PAGE .. Config.STORM_LOG.pages[1].id] = true
local expected = Config.PASS_VALUES.doubleVolts
	* Config.PASS_VALUES.vipVolts
	* Config.EVENTS[1].multiplier
	* Config.SERVER_GOAL.multiplier
	* (1 + Config.STORM_LOG.pageBonus)
	* 1.5
check(near(Passes.sellMultiplier(stack), expected), "stacks with passes, an event, a Surge and the Log")
check(Passes.sale(100, Passes.withAscension({}, 3)) == 250, "a 100 Volt bottle sells for 250 at level 3")
check(Ascension.bonusText(3) == "+150%" and Ascension.stars(2) == "★★", "the text")

-- the save migration -------------------------------------------------------------------
local fromV14 = PlayerData.migrate({ version = 14, volts = 1, bottleTier = 1 })
check(fromV14.version >= 15 and fromV14.ascension == 0, "v14 saves start at Ascension level 0")
local migrated = PlayerData.migrate({ version = 12, volts = 10, totalVolts = 5000, bottleTier = 1 })
check(migrated.version >= 15 and migrated.ascension == 0, "v12 saves become v15 (or a later version)")
check(typeof(migrated.logClaimed) == "table", "with no Log rows claimed")
local fromV13 = PlayerData.migrate({ version = 13, volts = 1, bottleTier = 1 })
check(
	fromV13.version >= 15
		and typeof(fromV13.logClaimed) == "table"
		and next(fromV13.logClaimed) == nil,
	"v13 saves get an empty Storm Log claim list"
)
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
