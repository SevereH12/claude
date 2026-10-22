--!strict
-- The Remote Sell pass: its SELL button (Controllers/HUD) fires the
-- RemoteSell remote, and this sells from anywhere through Selling.payOut,
-- the same payout as a sell station (so Analytics and the Sold pop-up work
-- the same). The client's charge-up ring is only for show: the server checks
-- the rate limit, the pass, a live character, charges and its own cooldown.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Passes = require(script.Parent.Passes)
local PlayerData = require(script.Parent.PlayerData)
local Selling = require(script.Parent.Selling)
local RateLimit = require(ServerScriptService.Server.Lib.RateLimit)

local RemoteSell = {}

local lastSold: { [Player]: number } = {}

local function onRemoteSell(player: Player)
	if not RateLimit.allow(player, "RemoteSell", 1, 3) then
		return
	end
	local profile = PlayerData.get(player)
	if not profile or profile.chargeCount <= 0 or not Passes.owns(player, "RemoteSell") then
		return
	end
	local now = os.clock()
	if now - (lastSold[player] or -math.huge) < Config.PASS_VALUES.remoteSellCooldown then
		return
	end
	if not Selling.isAlive(player) then
		return
	end
	lastSold[player] = now
	Selling.payOut(player, profile)
end

function RemoteSell.init()
	Net.get("RemoteSell").OnServerEvent:Connect(onRemoteSell)
	Players.PlayerRemoving:Connect(function(player)
		lastSold[player] = nil
	end)
end

return RemoteSell
