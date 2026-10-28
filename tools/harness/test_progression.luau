--!nocheck
-- Zone gates, world portals, next goals and the bottle tier migration.
--   lune run tools/harness/test_progression.luau
local roblox = require("@lune/roblox")
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
check(Progression.canEnter(progress(1), shoreline, false), "everyone can enter Shoreline")
check(Progression.lockReason(progress(1), shoreline, false) == nil, "Shoreline has no lock reason")
check(not Progression.canEnter(progress(1), mesa, false), "a Jar can't enter Mesa")
check(not Progression.canEnter(progress(2), mesa, false), "a Vial can't enter Mesa")
check(Progression.canEnter(progress(3), mesa, false), "a Flask can enter Mesa")
check(Progression.canEnter(progress(5), mesa, false), "a better bottle can enter Mesa")
check(
	Progression.lockReason(progress(1), mesa, false) == "Needs a Flask",
	"Mesa's lock reason names the Flask"
)
check(Progression.lockReason(progress(3), mesa, false) == nil, "no lock reason once Mesa is open")
check(Progression.requirement(shoreline) == nil, "Shoreline has no gate")
check(Progression.requirement(mesa) == "Needs a Flask", "Mesa's gate sign says it needs a Flask")

-- Premium zone: members only, and pays 1.5x the best zone you can enter
local aurora = Config.ZONES.Aurora
local Premium, NotPremium = roblox.Enum.MembershipType.Premium, roblox.Enum.MembershipType.None
check(aurora ~= nil and aurora.premium == true, "Aurora is a premium zone")
check(Progression.isPremium(Premium), "a member is Premium")
check(not Progression.isPremium(NotPremium), "a non-member isn't")
check(Progression.canEnter(progress(1), aurora, true), "a member can enter Aurora with a Jar")
check(
	not Progression.canEnter(progress(5), aurora, false),
	"a non-member can't, whatever the bottle"
)
check(Progression.canEnter(progress(5), shoreline, false), "non-members still enter free zones")
local premiumReason = Progression.lockReason(progress(1), aurora, false)
check(
	premiumReason ~= nil and string.find(premiumReason, "Premium members only", 1, true) ~= nil,
	"Aurora's lock reason says Premium members only"
)
check(
	string.find(premiumReason or "", utf8.char(0xE001), 1, true) ~= nil,
	"and shows the Premium icon"
)
check(Progression.lockReason(progress(1), aurora, true) == nil, "no lock reason for a member")
check(
	Progression.lockReason(progress(1), mesa, true) == "Needs a Flask",
	"Premium doesn't open Mesa"
)
check(Progression.requirement(aurora) == premiumReason, "Aurora's gate sign matches")
local multiplier = Config.PREMIUM_VALUE_MULTIPLIER
check(
	Progression.boltValue(progress(1), aurora) == math.round(shoreline.chargeValue * multiplier),
	"with a Jar, Aurora pays 1.5x Shoreline"
)
check(
	Progression.boltValue(progress(3), aurora) == math.round(mesa.chargeValue * multiplier),
	"with a Flask, Aurora pays 1.5x Mesa"
)
check(
	Progression.boltValue(progress(3), mesa) == mesa.chargeValue,
	"other zones pay their own value"
)
for tier = 1, #Config.BOTTLES do
	for _, goal in Progression.nextGoals(progress(tier)) do
		check(goal.title ~= aurora.displayName, "Aurora is never a Volts goal")
	end
end

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
local topNeed = 0
for _, zone in Config.ZONES do
	topNeed = math.max(topNeed, zone.requiresBottle)
end
for _, goal in Progression.nextGoals(progress(topNeed)) do
	check(goal.kind ~= "zone", "no zone goal once every zone is open")
end

-- worlds: the second world's portal opens with its bottle, and until then
-- the zone goal past the first world is the world itself
local second = Config.WORLDS[2]
if second then
	local need = second.requiresBottle
	check(
		Progression.canEnterWorld(progress(1), Config.WORLDS[1]),
		"everyone can be in the first world"
	)
	check(
		not Progression.canEnterWorld(progress(need - 1), second),
		"the bottle before can't travel on"
	)
	check(Progression.canEnterWorld(progress(need), second), "its bottle opens the next world")
	check(
		Progression.worldLockReason(progress(1), second) == Progression.worldRequirement(second),
		"a locked portal says what it needs"
	)
	check(
		Progression.worldLockReason(progress(need), second) == nil,
		"an open portal has no lock reason"
	)
	local firstWorldTop = 0
	for _, zone in Config.ZONES do
		if zone.world == Config.WORLDS[1].id and not zone.premium then
			firstWorldTop = math.max(firstWorldTop, zone.requiresBottle)
		end
	end
	local worldGoal
	for _, goal in Progression.nextGoals(progress(firstWorldTop)) do
		if goal.kind == "zone" then
			worldGoal = goal
		end
	end
	check(
		worldGoal ~= nil and worldGoal.title == second.displayName,
		"with the first world open, the next zone goal is the next world"
	)
	local cost = 0
	for tier = firstWorldTop + 1, need do
		cost += Config.BOTTLES[tier].price
	end
	check(
		worldGoal ~= nil and worldGoal.price == cost,
		"and it costs the bottles up to the world's"
	)
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
