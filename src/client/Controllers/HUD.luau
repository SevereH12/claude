--!strict
-- Always-on screen UI. Shows state, never changes it.
--
--   StormBottlerHUD (ScreenGui), every piece on a screen edge (LayoutMath.hud)
--   ├── VoltsPanel   top left: ⚡ Volts (counts up)
--   ├── StormPill    under Volts: "⚡ STORM 1:12" / "☀ STORM IN 0:15"
--   ├── BoostRow     one chip per running timed boost ("⚡ 14:32"): a row
--   │                under the storm timer, a column beside Volts on a
--   │                sideways phone or tablet (LayoutMath.hud.boosts)
--   ├── GoalCard     top right: the closest next goal and Volts towards it
--   ├── StormChip    under it, while a Server Storm is on (Systems/Boosts,
--   │                read from workspace attributes): its latest buyer and
--   │                time left ("🌩️ SERVER 2x · Alex · 14:32")
--   ├── EventChip    under that, while a scheduled event is on (Config.EVENTS,
--   │                Util/Weather): "🎉 Double Volts Weekend 2x · 1d 4h"
--   ├── BottleBar    bottom centre (top centre on touch): fill + "JAR 3 / 5",
--   │                with the Chemist's TANK count beside it
--   └── RemoteSell   Remote Sell pass owners: a SELL button at the bar's
--                    right end (the bar shrinks to make room); it charges
--                    up for 1.5s, then sells (keyboard V, gamepad L1).
--                    Without the pass it shows locked while a full bottle is
--                    far from a station (HUD.setSellNudge: Controllers/Offers)
-- The MENU button (shop, research, teleport, boosts) is Controllers/Menu.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local BoostRules = require(ReplicatedStorage.Shared.Util.Boosts)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Net = require(ReplicatedStorage.Shared.Net)
local Formulas = require(ReplicatedStorage.Shared.Util.Formulas)
local Progression = require(ReplicatedStorage.Shared.Util.Progression)
local ResearchMath = require(ReplicatedStorage.Shared.Util.Research)
local Types = require(ReplicatedStorage.Shared.Types)
local Weather = require(ReplicatedStorage.Shared.Util.Weather)
local Layout = require(script.Parent.Parent.Lib.Layout)
local LayoutMath = require(script.Parent.Parent.Lib.LayoutMath)
local Sfx = require(script.Parent.Parent.Lib.Sfx)
local UI = require(script.Parent.Parent.Lib.UI)
local State = require(script.Parent.State)
local Storm = require(script.Parent.Storm)

local COLORS = UI.COLORS
local FULL_PULSE = TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local SELL_WIDTH = 104 -- design pixels the SELL button takes from the bar's slot

local HUD = {}

local screenGui: Frame -- the HUD's Layout root
local voltsPanel: Frame
local voltsLabel: TextLabel
local stormPill: Frame
local stormLabel: TextLabel
local bottleBar: Frame
local bottleFill: Frame
local fillGradient: UIGradient
local bottleLabel: TextLabel
local bottleValue: TextLabel
local tankLabel: TextLabel
local sellButton: TextButton
local sellRing: Frame
local sellProgress: UIGradient
local hasRemoteSell = false
local sellNudge: (() -> ())? = nil -- set while the locked SELL shows: what a tap does
local boostRow: Frame
local boostList: UIListLayout
local boostChips: { [string]: TextLabel } = {} -- by boost key
local stormChip: TextLabel
local eventChip: TextLabel
local sellCharging = false
local sellReadyAt = 0
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
		Parent = screenGui,
	})
	voltsPanel = panel

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
		BackgroundColor3 = COLORS.calm,
		Parent = screenGui,
	})
	UI.corner(stormPill, UDim.new(0.5, 0))
	UI.stroke(stormPill, 3)
	UI.gradient(stormPill, Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 185))
	UI.make(Instance.new("UIScale"), { Parent = stormPill })
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
		Visible = false,
		Parent = screenGui,
	})
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

local function buildBottleBar()
	bottleBar = UI.panel({
		Name = "BottleBar",
		Parent = screenGui,
	})
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
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.fromOffset(150, 22),
		Parent = bottleBar,
	})
	UI.maxText(tankLabel, 20)
end

-- A chip per boost (Config.BOOSTS order), shown while it runs.
local BOOST_COLORS: { [string]: Color3 } = {
	DoubleVolts = COLORS.voltDeep,
	Lucky = COLORS.green,
	BigBottles = COLORS.stormDeep,
}

local function buildBoostRow()
	boostRow = UI.make(Instance.new("Frame"), {
		Name = "BoostRow",
		BackgroundTransparency = 1,
		Parent = screenGui,
	})
	boostList = UI.make(Instance.new("UIListLayout"), {
		Padding = UDim.new(0, LayoutMath.GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = boostRow,
	})
	for index, boost in Config.BOOSTS do
		local chip = UI.label({
			Title = true,
			Name = boost.key,
			LayoutOrder = index,
			Text = "",
			Visible = false,
			TextColor3 = COLORS.text,
			BackgroundColor3 = BOOST_COLORS[boost.key] or COLORS.panelTop,
			BackgroundTransparency = 0,
			Parent = boostRow,
		})
		UI.corner(chip, UDim.new(0.5, 0))
		UI.stroke(chip, 2)
		UI.maxText(chip, 18)
		boostChips[boost.key] = chip
	end
end

-- The Server Storm's chip under the goal card.
local function buildStormChip()
	stormChip = UI.label({
		Title = true,
		Name = "StormChip",
		Text = "",
		Visible = false,
		TextColor3 = COLORS.text,
		BackgroundColor3 = Color3.fromRGB(130, 70, 230),
		BackgroundTransparency = 0,
		Parent = screenGui,
	})
	UI.corner(stormChip, UDim.new(0.5, 0))
	UI.stroke(stormChip, 2)
	UI.maxText(stormChip, 18)
end

-- A scheduled event's chip under the Server Storm's.
local function buildEventChip()
	eventChip = UI.label({
		Title = true,
		Name = "EventChip",
		Text = "",
		Visible = false,
		TextColor3 = COLORS.text,
		BackgroundColor3 = Color3.fromRGB(230, 150, 20),
		BackgroundTransparency = 0,
		Parent = screenGui,
	})
	UI.corner(eventChip, UDim.new(0.5, 0))
	UI.stroke(eventChip, 2)
	UI.maxText(eventChip, 18)
end

-- The SELL button's charge-up ring: an outline that fills left to right.
local function buildSellButton()
	sellButton = UI.button({
		Name = "RemoteSell",
		Text = "SELL",
		Visible = false,
		BackgroundColor3 = COLORS.green,
		Parent = screenGui,
	})
	UI.maxText(sellButton, 26)
	UI.padHint(sellButton, "RemoteSell")
	sellRing = UI.make(Instance.new("Frame"), {
		Name = "ChargeRing",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 10, 1, 10),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 4,
		Parent = sellButton,
	})
	UI.corner(sellRing, UDim.new(0.3, 0))
	local stroke = UI.make(Instance.new("UIStroke"), {
		Thickness = 4,
		Color = COLORS.volt,
		Parent = sellRing,
	})
	sellProgress = UI.make(Instance.new("UIGradient"), { Parent = stroke })
	sellButton.Activated:Connect(function()
		local nudge = sellNudge
		if hasRemoteSell then
			HUD.remoteSell()
		elseif nudge then
			UI.pop(sellButton)
			nudge()
		end
	end)
end

-- Without Remote Sell: show the SELL button locked (`onTap` opens the pass
-- in the store), or hide it again with nil.
function HUD.setSellNudge(onTap: (() -> ())?)
	if (sellNudge ~= nil) == (onTap ~= nil) then
		sellNudge = onTap
		return
	end
	sellNudge = onTap
	HUD.place()
end

local function setSellProgress(fraction: number)
	if fraction <= 0.001 then
		sellProgress.Transparency = NumberSequence.new(1)
	elseif fraction >= 0.999 then
		sellProgress.Transparency = NumberSequence.new(0)
	else
		sellProgress.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(fraction, 0),
			NumberSequenceKeypoint.new(fraction + 0.001, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
	end
end

-- Remote Sell (the SELL button, V or L1): charge up for a moment, then ask
-- the server to sell. The server checks the pass, the charges and its own
-- cooldown; this only keeps the button honest about when it can fire.
function HUD.remoteSell()
	local snapshot = State.current
	if not hasRemoteSell or sellCharging or os.clock() < sellReadyAt or not snapshot then
		return
	end
	if snapshot.chargeCount <= 0 then
		UI.toast("Your bottle is empty: catch some lightning first", "info")
		return
	end
	sellCharging = true
	UI.pop(sellButton)
	task.spawn(function()
		local values = Config.PASS_VALUES
		sellRing.Visible = true
		sellButton.Text = "..."
		local started = os.clock()
		while os.clock() - started < values.remoteSellChargeUp do
			setSellProgress((os.clock() - started) / values.remoteSellChargeUp)
			RunService.RenderStepped:Wait()
		end
		sellRing.Visible = false
		setSellProgress(0)
		Net.get("RemoteSell"):FireServer()
		sellCharging = false
		-- greyed out with a countdown until the server's cooldown is over
		sellReadyAt = os.clock() + values.remoteSellCooldown
		UI.setEnabled(sellButton, false, COLORS.green)
		while os.clock() < sellReadyAt do
			sellButton.Text = tostring(math.ceil(sellReadyAt - os.clock()))
			task.wait(0.2)
		end
		sellButton.Text = "SELL"
		UI.setEnabled(sellButton, true, COLORS.green)
	end)
end

-- Each running boost's time left ("⚡ 14:32"; over an hour, "⚡ 1:05:00").
local function renderBoosts()
	local snapshot = State.current
	local now = workspace:GetServerTimeNow()
	for index, boost in Config.BOOSTS do
		local chip = boostChips[boost.key]
		local ends = if snapshot then snapshot.boosts[boost.key] else nil
		local left = if ends then math.ceil(ends - now) else 0
		chip.Visible = left > 0
		if left > 0 then
			local clock = if left >= 3600
				then string.format("%d:%02d:%02d", left // 3600, left // 60 % 60, left % 60)
				else string.format("%d:%02d", left // 60, left % 60)
			chip.Text = `{boost.icon} {clock}`
			chip.LayoutOrder = index
		end
	end
end

-- A Server Storm's latest buyer and time left, while one is on.
local function renderServerStorm()
	local left = math.ceil(
		BoostRules.stormLeft(
			workspace:GetAttribute(BoostRules.STORM_ENDS),
			workspace:GetServerTimeNow()
		)
	)
	stormChip.Visible = left > 0
	if left > 0 then
		local by = workspace:GetAttribute(BoostRules.STORM_BY)
		local name = if typeof(by) == "string" then ` · {by}` else ""
		stormChip.Text =
			string.format("🌩️ SERVER 2x%s · %d:%02d", name, left // 60, left % 60)
	end
end

-- The scheduled event on now (the first, if several), and its time left.
local function renderEvent()
	local active = Weather.liveEvents()[1]
	eventChip.Visible = active ~= nil
	if active then
		local event = active.event
		eventChip.Text =
			`🎉 {event.name} {event.multiplier}x · {Weather.formatLeft(active.left)}`
	end
end

local function renderStorm()
	local state = Storm.current
	if not state then
		return
	end
	local seconds = math.ceil(Storm.secondsLeft())
	local clock = string.format("%d:%02d", seconds // 60, seconds % 60)
	local supercellIn = if state.supercellAt
		then math.max(0, math.ceil(state.supercellAt - workspace:GetServerTimeNow()))
		else nil
	if state.phase == "Storm" and state.supercell then
		stormLabel.Text = `⛈ SUPERCELL  {clock}`
		stormPill.BackgroundColor3 = Color3.fromRGB(120, 60, 200)
	elseif supercellIn then
		-- the 30 s countdown to a Supercell (Systems/StormCycle)
		stormLabel.Text = string.format("⛈ SUPERCELL IN 0:%02d", supercellIn)
		stormPill.BackgroundColor3 = Color3.fromRGB(120, 60, 200)
	elseif state.phase == "Storm" then
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
	if lastChargeCount < 0 then
		displayedVolts.Value = snapshot.volts -- loading in: no count-up
	else
		TweenService:Create(displayedVolts, UI.TWEEN.countUp, { Value = snapshot.volts }):Play()
	end
	renderGoal(snapshot)

	local bottle = Formulas.bottle(snapshot.bottleTier)
	local capacity = snapshot.capacity -- Big Bottles included
	local fraction = math.clamp(snapshot.chargeCount / capacity, 0, 1)
	TweenService:Create(bottleFill, UI.TWEEN.fast, { Size = UDim2.fromScale(fraction, 1) }):Play()

	-- full: the bar glows and a toast says so once (the text stays a count)
	local full = fraction >= 1
	setFull(full)
	if full and not wasFull and lastChargeCount >= 0 then
		Sfx.play("bottle_full")
		UI.toastEvery("bottleFull", UI.FULL_REMINDER, UI.FULL_MESSAGE, "warn", true)
	end
	wasFull = full
	bottleLabel.Text = `{string.upper(bottle.name)}  {snapshot.chargeCount} / {capacity}`
	bottleValue.Text = `{Format.abbreviate(snapshot.chargeValue)} ⚡`

	local chemist = snapshot.researchers.Chemist
	tankLabel.Visible = chemist ~= nil
	if chemist then
		local tankCapacity = ResearchMath.tankCapacity(chemist.level, chemist.rank)
		tankLabel.Text = `TANK {snapshot.tankCount}/{tankCapacity}`
	end

	if snapshot.chargeCount > lastChargeCount and lastChargeCount >= 0 then
		UI.pop(bottleBar, 1.08)
	end
	lastChargeCount = snapshot.chargeCount

	if (snapshot.passes.RemoteSell == true) ~= hasRemoteSell then
		hasRemoteSell = snapshot.passes.RemoteSell == true
		HUD.place()
	end
end

-- Every piece on its edge (LayoutMath.hud): Volts and the storm timer top
-- left, the goal top right, the bottle bar bottom centre (top centre on
-- touch). The TANK count sits just past the bar's right end, on the side
-- away from the screen edge. With Remote Sell, the SELL button takes the
-- right end of the bar's place.
function HUD.place()
	local hud = Layout.hud
	UI.place(voltsPanel, hud.volts)
	UI.place(stormPill, hud.storm)
	UI.place(goalCard, hud.goal)
	UI.place(stormChip, hud.serverStorm)
	UI.place(eventChip, hud.event)
	-- the boosts' chips: three across a row, or stacked in a column
	local boosts = hud.boosts
	UI.place(boostRow, boosts)
	local across = boosts.w > boosts.h
	boostList.FillDirection = if across
		then Enum.FillDirection.Horizontal
		else Enum.FillDirection.Vertical
	local chipSize = if across
		then UDim2.new(1 / 3, -LayoutMath.GAP, 1, 0)
		else UDim2.new(1, 0, 0, LayoutMath.HUD.boostHeight)
	for _, chip in boostChips do
		chip.Size = chipSize
	end
	local bar = hud.bar
	local showSell = hasRemoteSell or sellNudge ~= nil
	sellButton.Visible = showSell
	if not hasRemoteSell then
		sellButton.Text = "🔒 SELL"
		UI.setEnabled(sellButton, true, COLORS.disabled)
	elseif not sellCharging and os.clock() >= sellReadyAt then
		sellButton.Text = "SELL"
		UI.setEnabled(sellButton, true, COLORS.green)
	end
	if showSell then
		local barWidth = bar.w - SELL_WIDTH - LayoutMath.GAP
		UI.place(bottleBar, { x = bar.x, y = bar.y, w = barWidth, h = bar.h })
		UI.place(
			sellButton,
			{ x = bar.x + bar.w - SELL_WIDTH, y = bar.y, w = SELL_WIDTH, h = bar.h }
		)
	else
		UI.place(bottleBar, bar)
	end
	local atBottom = not Layout.isTouch()
	tankLabel.AnchorPoint = Vector2.new(1, if atBottom then 1 else 0)
	tankLabel.Position = if atBottom then UDim2.new(1, -10, 0, -4) else UDim2.new(1, -10, 1, 4)
end

function HUD.init()
	-- there are no tools in this game; hide the empty hotbar
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)

	local _, root = Layout.screen("StormBottlerHUD", 1)
	screenGui = root
	displayedVolts =
		UI.make(Instance.new("NumberValue"), { Name = "DisplayedVolts", Parent = screenGui })

	buildVoltsPanel()
	buildStormPill()
	buildGoalCard()
	buildBottleBar()
	buildBoostRow()
	buildStormChip()
	buildEventChip()
	buildSellButton()
	HUD.place()
	Layout.Changed:Connect(HUD.place)

	-- the counter ticks as it counts up (Sfx keeps it to one tick per 80 ms)
	local lastVolts = displayedVolts.Value
	displayedVolts.Changed:Connect(function(value: number)
		voltsLabel.Text = Format.abbreviate(value)
		if value > lastVolts and lastChargeCount >= 0 then
			Sfx.play("volts_tick")
		end
		lastVolts = value
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
		renderBoosts()
		renderServerStorm()
		renderEvent()
		task.wait(0.25)
	end
end

return HUD
