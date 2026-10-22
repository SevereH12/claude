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
for _, key in { "DoubleVolts", "RemoteSell", "BigBottles", "LuckyCharges" } do
	check(keys[key], `{key} is in Config.PASSES`)
end

-- 2x Volts
check(Passes.sellMultiplier(none) == 1, "no pass: sales pay 1x")
check(Passes.sellMultiplier({ DoubleVolts = true }) == 2, "2x Volts pays 2x")
check(Passes.sellMultiplier({ BigBottles = true }) == 1, "other passes don't change sales")

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

-- every pass at once still works
check(Passes.sellMultiplier(all) == 2, "all passes: 2x")
check(Passes.luckChance(all) == 0.15, "all passes: 15% luck")

if failures > 0 then
	error(`{failures} pass checks failed`)
end
print("pass checks passed")
