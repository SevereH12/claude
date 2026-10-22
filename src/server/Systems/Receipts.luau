--!strict
-- Volts packs (Developer Products, Config.VOLT_PACKS). The only code that
-- sets MarketplaceService.ProcessReceipt. Each purchase is granted exactly
-- once: the profile remembers the newest purchase ids (Util/Store), and
-- Roblox only hears PurchaseGranted once the grant has been saved; until
-- then it asks again later (when the player rejoins), and the remembered id
-- stops a second grant.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Store = require(ReplicatedStorage.Shared.Util.Store)
local Types = require(ReplicatedStorage.Shared.Types)
local Analytics = require(script.Parent.Analytics)
local PlayerData = require(script.Parent.PlayerData)
local Sync = require(script.Parent.Sync)

local Receipts = {}

local purchasedRemote: RemoteEvent

local function packFor(productId: number): Types.VoltPackDef?
	for _, pack in Config.VOLT_PACKS do
		if pack.productId ~= 0 and pack.productId == productId then
			return pack
		end
	end
	return nil
end

local function processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local pack = packFor(receipt.ProductId)
	if not pack then
		warn(`[Receipts] no Volts pack has product id {receipt.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local profile = if player then PlayerData.get(player) else nil
	local purchaseId = tostring(receipt.PurchaseId)
	local decision = Store.receiptDecision(if profile then profile.purchases else nil, purchaseId)
	if decision == "AlreadyGranted" then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	if decision ~= "Grant" or not player or not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local volts = Store.packVolts(pack, profile)
	profile.volts += volts
	Store.recordPurchase(profile.purchases, purchaseId)
	Sync.markDirty(player)
	Analytics.packBought(player, pack, volts)
	purchasedRemote:FireClient(player, player.UserId, pack.key, volts)
	print(`[Receipts] {player.Name} bought {pack.name}: +{volts} Volts`)

	-- only confirm once it's saved; the id is remembered either way, so
	-- Roblox asking again can't grant it twice
	if PlayerData.saveNow(player) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	warn(`[Receipts] couldn't save {player.Name}'s {pack.name} yet; Roblox will ask again`)
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

function Receipts.init()
	purchasedRemote = Net.get("Purchased")
	MarketplaceService.ProcessReceipt = processReceipt
end

return Receipts
