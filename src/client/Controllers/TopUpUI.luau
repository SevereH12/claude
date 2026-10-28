--!strict
-- The top-up card: tapping a buy button you can't afford (a bottle, boots,
-- Ascend, HIRE or PROMOTE) shows a small card in the middle of the screen,
-- "You need 1.2K more ⚡. Get the Storm Jar (+2.4K ⚡) for 199 R$?", with
-- BUY and NO. The pack is Util/TopUp's pick: the cheapest that covers what
-- you're short, else the biggest. BUY only opens Roblox's purchase window
-- for that pack (Systems/Receipts pays it); it never buys the item itself:
-- the player taps the item again. The server still checks every price.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Util.Format)
local Net = require(ReplicatedStorage.Shared.Net)
local Store = require(ReplicatedStorage.Shared.Util.Store)
local TopUp = require(ReplicatedStorage.Shared.Util.TopUp)
local Layout = require(script.Parent.Parent.Lib.Layout)
local Sfx = require(script.Parent.Parent.Lib.Sfx)
local UI = require(script.Parent.Parent.Lib.UI)
local State = require(script.Parent.State)

local COLORS = UI.COLORS
local SIZE = Vector2.new(460, 160) -- design pixels
local SHOW_SECONDS = 20 -- the card hides itself after this

local TopUpUI = {}

local player = Players.LocalPlayer
local storeEvent: RemoteEvent
local card: Frame
local icon: ImageLabel
local text: TextLabel
local token = 0 -- bumped whenever the card changes, so old timers leave it alone

-- What the card is offering now. `line` is its text at a Robux price (0 =
-- not loaded yet: Config's).
type Offer = { key: string, productId: number, image: number, line: (price: number) -> string }
local current: Offer? = nil
local prices: { [number]: number } = {} -- product id -> Roblox's price, once loaded

local function hide()
	token += 1
	current = nil
	card.Visible = false
end

local function render()
	local offer = current
	if not offer then
		return
	end
	text.Text = offer.line(prices[offer.productId] or 0)
end

-- Roblox's real price (it can differ from Config's), loaded once.
local function loadPrice(productId: number)
	if prices[productId] then
		return
	end
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
		end)
		if ok and typeof(info) == "table" and typeof(info.PriceInRobux) == "number" then
			prices[productId] = info.PriceInRobux
			render()
		end
	end)
end

local function show(offer: Offer)
	token += 1
	local mine = token
	current = offer
	icon.Image = if offer.image ~= 0 then `rbxassetid://{offer.image}` else ""
	text.Text = offer.line(prices[offer.productId] or 0)
	loadPrice(offer.productId)
	card.Visible = true
	UI.pop(card, 1.05)
	Sfx.play("toast")
	task.delay(SHOW_SECONDS, function()
		if token == mine then
			hide()
		end
	end)
end

-- Short of Volts: offer the Volts pack that covers `short`.
function TopUpUI.volts(short: number)
	local snapshot = State.current
	local pack = if snapshot then TopUp.volts(short, snapshot) else nil
	local need = `You need {Format.abbreviate(short)} more ⚡`
	if not snapshot or not pack then
		UI.toast(need, "warn")
		return
	end
	local volts = Format.abbreviate(Store.packVolts(pack, snapshot))
	local name, fallback = pack.name, pack.price
	show({
		key = pack.key,
		productId = pack.productId,
		image = pack.image,
		line = function(price)
			local robux = Format.abbreviate(if price > 0 then price else fallback)
			return `{need}. Get the {name} (+{volts} ⚡) for {robux} R$?`
		end,
	})
end

-- Short of Glints for a promotion to `rank`: offer that tier's Glint pack.
function TopUpUI.glints(short: number, rank: number)
	local pack = TopUp.glints(short, rank)
	local need = `You need {Format.abbreviate(short)} more {Store.tierName(rank)} Glints`
	if not pack then
		UI.toast(need, "warn")
		return
	end
	local name, fallback = Store.glintPackName(pack), pack.price
	show({
		key = pack.key,
		productId = pack.productId,
		image = pack.image,
		line = function(price)
			local robux = Format.abbreviate(if price > 0 then price else fallback)
			return `{need}. Get {name} for {robux} R$?`
		end,
	})
end

local function buy()
	local offer = current
	hide()
	if not offer then
		return
	end
	Sfx.play("click")
	local productId = offer.productId
	local ok, err = pcall(function()
		MarketplaceService:PromptProductPurchase(player, productId)
	end)
	if ok then
		storeEvent:FireServer("prompt", offer.key)
	else
		warn(`[TopUpUI] couldn't open the purchase window: {err}`)
		UI.toast("The store isn't available right now. Try again soon.", "warn")
	end
end

function TopUpUI.init()
	storeEvent = Net.get("StoreEvent")
	-- above the shop and research panels (5 and 6)
	local _, root = Layout.screen("StormBottlerTopUp", 7)
	card = UI.panel({
		Name = "TopUpCard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(SIZE.X, SIZE.Y),
		Visible = false,
		Parent = root,
	})
	icon = UI.make(Instance.new("ImageLabel"), {
		Name = "Icon",
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(64, 64),
		Parent = card,
	})
	UI.corner(icon, UDim.new(0, 10))
	text = UI.label({
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Position = UDim2.fromOffset(88, 12),
		Size = UDim2.new(1, -100, 0, 80),
		Parent = card,
	})
	UI.maxText(text, 22)
	local no = UI.button({
		Name = "No",
		Text = "NO",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -12),
		Size = UDim2.new(0.5, -18, 0, 48),
		BackgroundColor3 = COLORS.panelDark,
		Parent = card,
	})
	UI.maxText(no, 24)
	no.Activated:Connect(function()
		UI.pop(no)
		Sfx.play("click")
		hide()
	end)
	local yes = UI.button({
		Name = "Buy",
		Text = "BUY",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -12),
		Size = UDim2.new(0.5, -18, 0, 48),
		BackgroundColor3 = COLORS.green,
		Parent = card,
	})
	UI.maxText(yes, 24)
	yes.Activated:Connect(function()
		UI.pop(yes)
		buy()
	end)
end

return TopUpUI
