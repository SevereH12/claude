--!strict
-- Timed boosts as pure maths (Systems/Boosts keeps them per player;
-- tools/harness/test_rewards.luau tests this). `boosts` is a profile's
-- seconds left per boost key (Config.BOOSTS), e.g. { DoubleVolts = 540 }.

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)

export type Left = { [string]: number }

local Boosts = {}

-- The boost with this key, or nil.
function Boosts.def(key: string): Types.BoostDef?
	for _, boost in Config.BOOSTS do
		if boost.key == key then
			return boost
		end
	end
	return nil
end

-- Adds `seconds` to a boost: time stacks, up to Config.BOOST_CAP.
function Boosts.grant(boosts: Left, key: string, seconds: number)
	boosts[key] = math.min((boosts[key] or 0) + seconds, Config.BOOST_CAP)
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
