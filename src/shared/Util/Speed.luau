--!strict
-- Walk speed inside storm zones: boots speed you up, each zone's storm
-- slows you down. Pure rules, used by both sides: Systems/Movement sets the
-- speed, Util/Afk counts it, the zone banner and the shop show it.
-- tools/harness/test_speed.luau tests it; tools/balance/prestige.py reads it.
--
-- How it works:
-- * Boots add their speedBonus (Config.BOOTS) inside storm zones.
-- * Every zone has a "storm drag" that takes speed away. Nobody types the
--   drag in: it's worked out here from Config, so a new zone gets one by
--   itself. It's the speedBonus of the boots a typical player owns when
--   that zone opens (Speed.typicalBootTier). So a typical player walks into
--   every zone at about Config.WALK_SPEED_IN_ZONE, and each pair of boots
--   they buy while they're there makes them faster again.
-- * A "typical player" buys whatever the HUD's goal list shows first: the
--   cheaper of the next bottle and the next boots (the bottle when they
--   cost the same), starting from a Jar and Rain Boots. Their boots on the
--   day they buy the bottle a zone needs are that zone's typical boots.
-- * A Premium zone (open to members from the start) drags like the
--   player's best zone, as it pays like their best zone too.
-- * The speed stays between Config.ZONE_SPEED.min and .max. The max is
--   below WALK_SPEED_OUTSIDE, so the walk between zones is always faster
--   (boots never change that speed; Jet Boots make it faster still).

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)
local Formulas = require(script.Parent.Formulas)
local PassRules = require(script.Parent.Passes)
local Progression = require(script.Parent.Progression)

local Speed = {}

-- The boot tier a typical player owns when they buy bottle `bottleTier`
-- (see the top of this file).
function Speed.typicalBootTier(bottleTier: number): number
	local bottle, boots = 1, 1
	local target = math.clamp(bottleTier, 1, #Config.BOTTLES)
	while bottle < target do
		local nextBottle = Config.BOTTLES[bottle + 1]
		local nextBoots = Config.BOOTS[boots + 1]
		if nextBoots and nextBoots.price < nextBottle.price then
			boots += 1
		else
			bottle += 1
		end
	end
	return boots
end

-- The bottle that opens a zone: its own rule, or its world's if that's
-- bigger (you have to get to the world first).
local function opensWith(zone: Types.ZoneDef): number
	return math.max(zone.requiresBottle, Formulas.world(zone.world).requiresBottle)
end

-- How much speed this zone's storm takes away. `progress` is only needed
-- for a Premium zone (it drags like the player's best zone; nothing
-- without a progress).
function Speed.drag(zone: Types.ZoneDef, progress: Progression.Progress?): number
	if zone.premium then
		local best = progress and Progression.bestZone(progress)
		return if best and not best.premium then Speed.drag(best) else 0
	end
	return Formulas.boots(Speed.typicalBootTier(opensWith(zone))).speedBonus
end

-- In-zone walk speed with these boots against this much drag.
function Speed.withDrag(bootTier: number, drag: number): number
	local raw = Config.WALK_SPEED_IN_ZONE + Formulas.boots(bootTier).speedBonus - drag
	return math.clamp(raw, Config.ZONE_SPEED.min, Config.ZONE_SPEED.max)
end

-- The player's walk speed inside this zone.
function Speed.inZone(progress: Progression.Progress, zone: Types.ZoneDef): number
	return Speed.withDrag(progress.bootTier, Speed.drag(zone, progress))
end

-- What a typical player walks at on the day this zone opens (about
-- WALK_SPEED_IN_ZONE in every zone: that's the point of the drag).
function Speed.arrival(zone: Types.ZoneDef): number
	return Speed.withDrag(Speed.typicalBootTier(opensWith(zone)), Speed.drag(zone))
end

-- The player's walk speed: inside `zone`, or between zones when it's nil
-- (`owned`: their Game Pass keys, for Jet Boots).
function Speed.walkSpeed(
	progress: Progression.Progress,
	zone: Types.ZoneDef?,
	owned: PassRules.Owned?
): number
	if zone then
		return Speed.inZone(progress, zone)
	end
	return Formulas.walkSpeed(false, progress.bootTier, owned)
end

-- The note shown on entering a zone: "Storm drag -12 speed: you run 20
-- here", or nil when this zone's storm doesn't slow anyone down.
function Speed.dragText(progress: Progression.Progress, zone: Types.ZoneDef): string?
	local drag = Speed.drag(zone, progress)
	if drag <= 0 then
		return nil
	end
	return `Storm drag -{drag} speed: you run {Speed.inZone(progress, zone)} here`
end

return Speed
