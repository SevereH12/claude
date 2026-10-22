--!strict
-- Boosts panel (from the menu): the store. Two tabs, GAME PASSES and VOLTS,
-- each a grid of cards (icon, name, what it gives, Robux price). Prices are
-- Roblox's (GetProductInfo: price optimization can personalise them);
-- Config's only show until they load. BUY opens Roblox's purchase window,
-- only ever when tapped; the server grants (Systems/Passes, Receipts).
--   GAME PASSES: Config.PASSES. Owned passes say OWNED; a pass with no id
--     yet says COMING SOON. Bolt Colours owners get CHOOSE COLOUR instead,
--     which opens a colour picker (SetBoltColour, checked by
--     Systems/PassPerks). The 2x Volts card shows what 2x would really have
--     added this session (from the server).
--   VOLTS: Config.VOLT_PACKS, each showing this player's real amount (it
--     grows with progress: Util/Store) and about how long it takes to catch.
-- The store reports visits, card taps and purchase windows for the stats
-- (StoreEvent: Systems/Store). BoostsUI.openAt(key) opens it at one card
-- (the offers' SEE).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Net = require(ReplicatedStorage.Shared.Net)
local PassRules = require(ReplicatedStorage.Shared.Util.Passes)
local Store = require(ReplicatedStorage.Shared.Util.Store)
local Types = require(ReplicatedStorage.Shared.Types)
local Layout = require(script.Parent.Parent.Lib.Layout)
local UI = require(script.Parent.Parent.Lib.UI)
local State = require(script.Parent.State)

local COLORS = UI.COLORS
local ROBUX = utf8.char(0xE002) -- Roblox's fonts draw the Robux icon for this
local CARD_HEIGHT = 168
local CARD_GAP = 10
local TAB_HEIGHT = 46
local SWATCH_HEIGHT = 56
local DEFAULT_BOLT = Color3.fromRGB(120, 175, 255) -- StrikeFX's default glow

type Card = {
	icon: string,
	image: number, -- icon asset id, 0 = show the emoji
	name: string,
	detail: string,
	price: number,
}
type CardParts = { frame: Frame, buy: TextButton, detail: TextLabel, status: TextLabel }
type Tab = { button: TextButton, grid: ScrollingFrame }
type Placed = { tab: Tab, order: number, parts: CardParts } -- where a card is, for openAt
type PassCard = { pass: Types.PassDef, parts: CardParts }
type PackCard = { pack: Types.VoltPackDef, parts: CardParts }
type Swatch = { index: number, button: TextButton }

local BoostsUI = {}

local player = Players.LocalPlayer
local storeEvent: RemoteEvent
local panel: Frame
local tabs: { Tab } = {}
local grids: { UIGridLayout } = {}
local placed: { [string]: Placed } = {} -- by pass or pack key
local passCards: { PassCard } = {}
local packCards: { PackCard } = {}
local prices: { [string]: number } = {} -- pass or pack key -> Robux, from Roblox
local picker: Frame
local pickerGrid: UIGridLayout
local swatches: { Swatch } = {}

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

local function oneColumn(): boolean
	return Layout.class == "Phone" and Layout.portrait
end

-- Two cards a row, one on a phone held upright (colour swatches: three
-- a row, two upright).
local function fitColumns()
	local one = oneColumn()
	for _, grid in grids do
		grid.CellSize = if one
			then UDim2.new(1, -8, 0, CARD_HEIGHT)
			else UDim2.new(0.5, -10, 0, CARD_HEIGHT)
	end
	pickerGrid.CellSize = if one
		then UDim2.new(0.5, -10, 0, SWATCH_HEIGHT)
		else UDim2.new(1 / 3, -10, 0, SWATCH_HEIGHT)
end

function BoostsUI.open()
	picker.Visible = false
	if not panel.Visible then
		storeEvent:FireServer("open")
	end
	UI.openPanel(panel)
end

-- Opens the store at one pass or pack card, scrolled into view and lit up.
function BoostsUI.openAt(key: string)
	BoostsUI.open()
	local card = placed[key]
	if not card then
		return
	end
	selectTab(card.tab)
	-- scroll once the grid has laid out (a frame later)
	local columns = if oneColumn() then 1 else 2
	local row = (card.order - 1) // columns
	task.spawn(function()
		RunService.Heartbeat:Wait()
		card.tab.grid.CanvasPosition = Vector2.new(0, row * (CARD_HEIGHT + CARD_GAP))
	end)
	local stroke = card.parts.frame:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = COLORS.volt
		stroke.Thickness = 5
		task.delay(2, function()
			stroke.Color = COLORS.stroke
			stroke.Thickness = 3
		end)
	end
	UI.pop(card.parts.frame, 1.05)
end

-- `onLook`: the card (anywhere, BUY included) was tapped.
local function buildCard(parent: Instance, order: number, card: Card, onLook: () -> ()): CardParts
	local frame = UI.make(Instance.new("Frame"), {
		Name = card.name,
		LayoutOrder = order,
		BackgroundColor3 = COLORS.panelDark,
		Parent = parent,
	})
	UI.corner(frame, UDim.new(0, 14))
	UI.stroke(frame, 3)
	-- under everything else on the card: a tap anywhere counts as a look
	local look = UI.make(Instance.new("TextButton"), {
		Name = "Look",
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
		Parent = frame,
	})
	look.Activated:Connect(function()
		UI.pop(frame, 1.03)
		onLook()
	end)
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
	return { frame = frame, buy = buy, detail = detail, status = status }
end

-- What the 2x Volts card says under its description: only true numbers.
local function doubleVoltsNote(snapshot: Types.Snapshot): string
	local store = snapshot.store
	if workspace:GetServerTimeNow() < store.trialEndsAt then
		return "🎁 YOUR FREE TRIAL IS ON"
	elseif store.missedDouble > 0 then
		return `+{Format.abbreviate(store.missedDouble)} Volts this session with 2x`
	end
	return ""
end

-- Every card: OWNED, COMING SOON, or its price and BUY; packs show this
-- player's amount.
local function render()
	local snapshot = State.current
	local owned = if snapshot then snapshot.passes else {}
	for _, card in passCards do
		local pass, parts = card.pass, card.parts
		if owned[pass.key] and pass.key == "BoltColours" then
			parts.buy.Text = "🎨 CHOOSE COLOUR"
			parts.status.Text = "✓ OWNED"
			UI.setEnabled(parts.buy, true, COLORS.storm)
		elseif owned[pass.key] then
			parts.buy.Text = "✓ OWNED"
			parts.status.Text = ""
			UI.setEnabled(parts.buy, false, COLORS.green)
		elseif pass.id == 0 then
			parts.buy.Text = `{ROBUX} {Format.abbreviate(pass.price)}`
			parts.status.Text = "COMING SOON"
			UI.setEnabled(parts.buy, false, COLORS.green)
		else
			parts.buy.Text = `{ROBUX} {Format.abbreviate(prices[pass.key] or pass.price)}`
			parts.status.Text = if pass.key == "DoubleVolts" and snapshot
				then doubleVoltsNote(snapshot)
				else ""
			UI.setEnabled(parts.buy, true, COLORS.green)
		end
	end
	for _, card in packCards do
		local pack, parts = card.pack, card.parts
		if snapshot then
			parts.detail.Text = `+{Format.abbreviate(Store.packVolts(pack, snapshot))} ⚡ Volts`
		end
		parts.buy.Text = `{ROBUX} {Format.abbreviate(prices[pack.key] or pack.price)}`
		if pack.productId == 0 then
			parts.status.Text = "COMING SOON"
			UI.setEnabled(parts.buy, false, COLORS.green)
		else
			parts.status.Text = `{Store.packTime(pack)} of catching`
			UI.setEnabled(parts.buy, true, COLORS.green)
		end
	end
end

-- The picker's swatches: the current pick ticked and outlined in gold. The
-- default swatch is VIP gold for a VIP.
local function renderPicker()
	local current = player:GetAttribute(PassRules.BOLT_ATTRIBUTE)
	local picked = if typeof(current) == "number" then current else 0
	local vip = State.current ~= nil and State.current.passes.VIP == true
	for _, swatch in swatches do
		local name = if swatch.index > 0
			then Config.BOLT_COLOURS[swatch.index].name
			elseif vip then "VIP Gold"
			else "Default"
		local selected = swatch.index == picked
		swatch.button.Text = if selected then `✓ {name}` else name
		if swatch.index == 0 then
			swatch.button.BackgroundColor3 = if vip then Config.VIP_GOLD else DEFAULT_BOLT
		end
		local stroke = swatch.button:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if selected then COLORS.volt else COLORS.stroke
			stroke.Thickness = if selected then 5 else 3
		end
	end
end

local function openPicker()
	renderPicker()
	picker.Visible = true
end

-- Bolt Colours owners: the default and Config.BOLT_COLOURS as swatches, over
-- the store's tabs.
local function buildPicker(body: Frame)
	picker = UI.make(Instance.new("Frame"), {
		Name = "BoltColourPicker",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = COLORS.panelDark,
		Active = true, -- taps don't fall through to the cards underneath
		Visible = false,
		ZIndex = 10,
		Parent = body,
	})
	UI.corner(picker, UDim.new(0, 14))
	UI.stroke(picker, 3)
	local title = UI.label({
		Title = true,
		Text = "🎨 CHOOSE YOUR LIGHTNING",
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(14, 10),
		Size = UDim2.new(1, -86, 0, 36),
		Parent = picker,
	})
	UI.maxText(title, 26)
	local close = UI.button({
		Name = "Close",
		Text = "✕",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
		Size = UDim2.fromOffset(52, 42),
		BackgroundColor3 = COLORS.red,
		Parent = picker,
	})
	close.Activated:Connect(function()
		UI.pop(close)
		picker.Visible = false
	end)
	local hint = UI.label({
		Text = "Your lightning arcs and bottle glow in this colour. Everyone sees it!",
		TextColor3 = COLORS.subtext,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(14, 52),
		Size = UDim2.new(1, -28, 0, 20),
		Parent = picker,
	})
	UI.maxText(hint, 17)
	local grid = UI.make(Instance.new("ScrollingFrame"), {
		Name = "Swatches",
		Position = UDim2.fromOffset(10, 82),
		Size = UDim2.new(1, -20, 1, -92),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = picker,
	})
	pickerGrid = UI.make(Instance.new("UIGridLayout"), {
		CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	UI.make(Instance.new("UIPadding"), {
		PaddingTop = UDim.new(0, 4),
		PaddingLeft = UDim.new(0, 4),
		Parent = grid,
	})
	local remote = Net.get("SetBoltColour")
	for index = 0, #Config.BOLT_COLOURS do
		local button = UI.button({
			Name = `Colour{index}`,
			LayoutOrder = index,
			Text = "",
			BackgroundColor3 = if index == 0
				then DEFAULT_BOLT
				else Config.BOLT_COLOURS[index].color,
			Parent = grid,
		})
		UI.maxText(button, 20)
		button.Activated:Connect(function()
			UI.pop(button)
			remote:FireServer(index)
		end)
		table.insert(swatches, { index = index, button = button })
	end
	player:GetAttributeChangedSignal(PassRules.BOLT_ATTRIBUTE):Connect(renderPicker)
end

-- Roblox's real price for an item, once per session.
local function loadPrice(key: string, id: number, infoType: Enum.InfoType)
	if id == 0 or prices[key] then
		return
	end
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(id, infoType)
		end)
		if ok and typeof(info) == "table" and typeof(info.PriceInRobux) == "number" then
			prices[key] = info.PriceInRobux
			render()
		end
	end)
end

-- Opens Roblox's purchase window: only ever because the player tapped BUY.
local function prompt(key: string, open: () -> ())
	local ok, err = pcall(open)
	if ok then
		storeEvent:FireServer("prompt", key)
	else
		warn(`[BoostsUI] couldn't open the purchase window: {err}`)
		UI.toast("The store isn't available right now. Try again soon.", "warn")
	end
end

local function buildPassCard(tab: Tab, order: number, pass: Types.PassDef)
	local parts = buildCard(tab.grid, order, {
		icon = pass.icon,
		image = pass.image,
		name = pass.name,
		detail = pass.detail,
		price = pass.price,
	}, function()
		storeEvent:FireServer("card", pass.key)
	end)
	parts.buy.Activated:Connect(function()
		UI.pop(parts.buy)
		storeEvent:FireServer("card", pass.key)
		local owned = State.current and State.current.passes[pass.key]
		if owned and pass.key == "BoltColours" then
			openPicker()
		elseif owned then
			return
		elseif pass.id == 0 then
			UI.toast(`{pass.name} is coming soon!`, "volt")
		else
			prompt(pass.key, function()
				MarketplaceService:PromptGamePassPurchase(player, pass.id)
			end)
		end
	end)
	table.insert(passCards, { pass = pass, parts = parts })
	placed[pass.key] = { tab = tab, order = order, parts = parts }
	loadPrice(pass.key, pass.id, Enum.InfoType.GamePass)
end

local function buildPackCard(tab: Tab, order: number, pack: Types.VoltPackDef)
	local parts = buildCard(tab.grid, order, {
		icon = pack.icon,
		image = pack.image,
		name = pack.name,
		detail = "",
		price = pack.price,
	}, function()
		storeEvent:FireServer("card", pack.key)
	end)
	parts.buy.Activated:Connect(function()
		UI.pop(parts.buy)
		storeEvent:FireServer("card", pack.key)
		if pack.productId == 0 then
			UI.toast(`{pack.name} is coming soon!`, "volt")
			return
		end
		prompt(pack.key, function()
			MarketplaceService:PromptProductPurchase(player, pack.productId)
		end)
	end)
	table.insert(packCards, { pack = pack, parts = parts })
	placed[pack.key] = { tab = tab, order = order, parts = parts }
	loadPrice(pack.key, pack.productId, Enum.InfoType.Product)
end

local function buildTab(body: Frame, order: number, title: string): Tab
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
		CellPadding = UDim2.fromOffset(CARD_GAP, CARD_GAP),
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
	return tab
end

function BoostsUI.init()
	storeEvent = Net.get("StoreEvent")
	local _, root = Layout.screen("StormBottlerBoosts", 5)
	local window = UI.window(root, "BoostsPanel", "🚀 BOOSTS", COLORS.volt, Vector2.new(680, 560))
	panel = window.panel

	local passTab = buildTab(window.body, 1, "GAME PASSES")
	for index, pass in Config.PASSES do
		buildPassCard(passTab, index, pass)
	end
	local voltTab = buildTab(window.body, 2, "VOLTS")
	for index, pack in Config.VOLT_PACKS do
		buildPackCard(voltTab, index, pack)
	end
	buildPicker(window.body)
	selectTab(passTab)
	fitColumns()
	Layout.Changed:Connect(fitColumns)
	render()
end

function BoostsUI.start()
	render()
	State.Changed:Connect(function()
		render()
		if picker.Visible then
			renderPicker() -- VIP bought while it's open: the default swatch turns gold
		end
	end)
	-- the 2x Volts card's trial note ends with the trial
	while true do
		task.wait(1)
		if panel.Visible then
			render()
		end
	end
end

return BoostsUI
