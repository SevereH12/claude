--!strict
-- Developer Product receipts: the only code that sets
-- MarketplaceService.ProcessReceipt. Gift products and boosts (for the
-- buyer or a gift) go to Systems/Gifts; a Server Storm (Systems/Boosts),
-- Volts packs (Config.VOLT_PACKS) and Glint packs (Config.GLINT_PACKS,
-- through Research.addGlints) are granted here, to the buyer in this
-- server. Each purchase is granted exactly once: the profile remembers the
-- newest purchase ids (Util/Store), and Roblox only hears PurchaseGranted
-- once the grant has been saved; until then it asks again later (when the
-- player rejoins, in whichever server they're in: a Server Storm bought
-- just before leaving starts there), and the remembered id stops a second
-- grant.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoostRules = require(ReplicatedStorage.Shared.Util.Boosts)
local Config = require(ReplicatedStorage.Shared.Config)
local GiftRules = require(ReplicatedStorage.Shared.Util.Gifts)
local Net = require(ReplicatedStorage.Shared.Net)
local ResearchMath = require(ReplicatedStorage.Shared.Util.Research)
local Store = require(ReplicatedStorage.Shared.Util.Store)
local Types = require(ReplicatedStorage.Shared.Types)
local Analytics = require(script.Parent.Analytics)
local Boosts = require(script.Parent.Boosts)
local Gifts = require(script.Parent.Gifts)
local PlayerData = require(script.Parent.PlayerData)
local Research = require(script.Parent.Research)
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

-- A purchase for the buyer, granted once: `give` grants it while they're
-- in this server with their profile loaded.
local function forBuyer(
	receipt: { [string]: any },
	name: string,
	give: (Player, Types.Profile) -> ()
): Enum.ProductPurchaseDecision
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

	give(player, profile)
	Store.recordPurchase(profile.purchases, purchaseId)
	Sync.markDirty(player)

	-- only confirm once it's saved; the id is remembered either way, so
	-- Roblox asking again can't grant it twice
	if PlayerData.saveNow(player) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	warn(`[Receipts] couldn't save {player.Name}'s {name} yet; Roblox will ask again`)
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

local function processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	-- a "Gift: <pass>" product or a boost, for the buyer or a gift (Systems/Gifts)
	local giftKey = GiftRules.byProductId(receipt.ProductId)
	if giftKey then
		return Gifts.processReceipt(receipt, giftKey)
	end
	local storm = BoostRules.productById(receipt.ProductId)
	if storm and storm.serverStorm then
		return forBuyer(receipt, storm.name, function(player)
			local left = Boosts.startStorm(player)
			Analytics.serverStorm(player, math.round(left / 60))
			purchasedRemote:FireClient(player, player.UserId, storm.key, 0)
		end)
	end
	local glintPack = Store.glintPackById(receipt.ProductId)
	if glintPack then
		local name = Store.glintPackName(glintPack)
		return forBuyer(receipt, name, function(player, profile)
			Research.addGlints(player, glintPack.tier, glintPack.glints)
			local balance = ResearchMath.glintsOf(profile.glints, glintPack.tier)
			Analytics.glintPackBought(player, name, glintPack.glints, balance)
			purchasedRemote:FireClient(player, player.UserId, glintPack.key, glintPack.glints)
			print(`[Receipts] {player.Name} bought {name}`)
		end)
	end
	local pack = packFor(receipt.ProductId)
	if not pack then
		warn(`[Receipts] no product has id {receipt.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return forBuyer(receipt, pack.name, function(player, profile)
		local volts = Store.packVolts(pack, profile)
		profile.volts += volts
		Analytics.packBought(player, pack, volts)
		purchasedRemote:FireClient(player, player.UserId, pack.key, volts)
		print(`[Receipts] {player.Name} bought {pack.name}: +{volts} Volts`)
	end)
end

function Receipts.init()
	purchasedRemote = Net.get("Purchased")
	MarketplaceService.ProcessReceipt = processReceipt
end

return Receipts
