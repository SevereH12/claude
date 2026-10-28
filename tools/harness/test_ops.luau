--!nocheck
-- Launch and operations (prompt 18 part A): who is an admin (Util/Ops),
-- error fingerprints, the panel's small helpers and rate windows, and that
-- the built map turns streaming on with everything gameplay needs
-- everywhere inside a Persistent model.
--   lune run tools/harness/test_ops.luau
local World = require("./World")
local Enum = require("@lune/roblox").Enum

local world = World.new("src")
local Config = world:require("ReplicatedStorage.Shared.Config")
local Ops = world:require("ReplicatedStorage.Shared.Util.Ops")

local failures = 0
local function check(condition, message)
	if not condition then
		failures += 1
		print("FAIL: " .. message)
	end
end

-- who is an admin ----------------------------------------------------------------
local OWNER = 1001
check(Config.ADMIN_RANK == 200, "admins are rank 200 and up")
check(Ops.isAdmin({ studio = true, userId = -1 }), "everyone is an admin in Studio")
check(Ops.isAdmin({ studio = false, userId = 5, rank = 200 }), "rank 200 is an admin")
check(Ops.isAdmin({ studio = false, userId = 5, rank = 255 }), "rank 255 is an admin")
check(not Ops.isAdmin({ studio = false, userId = 5, rank = 199 }), "rank 199 is not an admin")
check(not Ops.isAdmin({ studio = false, userId = 5, rank = 0 }), "a non-member is not an admin")
check(not Ops.isAdmin({ studio = false, userId = 5 }), "an unknown rank is not an admin")
check(
	Ops.isAdmin({ studio = false, userId = OWNER, groupOwnerId = OWNER, rank = 0 }),
	"the group's owner is an admin even if the rank check failed"
)
check(
	Ops.isAdmin({ studio = false, userId = OWNER, placeOwnerId = OWNER, rank = 0 }),
	"the place's owner is an admin"
)
check(
	not Ops.isAdmin({ studio = false, userId = 5, groupOwnerId = OWNER, placeOwnerId = OWNER, rank = 10 }),
	"someone else isn't an admin because the owner is"
)
check(not Ops.isAdmin({ studio = false, userId = -1, rank = 255 }), "a guest is never an admin outside Studio")

-- error fingerprints --------------------------------------------------------------
local a = Ops.fingerprint(
	"ServerScriptService.Server.Systems.Shop",
	"ServerScriptService.Server.Systems.Shop:120: attempt to index nil with 'Price'\nStack Begin"
)
local b = Ops.fingerprint(
	"ServerScriptService.Server.Systems.Shop",
	"ServerScriptService.Server.Systems.Shop:131: attempt to index nil with 'Price'"
)
check(a == b, `the same error on another line is one fingerprint ({a} / {b})`)
check(a == "Shop: attempt to index nil with 'Price'", `fingerprint is script + message: {a}`)
check(not string.find(a, "%d"), "fingerprints have no numbers")
check(not string.find(a, "\n"), "fingerprints are one line")
local henry = Ops.fingerprint(
	"Shop",
	"Players.Henry.PlayerScripts.Client.Controllers.ShopUI:44: bad argument #2 to 'clamp'"
)
local sam = Ops.fingerprint(
	"Shop",
	"Players.Sam_99.PlayerScripts.Client.Controllers.ShopUI:44: bad argument #2 to 'clamp'"
)
check(henry == sam, `a client error is one fingerprint for every player ({henry} / {sam})`)
check(not string.find(henry, "Henry"), "player names are taken out")
local counted = Ops.fingerprint("Strikes", "Strikes:9: spent 1234 of 5000 Volts")
check(counted == Ops.fingerprint("Strikes", "Strikes:10: spent 77 of 12 Volts"), "counts are taken out")
check(
	Ops.fingerprint("Shop", "boom") ~= Ops.fingerprint("Strikes", "boom"),
	"the same message in two scripts is two fingerprints"
)
check(
	Ops.fingerprint("Shop", "boom") ~= Ops.fingerprint("Shop", "bang"),
	"two messages in one script are two fingerprints"
)
local long = Ops.fingerprint("Shop", string.rep("x", 500))
check(#long <= 100, "fingerprints are short")
check(Ops.fingerprint("", "boom") == "?: boom", "a missing script name still works")

-- panel helpers --------------------------------------------------------------------
local name, id = Ops.parseTarget("  Henry_12 ")
check(name == "Henry_12" and id == nil, "a username is trimmed")
name, id = Ops.parseTarget("123456")
check(name == "123456" and id == 123456, "digits are a user id")
check(Ops.parseTarget("ab") == nil, "too short for a username")
check(Ops.parseTarget("bad name!") == nil, "spaces and symbols are refused")
check(Ops.parseTarget(42) == nil, "only text is a target")
check(Ops.cleanReason("  spam\nspam  ") == "spam spam", "reasons are one trimmed line")
check(#Ops.cleanReason(string.rep("a", 999)) == Config.ADMIN.reasonLength, "reasons are cut short")
check(Ops.cleanReason(nil) == nil, "a missing reason is nil")
check(Ops.banLabel(3600) == "1 hour" and Ops.banLabel(86400) == "1 day", "ban lengths read well")
check(Ops.banLabel(7 * 86400) == "7 days" and Ops.banLabel(-1) == "forever", "long bans read well")
for _, seconds in Config.ADMIN.banSeconds do
	check(Ops.isBanLength(seconds), `{seconds} s is a ban length`)
end
check(not Ops.isBanLength(5), "made-up ban lengths are refused")
check(not Ops.isBanLength("3600"), "ban lengths are numbers")
local lines = Ops.summary({ volts = 12, name = "x", boosts = { a = 1, b = 2 }, on = true }, 10)
check(#lines == 4 and lines[1] == "boosts: 2 entries", "the lookup lists keys in order")
check(table.find(lines, "volts: 12") ~= nil, "numbers show as they are")
check(#Ops.summary({ a = 1, b = 2, c = 3 }, 2) == 2, "the lookup stops at its line limit")

-- rate windows: 5 a minute per player, 300 a minute per server ---------------------
local perPlayer = Ops.newWindow(Config.ERRORS.perPlayer, 60)
local sent = 0
for _ = 1, 20 do
	if Ops.allow(perPlayer, 10) then
		sent += 1
	end
end
check(sent == 5, `5 client errors a minute per player (sent {sent})`)
check(not Ops.allow(perPlayer, 69), "still full before the minute is up")
check(Ops.allow(perPlayer, 70.5), "a new minute lets more through")
local perServer = Ops.newWindow(Config.ERRORS.perServer, 60)
sent = 0
for i = 1, 1000 do
	if Ops.allow(perServer, i * 0.01) then
		sent += 1
	end
end
check(sent == 300, `300 client errors a minute per server (sent {sent})`)

-- spam caps on what goes to Analytics (Systems/Errors)
local maxReported, maxClient = Config.ERRORS.maxReported, Config.ERRORS.maxClientReports
check(Ops.mayReport("client", 0, 0) and Ops.mayReport("server", 0, 0), "the first errors are sent")
check(not Ops.mayReport("client", maxClient, maxClient), `no more than {maxClient} client errors`)
check(Ops.mayReport("server", maxClient, maxClient), "server errors still go after the client cap")
check(not Ops.mayReport("server", maxReported, 0), `no more than {maxReported} in all`)
local reportedCount, clientCount = 0, 0
for _ = 1, 10000 do
	if Ops.mayReport("client", reportedCount, clientCount) then
		reportedCount += 1
		clientCount += 1
	end
end
check(clientCount == maxClient, `a flood of made-up client errors sends {maxClient} (sent {clientCount})`)

-- streaming: the built map ---------------------------------------------------------
local MapBuilder = world:require("ServerScriptService.Server.Lib.MapBuilder")
local map = MapBuilder.build()
world:normalizeParts()
local workspace = world.workspace
check(workspace.StreamingEnabled == true, "MapBuilder turns streaming on")
check(workspace.StreamingMinRadius == Config.STREAMING.minRadius, "streaming min radius is set")
check(workspace.StreamingTargetRadius == Config.STREAMING.targetRadius, "streaming target radius is set")

local function persistent(instance)
	local node = instance.Parent
	while node do
		if node:IsA("Model") and node.ModelStreamingMode == Enum.ModelStreamingMode.Persistent then
			return true
		end
		node = node.Parent
	end
	return false
end
local counts = {}
for _, tag in { "SellArea", "ResearchOffice", "Portal", "AfkZone" } do
	counts[tag] = 0
end
for _, inst in map:GetDescendants() do
	for tag in counts do
		if inst:HasTag(tag) then
			counts[tag] += 1
			check(persistent(inst), `{inst:GetFullName()} ({tag}) is in a Persistent model`)
		end
	end
end
for tag, count in counts do
	check(count > 0, `the map has {tag} boxes`)
end
for _, name in { "Zones", "ResearchCamps", "ZoneGates" } do
	local container = map:FindFirstChild(name)
	check(
		container and container.ModelStreamingMode == Enum.ModelStreamingMode.Persistent,
		`Map.{name} is Persistent`
	)
end

if failures > 0 then
	print(`test_ops: {failures} failure(s)`)
	error("ops tests failed")
end
print("test_ops: all checks passed")
