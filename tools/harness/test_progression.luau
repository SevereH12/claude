--!nocheck
-- Zone gates, next goals and the bottle tier migration.
--   lune run tools/harness/test_progression.luau
local World = require("./World")

local world = World.new("src")
local Config = world:require("ReplicatedStorage.Shared.Config")
local Progression = world:require("ReplicatedStorage.Shared.Util.Progression")
local PlayerData = world:require("ServerScriptService.Server.Systems.PlayerData")

local failures = 0
local function check(condition, message)
	if not condition then
		failures += 1
		print("FAIL: " .. message)
	end
end

local function progress(bottleTier, bootTier)
	return { bottleTier = bottleTier, bootTier = bootTier or 1, volts = 0 }
end

local shoreline, mesa = Config.ZONES.Shoreline, Config.ZONES.Mesa
local flask = 0
for tier, bottle in Config.BOTTLES do
	if bottle.name == "Flask" then
		flask = tier
	end
end
check(Config.BOTTLES[2].name == "Vial", "the Vial is bottle tier 2")
check(flask == 3, "the Flask is bottle tier 3")
check(mesa.requiresBottle == flask, "Mesa needs the Flask")

-- canEnter / lockReason
check(Progression.canEnter(progress(1), shoreline), "everyone can enter Shoreline")
check(Progression.lockReason(progress(1), shoreline) == nil, "Shoreline has no lock reason")
check(not Progression.canEnter(progress(1), mesa), "a Jar can't enter Mesa")
check(not Progression.canEnter(progress(2), mesa), "a Vial can't enter Mesa")
check(Progression.canEnter(progress(3), mesa), "a Flask can enter Mesa")
check(Progression.canEnter(progress(5), mesa), "a better bottle can enter Mesa")
check(
	Progression.lockReason(progress(1), mesa) == "Needs a Flask",
	"Mesa's lock reason names the Flask"
)
check(Progression.lockReason(progress(3), mesa) == nil, "no lock reason once Mesa is open")
check(Progression.requirement(shoreline) == nil, "Shoreline has no gate")
check(Progression.requirement(mesa) == "Needs a Flask", "Mesa's gate sign says it needs a Flask")

-- nextGoals: cheapest first, a zone wins ties
local goals = Progression.nextGoals(progress(1))
check(#goals == 3, "a new player has three goals (bottle, boots, zone)")
check(goals[1].kind == "bottle" and goals[1].title == "Vial", "the first goal is the cheap Vial")
for i = 2, #goals do
	check(goals[i - 1].price <= goals[i].price, "goals are sorted by price")
end
local mesaGoal
for _, goal in goals do
	if goal.kind == "zone" then
		mesaGoal = goal
	end
end
check(mesaGoal ~= nil and mesaGoal.title == mesa.displayName, "Mesa is a goal for a new player")
check(
	mesaGoal ~= nil and mesaGoal.price == Config.BOTTLES[2].price + Config.BOTTLES[3].price,
	"unlocking Mesa from a Jar costs the Vial plus the Flask"
)
local withVial = Progression.nextGoals(progress(2))
check(withVial[1].kind == "zone", "with a Vial, unlocking Mesa (a Flask away) is the top goal")
check(withVial[1].price == Config.BOTTLES[3].price, "and it costs one Flask")
for _, goal in Progression.nextGoals(progress(3)) do
	check(goal.kind ~= "zone", "no zone goal once every zone is open")
end
local top = Progression.nextGoals(progress(#Config.BOTTLES, #Config.BOOTS))
check(#top == 0, "nothing left to aim for with the best bottle and boots")

-- migration: Vial was inserted at tier 2, so saved tiers 2+ move up one
local function migrated(version, bottleTier)
	return PlayerData.migrate({ version = version, volts = 0, bottleTier = bottleTier })
end
check(migrated(3, 1).bottleTier == 1, "a saved Jar stays a Jar")
check(migrated(3, 2).bottleTier == 3, "a saved Flask (old tier 2) is still a Flask")
check(migrated(3, 4).bottleTier == 5, "a saved Storm Cell (old tier 4) is still a Storm Cell")
check(migrated(1, 2).bottleTier == 3, "migrating from v1 moves the tier up too")
check(migrated(1, 2).bootTier == 1, "and adds the starter boots")
check(migrated(4, 2).bottleTier == 2, "a current save isn't moved")

if failures > 0 then
	error(`{failures} progression checks failed`)
end
print("progression checks passed")
