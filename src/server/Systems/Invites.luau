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
--     is invite-<new player's id>, so it can only arrive once. It's paid
--     only once the new player has played Config.INVITES.playMinutes
--     minutes in all or made a sale (Util/Social.inviteEarned): until then
--     the inviter's id waits in the new player's profile (invitedBy), over
--     as many visits as it takes.
-- Abuse limits: the inviter's reward needs the new player's account to be
-- at least Config.INVITES.minAccountAgeDays old, and an inviter is rewarded
-- at most Config.INVITES.dailyCap times a UTC day: counted in DataStore
-- StormBottler_Invites (key inviter_<userId>, UpdateAsync only). Studio
-- without API access keeps the counts in memory.
-- Every decision is logged ("[Invites] ...") so it can be checked in the
-- output: Studio can't make real invites.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local SocialRules = require(ReplicatedStorage.Shared.Util.Social)
local Types = require(ReplicatedStorage.Shared.Types)
local Gifts = require(script.Parent.Gifts)
local PlayerData = require(script.Parent.PlayerData)
local Rewards = require(script.Parent.Rewards)

local STORE_NAME = "StormBottler_Invites"
local DAY = 86400
local CHECK_INTERVAL = 15 -- seconds between checks of invited players' playtime

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

-- Pays the inviter (once the new player has played enough): counts it in
-- today's cap, then sends the boost to their gift inbox.
local function payInviter(player: Player, inviterId: number)
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

-- An invited player whose inviter is waiting (profile.invitedBy): pay the
-- inviter once they've played enough (Util/Social.inviteEarned). It's
-- saved, so it carries on over later visits.
local function checkWaiting(player: Player, profile: Types.Profile)
	local inviterId = profile.invitedBy
	if inviterId == 0 or not SocialRules.inviteEarned(profile.stats.lifetime) then
		return
	end
	profile.invitedBy = 0 -- before anything yields: paid once
	print(`[Invites] {player.Name} has played enough: rewarding user {inviterId}`)
	task.spawn(payInviter, player, inviterId)
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
	profile.invitedBy = inviterId
	print(
		`[Invites] user {inviterId} is rewarded once {player.Name} plays {Config.INVITES.playMinutes} minutes or sells`
	)
end

function Invites.init()
	PlayerData.Loaded:Connect(function(player: Player, profile: Types.Profile)
		task.spawn(onLoaded, player, profile)
	end)
end

function Invites.start()
	while true do
		task.wait(CHECK_INTERVAL)
		for _, player in Players:GetPlayers() do
			local profile = PlayerData.get(player)
			if profile then
				checkWaiting(player, profile)
			end
		end
	end
end

return Invites
