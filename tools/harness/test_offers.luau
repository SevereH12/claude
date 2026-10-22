--!nocheck
-- The store's rules (shared/Util/Store): when an offer may show, what to do
-- with a purchase receipt, and how Volts packs scale with progress.
--   lune run tools/harness/test_offers.luau
local World = require("./World")

local world = World.new("src")
local Config = world:require("ReplicatedStorage.Shared.Config")
local Store = world:require("ReplicatedStorage.Shared.Util.Store")
local PlayerData = world:require("ServerScriptService.Server.Systems.PlayerData")

local failures = 0
local function check(condition, message)
	if not condition then
		failures += 1
		print("FAIL: " .. message)
	end
end

local STORE = Config.STORE

-- canOffer: every rule on its own -----------------------------------------------
local function state(sessionStart, lastOfferAt, shown)
	return { sessionStart = sessionStart, lastOfferAt = lastOfferAt, shown = shown or {} }
end
local start = 1000
local later = start + STORE.offerFirstAfter + 1 -- past the quiet start

check(Store.canOffer(state(start), "RemoteSell", later, false, false), "an offer can show")
check(
	not Store.canOffer(state(start), "RemoteSell", start + STORE.offerFirstAfter - 1, false, false),
	"never in the first 3 minutes of a session"
)
check(
	Store.canOffer(state(start), "RemoteSell", start + STORE.offerFirstAfter, false, false),
	"from 3 minutes in"
)
check(
	not Store.canOffer(state(start, later), "LabGrant", later + STORE.offerGap - 1, false, false),
	"at most one offer every 5 minutes"
)
check(
	Store.canOffer(state(start, later), "LabGrant", later + STORE.offerGap, false, false),
	"another offer 5 minutes later"
)
check(
	not Store.canOffer(state(start, nil, { RemoteSell = true }), "RemoteSell", later, false, false),
	"each offer at most once a session"
)
check(
	Store.canOffer(state(start, nil, { RemoteSell = true }), "BigBottles", later, false, false),
	"a different offer can still show"
)
check(
	not Store.canOffer(state(start), "RemoteSell", later, true, false),
	"never over the menu or a panel"
)
check(
	not Store.canOffer(state(start), "RemoteSell", later, false, true),
	"never for a pass they own"
)
check(STORE.offerFirstAfter == 180, "the quiet start is 3 minutes")
check(STORE.offerGap == 300, "offers are 5 minutes apart")

-- the receipt decision ----------------------------------------------------------
check(
	Store.receiptDecision(nil, "abc") == "NotProcessedYet",
	"no loaded profile: not processed yet"
)
check(Store.receiptDecision({ "abc" }, "abc") == "AlreadyGranted", "a seen id: already granted")
check(Store.receiptDecision({ "xyz" }, "abc") == "Grant", "a new id: grant it")
check(Store.receiptDecision({}, "abc") == "Grant", "the first purchase: grant it")
local purchases = {}
for i = 1, STORE.purchaseHistory + 25 do
	Store.recordPurchase(purchases, `id{i}`)
end
check(#purchases == STORE.purchaseHistory, "keeps the last 100 purchase ids")
check(purchases[#purchases] == `id{STORE.purchaseHistory + 25}`, "the newest id is kept")
check(
	Store.receiptDecision(purchases, "id1") == "Grant",
	"ids older than the last 100 are forgotten"
)
check(
	Store.receiptDecision(purchases, `id{STORE.purchaseHistory + 25}`) == "AlreadyGranted",
	"a recent id is remembered"
)

-- profiles gain the purchase history and the trial flag
local migrated = PlayerData.migrate({ version = 6, volts = 0, bottleTier = 1 })
check(
	typeof(migrated.purchases) == "table" and #migrated.purchases == 0,
	"v6 saves get an empty purchase list"
)
check(migrated.trialUsed == false, "v6 saves haven't used the trial")
local fromOld = PlayerData.migrate({ version = 1, volts = 0, bottleTier = 1 })
check(
	fromOld.trialUsed == false and typeof(fromOld.purchases) == "table",
	"older saves get them too"
)

-- pack scaling ------------------------------------------------------------------
local function progress(bottleTier)
	return { bottleTier = bottleTier, bootTier = 1 }
end
-- the best non-premium zone each bottle opens, worked out by hand
local function bestValue(tier)
	local best = 0
	for _, zone in Config.ZONES do
		if not zone.premium and tier >= zone.requiresBottle then
			best = math.max(best, zone.chargeValue)
		end
	end
	return best
end
check(#Config.VOLT_PACKS == 4, "four Volts packs")
local suggested = {
	PocketCharge = { 200, 49 },
	StormJar = { 1000, 199 },
	ThunderCrate = { 6000, 899 },
	LightningVault = { 40000, 3999 },
}
local previousCharges = 0
for _, pack in Config.VOLT_PACKS do
	local want = suggested[pack.key]
	check(want ~= nil, `{pack.key} is a suggested pack`)
	if want then
		check(pack.charges == want[1], `{pack.name} is {want[1]} charges`)
		check(pack.price == want[2], `{pack.name} falls back to {want[2]} Robux`)
	end
	check(pack.charges > previousCharges, `{pack.name} is bigger than the pack before`)
	previousCharges = pack.charges
	check(
		pack.productId >= 0 and pack.productId == math.floor(pack.productId),
		`{pack.name} id is whole`
	)
	local previousVolts = 0
	for tier = 1, #Config.BOTTLES do
		local volts = Store.packVolts(pack, progress(tier))
		check(
			volts == pack.charges * bestValue(tier),
			`{pack.name} at bottle {tier}: charges x best bolt`
		)
		check(volts >= previousVolts, `{pack.name} never shrinks as you progress (bottle {tier})`)
		previousVolts = volts
	end
	check(
		Store.packVolts(pack, progress(#Config.BOTTLES)) > Store.packVolts(pack, progress(1)),
		`{pack.name} grows with progress`
	)
	check(
		string.find(Store.packTime(pack), "^about %d+ ") ~= nil,
		`{pack.name} says about how long`
	)
end
check(
	Store.packVolts(Config.VOLT_PACKS[1], progress(1)) == 200 * 5,
	"a new player's Pocket Charge is 200 Shoreline bolts"
)
check(Store.boltValue(progress(1)) == 5, "the premium zone never counts as the best zone")

if failures > 0 then
	error(`{failures} offer checks failed`)
end
print("offer checks passed")
