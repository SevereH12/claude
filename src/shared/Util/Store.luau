--!strict
-- The store's pure rules (tools/harness/test_offers.luau and test_store.luau
-- test them): what a Volts pack gives, Glint packs' names and products,
-- what to do with a purchase receipt, and when an offer may show. No Roblox
-- services.

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)
local Progression = require(script.Parent.Progression)
local Research = require(script.Parent.Research)

local STORE = Config.STORE

local Store = {}

-- Volts one bolt is worth in the best non-premium zone this progress
-- opens (the zone a pack's `charges` are counted in).
function Store.boltValue(progress: Progression.Progress): number
	local best = Progression.bestZone(progress)
	return if best then best.chargeValue else 0
end

-- The Volts `charges` are worth to this player: that many bolts from their
-- best zone. Volts packs and rewards are counted this way, so they're worth
-- the same playtime early or late.
function Store.volts(charges: number, progress: Progression.Progress): number
	return charges * Store.boltValue(progress)
end

-- The Volts a pack gives this player.
function Store.packVolts(pack: Types.VoltPackDef, progress: Progression.Progress): number
	return Store.volts(pack.charges, progress)
end

-- The name of a tier's Glints, after its first zone: "Mesa".
function Store.tierName(tier: number): string
	local zone = Research.tierZone(tier)
	return if zone then zone.displayName else `Tier {tier}`
end

-- A Glint pack's name: "75 Mesa Glints".
function Store.glintPackName(pack: Types.GlintPackDef): string
	return `{pack.glints} {Store.tierName(pack.tier)} Glints`
end

-- The Glint pack sold as this Developer Product, if any.
function Store.glintPackById(productId: number): Types.GlintPackDef?
	for _, pack in Config.GLINT_PACKS do
		if pack.productId ~= 0 and pack.productId == productId then
			return pack
		end
	end
	return nil
end

-- The highest zone tier this progress has reached: the top tier of the
-- non-premium zones its bottle opens.
function Store.reachedTier(progress: Progression.Progress): number
	local reached = 0
	for _, zone in Config.ZONES do
		if not zone.premium and progress.bottleTier >= zone.requiresBottle then
			reached = math.max(reached, Research.zoneTier(zone))
		end
	end
	return reached
end

-- Roughly how long catching a pack's Volts takes, as "about 20 minutes" or
-- "about 3 hours" (Config.STORE.catchesPerMinute).
function Store.packTime(pack: Types.VoltPackDef): string
	local minutes = pack.charges / STORE.catchesPerMinute
	if minutes < 90 then
		return `about {math.max(1, math.round(minutes))} minutes`
	end
	return `about {math.round(minutes / 60)} hours`
end

-- What to do with a Developer Product receipt. `purchases` is the buyer's
-- saved purchase ids, nil when their profile isn't loaded:
--   "AlreadyGranted": this purchase was granted before; tell Roblox so
--   "NotProcessedYet": no profile to grant into; Roblox asks again later
--   "Grant": grant it, record the id and save before saying so
export type ReceiptDecision = "AlreadyGranted" | "NotProcessedYet" | "Grant"

function Store.receiptDecision(purchases: { string }?, purchaseId: string): ReceiptDecision
	if not purchases then
		return "NotProcessedYet"
	end
	if table.find(purchases, purchaseId) then
		return "AlreadyGranted"
	end
	return "Grant"
end

-- Remembers a granted purchase id, keeping only the newest
-- Config.STORE.purchaseHistory.
function Store.recordPurchase(purchases: { string }, purchaseId: string)
	table.insert(purchases, purchaseId)
	while #purchases > STORE.purchaseHistory do
		table.remove(purchases, 1)
	end
end

-- What the client remembers about offers this session (os.clock() times).
export type OfferState = {
	sessionStart: number,
	lastOfferAt: number?, -- when the last offer showed, nil before the first
	shown: { [string]: boolean }, -- offer keys already shown this session
}

-- May the offer `key` show now? Never in a session's first minutes, at most
-- one every few minutes, each at most once a session, never over the menu
-- or a panel (`uiOpen`), never for a pass the player owns (`owned`).
function Store.canOffer(
	state: OfferState,
	key: string,
	now: number,
	uiOpen: boolean,
	owned: boolean
): boolean
	if owned or uiOpen or state.shown[key] then
		return false
	end
	if now - state.sessionStart < STORE.offerFirstAfter then
		return false
	end
	local last = state.lastOfferAt
	if last and now - last < STORE.offerGap then
		return false
	end
	return true
end

return Store
