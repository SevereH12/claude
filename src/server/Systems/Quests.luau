--!strict
-- Daily and weekly quests (the rules are Util/Quests; counters are
-- Systems/Stats). The client only asks: ClaimQuest(period, index) pays a
-- finished quest's reward, RerollQuest(period, index) uses today's free
-- reroll on an unfinished one. Both are rate-limited and checked here.
-- Rewards pay through Systems/Rewards (charges and boosts, and the Rewarded
-- celebration), like the daily streak.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Net = require(ReplicatedStorage.Shared.Net)
local QuestRules = require(ReplicatedStorage.Shared.Util.Quests)
local Rewards = require(script.Parent.Rewards)
local Stats = require(script.Parent.Stats)
local Sync = require(script.Parent.Sync)
local RateLimit = require(ServerScriptService.Server.Lib.RateLimit)

local Quests = {}

-- "daily" or "weekly" and a whole-number index, or nil.
local function readArgs(period: unknown, index: unknown): (QuestRules.Period?, number)
	if period ~= "daily" and period ~= "weekly" then
		return nil, 0
	end
	if typeof(index) ~= "number" or index ~= math.floor(index) or index < 1 or index > 10 then
		return nil, 0
	end
	return period :: QuestRules.Period, index
end

local function onClaim(player: Player, rawPeriod: unknown, rawIndex: unknown)
	if not RateLimit.allow(player, "ClaimQuest", 2, 4) then
		return
	end
	local period, index = readArgs(rawPeriod, rawIndex)
	local profile = Stats.refresh(player)
	if not period or not profile then
		return
	end
	local quest = QuestRules.claim(profile.quests, profile.stats, period, index)
	if not quest then
		return
	end
	local sku = if period == "weekly" then `Weekly quest {quest.key}` else `Quest {quest.key}`
	Rewards.give(player, profile, QuestRules.reward(quest.key, period), sku)
	print(`[Quests] {player.Name} claimed {period} quest {index} ({quest.key})`)
end

local function onReroll(player: Player, rawPeriod: unknown, rawIndex: unknown)
	if not RateLimit.allow(player, "RerollQuest", 1, 3) then
		return
	end
	local period, index = readArgs(rawPeriod, rawIndex)
	local profile = Stats.refresh(player)
	if not period or not profile then
		return
	end
	if
		QuestRules.reroll(
			profile.quests,
			profile.stats,
			period,
			index,
			player.UserId,
			Stats.today(player),
			profile,
			next(profile.researchers) ~= nil
		)
	then
		Sync.markDirty(player)
	end
end

-- Studio TEST "complete quest" (Systems/DevCommands only calls it in Studio).
function Quests.testComplete(player: Player): boolean
	local profile = Stats.refresh(player)
	if not profile or not QuestRules.testComplete(profile.quests, profile.stats) then
		return false
	end
	Sync.markDirty(player)
	return true
end

function Quests.init()
	Net.get("ClaimQuest").OnServerEvent:Connect(onClaim)
	Net.get("RerollQuest").OnServerEvent:Connect(onReroll)
end

return Quests
