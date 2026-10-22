--!strict
-- Shop popup with two tabs, BOTTLES and BOOTS. One row per tier; only the
-- next tier can be bought. Pressing Buy just asks the server, which checks
-- the price itself.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local Layout = require(script.Parent.Parent.Lib.Layout)
local UI = require(script.Parent.Parent.Lib.UI)
local State = require(script.Parent.State)

local COLORS = UI.COLORS
local ROW_HEIGHT = 76 -- pixels; the list scrolls when the rows don't fit

-- What a row shows, whichever kind of item it is.
type Item = { name: string, price: number, badge: string, detail: string }
type Row = { tier: number, item: Item, frame: Frame, button: TextButton }
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

function ShopUI.open()
	UI.openPanel(panel)
end

function ShopUI.toggle()
	UI.togglePanel(panel)
end

local function render(snapshot: Types.Snapshot)
	for _, tab in tabs do
		local owned = tab.ownedTier(snapshot)
		for _, row in tab.rows do
			if row.tier <= owned then
				row.button.Text = if row.tier == owned then "EQUIPPED" else "OWNED"
				UI.setEnabled(row.button, false, COLORS.green)
			elseif row.tier == owned + 1 then
				row.button.Text = `{Format.abbreviate(row.item.price)} ⚡`
				UI.setEnabled(row.button, snapshot.volts >= row.item.price, COLORS.green)
			else
				row.button.Text = "LOCKED"
				UI.setEnabled(row.button, false, COLORS.green)
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

local function buildRow(tab: Tab, tier: number, item: Item)
	local frame = UI.make(Instance.new("Frame"), {
		Name = item.name,
		LayoutOrder = tier,
		Size = UDim2.new(1, -12, 0, ROW_HEIGHT),
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
		tab.remote:FireServer(tier)
	end)

	table.insert(tab.rows, { tier = tier, item = item, frame = frame, button = button })
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
	local list = UI.make(Instance.new("ScrollingFrame"), {
		Name = title .. "List",
		Position = UDim2.fromOffset(0, 86),
		Size = UDim2.new(1, 0, 1, -86),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Visible = false,
		Parent = body,
	})
	UI.make(Instance.new("UIListLayout"), {
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = list,
	})
	UI.make(Instance.new("UIPadding"), {
		PaddingTop = UDim.new(0, 4),
		PaddingLeft = UDim.new(0, 4),
		Parent = list,
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
		})
	end

	local boots = buildTab(
		2,
		"BOOTS",
		"Boots make you faster inside storm zones, so you reach bolts first.",
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
