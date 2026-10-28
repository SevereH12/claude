--!strict
-- The one MENU button on the left edge and the card it opens: five tiles,
-- SHOP, RESEARCH, TELEPORT, BOOSTS and REWARDS (three across, the last two
-- centred under them), that pop in one after another over a dimmed
-- screen. A red dot on REWARDS and on the MENU button means a reward is
-- ready to claim; a yellow dot on SHOP means you can afford the next bottle
-- or boots, on RESEARCH the next researcher.
-- Picking a tile closes the card and opens that panel. The card also
-- closes on the menu button, a click or tap anywhere else (the dim
-- backdrop behind it), Esc or gamepad B (Controllers/Shortcuts). On a
-- gamepad, Y opens it and the first tile is selected. Shortcut chips show
-- the gamepad button to gamepad players only ("Y" on MENU) and the key to
-- PC players only (M, and B, R, T, P on the tiles); none on touch.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Layout = require(script.Parent.Parent.Lib.Layout)
local Sfx = require(script.Parent.Parent.Lib.Sfx)
local UI = require(script.Parent.Parent.Lib.UI)
local BoostsUI = require(script.Parent.BoostsUI)
local ResearchUI = require(script.Parent.ResearchUI)
local RewardsUI = require(script.Parent.RewardsUI)
local SettingsUI = require(script.Parent.SettingsUI)
local ShopUI = require(script.Parent.ShopUI)
local State = require(script.Parent.State)
local TeleportUI = require(script.Parent.TeleportUI)

local COLORS = UI.COLORS
local TILE = Vector2.new(118, 90)
local COLUMNS = 3
local GAP = 10
local PAD = 12
local STAGGER = 0.045

local CARD_IN = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CARD_OUT = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local ICON_TURN = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local DIM_FADE = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local DIM = 0.55 -- the backdrop's transparency while the card is open

-- `action`: its shortcut's action (Util/Settings.ACTIONS, Controllers/Shortcuts)
type Item = { name: string, icon: string, color: Color3, action: string, open: () -> () }

local ITEMS: { Item } = {
	{ name = "SHOP", icon = "🛒", color = COLORS.green, action = "Shop", open = ShopUI.open },
	{
		name = "RESEARCH",
		icon = "🔬",
		color = COLORS.storm,
		action = "Research",
		open = ResearchUI.open,
	},
	{
		name = "TELEPORT",
		icon = "🌀",
		color = Color3.fromRGB(165, 110, 255),
		action = "Teleport",
		open = TeleportUI.open,
	},
	{
		name = "BOOSTS",
		icon = "🚀",
		color = COLORS.volt,
		action = "Boosts",
		open = BoostsUI.open,
	},
	{
		name = "REWARDS",
		icon = "🎁",
		color = Color3.fromRGB(255, 120, 170),
		action = "Rewards",
		open = RewardsUI.open,
	},
	{
		name = "SETTINGS",
		icon = "⚙️",
		color = Color3.fromRGB(120, 130, 160),
		action = "Settings",
		open = SettingsUI.open,
	},
}

local Menu = {}

local dock: Frame
local catcher: TextButton -- the dim backdrop behind the card: a click on it closes the card
local menuButton: TextButton
local icon: TextLabel
local card: Frame
local cardScale: UIScale
local tileScales: { UIScale } = {}
local dots: { GuiObject } = {} -- "a reward is ready" dots: the MENU button's and the REWARDS tile's
local buyDots: { [string]: GuiObject } = {} -- "you can afford the next one": SHOP's and RESEARCH's
local tiles: { [string]: TextButton } = {} -- by item name (the tutorial points at SHOP)
local isOpen = false
local token = 0

function Menu.isOpen(): boolean
	return isOpen
end

-- The MENU button and a tile ("SHOP"), for the tutorial to point at.
function Menu.button(): GuiObject?
	return menuButton
end

function Menu.tile(name: string): GuiObject?
	return tiles[name]
end

local function setIcon(open: boolean)
	icon.Text = if open then "✕" else "☰"
	icon.Rotation = if open then -90 else 90
	TweenService:Create(icon, ICON_TURN, { Rotation = 0 }):Play()
end

function Menu.open()
	if isOpen then
		return
	end
	isOpen = true
	token += 1
	UI.closePanels()
	Sfx.play("menu_open")
	setIcon(true)
	catcher.Visible = true
	TweenService:Create(catcher, DIM_FADE, { BackgroundTransparency = DIM }):Play()
	card.Visible = true
	cardScale.Scale = 0.7
	TweenService:Create(cardScale, CARD_IN, { Scale = 1 }):Play()
	for index, scale in tileScales do
		scale.Scale = 0
		TweenService:Create(
			scale,
			TweenInfo.new(
				0.3,
				Enum.EasingStyle.Back,
				Enum.EasingDirection.Out,
				0,
				false,
				index * STAGGER
			),
			{ Scale = 1 }
		):Play()
	end
	UI.selectFirst(card)
end

function Menu.close()
	if not isOpen then
		return
	end
	isOpen = false
	token += 1
	Sfx.play("menu_close")
	local mine = token
	setIcon(false)
	local undim = TweenService:Create(catcher, DIM_FADE, { BackgroundTransparency = 1 })
	undim.Completed:Once(function()
		if token == mine then
			catcher.Visible = false
		end
	end)
	undim:Play()
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(card) then
		GuiService.SelectedObject = nil
	end
	for _, scale in tileScales do
		TweenService:Create(scale, CARD_OUT, { Scale = 0 }):Play()
	end
	local shrink = TweenService:Create(cardScale, CARD_OUT, { Scale = 0.7 })
	shrink.Completed:Once(function()
		if token == mine then
			card.Visible = false
		end
	end)
	shrink:Play()
end

function Menu.toggle()
	if isOpen then
		Menu.close()
	else
		Menu.open()
	end
end

-- A small dot in a button's top-left corner (top right is the shortcut
-- chip's): red while a reward is ready, or (`color`) another badge.
local function addDot(button: GuiObject, color: Color3?): Frame
	local dot = UI.make(Instance.new("Frame"), {
		Name = "ReadyDot",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.fromOffset(20, 20),
		BackgroundColor3 = color or COLORS.red,
		Visible = if color then false else RewardsUI.isReady(),
		ZIndex = 5,
		Parent = button,
	})
	UI.corner(dot, UDim.new(0.5, 0))
	UI.stroke(dot, 2)
	if not color then
		table.insert(dots, dot)
	end
	return dot
end

-- Can the player afford the next bottle or boots (SHOP), and the next
-- researcher to hire (RESEARCH: they're hired in order)?
local function canAfford(snapshot: Types.Snapshot): (boolean, boolean)
	local bottle = Config.BOTTLES[snapshot.bottleTier + 1]
	local boots = Config.BOOTS[snapshot.bootTier + 1]
	local shop = (bottle ~= nil and snapshot.volts >= bottle.price)
		or (boots ~= nil and snapshot.volts >= boots.price)
	local research = false
	for _, def in Config.RESEARCHERS do
		if not snapshot.researchers[def.id] then
			research = snapshot.volts >= def.price
			break
		end
	end
	return shop, research
end

-- RESEARCH's dot also lights when a Storm Log row can be claimed (its LOG tab).
local function renderBadges(snapshot: Types.Snapshot)
	local shop, research = canAfford(snapshot)
	research = research or ResearchUI.isReady()
	if buyDots.SHOP then
		buyDots.SHOP.Visible = shop
	end
	if buyDots.RESEARCH then
		buyDots.RESEARCH.Visible = research
	end
end

local function buildTile(index: number, item: Item)
	local col, row = (index - 1) % COLUMNS, (index - 1) // COLUMNS
	-- a short last row is centred under the full ones
	local inRow = math.min(COLUMNS, #ITEMS - row * COLUMNS)
	local x = PAD + (col + (COLUMNS - inRow) / 2) * (TILE.X + GAP)
	-- a cell holds the tile so the tile can scale from its own centre
	local cell = UI.make(Instance.new("Frame"), {
		Name = item.name,
		Position = UDim2.fromOffset(x, PAD + row * (TILE.Y + GAP)),
		Size = UDim2.fromOffset(TILE.X, TILE.Y),
		BackgroundTransparency = 1,
		Parent = card,
	})
	local tile = UI.button({
		Name = "Tile",
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = item.color,
		Parent = cell,
	})
	local corner = tile:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0, 16)
	end
	local scale = UI.make(Instance.new("UIScale"), { Scale = 0, Parent = tile })
	table.insert(tileScales, scale)
	tiles[item.name] = tile
	local glyph = UI.label({
		Title = true,
		Text = item.icon,
		Position = UDim2.fromScale(0, -0.02),
		Size = UDim2.fromScale(1, 0.6),
		Parent = tile,
	})
	UI.maxText(glyph, 40)
	local label = UI.label({
		Title = true,
		Text = item.name,
		Position = UDim2.fromScale(0, 0.6),
		Size = UDim2.fromScale(1, 0.36),
		Parent = tile,
	})
	UI.maxText(label, 20)
	tile.Activated:Connect(function()
		Menu.close()
		item.open()
	end)
	if item.open == RewardsUI.open then
		addDot(tile)
	elseif item.name == "SHOP" or item.name == "RESEARCH" then
		buyDots[item.name] = addDot(tile, COLORS.volt)
	end
	UI.padHint(tile, item.action)
end

-- The button and its card go where LayoutMath.hud says: the left edge,
-- in the middle on a PC or console, higher on touch (clear of the
-- thumbstick), with the card beside it.
local function place()
	UI.place(dock, Layout.hud.menu)
	UI.place(card, Layout.hud.card)
end

function Menu.init()
	local _, root = Layout.screen("StormBottlerMenu", 2)
	catcher = UI.make(Instance.new("TextButton"), {
		Name = "ClickAway",
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(-0.5, -0.5),
		Size = UDim2.fromScale(2, 2), -- past the safe area to the screen edges
		Visible = false,
		ZIndex = 1,
		Parent = root,
	})
	catcher.Activated:Connect(Menu.close)
	dock = UI.make(Instance.new("Frame"), {
		Name = "MenuDock",
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = root,
	})
	menuButton = UI.button({
		Name = "MenuButton",
		Text = "",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = COLORS.panelTop,
		Parent = dock,
	})
	local corner = menuButton:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0, 18)
	end
	icon = UI.label({
		Title = true,
		Text = "☰",
		TextColor3 = COLORS.volt,
		Position = UDim2.fromScale(0, -0.04),
		Size = UDim2.fromScale(1, 0.66),
		Parent = menuButton,
	})
	UI.maxText(icon, 40)
	local caption = UI.label({
		Title = true,
		Text = "MENU",
		Position = UDim2.fromScale(0, 0.6),
		Size = UDim2.fromScale(1, 0.32),
		Parent = menuButton,
	})
	UI.maxText(caption, 18)
	UI.padHint(menuButton, "Menu")
	addDot(menuButton)
	menuButton.Activated:Connect(function()
		UI.pop(menuButton)
		Menu.toggle()
	end)

	card = UI.panel({
		Name = "MenuCard",
		Visible = false,
		ZIndex = 2,
		Parent = root,
	})
	cardScale = card:FindFirstChildOfClass("UIScale")
		or UI.make(Instance.new("UIScale"), { Parent = card })
	for index, item in ITEMS do
		buildTile(index, item)
	end

	place()
	Layout.Changed:Connect(place)
	RewardsUI.ReadyChanged:Connect(function(isReady: boolean)
		for _, dot in dots do
			dot.Visible = isReady
		end
	end)
end

function Menu.start()
	if State.current then
		renderBadges(State.current)
	end
	State.Changed:Connect(renderBadges)
	ResearchUI.ReadyChanged:Connect(function()
		if State.current then
			renderBadges(State.current)
		end
	end)
end

return Menu
