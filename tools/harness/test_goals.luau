--!nocheck
-- The goal card's goals (shared/Util/Goals): a new player's first bottle,
-- hiring in order, promoting (Glints, top level only, the closest one),
-- the next Ascension, the tie order, and that the card is never empty.
--   lune run tools/harness/test_goals.luau
local World = require("./World")

local world = World.new("src")
local Config = world:require("ReplicatedStorage.Shared.Config")
local Goals = world:require("ReplicatedStorage.Shared.Util.Goals")
local Research = world:require("ReplicatedStorage.Shared.Util.Research")
local Ascension = world:require("ReplicatedStorage.Shared.Util.Ascension")

local failures = 0
local function check(condition, message)
	if not condition then
		failures += 1
		print("FAIL: " .. message)
	end
end

local TOP_LEVEL = #Config.RESEARCH_LEVELS
local TOP_BOTTLE = #Config.BOTTLES
local TOP_BOOTS = #Config.BOOTS
local MAX_RANK = Research.maxRank()

local function player(fields)
	local progress = {
		volts = 0,
		bottleTier = 1,
		bootTier = 1,
		researchers = {},
		glints = {},
		ascension = 0,
	}
	for key, value in fields or {} do
		progress[key] = value
	end
	return progress
end

local function researcher(level, rank)
	return { level = level, data = 0, post = "Office", rank = rank }
end

local function find(goals, kind)
	for _, goal in goals do
		if goal.kind == kind then
			return goal
		end
	end
	return nil
end

-- A new player: the first bottle to buy is the pick
local fresh = Goals.pick(player())
check(fresh ~= nil, "a new player has a goal")
check(fresh and fresh.kind == "bottle", "a new player's goal is a bottle")
check(fresh and fresh.title == Config.BOTTLES[2].name, "and it's the second bottle")
check(fresh and fresh.unit == "volts" and fresh.current == 0, "counted in Volts from 0")
check(fresh and fresh.target == Config.BOTTLES[2].price, "toward its price")
check(fresh and not fresh.ready, "not ready with no Volts")
local rich = Goals.pick(player({ volts = Config.BOTTLES[2].price }))
check(rich and rich.ready and rich.kind == "bottle", "ready once they have the Volts")

-- Hire: the next researcher not hired yet, in Config.RESEARCHERS order
local hired = {}
for index, def in Config.RESEARCHERS do
	local hire = find(Goals.list(player({ researchers = hired })), "hire")
	check(hire ~= nil and hire.title == def.name, `hire #{index} is {def.name}`)
	check(hire and hire.target == def.price and hire.unit == "volts", `{def.name} costs Volts`)
	check(hire and hire.readyText == "Hire at the Research Center", "hire's ready text")
	hired[def.id] = researcher(1, 0)
end
local allHired = Goals.list(player({ researchers = hired }))
check(find(allHired, "hire") == nil, "no hire once all are hired")
local first = Config.RESEARCHERS[1]
local hireReady = find(Goals.list(player({ volts = first.price })), "hire")
check(hireReady and hireReady.ready, "hire is ready with the price in Volts")

-- Promote: only researchers at the top level, Glints from Research.glintsFor
local a, b = Config.RESEARCHERS[1], Config.RESEARCHERS[2]
local glints = {}
for tier = 0, MAX_RANK do
	glints[tier + 1] = 10 * (tier + 1)
end
local onlyLow = Goals.list(player({ researchers = { [a.id] = researcher(TOP_LEVEL - 1, 0) } }))
check(find(onlyLow, "promote") == nil, "no promote below the top level")
local topRank = Goals.list(player({ researchers = { [a.id] = researcher(TOP_LEVEL, MAX_RANK) } }))
check(find(topRank, "promote") == nil, "no promote at the top rank")
local one = find(
	Goals.list(player({ glints = glints, researchers = { [a.id] = researcher(TOP_LEVEL, 0) } })),
	"promote"
)
check(one ~= nil and one.title == a.name, "promote for a top-level researcher")
check(one and one.unit == "glints", "promote counts Glints")
check(one and one.current == Research.glintsFor(glints, 1), "using Research.glintsFor")
check(one and one.target == Config.RESEARCH_PRESTIGE.glintCost[1], "toward the rank's cost")
check(
	one and one.zone == Research.tierZone(1).displayName,
	"named after the Glint tier's zone"
)
check(
	one and string.find(one.detail, "Rank 1: works in", 1, true) ~= nil,
	"detail says the rank"
)
check(
	one and one.ready == (Research.canPromote(researcher(TOP_LEVEL, 0), glints)),
	"ready matches canPromote"
)
-- two at the top level: only the closest one goes in the list
if MAX_RANK >= 2 then
	local both = Goals.list(player({
		glints = glints,
		researchers = { [a.id] = researcher(TOP_LEVEL, 0), [b.id] = researcher(TOP_LEVEL, 1) },
	}))
	local count = 0
	for _, goal in both do
		if goal.kind == "promote" then
			count += 1
		end
	end
	check(count == 1, "only one promote goal")
	local fa = math.min(Research.glintsFor(glints, 1) / Config.RESEARCH_PRESTIGE.glintCost[1], 1)
	local fb = math.min(Research.glintsFor(glints, 2) / Config.RESEARCH_PRESTIGE.glintCost[2], 1)
	local expected = if fb > fa then b.name else a.name
	local promote = find(both, "promote")
	check(promote and promote.title == expected, "the closest researcher is the one shown")
end
local enough = {}
for tier = 0, MAX_RANK do
	enough[tier + 1] = 1000
end
local ready = find(
	Goals.list(player({ glints = enough, researchers = { [a.id] = researcher(TOP_LEVEL, 0) } })),
	"promote"
)
check(ready and ready.ready, "promote is ready with enough Glints")
check(ready and ready.readyText == "Promote at the Research Office", "promote's ready text")

-- Ascend: only with the top bottle, and the pick when everything else is done
for tier = 1, TOP_BOTTLE - 1 do
	check(find(Goals.list(player({ bottleTier = tier })), "ascend") == nil, `no ascend at {tier}`)
end
local done = {}
for _, def in Config.RESEARCHERS do
	done[def.id] = researcher(TOP_LEVEL, MAX_RANK)
end
local finished = player({ bottleTier = TOP_BOTTLE, bootTier = TOP_BOOTS, researchers = done })
local ascend = find(Goals.list(finished), "ascend")
check(ascend ~= nil, "ascend shows with the top bottle")
check(ascend and ascend.target == Ascension.cost(0), "toward Ascension.cost")
check(ascend and string.find(ascend.title, "Level 1", 1, true) ~= nil, "named by the next level")
check(#Goals.list(finished) == 1, "only ascend is left when everything else is done")
local pick = Goals.pick(finished)
check(pick and pick.kind == "ascend", "ascend is the pick when everything else is done")
finished.volts = Ascension.cost(0)
local ascendReady = Goals.pick(finished)
check(ascendReady and ascendReady.ready, "ascend is ready with the Volts")
check(ascendReady and ascendReady.readyText == "Ascend in the Shop", "ascend's ready text")
finished.ascension = 1
local second = Goals.pick(finished)
check(second and second.target == Ascension.cost(1), "the next level costs more")
check(second and string.find(second.title, "Level 2", 1, true) ~= nil, "Level 2 next")

-- The tie order: ascend, promote, zone, bottle, boots, hire
local function goal(kind, current, target)
	return {
		kind = kind,
		title = kind,
		detail = "",
		current = current,
		target = target,
		unit = if kind == "promote" then "glints" else "volts",
		ready = current >= target,
		readyText = "",
	}
end
local all = {
	goal("hire", 10, 10),
	goal("boots", 10, 10),
	goal("bottle", 10, 10),
	goal("zone", 10, 10),
	goal("promote", 10, 10),
	goal("ascend", 10, 10),
}
Goals.sort(all)
local order = {}
for _, g in all do
	table.insert(order, g.kind)
end
check(
	table.concat(order, ",") == "ascend,promote,zone,bottle,boots,hire",
	`ready goals go by kind (got {table.concat(order, ",")})`
)
local same = { goal("bottle", 5, 100), goal("zone", 5, 100) }
Goals.sort(same)
check(same[1].kind == "zone", "a zone beats a bottle at the same price")
local cheap = { goal("zone", 0, 300), goal("bottle", 0, 80), goal("hire", 0, 400) }
Goals.sort(cheap)
check(cheap[1].kind == "bottle", "with no Volts, the cheapest goes first")
local closer = { goal("bottle", 50, 100), goal("promote", 30, 40) }
Goals.sort(closer)
check(closer[1].kind == "promote", "the goal closest to done goes first")

-- The card is never empty, for any bottle tier
for tier = 1, TOP_BOTTLE do
	for _, boots in { 1, TOP_BOOTS } do
		local p = player({ bottleTier = tier, bootTier = boots, researchers = done })
		check(Goals.pick(p) ~= nil, `a goal with bottle {tier} and boots {boots}`)
	end
end

if failures > 0 then
	error(`{failures} goal checks failed`)
end
print("goal checks passed")
