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
