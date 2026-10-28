--!nocheck
-- Movement checks (shared/Util/AntiCheat): walking, running with Jet Boots,
-- jumping and falling are fine; teleports and speed cheats make the player
-- suspect for a few seconds; moves the server makes aren't checked.
--   lune run tools/harness/test_anticheat.luau
local World = require("./World")

local world = World.new("src")
local Config = world:require("ReplicatedStorage.Shared.Config")
local AntiCheat = world:require("ReplicatedStorage.Shared.Util.AntiCheat")
local Formulas = world:require("ReplicatedStorage.Shared.Util.Formulas")

local failures = 0
local function check(condition, message)
	if not condition then
		failures += 1
		print("FAIL: " .. message)
	end
end

local RULES = Config.ANTI_CHEAT
local STEP = RULES.checkEvery

-- the real walk speeds: in a zone with the best boots, and outside with Jet Boots
local bestBoots = #Config.BOOTS
local speeds = {
	inZone = Formulas.walkSpeed(true, bestBoots, { JetBoots = true }),
	outside = Formulas.walkSpeed(false, bestBoots, { JetBoots = true }),
}
local plain = { inZone = Formulas.walkSpeed(true, 1, {}), outside = Formulas.walkSpeed(false, 1, {}) }
check(speeds.outside > plain.outside, "Jet Boots are faster outside")

-- walks in a straight line at `speed` for `seconds`; returns how many
-- steps were flagged
local function walk(track, startAt, x, speed, seconds, inZone, speedTable)
	local flagged = 0
	local t = startAt
	while t <= startAt + seconds + 1e-9 do
		if AntiCheat.step(track, { x = x + speed * (t - startAt), z = 0, at = t, inZone = inZone }, speedTable) then
			flagged += 1
		end
		t += STEP
	end
	return flagged
end

-- legit movement is never flagged
local track = AntiCheat.new()
check(walk(track, 0, 0, plain.inZone, 10, true, plain) == 0, "walking in a zone is fine")
check(walk(AntiCheat.new(), 0, 0, speeds.outside, 10, false, speeds) == 0, "running outside with Jet Boots is fine")
check(walk(AntiCheat.new(), 0, 0, speeds.inZone, 10, true, speeds) == 0, "the best boots in a zone are fine")
-- walking out of a zone at outside speed: the outside speed counts
local crossing = AntiCheat.new()
check(walk(crossing, 0, 0, plain.inZone, 2, true, plain) == 0, "walking up to a zone's edge")
check(walk(crossing, 2.2, plain.inZone * 2.2, plain.outside, 3, false, plain) == 0, "then running off outside")

-- falling and jumping: only flat distance counts
local faller = AntiCheat.new()
local flagged = 0
for i = 0, 20 do
	-- straight down 500 studs while walking: x moves at walk speed only
	if AntiCheat.step(faller, { x = plain.outside * i * STEP, z = 0, at = i * STEP, inZone = false }, plain) then
		flagged += 1
	end
end
check(flagged == 0, "falling off a cliff while walking is fine")

-- a teleport onto a ring: suspect for suspectSeconds
local cheat = AntiCheat.new()
walk(cheat, 0, 0, plain.inZone, 2, true, plain)
local t = 2 + STEP
check(AntiCheat.step(cheat, { x = 200, z = 80, at = t, inZone = true }, plain), "a 200-stud jump is impossible")
check(AntiCheat.isSuspect(cheat, t), "they're suspect straight away")
check(AntiCheat.isSuspect(cheat, t + RULES.suspectSeconds - 0.1), "for suspectSeconds")
check(not AntiCheat.isSuspect(cheat, t + RULES.suspectSeconds), "then it's over")
check(cheat.strikes == 1, "one impossible move counted")
check(not AntiCheat.step(cheat, { x = 200, z = 80, at = t + STEP, inZone = true }, plain), "it counts once, not every check after")

-- a short teleport inside a zone (40 studs) is caught too
local hop = AntiCheat.new()
walk(hop, 0, 0, 0, 2, true, plain)
check(AntiCheat.step(hop, { x = 40, z = 0, at = 2 + STEP, inZone = true }, plain), "a 40-stud hop in a zone is caught")

-- a speed cheat: twice the walk speed, kept up, is caught within the window
local fast = AntiCheat.new()
check(walk(fast, 0, 0, plain.inZone * 2, 3, true, plain) > 0, "2x walk speed in a zone is caught")
check(walk(AntiCheat.new(), 0, 0, speeds.outside * 2, 3, false, speeds) > 0, "2x Jet Boots speed outside is caught")

-- moves the server makes aren't checked for graceSeconds
local traveller = AntiCheat.new()
walk(traveller, 0, 0, plain.outside, 1, false, plain)
AntiCheat.allowMove(traveller, 1.1)
check(not AntiCheat.step(traveller, { x = 5000, z = 0, at = 1.2, inZone = false }, plain), "a portal trip isn't a cheat")
check(not AntiCheat.step(traveller, { x = 5003, z = 0, at = 1.4, inZone = false }, plain), "nor the moments after")
check(
	walk(traveller, 1.1 + RULES.graceSeconds, 5003, plain.outside, 3, false, plain) == 0,
	"walking on after the grace is fine"
)
check(not AntiCheat.isSuspect(traveller, 10), "and they were never suspect")

-- logging repeat offenders
local repeat_ = AntiCheat.new()
for i = 1, RULES.logAfter do
	AntiCheat.step(repeat_, { x = 1000 * (i - 1), z = 0, at = i * 10, inZone = false }, plain)
	AntiCheat.step(repeat_, { x = 1000 * i, z = 0, at = i * 10 + STEP, inZone = false }, plain)
	check(AntiCheat.shouldLog(repeat_) == (i >= RULES.logAfter), `logged after {RULES.logAfter} (move {i})`)
end

if failures > 0 then
	error(`{failures} anti-cheat checks failed`)
end
print("anti-cheat checks passed")
