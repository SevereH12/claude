--!nocheck
-- Gameplay tips (shared/Util/Hints, Config.HINTS): every tip in the list
-- is well formed, the triggers, the order, the timing rules (no tip during
-- the tutorial, while busy, with tips off, too soon after joining or after
-- the last tip), once only, and the v18 -> v19 profile migration (tips for
-- things already done count as seen).
--   lune run tools/harness/test_hints.luau
local World = require("./World")

local world = World.new("src")
local Config = world:require("ReplicatedStorage.Shared.Config")
local Hints = world:require("ReplicatedStorage.Shared.Util.Hints")
local Settings = world:require("ReplicatedStorage.Shared.Util.Settings")
local Stats = world:require("ReplicatedStorage.Shared.Util.Stats")
local PlayerData = world:require("ServerScriptService.Server.Systems.PlayerData")

local failures = 0
local function check(condition, message)
	if not condition then
		failures += 1
		print("FAIL: " .. message)
	end
end

-- the list ------------------------------------------------------------------------
local OPENS = {
	shop = true,
	shopBoots = true,
	research = true,
	researchLog = true,
	rewards = true,
	quests = true,
	top = true,
	boosts = true,
	teleport = true,
	settings = true,
	sell = true,
}
local GLOWS = {
	SHOP = true,
	RESEARCH = true,
	TELEPORT = true,
	BOOSTS = true,
	REWARDS = true,
	SETTINGS = true,
	RemoteSell = true,
	ServerGoal = true,
}
local ids = {}
for _, def in Hints.list() do
	check(not ids[def.id], `tip {def.id} is listed once`)
	ids[def.id] = true
	check(Hints.CONDITIONS[def.when] ~= nil, `tip {def.id}'s trigger {def.when} exists`)
	check(def.open == nil or OPENS[def.open], `tip {def.id} opens something real`)
	check(def.glow == nil or GLOWS[def.glow], `tip {def.id} glows on something real`)
	local text = Hints.text(def)
	check(not string.find(text, "{", 1, true), `tip {def.id}'s numbers are filled in: {text}`)
	check(#text <= 80, `tip {def.id} is short enough for its toast ({#text} characters)`)
	check(Hints.def(def.id) == def, `tip {def.id} is found by id`)
end
-- every part of the game has a tip
for _, id in
	{
		"boots",
		"newZone",
		"hireResearcher",
		"postResearcher",
		"glints",
		"promote",
		"stormLog",
		"dailyStreak",
		"playtimeGifts",
		"quests",
		"leaderboards",
		"invite",
		"group",
		"boosts",
		"afkLounge",
		"portal",
		"teleport",
		"rareBolt",
		"supercell",
		"event",
		"serverGoal",
		"remoteSell",
		"ascend",
		"settings",
		"friendsBoost",
	}
do
	check(ids[id], `there's a tip for {id}`)
end
check(Hints.def("nope") == nil and Hints.def(5) == nil, "unknown ids are refused")
check(
	string.find(Hints.text(Hints.def("group")), "+10%", 1, true) ~= nil,
	"the group tip says +10%"
)
check(
	string.find(Hints.text(Hints.def("friendsBoost")), "up to +15%", 1, true) ~= nil,
	"the friends tip says up to +15%"
)

-- the setting
local tips = Settings.def("showTips")
check(tips ~= nil and tips.kind == "bool" and tips.default == true, "Gameplay tips is a switch, on")
check(tips ~= nil and tips.section == "Accessibility & HUD", "on the Accessibility & HUD tab")

-- triggers and order --------------------------------------------------------------
local function snapshot(over)
	local s = {
		tutorialStep = 0,
		bottleTier = 2,
		bootTier = 1,
		volts = 0,
		researchers = {},
		glints = {},
		log = { found = {}, claimed = {} },
		daily = { streak = 0, lastDay = 0 },
		chargeCount = 0,
		capacity = 10,
		passes = {},
		friends = 0,
	}
	for k, v in over or {} do
		s[k] = v
	end
	return s
end
local function session(over)
	local s = {
		minutes = 0,
		canAscend = false,
		groupMember = true,
		sold = false,
		sawRareBolt = false,
		sawSupercell = false,
		eventOn = false,
	}
	for k, v in over or {} do
		s[k] = v
	end
	return s
end
local OPEN = { now = 1000, lastShown = -math.huge, quietUntil = 0, busy = false, enabled = true }
local function pick(snap, sess, seen, timing)
	local def = Hints.pick(seen or {}, Hints.facts(snapshot(snap), session(sess)), timing or OPEN)
	return def and def.id
end

check(pick() == nil, "a fresh player with nothing going on gets no tip")
check(
	pick({ volts = Config.BOOTS[2].price }) == "boots",
	"affording the first boots: the boots tip"
)
check(pick({ volts = Config.BOOTS[2].price - 1 }) == nil, "not quite affording them: nothing")
check(
	pick({ volts = Config.BOOTS[2].price, bootTier = 2 }) == nil,
	"already in better boots: no boots tip"
)
check(pick({ bottleTier = 3 }) == "newZone", "the Flask opens Mesa: the new zone tip")
check(
	pick({ bottleTier = Config.WORLDS[2].requiresBottle }) == "portal",
	"a new world beats a new zone"
)
check(pick({ volts = 400 }) == "boots", "boots come before the first researcher")
check(pick({ volts = 400 }, nil, { boots = true }) == "hireResearcher", "then hiring one")
local office = { Forecaster = { level = 1, data = 0, post = "Office", rank = 0 } }
check(pick({ researchers = office }) == "postResearcher", "a researcher at the Office: post them")
local posted = { Forecaster = { level = 5, data = 0, post = "Shoreline", rank = 0 } }
check(pick({ researchers = posted, glints = { 3 } }) == "glints", "Glints come before promoting")
check(
	pick({ researchers = posted, glints = { 3 } }, nil, { glints = true }) == "promote",
	"a level 5 researcher: promote"
)
check(
	pick({ log = { found = { "a", "b", "c" }, claimed = {} } }) == "stormLog",
	"3 Log entries: the Storm Log tip"
)
check(
	pick({ daily = { streak = 1, lastDay = 1 } }) == "dailyStreak",
	"a claimed daily: the streak tip"
)
check(pick(nil, { minutes = 2.9 }) == nil, "time tips wait for their minute")
check(pick(nil, { minutes = 3 }) == "playtimeGifts", "3 minutes in: playtime gifts")
check(
	pick(nil, { minutes = 5, sold = true }, { playtimeGifts = true }) == "serverGoal",
	"after a sale: the server goal"
)
check(
	pick(nil, { minutes = 4 }, { playtimeGifts = true }) == nil,
	"no server goal tip before a sale"
)
check(pick({ friends = 1 }) == "friendsBoost", "a friend in the server: the friends tip")
check(pick(nil, { groupMember = false, minutes = 22 }, {
	playtimeGifts = true,
	quests = true,
	afkLounge = true,
	leaderboards = true,
}) == "group", "not in the group, 22 minutes in: the group tip")
check(pick(nil, { minutes = 22 }, {
	playtimeGifts = true,
	quests = true,
	afkLounge = true,
	leaderboards = true,
}) == nil, "a group member never gets it")
check(
	pick({ passes = { RemoteSell = true }, chargeCount = 10 }) == "remoteSell",
	"Remote Sell and a full bottle"
)
check(
	pick({ passes = { RemoteSell = true }, chargeCount = 3 }) == nil,
	"Remote Sell with room left: not yet"
)
check(pick({ chargeCount = 10 }) == nil, "a full bottle without Remote Sell: nothing")
check(pick(nil, { canAscend = true }) == "ascend", "ready to ascend")
check(pick(nil, { sawRareBolt = true }) == "rareBolt", "a rare bolt was seen")
check(pick(nil, { sawSupercell = true }) == "supercell", "a Supercell was seen")
check(pick(nil, { eventOn = true }) == "event", "an event is on")
check(
	pick({ passes = { RemoteSell = true }, chargeCount = 10, volts = 400 }, { canAscend = true })
		== "remoteSell",
	"the first true tip in the list wins"
)

-- once only: going through the whole list, every tip shows once and in order
local everything = {
	bottleTier = Config.WORLDS[2].requiresBottle,
	volts = 10_000_000,
	researchers = { Forecaster = { level = 5, data = 0, post = "Office", rank = 0 } },
	glints = { 5 },
	log = { found = { "a", "b", "c" }, claimed = {} },
	daily = { streak = 2, lastDay = 1 },
	chargeCount = 10,
	passes = { RemoteSell = true },
	friends = 2,
}
local allOn = {
	minutes = 120,
	canAscend = true,
	groupMember = false,
	sold = true,
	sawRareBolt = true,
	sawSupercell = true,
	eventOn = true,
}
local seen = {}
local order = {}
for _ = 1, #Hints.list() + 3 do
	local id = pick(everything, allOn, seen)
	if not id then
		break
	end
	check(not seen[id], `{id} only shows once`)
	seen[id] = true
	table.insert(order, id)
end
-- (all but hiring: it's only for a player with nobody hired, tested above)
local expected = {}
for _, def in Hints.list() do
	if def.id ~= "hireResearcher" then
		table.insert(expected, def.id)
	end
end
check(#order == #expected, `every tip shows once when everything is true ({#order} of {#expected})`)
for index, id in expected do
	check(order[index] == id, `tip {index} is {id} (got {tostring(order[index])})`)
end
check(pick(everything, allOn, seen) == nil, "once all are seen, nothing more")

-- timing ----------------------------------------------------------------------------
local boots = { volts = Config.BOOTS[2].price }
local function timing(over)
	local t = table.clone(OPEN)
	for k, v in over do
		t[k] = v
	end
	return t
end
check(pick(boots, nil, nil, timing({ enabled = false })) == nil, "tips off in SETTINGS: nothing")
check(
	pick(boots, nil, nil, timing({ busy = true })) == nil,
	"busy (a panel open, catching, AFK): nothing"
)
check(pick(boots, nil, nil, timing({ quietUntil = 1001 })) == nil, "just joined: nothing yet")
check(
	pick(boots, nil, nil, timing({ quietUntil = 1000 })) == "boots",
	"after the first delay: it shows"
)
for step = 1, 4 do
	check(
		pick({ tutorialStep = step, volts = Config.BOOTS[2].price }) == nil,
		`no tips during tutorial step {step}`
	)
end
local gap = Config.HINTS.gapSeconds
check(gap >= 60, "tips are at least a minute apart")
check(
	pick(boots, nil, nil, timing({ lastShown = 1000 - gap + 1 })) == nil,
	"too soon after the last tip"
)
check(
	pick(boots, nil, nil, timing({ lastShown = 1000 - gap })) == "boots",
	"the gap is over: the next tip"
)
check(Config.HINTS.showSeconds < gap, "a tip is gone long before the next one (one at a time)")

-- sanitize ----------------------------------------------------------------------------
local clean = Hints.sanitize({ boots = true, nope = true, quests = false, [5] = true })
check(
	clean.boots == true and clean.nope == nil and clean.quests == nil and clean[5] == nil,
	"sanitize keeps known true ids"
)
check(next(Hints.sanitize("junk")) == nil, "sanitize turns junk into an empty set")

-- the migration -----------------------------------------------------------------------
local fresh = PlayerData.migrate({ version = 18, volts = 0, bottleTier = 1 })
check(fresh.version == 19, "a v18 save becomes v19")
check(
	typeof(fresh.hintsSeen) == "table" and next(fresh.hintsSeen) == nil,
	"a new-ish save has seen no tips"
)
local lifetime = {
	[Stats.visitZoneKey("Shoreline")] = 3,
	[Stats.visitZoneKey("Mesa")] = 1,
	[Stats.typeKey("Golden")] = 1,
	[Stats.SUPERCELLS_SEEN] = 1,
}
local veteran = PlayerData.migrate({
	version = 18,
	volts = 500,
	bottleTier = 4,
	bootTier = 3,
	researchers = { Forecaster = { level = 2, data = 10, post = "Mesa", rank = 1 } },
	dailyStreak = 3,
	trialUsed = true,
	logClaimed = { someRow = true },
	playtime = { day = 1, seconds = 0, claimed = { true } },
	quests = {
		day = 1,
		week = 1,
		daily = { { key = "Catch", target = 1, base = 0, claimed = true } },
		weekly = {},
		rerollDay = 0,
	},
	stats = { lifetime = lifetime, today = {}, thisWeek = {}, day = 1, week = 1 },
})
for _, id in
	{
		"boots",
		"newZone",
		"hireResearcher",
		"postResearcher",
		"promote",
		"glints",
		"stormLog",
		"dailyStreak",
		"playtimeGifts",
		"quests",
		"boosts",
		"rareBolt",
		"supercell",
	}
do
	check(veteran.hintsSeen[id] == true, `a player who has used it doesn't get the {id} tip`)
end
for _, id in
	{ "portal", "ascend", "settings", "invite", "leaderboards", "afkLounge", "group", "event" }
do
	check(veteran.hintsSeen[id] == nil, `but still gets the {id} tip`)
end
local fromOld = PlayerData.migrate({ version = 1, volts = 0, bottleTier = 1 })
check(typeof(fromOld.hintsSeen) == "table", "a very old save gets an empty set too")

if failures > 0 then
	error(`{failures} hint checks failed`)
end
print("hint checks passed")
