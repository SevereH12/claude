--!nocheck
-- Top-ups (shared/Util/TopUp): the pack offered when a player is short is
-- the cheapest that covers the shortfall (Volts packs grow with progress),
-- else the biggest; packs with no product id are skipped; Glint packs come
-- from the promotion's tier.
--   lune run tools/harness/test_topup.luau
local World = require("./World")

local world = World.new("src")
local Config = world:require("ReplicatedStorage.Shared.Config")
local Store = world:require("ReplicatedStorage.Shared.Util.Store")
local TopUp = world:require("ReplicatedStorage.Shared.Util.TopUp")

local failures = 0
local function check(condition, message)
	if not condition then
		failures += 1
		print("FAIL: " .. message)
	end
end

local function progress(bottleTier)
	return { bottleTier = bottleTier, bootTier = 1 }
end
local function key(pack)
	return if pack then pack.key else "nothing"
end

-- Volts: the cheapest pack that covers it, at several progress levels -----------
for _, tier in { 1, 3, 5, #Config.BOTTLES } do
	local p = progress(tier)
	local biggest = nil
	for _, pack in Config.VOLT_PACKS do
		if biggest == nil or Store.packVolts(pack, p) > Store.packVolts(biggest, p) then
			biggest = pack
		end
	end
	for _, pack in Config.VOLT_PACKS do
		local volts = Store.packVolts(pack, p)
		for _, short in { 1, volts - 1, volts, volts + 1 } do
			local pick = TopUp.volts(short, p)
			check(pick ~= nil, `bottle {tier}: a pack for {short} Volts`)
			if pick then
				local covers = Store.packVolts(pick, p) >= short
				if short <= Store.packVolts(biggest, p) then
					check(covers, `bottle {tier}: {key(pick)} covers {short} Volts`)
					for _, other in Config.VOLT_PACKS do
						if Store.packVolts(other, p) >= short then
							check(
								other.price >= pick.price,
								`bottle {tier}: nothing cheaper than {key(pick)} covers {short}`
							)
						end
					end
				end
			end
		end
	end
	-- nothing covers it: the biggest
	local tooMuch = Store.packVolts(biggest, p) + 1
	check(key(TopUp.volts(tooMuch, p)) == biggest.key, `bottle {tier}: too much offers the biggest`)
end

-- the same shortfall picks a smaller pack as packs grow with progress
local early, late = progress(1), progress(#Config.BOTTLES)
local pocket = Config.VOLT_PACKS[1]
local short = Store.packVolts(pocket, early) + 1
check(key(TopUp.volts(short, early)) ~= pocket.key, "early on, a bigger pack than the Pocket Charge")
check(key(TopUp.volts(short, late)) == pocket.key, "later, the Pocket Charge covers the same shortfall")
check(key(TopUp.volts(1, early)) == pocket.key, "a little short: the cheapest pack")

-- products with no id are skipped -------------------------------------------------
local fake = {
	{ key = "NoId", productId = 0, image = 0, name = "No Id", icon = "", charges = 10_000, price = 1 },
	{ key = "Small", productId = 11, image = 0, name = "Small", icon = "", charges = 100, price = 50 },
	{ key = "Big", productId = 12, image = 0, name = "Big", icon = "", charges = 1_000, price = 200 },
}
check(key(TopUp.volts(1, early, fake)) == "Small", "a pack with no id is never offered")
check(key(TopUp.volts(10 ^ 9, early, fake)) == "Big", "the biggest with an id when none covers it")
check(TopUp.volts(1, early, { fake[1] }) == nil, "nothing to offer when no pack has an id")

-- Glints: packs of the promotion's tier ------------------------------------------
check(key(TopUp.glints(1, 1)) == "Tier1Glints25", "1 short for rank 1: 25 Mesa Glints")
check(key(TopUp.glints(25, 1)) == "Tier1Glints25", "25 short: 25 covers it")
check(key(TopUp.glints(26, 1)) == "Tier1Glints75", "26 short: 75")
check(key(TopUp.glints(150, 3)) == "Tier3Glints200", "150 short for rank 3: 200 of tier 3")
check(key(TopUp.glints(1000, 2)) == "Tier2Glints200", "too many short: the biggest of tier 2")
for rank = 1, 6 do
	local pick = TopUp.glints(10, rank)
	check(pick ~= nil and pick.tier == rank, `rank {rank}: a Glint pack of tier {rank}`)
end
check(TopUp.glints(10, 0) == nil, "no Glint packs for tier 0")
local fakeGlints = {
	{ key = "G0", tier = 1, glints = 500, productId = 0, image = 0, price = 1 },
	{ key = "G1", tier = 1, glints = 25, productId = 21, image = 0, price = 49 },
	{ key = "G2", tier = 2, glints = 500, productId = 22, image = 0, price = 1 },
}
check(key(TopUp.glints(100, 1, fakeGlints)) == "G1", "Glint packs: no id skipped, other tiers ignored")

if failures > 0 then
	error(`{failures} top-up checks failed`)
end
print("top-up checks passed")
