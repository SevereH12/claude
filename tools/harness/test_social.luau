--!nocheck
-- The new-player tutorial (shared/Util/Tutorial), the friends boost
-- (Util/Social, Util/Passes) and invite rewards (Util/Social), plus the
-- profile migration that decides who sees the tutorial.
--   lune run tools/harness/test_social.luau
local World = require("./World")

local world = World.new("src")
local Config = world:require("ReplicatedStorage.Shared.Config")
local Tutorial = world:require("ReplicatedStorage.Shared.Util.Tutorial")
local Social = world:require("ReplicatedStorage.Shared.Util.Social")
local Passes = world:require("ReplicatedStorage.Shared.Util.Passes")
local Afk = world:require("ReplicatedStorage.Shared.Util.Afk")
local PlayerData = world:require("ServerScriptService.Server.Systems.PlayerData")

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

if failures > 0 then
	error(`{failures} social checks failed`)
end
print("social checks passed")
