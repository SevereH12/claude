--!strict
-- Pure game math used by both sides. The server's result is the one that
-- counts; the client uses it only for the UI.

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)

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

function Formulas.isFull(state: { bottleTier: number, chargeCount: number }): boolean
	return state.chargeCount >= Formulas.capacity(state.bottleTier)
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
-- WALK_SPEED_OUTSIDE.
function Formulas.walkSpeed(inZone: boolean, bootTier: number): number
	if not inZone then
		return Config.WALK_SPEED_OUTSIDE
	end
	return Config.WALK_SPEED_IN_ZONE + Formulas.boots(bootTier).speedBonus
end

-- Zone definitions sorted for display.
function Formulas.sortedZones(): { Types.ZoneDef }
	local list: { Types.ZoneDef } = {}
	for _, def in Config.ZONES do
		table.insert(list, def)
	end
	table.sort(list, function(a, b)
		return a.order < b.order
	end)
	return list
end

return Formulas
