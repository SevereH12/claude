--!strict
-- Sends each player their latest state. Systems that change a profile call
-- Sync.markDirty(player); changes are batched and sent 10 times a second.
-- Also keeps the Volts leaderboard stat up to date.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local Formulas = require(ReplicatedStorage.Shared.Util.Formulas)
local PassRules = require(ReplicatedStorage.Shared.Util.Passes)
local Progression = require(ReplicatedStorage.Shared.Util.Progression)
local PlayerData = require(script.Parent.PlayerData)

local FLUSH_INTERVAL = 0.1

local dirty: { [Player]: boolean } = {}

local Sync = {}

-- Owned by Systems/Research: per player, role id -> set-up-done time
-- (workspace:GetServerTimeNow()). Sent in the snapshot for the Research panel.
Sync.setupUntil = {} :: { [Player]: { [string]: number } }

-- Owned by Systems/Passes: per player, the Game Passes they own (key set),
-- and this session's store numbers (the free trial, 2x Volts tallies).
Sync.passes = {} :: { [Player]: PassRules.Owned }
Sync.store = {} :: { [Player]: Types.StoreSession }

local NO_STORE: Types.StoreSession =
	table.freeze({ trialEndsAt = 0, trialEarned = 0, missedDouble = 0 })

function Sync.markDirty(player: Player)
	dirty[player] = true
end

local function toSnapshot(player: Player, profile: Types.Profile): Types.Snapshot
	local passes = Sync.passes[player] or {}
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
		capacity = PassRules.capacity(Formulas.capacity(profile.bottleTier), passes),
		trialUsed = profile.trialUsed,
		store = Sync.store[player] or NO_STORE,
	}
end

local function setupLeaderstats(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local volts = Instance.new("NumberValue")
	volts.Name = "Volts"
	volts.Parent = leaderstats
	leaderstats.Parent = player
end

local function updateLeaderstats(player: Player, profile: Types.Profile)
	local leaderstats = player:FindFirstChild("leaderstats")
	local volts = leaderstats and leaderstats:FindFirstChild("Volts")
	if volts and volts:IsA("NumberValue") then
		volts.Value = profile.volts
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
		Sync.setupUntil[player] = nil
		Sync.passes[player] = nil
		Sync.store[player] = nil
	end)
end

function Sync.start()
	local remote = Net.get("StateSnapshot")
	while true do
		task.wait(FLUSH_INTERVAL)
		for player in dirty do
			dirty[player] = nil
			local profile = PlayerData.get(player)
			if profile and player.Parent then
				updateLeaderstats(player, profile)
				remote:FireClient(player, toSnapshot(player, profile))
			end
		end
	end
end

return Sync
