--!strict
-- Gifting passes to anyone, by username (the rules: Util/Gifts). Nobody can
-- buy a game pass for someone else, so each pass has a "Gift" Developer
-- Product; the receiver gets the pass's effect in this game.
--
--   FindPlayer(username): who's that? GiftNews "found" with their user id,
--     name and display name (or nil).
--   PrepareGift(productKey, recipientId): every check (a real gift product,
--     a real player who isn't the giver and doesn't have the pass already,
--     real, gifted or waiting in their inbox), then remembers who it's for
--     for 5 minutes (the intent) and says "ready": the client opens the
--     purchase window. A receipt doesn't say who a gift is for.
--   SendCredit(productKey, recipientId): the same checks, then sends a gift
--     the giver already paid for (a credit), with no purchase.
--   Receipts: Systems/Receipts hands gift products to Gifts.processReceipt.
--     With a live intent the gift goes to the receiver's inbox; with none
--     (it expired, or this is another server) the giver gets a credit.
--   The inbox (DataStore StormBottler_Gifts, key inbox_<userId>, written
--     only with UpdateAsync): delivered on join and when MessagingService
--     (topic Gifts) says one came: applied to the profile by id, saved, and
--     only then removed from the inbox.
--
-- Every gift arrives exactly once: before a gift goes in an inbox, who it's
-- for is saved under its purchase id (key receipt_<id>), and that saved
-- receiver wins if Roblox retries the receipt or a credit is sent again;
-- inbox entries and applied gifts are both kept by id; Roblox only hears
-- PurchaseGranted once the giver's purchase id is saved.
--
-- GiftNews tells clients: "found", "ready", "refused", "sent", "credit",
-- "received". Studio: without API access the inbox lives in memory for the
-- session, and the TEST panel's "Send test gift to me" (Gifts.testGift)
-- puts a gift in your own inbox.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local UserService = game:GetService("UserService")

local Config = require(ReplicatedStorage.Shared.Config)
local GiftRules = require(ReplicatedStorage.Shared.Util.Gifts)
local Net = require(ReplicatedStorage.Shared.Net)
local Store = require(ReplicatedStorage.Shared.Util.Store)
local Types = require(ReplicatedStorage.Shared.Types)
local Passes = require(script.Parent.Passes)
local PlayerData = require(script.Parent.PlayerData)
local Sync = require(script.Parent.Sync)
local RateLimit = require(ServerScriptService.Server.Lib.RateLimit)

local STORE_NAME = "StormBottler_Gifts"
local TOPIC = "Gifts"

local Gifts = {}

local news: RemoteEvent
local intents: { [Player]: Types.GiftIntent } = {}
local delivering: { [Player]: boolean } = {}
local again: { [Player]: boolean } = {}

local storeOk, storeResult = pcall(function()
	return DataStoreService:GetDataStore(STORE_NAME)
end)
local giftStore: DataStore? = if storeOk then storeResult else nil
-- Studio without API access: inboxes and markers live here, this session only
local inMemory = false
local memory: { [string]: any } = {}

local function useMemory(err: any): boolean
	if not RunService:IsStudio() then
		warn(`[Gifts] DataStore error: {err}`)
		return false
	end
	if not inMemory then
		inMemory = true
		warn("[Gifts] DataStores unavailable in Studio: gifts are kept in memory this session")
	end
	return true
end

-- Reads a key: false if it couldn't be read.
local function readKey(key: string): (boolean, any)
	local dataStore = giftStore
	if dataStore and not inMemory then
		local ok, value = pcall(function()
			return dataStore:GetAsync(key)
		end)
		if ok then
			return true, value
		end
		if not useMemory(value) then
			return false, nil
		end
	elseif not dataStore and not useMemory("no DataStore") then
		return false, nil
	end
	return true, memory[key]
end

-- UpdateAsync on a key (`transform` returns nil to leave it): false if it
-- couldn't be written.
local function updateKey(key: string, transform: (any) -> any): boolean
	local dataStore = giftStore
	if dataStore and not inMemory then
		local ok, err = pcall(function()
			dataStore:UpdateAsync(key, transform)
		end)
		if ok then
			return true
		end
		if not useMemory(err) then
			return false
		end
	elseif not dataStore and not useMemory("no DataStore") then
		return false
	end
	local result = transform(memory[key])
	if result ~= nil then
		memory[key] = result
	end
	return true
end

local function inboxKey(userId: number): string
	return `inbox_{userId}`
end

local function markerKey(purchaseId: string): string
	return `receipt_{purchaseId}`
end

-- Adds a gift to someone's inbox (each id once): false if it couldn't be
-- written or their inbox is full.
local function addToInbox(userId: number, entry: Types.GiftEntry): boolean
	local added = false
	local ok = updateKey(inboxKey(userId), function(old: any): any
		local entries = if typeof(old) == "table" then old else {}
		added = GiftRules.addToInbox(entries, entry)
		return if added then entries else nil
	end)
	return ok and added
end

local function readInbox(userId: number): (boolean, { Types.GiftEntry })
	local ok, value = readKey(inboxKey(userId))
	return ok, if ok and typeof(value) == "table" then value else {}
end

-- Saves who a purchase's gift goes to, unless that was saved before.
-- Returns who it really goes to (the first one saved), or nil if it
-- couldn't be written.
local function claimMarker(
	purchaseId: string,
	recipientId: number,
	recipientName: string
): (number?, string)
	local finalId, finalName = recipientId, recipientName
	local ok = updateKey(markerKey(purchaseId), function(old: any): any
		if typeof(old) == "table" and typeof(old.recipientId) == "number" then
			finalId = old.recipientId
			finalName = if typeof(old.recipientName) == "string" then old.recipientName else ""
			return nil
		end
		finalId, finalName = recipientId, recipientName
		return { recipientId = recipientId, recipientName = recipientName }
	end)
	return if ok then finalId else nil, finalName
end

-- Applies a player's waiting gifts: on join, and when one comes in. Gifts
-- leave the inbox only once they're saved in the profile.
local function deliver(player: Player, onJoin: boolean)
	if delivering[player] then
		again[player] = true
		return
	end
	delivering[player] = true
	repeat
		again[player] = nil
		local profile = PlayerData.get(player)
		local ok, entries = readInbox(player.UserId)
		if profile and ok and #entries > 0 then
			local applied, done = GiftRules.apply(profile, entries)
			if #applied > 0 then
				Passes.refresh(player)
				Sync.markDirty(player)
			end
			if next(done) and (PlayerData.saveNow(player) or inMemory) then
				updateKey(inboxKey(player.UserId), function(old: any): any
					return if typeof(old) == "table"
						then GiftRules.removeFromInbox(old, done)
						else nil
				end)
			end
			if #applied > 0 then
				news:FireClient(player, "received", applied, onJoin)
			end
		end
	until not again[player] or not player.Parent
	delivering[player] = nil
end

-- A gift is in `recipientId`'s inbox: deliver it now if they're here,
-- otherwise tell every server (if that fails, it waits for their next join).
local function announce(recipientId: number)
	local here = Players:GetPlayerByUserId(recipientId)
	if here then
		task.spawn(deliver, here, false)
		return
	end
	local ok, err = pcall(function()
		MessagingService:PublishAsync(TOPIC, { recipientId = recipientId })
	end)
	if not ok then
		warn(`[Gifts] couldn't announce a gift: {err}`)
	end
end

-- The player with this id (name and display name), or nil if Roblox has none.
local function lookUp(userId: number): Types.FoundPlayer?
	local live = Players:GetPlayerByUserId(userId)
	if live then
		return { userId = userId, name = live.Name, displayName = live.DisplayName }
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if not ok or typeof(name) ~= "string" then
		return nil
	end
	local displayName = name
	local infoOk, infos = pcall(function()
		return UserService:GetUserInfosByUserIdsAsync({ userId })
	end)
	local info = if infoOk and typeof(infos) == "table" then infos[1] else nil
	if typeof(info) == "table" and typeof(info.DisplayName) == "string" then
		displayName = info.DisplayName
	end
	return { userId = userId, name = name, displayName = displayName }
end

-- Does this player have the pass already: real, gifted, or a gift waiting
-- in their inbox? nil when that couldn't be checked.
local function alreadyHas(recipientId: number, pass: Types.PassDef): boolean?
	local live = Players:GetPlayerByUserId(recipientId)
	if live then
		if Passes.owns(live, pass.key) then
			return true
		end
	else
		if pass.id ~= 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(recipientId, pass.id)
			end)
			if not ok then
				return nil
			end
			if owns then
				return true
			end
		end
		local ok, saved = PlayerData.peek(recipientId)
		if not ok and not RunService:IsStudio() then
			return nil
		end
		if saved and saved.giftedPasses[pass.key] then
			return true
		end
	end
	local ok, entries = readInbox(recipientId)
	if not ok then
		return nil
	end
	for _, entry in entries do
		if entry.kind == "pass" and entry.key == pass.key then
			return true
		end
	end
	return false
end

-- Every check before a gift may go. Returns why it can't (a message for the
-- giver), or the pass and who it's for.
local function check(
	giver: Player,
	productKey: unknown,
	recipientId: unknown
): (string?, Types.PassDef?, Types.FoundPlayer?)
	local refusal = GiftRules.basicRefusal(giver.UserId, productKey, recipientId)
	if refusal then
		return refusal, nil, nil
	end
	local pass = GiftRules.passFor(productKey :: string) :: Types.PassDef
	local found = lookUp(recipientId :: number)
	local has = if found then alreadyHas(found.userId, pass) else false
	refusal = GiftRules.recipientRefusal(pass, found ~= nil, has)
	if refusal then
		return refusal, nil, nil
	end
	return nil, pass, found
end

local function entryFor(giver: Player, id: string, pass: Types.PassDef): Types.GiftEntry
	return {
		id = id,
		kind = "pass",
		key = pass.key,
		fromId = giver.UserId,
		fromName = giver.DisplayName,
		time = os.time(),
	}
end

local function onFindPlayer(player: Player, username: unknown)
	if not RateLimit.allow(player, "FindPlayer", 1, 3) or typeof(username) ~= "string" then
		return
	end
	local name = string.gsub(username, "^@", "")
	local found: Types.FoundPlayer? = nil
	if #name >= 3 and #name <= 20 and string.match(name, "^[%w_]+$") then
		local ok, userId = pcall(function()
			return Players:GetUserIdFromNameAsync(name)
		end)
		if ok and typeof(userId) == "number" then
			found = lookUp(userId)
		end
	end
	news:FireClient(player, "found", username, found)
end

local function onPrepareGift(player: Player, productKey: unknown, recipientId: unknown)
	if not RateLimit.allow(player, "PrepareGift", 1, 3) then
		return
	end
	local refusal, pass, found = check(player, productKey, recipientId)
	if not refusal and pass and GiftRules.productId(GiftRules.productKey(pass.key)) == 0 then
		refusal = "That gift isn't on sale yet"
	end
	if refusal or not pass or not found then
		news:FireClient(player, "refused", refusal or "That gift can't go right now")
		return
	end
	intents[player] = {
		recipientId = found.userId,
		recipientName = found.displayName,
		productKey = GiftRules.productKey(pass.key),
		expires = os.clock() + Config.GIFTS.intentSeconds,
	}
	news:FireClient(player, "ready", GiftRules.productKey(pass.key), found.userId)
end

-- Sends a gift the giver paid for earlier (a credit). The credit's purchase
-- id is the gift's id, and its receiver is saved first: sending it again
-- after a crash can only reach the same person, once.
local function onSendCredit(player: Player, productKey: unknown, recipientId: unknown)
	if not RateLimit.allow(player, "SendCredit", 1, 3) then
		return
	end
	local profile = PlayerData.get(player)
	local creditId = if profile and typeof(productKey) == "string"
		then GiftRules.nextCredit(profile.giftCredits, productKey)
		else nil
	if not profile or not creditId then
		news:FireClient(player, "refused", "You don't have that gift to send")
		return
	end
	local refusal, pass, found = check(player, productKey, recipientId)
	if refusal or not pass or not found then
		news:FireClient(player, "refused", refusal or "That gift can't go right now")
		return
	end
	local toId, toName = claimMarker(creditId, found.userId, found.displayName)
	if not toId or not addToInbox(toId, entryFor(player, creditId, pass)) then
		news:FireClient(player, "refused", "Couldn't send it right now. Try again in a moment")
		return
	end
	GiftRules.removeCredit(profile.giftCredits, productKey :: string, creditId)
	Sync.markDirty(player)
	PlayerData.saveNow(player)
	announce(toId)
	news:FireClient(player, "sent", toName, Players:GetPlayerByUserId(toId) ~= nil)
end

-- A gift product's receipt (from Systems/Receipts).
function Gifts.processReceipt(
	receipt: { [string]: any },
	productKey: string
): Enum.ProductPurchaseDecision
	local pass = GiftRules.passFor(productKey)
	local giver = Players:GetPlayerByUserId(receipt.PlayerId)
	local profile = if giver then PlayerData.get(giver) else nil
	local purchaseId = tostring(receipt.PurchaseId)
	if not pass or not giver or not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if Store.receiptDecision(profile.purchases, purchaseId) == "AlreadyGranted" then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	-- who it's for: the live intent, or the receiver saved by an earlier try
	local recipientId: number?, recipientName = nil, ""
	local intent = intents[giver]
	if intent and GiftRules.intentMatches(intent, productKey, os.clock()) then
		-- they may have got it meanwhile: then it's a credit instead
		if alreadyHas(intent.recipientId, pass) ~= true then
			recipientId, recipientName =
				claimMarker(purchaseId, intent.recipientId, intent.recipientName)
			if not recipientId then
				return Enum.ProductPurchaseDecision.NotProcessedYet -- the intent stays for the retry
			end
		end
	else
		local ok, marker = readKey(markerKey(purchaseId))
		if not ok then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		if typeof(marker) == "table" and typeof(marker.recipientId) == "number" then
			recipientId = marker.recipientId
			recipientName = if typeof(marker.recipientName) == "string"
				then marker.recipientName
				else ""
		end
	end

	local plan = GiftRules.receiptPlan(profile.purchases, purchaseId, recipientId)
	if plan == "Inbox" and recipientId then
		if not addToInbox(recipientId, entryFor(giver, purchaseId, pass)) then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		intents[giver] = nil
		Store.recordPurchase(profile.purchases, purchaseId)
		announce(recipientId)
		news:FireClient(giver, "sent", recipientName, Players:GetPlayerByUserId(recipientId) ~= nil)
		print(`[Gifts] {giver.Name} gifted {pass.name} to {recipientName}`)
	elseif plan == "Credit" then
		intents[giver] = nil
		GiftRules.addCredit(profile.giftCredits, productKey, purchaseId)
		Store.recordPurchase(profile.purchases, purchaseId)
		news:FireClient(giver, "credit", productKey)
	end
	Sync.markDirty(giver)
	if PlayerData.saveNow(giver) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

-- Studio TEST tool: a gift from "Test Gifter" to yourself, of the first pass
-- you don't have, through your own inbox.
function Gifts.testGift(player: Player)
	for _, pass in Config.PASSES do
		if not Passes.owns(player, pass.key) then
			local entry: Types.GiftEntry = {
				id = `test-{HttpService:GenerateGUID(false)}`,
				kind = "pass",
				key = pass.key,
				fromId = player.UserId,
				fromName = "Test Gifter",
				time = os.time(),
			}
			if addToInbox(player.UserId, entry) then
				task.spawn(deliver, player, false)
			end
			return
		end
	end
	news:FireClient(player, "refused", "You already have every pass")
end

function Gifts.init()
	news = Net.get("GiftNews")
	Net.get("FindPlayer").OnServerEvent:Connect(onFindPlayer)
	Net.get("PrepareGift").OnServerEvent:Connect(onPrepareGift)
	Net.get("SendCredit").OnServerEvent:Connect(onSendCredit)
	PlayerData.Loaded:Connect(function(player: Player)
		task.spawn(deliver, player, true)
	end)
	Players.PlayerRemoving:Connect(function(player)
		intents[player] = nil
		again[player] = nil
	end)
end

function Gifts.start()
	-- a gift for someone in this server, bought in another one
	local ok, err = pcall(function()
		MessagingService:SubscribeAsync(TOPIC, function(message)
			local data = message.Data
			local recipientId = if typeof(data) == "table" then data.recipientId else nil
			local player = if typeof(recipientId) == "number"
				then Players:GetPlayerByUserId(recipientId)
				else nil
			if player then
				task.spawn(deliver, player, false)
			end
		end)
	end)
	if not ok then
		warn(`[Gifts] live delivery is off (gifts arrive on the next join): {err}`)
	end
end

return Gifts
