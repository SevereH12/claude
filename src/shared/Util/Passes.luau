--!strict
-- What each Game Pass does, as pure maths (Systems/Passes decides who owns
-- what; tools/harness/test_passes.luau tests this). `owned` is a set of
-- pass keys (Config.PASSES), e.g. { DoubleVolts = true }.

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)
local Boosts = require(script.Parent.Boosts)

export type Owned = { [string]: boolean }

local VALUES = Config.PASS_VALUES

local Passes = {}

-- Player attributes everyone can read: ATTRIBUTE .. key is true while the
-- player owns that pass (Systems/Passes); BOLT_ATTRIBUTE is their Bolt
-- Colours pick (Systems/PassPerks).
Passes.ATTRIBUTE = "Pass_"
Passes.BOLT_ATTRIBUTE = "BoltColour"

-- A member of the game's group (Config.GROUP_ID, Systems/Group): the
-- player attribute everyone can read, and the key that marks one in an
-- `owned` set, so the group bonus multiplies like a pass.
Passes.GROUP = "GroupMember"

-- A Server Storm is on in the player's server (Systems/Boosts): the key
-- that marks it in an `owned` set, so it multiplies sales like a pass.
Passes.SERVER_STORM = "ServerStorm"

-- A Server Surge is on (the server goal was filled: Systems/ServerGoal).
-- It stacks with a Server Storm (both on: 2 x 2 = 4x).
Passes.SERVER_SURGE = "ServerSurge"

-- A scheduled event is on (Config.EVENTS, Util/Weather): EVENT .. its name
-- marks it in an `owned` set, so it multiplies sales like a pass.
Passes.EVENT = "Event_"

-- A finished Storm Log page (Util/StormLog): LOG_PAGE .. its id marks it in
-- an `owned` set, so each one adds Config.STORM_LOG.pageBonus to sales.
Passes.LOG_PAGE = "LogPage_"

-- The pass with this key, or nil.
function Passes.def(key: string): Types.PassDef?
	for _, pass in Config.PASSES do
		if pass.key == key then
			return pass
		end
	end
	return nil
end

-- The Storm Log's extra (0.02 per finished page in `owned`, up to
-- Config.STORM_LOG.maxBonus): added up, then it multiplies like a pass.
function Passes.logBonus(owned: Owned): number
	local log = Config.STORM_LOG
	local pages = 0
	for _, page in log.pages do
		if owned[Passes.LOG_PAGE .. page.id] then
			pages += 1
		end
	end
	return math.min(pages * log.pageBonus, log.maxBonus)
end

-- What a sale pays, times this: 2x Volts (pass or boost), VIP, the group
-- bonus, a Server Storm, a Server Surge and any scheduled event multiply
-- (2 x 1.1 x 1.1 x 2 = 4.84, x2 more on a Double Volts Weekend), and the
-- Storm Log's finished pages add up to +8% on top.
function Passes.sellMultiplier(owned: Owned): number
	local multiplier = 1
	if owned.DoubleVolts then
		multiplier *= VALUES.doubleVolts
	end
	if owned.VIP then
		multiplier *= VALUES.vipVolts
	end
	if owned[Passes.GROUP] then
		multiplier *= 1 + Config.GROUP_BONUS
	end
	if owned[Passes.SERVER_STORM] then
		multiplier *= Config.SERVER_STORM.multiplier
	end
	if owned[Passes.SERVER_SURGE] then
		multiplier *= Config.SERVER_GOAL.multiplier
	end
	for _, event in Config.EVENTS do
		if owned[Passes.EVENT .. event.name] then
			multiplier *= event.multiplier
		end
	end
	multiplier *= 1 + Passes.logBonus(owned)
	return multiplier
end

-- The Volts a bottle worth `value` sells for, rounded down. (The tiny
-- nudge keeps 10 x 1.1 at 11 when floating point lands just under.)
function Passes.sale(value: number, owned: Owned): number
	return math.floor(value * Passes.sellMultiplier(owned) + 1e-6)
end

-- The passes a player owns plus the effects of their running boosts
-- (Util/Boosts: seconds left per boost key). Everything that applies a
-- pass effect takes this, so a boost works everywhere its pass does.
function Passes.withBoosts(owned: Owned, boosts: Boosts.Left): Owned
	local set = table.clone(owned)
	for pass in Boosts.effects(boosts) do
		set[pass] = true
	end
	return set
end

-- A sale broken down: what it pays (passes and running boosts), the extra
-- 2x Volts would have paid (with neither the pass nor a 2x boost), and the
-- extra a 2x boost paid (the free trial is one).
function Passes.saleBreakdown(
	value: number,
	owned: Owned,
	boosts: Boosts.Left
): (number, number, number)
	local effects = Passes.withBoosts(owned, boosts)
	local earned = Passes.sale(value, effects)
	if owned.DoubleVolts then
		return earned, 0, 0
	end
	if effects.DoubleVolts then
		local without = table.clone(effects)
		without.DoubleVolts = nil
		return earned, 0, earned - Passes.sale(value, without)
	end
	local with = table.clone(effects)
	with.DoubleVolts = true
	return earned, Passes.sale(value, with) - earned, 0
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

-- Seconds a newly posted researcher needs to set up: none with Lab Grant.
function Passes.setupTime(baseSeconds: number, owned: Owned): number
	return if owned.LabGrant then 0 else baseSeconds
end

-- Field data a researcher gains: double with Lab Grant.
function Passes.fieldData(baseData: number, owned: Owned): number
	return if owned.LabGrant then baseData * VALUES.labGrantData else baseData
end

-- Walk speed between storm zones: 50% faster with Jet Boots. (Speed inside
-- zones never changes: Formulas.walkSpeed.)
function Passes.outsideSpeed(baseSpeed: number, owned: Owned): number
	return if owned.JetBoots then baseSpeed * VALUES.jetBoots else baseSpeed
end

-- Is this a Bolt Colours pick a client may ask for? 0 (the default) or an
-- index into Config.BOLT_COLOURS.
function Passes.isValidColour(index: unknown): boolean
	return typeof(index) == "number"
		and index == math.floor(index)
		and index >= 0
		and index <= #Config.BOLT_COLOURS
end

-- The colour of a player's lightning arcs and bottle charge, or nil for the
-- default: a picked colour (Bolt Colours) wins over VIP gold, and VIP gold
-- wins over the default. `choice` is their saved pick (0 = none).
function Passes.boltColour(owned: Owned, choice: number?): Color3?
	if owned.BoltColours and choice and choice >= 1 and Passes.isValidColour(choice) then
		return Config.BOLT_COLOURS[choice].color
	end
	if owned.VIP then
		return Config.VIP_GOLD
	end
	return nil
end

return Passes
