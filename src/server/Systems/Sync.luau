--!strict
-- Sends each player their latest state. Systems that change a profile call
-- Sync.markDirty(player); changes are batched: checked 10 times a second,
-- but each player gets at most MAX_SENDS_PER_SECOND snapshots a second
-- (the snapshot is big, and in a busy storm every catch marks it dirty).
-- Also keeps the Volts leaderboard stat up to date.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local AscensionRules = require(ReplicatedStorage.Shared.Util.Ascension)
local Types = require(ReplicatedStorage.Shared.Types)
local Formulas = require(ReplicatedStorage.Shared.Util.Formulas)
local GiftRules = require(ReplicatedStorage.Shared.Util.Gifts)
local PassRules = require(ReplicatedStorage.Shared.Util.Passes)
local Progression = require(ReplicatedStorage.Shared.Util.Progression)
local QuestRules = require(ReplicatedStorage.Shared.Util.Quests)
local RewardRules = require(ReplicatedStorage.Shared.Util.Rewards)
local StormLogRules = require(ReplicatedStorage.Shared.Util.StormLog)
local PlayerData = require(script.Parent.PlayerData)

local FLUSH_INTERVAL = 0.1
local MAX_SENDS_PER_SECOND = 4

local dirty: { [Player]: boolean } = {}
local lastSent: { [Player]: number } = {} -- os.clock() of the last snapshot

local Sync = {}

-- Owned by Systems/Research: per player, role id -> set-up-done time
-- (workspace:GetServerTimeNow()). Sent in the snapshot for the Research panel.
Sync.setupUntil = {} :: { [Player]: { [string]: number } }

-- Owned by Systems/Passes: per player, the Game Passes they own (key set),
-- and this session's store numbers (the free trial, 2x Volts tallies).
Sync.passes = {} :: { [Player]: PassRules.Owned }
Sync.store = {} :: { [Player]: Types.StoreSession }

-- Owned by Systems/Rewards: per player, this session's playtime gifts.
Sync.rewards = {} :: { [Player]: Types.RewardSession }

-- Owned by Systems/Afk: per player in the AFK Lounge, its state.
Sync.afk = {} :: { [Player]: Types.AfkState }

-- Owned by Systems/Friends: per player, how many of their Roblox friends
-- are in this server.
Sync.friends = {} :: { [Player]: number }

local NO_STORE: Types.StoreSession = table.freeze({ boostEarned = 0, missedDouble = 0 })

function Sync.markDirty(player: Player)
	dirty[player] = true
end

-- When each running boost ends, in server time (they count down while the
-- player is here, so the client can count down too).
local function boostEnds(profile: Types.Profile): { [string]: number }
	local now = workspace:GetServerTimeNow()
	local ends: { [string]: number } = {}
	for key, left in profile.boosts do
		ends[key] = now + left
	end
	return ends
end

local function toSnapshot(player: Player, profile: Types.Profile): Types.Snapshot
	local passes = Sync.passes[player] or {}
	local effects = PassRules.withBoosts(passes, profile.boosts)
	local rewards = Sync.rewards[player]
	local today = RewardRules.today(os.time())
	return {
		volts = profile.volts,
		totalVolts = profile.totalVolts,
		bottleTier = profile.bottleTier,
		bootTier = profile.bootTier,
		chargeCount = profile.chargeCount,
		chargeValue = profile.chargeValue,
		researchers = profile.researchers,
		tankCount = profile.tankCount,
		tankValue = profile.tankValue,
		setupUntil = Sync.setupUntil[player] or {},
		premium = Progression.playerIsPremium(player),
		passes = passes,
		capacity = PassRules.capacity(Formulas.capacity(profile.bottleTier), effects),
		trialUsed = profile.trialUsed,
		store = Sync.store[player] or NO_STORE,
		boosts = boostEnds(profile),
		daily = {
			streak = profile.dailyStreak,
			lastDay = profile.lastDailyDay,
		},
		gifts = {
			startedAt = if rewards then rewards.startedAt else workspace:GetServerTimeNow(),
			claimed = if rewards then rewards.claimed else {},
		},
		gifted = profile.giftedPasses,
		giftCredits = GiftRules.creditCounts(profile.giftCredits),
		afk = Sync.afk[player],
		glints = profile.glints,
		quests = QuestRules.view(profile.quests, profile.stats, today),
		log = StormLogRules.view(
			StormLogRules.found(profile.stats.lifetime, profile.researchers),
			profile.logClaimed
		),
		ascension = profile.ascension,
		tutorialStep = profile.tutorialStep,
		friends = Sync.friends[player] or 0,
		hintsSeen = profile.hintsSeen,
	}
end

local function setupLeaderstats(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local volts = Instance.new("NumberValue")
	volts.Name = "Volts"
	volts.Parent = leaderstats
	-- Ascension stars in the player list (Systems/Ascension)
	local ascension = Instance.new("StringValue")
	ascension.Name = "Ascension"
	ascension.Parent = leaderstats
	leaderstats.Parent = player
end

local function updateLeaderstats(player: Player, profile: Types.Profile)
	local leaderstats = player:FindFirstChild("leaderstats")
	local volts = leaderstats and leaderstats:FindFirstChild("Volts")
	if volts and volts:IsA("NumberValue") then
		volts.Value = profile.volts
	end
	local ascension = leaderstats and leaderstats:FindFirstChild("Ascension")
	if ascension and ascension:IsA("StringValue") then
		local stars = AscensionRules.stars(profile.ascension)
		ascension.Value = if stars == "" then "-" else stars
	end
end

function Sync.init()
	PlayerData.Loaded:Connect(function(player)
		setupLeaderstats(player)
		Sync.markDirty(player)
	end)
	-- fires when someone buys Premium in game: their gates open straight away
	Players.PlayerMembershipChanged:Connect(Sync.markDirty)
	Players.PlayerRemoving:Connect(function(player)
		dirty[player] = nil
		lastSent[player] = nil
		Sync.setupUntil[player] = nil
		Sync.passes[player] = nil
		Sync.store[player] = nil
		-- Sync.rewards is cleared by Systems/Rewards when the player's
		-- profile leaves (it saves today's playtime from it first)
	end)
end

function Sync.start()
	local remote = Net.get("StateSnapshot")
	while true do
		task.wait(FLUSH_INTERVAL)
		local now = os.clock()
		for player in dirty do
			if now - (lastSent[player] or -math.huge) < 1 / MAX_SENDS_PER_SECOND then
				continue -- sent very recently: it stays dirty for the next flush
			end
			dirty[player] = nil
			local profile = PlayerData.get(player)
			if profile and player.Parent then
				lastSent[player] = now
				updateLeaderstats(player, profile)
				remote:FireClient(player, toSnapshot(player, profile))
			end
		end
	end
end

return Sync
