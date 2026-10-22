--!nocheck
-- Game Pass maths (shared/Util/Passes) and the pass list in Config.
--   lune run tools/harness/test_passes.luau
local World = require("./World")

local world = World.new("src")
local Config = world:require("ReplicatedStorage.Shared.Config")
local Formulas = world:require("ReplicatedStorage.Shared.Util.Formulas")
local Passes = world:require("ReplicatedStorage.Shared.Util.Passes")

local failures = 0
local function check(condition, message)
	if not condition then
		failures += 1
		print("FAIL: " .. message)
	end
end

local none = {}
local all = {}
local keys = {}
for _, pass in Config.PASSES do
	all[pass.key] = true
	check(not keys[pass.key], `{pass.key} is listed once`)
	keys[pass.key] = true
	check(pass.price > 0, `{pass.key} has a fallback price`)
	check(pass.id >= 0 and pass.id == math.floor(pass.id), `{pass.key} id is a whole number`)
	local found = Passes.def(pass.key)
	check(found ~= nil and found.id == pass.id, `def({pass.key})`)
end
check(Passes.def("Nothing") == nil, "unknown pass has no def")
for _, key in
	{
		"DoubleVolts",
		"RemoteSell",
		"BigBottles",
		"LuckyCharges",
		"LabGrant",
		"VIP",
		"BoltColours",
		"JetBoots",
	}
do
	check(keys[key], `{key} is in Config.PASSES`)
end
check(#Config.PASSES == 8, "eight passes")

-- 2x Volts and VIP multiply
local function near(a, b)
	return math.abs(a - b) < 1e-9
end
check(Passes.sellMultiplier(none) == 1, "no pass: sales pay 1x")
check(Passes.sellMultiplier({ DoubleVolts = true }) == 2, "2x Volts pays 2x")
check(near(Passes.sellMultiplier({ VIP = true }), 1.1), "VIP pays 10% more")
check(
	near(Passes.sellMultiplier({ DoubleVolts = true, VIP = true }), 2.2),
	"2x Volts with VIP pays 2.2x"
)
check(Passes.sellMultiplier({ BigBottles = true }) == 1, "other passes don't change sales")
-- a sale rounds down, and never loses a Volt to floating point
for value = 0, 2000 do
	check(Passes.sale(value, none) == value, `sale({value}) with no pass`)
	check(Passes.sale(value, { DoubleVolts = true }) == 2 * value, `sale({value}) with 2x`)
	check(Passes.sale(value, { VIP = true }) == (value * 11) // 10, `sale({value}) with VIP`)
	check(
		Passes.sale(value, { DoubleVolts = true, VIP = true }) == (value * 22) // 10,
		`sale({value}) with 2x and VIP`
	)
end

-- Big Bottles: 50% more, rounded down, on every bottle
for tier, bottle in Config.BOTTLES do
	local base = Formulas.capacity(tier)
	check(Passes.capacity(base, none) == base, `{bottle.name}: no pass keeps its capacity`)
	local big = Passes.capacity(base, { BigBottles = true })
	check(big == math.floor(base * 1.5), `{bottle.name}: Big Bottles holds 50% more`)
	check(big > base, `{bottle.name}: Big Bottles always holds more`)
end
check(Passes.capacity(5, { BigBottles = true }) == 7, "7.5 rounds down to 7")

-- full bottle checks use the player's own capacity
check(Formulas.isFull(5, 5), "5 of 5 is full")
check(not Formulas.isFull(5, Passes.capacity(5, { BigBottles = true })), "5 of 7 is not full")

-- Lucky Charges
check(Passes.luckChance(none) == 0, "no pass: no luck rolls")
check(Passes.luckChance({ LuckyCharges = true }) == 0.15, "Lucky Charges: 15%")

-- Lab Grant: no set-up time, double field data
check(Passes.setupTime(8, none) == 8, "no pass: researchers take the set-up time")
check(Passes.setupTime(8, { LabGrant = true }) == 0, "Lab Grant: set up instantly")
check(Passes.fieldData(3, none) == 3, "no pass: normal field data")
check(Passes.fieldData(3, { LabGrant = true }) == 6, "Lab Grant: double field data")
check(Passes.fieldData(1, { VIP = true }) == 1, "other passes don't change field data")

-- Jet Boots: 1.5x between zones only
for tier = 1, #Config.BOOTS do
	check(
		Formulas.walkSpeed(false, tier, { JetBoots = true }) == Config.WALK_SPEED_OUTSIDE * 1.5,
		`boot tier {tier}: Jet Boots are 50% faster between zones`
	)
	check(
		Formulas.walkSpeed(true, tier, { JetBoots = true }) == Formulas.walkSpeed(true, tier),
		`boot tier {tier}: Jet Boots don't change speed inside zones`
	)
	check(
		Formulas.walkSpeed(false, tier, none) == Config.WALK_SPEED_OUTSIDE,
		`boot tier {tier}: no pass walks at WALK_SPEED_OUTSIDE`
	)
end

-- Bolt Colours: eight named colours, bright enough to read in a storm
check(#Config.BOLT_COLOURS == 8, "eight bolt colours")
local names = {}
for index, def in Config.BOLT_COLOURS do
	check(typeof(def.name) == "string" and #def.name > 0, `colour {index} has a name`)
	check(not names[def.name], `{def.name} is listed once`)
	names[def.name] = true
	local c = def.color
	check(math.max(c.R, c.G, c.B) >= 0.9, `{def.name} is bright`)
	check(Passes.isValidColour(index), `{def.name} is a valid pick`)
end
check(Passes.isValidColour(0), "0 (the default) is a valid pick")
for _, bad in { -1, 9, 1.5, 0 / 0, math.huge, "1", nil } do
	check(not Passes.isValidColour(bad), `{tostring(bad)} is not a valid pick`)
end
-- a picked colour wins over VIP gold, VIP gold over the default
local pink = Config.BOLT_COLOURS[1].color
check(Passes.boltColour(none, 0) == nil, "no pass: default lightning")
check(Passes.boltColour(none, 1) == nil, "a saved pick without the pass shows the default")
check(Passes.boltColour({ VIP = true }, 0) == Config.VIP_GOLD, "VIP: gold lightning")
check(Passes.boltColour({ VIP = true }, 1) == Config.VIP_GOLD, "VIP without Bolt Colours: gold")
check(Passes.boltColour({ BoltColours = true }, 0) == nil, "Bolt Colours with no pick: default")
check(Passes.boltColour({ BoltColours = true }, 1) == pink, "Bolt Colours: the pick")
check(Passes.boltColour({ BoltColours = true, VIP = true }, 1) == pink, "a pick wins over VIP gold")
check(
	Passes.boltColour({ BoltColours = true, VIP = true }, 0) == Config.VIP_GOLD,
	"no pick: VIP gold"
)
check(Passes.boltColour({ BoltColours = true }, 99) == nil, "an out-of-range pick: default")

-- a sale broken down: 2x Volts' missed extra, and a 2x boost's extra
do
	local two = { DoubleVolts = 60 } -- a running 2x boost (the free trial is one)
	local earned, missed, boostExtra = Passes.saleBreakdown(100, none, {})
	check(earned == 100 and missed == 100 and boostExtra == 0, "no pass: 2x would have paid +100")
	earned, missed, boostExtra = Passes.saleBreakdown(100, none, two)
	check(earned == 200 and missed == 0 and boostExtra == 100, "a 2x boost pays 2x and says so")
	earned, missed, boostExtra = Passes.saleBreakdown(100, { DoubleVolts = true }, {})
	check(earned == 200 and missed == 0 and boostExtra == 0, "owners miss nothing")
	earned, missed, boostExtra = Passes.saleBreakdown(100, { DoubleVolts = true }, two)
	check(earned == 200 and boostExtra == 0, "a 2x boost adds nothing for owners")
	earned, missed, boostExtra = Passes.saleBreakdown(100, { VIP = true }, {})
	check(earned == 110 and missed == 110, "VIP: 2x would have paid +110")
	earned, missed, boostExtra = Passes.saleBreakdown(100, { VIP = true }, two)
	check(earned == 220 and boostExtra == 110, "VIP with a 2x boost: 2.2x")
	earned, missed, boostExtra = Passes.saleBreakdown(100, none, { Lucky = 60 })
	check(earned == 100 and missed == 100 and boostExtra == 0, "other boosts don't change sales")
end

-- every pass at once still works
check(near(Passes.sellMultiplier(all), 2.2), "all passes: 2.2x")
check(Passes.luckChance(all) == 0.15, "all passes: 15% luck")
check(Passes.setupTime(8, all) == 0, "all passes: instant set-up")

if failures > 0 then
	error(`{failures} pass checks failed`)
end
print("pass checks passed")
