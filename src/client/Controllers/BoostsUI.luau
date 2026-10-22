--!strict
-- Boosts panel (from the menu): the store. Two tabs, GAME PASSES and VOLTS,
-- each a grid of cards (icon, name, what it gives, Robux price).
--   GAME PASSES: Config.PASSES. The price shown is Roblox's (GetProductInfo:
--     price optimization can personalise it); Config's price only shows
--     until that loads. BUY opens Roblox's purchase window, only when
--     tapped; the server grants the pass (Systems/Passes). Owned passes say
--     OWNED; a pass with no id yet says COMING SOON.
--   VOLTS: LAYOUT ONLY for now (Config.STORE.volts): Buy says "coming soon".

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Types = require(ReplicatedStorage.Shared.Types)
local Layout = require(script.Parent.Parent.Lib.Layout)
local UI = require(script.Parent.Parent.Lib.UI)
local State = require(script.Parent.State)

local COLORS = UI.COLORS
local ROBUX = utf8.char(0xE002) -- Roblox's fonts draw the Robux icon for this
local CARD_HEIGHT = 168
local TAB_HEIGHT = 46

type Card = {
	icon: string,
	image: number, -- icon asset id, 0 = show the emoji
	name: string,
	detail: string,
	price: number,
}
type CardParts = { buy: TextButton, status: TextLabel }
type PassCard = { pass: Types.PassDef, parts: CardParts }
type Tab = { button: TextButton, grid: ScrollingFrame }

local BoostsUI = {}

local player = Players.LocalPlayer
local panel: Frame
local tabs: { Tab } = {}
local grids: { UIGridLayout } = {}
local passCards: { PassCard } = {}
local prices: { [number]: number } = {} -- pass id -> Robux, from Roblox

function BoostsUI.open()
	UI.openPanel(panel)
end

local function selectTab(selected: Tab)
	for _, tab in tabs do
		local on = tab == selected
		tab.button.BackgroundColor3 = if on then COLORS.volt else COLORS.panelDark
		if on and not tab.grid.Visible then
			-- slide the new page up into place
			tab.grid.Position = UDim2.fromOffset(0, TAB_HEIGHT + 30)
			tab.grid.Visible = true
			TweenService:Create(tab.grid, UI.TWEEN.open, {
				Position = UDim2.fromOffset(0, TAB_HEIGHT + 10),
			}):Play()
		elseif not on then
			tab.grid.Visible = false
		end
	end
end

-- Two cards a row, one on a phone held upright.
local function fitColumns()
	local one = Layout.class == "Phone" and Layout.portrait
	for _, grid in grids do
		grid.CellSize = if one
			then UDim2.new(1, -8, 0, CARD_HEIGHT)
			else UDim2.new(0.5, -10, 0, CARD_HEIGHT)
	end
end

local function buildCard(parent: Instance, order: number, card: Card): CardParts
	local frame = UI.make(Instance.new("Frame"), {
		Name = card.name,
		LayoutOrder = order,
		BackgroundColor3 = COLORS.panelDark,
		Parent = parent,
	})
	UI.corner(frame, UDim.new(0, 14))
	UI.stroke(frame, 3)
	if card.image ~= 0 then
		local image = UI.make(Instance.new("ImageLabel"), {
			Name = "Icon",
			Image = `rbxassetid://{card.image}`,
			BackgroundTransparency = 1,
			ScaleType = Enum.ScaleType.Fit,
			Position = UDim2.fromOffset(8, 8),
			Size = UDim2.fromOffset(58, 58),
			Parent = frame,
		})
		UI.corner(image, UDim.new(0, 10))
	else
		local icon = UI.label({
			Title = true,
			Text = card.icon,
			Position = UDim2.fromOffset(10, 10),
			Size = UDim2.fromOffset(54, 54),
			Parent = frame,
		})
		UI.maxText(icon, 44)
	end
	local name = UI.label({
		Title = true,
		Text = string.upper(card.name),
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.new(0, 76, 0, 12),
		Size = UDim2.new(1, -86, 0, 26),
		Parent = frame,
	})
	UI.maxText(name, 24)
	local detail = UI.label({
		Text = card.detail,
		TextColor3 = COLORS.subtext,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Position = UDim2.new(0, 76, 0, 40),
		Size = UDim2.new(1, -86, 0, 42),
		Parent = frame,
	})
	UI.maxText(detail, 17)
	local status = UI.label({
		Text = "",
		TextColor3 = COLORS.volt,
		Position = UDim2.new(0, 10, 0, 86),
		Size = UDim2.new(1, -20, 0, 16),
		Parent = frame,
	})
	UI.maxText(status, 14)
	local buy = UI.button({
		Name = "Buy",
		Text = `{ROBUX} {Format.abbreviate(card.price)}`,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, -20, 0, 48),
		BackgroundColor3 = COLORS.green,
		Parent = frame,
	})
	UI.maxText(buy, 24)
	return { buy = buy, status = status }
end

-- Every pass card: OWNED, COMING SOON, or its price and BUY.
local function renderPasses()
	local owned = if State.current then State.current.passes else {}
	for _, card in passCards do
		local pass, parts = card.pass, card.parts
		if owned[pass.key] then
			parts.buy.Text = "✓ OWNED"
			parts.status.Text = ""
			UI.setEnabled(parts.buy, false, COLORS.green)
		elseif pass.id == 0 then
			parts.buy.Text = `{ROBUX} {Format.abbreviate(pass.price)}`
			parts.status.Text = "COMING SOON"
			UI.setEnabled(parts.buy, false, COLORS.green)
		else
			parts.buy.Text = `{ROBUX} {Format.abbreviate(prices[pass.id] or pass.price)}`
			parts.status.Text = ""
			UI.setEnabled(parts.buy, true, COLORS.green)
		end
	end
end

-- Roblox's real price for a pass, once per session.
local function loadPrice(pass: Types.PassDef)
	if pass.id == 0 or prices[pass.id] then
		return
	end
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(pass.id, Enum.InfoType.GamePass)
		end)
		if ok and typeof(info) == "table" and typeof(info.PriceInRobux) == "number" then
			prices[pass.id] = info.PriceInRobux
			renderPasses()
		end
	end)
end

local function buildPassCard(grid: Instance, order: number, pass: Types.PassDef)
	local parts = buildCard(grid, order, {
		icon = pass.icon,
		image = pass.image,
		name = pass.name,
		detail = pass.detail,
		price = pass.price,
	})
	parts.buy.Activated:Connect(function()
		UI.pop(parts.buy)
		local owned = State.current and State.current.passes[pass.key]
		if owned then
			return
		elseif pass.id == 0 then
			UI.toast(`{pass.name} is coming soon!`, "volt")
			return
		end
		-- only ever because the player tapped BUY
		local ok, err = pcall(function()
			MarketplaceService:PromptGamePassPurchase(player, pass.id)
		end)
		if not ok then
			warn(`[BoostsUI] couldn't open the purchase window: {err}`)
			UI.toast("The store isn't available right now. Try again soon.", "warn")
		end
	end)
	table.insert(passCards, { pass = pass, parts = parts })
	loadPrice(pass)
end

local function buildTab(body: Frame, order: number, title: string): (Tab, ScrollingFrame)
	local button = UI.button({
		Name = title,
		Text = title,
		Position = UDim2.new((order - 1) * 0.5, if order == 1 then 0 else 6, 0, 0),
		Size = UDim2.new(0.5, -6, 0, TAB_HEIGHT),
		BackgroundColor3 = COLORS.panelDark,
		Parent = body,
	})
	UI.maxText(button, 22)
	local grid = UI.make(Instance.new("ScrollingFrame"), {
		Name = title .. "Grid",
		Position = UDim2.fromOffset(0, TAB_HEIGHT + 10),
		Size = UDim2.new(1, 0, 1, -(TAB_HEIGHT + 10)),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Visible = false,
		Parent = body,
	})
	local layout = UI.make(Instance.new("UIGridLayout"), {
		CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	table.insert(grids, layout)
	UI.make(Instance.new("UIPadding"), {
		PaddingTop = UDim.new(0, 4),
		PaddingLeft = UDim.new(0, 4),
		Parent = grid,
	})
	local tab = { button = button, grid = grid }
	button.Activated:Connect(function()
		UI.pop(button)
		selectTab(tab)
	end)
	table.insert(tabs, tab)
	return tab, grid
end

function BoostsUI.init()
	local _, root = Layout.screen("StormBottlerBoosts", 5)
	local window = UI.window(root, "BoostsPanel", "🚀 BOOSTS", COLORS.volt, Vector2.new(680, 560))
	panel = window.panel

	local first, passGrid = buildTab(window.body, 1, "GAME PASSES")
	for index, pass in Config.PASSES do
		buildPassCard(passGrid, index, pass)
	end
	local _, voltGrid = buildTab(window.body, 2, "VOLTS")
	for index, pack in Config.STORE.volts do
		local parts = buildCard(voltGrid, index, {
			icon = pack.icon,
			image = 0,
			name = pack.name,
			detail = `+{Format.abbreviate(pack.volts)} ⚡ Volts`,
			price = pack.price,
		})
		parts.status.Text = "COMING SOON"
		parts.buy.Activated:Connect(function()
			UI.pop(parts.buy)
			UI.toast(`{pack.name} is coming soon!`, "volt")
		end)
	end
	selectTab(first)
	fitColumns()
	Layout.Changed:Connect(fitColumns)
	renderPasses()
end

function BoostsUI.start()
	renderPasses()
	State.Changed:Connect(renderPasses)
end

return BoostsUI
