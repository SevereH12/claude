--!nocheck
-- Gifting's rules (shared/Util/Gifts): intent matching and expiry, the
-- receipt plan (including the no-intent credit and FOR ME paths), inbox
-- apply with duplicate ids skipped, owned = real or gifted, every refusal
-- rule, boost gifts adding time, Server Storm stacking and its cap, and the
-- sell multiplier with a pass, a boost, the group bonus and a Server Storm.
--   lune run tools/harness/test_gifts.luau
local World = require("./World")

local world = World.new("src")
local Boosts = world:require("ReplicatedStorage.Shared.Util.Boosts")
local Config = world:require("ReplicatedStorage.Shared.Config")
local Gifts = world:require("ReplicatedStorage.Shared.Util.Gifts")
local Passes = world:require("ReplicatedStorage.Shared.Util.Passes")
local PlayerData = world:require("ServerScriptService.Server.Systems.PlayerData")

local failures = 0
local function check(condition, message)
	if not condition then
		failures += 1
		print("FAIL: " .. message)
	end
end

-- every pass has a gift product -------------------------------------------------
for _, pass in Config.PASSES do
	local key = Gifts.productKey(pass.key)
	check(key == "Gift" .. pass.key, `{pass.key}'s gift product is {key}`)
	check(
		Gifts.passFor(key) ~= nil and Gifts.passFor(key).key == pass.key,
		`{key} gives {pass.key}`
	)
	local id = Gifts.productId(key)
	check(id > 0 and Config.GIFT_PASS_PRODUCTS[pass.key] == id, `{key} has its product id`)
	check(Gifts.byProductId(id) == key, `product {id} is {key}`)
	check((Config.GIFT_ICONS[key] or 0) > 0, `{key} has an icon`)
end
check(
	Gifts.passFor("GiftNothing") == nil and Gifts.passFor("VIP") == nil,
	"only gift products are gifts"
)
check(
	Gifts.byProductId(0) == nil and Gifts.byProductId(123) == nil,
	"unknown product ids aren't gifts"
)

-- intent matching and expiry ------------------------------------------------------
local intent = { recipientId = 42, recipientName = "Sam", productKey = "GiftVIP", expires = 1000 }
check(Gifts.intentMatches(intent, "GiftVIP", 999), "a fresh intent for this product matches")
check(not Gifts.intentMatches(intent, "GiftVIP", 1000), "an intent expires")
check(not Gifts.intentMatches(intent, "GiftJetBoots", 999), "an intent is for one product")
check(not Gifts.intentMatches(nil, "GiftVIP", 0), "no intent, no match")
check(Config.GIFTS.intentSeconds == 300, "an intent lasts 5 minutes")

-- the receipt plan ---------------------------------------------------------------------
check(
	Gifts.receiptPlan({ "p1" }, "p1", 42, "GiftVIP") == "AlreadyGranted",
	"a seen purchase is already granted"
)
check(
	Gifts.receiptPlan(nil, "p1", 42, "GiftVIP") == "NotProcessedYet",
	"no giver profile: not processed yet"
)
check(
	Gifts.receiptPlan({}, "p1", 42, "GiftVIP") == "Inbox",
	"with someone to send it to: the inbox"
)
check(
	Gifts.receiptPlan({}, "p1", nil, "GiftVIP") == "Credit",
	"no intent: a gift credit, nothing is lost"
)
check(Gifts.receiptPlan({}, "p1", 42, "LuckyBoost") == "Inbox", "a boost for someone: their inbox")
check(
	Gifts.receiptPlan({}, "p1", nil, "LuckyBoost") == "ForMe",
	"a boost for nobody: FOR ME, the buyer's own"
)
check(
	Gifts.receiptPlan({ "p1" }, "p1", nil, "LuckyBoost") == "AlreadyGranted",
	"a FOR ME boost is granted once"
)
local credits = {}
Gifts.addCredit(credits, "GiftVIP", "p7")
Gifts.addCredit(credits, "GiftVIP", "p8")
Gifts.addCredit(credits, "GiftVIP", "p8")
check(Gifts.creditCounts(credits).GiftVIP == 2, "credits add up, each purchase once")
check(Gifts.nextCredit(credits, "GiftVIP") == "p7", "the oldest credit goes first")
Gifts.removeCredit(credits, "GiftVIP", "p7")
check(Gifts.creditCounts(credits).GiftVIP == 1, "sending one uses one")
Gifts.removeCredit(credits, "GiftVIP", "p8")
check(
	credits.GiftVIP == nil and Gifts.nextCredit(credits, "GiftVIP") == nil,
	"no credit, no free gift"
)

-- the inbox -------------------------------------------------------------------------------
local function entry(id, key)
	return { id = id, kind = "pass", key = key or "VIP", fromId = 7, fromName = "Alex", time = 0 }
end
local inbox = {}
check(Gifts.addToInbox(inbox, entry("a")), "a gift goes in")
check(Gifts.addToInbox(inbox, entry("a")) and #inbox == 1, "the same id twice is one gift")
for i = 2, Config.GIFTS.inboxCap do
	Gifts.addToInbox(inbox, entry(`id{i}`))
end
check(#inbox == Config.GIFTS.inboxCap, "an inbox holds 100")
check(
	not Gifts.addToInbox(inbox, entry("one too many")),
	"a full inbox refuses (the receipt waits)"
)
check(
	#Gifts.removeFromInbox(inbox, { a = true, id2 = true }) == Config.GIFTS.inboxCap - 2,
	"delivered ids leave"
)

-- inbox apply with duplicate ids skipped
local profile = { giftedPasses = {}, receivedGiftIds = {} }
local applied, done = Gifts.apply(profile, { entry("g1", "VIP"), entry("g2", "JetBoots") })
check(#applied == 2 and profile.giftedPasses.VIP and profile.giftedPasses.JetBoots, "gifts apply")
check(done.g1 and done.g2, "applied gifts can leave the inbox")
applied, done = Gifts.apply(profile, { entry("g1", "VIP"), entry("g3", "LabGrant") })
check(#applied == 1 and applied[1].id == "g3", "an id applied before is skipped")
check(done.g1 and done.g3, "and still leaves the inbox")
check(#profile.receivedGiftIds == 3, "each id is remembered once")
applied, done = Gifts.apply(
	profile,
	{ { id = "f1", kind = "future", key = "x", fromId = 1, fromName = "A", time = 0 } }
)
check(#applied == 0 and not done.f1, "a kind this version doesn't know waits in the inbox")
for i = 1, Config.GIFTS.receivedCap + 10 do
	Gifts.apply(profile, { entry(`many{i}`) })
end
check(#profile.receivedGiftIds == Config.GIFTS.receivedCap, "the last 200 ids are kept")

-- owned = real or gifted -------------------------------------------------------------------
local owned = Gifts.owned({ DoubleVolts = true }, { VIP = true })
check(owned.DoubleVolts and owned.VIP and not owned.JetBoots, "owned is real or gifted")

-- every refusal rule ---------------------------------------------------------------------
check(Gifts.basicRefusal(1, "GiftNope", 2) ~= nil, "refused: not a gift product")
check(Gifts.basicRefusal(1, 5, 2) ~= nil, "refused: a product key must be text")
check(Gifts.basicRefusal(1, "GiftVIP", nil) ~= nil, "refused: nobody chosen")
check(Gifts.basicRefusal(1, "GiftVIP", 2.5) ~= nil, "refused: a user id is a whole number")
check(Gifts.basicRefusal(1, "GiftVIP", -3) ~= nil, "refused: a user id is positive")
check(Gifts.basicRefusal(1, "GiftVIP", 1) ~= nil, "refused: no gifting yourself")
check(Gifts.basicRefusal(1, "GiftVIP", 2) == nil, "a gift to someone else is fine")
local vip = Gifts.passFor("GiftVIP")
check(Gifts.recipientRefusal(vip.name, false, false) ~= nil, "refused: no such player")
check(Gifts.recipientRefusal(vip.name, true, nil) ~= nil, "refused: couldn't check what they own")
check(
	Gifts.recipientRefusal(vip.name, true, true) == "They already have VIP",
	"refused: they already have it"
)
check(Gifts.recipientRefusal(vip.name, true, false) == nil, "a new pass for them is fine")
check(Gifts.basicRefusal(1, "LuckyBoost", 2) == nil, "a boost can be gifted")
check(
	Gifts.basicRefusal(1, "ServerStorm", 2) ~= nil,
	"refused: a Server Storm is for the whole server"
)
check(
	Gifts.basicRefusal(1, "LuckyBoost", 1) ~= nil,
	"refused: no gifting yourself a boost (FOR ME)"
)

-- boosts you can buy and gift ---------------------------------------------------------------
for _, product in Config.BOOST_PRODUCTS do
	local byId = Boosts.productById(product.productId)
	check(
		product.productId > 0 and byId ~= nil and byId.key == product.key,
		`{product.key} has its product id`
	)
	check(product.image > 0, `{product.key} has an icon`)
	if product.serverStorm then
		check(product.boosts == nil, "a Server Storm gives no personal boost")
		check(Gifts.boostFor(product.key) == nil, "a Server Storm can't be gifted")
		check(Gifts.byProductId(product.productId) == nil, "a Server Storm's receipt isn't a gift")
	else
		local gift = Gifts.boostFor(product.key)
		check(gift ~= nil and gift.key == product.key, `{product.key} can be gifted`)
		check(
			Gifts.byProductId(product.productId) == product.key,
			`{product.key}'s receipt goes to Gifts`
		)
		check(
			Gifts.productId(product.key) == product.productId,
			`{product.key}'s gift is the product itself`
		)
		check(
			Gifts.itemName(product.key) == product.name
				and Gifts.price(product.key) == product.price,
			`{product.key} has a name and price`
		)
		for _, boost in product.boosts do
			check(
				Boosts.def(boost.key) ~= nil and boost.minutes > 0,
				`{product.key} gives a real boost`
			)
		end
	end
end
local kind, key = Gifts.entryKind("LuckyBoost")
check(kind == "boost" and key == "LuckyBoost", "a boost gift's inbox entry is kind boost")
kind, key = Gifts.entryKind("GiftVIP")
check(kind == "pass" and key == "VIP", "a pass gift's inbox entry is kind pass")
check(
	Gifts.entryProduct({ kind = "pass", key = "VIP" }) == "GiftVIP",
	"a pass entry came from its gift product"
)
check(
	Gifts.entryProduct({ kind = "boost", key = "LuckyBoost" }) == "LuckyBoost",
	"a boost entry came from the boost"
)

-- boost gifts add time (in full, past the reward cap) ---------------------------------
local function boostEntry(id, key)
	return { id = id, kind = "boost", key = key, fromId = 7, fromName = "Alex", time = 0 }
end
local receiver = { giftedPasses = {}, receivedGiftIds = {}, boosts = { DoubleVolts = 100 } }
applied, done = Gifts.apply(receiver, { boostEntry("b1", "DoubleVoltsBoost") })
check(#applied == 1 and done.b1, "a boost gift applies")
check(
	receiver.boosts.DoubleVolts == 100 + 30 * 60,
	"a 2x Volts Boost gift adds 30 minutes to what's left"
)
applied = Gifts.apply(receiver, { boostEntry("b1", "DoubleVoltsBoost") })
check(
	#applied == 0 and receiver.boosts.DoubleVolts == 100 + 30 * 60,
	"the same boost gift never adds twice"
)
Gifts.apply(receiver, { boostEntry("b2", "BoostBundle") })
check(receiver.boosts.DoubleVolts == 100 + 90 * 60, "the bundle adds an hour of 2x Volts")
check(
	receiver.boosts.Lucky == 3600 and receiver.boosts.BigBottles == 3600,
	"and an hour of Lucky and Big Bottles"
)
Gifts.apply(receiver, { boostEntry("b3", "BoostBundle"), boostEntry("b4", "BoostBundle") })
check(
	receiver.boosts.Lucky == 3 * 3600,
	"bought or gifted time adds in full, past the 2-hour reward cap"
)
applied, done =
	Gifts.apply(receiver, { boostEntry("s1", "ServerStorm"), boostEntry("x1", "NoSuchBoost") })
check(
	#applied == 0 and not done.s1 and not done.x1,
	"a boost this version can't give waits in the inbox"
)
check(next(receiver.giftedPasses) == nil, "boost gifts aren't passes")
-- a boost received while offline is seconds left, so it starts when they next play
local offline = { giftedPasses = {}, receivedGiftIds = {}, boosts = {} }
Gifts.apply(offline, { boostEntry("o1", "LuckyBoost") })
check(offline.boosts.Lucky == 1800, "a gift waits as 30 minutes left, counting down only in game")
-- a reward never takes away bought time
local paid = { DoubleVolts = 3 * 3600 }
Boosts.grant(paid, "DoubleVolts", 600)
check(paid.DoubleVolts == 3 * 3600, "a reward past the cap leaves bought time alone")
Boosts.grant(paid, "DoubleVolts", 600, true)
check(paid.DoubleVolts == 3 * 3600 + 600, "bought time still adds")
local rewards = { DoubleVolts = 7000 }
Boosts.grant(rewards, "DoubleVolts", 600)
check(rewards.DoubleVolts == Config.BOOST_CAP, "reward time still stops at the cap")

-- Server Storm stacking and its cap -----------------------------------------------------
local STORM = Config.SERVER_STORM
check(
	STORM.minutes == 15 and STORM.maxMinutes == 60 and STORM.multiplier == 2,
	"a storm is 15 minutes of 2x, up to 60"
)
check(Boosts.stormAdd(0) == 15 * 60, "a new storm lasts 15 minutes")
check(Boosts.stormAdd(10 * 60) == 25 * 60, "a second purchase adds 15 minutes")
check(Boosts.stormAdd(50 * 60) == 60 * 60, "never past 60 minutes")
check(Boosts.stormAdd(60 * 60) == 60 * 60, "a full storm stays at 60")
check(Boosts.stormAdd(-30) == 15 * 60, "an ended storm starts fresh")
check(
	Boosts.stormHasRoom(45 * 60) and not Boosts.stormHasRoom(45 * 60 + 1),
	"a purchase fits until 45 minutes are left"
)
check(
	Boosts.stormLeft(nil, 100) == 0
		and Boosts.stormLeft(160, 100) == 60
		and Boosts.stormLeft(90, 100) == 0,
	"time left from the attribute"
)

-- the sell multiplier: a pass, a boost, the group bonus and a Server Storm --------------
local GROUP, STORM_KEY = Passes.GROUP, Passes.SERVER_STORM
check(Passes.sale(100, { [STORM_KEY] = true }) == 200, "a Server Storm doubles a sale")
check(
	Passes.sale(100, Passes.withBoosts({ [STORM_KEY] = true }, { DoubleVolts = 60 })) == 400,
	"with a 2x boost: 4x"
)
check(Passes.sale(100, { DoubleVolts = true, [STORM_KEY] = true }) == 400, "with the 2x pass: 4x")
check(
	Passes.sale(100, Passes.withBoosts({ DoubleVolts = true }, { DoubleVolts = 60 })) == 200,
	"a 2x boost adds nothing to the 2x pass"
)
local everything = Passes.withBoosts(
	{ VIP = true, [GROUP] = true, [STORM_KEY] = true },
	{ DoubleVolts = 60 }
)
check(
	Passes.sale(100, everything) == 484,
	"VIP, the group, a 2x boost and a storm: 2 x 1.1 x 1.1 x 2 = 4.84x"
)
local earned, missed, boostExtra = Passes.saleBreakdown(100, { [STORM_KEY] = true }, {})
check(
	earned == 200 and missed == 200 and boostExtra == 0,
	"in a storm, 2x Volts would add another 200"
)

-- profiles gain gifts ------------------------------------------------------------------------
local migrated = PlayerData.migrate({ version = 8, volts = 0, bottleTier = 1 })
check(
	next(migrated.giftedPasses) == nil and #migrated.receivedGiftIds == 0,
	"v8 saves have no gifts"
)
check(next(migrated.giftCredits) == nil, "and no gift credits")

if failures > 0 then
	error(`{failures} gift checks failed`)
end
print("gift checks passed")
