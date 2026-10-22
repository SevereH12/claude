--!strict
-- What each Game Pass does, as pure maths (Systems/Passes decides who owns
-- what; tools/harness/test_passes.luau tests this). `owned` is a set of
-- pass keys (Config.PASSES), e.g. { DoubleVolts = true }.

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)

export type Owned = { [string]: boolean }

local VALUES = Config.PASS_VALUES

local Passes = {}

-- The pass with this key, or nil.
function Passes.def(key: string): Types.PassDef?
	for _, pass in Config.PASSES do
		if pass.key == key then
			return pass
		end
	end
	return nil
end

-- What a sale pays, times this.
function Passes.sellMultiplier(owned: Owned): number
	return if owned.DoubleVolts then VALUES.doubleVolts else 1
end

-- A bottle's capacity for this player: Big Bottles holds 50% more,
-- rounded down.
function Passes.capacity(baseCapacity: number, owned: Owned): number
	if owned.BigBottles then
		return math.floor(baseCapacity * VALUES.bigBottles)
	end
	return baseCapacity
end

-- The chance a caught charge is worth double (Lucky Charges).
function Passes.luckChance(owned: Owned): number
	return if owned.LuckyCharges then VALUES.luckyChance else 0
end

return Passes
