--!nocheck
-- Storm surprises (shared/Util/Weather): rare bolt odds, Supercell timing,
-- scheduled event windows and the sale multiplier with an event on.
--   lune run tools/harness/test_weather.luau
local World = require("./World")

local world = World.new("src")
local Config = world:require("ReplicatedStorage.Shared.Config")
local Passes = world:require("ReplicatedStorage.Shared.Util.Passes")
local Weather = world:require("ReplicatedStorage.Shared.Util.Weather")

local failures = 0
local function check(condition, message)
	if not condition then
		failures += 1
		print("FAIL: " .. message)
	end
end
-- seeded random rolls, 0 <= n < 1 (lune has no Random)
local function seeded(seed)
	math.randomseed(seed)
	return { NextNumber = math.random }
end
local function near(a, b, tolerance)
	return math.abs(a - b) <= (tolerance or 1e-9)
end

-- Bolt types ---------------------------------------------------------------

local golden, rainbow, ball =
	Weather.boltDef("Golden"), Weather.boltDef("Rainbow"), Weather.boltDef("Ball")
check(golden and golden.chance == 0.02 and golden.multiplier == 10, "Golden: 2%, x10")
check(rainbow and rainbow.chance == 0.004 and rainbow.multiplier == 25, "Rainbow: 0.4%, x25")
check(rainbow and rainbow.boostMinutes == 5, "Rainbow: 5 min of a boost")
check(ball and ball.chance == 0.01 and ball.multiplier == 5, "Ball lightning: 1%, x5")
check(Weather.boltMultiplier("Normal") == 1 and Weather.boltMultiplier(nil) == 1, "Normal: x1")
check(Weather.boltMultiplier("Golden") == 10, "Golden multiplier")

-- the edges of the roll
check(Weather.pickBoltType(0, false) == "Golden", "roll 0 is Golden")
check(Weather.pickBoltType(0.0199, false) == "Golden", "roll just under 2% is Golden")
check(Weather.pickBoltType(0.0201, false) == "Rainbow", "roll just over 2% is Rainbow")
check(Weather.pickBoltType(0.0241, false) == "Ball", "roll just over 2.4% is Ball")
check(Weather.pickBoltType(0.0341, false) == "Normal", "roll just over 3.4% is Normal")
check(Weather.pickBoltType(0.999, false) == "Normal", "a high roll is Normal")
check(Weather.pickBoltType(0.09, true) == "Golden", "Supercell: 9% is still Golden (x5 = 10%)")

-- the odds over 100k rolls
local function odds(supercell)
	local random = seeded(1234)
	local counts = { Normal = 0, Golden = 0, Rainbow = 0, Ball = 0 }
	local rolls = 100000
	for _ = 1, rolls do
		local kind = Weather.pickBoltType(random.NextNumber(), supercell)
		counts[kind] += 1
	end
	for kind, count in counts do
		counts[kind] = count / rolls
	end
	return counts
end
local normal = odds(false)
check(near(normal.Golden, 0.02, 0.002), `Golden about 2% (got {normal.Golden})`)
check(near(normal.Rainbow, 0.004, 0.001), `Rainbow about 0.4% (got {normal.Rainbow})`)
check(near(normal.Ball, 0.01, 0.0015), `Ball about 1% (got {normal.Ball})`)
check(near(normal.Normal, 0.966, 0.003), `Normal about 96.6% (got {normal.Normal})`)
local storm = odds(true)
check(near(storm.Golden, 0.10, 0.004), `Supercell Golden about 10% (got {storm.Golden})`)
check(near(storm.Rainbow, 0.004, 0.001), `Supercell Rainbow unchanged (got {storm.Rainbow})`)

-- Supercells ---------------------------------------------------------------

local cell = Config.SUPERCELL
check(
	cell.intervalMinutes == 60 and cell.jitterMinutes == 15 and cell.minutes == 3,
	"Supercell config"
)
check(Weather.nextSupercellAt(1000, 0.5) == 1000 + 60 * 60, "on time: 60 min")
check(Weather.nextSupercellAt(1000, 0) == 1000 + 45 * 60, "earliest: 45 min")
check(Weather.nextSupercellAt(1000, 1) == 1000 + 75 * 60, "latest: 75 min")
check(Weather.nextSupercellAt(0, 5) == 75 * 60, "a roll past 1 is clamped")
local random = seeded(7)
for _ = 1, 1000 do
	local at = Weather.nextSupercellAt(0, random.NextNumber())
	if at < 45 * 60 or at > 75 * 60 then
		check(false, `a Supercell landed outside 45 to 75 min ({at})`)
		break
	end
end
local at = 10000
check(Weather.supercellStage(at - 31, at) == "waiting", "31 s before: waiting")
check(Weather.supercellStage(at - 30, at) == "warning", "30 s before: the countdown")
check(Weather.supercellStage(at - 0.1, at) == "warning", "just before: the countdown")
check(Weather.supercellStage(at, at) == "on", "at the start: on")
check(Weather.supercellStage(at + 179, at) == "on", "179 s in: on")
check(Weather.supercellStage(at + 180, at) == "over", "3 min in: over")
check(Weather.supercellStage(0, math.huge) == "waiting", "none scheduled: waiting")

-- Scheduled events -----------------------------------------------------------

local DAY = 86400
-- 2026-10-24 is a Saturday: 00:00 UTC
local SATURDAY = 1792800000
check(Weather.weekSeconds(SATURDAY) == 5 * DAY, "Saturday 00:00 is 5 days into the week")
check(Weather.weekSeconds(0) == 3 * DAY, "the Unix clock started on a Thursday")
check(Weather.parseWeekly("Sat 00:00") == 5 * DAY, "parse Sat 00:00")
check(Weather.parseWeekly("Sun 23:59") == 6 * DAY + 23 * 3600 + 59 * 60, "parse Sun 23:59")
check(Weather.parseWeekly("Mon 9:05") == 9 * 3600 + 5 * 60, "parse Mon 9:05")
check(Weather.parseWeekly("Someday 10:00") == nil, "a bad day is nil")
check(Weather.parseWeekly("Sat 24:00") == nil, "a bad hour is nil")

local weekend
for _, event in Config.EVENTS do
	if event.name == "Double Volts Weekend" then
		weekend = event
	end
end
check(weekend ~= nil, "Double Volts Weekend is in Config.EVENTS")
check(weekend.startUtc == "Sat 00:00" and weekend.endUtc == "Sun 23:59", "it runs Sat to Sun")
check(weekend.multiplier == 2, "it doubles Volts")

local function on(t)
	local isOn = Weather.eventWindow(weekend, t)
	return isOn
end
check(not on(SATURDAY - 1), "Friday 23:59:59: off")
check(on(SATURDAY), "Saturday 00:00:00: on")
check(on(SATURDAY + DAY + 23 * 3600 + 59 * 60), "Sunday 23:59: on")
check(on(SATURDAY + 2 * DAY - 1), "Sunday 23:59:59: on")
check(not on(SATURDAY + 2 * DAY), "Monday 00:00: off")
check(not on(SATURDAY - 3 * DAY), "Wednesday: off")
for week = 1, 60 do
	local offset = week * 7 * DAY
	if not on(SATURDAY + offset + 3600) or on(SATURDAY + offset - 3600) then
		check(false, `the weekend repeats every week (week {week})`)
		break
	end
end
local _, left = Weather.eventWindow(weekend, SATURDAY)
check(left == 2 * DAY, `two days left at the start (got {left})`)
local _, leftLate = Weather.eventWindow(weekend, SATURDAY + 2 * DAY - 60)
check(leftLate == 60, "a minute left at Sunday 23:59")
local _, offLeft = Weather.eventWindow(weekend, SATURDAY - 10)
check(offLeft == 0, "nothing left while off")

-- a window that wraps past Monday 00:00, and a one-off event
local wrap =
	{ name = "Late", startUtc = "Sun 22:00", endUtc = "Mon 01:59", multiplier = 3, banner = "" }
check(Weather.eventWindow(wrap, SATURDAY + DAY + 23 * 3600), "a wrapping window: Sunday 23:00 on")
check(Weather.eventWindow(wrap, SATURDAY + 2 * DAY + 3600), "a wrapping window: Monday 01:00 on")
check(
	not Weather.eventWindow(wrap, SATURDAY + 2 * DAY + 2 * 3600),
	"a wrapping window: Monday 02:00 off"
)
local once = { name = "Launch", startUtc = 1000, endUtc = 2000, multiplier = 1.5, banner = "" }
check(not Weather.eventWindow(once, 999), "one-off: before")
check(Weather.eventWindow(once, 1000), "one-off: the start")
check(not Weather.eventWindow(once, 2000), "one-off: the end")
local active = Weather.activeEvents(1500, { once, weekend })
check(
	#active == 1 and active[1].event == once and active[1].left == 500,
	"activeEvents lists what's on"
)
check(#Weather.activeEvents(SATURDAY - 10) == 0, "nothing on on a Friday")
check(#Weather.activeEvents(SATURDAY - 10, nil, true) >= 1, "pretend turns the first event on")

-- The sale multiplier with an event on ---------------------------------------

local none = {}
check(Passes.sellMultiplier(Weather.withEvents(none, SATURDAY - 10)) == 1, "Friday: x1")
check(Passes.sellMultiplier(Weather.withEvents(none, SATURDAY + 10)) == 2, "the weekend: x2")
check(Weather.withEvents(none, SATURDAY - 10) == none, "no event: the same set")
local double = Weather.withEvents({ DoubleVolts = true }, SATURDAY + 10)
check(
	near(Passes.sellMultiplier(double), Config.PASS_VALUES.doubleVolts * 2),
	"2x Volts pass and the weekend: x4"
)
check(
	Passes.sale(100, double) == 400,
	"a 100 Volt bottle sells for 400 on the weekend with 2x Volts"
)
check(
	Passes.sale(100, Weather.withEvents(none, SATURDAY + 10)) == 200,
	"a 100 Volt bottle sells for 200"
)

-- The server goal -------------------------------------------------------------

local GOAL = Config.SERVER_GOAL
local Afk = world:require("ReplicatedStorage.Shared.Util.Afk")
check(
	GOAL.minutes == 15 and GOAL.surgeMinutes == 10 and GOAL.multiplier == 2,
	"goal: 15 min, surge 10 min 2x"
)
-- the size: the rates added up, times 15 minutes
check(Weather.goalSize({ 10, 20 }, 0, 0) == 30 * 15 * 60, "two players at 10 and 20 V/s: 27,000")
check(Weather.goalSize({}, 0, 0) == GOAL.minGoal, "an empty server: the smallest goal")
check(Weather.goalSize({ 0.01 }, 0, 0) == GOAL.minGoal, "a tiny rate: the smallest goal")
check(Weather.goalSize({ 0 / 0, -5, 10 }, 0, 0) == 9000, "NaN and negative rates are skipped")
-- each goal this hour is 1.5x the last
check(Weather.goalSize({ 10 }, 1, 0) == 13500, "the second goal is 1.5x")
check(Weather.goalSize({ 10 }, 2, 0) == 20250, "the third is 2.25x")
-- a full server of late players and a small early server take the same time
local function minutesToFill(rates)
	local sum = 0
	for _, rate in rates do
		sum += rate
	end
	return Weather.goalSize(rates, 0, 0) / sum / 60
end
local late, early = {}, {}
for _ = 1, 12 do
	local _, breakdown = Afk.rate(
		{ bottleTier = #Config.BOTTLES, bootTier = #Config.BOOTS },
		{},
		false
	)
	table.insert(late, breakdown.grindPerSecond)
end
for _ = 1, 2 do
	local _, breakdown = Afk.rate({ bottleTier = 5, bootTier = 1 }, {}, false)
	table.insert(early, breakdown.grindPerSecond)
end
check(near(minutesToFill(late), 15, 0.01), "12 late-game players: about 15 minutes")
check(near(minutesToFill(early), 15, 0.01), "2 early players: about 15 minutes")
-- never stuck: a big player leaves after the meter is mostly full
local filled = 25000
check(Weather.goalFloor(filled) == 27500, "the floor is filled + 10%")
check(Weather.goalSize({ 1 }, 0, filled) == 27500, "the goal never drops below filled + 10%")
check(Weather.goalSize({ 1000 }, 0, filled) == 900000, "a bigger goal stays as it is")
check(Weather.goalSize({}, 3, 0) >= GOAL.minGoal, "rounds never go under the smallest goal")
-- the hourly reset
local round, start = Weather.goalRound(2, 100, 100 + 3599)
check(round == 2 and start == 100, "under an hour: the same round")
round, start = Weather.goalRound(2, 100, 100 + 3600)
check(round == 0 and start == 3700, "an hour on: back to round 0")
-- the meter's fraction
check(Weather.goalFraction(62, 100) == 0.62, "62%")
check(Weather.goalFraction(150, 100) == 1, "never over 100%")
check(Weather.goalFraction(nil, 100) == 0 and Weather.goalFraction(5, 0) == 0, "no meter: 0")
-- the top contributors
local top = Weather.topContributors({ Alex = 500, Sam = 1200, Kim = 500, Lee = 10, Zed = 0 }, 3)
check(
	#top == 3 and top[1].name == "Sam" and top[2].name == "Alex" and top[3].name == "Kim",
	"top 3, ties by name"
)
local decoded = Weather.decodeTop(Weather.encodeTop(top))
check(#decoded == 3 and decoded[1].name == "Sam" and decoded[1].volts == 1200, "top 3 round trip")
check(#Weather.decodeTop(nil) == 0 and #Weather.decodeTop("") == 0, "no top: empty")
check(Weather.decodeTop("Big Al=5")[1].name == "Big Al", "names with spaces")
-- a Surge doubles sales, and stacks with a Server Storm
check(Passes.sellMultiplier({ [Passes.SERVER_SURGE] = true }) == 2, "a Surge: x2")
check(
	Passes.sellMultiplier({ [Passes.SERVER_SURGE] = true, [Passes.SERVER_STORM] = true }) == 4,
	"a Surge and a Server Storm: x4"
)

-- Formatting ----------------------------------------------------------------

check(Weather.formatLeft(2 * DAY) == "2d 0h", "2 days")
check(Weather.formatLeft(3 * 3600 + 12 * 60) == "3h 12m", "3h 12m")
check(Weather.formatLeft(65) == "1:05", "1:05")

if failures > 0 then
	error(`{failures} weather check(s) failed`)
end
print("weather checks passed")
