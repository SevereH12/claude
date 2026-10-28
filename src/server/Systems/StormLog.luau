--!strict
-- The Storm Log (the rules are Util/StormLog; it's worked out from the
-- stat counters in Systems/Stats). The client only asks: ClaimLogRow(rowId)
-- pays a finished row's reward once. It's rate-limited and checked here,
-- and pays through Systems/Rewards like a quest. The +2% Volts per finished
-- page needs nothing here: Systems/Passes adds it to every sale.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Net = require(ReplicatedStorage.Shared.Net)
local StormLogRules = require(ReplicatedStorage.Shared.Util.StormLog)
local Types = require(ReplicatedStorage.Shared.Types)
local PlayerData = require(script.Parent.PlayerData)
local Rewards = require(script.Parent.Rewards)
local Sync = require(script.Parent.Sync)
local RateLimit = require(ServerScriptService.Server.Lib.RateLimit)

local MAX_ROW_ID = 64 -- characters; every real row id is shorter

local StormLog = {}

local function foundFor(profile: Types.Profile): StormLogRules.Found
	return StormLogRules.found(profile.stats.lifetime, profile.researchers)
end

local function onClaim(player: Player, rowId: unknown)
	if not RateLimit.allow(player, "ClaimLogRow", 2, 4) then
		return
	end
	if typeof(rowId) ~= "string" or #rowId > MAX_ROW_ID then
		return
	end
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	local reward = StormLogRules.claim(profile.logClaimed, rowId, foundFor(profile))
	if not reward then
		return
	end
	Rewards.give(player, profile, reward, `Log {rowId}`)
	Sync.markDirty(player)
	print(`[StormLog] {player.Name} claimed row {rowId}`)
end

function StormLog.init()
	Net.get("ClaimLogRow").OnServerEvent:Connect(onClaim)
end

return StormLog
