--!nocheck
-- Shared game math: walk speed with boots, boots lookups.
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

if failures > 0 then
	error(`{failures} formula checks failed`)
end
print("formula checks passed")
