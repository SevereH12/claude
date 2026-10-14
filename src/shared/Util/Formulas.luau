--!strict
-- Pure game math used by both sides. The server's result is the one that
-- counts; the client uses it only to show prices and stats in the UI.

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)

-- Anything with the fields the formulas read (a Profile or a Snapshot).
type State = {
	rebirths: number,
	upgrades: { [string]: number },
}

local Formulas = {}

function Formulas.level(state: State, upgradeId: string): number
	return state.upgrades[upgradeId] or 0
end

function Formulas.multiplier(state: State): number
	local rebirthBonus = 1 + state.rebirths * Config.REBIRTH_MULTIPLIER
	local goldenBonus = 1 + Formulas.level(state, "GoldenHands") * Config.GOLDEN_HANDS_BONUS
	return rebirthBonus * goldenBonus
end

function Formulas.clickValue(state: State): number
	local base = Config.BASE_CLICK_VALUE + Formulas.level(state, "ClickPower")
	return math.max(1, math.floor(base * Formulas.multiplier(state)))
end

function Formulas.autoIncome(state: State): number
	local base = Formulas.level(state, "AutoClicker") * Config.AUTO_CLICKER_PER_LEVEL
	return math.floor(base * Formulas.multiplier(state))
end

function Formulas.upgradeCost(def: Types.UpgradeDef, currentLevel: number): number
	return math.floor(def.basePrice * def.priceGrowth ^ currentLevel)
end

function Formulas.rebirthCost(rebirths: number): number
	return math.floor(Config.REBIRTH_BASE_COST * Config.REBIRTH_COST_GROWTH ^ rebirths)
end

-- Upgrade definitions sorted for display.
function Formulas.sortedUpgrades(): { Types.UpgradeDef }
	local list: { Types.UpgradeDef } = {}
	for _, def in Config.UPGRADES do
		table.insert(list, def)
	end
	table.sort(list, function(a, b)
		return a.order < b.order
	end)
	return list
end

return Formulas
