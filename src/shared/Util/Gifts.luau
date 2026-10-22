--!strict
-- Gifting's rules (Systems/Gifts applies them; tools/harness/test_gifts.luau
-- tests them). Pure: no Roblox services.
--
-- A pass is gifted by buying its "Gift" Developer Product (product key
-- "Gift" .. pass key). The server remembers who it's for (an intent) before
-- the purchase window opens, puts the gift in the receiver's inbox when the
-- receipt arrives, and the receiver's profile applies it once (by id).

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)
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

-- A gift product's Developer Product id (0 = not made yet).
function Gifts.productId(productKey: string): number
	local pass = Gifts.passFor(productKey)
	return if pass then Config.GIFT_PASS_PRODUCTS[pass.key] or 0 else 0
end

-- The gift product key with this Developer Product id, or nil.
function Gifts.byProductId(productId: number): string?
	for passKey, id in Config.GIFT_PASS_PRODUCTS do
		if id ~= 0 and id == productId then
			return Gifts.productKey(passKey)
		end
	end
	return nil
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
	if typeof(productKey) ~= "string" or not Gifts.passFor(productKey) then
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

-- Why it can't go to this receiver: `exists` (Roblox knows the player) and
-- `has` (they already have the pass, real or gifted; nil when that
-- couldn't be checked), or nil.
function Gifts.recipientRefusal(pass: Types.PassDef, exists: boolean, has: boolean?): string?
	if not exists then
		return "There's no player with that name"
	end
	if has == nil then
		return "Couldn't check right now. Try again in a moment"
	end
	if has then
		return `They already have {pass.name}`
	end
	return nil
end

-- Is this intent for this product and still fresh? (`now`: os.clock())
function Gifts.intentMatches(intent: Types.GiftIntent?, productKey: string, now: number): boolean
	return intent ~= nil and intent.productKey == productKey and now < intent.expires
end

-- What to do with a gift product's receipt. `purchases` are the giver's
-- handled purchase ids (nil: their profile isn't loaded); `recipientId` is
-- who it's for (from a live intent or the receipt's saved marker), nil when
-- nobody knows:
--   "AlreadyGranted": handled before
--   "NotProcessedYet": the giver's profile isn't here; Roblox asks again
--   "Inbox": put it in the receiver's inbox
--   "Credit": the giver gets a gift credit to send to anyone later
export type ReceiptPlan = "AlreadyGranted" | "NotProcessedYet" | "Inbox" | "Credit"

function Gifts.receiptPlan(
	purchases: { string }?,
	purchaseId: string,
	recipientId: number?
): ReceiptPlan
	local decision = Store.receiptDecision(purchases, purchaseId)
	if decision ~= "Grant" then
		return decision
	end
	return if recipientId then "Inbox" else "Credit"
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
-- before a crash is skipped the next time). Returns the gifts applied now,
-- and every id that can leave the inbox (applied now or before). A kind
-- this version doesn't know stays in the inbox.
export type Receiver = { giftedPasses: { [string]: boolean }, receivedGiftIds: { string } }

function Gifts.apply(
	profile: Receiver,
	entries: { Types.GiftEntry }
): ({ Types.GiftEntry }, { [string]: boolean })
	local applied: { Types.GiftEntry } = {}
	local done: { [string]: boolean } = {}
	for _, entry in entries do
		if table.find(profile.receivedGiftIds, entry.id) then
			done[entry.id] = true
		elseif entry.kind == "pass" and Gifts.passFor(Gifts.productKey(entry.key)) then
			profile.giftedPasses[entry.key] = true
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
