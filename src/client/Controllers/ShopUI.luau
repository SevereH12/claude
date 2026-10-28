--!strict
-- Shop popup with two tabs, BOTTLES and BOOTS. One row per tier; only the
-- next tier can be bought. Pressing Buy just asks the server, which checks
-- the price itself. Once you own the top bottle, an ASCEND row shows under
-- the bottles (Util/Ascension): its button asks the server, which opens the
-- confirm screen (Controllers/AscensionUI).
-- A next tier or ASCEND you can't afford yet still looks like a buy button
-- with its price: tapping it offers the Volts pack that covers the
-- difference (Controllers/TopUpUI). Owned and locked tiers stay greyed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AscensionRules = require(ReplicatedStorage.Shared.Util.Ascension)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Net = require(ReplicatedStorage.Shared.Net)
local PassRules = require(ReplicatedStorage.Shared.Util.Passes)
local Progression = require(ReplicatedStorage.Shared.Util.Progression)
local Speed = require(ReplicatedStorage.Shared.Util.Speed)
local Types = require(ReplicatedStorage.Shared.Types)
local Layout = require(script.Parent.Parent.Lib.Layout)
local Sfx = require(script.Parent.Parent.Lib.Sfx)
local UI = require(script.Parent.Parent.Lib.UI)
local AscensionUI = require(script.Parent.AscensionUI)
local State = require(script.Parent.State)
local TopUpUI = require(script.Parent.TopUpUI)

local COLORS = UI.COLORS
local ROW_HEIGHT = 76 -- pixels; the list scrolls when the rows don't fit

-- What a row shows, whichever kind of item it is. `describe`, if set,
-- re-reads the badge and detail from the latest snapshot (Big Bottles).
type Item = {
	name: string,
	price: number,
	badge: string,
	detail: string,
	describe: ((Types.Snapshot) -> (string, string))?,
}
type Row = {
	tier: number,
	item: Item,
	frame: Frame,
	button: TextButton,
	badge: TextLabel,
	detail: TextLabel,
}
type Tab = {
	title: string,
	hint: string,
	remote: RemoteEvent,
	ownedTier: (snapshot: Types.Snapshot) -> number,
	list: ScrollingFrame,
	button: TextButton,
	rows: { Row },
}

local ShopUI = {}

local panel: Frame
local body: Frame -- under the window's header (UI.window)
local hint: TextLabel
local tabs: { Tab } = {}
local current: Tab? = nil
local PURPLE = Color3.fromRGB(170, 110, 255)
type AscendRow = { frame: Frame, title: TextLabel, detail: TextLabel, button: TextButton }
local ascendRow: AscendRow? = nil

function ShopUI.open()
	UI.openPanel(panel)
end

function ShopUI.toggle()
	UI.togglePanel(panel)
end

function ShopUI.isOpen(): boolean
	return panel ~= nil and panel.Visible
end

-- The ASCEND row: shown once the top bottle is owned. Short of Volts, its
-- button shows the cost and offers a top-up (the server checks again).
local function renderAscend(snapshot: Types.Snapshot)
	local row = ascendRow
	if not row then
		return
	end
	row.frame.Visible = snapshot.bottleTier >= AscensionRules.topTier()
	local level = snapshot.ascension
	local stars = AscensionRules.stars(level)
	row.title.Text = if level > 0 then `ASCEND  {stars}` else "ASCEND"
	local cost = AscensionRules.cost(level)
	row.detail.Text =
		`Start again for {AscensionRules.bonusText(level + 1)} Volts for good · {Format.abbreviate(
			cost
		)} ⚡`
	local ready = AscensionRules.canAscend(snapshot)
	row.button.Text = if ready then "🌟 ASCEND" else `{Format.abbreviate(cost)} ⚡`
	-- only the top bottle (the row is hidden without it) or Volts stop it
	UI.setEnabled(row.button, snapshot.bottleTier >= AscensionRules.topTier(), PURPLE)
end

local function render(snapshot: Types.Snapshot)
	renderAscend(snapshot)
	for _, tab in tabs do
		local owned = tab.ownedTier(snapshot)
		for _, row in tab.rows do
			if row.tier <= owned then
				row.button.Text = if row.tier == owned then "EQUIPPED" else "OWNED"
				UI.setEnabled(row.button, false, COLORS.green)
			elseif row.tier == owned + 1 then
				row.button.Text = `{Format.abbreviate(row.item.price)} ⚡`
				UI.setEnabled(row.button, true, COLORS.green) -- short of Volts: a top-up offer
			else
				row.button.Text = "LOCKED"
				UI.setEnabled(row.button, false, COLORS.green)
			end
			if row.item.describe then
				row.badge.Text, row.detail.Text = row.item.describe(snapshot)
			end
			-- highlight the one you're using
			local stroke = row.frame:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = if row.tier == owned then COLORS.volt else COLORS.stroke
			end
		end
	end
end

local function selectTab(tab: Tab)
	current = tab
	for _, other in tabs do
		other.list.Visible = other == tab
		other.button.BackgroundColor3 = if other == tab then COLORS.volt else COLORS.panelDark
	end
	hint.Text = tab.hint
end

-- Opens the shop on the BOOTS tab (a gameplay tip, Controllers/Hints).
function ShopUI.openBoots()
	for _, tab in tabs do
		if tab.title == "BOOTS" then
			selectTab(tab)
		end
	end
	ShopUI.open()
end

-- The tutorial: shows the BOTTLES tab, scrolled to this tier's row, and
-- returns its Buy button to point at (nil if there's no such row).
function ShopUI.focusBottle(tier: number): GuiObject?
	local bottles = tabs[1]
	if not bottles then
		return nil
	end
	if current ~= bottles then
		selectTab(bottles)
	end
	for _, row in bottles.rows do
		if row.tier == tier then
			-- rows are ROW_HEIGHT tall with 10 between them, in tier order
			bottles.list.CanvasPosition = Vector2.new(0, (tier - 1) * (ROW_HEIGHT + 10))
			return row.button
		end
	end
	return nil
end

local function buildRow(tab: Tab, tier: number, item: Item)
	local frame = UI.make(Instance.new("Frame"), {
		Name = item.name,
		LayoutOrder = tier,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		BackgroundColor3 = COLORS.panelDark,
		Parent = tab.list,
	})
	UI.corner(frame, UDim.new(0.2, 0))
	UI.stroke(frame, 3)

	-- capacity / speed badge
	local badge = UI.make(Instance.new("Frame"), {
		Name = "Badge",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.03, 0.5),
		Size = UDim2.fromScale(0.75, 0.75),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = frame,
	})
	UI.corner(badge, UDim.new(0.5, 0))
	UI.stroke(badge, 3)
	UI.gradient(badge, COLORS.storm, COLORS.stormDeep)
	local badgeText = UI.label({
		Title = true,
		Text = item.badge,
		Position = UDim2.fromScale(0.12, 0.15),
		Size = UDim2.fromScale(0.76, 0.7),
		Parent = badge,
	})
	UI.maxText(badgeText, 30)

	local name = UI.label({
		Title = true,
		Text = string.upper(item.name),
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromScale(0.25, 0.12),
		Size = UDim2.fromScale(0.42, 0.42),
		Parent = frame,
	})
	UI.maxText(name, 28)
	local detail = UI.label({
		Text = item.detail,
		TextColor3 = COLORS.subtext,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromScale(0.25, 0.56),
		Size = UDim2.fromScale(0.42, 0.3),
		Parent = frame,
	})
	UI.maxText(detail, 20)

	local button = UI.button({
		Name = "Buy",
		Text = "...",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.97, 0.5),
		Size = UDim2.fromScale(0.29, 0.66),
		BackgroundColor3 = COLORS.green,
		Parent = frame,
	})
	UI.maxText(button, 24)
	button.Activated:Connect(function()
		UI.pop(button)
		-- the next tier, short of Volts: offer a top-up instead of asking
		local snapshot = State.current
		if snapshot and tier == tab.ownedTier(snapshot) + 1 and snapshot.volts < item.price then
			TopUpUI.volts(item.price - snapshot.volts)
			return
		end
		tab.remote:FireServer(tier)
	end)

	table.insert(tab.rows, {
		tier = tier,
		item = item,
		frame = frame,
		button = button,
		badge = badgeText,
		detail = detail,
	})
end

local function buildTab(
	order: number,
	title: string,
	tabHint: string,
	remote: RemoteEvent,
	ownedTier: (Types.Snapshot) -> number
): Tab
	local tabButton = UI.button({
		Name = title,
		Text = title,
		Position = UDim2.new((order - 1) * 0.5, if order == 1 then 0 else 6, 0, 0),
		Size = UDim2.new(0.5, -6, 0, 46),
		BackgroundColor3 = COLORS.panelDark,
		Parent = body,
	})
	UI.maxText(tabButton, 22)
	local list = UI.list(body, {
		Name = title .. "List",
		Position = UDim2.fromOffset(0, 86),
		Size = UDim2.new(1, 0, 1, -86),
		Visible = false,
		gap = 10,
	})
	local tab: Tab = {
		title = title,
		hint = tabHint,
		remote = remote,
		ownedTier = ownedTier,
		list = list,
		button = tabButton,
		rows = {},
	}
	tabButton.Activated:Connect(function()
		if current ~= tab then
			UI.pop(tabButton)
			Sfx.play("tab")
			selectTab(tab)
		end
	end)
	table.insert(tabs, tab)
	return tab
end

function ShopUI.init()
	local _, screenGui = Layout.screen("StormBottlerShop", 5)
	local window =
		UI.window(screenGui, "ShopPanel", "🛒 SHOP", COLORS.green, Vector2.new(600, 520))
	panel = window.panel
	body = window.body
	hint = UI.label({
		Text = "",
		TextColor3 = COLORS.subtext,
		Position = UDim2.fromOffset(0, 54),
		Size = UDim2.new(1, 0, 0, 24),
		Parent = body,
	})
	UI.maxText(hint, 18)

	local bottles = buildTab(
		1,
		"BOTTLES",
		"Bigger bottles hold more charges before you need to sell.",
		Net.get("BuyBottle"),
		function(snapshot)
			return snapshot.bottleTier
		end
	)
	for tier, bottle in Config.BOTTLES do
		buildRow(bottles, tier, {
			name = bottle.name,
			price = bottle.price,
			badge = tostring(bottle.capacity),
			detail = `Holds {bottle.capacity} charges`,
			describe = function(snapshot)
				local capacity = PassRules.capacity(bottle.capacity, snapshot.passes)
				return tostring(capacity), `Holds {capacity} charges`
			end,
		})
	end

	-- the ASCEND row, last in the bottles list
	do
		local frame = UI.make(Instance.new("Frame"), {
			Name = "Ascend",
			LayoutOrder = #Config.BOTTLES + 1,
			Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
			BackgroundColor3 = COLORS.panelDark,
			Visible = false,
			Parent = bottles.list,
		})
		UI.corner(frame, UDim.new(0.2, 0))
		UI.stroke(frame, 3, PURPLE)
		local title = UI.label({
			Title = true,
			Text = "ASCEND",
			TextColor3 = PURPLE,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromScale(0.04, 0.12),
			Size = UDim2.fromScale(0.6, 0.42),
			Parent = frame,
		})
		UI.maxText(title, 28)
		local detail = UI.label({
			Text = "",
			TextColor3 = COLORS.subtext,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromScale(0.04, 0.56),
			Size = UDim2.fromScale(0.63, 0.3),
			Parent = frame,
		})
		UI.maxText(detail, 18)
		local button = UI.button({
			Name = "AscendButton",
			Text = "🌟 ASCEND",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(0.97, 0.5),
			Size = UDim2.fromScale(0.29, 0.66),
			BackgroundColor3 = PURPLE,
			Parent = frame,
		})
		UI.maxText(button, 24)
		button.Activated:Connect(function()
			UI.pop(button)
			local snapshot = State.current
			if snapshot and snapshot.bottleTier >= AscensionRules.topTier() then
				local cost = AscensionRules.cost(snapshot.ascension)
				if snapshot.volts < cost then
					TopUpUI.volts(cost - snapshot.volts)
					return
				end
			end
			AscensionUI.ask()
		end)
		ascendRow = { frame = frame, title = title, detail = detail, button = button }
	end

	local boots = buildTab(
		2,
		"BOOTS",
		"Boots beat each zone's storm drag, so you reach bolts first.",
		Net.get("BuyBoots"),
		function(snapshot)
			return snapshot.bootTier
		end
	)
	for tier, def in Config.BOOTS do
		buildRow(boots, tier, {
			name = def.name,
			price = def.price,
			badge = `+{def.speedBonus}`,
			detail = if def.speedBonus > 0
				then `+{def.speedBonus} speed in storm zones`
				else "Your starter pair",
			-- the speed these boots give in the player's best zone, after
			-- its storm drag (Util/Speed)
			describe = function(snapshot)
				local badge = `+{def.speedBonus}`
				local zone = Progression.bestZone(snapshot)
				local base = if def.speedBonus > 0
					then `+{def.speedBonus} speed`
					else "Starter pair"
				if not zone then
					return badge, base
				end
				local speed = Speed.withDrag(tier, Speed.drag(zone, snapshot))
				return badge, `{base}: runs {speed} in {zone.displayName}`
			end,
		})
	end

	selectTab(bottles)
end

function ShopUI.start()
	if State.current then
		render(State.current)
	end
	State.Changed:Connect(render)
end

return ShopUI
