--!nocheck
-- The menu's Teleport panel rule (shared/Util/Portals.teleportRefusal), which
-- the server checks and the panel shows: a locked world and an unlocked
-- one, an unknown world id, the world you're in, and the cooldown maths.
--   lune run tools/harness/test_teleport.luau
local World = require("./World")

local world = World.new("src")
local Config = world:require("ReplicatedStorage.Shared.Config")
local Portals = world:require("ReplicatedStorage.Shared.Util.Portals")

local failures = 0
local function check(condition, message)
	if not condition then
		failures += 1
		print("FAIL: " .. message)
	end
end

local first, second = Config.WORLDS[1], Config.WORLDS[2]
check(first ~= nil and second ~= nil, "there are at least two worlds")
local starter = { bottleTier = 1, bootTier = 1 }
local unlocked = { bottleTier = second.requiresBottle, bootTier = 1 }

-- a locked world and an unlocked world ---------------------------------------------------
local refusal, to = Portals.teleportRefusal(starter, second.id, first.id, 100, 0)
check(refusal ~= nil and to == nil, "a world you haven't unlocked refuses")
check(refusal and string.find(refusal, "Needs", 1, true) ~= nil, `it says what it needs (got {refusal})`)
refusal, to = Portals.teleportRefusal(unlocked, second.id, first.id, 100, 0)
check(refusal == nil and to ~= nil and to.id == second.id, "an unlocked world takes you there")
refusal, to = Portals.teleportRefusal(unlocked, first.id, second.id, 100, 0)
check(refusal == nil and to ~= nil and to.id == first.id, "and back to the first world")

-- an unknown world id, and the world you're in ----------------------------------------------
for _, bad in { "Atlantis", "", 42, nil, {} } do
	refusal, to = Portals.teleportRefusal(unlocked, bad, first.id, 100, 0)
	check(refusal ~= nil and to == nil, `an unknown world id ({tostring(bad)}) refuses`)
end
refusal, to = Portals.teleportRefusal(unlocked, first.id, first.id, 100, 0)
check(refusal ~= nil and to == nil, "the world you're in can't be picked")

-- the cooldown maths --------------------------------------------------------------------------
check(Config.TELEPORT_COOLDOWN >= 5 and Config.TELEPORT_COOLDOWN <= 15, "the cooldown is about 10 seconds")
local readyAt = 100 + Config.TELEPORT_COOLDOWN -- a trip at time 100
check(Portals.cooldownLeft(100, readyAt) == Config.TELEPORT_COOLDOWN, "right after a trip: the whole cooldown")
check(Portals.cooldownLeft(100.2, readyAt) == Config.TELEPORT_COOLDOWN, "part seconds round up")
check(Portals.cooldownLeft(readyAt - 0.5, readyAt) == 1, "half a second left shows 1s")
check(Portals.cooldownLeft(readyAt, readyAt) == 0, "ready on the dot")
check(Portals.cooldownLeft(readyAt + 30, readyAt) == 0, "and stays ready")
check(Portals.cooldownLeft(5, 0) == 0, "never teleported: ready")
refusal = Portals.teleportRefusal(unlocked, second.id, first.id, readyAt - 3, readyAt)
check(refusal == "Teleport ready in 3s", `cooling down refuses with the wait (got {refusal})`)
refusal = Portals.teleportRefusal(unlocked, second.id, first.id, readyAt, readyAt)
check(refusal == nil, "after the cooldown it goes")
refusal = Portals.teleportRefusal(starter, second.id, first.id, readyAt - 3, readyAt)
check(refusal and string.find(refusal, "Needs", 1, true) ~= nil, "a locked world says what it needs before the wait")

if failures > 0 then
	error(`{failures} teleport checks failed`)
end
print("teleport checks passed")
