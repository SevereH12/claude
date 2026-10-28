--!nocheck
-- Research math: level thresholds, perk values, post validation, and
-- ranks (prestige): zone tiers, per-rank levels, the rank bonus, posting,
-- promotion, Glint spending and the v9 -> v10 save migration.
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

local PRESTIGE = Config.RESEARCH_PRESTIGE
-- level thresholds per rank: RESEARCH_LEVELS x that rank's scale
for rank = 0, Research.maxRank() do
	local scale = PRESTIGE.dataScale[math.min(rank + 1, #PRESTIGE.dataScale)]
	for level, base in Config.RESEARCH_LEVELS do
		local threshold = math.floor(base * scale + 0.5)
		check(
			Research.levelFor(threshold, rank) == level,
			`rank {rank}: levelFor({threshold}) == {level}`
		)
		if level > 1 then
			check(
				Research.levelFor(threshold - 1, rank) == level - 1,
				`rank {rank}: just under level {level}`
			)
			check(
				Research.nextThreshold(level - 1, rank) == threshold,
				`rank {rank}: next threshold of level {level - 1}`
			)
		end
	end
	check(Research.levelFor(0, rank) == 1, `rank {rank}: level 1 at no data`)
	check(
		Research.levelFor(1e9, rank) == #Config.RESEARCH_LEVELS,
		`rank {rank}: capped at max level`
	)
end
check(Research.nextThreshold(#Config.RESEARCH_LEVELS) == nil, "no next threshold at max")
local LEVEL5 = { 950, 1600, 2900, 4300, 4900, 5450, 5450 }
for rank = 0, 6 do
	check(
		Research.nextThreshold(4, rank) == LEVEL5[rank + 1],
		`level 5 at rank {rank} needs {LEVEL5[rank + 1]} data`
	)
end

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
check(
	math.abs(Research.forecastLead(5, Research.maxRank()) - Config.FORECAST_MAX_LEAD) < 1e-9,
	"a top-rank Forecaster uses the full lead"
)
check(Research.forecastLead(5) == 1.2, "a rank-0 Forecaster at level 5: 1.2 s")
check(Research.forecastLead(99, 99) <= Config.FORECAST_MAX_LEAD, "forecast lead clamps")

check(Research.assayChance(1) == 0.1, "Analyst level 1 assay chance")
check(Research.assayChance(5) == 0.3, "Analyst level 5 assay chance")

check(Research.isValidPost("Office"), "Office is a valid post")
check(Research.isValidPost("Mesa"), "a zone is a valid post")
check(not Research.isValidPost("Nowhere"), "unknown zone is invalid")
check(not Research.isValidPost(5), "non-string is invalid")
check(not Research.isValidPost(nil), "nil is invalid")

-- zone tiers come from Config -------------------------------------------------------
local TIERS = {
	Shoreline = 0,
	Aurora = 0,
	Mesa = 1,
	Yard = 2,
	Tidewire = 3,
	Thunderhead = 4,
	Spire = 4,
	Cloudshore = 5,
	Ember = 6,
}
for id, tier in TIERS do
	check(Config.ZONES[id] and Research.zoneTier(Config.ZONES[id]) == tier, `{id} is tier {tier}`)
end
check(Research.maxRank() == 6, "six ranks above 0")
check(Research.tierZone(2) and Research.tierZone(2).id == "Yard", "tier 2's zone is Generator Yard")
-- each tier is one more distinct bottle
for _, zone in Config.ZONES do
	for _, other in Config.ZONES do
		if
			not zone.premium
			and not other.premium
			and zone.requiresBottle < other.requiresBottle
		then
			check(Research.zoneTier(zone) < Research.zoneTier(other), `{zone.id} below {other.id}`)
		end
	end
end

-- the rank bonus: 10% a rank, divided for lower-is-better perks ---------------------
check(
	math.abs(Research.perkValue("Analyst", 5, 3) - 30 * 1.3) < 1e-9,
	"Analyst level 5 rank 3: +30%"
)
check(
	math.abs(Research.perkValue("StormChaser", 5, 6) - 12 / 1.6) < 1e-9,
	"Storm Chaser rank 6 waits 1.6x less"
)
check(
	Research.lowerIsBetter("StormChaser") and not Research.lowerIsBetter("Analyst"),
	"only the Storm Chaser is lower-is-better"
)
check(Research.perkValue("RodTech", 3, 0) == Research.perkValue("RodTech", 3), "rank 0 is no bonus")
check(Research.tankCapacity(5, 6) == 24, "Chemist rank 6 level 5 holds 24 (whole charges)")

-- posting ---------------------------------------------------------------------------
check(Research.canPost(0, Config.ZONES.Shoreline), "rank 0 works in Shoreline")
check(Research.canPost(0, Config.ZONES.Aurora), "and the Premium zone (tier 0)")
check(not Research.canPost(0, Config.ZONES.Mesa), "but not Mesa")
check(
	Research.canPost(4, Config.ZONES.Spire) and Research.canPost(4, Config.ZONES.Thunderhead),
	"rank 4: Thunderhead and Rune Spire"
)
check(not Research.canPost(4, Config.ZONES.Cloudshore), "not Cloudshore")

-- promotion: every refusal ---------------------------------------------------------
local function glints(list)
	return list
end
local ok, why =
	Research.canPromote({ level = 4, data = 0, post = "Office", rank = 0 }, glints({ 0, 999 }))
check(not ok and why and string.find(why, "level 5"), `not before level 5 ({why})`)
ok, why =
	Research.canPromote({ level = 5, data = 0, post = "Office", rank = 0 }, glints({ 999, 10 }))
check(
	not ok and why == "Needs 40 more Mesa Glints",
	`rank 1 needs Mesa Glints, not Shoreline ones ({why})`
)
ok = Research.canPromote({ level = 5, data = 0, post = "Office", rank = 0 }, glints({ 0, 20, 30 }))
check(ok, "Glints of a higher tier pay too")
ok, why = Research.canPromote(
	{ level = 5, data = 0, post = "Office", rank = 6 },
	glints({ 999, 999, 999, 999, 999, 999, 999 })
)
check(not ok and why == "Already at the top rank", `the top rank can't go higher ({why})`)

-- Glint spending: lowest eligible tier first, then higher ones ------------------------
local after = Research.spendGlints({ 50, 20, 40, 0, 0, 0, 0 }, 1) -- costs 50 of tier 1+
check(
	after and after[1] == 50 and after[2] == 0 and after[3] == 10,
	"rank 1: Mesa's 20 first, then 30 Generator Yard"
)
check(Research.spendGlints({ 100, 10 }, 1) == nil, "not enough: nothing spent")
local exact = Research.spendGlints({ 0, 0, 65 }, 2)
check(exact and exact[3] == 0 and #exact == 7, "spends to 0 and keeps the list whole")

-- the migration: rank = the tier of the zone they're in, level kept or raised -------
local PlayerData = world:require("ServerScriptService.Server.Systems.PlayerData")
local migrated = PlayerData.migrate({
	version = 9,
	volts = 0,
	bottleTier = 7,
	researchers = {
		Forecaster = { level = 3, data = 300, post = "Thunderhead" },
		RodTech = { level = 5, data = 1000, post = "Office" },
		Analyst = { level = 2, data = 1200, post = "Mesa" },
	},
})
check(
	migrated.version >= 10 and typeof(migrated.glints) == "table" and #migrated.glints == 0,
	"v10 with no Glints"
)
check(
	typeof(migrated.settings) == "table"
		and migrated.settings.sfxVolume == 1
		and migrated.settings.muted == false,
	"v11: default sound settings"
)
check(migrated.researchers.Forecaster.rank == 4, "posted in Thunderhead: rank 4")
check(migrated.researchers.RodTech.rank == 0, "at the Office: rank 0")
check(
	migrated.researchers.RodTech.level == 5 and migrated.researchers.RodTech.data == 1000,
	"level and data kept"
)
check(
	migrated.researchers.Analyst.rank == 1 and migrated.researchers.Analyst.level == 4,
	"Mesa rank 1: 1200 data is level 4 there"
)
check(migrated.researchers.Forecaster.level == 3, "never lowered")

if failures > 0 then
	error(`{failures} research checks failed`)
end
print("research checks passed")
