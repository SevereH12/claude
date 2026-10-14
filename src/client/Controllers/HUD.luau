--!strict
-- Always-on screen UI. Shows state, never changes it.
--
--   StormBottlerHUD (ScreenGui)
--   ├── VoltsPanel   top centre: Volts (counts up)
--   ├── StormPill    under Volts: "STORM 1:12" / "CALM 0:15"
--   ├── CityMeter    top right: server city meter (placeholder until that update)
--   ├── ShopButton   left: opens the bottle shop
--   └── BottleBar    bottom centre, above the hotbar: fill + "Jar 3/5"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Format = require(ReplicatedStorage.Shared.Util.Format)
local Formulas = require(ReplicatedStorage.Shared.Util.Formulas)
local Types = require(ReplicatedStorage.Shared.Types)
local UI = require(script.Parent.Parent.Lib.UI)
local ShopUI = require(script.Parent.ShopUI)
local State = require(script.Parent.State)
local Storm = require(script.Parent.Storm)

local COLORS = UI.COLORS

local HUD = {}

local screenGui: ScreenGui
local voltsLabel: TextLabel
local stormPill: Frame
local stormLabel: TextLabel
local bottleFill: Frame
local bottleLabel: TextLabel
local displayedVolts: NumberValue
local lastChargeCount = -1

local function buildVoltsPanel()
	local panel = UI.make(Instance.new("Frame"), {
		Name = "VoltsPanel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromScale(0.26, 0.09),
		BackgroundColor3 = COLORS.panel,
		Parent = screenGui,
	})
	UI.corner(panel, UDim.new(0.3, 0))
	UI.stroke(panel, 4)
	UI.sizeLimits(panel, Vector2.new(190, 48), Vector2.new(380, 80))
	voltsLabel = UI.label({
		Name = "Volts",
		Text = "0 Volts",
		TextColor3 = COLORS.volt,
		Position = UDim2.fromScale(0.05, 0.1),
		Size = UDim2.fromScale(0.9, 0.8),
		Parent = panel,
	})
	UI.maxText(voltsLabel, 44)
end

local function buildStormPill()
	stormPill = UI.make(Instance.new("Frame"), {
		Name = "StormPill",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 92),
		Size = UDim2.fromScale(0.16, 0.05),
		BackgroundColor3 = COLORS.calm,
		Parent = screenGui,
	})
	UI.corner(stormPill, UDim.new(0.5, 0))
	UI.stroke(stormPill, 3)
	UI.sizeLimits(stormPill, Vector2.new(140, 30), Vector2.new(240, 44))
	stormLabel = UI.label({
		Name = "Timer",
		Text = "...",
		Position = UDim2.fromScale(0.05, 0.12),
		Size = UDim2.fromScale(0.9, 0.76),
		Parent = stormPill,
	})
	UI.maxText(stormLabel, 28)
end

local function buildCityMeter()
	local meter = UI.make(Instance.new("Frame"), {
		Name = "CityMeter",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 8),
		Size = UDim2.fromScale(0.18, 0.08),
		BackgroundColor3 = COLORS.panel,
		BackgroundTransparency = 0.3,
		Parent = screenGui,
	})
	UI.corner(meter, UDim.new(0.25, 0))
	UI.stroke(meter, 3)
	UI.sizeLimits(meter, Vector2.new(150, 44), Vector2.new(260, 70))
	local title = UI.label({
		Text = "SERVER CITY",
		TextColor3 = COLORS.subtext,
		Position = UDim2.fromScale(0.05, 0.06),
		Size = UDim2.fromScale(0.9, 0.42),
		Parent = meter,
	})
	UI.maxText(title, 20)
	local track = UI.make(Instance.new("Frame"), {
		Position = UDim2.fromScale(0.06, 0.58),
		Size = UDim2.fromScale(0.88, 0.26),
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
	UI.maxText(comingSoon, 14)
end

local function buildShopButton()
	local button = UI.button({
		Name = "ShopButton",
		Text = "Shop",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.015, 0.5),
		Size = UDim2.fromScale(0.11, 0.08),
		BackgroundColor3 = COLORS.green,
		Parent = screenGui,
	})
	UI.sizeLimits(button, Vector2.new(90, 44), Vector2.new(160, 64))
	UI.maxText(button, 30)
	button.Activated:Connect(function()
		UI.pop(button)
		ShopUI.toggle()
	end)
end

local function buildBottleBar()
	local bar = UI.make(Instance.new("Frame"), {
		Name = "BottleBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -90), -- sits above the backpack hotbar
		Size = UDim2.fromScale(0.34, 0.055),
		BackgroundColor3 = COLORS.panelDark,
		Parent = screenGui,
	})
	UI.corner(bar, UDim.new(0.5, 0))
	UI.stroke(bar, 3)
	UI.sizeLimits(bar, Vector2.new(240, 30), Vector2.new(460, 44))

	local clip = UI.make(Instance.new("CanvasGroup"), {
		Name = "Clip",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = bar,
	})
	UI.corner(clip, UDim.new(0.5, 0))
	bottleFill = UI.make(Instance.new("Frame"), {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = COLORS.storm,
		BorderSizePixel = 0,
		Parent = clip,
	})
	bottleLabel = UI.label({
		Name = "Text",
		Text = "",
		Position = UDim2.fromScale(0.04, 0.12),
		Size = UDim2.fromScale(0.92, 0.76),
		ZIndex = 2,
		Parent = bar,
	})
	UI.maxText(bottleLabel, 24)
end

local function renderStorm()
	local state = Storm.current
	if not state then
		return
	end
	local seconds = math.ceil(Storm.secondsLeft())
	local clock = string.format("%d:%02d", seconds // 60, seconds % 60)
	if state.phase == "Storm" then
		stormLabel.Text = `STORM  {clock}`
		stormPill.BackgroundColor3 = COLORS.storm
	else
		stormLabel.Text = `Storm in {clock}`
		stormPill.BackgroundColor3 = COLORS.calm
	end
end

local function render(snapshot: Types.Snapshot)
	TweenService:Create(displayedVolts, UI.TWEEN.countUp, { Value = snapshot.volts }):Play()

	local bottle = Formulas.bottle(snapshot.bottleTier)
	local fraction = math.clamp(snapshot.chargeCount / bottle.capacity, 0, 1)
	TweenService:Create(bottleFill, UI.TWEEN.fast, { Size = UDim2.fromScale(fraction, 1) }):Play()

	if fraction >= 1 then
		bottleFill.BackgroundColor3 = COLORS.red
		bottleLabel.Text = "FULL! Sell at the Power Plant"
	else
		bottleFill.BackgroundColor3 = COLORS.storm
		bottleLabel.Text =
			`{bottle.name}  {snapshot.chargeCount}/{bottle.capacity}  •  {Format.abbreviate(
				snapshot.chargeValue
			)} Volts`
	end

	if snapshot.chargeCount > lastChargeCount and lastChargeCount >= 0 then
		UI.pop(bottleFill.Parent :: GuiObject, 1.06)
	end
	lastChargeCount = snapshot.chargeCount
end

function HUD.init()
	screenGui = UI.make(Instance.new("ScreenGui"), {
		Name = "StormBottlerHUD",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	displayedVolts =
		UI.make(Instance.new("NumberValue"), { Name = "DisplayedVolts", Parent = screenGui })
	displayedVolts.Changed:Connect(function(value: number)
		voltsLabel.Text = `{Format.abbreviate(value)} Volts`
	end)

	buildVoltsPanel()
	buildStormPill()
	buildCityMeter()
	buildShopButton()
	buildBottleBar()
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
