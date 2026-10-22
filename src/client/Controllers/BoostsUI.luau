--!strict
-- Boosts panel (from the menu): the store. Two tabs, GAME PASSES and VOLTS,
-- each a grid of cards (icon, name, what it gives, Robux price). LAYOUT
-- ONLY: nothing is on sale yet (Config.STORE), so Buy says "coming soon".

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Layout = require(script.Parent.Parent.Lib.Layout)
local UI = require(script.Parent.Parent.Lib.UI)

local COLORS = UI.COLORS
local ROBUX = utf8.char(0xE002) -- Roblox's fonts draw the Robux icon for this
local CARD_HEIGHT = 168
local TAB_HEIGHT = 46

type Card = { icon: string, name: string, detail: string, price: number }
type Tab = { button: TextButton, grid: ScrollingFrame }

local BoostsUI = {}

local panel: Frame
local tabs: { Tab } = {}
local grids: { UIGridLayout } = {}

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

local function buildCard(parent: Instance, order: number, card: Card)
	local frame = UI.make(Instance.new("Frame"), {
		Name = card.name,
		LayoutOrder = order,
		BackgroundColor3 = COLORS.panelDark,
		Parent = parent,
	})
	UI.corner(frame, UDim.new(0, 14))
	UI.stroke(frame, 3)
	local icon = UI.label({
		Title = true,
		Text = card.icon,
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.fromOffset(54, 54),
		Parent = frame,
	})
	UI.maxText(icon, 44)
	local name = UI.label({
		Title = true,
		Text = string.upper(card.name),
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.new(0, 72, 0, 12),
		Size = UDim2.new(1, -82, 0, 26),
		Parent = frame,
	})
	UI.maxText(name, 24)
	local detail = UI.label({
		Text = card.detail,
		TextColor3 = COLORS.subtext,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Position = UDim2.new(0, 72, 0, 40),
		Size = UDim2.new(1, -82, 0, 40),
		Parent = frame,
	})
	UI.maxText(detail, 17)
	local soon = UI.label({
		Text = "COMING SOON",
		TextColor3 = COLORS.volt,
		Position = UDim2.new(0, 10, 0, 86),
		Size = UDim2.new(1, -20, 0, 16),
		Parent = frame,
	})
	UI.maxText(soon, 14)
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
	buy.Activated:Connect(function()
		UI.pop(buy)
		UI.toast(`{card.name} is coming soon!`, "volt")
	end)
end

local function buildTab(body: Frame, order: number, title: string, cards: { Card }): Tab
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
	for index, card in cards do
		buildCard(grid, index, card)
	end
	local tab = { button = button, grid = grid }
	button.Activated:Connect(function()
		UI.pop(button)
		selectTab(tab)
	end)
	table.insert(tabs, tab)
	return tab
end

function BoostsUI.init()
	local _, root = Layout.screen("StormBottlerBoosts", 5)
	local window = UI.window(root, "BoostsPanel", "🚀 BOOSTS", COLORS.volt, Vector2.new(680, 560))
	panel = window.panel

	local passes: { Card } = {}
	for _, pass in Config.STORE.passes do
		table.insert(
			passes,
			{ icon = pass.icon, name = pass.name, detail = pass.detail, price = pass.price }
		)
	end
	local volts: { Card } = {}
	for _, pack in Config.STORE.volts do
		table.insert(volts, {
			icon = pack.icon,
			name = pack.name,
			detail = `+{Format.abbreviate(pack.volts)} ⚡ Volts`,
			price = pack.price,
		})
	end
	local first = buildTab(window.body, 1, "GAME PASSES", passes)
	buildTab(window.body, 2, "VOLTS", volts)
	selectTab(first)
	fitColumns()
	Layout.Changed:Connect(fitColumns)
end

return BoostsUI
