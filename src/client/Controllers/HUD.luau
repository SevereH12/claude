--!strict
-- Always-on screen UI. Shows state, never changes it.
--
--   StormBottlerHUD (ScreenGui)
--   ├── VoltsPanel   top centre: ⚡ Volts (counts up)
--   ├── StormPill    under Volts: "⚡ STORM 1:12" / "☀ CALM  storm in 0:15"
--   ├── GoalCard     under that: the closest next goal and Volts towards it
--   ├── CityMeter    top right: server city meter (placeholder until that update)
--   ├── ShopButton   left: opens the bottle shop
--   └── BottleBar    bottom centre: shiny fill + "JAR 3 / 5"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local Format = require(ReplicatedStorage.Shared.Util.Format)
local Formulas = require(ReplicatedStorage.Shared.Util.Formulas)
local Progression = require(ReplicatedStorage.Shared.Util.Progression)
local ResearchMath = require(ReplicatedStorage.Shared.Util.Research)
local Types = require(ReplicatedStorage.Shared.Types)
local UI = require(script.Parent.Parent.Lib.UI)
local ResearchUI = require(script.Parent.ResearchUI)
local ShopUI = require(script.Parent.ShopUI)
local State = require(script.Parent.State)
local Storm = require(script.Parent.Storm)

local COLORS = UI.COLORS
local FULL_PULSE = TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

local HUD = {}

local screenGui: ScreenGui
local voltsLabel: TextLabel
local stormPill: Frame
local stormLabel: TextLabel
local bottleBar: Frame
local bottleFill: Frame
local fillGradient: UIGradient
local bottleLabel: TextLabel
local bottleValue: TextLabel
local tankLabel: TextLabel
local goalCard: Frame
local goalTitle: TextLabel
local goalDetail: TextLabel
local goalFill: Frame
local goalAmount: TextLabel
local displayedVolts: NumberValue
local fullPulse: Tween?
local lastChargeCount = -1
local wasFull = false
local lastPhase: Types.StormPhase? = nil

local function buildVoltsPanel()
	local panel = UI.panel({
		Name = "VoltsPanel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromScale(0.24, 0.085),
		Parent = screenGui,
	})
	UI.sizeLimits(panel, Vector2.new(200, 50), Vector2.new(360, 76))

	local icon = UI.label({
		Title = true,
		Name = "Icon",
		Text = "⚡",
		Position = UDim2.fromScale(0.03, 0.1),
		Size = UDim2.fromScale(0.2, 0.8),
		Parent = panel,
	})
	UI.gradient(icon, COLORS.volt, COLORS.voltDeep)

	voltsLabel = UI.label({
		Title = true,
		Name = "Volts",
		Text = "0",
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromScale(0.24, 0.1),
		Size = UDim2.fromScale(0.72, 0.8),
		Parent = panel,
	})
	UI.gradient(voltsLabel, COLORS.volt, COLORS.voltDeep)
	UI.maxText(voltsLabel, 46)
end

local function buildStormPill()
	stormPill = UI.make(Instance.new("Frame"), {
		Name = "StormPill",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 92),
		Size = UDim2.fromScale(0.2, 0.048),
		BackgroundColor3 = COLORS.calm,
		Parent = screenGui,
	})
	UI.corner(stormPill, UDim.new(0.5, 0))
	UI.stroke(stormPill, 3)
	UI.gradient(stormPill, Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 185))
	UI.make(Instance.new("UIScale"), { Parent = stormPill })
	UI.sizeLimits(stormPill, Vector2.new(180, 30), Vector2.new(300, 42))
	stormLabel = UI.label({
		Title = true,
		Name = "Timer",
		Text = "...",
		Position = UDim2.fromScale(0.05, 0.12),
		Size = UDim2.fromScale(0.9, 0.76),
		Parent = stormPill,
	})
	UI.maxText(stormLabel, 26)
end

local function buildGoalCard()
	goalCard = UI.panel({
		Name = "GoalCard",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 140),
		Size = UDim2.fromScale(0.22, 0.085),
		Visible = false,
		Parent = screenGui,
	})
	UI.sizeLimits(goalCard, Vector2.new(210, 54), Vector2.new(330, 72))
	goalTitle = UI.label({
		Title = true,
		Name = "Title",
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromScale(0.05, 0.06),
		Size = UDim2.fromScale(0.9, 0.34),
		Parent = goalCard,
	})
	UI.maxText(goalTitle, 22)
	goalDetail = UI.label({
		Name = "Detail",
		Text = "",
		TextColor3 = COLORS.subtext,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromScale(0.05, 0.38),
		Size = UDim2.fromScale(0.9, 0.22),
		Parent = goalCard,
	})
	UI.maxText(goalDetail, 16)
	local bar = UI.make(Instance.new("Frame"), {
		Name = "Bar",
		Position = UDim2.fromScale(0.05, 0.66),
		Size = UDim2.fromScale(0.9, 0.24),
		BackgroundColor3 = COLORS.stroke,
		Parent = goalCard,
	})
	UI.corner(bar, UDim.new(0.5, 0))
	local clip = UI.make(Instance.new("CanvasGroup"), {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = bar,
	})
	UI.corner(clip, UDim.new(0.5, 0))
	goalFill = UI.make(Instance.new("Frame"), {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = COLORS.volt,
		BorderSizePixel = 0,
		Parent = clip,
	})
	goalAmount = UI.label({
		Name = "Amount",
		Text = "",
		Size = UDim2.fromScale(1, 1),
		Parent = bar,
	})
	UI.maxText(goalAmount, 14)
end

local function buildCityMeter()
	local meter = UI.panel({
		Name = "CityMeter",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 10),
		Size = UDim2.fromScale(0.17, 0.08),
		Parent = screenGui,
	})
	UI.sizeLimits(meter, Vector2.new(150, 46), Vector2.new(250, 68))
	local title = UI.label({
		Title = true,
		Text = "SERVER CITY",
		TextColor3 = COLORS.subtext,
		Position = UDim2.fromScale(0.06, 0.08),
		Size = UDim2.fromScale(0.88, 0.4),
		Parent = meter,
	})
	UI.maxText(title, 18)
	local track = UI.make(Instance.new("Frame"), {
		Position = UDim2.fromScale(0.06, 0.58),
		Size = UDim2.fromScale(0.88, 0.28),
		BackgroundColor3 = COLORS.panelDark,
		Parent = meter,
	})
	UI.corner(track, UDim.new(0.5, 0))
	local comingSoon = UI.label({
		Text = "coming soon",
		TextColor3 = COLORS.disabled,
		Size = UDim2.fromScale(1, 1),
		Parent = track,
	})
	UI.maxText(comingSoon, 13)
end

local function buildShopButton()
	local button = UI.button({
		Name = "ShopButton",
		Text = "SHOP",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.015, 0.5),
		Size = UDim2.fromScale(0.1, 0.075),
		BackgroundColor3 = COLORS.green,
		Parent = screenGui,
	})
	UI.sizeLimits(button, Vector2.new(96, 46), Vector2.new(150, 62))
	UI.maxText(button, 30)
	button.Activated:Connect(function()
		UI.pop(button)
		ShopUI.toggle()
	end)
end

local function buildResearchButton()
	local button = UI.button({
		Name = "ResearchButton",
		Text = "RESEARCH",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.015, 0.595),
		Size = UDim2.fromScale(0.1, 0.075),
		BackgroundColor3 = COLORS.storm,
		Parent = screenGui,
	})
	UI.sizeLimits(button, Vector2.new(96, 46), Vector2.new(150, 62))
	UI.maxText(button, 24)
	button.Activated:Connect(function()
		UI.pop(button)
		ResearchUI.toggle()
	end)
end

local function buildBottleBar()
	bottleBar = UI.panel({
		Name = "BottleBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromScale(0.36, 0.06),
		Parent = screenGui,
	})
	UI.sizeLimits(bottleBar, Vector2.new(260, 36), Vector2.new(480, 50))
	local barCorner = bottleBar:FindFirstChildOfClass("UICorner")
	if barCorner then
		barCorner.CornerRadius = UDim.new(0.5, 0)
	end

	-- CanvasGroup clips the fill to the bar's rounded shape
	local clip = UI.make(Instance.new("CanvasGroup"), {
		Name = "Clip",
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.new(1, -8, 1, -8),
		BackgroundColor3 = COLORS.panelDark,
		Parent = bottleBar,
	})
	UI.corner(clip, UDim.new(0.5, 0))
	bottleFill = UI.make(Instance.new("Frame"), {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = clip,
	})
	fillGradient = UI.make(Instance.new("UIGradient"), {
		Color = ColorSequence.new(COLORS.storm, COLORS.stormDeep),
		Parent = bottleFill,
	})
	-- glassy highlight across the top half
	UI.make(Instance.new("Frame"), {
		Name = "Shine",
		Size = UDim2.fromScale(1, 0.45),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = clip,
	})

	bottleLabel = UI.label({
		Title = true,
		Name = "Text",
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromScale(0.05, 0.14),
		Size = UDim2.fromScale(0.6, 0.72),
		ZIndex = 3,
		Parent = bottleBar,
	})
	UI.maxText(bottleLabel, 24)
	bottleValue = UI.label({
		Title = true,
		Name = "Value",
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.fromScale(0.6, 0.14),
		Size = UDim2.fromScale(0.35, 0.72),
		ZIndex = 3,
		Parent = bottleBar,
	})
	UI.gradient(bottleValue, COLORS.volt, COLORS.voltDeep)
	UI.maxText(bottleValue, 24)

	-- your Chemist's overflow tank, beside the bar
	tankLabel = UI.label({
		Title = true,
		Name = "Tank",
		Text = "",
		Visible = false,
		TextColor3 = COLORS.volt,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.new(1, 10, 0.1, 0),
		Size = UDim2.fromScale(0.3, 0.8),
		Parent = bottleBar,
	})
	UI.maxText(tankLabel, 20)
end

local function renderStorm()
	local state = Storm.current
	if not state then
		return
	end
	local seconds = math.ceil(Storm.secondsLeft())
	local clock = string.format("%d:%02d", seconds // 60, seconds % 60)
	if state.phase == "Storm" then
		stormLabel.Text = `⚡ STORM  {clock}`
		stormPill.BackgroundColor3 = COLORS.storm
	else
		stormLabel.Text = `☀ STORM IN {clock}`
		stormPill.BackgroundColor3 = COLORS.calm
	end
	if lastPhase ~= state.phase then
		lastPhase = state.phase
		UI.pop(stormPill, 1.25)
	end
end

local function setFull(full: boolean)
	if full and not fullPulse then
		fillGradient.Color = ColorSequence.new(COLORS.volt, COLORS.red)
		local pulse = TweenService:Create(bottleFill, FULL_PULSE, { BackgroundTransparency = 0.35 })
		fullPulse = pulse
		pulse:Play()
	elseif not full and fullPulse then
		fullPulse:Cancel()
		fullPulse = nil
		bottleFill.BackgroundTransparency = 0
		fillGradient.Color = ColorSequence.new(COLORS.storm, COLORS.stormDeep)
	end
end

local GOAL_TITLES: { [Progression.GoalKind]: string } = {
	zone = "UNLOCK",
	bottle = "NEXT BOTTLE:",
	boots = "NEXT BOOTS:",
}

local function renderGoal(snapshot: Types.Snapshot)
	local goal = Progression.nextGoals(snapshot)[1]
	goalCard.Visible = goal ~= nil
	if not goal then
		return
	end
	goalTitle.Text = `{GOAL_TITLES[goal.kind]} {string.upper(goal.title)}`
	goalDetail.Text = goal.detail
	local fraction = if goal.price > 0 then math.clamp(snapshot.volts / goal.price, 0, 1) else 1
	TweenService:Create(goalFill, UI.TWEEN.fast, { Size = UDim2.fromScale(fraction, 1) }):Play()
	goalAmount.Text = if fraction >= 1
		then "READY! Open the SHOP"
		else `{Format.abbreviate(snapshot.volts)} / {Format.abbreviate(goal.price)} ⚡`
end

local function render(snapshot: Types.Snapshot)
	TweenService:Create(displayedVolts, UI.TWEEN.countUp, { Value = snapshot.volts }):Play()
	renderGoal(snapshot)

	local bottle = Formulas.bottle(snapshot.bottleTier)
	local fraction = math.clamp(snapshot.chargeCount / bottle.capacity, 0, 1)
	TweenService:Create(bottleFill, UI.TWEEN.fast, { Size = UDim2.fromScale(fraction, 1) }):Play()

	-- full: the bar glows and a toast says so once (the text stays a count)
	local full = fraction >= 1
	setFull(full)
	if full and not wasFull and lastChargeCount >= 0 then
		UI.toastEvery("bottleFull", UI.FULL_REMINDER, UI.FULL_MESSAGE, "warn", true)
	end
	wasFull = full
	bottleLabel.Text = `{string.upper(bottle.name)}  {snapshot.chargeCount} / {bottle.capacity}`
	bottleValue.Text = `{Format.abbreviate(snapshot.chargeValue)} ⚡`

	local chemist = snapshot.researchers.Chemist
	tankLabel.Visible = chemist ~= nil
	if chemist then
		local capacity = ResearchMath.tankCapacity(chemist.level)
		tankLabel.Text = `TANK {snapshot.tankCount}/{capacity}`
	end

	if snapshot.chargeCount > lastChargeCount and lastChargeCount >= 0 then
		UI.pop(bottleBar, 1.08)
	end
	lastChargeCount = snapshot.chargeCount
end

function HUD.init()
	-- there are no tools in this game; hide the empty hotbar
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)

	screenGui = UI.make(Instance.new("ScreenGui"), {
		Name = "StormBottlerHUD",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	displayedVolts =
		UI.make(Instance.new("NumberValue"), { Name = "DisplayedVolts", Parent = screenGui })

	buildVoltsPanel()
	buildStormPill()
	buildGoalCard()
	buildCityMeter()
	buildShopButton()
	buildResearchButton()
	buildBottleBar()

	displayedVolts.Changed:Connect(function(value: number)
		voltsLabel.Text = Format.abbreviate(value)
	end)
end

function HUD.start()
	if State.current then
		render(State.current)
	end
	State.Changed:Connect(render)
	Storm.Changed:Connect(renderStorm)
	while true do
		renderStorm()
		task.wait(0.25)
	end
end

return HUD
