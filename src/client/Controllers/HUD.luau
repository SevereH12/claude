--!strict
-- The on-screen UI: coin counter, the big CLICK button, the upgrade shop and
-- the rebirth panel. It only shows state and asks the server for actions.
--
-- Layout (all Scale-based so it fits phones and desktops):
--   SimulatorHUD (ScreenGui)
--   ├── CoinPanel      top centre: coins + per-click / per-second stats
--   ├── ClickButton    bottom centre: round button
--   ├── SideBar        left: Shop / Rebirth buttons
--   ├── ShopPanel      centre popup: one row per upgrade
--   └── RebirthPanel   centre popup: cost, reward, confirm button

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Formulas = require(ReplicatedStorage.Shared.Util.Formulas)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local State = require(script.Parent.State)

local COLORS = {
	panel = Color3.fromRGB(30, 34, 54),
	panelDark = Color3.fromRGB(20, 23, 38),
	stroke = Color3.fromRGB(12, 14, 24),
	text = Color3.fromRGB(255, 255, 255),
	subtext = Color3.fromRGB(190, 196, 220),
	gold = Color3.fromRGB(255, 196, 46),
	green = Color3.fromRGB(70, 200, 100),
	purple = Color3.fromRGB(150, 90, 230),
	disabled = Color3.fromRGB(90, 94, 110),
	red = Color3.fromRGB(225, 70, 70),
}

local FONT = Enum.Font.FredokaOne
local POP_OUT = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POP_BACK = TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local PANEL_OPEN = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local COUNT_UP = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FLOAT_UP = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local MIN_CLICK_GAP = 1 / Config.MAX_CLICKS_PER_SECOND

type UpgradeRow = {
	def: Types.UpgradeDef,
	levelLabel: TextLabel,
	buyButton: TextButton,
}

local HUD = {}

local screenGui: ScreenGui
local coinsLabel: TextLabel
local statsLabel: TextLabel
local clickButton: TextButton
local shopPanel: Frame
local rebirthPanel: Frame
local rebirthInfo: TextLabel
local rebirthButton: TextButton
local upgradeRows: { UpgradeRow } = {}
local displayedCoins: NumberValue
local panelTweens: { [Instance]: Tween } = {}
local lastClick = 0

local clickRemote: RemoteEvent
local buyRemote: RemoteEvent
local rebirthRemote: RemoteEvent

-- UI helpers ---------------------------------------------------------------

local function make<T>(instance: T, props: { [string]: any }): T
	local parent = props.Parent
	for key, value in props do
		if key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end
	if parent then
		(instance :: any).Parent = parent
	end
	return instance
end

local function corner(parent: Instance, radius: UDim?)
	make(Instance.new("UICorner"), { CornerRadius = radius or UDim.new(0.2, 0), Parent = parent })
end

local function stroke(parent: Instance, thickness: number?)
	make(Instance.new("UIStroke"), {
		Color = COLORS.stroke,
		Thickness = thickness or 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

local function textStroke(parent: Instance)
	make(Instance.new("UIStroke"), {
		Color = COLORS.stroke,
		Thickness = 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Parent = parent,
	})
end

local function maxText(parent: Instance, size: number)
	make(Instance.new("UITextSizeConstraint"), { MaxTextSize = size, Parent = parent })
end

local function label(props: { [string]: any }): TextLabel
	local defaults: { [string]: any } = {
		BackgroundTransparency = 1,
		Font = FONT,
		TextColor3 = COLORS.text,
		TextScaled = true,
	}
	for key, value in props do
		defaults[key] = value
	end
	local newLabel = make(Instance.new("TextLabel"), defaults)
	textStroke(newLabel)
	return newLabel
end

local function button(props: { [string]: any }): TextButton
	local defaults: { [string]: any } = {
		AutoButtonColor = true,
		Font = FONT,
		TextColor3 = COLORS.text,
		TextScaled = true,
	}
	for key, value in props do
		defaults[key] = value
	end
	local newButton = make(Instance.new("TextButton"), defaults)
	corner(newButton)
	stroke(newButton)
	textStroke(newButton)
	make(Instance.new("UIPadding"), {
		PaddingTop = UDim.new(0.12, 0),
		PaddingBottom = UDim.new(0.12, 0),
		PaddingLeft = UDim.new(0.06, 0),
		PaddingRight = UDim.new(0.06, 0),
		Parent = newButton,
	})
	return newButton
end

local function pop(target: GuiObject)
	local scale = target:FindFirstChildOfClass("UIScale")
		or make(Instance.new("UIScale"), { Parent = target })
	local out = TweenService:Create(scale, POP_OUT, { Scale = 0.9 })
	out.Completed:Once(function()
		TweenService:Create(scale, POP_BACK, { Scale = 1 }):Play()
	end)
	out:Play()
end

-- Panels -------------------------------------------------------------------

local function setPanelOpen(panel: Frame, open: boolean)
	local scale = panel:FindFirstChildOfClass("UIScale")
	assert(scale, "panel needs a UIScale")
	local running = panelTweens[panel]
	if running then
		running:Cancel()
	end
	if open then
		panel.Visible = true
		scale.Scale = 0.6
		local tween = TweenService:Create(scale, PANEL_OPEN, { Scale = 1 })
		panelTweens[panel] = tween
		tween:Play()
	else
		panel.Visible = false
	end
end

local function togglePanel(panel: Frame)
	local opening = not panel.Visible
	-- only one popup at a time
	setPanelOpen(shopPanel, false)
	setPanelOpen(rebirthPanel, false)
	if opening then
		setPanelOpen(panel, true)
	end
end

local function makePanel(name: string, title: string, accent: Color3): (Frame, Frame)
	local panel = make(Instance.new("Frame"), {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.42, 0.62),
		BackgroundColor3 = COLORS.panel,
		Visible = false,
		Parent = screenGui,
	})
	corner(panel, UDim.new(0.05, 0))
	stroke(panel, 4)
	make(Instance.new("UIScale"), { Parent = panel })
	make(Instance.new("UISizeConstraint"), {
		MinSize = Vector2.new(300, 260),
		MaxSize = Vector2.new(560, 520),
		Parent = panel,
	})

	local header = make(Instance.new("Frame"), {
		Name = "Header",
		Size = UDim2.fromScale(1, 0.16),
		BackgroundColor3 = accent,
		Parent = panel,
	})
	corner(header, UDim.new(0.3, 0))
	maxText(
		label({
			Name = "Title",
			Text = title,
			Position = UDim2.fromScale(0.05, 0.15),
			Size = UDim2.fromScale(0.75, 0.7),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = header,
		}),
		36
	)

	local close = button({
		Name = "Close",
		Text = "X",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.97, 0.5),
		Size = UDim2.fromScale(0.75, 0.75),
		BackgroundColor3 = COLORS.red,
		Parent = header,
	})
	make(Instance.new("UIAspectRatioConstraint"), { Parent = close })
	close.Activated:Connect(function()
		setPanelOpen(panel, false)
	end)

	local body = make(Instance.new("Frame"), {
		Name = "Body",
		Position = UDim2.fromScale(0.04, 0.2),
		Size = UDim2.fromScale(0.92, 0.76),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	return panel, body
end

-- Build --------------------------------------------------------------------

local function buildCoinPanel()
	local coinPanel = make(Instance.new("Frame"), {
		Name = "CoinPanel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromScale(0.34, 0.12),
		BackgroundColor3 = COLORS.panel,
		Parent = screenGui,
	})
	corner(coinPanel, UDim.new(0.25, 0))
	stroke(coinPanel, 4)
	make(Instance.new("UISizeConstraint"), {
		MinSize = Vector2.new(220, 60),
		MaxSize = Vector2.new(480, 110),
		Parent = coinPanel,
	})

	coinsLabel = label({
		Name = "Coins",
		Text = "0",
		TextColor3 = COLORS.gold,
		Position = UDim2.fromScale(0.05, 0.06),
		Size = UDim2.fromScale(0.9, 0.58),
		Parent = coinPanel,
	})
	maxText(coinsLabel, 48)

	statsLabel = label({
		Name = "Stats",
		Text = "",
		TextColor3 = COLORS.subtext,
		Position = UDim2.fromScale(0.05, 0.64),
		Size = UDim2.fromScale(0.9, 0.3),
		Parent = coinPanel,
	})
	maxText(statsLabel, 22)
end

local function buildClickButton()
	clickButton = button({
		Name = "ClickButton",
		Text = "CLICK!",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.9),
		Size = UDim2.fromScale(0.24, 0.24),
		BackgroundColor3 = COLORS.gold,
		Parent = screenGui,
	})
	-- perfectly round, whatever the screen shape
	make(Instance.new("UIAspectRatioConstraint"), { Parent = clickButton })
	local roundCorner = clickButton:FindFirstChildOfClass("UICorner")
	if roundCorner then
		roundCorner.CornerRadius = UDim.new(0.5, 0)
	end
	maxText(clickButton, 54)
	make(Instance.new("UISizeConstraint"), {
		MinSize = Vector2.new(110, 110),
		MaxSize = Vector2.new(220, 220),
		Parent = clickButton,
	})
end

local function buildSideBar()
	local sideBar = make(Instance.new("Frame"), {
		Name = "SideBar",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.015, 0.5),
		Size = UDim2.fromScale(0.13, 0.3),
		BackgroundTransparency = 1,
		Parent = screenGui,
	})
	make(Instance.new("UISizeConstraint"), {
		MinSize = Vector2.new(90, 120),
		MaxSize = Vector2.new(170, 240),
		Parent = sideBar,
	})
	make(Instance.new("UIListLayout"), {
		Padding = UDim.new(0.06, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = sideBar,
	})

	local shopButton = button({
		Name = "ShopButton",
		Text = "Shop",
		LayoutOrder = 1,
		Size = UDim2.fromScale(1, 0.4),
		BackgroundColor3 = COLORS.green,
		Parent = sideBar,
	})
	shopButton.Activated:Connect(function()
		pop(shopButton)
		togglePanel(shopPanel)
	end)

	local rebirthOpen = button({
		Name = "RebirthButton",
		Text = "Rebirth",
		LayoutOrder = 2,
		Size = UDim2.fromScale(1, 0.4),
		BackgroundColor3 = COLORS.purple,
		Parent = sideBar,
	})
	rebirthOpen.Activated:Connect(function()
		pop(rebirthOpen)
		togglePanel(rebirthPanel)
	end)
end

local function buildShop()
	local body
	shopPanel, body = makePanel("ShopPanel", "Upgrades", COLORS.green)

	local list = make(Instance.new("ScrollingFrame"), {
		Name = "List",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = body,
	})
	make(Instance.new("UIListLayout"), {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = list,
	})

	for _, def in Formulas.sortedUpgrades() do
		local row = make(Instance.new("Frame"), {
			Name = def.id,
			LayoutOrder = def.order,
			Size = UDim2.new(1, -10, 0, 0),
			BackgroundColor3 = COLORS.panelDark,
			Parent = list,
		})
		-- height follows width so rows keep their shape on any screen
		make(Instance.new("UIAspectRatioConstraint"), { AspectRatio = 4.2, Parent = row })
		corner(row, UDim.new(0.15, 0))

		local nameLabel = label({
			Name = "Name",
			Text = def.name,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromScale(0.04, 0.1),
			Size = UDim2.fromScale(0.58, 0.42),
			Parent = row,
		})
		maxText(nameLabel, 28)

		local levelLabel = label({
			Name = "Level",
			Text = "Lv 0",
			TextColor3 = COLORS.gold,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromScale(0.04, 0.56),
			Size = UDim2.fromScale(0.58, 0.32),
			Parent = row,
		})
		maxText(levelLabel, 20)

		local buyButton = button({
			Name = "Buy",
			Text = "...",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(0.96, 0.5),
			Size = UDim2.fromScale(0.32, 0.7),
			BackgroundColor3 = COLORS.green,
			Parent = row,
		})
		maxText(buyButton, 26)
		buyButton.Activated:Connect(function()
			pop(buyButton)
			buyRemote:FireServer(def.id)
		end)

		table.insert(upgradeRows, { def = def, levelLabel = levelLabel, buyButton = buyButton })
	end
end

local function buildRebirth()
	local body
	rebirthPanel, body = makePanel("RebirthPanel", "Rebirth", COLORS.purple)

	rebirthInfo = label({
		Name = "Info",
		Text = "",
		TextWrapped = true,
		Size = UDim2.fromScale(1, 0.62),
		Parent = body,
	})
	maxText(rebirthInfo, 28)

	rebirthButton = button({
		Name = "Confirm",
		Text = "Rebirth",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.97),
		Size = UDim2.fromScale(0.6, 0.26),
		BackgroundColor3 = COLORS.purple,
		Parent = body,
	})
	maxText(rebirthButton, 34)
	rebirthButton.Activated:Connect(function()
		pop(rebirthButton)
		rebirthRemote:FireServer()
	end)
end

-- Rendering ----------------------------------------------------------------

local function floatText(text: string)
	local origin = clickButton.AbsolutePosition + clickButton.AbsoluteSize / 2
	local jitter = Vector2.new(math.random(-60, 60), math.random(-30, 10))
	local start = origin + jitter - Vector2.new(0, clickButton.AbsoluteSize.Y * 0.6)

	local floating = label({
		Text = text,
		TextColor3 = COLORS.gold,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(start.X, start.Y),
		Size = UDim2.fromOffset(140, 40),
		ZIndex = 5,
		Parent = screenGui,
	})
	local tween = TweenService:Create(floating, FLOAT_UP, {
		Position = UDim2.fromOffset(start.X, start.Y - 90),
		TextTransparency = 1,
	})
	tween.Completed:Once(function()
		floating:Destroy()
	end)
	tween:Play()
end

local function setEnabled(target: TextButton, enabled: boolean, color: Color3)
	target.BackgroundColor3 = if enabled then color else COLORS.disabled
	target.AutoButtonColor = enabled
end

local function render(snapshot: Types.Snapshot)
	TweenService:Create(displayedCoins, COUNT_UP, { Value = snapshot.coins }):Play()

	statsLabel.Text = string.format(
		"+%s / click  •  +%s / sec  •  %s",
		Format.abbreviate(Formulas.clickValue(snapshot)),
		Format.abbreviate(Formulas.autoIncome(snapshot)),
		Format.multiplier(Formulas.multiplier(snapshot))
	)

	for _, row in upgradeRows do
		local level = Formulas.level(snapshot, row.def.id)
		row.levelLabel.Text = `Lv {level}  •  {row.def.description}`
		if level >= row.def.maxLevel then
			row.buyButton.Text = "MAX"
			setEnabled(row.buyButton, false, COLORS.green)
		else
			local cost = Formulas.upgradeCost(row.def, level)
			row.buyButton.Text = Format.abbreviate(cost)
			setEnabled(row.buyButton, snapshot.coins >= cost, COLORS.green)
		end
	end

	local cost = Formulas.rebirthCost(snapshot.rebirths)
	local afterRebirth = { rebirths = snapshot.rebirths + 1, upgrades = {} }
	rebirthInfo.Text = string.format(
		"Rebirths: %d\n\nReset your coins and upgrades for +%d%% coins forever.\n\nCost: %s coins",
		snapshot.rebirths,
		math.floor(Config.REBIRTH_MULTIPLIER * 100),
		Format.abbreviate(cost)
	)
	rebirthButton.Text = if snapshot.coins >= cost
		then `Rebirth! ({Format.multiplier(Formulas.multiplier(afterRebirth))})`
		else `Need {Format.abbreviate(cost - snapshot.coins)} more`
	setEnabled(rebirthButton, snapshot.coins >= cost, COLORS.purple)
end

local function onClick()
	local now = os.clock()
	if now - lastClick < MIN_CLICK_GAP then
		return
	end
	lastClick = now
	clickRemote:FireServer()
	pop(clickButton)
	local snapshot = State.current
	if snapshot then
		floatText(`+{Format.abbreviate(Formulas.clickValue(snapshot))}`)
	end
end

-- Lifecycle ----------------------------------------------------------------

function HUD.init()
	clickRemote = Net.get("Click")
	buyRemote = Net.get("BuyUpgrade")
	rebirthRemote = Net.get("Rebirth")

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	screenGui = make(Instance.new("ScreenGui"), {
		Name = "SimulatorHUD",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	})

	displayedCoins =
		make(Instance.new("NumberValue"), { Name = "DisplayedCoins", Parent = screenGui })
	displayedCoins.Changed:Connect(function(value: number)
		coinsLabel.Text = `{Format.abbreviate(value)} coins`
	end)

	buildCoinPanel()
	buildClickButton()
	buildSideBar()
	buildShop()
	buildRebirth()

	clickButton.Activated:Connect(onClick)
end

function HUD.start()
	if State.current then
		render(State.current)
	end
	State.Changed:Connect(render)
end

return HUD
