--!strict
-- The gift window (from a pass or boost card's GIFT button): give a pass or
-- a boost to anyone, by username or from this server's players.
--   1. "Who's this for?": the other players here (avatar and display name)
--      and a username box. FIND asks the server (FindPlayer).
--   2. The confirm screen: "Gift VIP to DisplayName (@name)?", then BUY.
--      BUY asks the server to check and remember who it's for (PrepareGift);
--      only on its "ready" does Roblox's purchase window open, and only from
--      that tap. With a gift credit (a gift paid for earlier) the button is
--      SEND instead, and nothing is bought (SendCredit).
-- The server decides everything (Systems/Gifts) and says how it went on
-- GiftNews: found, ready, refused, sent, credit, received. Gifts that
-- arrive bring a celebration.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Util.Format)
local GiftRules = require(ReplicatedStorage.Shared.Util.Gifts)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local Celebrate = require(script.Parent.Parent.Lib.Celebrate)
local Layout = require(script.Parent.Parent.Lib.Layout)
local Sfx = require(script.Parent.Parent.Lib.Sfx)
local UI = require(script.Parent.Parent.Lib.UI)
local State = require(script.Parent.State)

local COLORS = UI.COLORS
local PINK = Color3.fromRGB(255, 120, 170)
local ROBUX = utf8.char(0xE002)
local ROW_HEIGHT = 64

local GiftUI = {}

local player = Players.LocalPlayer
local panel: Frame
local pickPage: Frame
local confirmPage: Frame
local title: TextLabel
local playerList: ScrollingFrame
local nameBox: TextBox
local pickStatus: TextLabel
local confirmAvatar: ImageLabel
local confirmText: TextLabel
local confirmStatus: TextLabel
local buyButton: TextButton

local gift: string? = nil -- the gift product being given ("GiftVIP", "LuckyBoost")
local chosen: Types.FoundPlayer? = nil
local looking: string? = nil -- the username FIND is waiting on
local waiting = false -- BUY/SEND is waiting on the server
local prices: { [string]: number } = {} -- gift product key -> Robux, from Roblox

local function productKey(): string
	return gift or ""
end

-- Gifts already paid for, waiting for someone to send them to.
local function credits(): number
	local snapshot = State.current
	return if snapshot then snapshot.giftCredits[productKey()] or 0 else 0
end

local function avatar(image: ImageLabel, userId: number)
	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(
				userId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size100x100
			)
		end)
		if ok then
			image.Image = content
		end
	end)
end

local function setStatus(label: TextLabel, text: string, bad: boolean?)
	label.Text = text
	label.TextColor3 = if bad then COLORS.red else COLORS.subtext
end

-- The confirm screen for `found`.
local function confirm(found: Types.FoundPlayer)
	local key = productKey()
	local name = GiftRules.itemName(key)
	if not name then
		return
	end
	chosen = found
	pickPage.Visible = false
	confirmPage.Visible = true
	confirmAvatar.Image = ""
	avatar(confirmAvatar, found.userId)
	confirmText.Text = `Gift {name} to {found.displayName} (@{found.name})?`
	if credits() > 0 then
		buyButton.Text = "🎁 SEND (already paid)"
	else
		buyButton.Text = `{ROBUX} {Format.abbreviate(prices[key] or GiftRules.price(key))}  BUY`
	end
	UI.setEnabled(buyButton, true, COLORS.green)
	setStatus(confirmStatus, "")
	waiting = false
end

local function showPick()
	chosen = nil
	looking = nil
	pickPage.Visible = true
	confirmPage.Visible = false
	setStatus(pickStatus, "")
end

-- One row per other player in this server.
local function fillPlayers()
	for _, child in playerList:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	for index, other in Players:GetPlayers() do
		if other ~= player then
			local row = UI.make(Instance.new("TextButton"), {
				Name = other.Name,
				LayoutOrder = index,
				Text = "",
				AutoButtonColor = true,
				BackgroundColor3 = COLORS.panelDark,
				Size = UDim2.new(1, -10, 0, ROW_HEIGHT),
				Parent = playerList,
			})
			UI.corner(row, UDim.new(0, 12))
			UI.stroke(row, 2)
			local image = UI.make(Instance.new("ImageLabel"), {
				Name = "Avatar",
				BackgroundColor3 = COLORS.panelTop,
				Position = UDim2.fromOffset(8, 6),
				Size = UDim2.fromOffset(ROW_HEIGHT - 12, ROW_HEIGHT - 12),
				Parent = row,
			})
			UI.corner(image, UDim.new(0.5, 0))
			avatar(image, other.UserId)
			local label = UI.label({
				Title = true,
				Text = `{other.DisplayName}  <font color="#BEC8EB">@{other.Name}</font>`,
				RichText = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				Position = UDim2.fromOffset(ROW_HEIGHT + 4, 14),
				Size = UDim2.new(1, -(ROW_HEIGHT + 14), 0, ROW_HEIGHT - 28),
				Parent = row,
			})
			UI.maxText(label, 22)
			UI.clickSound(row)
			row.Activated:Connect(function()
				UI.pop(row)
				confirm({
					userId = other.UserId,
					name = other.Name,
					displayName = other.DisplayName,
				})
			end)
		end
	end
end

local function loadPrice(key: string)
	local id = GiftRules.productId(key)
	if id == 0 or prices[key] then
		return
	end
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(id, Enum.InfoType.Product)
		end)
		if ok and typeof(info) == "table" and typeof(info.PriceInRobux) == "number" then
			prices[key] = info.PriceInRobux
		end
	end)
end

-- Opens the window to give a gift product: a pass's ("GiftVIP") or a
-- boost ("LuckyBoost").
function GiftUI.open(key: string)
	local name = GiftRules.itemName(key)
	if not name then
		return
	end
	gift = key
	loadPrice(key)
	title.Text = `Who's this {name} for?`
	nameBox.Text = ""
	fillPlayers()
	showPick()
	UI.openPanel(panel)
end

local function find()
	local name = string.gsub(nameBox.Text, "%s", "")
	if #name < 3 then
		setStatus(pickStatus, "Type their username (at least 3 letters)", true)
		return
	end
	looking = name
	setStatus(pickStatus, "Looking…")
	Net.get("FindPlayer"):FireServer(name)
end

-- BUY (or SEND a credit): the server checks first.
local function buy()
	local found = chosen
	if waiting or not found or not gift then
		return
	end
	waiting = true
	UI.setEnabled(buyButton, false, COLORS.green)
	if credits() > 0 then
		setStatus(confirmStatus, "Sending…")
		Net.get("SendCredit"):FireServer(productKey(), found.userId)
	else
		setStatus(confirmStatus, "Checking…")
		Net.get("PrepareGift"):FireServer(productKey(), found.userId)
	end
end

-- What a received gift was ("VIP", "Lucky Boost").
local function giftName(entry: Types.GiftEntry): string
	return GiftRules.itemName(GiftRules.entryProduct(entry)) or entry.key
end

-- What the server says.
local function onNews(kind: string, a: any, b: any)
	if kind == "found" then
		if a ~= looking then
			return
		end
		looking = nil
		if typeof(b) == "table" then
			if b.userId == player.UserId then
				setStatus(pickStatus, "That's you! Get it in the store instead", true)
			else
				confirm(b)
			end
		else
			setStatus(pickStatus, `No player is called "{a}"`, true)
		end
	elseif kind == "ready" then
		local found = chosen
		if not waiting or not found or a ~= productKey() or b ~= found.userId then
			return
		end
		local ok, err = pcall(function()
			MarketplaceService:PromptProductPurchase(player, GiftRules.productId(a))
		end)
		if ok then
			setStatus(confirmStatus, "Finish in Roblox's window")
		else
			warn(`[GiftUI] couldn't open the purchase window: {err}`)
			setStatus(confirmStatus, "The store isn't available right now. Try again soon.", true)
		end
		waiting = false
		UI.setEnabled(buyButton, true, COLORS.green)
	elseif kind == "refused" then
		waiting = false
		if panel.Visible then
			local label = if confirmPage.Visible then confirmStatus else pickStatus
			setStatus(label, tostring(a), true)
			UI.setEnabled(buyButton, true, COLORS.green)
		else
			UI.toast(tostring(a), "warn")
		end
	elseif kind == "sent" then
		waiting = false
		UI.closePanels()
		Sfx.play("purchase")
		Celebrate.sparks()
		UI.toast(`🎁 Gift sent to {a}!`, "good", 5)
		if not b then
			UI.toast("If they're not playing now, they'll get it next time they join", "info", 6)
		end
	elseif kind == "credit" then
		UI.toast("You have a gift to send: choose who gets it", "volt", 8, {
			text = "OPEN",
			onTap = function()
				if typeof(a) == "string" then
					GiftUI.open(a)
				end
			end,
		})
	elseif kind == "received" and typeof(a) == "table" then
		Sfx.play("gift_received")
		Celebrate.sparks()
		local gifts = a :: { Types.GiftEntry }
		if #gifts == 1 then
			UI.toast(`🎁 {gifts[1].fromName} gifted you {giftName(gifts[1])}!`, "good", 6)
		else
			local list: { string } = {}
			for _, entry in gifts do
				table.insert(list, `{giftName(entry)} from {entry.fromName}`)
			end
			UI.toast(`🎁 You received {#gifts} gifts!`, "good", 6)
			UI.toast(table.concat(list, ", "), "info", 8)
		end
	end
end

function GiftUI.init()
	local _, root = Layout.screen("StormBottlerGift", 6)
	local window = UI.window(root, "GiftPanel", "🎁 SEND A GIFT", PINK, Vector2.new(560, 520))
	panel = window.panel

	-- 1. who it's for
	pickPage = UI.make(Instance.new("Frame"), {
		Name = "Pick",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = window.body,
	})
	title = UI.label({
		Title = true,
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 30),
		Parent = pickPage,
	})
	UI.maxText(title, 26)
	nameBox = UI.make(Instance.new("TextBox"), {
		Name = "Username",
		PlaceholderText = "Username",
		Text = "",
		ClearTextOnFocus = false,
		Font = UI.FONT_TITLE,
		TextScaled = true,
		TextColor3 = COLORS.text,
		PlaceholderColor3 = COLORS.subtext,
		BackgroundColor3 = COLORS.panelDark,
		Position = UDim2.fromOffset(0, 38),
		Size = UDim2.new(0.68, -8, 0, 48),
		Parent = pickPage,
	})
	UI.corner(nameBox, UDim.new(0, 10))
	UI.stroke(nameBox, 2)
	UI.make(Instance.new("UIPadding"), {
		PaddingLeft = UDim.new(0, 10),
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
		Parent = nameBox,
	})
	nameBox.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			find()
		end
	end)
	local findButton = UI.button({
		Name = "Find",
		Text = "FIND",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 38),
		Size = UDim2.new(0.32, 0, 0, 48),
		BackgroundColor3 = COLORS.storm,
		Parent = pickPage,
	})
	UI.maxText(findButton, 22)
	findButton.Activated:Connect(function()
		UI.pop(findButton)
		find()
	end)
	pickStatus = UI.label({
		Text = "",
		TextColor3 = COLORS.subtext,
		Position = UDim2.fromOffset(0, 92),
		Size = UDim2.new(1, 0, 0, 20),
		Parent = pickPage,
	})
	UI.maxText(pickStatus, 17)
	local here = UI.label({
		Title = true,
		Text = "IN THIS SERVER",
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(0, 118),
		Size = UDim2.new(1, 0, 0, 22),
		Parent = pickPage,
	})
	UI.maxText(here, 18)
	playerList = UI.make(Instance.new("ScrollingFrame"), {
		Name = "Players",
		Position = UDim2.fromOffset(0, 146),
		Size = UDim2.new(1, 0, 1, -146),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = pickPage,
	})
	UI.make(Instance.new("UIListLayout"), {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = playerList,
	})

	-- 2. the confirm screen
	confirmPage = UI.make(Instance.new("Frame"), {
		Name = "Confirm",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = window.body,
	})
	confirmAvatar = UI.make(Instance.new("ImageLabel"), {
		Name = "Avatar",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = COLORS.panelTop,
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(120, 120),
		Parent = confirmPage,
	})
	UI.corner(confirmAvatar, UDim.new(0.5, 0))
	UI.stroke(confirmAvatar, 3, PINK)
	confirmText = UI.label({
		Title = true,
		Text = "",
		TextWrapped = true,
		Position = UDim2.fromOffset(0, 136),
		Size = UDim2.new(1, 0, 0, 70),
		Parent = confirmPage,
	})
	UI.maxText(confirmText, 28)
	buyButton = UI.button({
		Name = "Buy",
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 216),
		Size = UDim2.new(0.7, 0, 0, 56),
		BackgroundColor3 = COLORS.green,
		Parent = confirmPage,
	})
	UI.maxText(buyButton, 26)
	buyButton.Activated:Connect(function()
		UI.pop(buyButton)
		buy()
	end)
	local back = UI.button({
		Name = "Back",
		Text = "BACK",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 282),
		Size = UDim2.new(0.4, 0, 0, 44),
		BackgroundColor3 = COLORS.panelTop,
		Parent = confirmPage,
	})
	UI.maxText(back, 20)
	back.Activated:Connect(function()
		UI.pop(back)
		showPick()
	end)
	confirmStatus = UI.label({
		Text = "",
		TextColor3 = COLORS.subtext,
		TextWrapped = true,
		Position = UDim2.fromOffset(0, 334),
		Size = UDim2.new(1, 0, 0, 40),
		Parent = confirmPage,
	})
	UI.maxText(confirmStatus, 18)

	Net.get("GiftNews").OnClientEvent:Connect(onNews)
end

return GiftUI
