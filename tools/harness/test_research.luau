--!nocheck
-- Research math: level thresholds, perk values, post validation.
--   lune run tools/harness/test_research.luau
local World = require("./World")

local world = World.new("src")
local Config = world:require("ReplicatedStorage.Shared.Config")
local Research = world:require("ReplicatedStorage.Shared.Util.Research")

local failures = 0
local function check(condition, message)
	if not condition then
		failures += 1
		print("FAIL: " .. message)
	end
end

for level, threshold in Config.RESEARCH_LEVELS do
	check(Research.levelFor(threshold) == level, `levelFor({threshold}) == {level}`)
	if level > 1 then
		check(
			Research.levelFor(threshold - 1) == level - 1,
			`levelFor({threshold - 1}) == {level - 1}`
		)
	end
end
check(Research.levelFor(0) == 1, "level 1 at no data")
check(Research.levelFor(1_000_000) == #Config.RESEARCH_LEVELS, "capped at max level")
check(Research.nextThreshold(1) == Config.RESEARCH_LEVELS[2], "next threshold of level 1")
check(Research.nextThreshold(#Config.RESEARCH_LEVELS) == nil, "no next threshold at max")

local ends = {
	Forecaster = { 0.4, 1.2 },
	RodTech = { 1, 3 },
	Analyst = { 10, 30 },
	Chemist = { 3, 15 },
	StormChaser = { 30, 12 },
}
check(#Config.RESEARCHERS == 5, "five researchers")
for _, def in Config.RESEARCHERS do
	check(#def.values == #Config.RESEARCH_LEVELS, `{def.id} has one value per level`)
	local expected = ends[def.id]
	check(Research.perkValue(def.id, 1) == expected[1], `{def.id} level 1 perk`)
	check(Research.perkValue(def.id, 5) == expected[2], `{def.id} level 5 perk`)
	check(Research.perkValue(def.id, 99) == expected[2], `{def.id} clamps high levels`)
	local found = Research.def(def.id)
	check(found ~= nil and found.id == def.id, `def({def.id})`)
end
check(Research.def("Nobody") == nil, "unknown role has no def")
check(Research.perkValue("Nobody", 1) == 0, "unknown role perk is 0")

check(Research.catchRadius(nil) == Config.STRIKE_RADIUS, "no Rod Tech: base radius")
for level = 1, #Config.RESEARCH_LEVELS do
	local perk = Research.perkValue("RodTech", level)
	check(
		Research.catchRadius(level) == Config.STRIKE_RADIUS + perk,
		`catchRadius({level}) adds the perk`
	)
end
check(Research.catchRadius(1) < Research.catchRadius(5), "Rod Tech reach grows with level")

local lastLead = 0
for level = 1, #Config.RESEARCH_LEVELS do
	local lead = Research.forecastLead(level)
	check(lead > lastLead, `forecast lead grows at level {level}`)
	check(lead <= Config.FORECAST_MAX_LEAD, `forecast lead {level} within the public delay`)
	lastLead = lead
end
check(Research.forecastLead(5) == Config.FORECAST_MAX_LEAD, "top Forecaster uses the full lead")
check(Research.forecastLead(99) == Config.FORECAST_MAX_LEAD, "forecast lead clamps high levels")

check(Research.assayChance(1) == 0.1, "Analyst level 1 assay chance")
check(Research.assayChance(5) == 0.3, "Analyst level 5 assay chance")

check(Research.isValidPost("Office"), "Office is a valid post")
check(Research.isValidPost("Mesa"), "a zone is a valid post")
check(not Research.isValidPost("Nowhere"), "unknown zone is invalid")
check(not Research.isValidPost(5), "non-string is invalid")
check(not Research.isValidPost(nil), "nil is invalid")

if failures > 0 then
	error(`{failures} research checks failed`)
end
print("research checks passed")
