--!strict
-- Ascension (rebirth), as pure rules (Systems/Ascension does it for real;
-- tools/harness/test_quests.luau tests this). Once you own the top bottle and
-- have enough Volts, you can start again from the beginning: your Volts,
-- bottle, boots, bottle contents and Chemist's tank go back to how a new
-- player starts, and in return every sale pays +50% more for good, per
-- Ascension level (added up: level 3 = +150%). The bonus goes through
-- Passes.sellMultiplier, so the AFK Lounge, quests and everything else that
-- works out Volts follow by themselves.

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)
local Format = require(script.Parent.Format)

-- What the rules read: a server Profile or a client Snapshot both have these.
export type Progress = { volts: number, bottleTier: number, ascension: number }

local RULES = Config.ASCENSION

local Ascension = {}

-- Player attribute everyone can read: the player's Ascension level (the
-- name tag's stars).
Ascension.ATTRIBUTE = "Ascension"

-- The confirm screen's two lists, in plain words.
Ascension.RESETS = table.freeze({
	"Your Volts",
	"Your bottle (back to the Jar)",
	"Your boots (back to Rain Boots)",
	"The charges in your bottle and tank",
	"You go back to Barometer Bay",
})
Ascension.KEEPS = table.freeze({
	"Game passes and gifts",
	"Researchers, their ranks and levels",
	"Glints",
	"Quests and the Storm Log",
	"Settings and reward streaks",
})

-- The top bottle's tier (the one you need to own).
function Ascension.topTier(): number
	return #Config.BOTTLES
end

-- Volts needed to go from `level` to the next level: baseCost x (level + 1).
function Ascension.cost(level: number): number
	return RULES.baseCost * (level + 1)
end

-- The extra Volts per sale at `level` (0.5 per level: 1.5 = +150%).
function Ascension.bonus(level: number): number
	return level * RULES.perLevel
end

-- "+150%": the bonus as a percentage.
function Ascension.bonusText(level: number): string
	return `+{math.floor(Ascension.bonus(level) * 100 + 0.5)}%`
end

-- "★★★" (a number after five stars, so it stays short: "★×12").
function Ascension.stars(level: number): string
	if level <= 0 then
		return ""
	elseif level <= 5 then
		return string.rep("★", level)
	end
	return `★×{level}`
end

-- Can they ascend now? If not, the reason in plain words.
function Ascension.canAscend(progress: Progress): (boolean, string?)
	local top = Ascension.topTier()
	if progress.bottleTier < top then
		return false, `Own the {Config.BOTTLES[top].name} first`
	end
	local cost = Ascension.cost(progress.ascension)
	if progress.volts < cost then
		return false, `Needs {Format.abbreviate(cost)} Volts`
	end
	return true, nil
end

-- Does the Ascension: everything in Config.ASCENSION.resetTo goes back to how
-- a new player starts, and the level goes up by one. Nothing else in the
-- profile is touched (passes, gifts, researchers, Glints, quests, the Log,
-- settings, streaks and stats all stay). Returns the new level, or nil if
-- they can't ascend (and then nothing changes).
function Ascension.ascend(profile: Types.Profile): number?
	if not Ascension.canAscend(profile) then
		return nil
	end
	local data = profile :: any
	for key, value in RULES.resetTo do
		data[key] = value
	end
	profile.ascension += 1
	return profile.ascension
end

return Ascension
