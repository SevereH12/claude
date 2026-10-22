--!nocheck
-- Gifting's rules (shared/Util/Gifts): intent matching and expiry, the
-- receipt plan (including the no-intent credit path), inbox apply with
-- duplicate ids skipped, owned = real or gifted, and every refusal rule.
--   lune run tools/harness/test_gifts.luau
local World = require("./World")

local world = World.new("src")
local Config = world:require("ReplicatedStorage.Shared.Config")
local Gifts = world:require("ReplicatedStorage.Shared.Util.Gifts")
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
	check(Gifts.passFor(key) ~= nil and Gifts.passFor(key).key == pass.key, `{key} gives {pass.key}`)
	local id = Gifts.productId(key)
	check(id > 0 and Config.GIFT_PASS_PRODUCTS[pass.key] == id, `{key} has its product id`)
	check(Gifts.byProductId(id) == key, `product {id} is {key}`)
	check((Config.GIFT_ICONS[key] or 0) > 0, `{key} has an icon`)
end
check(Gifts.passFor("GiftNothing") == nil and Gifts.passFor("VIP") == nil, "only gift products are gifts")
check(Gifts.byProductId(0) == nil and Gifts.byProductId(123) == nil, "unknown product ids aren't gifts")

-- intent matching and expiry ------------------------------------------------------
local intent = { recipientId = 42, recipientName = "Sam", productKey = "GiftVIP", expires = 1000 }
check(Gifts.intentMatches(intent, "GiftVIP", 999), "a fresh intent for this product matches")
check(not Gifts.intentMatches(intent, "GiftVIP", 1000), "an intent expires")
check(not Gifts.intentMatches(intent, "GiftJetBoots", 999), "an intent is for one product")
check(not Gifts.intentMatches(nil, "GiftVIP", 0), "no intent, no match")
check(Config.GIFTS.intentSeconds == 300, "an intent lasts 5 minutes")

-- the receipt plan ---------------------------------------------------------------------
check(Gifts.receiptPlan({ "p1" }, "p1", 42) == "AlreadyGranted", "a seen purchase is already granted")
check(Gifts.receiptPlan(nil, "p1", 42) == "NotProcessedYet", "no giver profile: not processed yet")
check(Gifts.receiptPlan({}, "p1", 42) == "Inbox", "with someone to send it to: the inbox")
check(Gifts.receiptPlan({}, "p1", nil) == "Credit", "no intent: a gift credit, nothing is lost")
local credits = {}
Gifts.addCredit(credits, "GiftVIP", "p7")
Gifts.addCredit(credits, "GiftVIP", "p8")
Gifts.addCredit(credits, "GiftVIP", "p8")
check(Gifts.creditCounts(credits).GiftVIP == 2, "credits add up, each purchase once")
check(Gifts.nextCredit(credits, "GiftVIP") == "p7", "the oldest credit goes first")
Gifts.removeCredit(credits, "GiftVIP", "p7")
check(Gifts.creditCounts(credits).GiftVIP == 1, "sending one uses one")
Gifts.removeCredit(credits, "GiftVIP", "p8")
check(credits.GiftVIP == nil and Gifts.nextCredit(credits, "GiftVIP") == nil, "no credit, no free gift")

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
check(not Gifts.addToInbox(inbox, entry("one too many")), "a full inbox refuses (the receipt waits)")
check(#Gifts.removeFromInbox(inbox, { a = true, id2 = true }) == Config.GIFTS.inboxCap - 2, "delivered ids leave")

-- inbox apply with duplicate ids skipped
local profile = { giftedPasses = {}, receivedGiftIds = {} }
local applied, done = Gifts.apply(profile, { entry("g1", "VIP"), entry("g2", "JetBoots") })
check(#applied == 2 and profile.giftedPasses.VIP and profile.giftedPasses.JetBoots, "gifts apply")
check(done.g1 and done.g2, "applied gifts can leave the inbox")
applied, done = Gifts.apply(profile, { entry("g1", "VIP"), entry("g3", "LabGrant") })
check(#applied == 1 and applied[1].id == "g3", "an id applied before is skipped")
check(done.g1 and done.g3, "and still leaves the inbox")
check(#profile.receivedGiftIds == 3, "each id is remembered once")
applied, done = Gifts.apply(profile, { { id = "f1", kind = "future", key = "x", fromId = 1, fromName = "A", time = 0 } })
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
check(Gifts.recipientRefusal(vip, false, false) ~= nil, "refused: no such player")
check(Gifts.recipientRefusal(vip, true, nil) ~= nil, "refused: couldn't check what they own")
check(Gifts.recipientRefusal(vip, true, true) == "They already have VIP", "refused: they already have it")
check(Gifts.recipientRefusal(vip, true, false) == nil, "a new pass for them is fine")

-- profiles gain gifts ------------------------------------------------------------------------
local migrated = PlayerData.migrate({ version = 8, volts = 0, bottleTier = 1 })
check(next(migrated.giftedPasses) == nil and #migrated.receivedGiftIds == 0, "v8 saves have no gifts")
check(next(migrated.giftCredits) == nil, "and no gift credits")

if failures > 0 then
	error(`{failures} gift checks failed`)
end
print("gift checks passed")
