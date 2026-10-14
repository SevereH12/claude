--!strict
-- Bottle upgrades. BuyBottle is the only request a client can send, so it
-- gets the full treatment: rate limit, type/range checks, server prices.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local PlayerData = require(script.Parent.PlayerData)
local Sync = require(script.Parent.Sync)
local RateLimit = require(ServerScriptService.Server.Lib.RateLimit)

local Shop = {}

local function onBuyBottle(player: Player, tier: unknown)
	if not RateLimit.allow(player, "BuyBottle", 3, 5) then
		return
	end
	-- type and range: a whole number that is a real tier (rejects NaN/inf too)
	if typeof(tier) ~= "number" or tier ~= math.floor(tier) then
		return
	end
	if tier < 1 or tier > #Config.BOTTLES then
		return
	end
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	-- tiers are bought in order
	if tier ~= profile.bottleTier + 1 then
		return
	end
	local bottle = Config.BOTTLES[tier]
	if profile.volts < bottle.price then -- price from the server's catalog
		return
	end
	profile.volts -= bottle.price
	profile.bottleTier = tier
	Sync.markDirty(player)
end

function Shop.init()
	Net.get("BuyBottle").OnServerEvent:Connect(onBuyBottle)
end

return Shop
