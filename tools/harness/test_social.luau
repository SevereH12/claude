--!nocheck
-- The new-player tutorial (shared/Util/Tutorial), the friends boost
-- (Util/Social, Util/Passes) and invite rewards (Util/Social), plus the
-- profile migration that decides who sees the tutorial; leaderboards
-- (Util/Leaderboards), the login run (Util/Rewards) and the notification
-- queue: when reminders are due, and that a due item is only sent once
-- (Util/Notifications, against a pretend MemoryStore sorted map).
--   lune run tools/harness/test_social.luau
local World = require("./World")

local world = World.new("src")
local Config = world:require("ReplicatedStorage.Shared.Config")
local Tutorial = world:require("ReplicatedStorage.Shared.Util.Tutorial")
local Social = world:require("ReplicatedStorage.Shared.Util.Social")
local Passes = world:require("ReplicatedStorage.Shared.Util.Passes")
local Afk = world:require("ReplicatedStorage.Shared.Util.Afk")
local PlayerData = world:require("ServerScriptService.Server.Systems.PlayerData")
local Leaderboards = world:require("ReplicatedStorage.Shared.Util.Leaderboards")
local Notify = world:require("ReplicatedStorage.Shared.Util.Notifications")
local Rewards = world:require("ReplicatedStorage.Shared.Util.Rewards")
local Stats = world:require("ReplicatedStorage.Shared.Util.Stats")

local failures = 0
local function check(condition, message)
	if not condition then
		failures += 1
		print("FAIL: " .. message)
	end
end

-- tutorial steps ----------------------------------------------------------------
local function run(progress, events)
	for _, event in events do
		progress = Tutorial.advance(progress, event)
	end
	return progress
end
local start = Tutorial.restart()
check(start.step == Tutorial.WALK and start.caught == 0, "the tutorial starts at step 1")
check(Tutorial.advance(start, "caught").step == Tutorial.CATCH, "a catch before the gate counts too")
check(Tutorial.advance(start, "sold").step == Tutorial.BUY, "selling early skips to step 4")
local walked = Tutorial.advance(start, "zone")
check(walked.step == Tutorial.CATCH, "entering a zone moves on to catching")
check(Tutorial.advance(walked, "zone").step == Tutorial.CATCH, "entering again changes nothing")
local two = run(walked, { "caught", "caught" })
check(two.step == Tutorial.CATCH and two.caught == 2, "two catches: still catching (2/3)")
local three = Tutorial.advance(two, "caught")
check(three.step == Tutorial.SELL, `{Config.TUTORIAL.catches} catches move on to selling`)
check(Tutorial.advance(three, "caught").step == Tutorial.SELL, "more catches stay on selling")
check(Tutorial.advance(walked, "full").step == Tutorial.SELL, "a full bottle moves on to selling")
local buying = Tutorial.advance(three, "sold")
check(buying.step == Tutorial.BUY, "selling moves on to buying")
check(Tutorial.advance(buying, "sold").step == Tutorial.BUY, "selling again stays on buying")
check(Tutorial.advance(buying, "bottle").step == Tutorial.FINISHED, "buying a bottle finishes it")
local done = { step = Tutorial.DONE, caught = 0 }
check(Tutorial.advance(done, "bottle").step == Tutorial.DONE, "a finished tutorial never comes back")
check(not Tutorial.isActive(Tutorial.DONE) and not Tutorial.isActive(Tutorial.FINISHED), "done shows nothing")

-- skipping
check(Tutorial.skip(two).step == Tutorial.DONE, "SKIP ends it")
check(Tutorial.advance(Tutorial.skip(two), "bottle").step == Tutorial.DONE, "a skipped tutorial pays nothing")

-- who sees it
check(Tutorial.loadStep({ bottleTier = 1, ascension = 0, tutorialStep = 3 }) == 3, "a new player resumes their step")
check(Tutorial.loadStep({ bottleTier = 2, ascension = 0, tutorialStep = 3 }) == Tutorial.DONE, "a Vial owner never sees it")
check(Tutorial.loadStep({ bottleTier = 1, ascension = 1, tutorialStep = 1 }) == Tutorial.DONE, "an ascended player never sees it")
check(Tutorial.loadStep({ bottleTier = 1, ascension = 0, tutorialStep = 9 }) == Tutorial.DONE, "a strange step shows nothing")

-- the card's line
local info = { calm = true, secondsLeft = 75, caught = 1, full = false, nextBottle = "Vial", price = 80, volts = 25 }
check(string.find(Tutorial.cardText(Tutorial.CATCH, info), "1:15") ~= nil, "calm: the card explains the storm timer")
info.calm = false
check(string.find(Tutorial.cardText(Tutorial.CATCH, info), "1/3") ~= nil, "storm: the card counts catches")
check(string.find(Tutorial.cardText(Tutorial.BUY, info), "25 / 80") ~= nil, "short of Volts: the card shows the saving")
info.volts = 80
check(string.find(Tutorial.cardText(Tutorial.BUY, info), "SHOP") ~= nil, "enough Volts: open the SHOP")

-- the migration
local function migrated(bottleTier, ascension)
	return PlayerData.migrate({ version = 15, volts = 0, bottleTier = bottleTier, ascension = ascension })
end
check(migrated(1, 0).tutorialStep == Tutorial.WALK, "a saved Jar player starts the tutorial")
check(migrated(2, 0).tutorialStep == Tutorial.DONE, "a saved Vial owner never sees it")
check(migrated(7, 0).tutorialStep == Tutorial.DONE, "a saved Dynamo Drum owner never sees it")
check(migrated(1, 2).tutorialStep == Tutorial.DONE, "an ascended player never sees it")
check(PlayerData.migrate({ version = 1, volts = 0, bottleTier = 3 }).tutorialStep == Tutorial.DONE, "old saves with a Flask skip it")

-- friends boost ------------------------------------------------------------------
check(Social.countedFriends(0) == 0 and Social.countedFriends(2) == 2, "friends count one each")
check(Social.countedFriends(7) == Config.FRIENDS.max, "the count stops at 3")
check(math.abs(Social.friendsBonus(2) - 0.10) < 1e-9, "2 friends: +10%")
check(math.abs(Social.friendsBonus(9) - 0.15) < 1e-9, "never more than +15%")
check(Social.chipText(0) == "" and Social.chipText(2) == "👥 +10% friends", "the HUD chip text")
local owned = Passes.withFriends({}, 2)
check(owned[Passes.FRIENDS .. "2"] == true and Passes.friendCount(owned) == 2, "the count is a marker in the effects set")
check(next(Passes.withFriends({}, 0)) == nil, "no friends: no marker")
check(math.abs(Passes.sellMultiplier(owned) - 1.10) < 1e-9, "2 friends sell for 1.1x")
check(math.abs(Passes.sellMultiplier(Passes.withFriends({}, 5)) - 1.15) < 1e-9, "5 friends sell for 1.15x")
check(owned.DoubleVolts == nil, "it isn't a pass")
local both = Passes.withFriends({ DoubleVolts = true }, 1)
check(math.abs(Passes.sellMultiplier(both) - 2 * 1.05) < 1e-9, "it multiplies with 2x Volts")
check(Passes.sale(100, both) == 210, "a sale of 100 with 2x Volts and a friend pays 210")
local found = false
local _, breakdown = Afk.rate({ bottleTier = 1, bootTier = 1 }, owned, false)
for _, row in breakdown.multipliers do
	if row.label == "Friends" then
		found = true
	end
end
check(found, "the AFK screen lists the friends boost")

-- invites ------------------------------------------------------------------------
local join = { isNew = true, userId = 10, referrerId = 20, accountAge = 30 }
check(Social.welcomeRefusal(join) == nil and Social.inviterRefusal(join) == nil, "a new player's invite counts")
check(Social.welcomeRefusal({ isNew = false, userId = 10, referrerId = 20, accountAge = 30 }) == "notNew", "only new players")
check(Social.inviterRefusal({ isNew = false, userId = 10, referrerId = 20, accountAge = 30 }) == "notNew", "no inviter reward for an old player")
check(Social.welcomeRefusal({ isNew = true, userId = 10, referrerId = nil, accountAge = 30 }) == "notInvited", "no referrer: not an invite")
check(Social.welcomeRefusal({ isNew = true, userId = 10, referrerId = "20", accountAge = 30 }) == "notInvited", "a strange referrer is ignored")
check(Social.welcomeRefusal({ isNew = true, userId = 10, referrerId = 10, accountAge = 30 }) == "self", "you can't invite yourself")
local young = { isNew = true, userId = 10, referrerId = 20, accountAge = 2 }
check(Social.welcomeRefusal(young) == nil, "a young account still gets the welcome gift")
check(Social.inviterRefusal(young) == "tooYoung", "but its inviter gets nothing (under 3 days)")
check(Social.inviterRefusal({ isNew = true, userId = 10, referrerId = 20, accountAge = 3 }) == nil, "3 days old is enough")

-- the daily cap
local record = nil
local day = 20000
for id = 1, Config.INVITES.dailyCap do
	local ok
	record, ok = Social.countInvite(record, day, 100 + id)
	check(ok, `invite {id} of {Config.INVITES.dailyCap} today is rewarded`)
end
local _, sixth = Social.countInvite(record, day, 200)
check(not sixth, "the 6th rewarded invite of the day is refused")
local _, again = Social.countInvite({ day = day, ids = { 101 } }, day, 101)
check(not again, "the same new player is counted once")
local nextDay, fresh = Social.countInvite(record, day + 1, 200)
check(fresh and #nextDay.ids == 1 and nextDay.day == day + 1, "a new UTC day starts again")
local _, junk = Social.countInvite("junk", day, 5)
check(junk, "a broken record starts again")
check(Social.inviteGiftId(55) == "invite-55", "one inbox id per new player")

-- leaderboards -------------------------------------------------------------------
local profile = PlayerData.migrate({ version = 17, volts = 5, totalVolts = 1234.7, ascension = 2, bestLoginRun = 9 })
profile.stats.lifetime[Stats.BOLTS] = 321
check(Leaderboards.value(profile, "volts") == 1234, "all-time Volts, whole")
check(Leaderboards.value(profile, "bolts") == 321, "bolts caught from the stat counter")
check(Leaderboards.value(profile, "ascension") == 2, "the Ascension level")
check(Leaderboards.value(profile, "streak") == 9, "the longest login run")
profile.totalVolts = 0 / 0
check(Leaderboards.value(profile, "volts") == 0, "a broken number writes 0")
local values = Leaderboards.values(profile)
check(values.volts == 0 and values.bolts == 321, "every board's value at once")
local every = Config.LEADERBOARDS.writeEverySeconds
check(not Leaderboards.shouldWrite(5, 5, 0, 1000, every, true), "an unchanged value is never written")
check(not Leaderboards.shouldWrite(0, nil, -math.huge, 0, every, true), "no zeros for a brand-new player")
check(Leaderboards.shouldWrite(6, nil, -math.huge, 0, every, false), "the first value is written straight away")
check(not Leaderboards.shouldWrite(7, 6, 100, 100 + every - 1, every, false), "a change waits for the 5 minutes")
check(Leaderboards.shouldWrite(7, 6, 100, 100 + every, every, false), "then it's written")
check(Leaderboards.shouldWrite(7, 6, 100, 101, every, true), "leaving writes it now")
check(Leaderboards.backoff(1) == 1 and Leaderboards.backoff(3) == 4 and Leaderboards.backoff(9) == 30, "retry backoff")
local entries = { { userId = 5, name = "A", value = 9 }, { userId = 7, name = "B", value = 8 } }
check(Leaderboards.rankOf(entries, 7) == 2 and Leaderboards.rankOf(entries, 9) == nil, "ranks")
check(Leaderboards.youText(entries, 7, "volts", 8) == "You: #2 · 8 ⚡", "You: #N")
check(
	Leaderboards.youText(entries, 9, "streak", 3) == `You: not in the top {Config.LEADERBOARDS.top} · 3 days`,
	"not in the top 50, with your own value"
)
local test = Leaderboards.testBoards(99, "Me")
check(#test.volts == Config.LEADERBOARDS.top and Leaderboards.rankOf(test.volts, 99) == 7, "test data puts you at #7")
check(Leaderboards.rankOf(test.bolts, 99) == nil, "and off one board")
check(test.volts[1].value >= test.volts[2].value and test.volts[2].value >= test.volts[50].value, "test boards fall")

-- the login run (the longest streak board)
check(Rewards.loginRun(0, 100, 0) == 1, "a first claim starts the run")
check(Rewards.loginRun(99, 100, 7) == 8, "the run keeps counting past day 7")
check(Rewards.loginRun(98, 100, 12) == 1, "a missed day starts it again")
check(Rewards.loginRun(100, 100, 4) == 4, "claimed already today: unchanged")
local streakProfile = PlayerData.migrate({ version = 16, volts = 0, dailyStreak = 4 })
check(streakProfile.loginRun == 4 and streakProfile.bestLoginRun == 4 and streakProfile.notifyAsked == false, "the migration starts the run at the streak day")

-- notifications: when ---------------------------------------------------------------
local DAY = 86400
local today = 20000
local warn = Config.NOTIFICATIONS.streakWarnHours * 3600
local noon = today * DAY + 12 * 3600
local plan = Notify.plan(42, today, 3, noon)
check(#plan == 2, "claimed today with a streak: two reminders")
check(plan[1].kind == "daily" and plan[1].due == (today + 1) * DAY, "daily: at the start of the next UTC day")
check(plan[2].kind == "streak" and plan[2].due == (today + 2) * DAY - warn, "streak: 3 h before it breaks")
local yesterday = Notify.plan(42, today - 1, 3, noon)
check(#yesterday == 1 and yesterday[1].kind == "streak", "today's not claimed yet: it's ready already, only the streak one")
check(yesterday[1].due == (today + 1) * DAY - warn, "which goes 3 h before midnight tonight")
local late = Notify.plan(42, today - 1, 3, (today + 1) * DAY - warn + 1)
check(#late == 0, "nothing that's already due is queued")
check(#Notify.plan(42, today, 1, noon) == 1, "a 1-day run has no streak to lose")
check(#Notify.plan(42, 0, 0, noon) == 0, "never claimed: nothing")
local keys = Notify.keysFor(42, today, 3)
check(keys[1] == plan[1].key and keys[2] == plan[2].key, "coming back finds the same keys to remove")
check(Notify.key(5, 1, "daily") < Notify.key(40, 1, "daily"), "keys sort by due time")
check(plan[1].key < Notify.upperBound(plan[1].due), "the upper bound includes what's due now")
check(not (plan[1].key < Notify.upperBound(plan[1].due - 1)), "and leaves out what isn't due yet")
local body = Notify.body(777, "daily")
check(body.source.universe == "universes/777" and body.payload.type == "MOMENT", "the Open Cloud request body")

-- notifications: only sent once ------------------------------------------------------
-- a pretend MemoryStore sorted map: UpdateAsync runs the transform on the
-- current value and stores what it returns (nil = no change)
local stored = {}
local function updateAsync(key, transform)
	local result = transform(stored[key])
	if result ~= nil then
		stored[key] = result
		return result
	end
	return nil
end
for _, item in plan do
	stored[item.key] = { userId = item.userId, kind = item.kind, due = item.due }
end
local claimSeconds = Config.NOTIFICATIONS.claimSeconds
local dueAt = plan[1].due
local function tryClaim(server, key, now)
	local result = updateAsync(key, function(old)
		return Notify.claim(old, server, now, claimSeconds)
	end)
	return Notify.won(result, server, now)
end
check(not tryClaim("A", plan[1].key, dueAt - 1), "not claimed before it's due")
check(tryClaim("A", plan[1].key, dueAt), "server A claims a due item")
check(not tryClaim("B", plan[1].key, dueAt), "server B can't claim it too")
check(not tryClaim("B", plan[1].key, dueAt + 30), "not even a bit later")
check(not tryClaim("A", plan[1].key, dueAt + 30), "nor A again while it's sending")
check(tryClaim("B", plan[1].key, dueAt + claimSeconds), "a stale claim (server A stopped) can be taken over")
stored[plan[1].key] = nil -- sent and removed
check(not tryClaim("C", plan[1].key, dueAt + claimSeconds + 1), "a removed item can't be claimed")
-- many servers racing for the same items: each is sent exactly once
local sends = {}
for server = 1, 5 do
	for _, item in plan do
		if tryClaim(`S{server}`, item.key, (today + 3) * DAY) then
			sends[item.key] = (sends[item.key] or 0) + 1
		end
	end
end
check(sends[plan[2].key] == 1 and sends[plan[1].key] == nil, "five servers: the remaining item is sent once")
check(Notify.claim("junk", "A", 0, claimSeconds) == nil, "a broken value is left alone")

if failures > 0 then
	error(`{failures} social checks failed`)
end
print("social checks passed")
