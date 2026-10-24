--!strict
-- Researcher math, shared by server and client. Pure: no instances, no state.
--
-- Ranks (prestige, Config.RESEARCH_PRESTIGE): a researcher can only work in
-- zones whose tier is at or below their rank. A zone's tier is the place of
-- its requiresBottle among the non-premium zones' distinct requiresBottle
-- values, from 0, so a new zone gets one by itself. Each rank scales the
-- data per level (dataScale) and makes the perk perkBonusPerRank stronger
-- for good (divided instead for a lower-is-better perk, like the Storm
-- Chaser's seconds between balloon bolts). Promotion to rank r needs level
-- 5 and glintCost[r] Glints of tier r or higher (a Glint per bolt you catch
-- yourself, of that zone's tier), spent lowest tier first; it resets them to
-- level 1 with no data. `rank` arguments are optional: nil means rank 0.

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)

local Research = {}

function Research.def(roleId: string): Types.ResearcherDef?
	for _, def in Config.RESEARCHERS do
		if def.id == roleId then
			return def
		end
	end
	return nil
end

local PRESTIGE = Config.RESEARCH_PRESTIGE

-- The distinct requiresBottle values of the non-premium zones, lowest first.
local function tierBottles(): { number }
	local seen: { [number]: boolean } = {}
	local list: { number } = {}
	for _, zone in Config.ZONES do
		if not zone.premium and not seen[zone.requiresBottle] then
			seen[zone.requiresBottle] = true
			table.insert(list, zone.requiresBottle)
		end
	end
	table.sort(list)
	return list
end

-- A zone's tier: 0 for the first bottle's zones, then one per bottle that
-- opens new zones (a premium zone takes its bottle's tier).
function Research.zoneTier(zone: Types.ZoneDef): number
	local tier = 0
	for index, bottle in tierBottles() do
		if zone.requiresBottle >= bottle then
			tier = index - 1
		end
	end
	return tier
end

-- The highest rank (the top zone tier).
function Research.maxRank(): number
	return #tierBottles() - 1
end

-- The first zone of a tier, by bottle then order (for "Mesa Glints").
function Research.tierZone(tier: number): Types.ZoneDef?
	local best: Types.ZoneDef? = nil
	for _, zone in Config.ZONES do
		if not zone.premium and Research.zoneTier(zone) == tier then
			if best == nil or zone.order < (best :: Types.ZoneDef).order then
				best = zone
			end
		end
	end
	return best
end

-- How much more data each level needs at this rank.
function Research.dataScale(rank: number?): number
	local index = math.clamp((rank or 0) + 1, 1, #PRESTIGE.dataScale)
	return PRESTIGE.dataScale[index]
end

-- The level (1 to max) that a researcher of this rank with this much field
-- data has.
function Research.levelFor(data: number, rank: number?): number
	local scale = Research.dataScale(rank)
	local level = 1
	for index, threshold in Config.RESEARCH_LEVELS do
		if data >= math.floor(threshold * scale + 0.5) then
			level = index
		end
	end
	return level
end

-- Field data needed for the level after this one at this rank, or nil at
-- max level.
function Research.nextThreshold(level: number, rank: number?): number?
	local threshold = Config.RESEARCH_LEVELS[level + 1]
	return if threshold then math.floor(threshold * Research.dataScale(rank) + 0.5) else nil
end

-- How much stronger a perk is at this rank (1.1 at rank 1, 1.6 at rank 6).
function Research.rankBonus(rank: number?): number
	return 1 + (rank or 0) * PRESTIGE.perkBonusPerRank
end

-- Is lower better for this role's perk (its values go down with level)?
function Research.lowerIsBetter(roleId: string): boolean
	local def = Research.def(roleId)
	return def ~= nil and def.values[#def.values] < def.values[1]
end

-- The perk's number at a level (clamped to the valid levels) and rank, or 0
-- for an unknown role.
function Research.perkValue(roleId: string, level: number, rank: number?): number
	local def = Research.def(roleId)
	if not def then
		return 0
	end
	local index = math.clamp(math.floor(level), 1, #def.values)
	local value = def.values[index]
	local bonus = Research.rankBonus(rank)
	return if Research.lowerIsBetter(roleId) then value / bonus else value * bonus
end

-- Catch radius for a player whose Rod Tech is at this level (nil = no Rod Tech).
function Research.catchRadius(rodTechLevel: number?, rank: number?): number
	if not rodTechLevel then
		return Config.STRIKE_RADIUS
	end
	return Config.STRIKE_RADIUS + Research.perkValue("RodTech", rodTechLevel, rank)
end

-- Seconds of early warning for a Forecaster at this level.
function Research.forecastLead(level: number, rank: number?): number
	return math.min(Research.perkValue("Forecaster", level, rank), Config.FORECAST_MAX_LEAD)
end

-- Charges the Chemist's tank holds at this level (whole charges).
function Research.tankCapacity(level: number, rank: number?): number
	return math.floor(Research.perkValue("Chemist", level, rank) + 1e-6)
end

-- Seconds between weather balloon bolts for a Storm Chaser at this level.
function Research.balloonInterval(level: number, rank: number?): number
	return Research.perkValue("StormChaser", level, rank)
end

-- Chance (0 to 1) that a charge is high grade for an Analyst at this level.
function Research.assayChance(level: number, rank: number?): number
	return Research.perkValue("Analyst", level, rank) / 100
end

-- Can a researcher of this rank work in this zone?
function Research.canPost(rank: number?, zone: Types.ZoneDef): boolean
	return Research.zoneTier(zone) <= (rank or 0)
end

-- Glints of one tier (`glints` is the profile's list: glints[tier + 1]).
function Research.glintsOf(glints: { number }, tier: number): number
	return glints[tier + 1] or 0
end

-- Glints that can pay for a promotion to `rank`: tier `rank` or higher.
function Research.glintsFor(glints: { number }, rank: number): number
	local total = 0
	for tier = rank, Research.maxRank() do
		total += Research.glintsOf(glints, tier)
	end
	return total
end

-- Can this researcher be promoted now? true, or false and why (a message).
-- (Being at the Research Office is the server's check.)
function Research.canPromote(save: Types.ResearcherSave, glints: { number }): (boolean, string?)
	local rank = save.rank or 0
	if rank >= Research.maxRank() then
		return false, "Already at the top rank"
	end
	if save.level < #Config.RESEARCH_LEVELS then
		return false, `Needs level {#Config.RESEARCH_LEVELS} first`
	end
	local target = rank + 1
	local cost = PRESTIGE.glintCost[target]
	local have = Research.glintsFor(glints, target)
	if have < cost then
		local zone = Research.tierZone(target)
		local name = if zone then zone.displayName else `tier {target}`
		return false, `Needs {cost - have} more {name} Glints`
	end
	return true, nil
end

-- Spends the Glints for a promotion to `rank` (lowest eligible tier first).
-- Returns the new list, or nil when there aren't enough.
function Research.spendGlints(glints: { number }, rank: number): { number }?
	local cost = PRESTIGE.glintCost[rank]
	if not cost or Research.glintsFor(glints, rank) < cost then
		return nil
	end
	local out = table.clone(glints)
	for tier = rank, Research.maxRank() do
		local take = math.min(cost, Research.glintsOf(out, tier))
		out[tier + 1] = Research.glintsOf(out, tier) - take
		cost -= take
		if cost <= 0 then
			break
		end
	end
	for tier = 0, Research.maxRank() do
		out[tier + 1] = out[tier + 1] or 0 -- no holes: it's saved as a list
	end
	return out
end

-- "Office" or the id of a zone in Config.ZONES.
function Research.isValidPost(post: unknown): boolean
	if typeof(post) ~= "string" then
		return false
	end
	return post == "Office" or Config.ZONES[post] ~= nil
end

return Research
