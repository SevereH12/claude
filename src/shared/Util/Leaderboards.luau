--!strict
-- The leaderboard rules (Systems/Leaderboards uses them, the TOP tab and
-- the board at the spawn show them; tools/harness/test_social.luau tests
-- them). Pure: no Roblox services.
--
-- The boards are Config.LEADERBOARDS.boards:
--   volts: all-time Volts earned (profile.totalVolts, never reset)
--   bolts: bolts caught, ever (the boltsCaught stat counter)
--   ascension: the Ascension level
--   streak: the longest login run (days in a row with a daily claim)

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)
local Format = require(script.Parent.Format)
local Stats = require(script.Parent.Stats)

local Leaderboards = {}

-- The part at world 1's spawn that shows the top Volts (World/Kit builds
-- it; Systems/Leaderboards writes its rows).
Leaderboards.BOARD_TAG = "LeaderboardBoard"

export type BoardDef = { key: string, title: string, icon: string }

-- A board's definition by key, or nil.
function Leaderboards.def(key: string): BoardDef?
	for _, board in Config.LEADERBOARDS.boards do
		if board.key == key then
			return board
		end
	end
	return nil
end

-- What a profile scores on a board: a whole number, 0 or more (an
-- OrderedDataStore only keeps whole numbers).
function Leaderboards.value(profile: Types.Profile, key: string): number
	local value = 0
	if key == "volts" then
		value = profile.totalVolts
	elseif key == "bolts" then
		value = Stats.get(profile.stats.lifetime, Stats.BOLTS)
	elseif key == "ascension" then
		value = profile.ascension
	elseif key == "streak" then
		value = profile.bestLoginRun
	end
	if value ~= value or value < 0 then
		return 0
	end
	return math.floor(math.min(value, 2 ^ 53))
end

-- Every board's value for a profile.
function Leaderboards.values(profile: Types.Profile): { [string]: number }
	local values: { [string]: number } = {}
	for _, board in Config.LEADERBOARDS.boards do
		values[board.key] = Leaderboards.value(profile, board.key)
	end
	return values
end

-- Should a value be written now? Only when it changed since the last write
-- (`last`, nil = never written), and then only once `interval` seconds have
-- passed since that write (`force`: the player is leaving, write it now).
function Leaderboards.shouldWrite(
	value: number,
	last: number?,
	lastAt: number,
	now: number,
	interval: number,
	force: boolean
): boolean
	if value == last then
		return false
	end
	if value == 0 and last == nil then
		return false -- nothing to show yet: don't fill the board with zeros
	end
	return force or now - lastAt >= interval
end

-- Seconds to wait before retry `attempt` (1, 2, 4, 8... up to 30).
function Leaderboards.backoff(attempt: number): number
	return math.min(2 ^ (attempt - 1), 30)
end

-- A player's place on a board (1 = top), or nil if they aren't in it.
function Leaderboards.rankOf(entries: { Types.LeaderboardEntry }, userId: number): number?
	for rank, entry in entries do
		if entry.userId == userId then
			return rank
		end
	end
	return nil
end

-- A value as a board shows it: "1.2M ⚡", "3,402" bolts, "⭐3", "12 days".
function Leaderboards.format(key: string, value: number): string
	if key == "volts" then
		return `{Format.abbreviate(value)} ⚡`
	elseif key == "streak" then
		return if value == 1 then "1 day" else `{value} days`
	elseif key == "ascension" then
		return `⭐{value}`
	end
	return Format.abbreviate(value)
end

-- The "You:" line under a board: "You: #7 · 1.2M ⚡", or "You: not in the
-- top 50 · 1.2K ⚡".
function Leaderboards.youText(
	entries: { Types.LeaderboardEntry },
	userId: number,
	key: string,
	mine: number
): string
	local rank = Leaderboards.rankOf(entries, userId)
	local value = Leaderboards.format(key, mine)
	if rank then
		return `You: #{rank} · {value}`
	end
	return `You: not in the top {Config.LEADERBOARDS.top} · {value}`
end

return Leaderboards
