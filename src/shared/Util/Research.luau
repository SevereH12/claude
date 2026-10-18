--!strict
-- Researcher math, shared by server and client. Pure: no instances, no state.

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

-- The level (1 to max) that a researcher with this much field data has.
function Research.levelFor(data: number): number
	local level = 1
	for index, threshold in Config.RESEARCH_LEVELS do
		if data >= threshold then
			level = index
		end
	end
	return level
end

-- Field data needed for the level after this one, or nil at max level.
function Research.nextThreshold(level: number): number?
	return Config.RESEARCH_LEVELS[level + 1]
end

-- The perk's number at a level (clamped to the valid levels), or 0 for an
-- unknown role.
function Research.perkValue(roleId: string, level: number): number
	local def = Research.def(roleId)
	if not def then
		return 0
	end
	local index = math.clamp(math.floor(level), 1, #def.values)
	return def.values[index]
end

-- "Office" or the id of a zone in Config.ZONES.
function Research.isValidPost(post: unknown): boolean
	if typeof(post) ~= "string" then
		return false
	end
	return post == "Office" or Config.ZONES[post] ~= nil
end

return Research
