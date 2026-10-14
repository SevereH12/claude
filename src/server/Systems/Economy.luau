--!strict
-- Coins, upgrades and rebirths. The server decides everything: the client
-- only asks ("I clicked", "buy ClickPower", "rebirth") and gets sent its new
-- state back.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Util.Formulas)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local PlayerData = require(script.Parent.PlayerData)
local RateLimit = require(ServerScriptService.Server.Lib.RateLimit)

local FLUSH_INTERVAL = 0.1 -- how often changed state is sent to clients

-- players whose state changed since the last flush
local dirty: { [Player]: boolean } = {}

local Economy = {}

local function markDirty(player: Player)
	dirty[player] = true
end

local function addCoins(profile: Types.Profile, amount: number)
	profile.coins += amount
	profile.totalCoins += amount
end

local function toSnapshot(profile: Types.Profile): Types.Snapshot
	return {
		coins = profile.coins,
		totalCoins = profile.totalCoins,
		rebirths = profile.rebirths,
		upgrades = table.clone(profile.upgrades),
	}
end

local function setupLeaderstats(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local coins = Instance.new("NumberValue")
	coins.Name = "Coins"
	coins.Parent = leaderstats

	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Parent = leaderstats

	leaderstats.Parent = player
end

local function updateLeaderstats(player: Player, profile: Types.Profile)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return
	end
	local coins = leaderstats:FindFirstChild("Coins")
	if coins and coins:IsA("NumberValue") then
		coins.Value = profile.coins
	end
	local rebirths = leaderstats:FindFirstChild("Rebirths")
	if rebirths and rebirths:IsA("IntValue") then
		rebirths.Value = profile.rebirths
	end
end

local function flush(snapshotRemote: RemoteEvent)
	for player in dirty do
		dirty[player] = nil
		local profile = PlayerData.get(player)
		if profile and player.Parent then
			updateLeaderstats(player, profile)
			snapshotRemote:FireClient(player, toSnapshot(profile))
		end
	end
end

local function onClick(player: Player)
	if not RateLimit.allow(player, "Click", Config.MAX_CLICKS_PER_SECOND, Config.CLICK_BURST) then
		return
	end
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	addCoins(profile, Formulas.clickValue(profile))
	markDirty(player)
end

local function onBuyUpgrade(player: Player, upgradeId: unknown)
	if not RateLimit.allow(player, "BuyUpgrade", 10, 15) then
		return
	end
	if typeof(upgradeId) ~= "string" or #upgradeId > 32 then
		return
	end
	local def: Types.UpgradeDef? = Config.UPGRADES[upgradeId]
	if not def then
		return
	end
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	local level = Formulas.level(profile, def.id)
	if level >= def.maxLevel then
		return
	end
	local cost = Formulas.upgradeCost(def, level) -- price from the server's catalog
	if profile.coins < cost then
		return
	end
	profile.coins -= cost
	profile.upgrades[def.id] = level + 1
	markDirty(player)
end

local function onRebirth(player: Player)
	if not RateLimit.allow(player, "Rebirth", 1, 2) then
		return
	end
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	if profile.coins < Formulas.rebirthCost(profile.rebirths) then
		return
	end
	profile.coins = 0
	profile.upgrades = {}
	profile.rebirths += 1
	markDirty(player)
end

local function payAutoIncome()
	for _, player in Players:GetPlayers() do
		local profile = PlayerData.get(player)
		if profile then
			local income = Formulas.autoIncome(profile)
			if income > 0 then
				addCoins(profile, income)
				markDirty(player)
			end
		end
	end
end

function Economy.init()
	Net.get("Click").OnServerEvent:Connect(onClick)
	Net.get("BuyUpgrade").OnServerEvent:Connect(onBuyUpgrade)
	Net.get("Rebirth").OnServerEvent:Connect(onRebirth)

	PlayerData.Loaded:Connect(function(player)
		setupLeaderstats(player)
		markDirty(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		dirty[player] = nil
	end)
end

function Economy.start()
	local snapshotRemote = Net.get("StateSnapshot")

	task.spawn(function()
		while true do
			task.wait(1)
			payAutoIncome()
		end
	end)

	while true do
		task.wait(FLUSH_INTERVAL)
		flush(snapshotRemote)
	end
end

return Economy
