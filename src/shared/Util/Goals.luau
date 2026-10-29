--!strict
-- The goal card's goals (the HUD's top right card). Pure: no instances, no
-- state, so tools/harness/test_goals.luau can test it.
--
-- Goals.list gives every goal the player could work on now:
--   - what Progression.nextGoals gives (the next bottle, boots, zone or world)
--   - hire: the next researcher not hired yet (they're hired in
--     Config.RESEARCHERS order), for their price in Volts
--   - promote: the researcher at the top level closest to their next rank,
--     Glints toward that rank's cost (Research.glintsFor)
--   - ascend: once they own the top bottle, Volts toward the next Ascension
-- Goals.pick gives the one closest to done, so the card always has a goal
-- (ascend is always there at the top).

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)
local Ascension = require(script.Parent.Ascension)
local Progression = require(script.Parent.Progression)
local Research = require(script.Parent.Research)

-- What the goals read: a client Snapshot has all of these.
export type Progress = {
	volts: number,
	bottleTier: number,
	bootTier: number,
	researchers: { [string]: Types.ResearcherSave },
	glints: { number },
	ascension: number,
}

export type GoalKind = Progression.GoalKind | "hire" | "promote" | "ascend"

export type GoalUnit = "volts" | "glints"

export type Goal = {
	kind: GoalKind,
	title: string, -- "Vial", "Dr. Isobar", "Level 2 ⭐⭐"
	detail: string, -- what it gives, or what it takes
	current: number, -- Volts or Glints the player has toward it
	target: number, -- Volts or Glints it takes
	unit: GoalUnit,
	zone: string?, -- for Glints: the name of the Glint tier's zone ("Mesa")
	ready: boolean, -- it can be done now
	readyText: string, -- where to do it, shown once it's ready
}

local Goals = {}

-- Ties go by kind, in this order: a zone still beats a bottle at the same
-- price, as before.
local KIND_ORDER: { [GoalKind]: number } = {
	ascend = 1,
	promote = 2,
	zone = 3,
	bottle = 4,
	boots = 5,
	hire = 6,
}

-- 0.4 stays "0.4", 3.0 becomes "3".
local function formatNumber(value: number): string
	return if value == math.floor(value) then string.format("%d", value) else tostring(value)
end

-- A researcher's perk at level 1, e.g. "Grounding Rod: +1 studs catch radius".
local function perkText(def: Types.ResearcherDef): string
	local text = string.gsub(def.perk, "{v}", formatNumber(def.values[1]))
	return text
end

-- How far along a goal is, from 0 to 1.
function Goals.fraction(goal: Goal): number
	if goal.target <= 0 then
		return 1
	end
	return math.clamp(goal.current / goal.target, 0, 1)
end

local function hireGoal(progress: Progress): Goal?
	for _, def in Config.RESEARCHERS do
		if progress.researchers[def.id] == nil then
			return {
				kind = "hire",
				title = def.name,
				detail = perkText(def),
				current = progress.volts,
				target = def.price,
				unit = "volts",
				ready = progress.volts >= def.price,
				readyText = "Hire at the Research Center",
			}
		end
	end
	return nil
end

-- The hired researcher at the top level closest to their next rank (the
-- first in Config.RESEARCHERS order on a tie).
local function promoteGoal(progress: Progress): Goal?
	local best: Goal? = nil
	local topLevel = #Config.RESEARCH_LEVELS
	for _, def in Config.RESEARCHERS do
		local save = progress.researchers[def.id]
		local rank = if save then save.rank or 0 else 0
		if save and save.level >= topLevel and rank < Research.maxRank() then
			local target = rank + 1
			local zone = Research.tierZone(target)
			local zoneName = if zone then zone.displayName else `tier {target}`
			local percent = math.floor((Research.rankBonus(target) - 1) * 100 + 0.5)
			local current = Research.glintsFor(progress.glints, target)
			local cost = Config.RESEARCH_PRESTIGE.glintCost[target]
			local goal: Goal = {
				kind = "promote",
				title = def.name,
				detail = `Rank {target}: works in {zoneName}, +{percent}% perk`,
				current = current,
				target = cost,
				unit = "glints",
				zone = zoneName,
				ready = current >= cost and (Research.canPromote(save, progress.glints)),
				readyText = "Promote at the Research Office",
			}
			if best == nil or Goals.fraction(goal) > Goals.fraction(best) then
				best = goal
			end
		end
	end
	return best
end

local function ascendGoal(progress: Progress): Goal?
	if progress.bottleTier < Ascension.topTier() then
		return nil
	end
	local level = progress.ascension + 1
	local cost = Ascension.cost(progress.ascension)
	return {
		kind = "ascend",
		title = `Level {level} {Ascension.stars(level)}`,
		detail = `{Ascension.bonusText(level)} Volts for good, resets bottle and boots`,
		current = progress.volts,
		target = cost,
		unit = "volts",
		ready = (Ascension.canAscend(progress)),
		readyText = "Ascend in the Shop",
	}
end

-- Every goal the player could work on now (in no particular order).
function Goals.list(progress: Progress): { Goal }
	local goals: { Goal } = {}
	for _, shop in Progression.nextGoals(progress) do
		local goal: Goal = {
			kind = shop.kind,
			title = shop.title,
			detail = shop.detail,
			current = progress.volts,
			target = shop.price,
			unit = "volts",
			ready = progress.volts >= shop.price,
			readyText = "Open the SHOP",
		}
		table.insert(goals, goal)
	end
	local hire = hireGoal(progress)
	if hire then
		table.insert(goals, hire)
	end
	local promote = promoteGoal(progress)
	if promote then
		table.insert(goals, promote)
	end
	local ascend = ascendGoal(progress)
	if ascend then
		table.insert(goals, ascend)
	end
	return goals
end

-- At the same fraction, a Volts goal not done yet goes by its price (so with
-- 0 Volts the cheapest still goes first); every other goal counts as 0 here.
local function priceKey(goal: Goal): number
	return if goal.unit == "volts" and Goals.fraction(goal) < 1 then goal.target else 0
end

-- Sorts goals closest to done first (for Volts goals that's cheapest first),
-- ties by kind (KIND_ORDER).
function Goals.sort(goals: { Goal })
	table.sort(goals, function(a, b)
		local fa, fb = Goals.fraction(a), Goals.fraction(b)
		if fa ~= fb then
			return fa > fb
		end
		local pa, pb = priceKey(a), priceKey(b)
		if pa ~= pb then
			return pa < pb
		end
		return KIND_ORDER[a.kind] < KIND_ORDER[b.kind]
	end)
end

-- The goal closest to done, or nil if there's none (there always is once
-- the top bottle is owned).
function Goals.pick(progress: Progress): Goal?
	local goals = Goals.list(progress)
	Goals.sort(goals)
	return goals[1]
end

return Goals
