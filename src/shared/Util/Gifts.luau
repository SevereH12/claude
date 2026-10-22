--!strict
-- Gifting's rules (Systems/Gifts applies them; tools/harness/test_gifts.luau
-- tests them). Pure: no Roblox services.
--
-- A pass is gifted by buying its "Gift" Developer Product (product key
-- "Gift" .. pass key); a boost by buying the boost itself (its
-- Config.BOOST_PRODUCTS key) through the gift window. The server remembers
-- who it's for (an intent) before the purchase window opens, puts the gift
-- in the receiver's inbox when the receipt arrives, and the receiver's
-- profile applies it once (by id). A boost bought with nobody chosen is
-- for the buyer (FOR ME).

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)
local Boosts = require(script.Parent.Boosts)
local Store = require(script.Parent.Store)

local GIFTS = Config.GIFTS

local Gifts = {}

Gifts.PREFIX = "Gift"

-- The gift product key for a pass: "GiftVIP".
function Gifts.productKey(passKey: string): string
	return Gifts.PREFIX .. passKey
end

-- The pass a gift product gives, or nil when it isn't a gift product.
function Gifts.passFor(productKey: string): Types.PassDef?
	for _, pass in Config.PASSES do
		if Gifts.productKey(pass.key) == productKey and Config.GIFT_PASS_PRODUCTS[pass.key] then
			return pass
		end
	end
	return nil
end

-- The boost a gift of this product gives (a boost you can buy that isn't
-- a Server Storm), or nil.
function Gifts.boostFor(productKey: string): Types.BoostProductDef?
	local product = Boosts.product(productKey)
	return if product and product.boosts then product else nil
end

-- A gift product's Developer Product id (0 = not made yet).
function Gifts.productId(productKey: string): number
	local pass = Gifts.passFor(productKey)
	if pass then
		return Config.GIFT_PASS_PRODUCTS[pass.key] or 0
	end
	local boost = Gifts.boostFor(productKey)
	return if boost then boost.productId else 0
end

-- The gift product (a pass's or a boost) with this Developer Product id,
-- or nil.
function Gifts.byProductId(productId: number): string?
	for passKey, id in Config.GIFT_PASS_PRODUCTS do
		if id ~= 0 and id == productId then
			return Gifts.productKey(passKey)
		end
	end
	local boost = Boosts.productById(productId)
	return if boost and boost.boosts then boost.key else nil
end

-- What a gift product gives, by name ("VIP", "Lucky Boost"), or nil.
function Gifts.itemName(productKey: string): string?
	local pass = Gifts.passFor(productKey)
	if pass then
		return pass.name
	end
	local boost = Gifts.boostFor(productKey)
	return if boost then boost.name else nil
end

-- A gift product's Robux price before Roblox's real price loads.
function Gifts.price(productKey: string): number
	local pass = Gifts.passFor(productKey)
	if pass then
		return pass.price
	end
	local boost = Gifts.boostFor(productKey)
	return if boost then boost.price else 0
end

-- An inbox entry's kind and key for a gift product: ("pass", pass key) or
-- ("boost", boost product key).
function Gifts.entryKind(productKey: string): (string, string)
	local pass = Gifts.passFor(productKey)
	if pass then
		return "pass", pass.key
	end
	return "boost", productKey
end

-- The gift product an inbox entry came from ("GiftVIP", "LuckyBoost").
function Gifts.entryProduct(entry: Types.GiftEntry): string
	return if entry.kind == "pass" then Gifts.productKey(entry.key) else entry.key
end

-- What a player owns: real passes and gifted ones alike.
function Gifts.owned(
	real: { [string]: boolean },
	gifted: { [string]: boolean }
): { [string]: boolean }
	local set = table.clone(real)
	for key in gifted do
		set[key] = true
	end
	return set
end

-- Why a gift request can't go, before asking Roblox anything (a message
-- for the giver), or nil.
function Gifts.basicRefusal(giverId: number, productKey: unknown, recipientId: unknown): string?
	if typeof(productKey) ~= "string" or not Gifts.itemName(productKey) then
		return "That isn't something you can gift"
	end
	if
		typeof(recipientId) ~= "number"
		or recipientId ~= math.floor(recipientId)
		or recipientId <= 0
	then
		return "Choose who it's for first"
	end
	if recipientId == giverId then
		return "You can't gift yourself: get it in the store instead"
	end
	return nil
end

-- Why `itemName` can't go to this receiver: `exists` (Roblox knows the
-- player) and `has` (they already have the pass, real or gifted; nil when
-- that couldn't be checked; boosts stack, so always false), or nil.
function Gifts.recipientRefusal(itemName: string, exists: boolean, has: boolean?): string?
	if not exists then
		return "There's no player with that name"
	end
	if has == nil then
		return "Couldn't check right now. Try again in a moment"
	end
	if has then
		return `They already have {itemName}`
	end
	return nil
end

-- Is this intent for this product and still fresh? (`now`: os.clock())
function Gifts.intentMatches(intent: Types.GiftIntent?, productKey: string, now: number): boolean
	return intent ~= nil and intent.productKey == productKey and now < intent.expires
end

-- What to do with a gift product's (or a boost's) receipt. `purchases` are
-- the buyer's handled purchase ids (nil: their profile isn't loaded);
-- `recipientId` is who it's for (from a live intent or the receipt's saved
-- marker), nil when nobody knows:
--   "AlreadyGranted": handled before
--   "NotProcessedYet": the buyer's profile isn't here; Roblox asks again
--   "Inbox": put it in the receiver's inbox
--   "Credit": a pass gift for nobody: the giver gets a gift credit to send
--     to anyone later
--   "ForMe": a boost for nobody: it's the buyer's own (FOR ME)
export type ReceiptPlan = "AlreadyGranted" | "NotProcessedYet" | "Inbox" | "Credit" | "ForMe"

function Gifts.receiptPlan(
	purchases: { string }?,
	purchaseId: string,
	recipientId: number?,
	productKey: string
): ReceiptPlan
	local decision = Store.receiptDecision(purchases, purchaseId)
	if decision ~= "Grant" then
		return decision
	end
	if recipientId then
		return "Inbox"
	end
	return if Gifts.boostFor(productKey) then "ForMe" else "Credit"
end

-- Puts a gift in an inbox list: each id once, at most Config.GIFTS.inboxCap.
-- False when it's full: the receipt waits, nothing is dropped.
function Gifts.addToInbox(entries: { Types.GiftEntry }, entry: Types.GiftEntry): boolean
	for _, other in entries do
		if other.id == entry.id then
			return true
		end
	end
	if #entries >= GIFTS.inboxCap then
		return false
	end
	table.insert(entries, entry)
	return true
end

-- An inbox list without the given ids.
function Gifts.removeFromInbox(
	entries: { Types.GiftEntry },
	ids: { [string]: boolean }
): { Types.GiftEntry }
	local kept: { Types.GiftEntry } = {}
	for _, entry in entries do
		if not ids[entry.id] then
			table.insert(kept, entry)
		end
	end
	return kept
end

-- Applies inbox gifts to a profile, each id once (a gift applied just
-- before a crash is skipped the next time). A pass counts as owned; a
-- boost adds its time in full, counting down only while they play (so one
-- received offline starts when they next join). Returns the gifts applied
-- now, and every id that can leave the inbox (applied now or before). A
-- kind or key this version doesn't know stays in the inbox.
export type Receiver = {
	giftedPasses: { [string]: boolean },
	receivedGiftIds: { string },
	boosts: Boosts.Left,
}

function Gifts.apply(
	profile: Receiver,
	entries: { Types.GiftEntry }
): ({ Types.GiftEntry }, { [string]: boolean })
	local applied: { Types.GiftEntry } = {}
	local done: { [string]: boolean } = {}
	for _, entry in entries do
		local boost = if entry.kind == "boost" then Gifts.boostFor(entry.key) else nil
		if table.find(profile.receivedGiftIds, entry.id) then
			done[entry.id] = true
		elseif boost or (entry.kind == "pass" and Gifts.passFor(Gifts.productKey(entry.key))) then
			if boost then
				Boosts.grantProduct(profile.boosts, boost)
			else
				profile.giftedPasses[entry.key] = true
			end
			table.insert(profile.receivedGiftIds, entry.id)
			while #profile.receivedGiftIds > GIFTS.receivedCap do
				table.remove(profile.receivedGiftIds, 1)
			end
			table.insert(applied, entry)
			done[entry.id] = true
		end
	end
	return applied, done
end

-- Gift credits: paid-for gifts with nobody chosen yet, by product key, as
-- the purchase ids that paid for them (sending one reuses its id, so it
-- can only ever arrive once).
export type Credits = { [string]: { string } }

function Gifts.addCredit(credits: Credits, productKey: string, purchaseId: string)
	local list = credits[productKey] or {}
	credits[productKey] = list
	if not table.find(list, purchaseId) then
		table.insert(list, purchaseId)
	end
end

-- The credit to send next for this product (its purchase id), or nil.
function Gifts.nextCredit(credits: Credits, productKey: string): string?
	local list = credits[productKey]
	return if list then list[1] else nil
end

-- A credit is sent: it's gone.
function Gifts.removeCredit(credits: Credits, productKey: string, purchaseId: string)
	local list = credits[productKey]
	local index = if list then table.find(list, purchaseId) else nil
	if list and index then
		table.remove(list, index)
		if #list == 0 then
			credits[productKey] = nil
		end
	end
end

-- How many gifts of each product are waiting to be sent.
function Gifts.creditCounts(credits: Credits): { [string]: number }
	local counts: { [string]: number } = {}
	for key, list in credits do
		if #list > 0 then
			counts[key] = #list
		end
	end
	return counts
end

return Gifts
