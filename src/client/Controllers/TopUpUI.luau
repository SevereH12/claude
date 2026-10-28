--!strict
-- Top-ups: tapping a buy button you can't afford (a bottle, boots, Ascend,
-- HIRE or PROMOTE) opens Roblox's purchase window straight away for the
-- pack Util/TopUp picks: the cheapest that covers what you're short, else
-- the biggest. Systems/Receipts pays it; it never buys the item itself: the
-- player taps the item again. The server still checks every price.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Util.Format)
local Net = require(ReplicatedStorage.Shared.Net)
local Store = require(ReplicatedStorage.Shared.Util.Store)
local TopUp = require(ReplicatedStorage.Shared.Util.TopUp)
local UI = require(script.Parent.Parent.Lib.UI)
local State = require(script.Parent.State)

local REPEAT_SECONDS = 1 -- a double tap opens the window once

local TopUpUI = {}

local player = Players.LocalPlayer
local storeEvent: RemoteEvent
local lastPrompt = -math.huge

-- Opens Roblox's purchase window for a pack.
local function prompt(key: string, productId: number)
	if os.clock() - lastPrompt < REPEAT_SECONDS then
		return
	end
	lastPrompt = os.clock()
	local ok, err = pcall(function()
		MarketplaceService:PromptProductPurchase(player, productId)
	end)
	if ok then
		storeEvent:FireServer("prompt", key)
	else
		warn(`[TopUpUI] couldn't open the purchase window: {err}`)
		UI.toast("The store isn't available right now. Try again soon.", "warn")
	end
end

-- Short of Volts: the Volts pack that covers `short`.
function TopUpUI.volts(short: number)
	local snapshot = State.current
	local pack = if snapshot then TopUp.volts(short, snapshot) else nil
	if pack then
		prompt(pack.key, pack.productId)
	else
		UI.toast(`You need {Format.abbreviate(short)} more ⚡`, "warn")
	end
end

-- Short of Glints for a promotion to `rank`: that tier's Glint pack.
function TopUpUI.glints(short: number, rank: number)
	local pack = TopUp.glints(short, rank)
	if pack then
		prompt(pack.key, pack.productId)
	else
		UI.toast(`You need {Format.abbreviate(short)} more {Store.tierName(rank)} Glints`, "warn")
	end
end

function TopUpUI.init()
	storeEvent = Net.get("StoreEvent")
end

return TopUpUI
