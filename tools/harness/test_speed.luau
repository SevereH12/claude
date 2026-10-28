--!nocheck
-- Walk speed in storm zones (shared/Util/Speed): boots speed you up, each
-- zone's storm drag slows you down, so a typical player walks into every
-- zone at WALK_SPEED_IN_ZONE and buying boots there makes them faster.
-- Also prints the table (zone, typical boots, speed on arrival, speed with
-- the best boots).
--   lune run tools/harness/test_speed.luau
local World = require("./World")

local world = World.new("src")
local Config = world:require("ReplicatedStorage.Shared.Config")
local Formulas = world:require("ReplicatedStorage.Shared.Util.Formulas")
local Progression = world:require("ReplicatedStorage.Shared.Util.Progression")
local Speed = world:require("ReplicatedStorage.Shared.Util.Speed")

local failures = 0
local function check(condition, message)
	if not condition then
		failures += 1
		print("FAIL: " .. message)
	end
end

local BASE = Config.WALK_SPEED_IN_ZONE
local MIN, MAX = Config.ZONE_SPEED.min, Config.ZONE_SPEED.max
local BEST = #Config.BOOTS

-- the limits themselves ---------------------------------------------------------------
check(MIN <= BASE and BASE < MAX, "ZONE_SPEED.min <= WALK_SPEED_IN_ZONE < ZONE_SPEED.max")
check(MAX < Config.WALK_SPEED_OUTSIDE, "in-zone speed stays below the between-zones speed")

-- boots: free starters, then clearly faster every pair --------------------------------
check(Config.BOOTS[1].speedBonus == 0, "Rain Boots add nothing")
for tier = 2, BEST do
	local step = Config.BOOTS[tier].speedBonus - Config.BOOTS[tier - 1].speedBonus
	check(step >= 3, `{Config.BOOTS[tier].name}: at least +3 speed over the pair before`)
	check(
		Config.BOOTS[tier].price > Config.BOOTS[tier - 1].price,
		`{Config.BOOTS[tier].name} costs more than the pair before`
	)
end

-- typical boots: a hand-worked case and the general rules -----------------------------
-- Jar -> Vial (80) -> Flask (250): Puddle Jumpers (300) aren't the cheapest
-- goal until after the Flask, so a typical player opens Mesa in Rain Boots.
check(Speed.typicalBootTier(1) == 1, "a new player has Rain Boots")
check(Speed.typicalBootTier(3) == 1, "Flask before Puddle Jumpers")
-- by the Storm Cell (8,000) they've bought every pair cheaper than it
-- (300, 900, 2,000) but not Thunder Treads (10,000)
check(Speed.typicalBootTier(5) == 4, `Storm Cell -> Gale Striders (got {Speed.typicalBootTier(5)})`)
local last = 1
for bottle = 1, #Config.BOTTLES do
	local tier = Speed.typicalBootTier(bottle)
	check(tier >= last, `bottle {bottle}: typical boots never go down`)
	check(tier >= 1 and tier <= BEST, `bottle {bottle}: a real boot tier`)
	-- every pair they own cost less than the bottle bought after it
	for t = 2, tier do
		local bottleAfter = Config.BOTTLES[bottle + 1]
		check(
			bottleAfter == nil or Config.BOOTS[t].price < bottleAfter.price,
			`bottle {bottle}: {Config.BOOTS[t].name} was cheaper than the next bottle`
		)
	end
	-- and the next pair cost at least as much as the bottle they just bought
	local nextPair = Config.BOOTS[tier + 1]
	if bottle > 1 and nextPair then
		check(
			nextPair.price >= Config.BOTTLES[bottle].price,
			`bottle {bottle}: {nextPair.name} wasn't cheaper than the bottle`
		)
	end
	last = tier
end

-- speed maths ---------------------------------------------------------------------------
check(Speed.withDrag(1, 0) == BASE, "no boots, no drag: the base speed")
check(Speed.withDrag(2, 0) == BASE + Config.BOOTS[2].speedBonus, "boots add their bonus")
check(Speed.withDrag(2, Config.BOOTS[2].speedBonus) == BASE, "drag takes the same amount back")
check(Speed.withDrag(1, 1000) == MIN, "never below ZONE_SPEED.min")
check(Speed.withDrag(BEST, 0) == MAX, "never above ZONE_SPEED.max")
check(Speed.withDrag(99, 0) == MAX, "a bad tier clamps too")
for tier = 1, BEST do
	check(
		Formulas.walkSpeed(true, tier) == Speed.withDrag(tier, 0),
		`tier {tier}: Formulas.walkSpeed(true) is the no-drag speed`
	)
end

-- every zone ---------------------------------------------------------------------------
local zones = Formulas.sortedZones()
local lastDrag = {} -- world id -> drag of the previous zone in that world
print(
	string.format(
		"%-18s %-16s %5s %8s %10s %9s",
		"zone",
		"typical boots",
		"drag",
		"arrival",
		"best boots",
		"no boots"
	)
)
for _, zone in zones do
	local drag = Speed.drag(zone)
	local opens = math.max(zone.requiresBottle, Formulas.world(zone.world).requiresBottle)
	local typical = Speed.typicalBootTier(opens)
	local arrival = Speed.arrival(zone)
	local best = Speed.withDrag(BEST, drag)
	local none = Speed.withDrag(1, drag)
	print(
		string.format(
			"%-18s %-16s %5d %8d %10d %9d",
			zone.displayName,
			Formulas.boots(typical).name,
			drag,
			arrival,
			best,
			none
		)
	)
	check(drag >= 0, `{zone.id}: drag is never negative`)
	if not zone.premium then
		-- the whole point: everyone typical starts each zone at the same speed
		check(arrival == BASE, `{zone.id}: a typical player arrives at {BASE} (got {arrival})`)
		check(
			drag == Formulas.boots(typical).speedBonus,
			`{zone.id}: drag is the typical boots' bonus`
		)
		-- later zones in a world never drag less
		check(drag >= (lastDrag[zone.world] or 0), `{zone.id}: drag doesn't drop along its world`)
		lastDrag[zone.world] = drag
		-- buying more boots there helps (unless the typical player owns the best)
		if typical < BEST then
			check(
				Speed.withDrag(typical + 1, drag) > arrival,
				`{zone.id}: the next pair of boots makes you faster`
			)
		end
	end
	-- the player's own speed there is the same sum
	local progress = { bottleTier = #Config.BOTTLES, bootTier = 5 }
	if not zone.premium then
		check(
			Speed.inZone(progress, zone) == Speed.withDrag(5, drag),
			`{zone.id}: Speed.inZone uses the zone's drag`
		)
	end
end

-- a new zone gets a drag by itself: a made-up zone needing the Storm Core
local madeUp = table.clone(Config.ZONES.Shoreline)
madeUp.premium = nil
madeUp.requiresBottle = #Config.BOTTLES
check(
	Speed.drag(madeUp) == Formulas.boots(Speed.typicalBootTier(#Config.BOTTLES)).speedBonus,
	"a new zone's drag comes from its bottle"
)

-- Premium zones drag like the player's best zone ----------------------------------------
for _, zone in Config.ZONES do
	if zone.premium then
		for bottle = 1, #Config.BOTTLES do
			local progress = { bottleTier = bottle, bootTier = 1 }
			local best = Progression.bestZone(progress)
			check(
				Speed.drag(zone, progress) == Speed.drag(best),
				`{zone.id} with bottle {bottle}: drags like {best.id}`
			)
		end
		check(Speed.drag(zone) == 0, `{zone.id}: no drag without a player`)
	end
end

-- between zones: boots change nothing, Jet Boots still help -----------------------------
for tier = 1, BEST do
	local progress = { bottleTier = 9, bootTier = tier }
	check(
		Speed.walkSpeed(progress, nil, {}) == Config.WALK_SPEED_OUTSIDE,
		`tier {tier}: WALK_SPEED_OUTSIDE between zones`
	)
	check(
		Speed.walkSpeed(progress, nil, { JetBoots = true }) == Config.WALK_SPEED_OUTSIDE * 1.5,
		`tier {tier}: Jet Boots between zones`
	)
	for _, zone in Config.ZONES do
		local inside = Speed.walkSpeed(progress, zone, { JetBoots = true })
		check(
			inside == Speed.inZone(progress, zone),
			`tier {tier} {zone.id}: Jet Boots don't help inside`
		)
		check(
			inside < Config.WALK_SPEED_OUTSIDE,
			`tier {tier} {zone.id}: leaving a zone always speeds you up`
		)
		-- the movement checks allow for the fastest in-zone speed
		check(
			inside <= Formulas.walkSpeed(true, tier),
			`tier {tier} {zone.id}: within the anti-cheat's in-zone speed`
		)
	end
end

-- the banner line --------------------------------------------------------------------
check(
	Speed.dragText({ bottleTier = 1, bootTier = 1 }, Config.ZONES.Shoreline) == nil,
	"no drag, no line"
)
for _, zone in zones do
	local progress = { bottleTier = 9, bootTier = 1 }
	if Speed.drag(zone, progress) > 0 then
		local text = Speed.dragText(progress, zone)
		check(
			text ~= nil and string.find(text, tostring(Speed.drag(zone, progress)), 1, true) ~= nil,
			`{zone.id}: the banner says the drag`
		)
	end
end

if failures > 0 then
	error(`{failures} speed checks failed`)
end
print("speed checks passed")
