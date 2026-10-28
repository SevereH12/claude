--!strict
-- Movement checks, as pure rules (Systems/AntiCheat runs them on every
-- player; tools/harness/test_anticheat.luau tests them). No Roblox services.
--
-- The client moves its own character, so a cheat script can teleport it
-- (onto a lightning ring before the bolt lands) or make it run faster.
-- The server can't stop that, but it can notice it: it keeps a few of each
-- player's recent positions (flat: x and z, so falling and jumping never
-- count), and compares where they are now with where they were about
-- Config.ANTI_CHEAT.windowSeconds ago. Further than they could walk in
-- that time (with some slack for lag) is an impossible move: for a few
-- seconds they're "suspect" and can't catch or sell.
--
-- Walk speed is the player's in-zone speed when both positions are in a
-- storm zone, and their (faster) outside speed otherwise, so Jet Boots and
-- the boots' speed bonus are allowed for. Moves the server makes itself
-- (Track.allowMove) aren't checked for graceSeconds.

local Config = require(script.Parent.Parent.Config)

local RULES = Config.ANTI_CHEAT

-- One position seen by the server: flat coordinates, the time (seconds),
-- and whether it was inside a storm zone.
export type Sample = { x: number, z: number, at: number, inZone: boolean }

-- The player's walk speeds right now (Util/Formulas.walkSpeed).
export type Speeds = { inZone: number, outside: number }

export type Track = {
	samples: { Sample }, -- oldest first, about windowSeconds of them
	graceUntil: number, -- the server moved them: nothing is checked until then
	suspectUntil: number, -- an impossible move: no catching or selling until then
	strikes: number, -- impossible moves so far
}

local AntiCheat = {}

function AntiCheat.new(): Track
	return { samples = {}, graceUntil = -math.huge, suspectUntil = -math.huge, strikes = 0 }
end

-- The server is moving this player (a portal, a teleport, the lounge, a
-- respawn, the zone lock): don't check them for graceSeconds.
function AntiCheat.allowMove(track: Track, now: number)
	track.graceUntil = math.max(track.graceUntil, now + RULES.graceSeconds)
	table.clear(track.samples)
end

-- The furthest a player walking at `speed` may get in `seconds`.
function AntiCheat.allowedDistance(speed: number, seconds: number): number
	return speed * math.max(seconds, 0) * RULES.slack + RULES.extraStuds
end

-- Adds a position the server just saw. True if it's an impossible move
-- (then the player is suspect for suspectSeconds).
function AntiCheat.step(track: Track, sample: Sample, speeds: Speeds): boolean
	local samples = track.samples
	if sample.at < track.graceUntil then
		table.clear(samples)
		table.insert(samples, sample)
		return false
	end
	-- forget samples older than the window, but keep the newest of those
	-- (the one about windowSeconds ago, to compare with)
	while #samples >= 2 and sample.at - samples[2].at >= RULES.windowSeconds do
		table.remove(samples, 1)
	end
	local from = samples[1]
	table.insert(samples, sample)
	if not from then
		return false
	end
	local speed = if from.inZone and sample.inZone then speeds.inZone else speeds.outside
	local distance = math.sqrt((sample.x - from.x) ^ 2 + (sample.z - from.z) ^ 2)
	if distance <= AntiCheat.allowedDistance(speed, sample.at - from.at) then
		return false
	end
	track.suspectUntil = sample.at + RULES.suspectSeconds
	track.strikes += 1
	-- start again from here, so one teleport counts once
	table.clear(samples)
	table.insert(samples, sample)
	return true
end

-- May this player catch and sell right now? (Not while suspect.)
function AntiCheat.isSuspect(track: Track, now: number): boolean
	return now < track.suspectUntil
end

-- Should this impossible move go in the admin panel's list?
function AntiCheat.shouldLog(track: Track): boolean
	return track.strikes >= RULES.logAfter
end

return AntiCheat
