--!strict
-- Sends each player their latest state. Systems that change a profile call
-- Sync.markDirty(player); changes are batched and sent 10 times a second.
-- Also keeps the Volts leaderboard stat up to date.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local PlayerData = require(script.Parent.PlayerData)

local FLUSH_INTERVAL = 0.1

local dirty: { [Player]: boolean } = {}

local Sync = {}

-- Owned by Systems/Research: per player, role id -> set-up-done time
-- (workspace:GetServerTimeNow()). Sent in the snapshot for the Research panel.
Sync.setupUntil = {} :: { [Player]: { [string]: number } }

function Sync.markDirty(player: Player)
	dirty[player] = true
end

local function toSnapshot(player: Player, profile: Types.Profile): Types.Snapshot
	return {
		volts = profile.volts,
		totalVolts = profile.totalVolts,
		bottleTier = profile.bottleTier,
		chargeCount = profile.chargeCount,
		chargeValue = profile.chargeValue,
		researchers = profile.researchers,
		tankCount = profile.tankCount,
		tankValue = profile.tankValue,
		setupUntil = Sync.setupUntil[player] or {},
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
	Players.PlayerRemoving:Connect(function(player)
		dirty[player] = nil
		Sync.setupUntil[player] = nil
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
