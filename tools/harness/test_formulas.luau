--!nocheck
-- Shared game math: walk speed with boots, boots lookups, charge size.
--   lune run tools/harness/test_formulas.luau
local World = require("./World")

local world = World.new("src")
local Config = world:require("ReplicatedStorage.Shared.Config")
local Formulas = world:require("ReplicatedStorage.Shared.Util.Formulas")

local failures = 0
local function check(condition, message)
	if not condition then
		failures += 1
		print("FAIL: " .. message)
	end
end

check(#Config.BOOTS >= 2, "there are boots to buy")
check(
	Config.BOOTS[1].price == 0 and Config.BOOTS[1].speedBonus == 0,
	"everyone starts in free, plain boots"
)

for tier, def in Config.BOOTS do
	-- between zones everyone walks the same, whatever they wear
	check(
		Formulas.walkSpeed(false, tier) == Config.WALK_SPEED_OUTSIDE,
		`tier {tier}: outside zones walks at WALK_SPEED_OUTSIDE`
	)
	-- inside zones boots add their bonus...
	check(
		Formulas.walkSpeed(true, tier) == Config.WALK_SPEED_IN_ZONE + def.speedBonus,
		`tier {tier}: inside zones walks at WALK_SPEED_IN_ZONE + {def.speedBonus}`
	)
	-- ...but never reach the between-zones speed
	check(
		Formulas.walkSpeed(true, tier) < Config.WALK_SPEED_OUTSIDE,
		`tier {tier}: in-zone speed stays below WALK_SPEED_OUTSIDE`
	)
	if tier > 1 then
		check(
			def.speedBonus > Config.BOOTS[tier - 1].speedBonus,
			`tier {tier} is faster than tier {tier - 1}`
		)
		check(
			def.price > Config.BOOTS[tier - 1].price,
			`tier {tier} costs more than tier {tier - 1}`
		)
	end
	check(Formulas.boots(tier).name == def.name, `boots({tier}) is that tier`)
	local nextDef = Formulas.nextBoots(tier)
	local expected = Config.BOOTS[tier + 1]
	check(
		(nextDef and nextDef.name) == (expected and expected.name),
		`nextBoots({tier}) is the next tier`
	)
end

-- out-of-range tiers clamp instead of erroring
check(Formulas.boots(0).name == Config.BOOTS[1].name, "boots(0) clamps to the first pair")
check(
	Formulas.boots(99).name == Config.BOOTS[#Config.BOOTS].name,
	"boots(99) clamps to the best pair"
)
check(
	Formulas.walkSpeed(true, 99) < Config.WALK_SPEED_OUTSIDE,
	"a bad tier can't exceed the outside speed"
)
check(Formulas.nextBoots(#Config.BOOTS) == nil, "no next boots after the best pair")

-- charge size: bigger zones fill more of the bottle per strike, but a full
-- bottle is always worth more there. Zones in progression order (world,
-- then the bottle they need, then spiral order), premium zones left out.
local progression = {}
for _, zone in Config.ZONES do
	if not zone.premium then
		table.insert(progression, zone)
	end
end
table.sort(progression, function(a, b)
	local wa, wb = Formulas.worldIndex(a.world), Formulas.worldIndex(b.world)
	if wa ~= wb then
		return wa < wb
	elseif a.requiresBottle ~= b.requiresBottle then
		return a.requiresBottle < b.requiresBottle
	end
	return a.order < b.order
end)

-- Volts for one bottle of `capacity` filled strike by strike in `zone`
local function fullBottle(zone, capacity)
	local room, total = capacity, 0
	while room > 0 do
		local units, value = Formulas.fill(zone.chargeSize, zone.chargeValue, room)
		total += value
		room -= units
	end
	return total
end

for index, zone in progression do
	check(
		zone.chargeSize >= 1 and zone.chargeSize == math.floor(zone.chargeSize),
		`{zone.id}: chargeSize is a whole number`
	)
	local capacity = Formulas.capacity(zone.requiresBottle)
	check(capacity >= 5 * zone.chargeSize, `{zone.id}: its bottle holds at least 5 of its strikes`)
	local previous = progression[index - 1]
	if previous then
		check(
			zone.chargeValue / zone.chargeSize > previous.chargeValue / previous.chargeSize,
			`{zone.id} pays more Volts per unit than {previous.id}`
		)
		check(
			fullBottle(zone, capacity) > fullBottle(previous, capacity),
			`a full {Formulas.bottle(zone.requiresBottle).name} is worth more in {zone.id} than in {previous.id}`
		)
	end
end

-- partial fills pay that fraction, rounded down, at least 1
local units, value = Formulas.fill(3, 60, 10)
check(units == 3 and value == 60, "a strike that fits fills its size and pays its value")
units, value = Formulas.fill(3, 60, 1)
check(units == 1 and value == 20, "1 unit of room pays a third of 60")
units, value = Formulas.fill(8, 500, 3)
check(units == 3 and value == 187, "3 of 8 units pays 187 (187.5 rounded down)")
units, value = Formulas.fill(5, 3, 1)
check(units == 1 and value == 1, "a partial fill pays at least 1")
units, value = Formulas.fill(2, 20, 0)
check(units == 0 and value == 0, "a full bottle takes nothing")

-- the premium zone fills like the player's best zone and pays 1.5x per unit
local Progression = world:require("ReplicatedStorage.Shared.Util.Progression")
for _, zone in Config.ZONES do
	if zone.premium then
		for tier = 1, #Config.BOTTLES do
			local progress = { bottleTier = tier, bootTier = 1 }
			local best
			for _, other in progression do
				if
					tier >= other.requiresBottle
					and (best == nil or other.chargeValue > best.chargeValue)
				then
					best = other
				end
			end
			if best then
				check(
					Progression.chargeSize(progress, zone) == best.chargeSize,
					`tier {tier}: {zone.id} fills like {best.id}`
				)
				check(
					Progression.boltValue(progress, zone) / Progression.chargeSize(progress, zone)
						> best.chargeValue / best.chargeSize,
					`tier {tier}: {zone.id} pays more per unit than {best.id}`
				)
			end
		end
	end
end

if failures > 0 then
	error(`{failures} formula checks failed`)
end
print("formula checks passed")
