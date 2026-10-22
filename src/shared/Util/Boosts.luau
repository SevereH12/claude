--!strict
-- Timed boosts as pure maths (Systems/Boosts keeps them per player;
-- tools/harness/test_rewards.luau and test_gifts.luau test this). `boosts`
-- is a profile's seconds left per boost key (Config.BOOSTS), e.g.
-- { DoubleVolts = 540 }. Also the boosts you can buy (Config.BOOST_PRODUCTS)
-- and the Server Storm's timer (Config.SERVER_STORM).

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)

export type Left = { [string]: number }

local STORM = Config.SERVER_STORM

local Boosts = {}

-- Workspace attributes everyone can read while a Server Storm is on
-- (Systems/Boosts): the server time it ends, and its latest buyer's
-- display name.
Boosts.STORM_ENDS = "ServerStormEnds"
Boosts.STORM_BY = "ServerStormBy"

-- The boost with this key, or nil.
function Boosts.def(key: string): Types.BoostDef?
	for _, boost in Config.BOOSTS do
		if boost.key == key then
			return boost
		end
	end
	return nil
end

-- Adds `seconds` to a boost. Reward time stacks up to Config.BOOST_CAP
-- (and never takes away time already there); bought or gifted time
-- (`paid`) always adds in full.
function Boosts.grant(boosts: Left, key: string, seconds: number, paid: boolean?)
	local left = boosts[key] or 0
	boosts[key] = if paid
		then left + seconds
		else math.max(left, math.min(left + seconds, Config.BOOST_CAP))
end

-- The boost you can buy with this key (Config.BOOST_PRODUCTS), or nil.
function Boosts.product(key: string): Types.BoostProductDef?
	for _, product in Config.BOOST_PRODUCTS do
		if product.key == key then
			return product
		end
	end
	return nil
end

-- The boost you can buy with this Developer Product id, or nil.
function Boosts.productById(productId: number): Types.BoostProductDef?
	for _, product in Config.BOOST_PRODUCTS do
		if product.productId ~= 0 and product.productId == productId then
			return product
		end
	end
	return nil
end

-- Adds what a bought or gifted boost product gives (in full).
function Boosts.grantProduct(boosts: Left, product: Types.BoostProductDef)
	for _, boost in product.boosts or {} do
		Boosts.grant(boosts, boost.key, boost.minutes * 60, true)
	end
end

-- A Server Storm's seconds left after one more purchase: `left` (its
-- seconds left now, 0 when none is on) plus SERVER_STORM.minutes, up to
-- SERVER_STORM.maxMinutes.
function Boosts.stormAdd(left: number): number
	return math.min(math.max(left, 0) + STORM.minutes * 60, STORM.maxMinutes * 60)
end

-- Does one more purchase add its full time to a storm with `left` seconds?
function Boosts.stormHasRoom(left: number): boolean
	return math.max(left, 0) + STORM.minutes * 60 <= STORM.maxMinutes * 60
end

-- A Server Storm's seconds left, from its STORM_ENDS attribute (`ends`,
-- maybe unset) at server time `now`.
function Boosts.stormLeft(ends: unknown, now: number): number
	return if typeof(ends) == "number" then math.max(ends - now, 0) else 0
end

-- Counts every boost down by `dt` seconds. Returns the keys that ran out
-- (and are gone).
function Boosts.tick(boosts: Left, dt: number): { string }
	local ended: { string } = {}
	for key, left in boosts do
		if left - dt <= 0 then
			boosts[key] = nil
			table.insert(ended, key)
		else
			boosts[key] = left - dt
		end
	end
	return ended
end

-- The pass effects the running boosts give, as pass keys: { DoubleVolts = true }.
function Boosts.effects(boosts: Left): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for key, left in boosts do
		local def = Boosts.def(key)
		if def and left > 0 then
			set[def.pass] = true
		end
	end
	return set
end

return Boosts
