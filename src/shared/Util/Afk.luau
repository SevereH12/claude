--!strict
-- The AFK Lounge's pay rate (Systems/Afk pays it, the AFK screen shows the
-- breakdown; tools/harness/test_afk.luau tests it): Config.AFK.rateFraction
-- of what the player would earn grinding in their best zone (or
-- premiumRateFraction for Roblox Premium members).
--
-- `effects` is the sale's own set (Systems/Passes.saleEffects): owned passes
-- plus running boosts, the group bonus and a running Server Storm, so
-- everything that multiplies a real sale multiplies this too.
--
-- How the grinding rate is worked out, and what it assumes:
-- * The player grinds their best zone (Progression.bestZone: the highest
--   chargeValue their bottle opens, never the Premium zone).
-- * "Closest catcher wins" zones count as if the player were alone there.
-- * A strike is reachable when its ring lands within STRIKE_RADIUS plus how
--   far they can run in WARNING_TIME (their speed in that zone, Util/Speed:
--   boots and the zone's storm drag count, Jet Boots don't, they only help
--   outside zones). Strike centres are picked from
--   the zone inset by STRIKE_RADIUS + 2 (Systems/Strikes), so the chance is
--   that circle's area over that rectangle's, at most 1.
-- * Strikes only fall during storms, so the time to fill a bottle stretches
--   by (storm + calm) / storm.
-- * Walking to sell isn't counted, and researcher perks are left out.
-- * Lucky Charges adds its expected extra (15% of charges worth double).

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)
local Formulas = require(script.Parent.Formulas)
local Passes = require(script.Parent.Passes)
local Progression = require(script.Parent.Progression)
local Speed = require(script.Parent.Speed)

export type Multiplier = { label: string, value: number }

export type Breakdown = {
	zone: Types.ZoneDef?,
	bottle: string,
	baseCapacity: number,
	capacity: number, -- Big Bottles included
	chargeSize: number,
	strikes: number, -- strikes to fill the bottle
	reach: number, -- studs a warning ring can be away and still be caught
	chance: number, -- of a strike being reachable
	fillSeconds: number,
	bag: number, -- Volts one full bottle sells for (luck included)
	multipliers: { Multiplier }, -- what multiplied the sale
	luck: number, -- Lucky Charges' expected extra (0.15) or 0
	bigBottles: boolean,
	grindPerSecond: number,
	fraction: number, -- of the grinding rate the lounge pays
	premium: boolean,
	perSecond: number,
	perHour: number,
}

local Afk = {}

Afk.TAG = "AfkZone" -- the invisible box over the lounge (Kit.afkZone)

-- The sale multipliers in `effects`, each with its value (Passes.sellMultiplier
-- is their product).
local function multipliers(effects: Passes.Owned): { Multiplier }
	local list: { Multiplier } = {}
	if effects.DoubleVolts then
		table.insert(list, { label = "2x Volts", value = Config.PASS_VALUES.doubleVolts })
	end
	if effects.VIP then
		table.insert(list, { label = "VIP", value = Config.PASS_VALUES.vipVolts })
	end
	if effects[Passes.GROUP] then
		table.insert(list, { label = "Group", value = 1 + Config.GROUP_BONUS })
	end
	if effects[Passes.SERVER_STORM] then
		table.insert(list, { label = "Server Storm", value = Config.SERVER_STORM.multiplier })
	end
	if effects[Passes.SERVER_SURGE] then
		table.insert(list, { label = "Server Surge", value = Config.SERVER_GOAL.multiplier })
	end
	for _, event in Config.EVENTS do
		if effects[Passes.EVENT .. event.name] then
			table.insert(list, { label = event.name, value = event.multiplier })
		end
	end
	local logBonus = Passes.logBonus(effects)
	if logBonus > 0 then
		table.insert(list, { label = "Storm Log", value = 1 + logBonus })
	end
	local friends = Passes.friendsBonus(effects)
	if friends > 0 then
		table.insert(list, { label = "Friends", value = 1 + friends })
	end
	local ascension = Passes.ascensionBonus(effects)
	if ascension > 0 then
		table.insert(list, { label = "Ascension", value = 1 + ascension })
	end
	return list
end

-- Volts per second in the lounge, and how it was worked out.
function Afk.rate(
	progress: Progression.Progress,
	effects: Passes.Owned,
	premium: boolean
): (number, Breakdown)
	local zone = Progression.bestZone(progress)
	local baseCapacity = Formulas.capacity(progress.bottleTier)
	local capacity = Passes.capacity(baseCapacity, effects)
	local fraction = if premium then Config.AFK.premiumRateFraction else Config.AFK.rateFraction
	local breakdown: Breakdown = {
		zone = zone,
		bottle = Formulas.bottle(progress.bottleTier).name,
		baseCapacity = baseCapacity,
		capacity = capacity,
		chargeSize = 1,
		strikes = 0,
		reach = 0,
		chance = 0,
		fillSeconds = 0,
		bag = 0,
		multipliers = multipliers(effects),
		luck = Passes.luckChance(effects),
		bigBottles = capacity ~= baseCapacity,
		grindPerSecond = 0,
		fraction = fraction,
		premium = premium,
		perSecond = 0,
		perHour = 0,
	}
	if not zone then
		return 0, breakdown
	end
	local size = Progression.chargeSize(progress, zone)
	local strikes = math.ceil(capacity / size)
	local bag = capacity
		/ size
		* Progression.boltValue(progress, zone)
		* Passes.sellMultiplier(effects)
		* (1 + breakdown.luck)
	local speed = Speed.inZone(progress, zone)
	local reach = Config.STRIKE_RADIUS + speed * Config.WARNING_TIME
	local inset = 2 * (Config.STRIKE_RADIUS + 2)
	local area = math.max(zone.width - inset, 1) * math.max(zone.depth - inset, 1)
	local chance = math.min(1, math.pi * reach * reach / area)
	local stormShare = Config.STORM_DURATION / (Config.STORM_DURATION + Config.CALM_DURATION)
	local fill = strikes * zone.strikeInterval / chance / stormShare
	local grind = bag / fill
	breakdown.chargeSize = size
	breakdown.strikes = strikes
	breakdown.reach = reach
	breakdown.chance = chance
	breakdown.fillSeconds = fill
	breakdown.bag = bag
	breakdown.grindPerSecond = grind
	breakdown.perSecond = grind * fraction
	breakdown.perHour = grind * fraction * 3600
	return breakdown.perSecond, breakdown
end

return Afk
