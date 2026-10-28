--!strict
-- Pure game math used by both sides. The server's result is the one that
-- counts; the client uses it only for the UI.

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)
local PassRules = require(script.Parent.Passes)

local Formulas = {}

function Formulas.bottle(tier: number): Types.BottleDef
	local index = math.clamp(tier, 1, #Config.BOTTLES)
	return Config.BOTTLES[index]
end

-- The next bottle to buy, or nil when the best one is owned.
function Formulas.nextBottle(tier: number): Types.BottleDef?
	return Config.BOTTLES[tier + 1]
end

function Formulas.capacity(tier: number): number
	return Formulas.bottle(tier).capacity
end

-- A strike that fills `size` units and is worth `value`, caught into a
-- bottle (or tank) with `room` units free: the units that fit and the Volts
-- they pay. All of it when it fits; otherwise the room left and that
-- fraction of the value, rounded down but at least 1.
function Formulas.fill(size: number, value: number, room: number): (number, number)
	local units = math.min(size, math.max(room, 0))
	if units <= 0 then
		return 0, 0
	elseif units >= size then
		return size, value
	end
	return units, math.max(1, math.floor(value * units / size))
end

-- `capacity`: the player's own (Systems/Passes.capacity: Big Bottles included).
function Formulas.isFull(chargeCount: number, capacity: number): boolean
	return chargeCount >= capacity
end

function Formulas.boots(tier: number): Types.BootsDef
	local index = math.clamp(tier, 1, #Config.BOOTS)
	return Config.BOOTS[index]
end

-- The next boots to buy, or nil when the best pair is owned.
function Formulas.nextBoots(tier: number): Types.BootsDef?
	return Config.BOOTS[tier + 1]
end

-- Boots only help inside storm zones; between zones everyone walks at
-- WALK_SPEED_OUTSIDE (50% faster with the Jet Boots pass, in `owned`, the
-- player's Game Pass keys). Inside zones this is the fastest these boots
-- go anywhere (a zone with no storm drag, capped at ZONE_SPEED.max); the
-- speed in a given zone is Util/Speed.inZone.
function Formulas.walkSpeed(inZone: boolean, bootTier: number, owned: PassRules.Owned?): number
	if not inZone then
		return PassRules.outsideSpeed(Config.WALK_SPEED_OUTSIDE, owned or {})
	end
	local speed = Config.WALK_SPEED_IN_ZONE + Formulas.boots(bootTier).speedBonus
	return math.min(speed, Config.ZONE_SPEED.max)
end

-- The world with this id (the first world for an unknown id).
function Formulas.world(id: string): Types.WorldDef
	for _, world in Config.WORLDS do
		if world.id == id then
			return world
		end
	end
	return Config.WORLDS[1]
end

-- Position of a world in travel order (1 = the first world).
function Formulas.worldIndex(id: string): number
	for index, world in Config.WORLDS do
		if world.id == id then
			return index
		end
	end
	return 1
end

-- Every zone, in travel order: by world, then along each world's spiral.
function Formulas.sortedZones(): { Types.ZoneDef }
	local list: { Types.ZoneDef } = {}
	for _, def in Config.ZONES do
		table.insert(list, def)
	end
	table.sort(list, function(a, b)
		local wa, wb = Formulas.worldIndex(a.world), Formulas.worldIndex(b.world)
		if wa ~= wb then
			return wa < wb
		end
		return a.order < b.order
	end)
	return list
end

-- One world's zones along its spiral.
function Formulas.worldZones(worldId: string): { Types.ZoneDef }
	local list: { Types.ZoneDef } = {}
	for _, def in Formulas.sortedZones() do
		if def.world == worldId then
			table.insert(list, def)
		end
	end
	return list
end

return Formulas
