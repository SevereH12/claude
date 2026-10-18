--!strict
-- Who may go where, and what to aim for next. This is the one place for
-- zone entry rules. Takes a server Profile or a client Snapshot: both carry
-- the tiers it reads. The server enforces it (Strikes, Movement, Research);
-- the client only uses it for barriers and the HUD.

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)
local Formulas = require(script.Parent.Formulas)

export type Progress = { bottleTier: number, bootTier: number }

export type GoalKind = "zone" | "bottle" | "boots"

export type Goal = {
	kind: GoalKind,
	title: string, -- "Vial", "Puddle Jumpers", "Mesa"
	detail: string, -- what it gives, or what it takes
	price: number, -- Volts still to spend to reach it
}

local Progression = {}

local function withArticle(name: string): string
	return if string.find(string.lower(name), "^[aeiou]") then `an {name}` else `a {name}`
end

-- What a zone asks for, e.g. "Needs a Flask", or nil if it's open to all.
function Progression.requirement(zone: Types.ZoneDef): string?
	if zone.requiresBottle > 1 then
		return `Needs {withArticle(Formulas.bottle(zone.requiresBottle).name)}`
	end
	return nil
end

function Progression.canEnter(progress: Progress, zone: Types.ZoneDef): boolean
	return progress.bottleTier >= zone.requiresBottle
end

-- Why a zone is locked for this player, or nil when they can go in.
function Progression.lockReason(progress: Progress, zone: Types.ZoneDef): string?
	if Progression.canEnter(progress, zone) then
		return nil
	end
	return Progression.requirement(zone)
end

-- Volts to buy every bottle after `current` up to and including `tier`.
local function bottleCost(current: number, tier: number): number
	local total = 0
	for t = current + 1, math.min(tier, #Config.BOTTLES) do
		total += Config.BOTTLES[t].price
	end
	return total
end

local KIND_ORDER: { [GoalKind]: number } = { zone = 1, bottle = 2, boots = 3 }

-- The next bottle, the next boots and the nearest locked zone, cheapest
-- first (a zone wins a tie: it's the bigger reward). Empty at the top.
function Progression.nextGoals(progress: Progress): { Goal }
	local goals: { Goal } = {}
	local bottle = Formulas.nextBottle(progress.bottleTier)
	if bottle then
		table.insert(goals, {
			kind = "bottle",
			title = bottle.name,
			detail = `Holds {bottle.capacity} charges`,
			price = bottle.price,
		})
	end
	local boots = Formulas.nextBoots(progress.bootTier)
	if boots then
		table.insert(goals, {
			kind = "boots",
			title = boots.name,
			detail = `+{boots.speedBonus} speed in storm zones`,
			price = boots.price,
		})
	end
	for _, zone in Formulas.sortedZones() do
		if not Progression.canEnter(progress, zone) then
			local needed = Formulas.bottle(zone.requiresBottle).name
			table.insert(goals, {
				kind = "zone",
				title = zone.displayName,
				detail = `Buy {withArticle(needed)} to enter`,
				price = bottleCost(progress.bottleTier, zone.requiresBottle),
			})
			break
		end
	end
	table.sort(goals, function(a, b)
		if a.price ~= b.price then
			return a.price < b.price
		end
		return KIND_ORDER[a.kind] < KIND_ORDER[b.kind]
	end)
	return goals
end

return Progression
