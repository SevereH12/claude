--!strict
-- Invite rewards (the rules: Util/Social; the INVITE button is in the
-- REWARDS panel, Controllers/RewardsUI, which opens Roblox's own invite
-- window with SocialService on the client).
--
-- When a brand-new player (no saved profile yet: PlayerData.isNew) joins
-- from an invite, Player:GetJoinData().ReferredByPlayerId says who invited
-- them. Then:
--   * the new player gets a welcome gift: Config.INVITES.welcomeCharges
--     charges (Systems/Rewards, which celebrates it)
--   * the inviter gets Config.INVITES.inviterReward (a boost) through their
--     gift inbox (Systems/Gifts.sendReward), so it reaches them here, in
--     another server, or on their next join if they're offline. Its inbox id
--     is invite-<new player's id>, so it can only arrive once.
-- Abuse limits: the inviter's reward needs the new player's account to be
-- at least Config.INVITES.minAccountAgeDays old, and an inviter is rewarded
-- at most Config.INVITES.dailyCap times a UTC day: counted in DataStore
-- StormBottler_Invites (key inviter_<userId>, UpdateAsync only). Studio
-- without API access keeps the counts in memory.
-- Every decision is logged ("[Invites] ...") so it can be checked in the
-- output: Studio can't make real invites.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local SocialRules = require(ReplicatedStorage.Shared.Util.Social)
local Types = require(ReplicatedStorage.Shared.Types)
local Gifts = require(script.Parent.Gifts)
local PlayerData = require(script.Parent.PlayerData)
local Rewards = require(script.Parent.Rewards)

local STORE_NAME = "StormBottler_Invites"
local DAY = 86400

local Invites = {}

local storeOk, storeResult = pcall(function()
	return DataStoreService:GetDataStore(STORE_NAME)
end)
local store: DataStore? = if storeOk then storeResult else nil
local memory: { [string]: any } = {} -- Studio without API access

-- Counts the invite in the inviter's daily record: true if it's within
-- today's cap (and wasn't counted before), false if not or it couldn't be
-- written.
local function countInvite(inviterId: number, newUserId: number): boolean
	local key = `inviter_{inviterId}`
	local today = os.time() // DAY
	local dataStore = store
	local allowed = false
	if dataStore then
		local ok, err = pcall(function()
			dataStore:UpdateAsync(key, function(old: any): any
				local record, counted = SocialRules.countInvite(old, today, newUserId)
				allowed = counted
				return if counted then record else nil
			end)
		end)
		if ok then
			return allowed
		end
		warn(`[Invites] couldn't count the invite (using this server's memory): {err}`)
	end
	local record, counted = SocialRules.countInvite(memory[key], today, newUserId)
	memory[key] = record
	return counted
end

local function onLoaded(player: Player, profile: Types.Profile)
	local ok, joinData = pcall(function()
		return player:GetJoinData()
	end)
	local referrer = if ok and typeof(joinData) == "table" then joinData.ReferredByPlayerId else nil
	local join: SocialRules.Join = {
		isNew = PlayerData.isNew(player),
		userId = player.UserId,
		referrerId = referrer,
		accountAge = player.AccountAge,
	}
	local refusal = SocialRules.welcomeRefusal(join)
	if refusal == "notInvited" then
		return
	elseif refusal then
		print(`[Invites] {player.Name} joined from an invite: no rewards ({refusal})`)
		return
	end
	local inviterId = referrer :: number
	print(`[Invites] {player.Name} is new and was invited by user {inviterId}`)
	Rewards.give(player, profile, { charges = Config.INVITES.welcomeCharges }, "Invite welcome")

	local inviterRefusal = SocialRules.inviterRefusal(join)
	if inviterRefusal then
		print(`[Invites] no reward for user {inviterId} ({inviterRefusal})`)
		return
	end
	if not countInvite(inviterId, player.UserId) then
		print(`[Invites] no reward for user {inviterId} (today's limit, or counted already)`)
		return
	end
	local entry: Types.GiftEntry = {
		id = SocialRules.inviteGiftId(player.UserId),
		kind = "boost",
		key = Config.INVITES.inviterReward,
		fromId = player.UserId,
		fromName = `{player.DisplayName} (your invite)`,
		time = os.time(),
	}
	if Gifts.sendReward(inviterId, entry) then
		print(`[Invites] reward sent to user {inviterId}'s gift inbox`)
	else
		warn(`[Invites] couldn't send user {inviterId}'s reward`)
	end
end

function Invites.init()
	PlayerData.Loaded:Connect(function(player: Player, profile: Types.Profile)
		task.spawn(onLoaded, player, profile)
	end)
end

return Invites
