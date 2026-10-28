--!nocheck
-- Glint packs (Config.GLINT_PACKS, shared/Util/Store): every zone tier
-- promotions use has its three packs, every product key and id is unique,
-- Config matches tools/store/store_ids.json, a receipt finds its pack (and
-- never a gift or boost), and a receipt pays once.
--   lune run tools/harness/test_store.luau
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local World = require("./World")

local world = World.new("src")
local Config = world:require("ReplicatedStorage.Shared.Config")
local Store = world:require("ReplicatedStorage.Shared.Util.Store")
local Research = world:require("ReplicatedStorage.Shared.Util.Research")
local Gifts = world:require("ReplicatedStorage.Shared.Util.Gifts")
local Boosts = world:require("ReplicatedStorage.Shared.Util.Boosts")

local failures = 0
local function check(condition, message)
	if not condition then
		failures += 1
		print("FAIL: " .. message)
	end
end

local SIZES = { { glints = 25, price = 49 }, { glints = 75, price = 129 }, { glints = 200, price = 299 } }

-- every tier from 1 to maxRank has the three sizes; nothing else is sold --------
local maxRank = Research.maxRank()
check(maxRank >= 1, "there are ranks to promote to")
for tier = 1, maxRank do
	local packs = {}
	for _, pack in Config.GLINT_PACKS do
		if pack.tier == tier then
			packs[pack.glints] = pack
		end
	end
	for _, size in SIZES do
		local pack = packs[size.glints]
		check(pack ~= nil, `tier {tier} has a {size.glints} Glints pack`)
		if pack then
			check(pack.price == size.price, `{pack.key} costs {size.price} Robux`)
			check(pack.productId > 0, `{pack.key} has a product id`)
			check(pack.image > 0, `{pack.key} has an icon`)
		end
	end
end
check(#Config.GLINT_PACKS == maxRank * #SIZES, "three packs a tier, and no others")
for _, pack in Config.GLINT_PACKS do
	check(pack.tier >= 1 and pack.tier <= maxRank, `{pack.key} is for a tier promotions use`)
end

-- names, after the tier's first zone ----------------------------------------------
local function find(tier, glints)
	for _, pack in Config.GLINT_PACKS do
		if pack.tier == tier and pack.glints == glints then
			return pack
		end
	end
	return nil
end
local mesa = find(1, 75)
check(mesa ~= nil and Store.glintPackName(mesa) == "75 Mesa Glints", "tier 1 is Mesa: 75 Mesa Glints")
for tier = 1, maxRank do
	check(Research.tierZone(tier) ~= nil, `tier {tier} has a zone to be named after`)
end

-- keys and product ids are unique across every product -------------------------
local keys, ids = {}, {}
local function addKey(key)
	check(not keys[key], `key {key} is used once`)
	keys[key] = true
end
local function addId(id, key)
	if id ~= 0 then
		check(not ids[id], `product id {id} ({key}) is used once`)
		ids[id] = true
	end
end
for _, pass in Config.PASSES do
	addKey(pass.key)
end
for _, pack in Config.VOLT_PACKS do
	addKey(pack.key)
	addId(pack.productId, pack.key)
end
for _, product in Config.BOOST_PRODUCTS do
	addKey(product.key)
	addId(product.productId, product.key)
end
for key, id in Config.GIFT_PASS_PRODUCTS do
	addId(id, key)
end
for _, pack in Config.GLINT_PACKS do
	addKey(pack.key)
	addId(pack.productId, pack.key)
end

-- Config matches tools/store/store_ids.json ---------------------------------------
local storeIds = serde.decode("json", fs.readFile("tools/store/store_ids.json"))
for _, pack in Config.GLINT_PACKS do
	check(storeIds.glintPacks[pack.key] == pack.productId, `{pack.key}'s id is in store_ids.json`)
	check(storeIds.icons[pack.key] == pack.image, `{pack.key}'s icon is in store_ids.json`)
end

-- a receipt finds its Glint pack, and nothing else claims it ---------------------
for _, pack in Config.GLINT_PACKS do
	check(Store.glintPackById(pack.productId) == pack, `{pack.key}'s receipt finds it`)
	check(Gifts.byProductId(pack.productId) == nil, `{pack.key}'s receipt isn't a gift`)
	check(Boosts.productById(pack.productId) == nil, `{pack.key}'s receipt isn't a boost`)
end
check(Store.glintPackById(0) == nil, "product id 0 is no Glint pack")
check(Store.glintPackById(Config.VOLT_PACKS[1].productId) == nil, "a Volts pack isn't a Glint pack")

-- a receipt pays once (the rule Systems/Receipts follows) ----------------------
local profile = { purchases = {}, glints = { 0, 0 } }
local function receive(purchaseId, pack)
	local decision = Store.receiptDecision(profile.purchases, purchaseId)
	if decision == "Grant" then
		profile.glints[pack.tier + 1] = (profile.glints[pack.tier + 1] or 0) + pack.glints
		Store.recordPurchase(profile.purchases, purchaseId)
	end
	return decision
end
check(receive("buy-1", mesa) == "Grant", "the first receipt grants")
check(receive("buy-1", mesa) == "AlreadyGranted", "the same receipt again is already granted")
check(Research.glintsOf(profile.glints, 1) == 75, "75 Mesa Glints paid once")
check(receive("buy-2", mesa) == "Grant", "a second purchase grants again")
check(Research.glintsOf(profile.glints, 1) == 150, "a second purchase pays again")
check(Store.receiptDecision(nil, "buy-3") == "NotProcessedYet", "no profile: Roblox asks again later")

-- the tier you've reached (the store dims the rest) ----------------------------
check(Store.reachedTier({ bottleTier = 1, bootTier = 1 }) == 0, "a new player has reached tier 0")
check(
	Store.reachedTier({ bottleTier = #Config.BOTTLES, bootTier = 1 }) == maxRank,
	"the last bottle reaches the top tier"
)

if failures > 0 then
	error(`{failures} store checks failed`)
end
print("store checks passed")
