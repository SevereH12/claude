--!nocheck
-- Rewards (shared/Util/Rewards, Util/Boosts): the daily streak rules,
-- playtime gift readiness, the boost countdown, stacking and cap, boosts
-- working like their passes, and rewards scaling with progress.
--   lune run tools/harness/test_rewards.luau
local World = require("./World")

local world = World.new("src")
local Config = world:require("ReplicatedStorage.Shared.Config")
local Rewards = world:require("ReplicatedStorage.Shared.Util.Rewards")
local Boosts = world:require("ReplicatedStorage.Shared.Util.Boosts")
local Passes = world:require("ReplicatedStorage.Shared.Util.Passes")
local Store = world:require("ReplicatedStorage.Shared.Util.Store")
local Formulas = world:require("ReplicatedStorage.Shared.Util.Formulas")
local PlayerData = world:require("ServerScriptService.Server.Systems.PlayerData")

local failures = 0
local function check(condition, message)
	if not condition then
		failures += 1
		print("FAIL: " .. message)
	end
end

-- the daily streak -----------------------------------------------------------
local today = 20000
local function daily(lastDay, streak)
	local can, nextStreak = Rewards.daily(lastDay, today, streak)
	return can, nextStreak
end
local can, streak = daily(0, 0)
check(can and streak == 1, "the first claim ever is day 1")
can, streak = daily(today - 1, 3)
check(can and streak == 4, "claiming the next day continues the streak")
can, streak = daily(today - 2, 3)
check(can and streak == 1, "a missed day starts again at day 1")
can, streak = daily(today, 3)
check(not can and streak == 3, "already claimed today: no")
can, streak = daily(today - 1, 7)
check(can and streak == 1, "after day 7 it starts again at day 1")
can, streak = daily(today - 1, 6)
check(can and streak == 7, "day 6 then day 7")
can, streak = daily(today + 2, 4)
check(can and streak == 1, "a claim dated in the future (a Studio test day) doesn't lock today")
check(#Config.DAILY_REWARDS == 7, "seven daily rewards")
check(Rewards.today(86400 * 3 + 5) == 3, "a day is a UTC calendar day")
check(Rewards.untilNextDay(86400 * 3 + 5) == 86400 - 5, "time to the next UTC day")

-- playtime gifts -------------------------------------------------------------
local gifts = Config.PLAYTIME_GIFTS
check(#gifts == 6, "six playtime gifts")
local previous = 0
for index, gift in gifts do
	check(gift.minutes > previous, `gift {index} comes after the one before`)
	previous = gift.minutes
	check(
		not Rewards.giftReady(gift, gift.minutes * 60 - 1, false),
		`gift {index}: not before {gift.minutes} min`
	)
	check(
		Rewards.giftReady(gift, gift.minutes * 60, false),
		`gift {index}: ready at {gift.minutes} min`
	)
	check(
		not Rewards.giftReady(gift, gift.minutes * 60 + 999, true),
		`gift {index}: once a day`
	)
end

-- playtime gifts count per UTC day, across visits (profile.playtime)
local fresh = Rewards.playtimeToday(nil, 500)
check(fresh.day == 500 and fresh.seconds == 0 and #fresh.claimed == #gifts, "no save: a fresh day")
check(fresh.claimed[1] == false, "nothing claimed yet")
local saved = { day = 500, seconds = 1800, claimed = { true, true, true } }
local sameDay = Rewards.playtimeToday(saved, 500)
check(sameDay.seconds == 1800 and sameDay.claimed[3] and not sameDay.claimed[4], "rejoining the same day carries on")
check(not Rewards.giftReady(gifts[1], sameDay.seconds, sameDay.claimed[1]), "a claimed gift can't be claimed again after a rejoin")
local nextDay = Rewards.playtimeToday(saved, 501)
check(nextDay.day == 501 and nextDay.seconds == 0 and not nextDay.claimed[1], "a new day starts again")
local broken = Rewards.playtimeToday({ day = 500, seconds = 0 / 0, claimed = "x" }, 500)
check(broken.seconds == 0 and #broken.claimed == #gifts, "a broken save is cleaned up")
local migrated18 = PlayerData.migrate({ version = 17, volts = 0, bottleTier = 1 })
check(migrated18.version >= 18 and migrated18.playtime.day == 0 and migrated18.playtime.seconds == 0, "the v18 migration adds playtime")

-- the boost countdown, stacking and cap ---------------------------------------
local left = {}
Boosts.grant(left, "DoubleVolts", 600)
check(left.DoubleVolts == 600, "a boost starts with its time")
Boosts.grant(left, "DoubleVolts", 600)
check(left.DoubleVolts == 1200, "granting it again adds time")
Boosts.grant(left, "DoubleVolts", 3 * 60 * 60)
check(left.DoubleVolts == Config.BOOST_CAP, "time stacks up to the 2-hour cap")
check(Config.BOOST_CAP == 7200, "the cap is 2 hours")
local ended = Boosts.tick(left, 100)
check(#ended == 0 and left.DoubleVolts == Config.BOOST_CAP - 100, "the countdown")
Boosts.grant(left, "Lucky", 50)
ended = Boosts.tick(left, 60)
check(#ended == 1 and ended[1] == "Lucky" and left.Lucky == nil, "a boost that runs out is gone")
check(left.DoubleVolts == Config.BOOST_CAP - 160, "the others keep counting")

-- boosts work like their passes, and a pass owned adds nothing more --------------
local function near(a, b)
	return math.abs(a - b) < 1e-9
end
local boosts = { DoubleVolts = 60, Lucky = 60, BigBottles = 60 }
local effects = Passes.withBoosts({}, boosts)
check(
	effects.DoubleVolts and effects.LuckyCharges and effects.BigBottles,
	"boosts give their passes' effects"
)
check(
	Passes.sale(100, Passes.withBoosts({}, { DoubleVolts = 1 })) == 200,
	"a 2x boost: sales pay 2x"
)
check(
	Passes.luckChance(Passes.withBoosts({}, { Lucky = 1 })) == 0.15,
	"a Lucky boost: the Lucky Charges chance"
)
check(
	Passes.capacity(10, Passes.withBoosts({}, { BigBottles = 1 })) == 15,
	"a Big Bottles boost: 50% more capacity"
)
check(
	Passes.sale(100, Passes.withBoosts({ DoubleVolts = true }, { DoubleVolts = 60 })) == 200,
	"owning 2x Volts and boosting it is still 2x"
)
check(
	near(Passes.sellMultiplier(Passes.withBoosts({ VIP = true }, { DoubleVolts = 1 })), 2.2),
	"a 2x boost with VIP: 2.2x"
)
check(Passes.withBoosts({}, {}).DoubleVolts == nil, "no boosts, no effects")

-- the group bonus multiplies with passes and boosts ------------------------------
local member = { [Passes.GROUP] = true }
check(near(Passes.sellMultiplier(member), 1.1), "a group member gets +10% Volts")
check(Config.GROUP_ID == 7889739 and Config.GROUP_BONUS == 0.10, "Super Studio, +10%")
check(
	near(
		Passes.sellMultiplier(
			Passes.withBoosts({ [Passes.GROUP] = true, VIP = true }, { DoubleVolts = 60 })
		),
		2.42
	),
	"a member with VIP and a 2x boost: 2 x 1.1 x 1.1"
)
check(
	near(Passes.sellMultiplier({ [Passes.GROUP] = true, DoubleVolts = true }), 2.2),
	"a member with the 2x Volts pass: 2.2x"
)
for value = 0, 2000 do
	check(Passes.sale(value, member) == (value * 11) // 10, `a member's sale of {value}`)
	check(
		Passes.sale(
			value,
			Passes.withBoosts({ [Passes.GROUP] = true, VIP = true }, { DoubleVolts = 60 })
		) == (value * 242) // 100,
		`a member with VIP and a 2x boost selling {value}`
	)
end
do
	local earned, missed = Passes.saleBreakdown(100, member, {})
	check(earned == 110 and missed == 110, "a member without 2x: 2x would have paid +110")
end

-- a boost reward for an owned pass pays Volts instead --------------------------
local reward = {
	charges = 100,
	boosts = { { key = "DoubleVolts", minutes = 10 }, { key = "BigBottles", minutes = 30 } },
}
local resolved = Rewards.resolve(reward, {})
check(
	resolved.charges == 100 and #resolved.boosts == 2 and #resolved.swapped == 0,
	"nothing owned: the boosts"
)
resolved = Rewards.resolve(reward, { DoubleVolts = true })
check(
	resolved.charges == 100 + 10 * Config.REWARD_SWAP_CHARGES
		and #resolved.boosts == 1
		and resolved.boosts[1].key == "BigBottles"
		and resolved.swapped[1] == "DoubleVolts",
	"owning 2x Volts: its boost minutes become charges"
)
for day, dailyReward in Config.DAILY_REWARDS do
	local r = Rewards.resolve(dailyReward, {})
	check(r.charges > 0 or #r.boosts > 0, `day {day} gives something`)
	for _, boost in dailyReward.boosts or {} do
		check(Boosts.def(boost.key) ~= nil, `day {day}: {boost.key} is a boost`)
	end
end

-- rewards scale with progress --------------------------------------------------
local function progress(tier)
	return { bottleTier = tier, bootTier = 1 }
end
check(Store.volts(100, progress(1)) == 100 * 5, "100 charges for a new player: 100 Shoreline bolts")
local before = 0
for tier = 1, #Config.BOTTLES do
	local volts = Store.volts(100, progress(tier))
	check(volts >= before, `100 charges never shrink as you progress (bottle {tier})`)
	before = volts
end
check(
	Store.volts(100, progress(#Config.BOTTLES)) > Store.volts(100, progress(1)),
	"rewards grow with progress"
)
check(Formulas.capacity(1) > 0, "sanity: the Jar holds something")

-- profiles gain boosts and the streak --------------------------------------------
local migrated = PlayerData.migrate({ version = 7, volts = 0, bottleTier = 1 })
check(typeof(migrated.boosts) == "table" and next(migrated.boosts) == nil, "v7 saves get no boosts")
check(
	migrated.dailyStreak == 0 and migrated.lastDailyDay == 0,
	"v7 saves have never claimed a daily reward"
)

if failures > 0 then
	error(`{failures} reward checks failed`)
end
print("reward checks passed")
