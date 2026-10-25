--!strict
-- The 7-day login streak and playtime gifts (Config.DAILY_REWARDS and
-- PLAYTIME_GIFTS; the rules are Util/Rewards). ClaimDaily and
-- ClaimGift(index) only ask: rate-limited, and the server decides
-- everything. A day is a UTC calendar day; playtime counts from when the
-- profile loaded and starts again each visit.
-- A reward pays Volts in charges (Util/Store.volts: the player's best bolt,
-- so it's worth the same playtime early or late) and timed boosts
-- (Systems/Boosts); a boost for a pass they own pays Volts instead. The
-- Rewarded remote tells the client what came, for its celebration.
-- GroupJoined: the client says the player just joined the game's group
-- from the panel; Systems/Group checks for itself.
-- Stats (Analytics): DailyClaimed, PlaytimeGift, GroupJoined, and the
-- Volts as a TimedReward economy source.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local RewardRules = require(ReplicatedStorage.Shared.Util.Rewards)
local Store = require(ReplicatedStorage.Shared.Util.Store)
local Types = require(ReplicatedStorage.Shared.Types)
local Analytics = require(script.Parent.Analytics)
local Boosts = require(script.Parent.Boosts)
local Group = require(script.Parent.Group)
local Passes = require(script.Parent.Passes)
local PlayerData = require(script.Parent.PlayerData)
local Sync = require(script.Parent.Sync)
local RateLimit = require(ServerScriptService.Server.Lib.RateLimit)

local Rewards = {}

local rewardedRemote: RemoteEvent

-- Today's UTC day number for this player (Studio's "Next day" adds days).
local function today(player: Player): number
	local session = Sync.rewards[player]
	return RewardRules.today(os.time()) + (if session then session.dayOffset else 0)
end

-- Pays a reward (Systems/Quests uses it too). `sku` names it in the
-- economy stats ("Daily 3", "Gift 10 min").
function Rewards.give(player: Player, profile: Types.Profile, reward: Types.Reward, sku: string)
	local resolved = RewardRules.resolve(reward, Passes.owned(player))
	local volts = Store.volts(resolved.charges, profile)
	profile.volts += volts
	if volts > 0 then
		Analytics.rewardVolts(player, volts, sku)
	end
	for _, boost in resolved.boosts do
		Boosts.grant(player, boost.key, boost.minutes * 60)
	end
	Sync.markDirty(player)
	local rewarded: Types.Rewarded = {
		volts = volts,
		boosts = resolved.boosts,
		swapped = resolved.swapped,
	}
	rewardedRemote:FireClient(player, rewarded)
end

local function onClaimDaily(player: Player)
	if not RateLimit.allow(player, "ClaimDaily", 1, 3) then
		return
	end
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	local day = today(player)
	local canClaim, streak = RewardRules.daily(profile.lastDailyDay, day, profile.dailyStreak)
	if not canClaim then
		return
	end
	profile.dailyStreak = streak
	profile.lastDailyDay = day
	Rewards.give(player, profile, Config.DAILY_REWARDS[streak], `Daily {streak}`)
	Analytics.dailyClaimed(player, streak)
end

local function onClaimGift(player: Player, index: unknown)
	if not RateLimit.allow(player, "ClaimGift", 2, 4) then
		return
	end
	if
		typeof(index) ~= "number"
		or index ~= math.floor(index)
		or index < 1
		or index > #Config.PLAYTIME_GIFTS
	then
		return
	end
	local profile = PlayerData.get(player)
	local session = Sync.rewards[player]
	if not profile or not session then
		return
	end
	local gift = Config.PLAYTIME_GIFTS[index]
	local elapsed = workspace:GetServerTimeNow() - session.startedAt
	if not RewardRules.giftReady(gift, elapsed, session.claimed[index]) then
		return
	end
	session.claimed[index] = true
	Rewards.give(player, profile, gift.reward, `Gift {gift.minutes} min`)
	Analytics.giftClaimed(player, gift.minutes)
end

-- Studio TEST tools (Systems/DevCommands only calls these in Studio).
function Rewards.nextDay(player: Player)
	local session = Sync.rewards[player]
	if session then
		session.dayOffset += 1
		Sync.markDirty(player)
	end
end

function Rewards.addPlaytime(player: Player, seconds: number)
	local session = Sync.rewards[player]
	if session then
		session.startedAt -= seconds
		Sync.markDirty(player)
	end
end

local function onGroupJoined(player: Player)
	if RateLimit.allow(player, "GroupJoined", 1, 2) then
		Group.recheck(player)
	end
end

function Rewards.init()
	rewardedRemote = Net.get("Rewarded")
	Net.get("ClaimDaily").OnServerEvent:Connect(onClaimDaily)
	Net.get("ClaimGift").OnServerEvent:Connect(onClaimGift)
	Net.get("GroupJoined").OnServerEvent:Connect(onGroupJoined)
	Group.Joined:Connect(Analytics.groupJoined)
	PlayerData.Loaded:Connect(function(player: Player)
		Sync.rewards[player] = {
			startedAt = workspace:GetServerTimeNow(),
			claimed = table.create(#Config.PLAYTIME_GIFTS, false),
			dayOffset = 0,
		}
		Sync.markDirty(player)
	end)
end

return Rewards
