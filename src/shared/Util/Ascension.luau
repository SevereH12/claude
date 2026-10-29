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
local Progression = require(script.Parent.Progression)

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
	"Researchers in locked zones go to the Office",
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

-- "⭐⭐⭐" (a number after five stars, so it stays short: "⭐x12").
function Ascension.stars(level: number): string
	if level <= 0 then
		return ""
	elseif level <= 5 then
		return string.rep("⭐", level)
	end
	return `⭐x{level}`
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

-- The researchers (role ids, in Config.RESEARCHERS order) posted to a zone
-- the player couldn't enter after an Ascension (back on the first bottle):
-- they go back to the Office then, since their perks would be off anyway.
function Ascension.researchersToMove(profile: Types.Profile, premium: boolean): { string }
	local after = { bottleTier = RULES.resetTo.bottleTier, bootTier = RULES.resetTo.bootTier }
	local moving: { string } = {}
	for _, def in Config.RESEARCHERS do
		local save = profile.researchers[def.id]
		local zone = if save then Config.ZONES[save.post] else nil
		if zone and not Progression.canEnter(after, zone, premium) then
			table.insert(moving, def.id)
		end
	end
	return moving
end

-- Does the Ascension: everything in Config.ASCENSION.resetTo goes back to how
-- a new player starts, the level goes up by one, and researchers in zones
-- they can't enter any more go back to the Office (researchersToMove;
-- `premium` is whether the player is a Premium member). Nothing else in the
-- profile is touched (passes, gifts, researchers' ranks and levels, Glints,
-- quests, the Log, settings, streaks and stats all stay). Returns the new
-- level and the researchers moved, or nil if they can't ascend (and then
-- nothing changes).
function Ascension.ascend(profile: Types.Profile, premium: boolean?): (number?, { string })
	if not Ascension.canAscend(profile) then
		return nil, {}
	end
	local moving = Ascension.researchersToMove(profile, premium == true)
	local data = profile :: any
	for key, value in RULES.resetTo do
		data[key] = value
	end
	for _, roleId in moving do
		profile.researchers[roleId].post = "Office"
	end
	profile.ascension += 1
	return profile.ascension, moving
end

return Ascension
