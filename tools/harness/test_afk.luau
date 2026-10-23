--!nocheck
-- The AFK Lounge's rate (shared/Util/Afk): the expected Volts per hour for
-- each stage (docs/prompts/12-afk-zone.md, recomputed for the current
-- Config: with the Dynamo Drum the best zone is now Rune Spire, not
-- Thunderhead Mesa), the reach chance cap, the best zone, Big Bottles,
-- an expiring boost and the Premium rate.
--   lune run tools/harness/test_afk.luau
local World = require("./World")

local world = World.new("src")
local Config = world:require("ReplicatedStorage.Shared.Config")
local Afk = world:require("ReplicatedStorage.Shared.Util.Afk")
local Passes = world:require("ReplicatedStorage.Shared.Util.Passes")

local failures = 0
local function check(condition, message)
	if not condition then
		failures += 1
		print("FAIL: " .. message)
	end
end
local function near(a, b)
	return math.abs(a - b) <= math.abs(b) * 0.01
end

local ALL = { DoubleVolts = true, VIP = true, LuckyCharges = true, BigBottles = true }
local function with(base, extra)
	local set = table.clone(base)
	for k, v in extra do
		set[k] = v
	end
	return set
end
local SETS = {
	{ name = "no passes", effects = {} },
	{ name = "2x Volts", effects = { DoubleVolts = true } },
	{ name = "all passes", effects = ALL },
	{ name = "all + group", effects = with(ALL, { [Passes.GROUP] = true }) },
	{
		name = "+ Server Storm",
		effects = with(ALL, { [Passes.GROUP] = true, [Passes.SERVER_STORM] = true }),
	},
}
-- best zone, boots tier (speed bonus), bottle tier, then Volts per hour per set
local ROWS = {
	{ "Shoreline", 1, 1, { 575, 1149, 1454, 1600, 3199 } }, -- +0 boots, Jar
	{ "Mesa", 3, 3, { 3017, 6035, 8143, 8957, 17914 } }, -- +3, Flask
	{ "Yard", 4, 5, { 10830, 21660, 27948, 30743, 61485 } }, -- +4, Storm Cell
	{ "Spire", 6, 7, { 271380, 542761, 691496, 760646, 1521292 } }, -- +7, Dynamo Drum
	{ "Ember", 9, 9, { 2447204, 4894408, 6191426, 6810568, 13621137 } }, -- +10, Storm Core
}

-- the table, and Premium paying exactly 1.5x -----------------------------------------
for _, row in ROWS do
	local zone, boots, bottle, expected = row[1], row[2], row[3], row[4]
	local progress = { bottleTier = bottle, bootTier = boots }
	for i, set in SETS do
		local perSecond, breakdown = Afk.rate(progress, set.effects, false)
		local premium = Afk.rate(progress, set.effects, true)
		check(
			breakdown.zone and breakdown.zone.id == zone,
			`{zone}: best zone (got {breakdown.zone and breakdown.zone.id})`
		)
		check(
			near(perSecond * 3600, expected[i]),
			`{zone} {set.name}: {math.round(perSecond * 3600)} Volts/h, expected {expected[i]}`
		)
		check(
			math.abs(premium - perSecond * 1.5) < 1e-9 * math.max(1, premium),
			`{zone} {set.name}: Premium pays 1.5x`
		)
	end
end
check(
	Config.AFK.rateFraction == 0.10 and Config.AFK.premiumRateFraction == 0.15,
	"10% normally, 15% for Premium"
)

-- the reach chance is capped at 1 ----------------------------------------------------
local _, ember = Afk.rate({ bottleTier = 9, bootTier = 9 }, {}, false)
check(ember.chance == 1, `a fast player in Ember Mesa reaches every strike (chance {ember.chance})`)
local _, shore = Afk.rate({ bottleTier = 1, bootTier = 1 }, {}, false)
check(
	shore.chance > 0 and shore.chance < 1,
	`a new player in Shoreline doesn't (chance {shore.chance})`
)

-- the best zone: the highest value the bottle opens, never the Premium zone -----------
for tier = 1, #Config.BOTTLES do
	local _, b = Afk.rate({ bottleTier = tier, bootTier = 1 }, {}, false)
	check(b.zone ~= nil and not b.zone.premium, `bottle {tier}: a best zone, not the Premium one`)
	for _, zone in Config.ZONES do
		if not zone.premium and zone.requiresBottle <= tier then
			check(
				b.zone.chargeValue >= zone.chargeValue,
				`bottle {tier}: {b.zone.id} beats {zone.id}`
			)
		end
	end
end

-- Big Bottles only changes the strike count's rounding --------------------------------
local shoreBase = Afk.rate({ bottleTier = 1, bootTier = 1 }, {}, false)
local shoreBig = Afk.rate({ bottleTier = 1, bootTier = 1 }, { BigBottles = true }, false)
check(math.abs(shoreBig - shoreBase) < 1e-9, "Big Bottles in a 1-unit zone changes nothing")
local mesaBase, mb = Afk.rate({ bottleTier = 3, bootTier = 3 }, {}, false)
local mesaBig, mbb = Afk.rate({ bottleTier = 3, bootTier = 3 }, { BigBottles = true }, false)
check(
	mbb.capacity == math.floor(mb.capacity * 1.5) and mbb.bigBottles,
	"Big Bottles holds 50% more"
)
local ratio = (mbb.capacity / mbb.strikes) / (mb.capacity / mb.strikes)
check(
	math.abs(mesaBig / mesaBase - ratio) < 1e-9,
	"Big Bottles moves the rate only by capacity / strikes"
)

-- an expiring boost lowers the rate --------------------------------------------------
local progress = { bottleTier = 5, bootTier = 4 }
local boosted = Afk.rate(progress, Passes.withBoosts({}, { DoubleVolts = 30 }), false)
local expired = Afk.rate(progress, Passes.withBoosts({}, {}), false)
check(near(boosted, expired * 2), "a running 2x Volts boost doubles the rate")
check(expired < boosted, "when it runs out the rate drops")

-- the breakdown lists what multiplied ------------------------------------------------
local _, full = Afk.rate(progress, SETS[5].effects, false)
local labels = {}
for _, m in full.multipliers do
	labels[m.label] = m.value
end
check(
	labels["2x Volts"] == 2
		and labels.VIP == 1.1
		and labels.Group == 1.1
		and labels["Server Storm"] == 2,
	"every multiplier with its value"
)
check(full.luck == 0.15 and full.bigBottles, "Lucky and Big Bottles in the breakdown")

if failures > 0 then
	error(`{failures} AFK checks failed`)
end
print("afk checks passed")
