--!strict
-- The store's server side (purchases themselves: Systems/Passes for Game
-- Passes, Systems/Receipts for Volts packs):
--   * StartTrial: the free 2x Volts trial, once per player ever
--     (profile.trialUsed), only without 2x Volts: a 3-minute 2x Volts boost
--     (Systems/Boosts), so like every boost it only counts down while they
--     play. Its stats end when that boost runs out, or when they leave.
--   * StoreEvent(kind, key): the client reports store visits and offers for
--     the stats (Analytics): "open", "card" and "prompt" (pass or pack key)
--     are store funnel steps 1-3; "offerShown" and "offerTapped" (offer key)
--     custom events. Rate-limited, and only known kinds and keys count.
--   * Purchased: when anyone buys a pass, every client hears it (a chat line
--     for everyone, a celebration for the buyer).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local Analytics = require(script.Parent.Analytics)
local Boosts = require(script.Parent.Boosts)
local Passes = require(script.Parent.Passes)
local PlayerData = require(script.Parent.PlayerData)
local Sync = require(script.Parent.Sync)
local RateLimit = require(ServerScriptService.Server.Lib.RateLimit)

-- Offers the client may report (Controllers/Offers).
local OFFER_KEYS = {
	RemoteSell = true,
	BigBottles = true,
	DoubleVolts = true,
	LabGrant = true,
	LuckyCharges = true,
	Trial = true,
}

local Store = {}

-- Everything in the store a card can be: pass, boost and Volts pack keys.
local itemKeys: { [string]: boolean } = {}
for _, pass in Config.PASSES do
	itemKeys[pass.key] = true
end
for _, product in Config.BOOST_PRODUCTS do
	itemKeys[product.key] = true
end
for _, pack in Config.VOLT_PACKS do
	itemKeys[pack.key] = true
end

-- Trials running now: this session's store numbers and what 2x boosts had
-- paid when the trial began (kept here so a leaving player's trial can
-- still be summed up).
type Trial = { session: Types.StoreSession, start: number }
local trials: { [Player]: Trial } = {}

local function endTrial(player: Player)
	local trial = trials[player]
	if trial then
		trials[player] = nil
		Analytics.trialEnded(player, trial.session.boostEarned - trial.start)
	end
end

local function onStartTrial(player: Player)
	if not RateLimit.allow(player, "StartTrial", 1, 2) then
		return
	end
	local profile = PlayerData.get(player)
	if not profile or profile.trialUsed or Passes.owns(player, "DoubleVolts") then
		return
	end
	profile.trialUsed = true
	local session = Passes.storeSession(player)
	trials[player] = { session = session, start = session.boostEarned }
	Boosts.grant(player, "DoubleVolts", Config.STORE.trialSeconds)
	Analytics.trialStarted(player)
	Sync.markDirty(player)
	print(`[Store] {player.Name} started the free 2x Volts trial`)
end

local function onStoreEvent(player: Player, kind: unknown, key: unknown)
	if not RateLimit.allow(player, "StoreEvent", 4, 8) then
		return
	end
	if kind == "open" then
		Analytics.storeStep(player, 1)
	elseif (kind == "card" or kind == "prompt") and typeof(key) == "string" and itemKeys[key] then
		Analytics.storeStep(player, if kind == "card" then 2 else 3)
	elseif
		(kind == "offerShown" or kind == "offerTapped")
		and typeof(key) == "string"
		and OFFER_KEYS[key]
	then
		Analytics.offer(player, if kind == "offerShown" then "OfferShown" else "OfferTapped", key)
	end
end

function Store.init()
	Net.get("StartTrial").OnServerEvent:Connect(onStartTrial)
	Net.get("StoreEvent").OnServerEvent:Connect(onStoreEvent)
	local purchased = Net.get("Purchased")
	Passes.Purchased:Connect(function(player: Player, pass: Types.PassDef)
		purchased:FireAllClients(player.UserId, pass.key, 0)
		Analytics.storeStep(player, 4)
	end)
	Boosts.Ended:Connect(function(player: Player, key: string)
		if key == "DoubleVolts" then
			endTrial(player)
		end
	end)
	-- a trial cut short by leaving still counts as ended
	Players.PlayerRemoving:Connect(endTrial)
end

return Store
