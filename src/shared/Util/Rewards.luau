--!strict
-- The rules for the login streak and playtime gifts (Systems/Rewards
-- applies them; tools/harness/test_rewards.luau tests them). Pure: no
-- Roblox services.

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)
local Boosts = require(script.Parent.Boosts)

local Rewards = {}

local DAY = 24 * 60 * 60

-- Today as a UTC day number (a new day starts at midnight UTC).
function Rewards.today(unixTime: number): number
	return unixTime // DAY
end

-- Seconds until the next UTC day.
function Rewards.untilNextDay(unixTime: number): number
	return DAY - unixTime % DAY
end

-- May the player claim today's daily reward, and which streak day is it?
-- `lastClaimDay` and `streak` are what they last claimed (0 = never):
-- the day after a claim continues the streak, a missed day starts again at
-- day 1, and so does the day after day 7. Already claimed today: no.
function Rewards.daily(lastClaimDay: number, today: number, streak: number): (boolean, number)
	if lastClaimDay == today then
		return false, streak
	end
	if lastClaimDay == today - 1 and streak >= 1 and streak < #Config.DAILY_REWARDS then
		return true, streak + 1
	end
	return true, 1
end

-- The login run after claiming on `today`: days in a row with a claim.
-- Unlike the 7-day streak it keeps counting past day 7 (the "Longest
-- streak" leaderboard); a missed day starts it again at 1.
function Rewards.loginRun(lastClaimDay: number, today: number, run: number): number
	if lastClaimDay == today then
		return run
	end
	if lastClaimDay == today - 1 and run >= 1 then
		return run + 1
	end
	return 1
end

-- May this playtime gift be claimed, `elapsed` seconds into the session?
function Rewards.giftReady(gift: Types.PlaytimeGift, elapsed: number, claimed: boolean): boolean
	return not claimed and elapsed >= gift.minutes * 60
end

-- What a reward really gives a player who owns `owned` (pass keys): a boost
-- for a pass they own would add nothing, so it pays charges instead
-- (Config.REWARD_SWAP_CHARGES per minute). `swapped` lists those boosts.
export type Resolved = { charges: number, boosts: { Types.RewardBoost }, swapped: { string } }

function Rewards.resolve(reward: Types.Reward, owned: { [string]: boolean }): Resolved
	local charges = reward.charges or 0
	local boosts: { Types.RewardBoost } = {}
	local swapped: { string } = {}
	for _, boost in reward.boosts or {} do
		local def = Boosts.def(boost.key)
		if def and owned[def.pass] then
			charges += boost.minutes * Config.REWARD_SWAP_CHARGES
			table.insert(swapped, boost.key)
		else
			table.insert(boosts, boost)
		end
	end
	return { charges = charges, boosts = boosts, swapped = swapped }
end

return Rewards
