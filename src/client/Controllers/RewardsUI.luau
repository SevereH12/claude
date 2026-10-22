--!strict
-- REWARDS panel (from the menu), in the store's card style:
--   * the 7-day login streak: claimed days ticked, today's glowing with
--     CLAIM, later days dimmed, and "Next reward in 5h 12m" (to the next UTC
--     day) once today's is claimed
--   * the 6 playtime gifts of this visit, each counting down ("in 3:41") or
--     showing CLAIM
-- Each card shows what this player would really get: Volts grow with their
-- best zone, and a boost for a pass they own says so and pays Volts instead
-- (Util/Rewards.resolve). CLAIM only asks (ClaimDaily, ClaimGift); the
-- server decides (Systems/Rewards) and Rewarded brings a celebration.
-- RewardsUI.ReadyChanged tells the menu when something is ready to claim.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Net = require(ReplicatedStorage.Shared.Net)
local BoostRules = require(ReplicatedStorage.Shared.Util.Boosts)
local PassRules = require(ReplicatedStorage.Shared.Util.Passes)
local RewardRules = require(ReplicatedStorage.Shared.Util.Rewards)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Store = require(ReplicatedStorage.Shared.Util.Store)
local Types = require(ReplicatedStorage.Shared.Types)
local Celebrate = require(script.Parent.Parent.Lib.Celebrate)
local Layout = require(script.Parent.Parent.Lib.Layout)
local UI = require(script.Parent.Parent.Lib.UI)
local State = require(script.Parent.State)

local COLORS = UI.COLORS
local PINK = Color3.fromRGB(255, 120, 170)
local DAY_HEIGHT = 168
local GIFT_HEIGHT = 128
local HEADING = 28
local GAP = 8

type Card = {
	frame: Frame,
	image: ImageLabel,
	text: TextLabel,
	button: TextButton,
	stroke: UIStroke,
}

local RewardsUI = {}

-- Fires true when something becomes ready to claim, false when nothing is.
RewardsUI.ReadyChanged = Signal.new() :: Signal.Signal<boolean>

local panel: Frame
local dayCards: { Card } = {}
local giftCards: { Card } = {}
local nextLabel: TextLabel
local ready = false

function RewardsUI.open()
	UI.openPanel(panel)
end

function RewardsUI.isReady(): boolean
	return ready
end

-- "5h 12m" or "12m".
local function hoursMinutes(seconds: number): string
	local minutes = math.ceil(seconds / 60)
	if minutes >= 60 then
		return `{minutes // 60}h {minutes % 60}m`
	end
	return `{minutes}m`
end

-- What a reward gives this player, as card text, and its icon: a boost's
-- pass art, or a Volts pack's (bigger reward, bigger pack).
local function describe(reward: Types.Reward, snapshot: Types.Snapshot): (string, number)
	local resolved = RewardRules.resolve(reward, snapshot.passes)
	local lines: { string } = {}
	if resolved.charges > 0 then
		table.insert(lines, `+{Format.abbreviate(Store.volts(resolved.charges, snapshot))} ⚡`)
	end
	for _, boost in resolved.boosts do
		local def = BoostRules.def(boost.key)
		if def then
			table.insert(lines, `{def.name} {boost.minutes}m`)
		end
	end
	for _, key in resolved.swapped do
		local def = BoostRules.def(key)
		local pass = if def then PassRules.def(def.pass) else nil
		if pass then
			table.insert(lines, `(you own {pass.name})`)
		end
	end
	local image = 0
	local first = resolved.boosts[1]
	if resolved.charges == 0 and first then
		local def = BoostRules.def(first.key)
		local pass = if def then PassRules.def(def.pass) else nil
		image = if pass then pass.image else 0
	else
		local size = if resolved.charges >= 1000 then 3 elseif resolved.charges >= 250 then 2 else 1
		image = Config.VOLT_PACKS[size].image
	end
	return table.concat(lines, "\n"), image
end

-- A day or gift card: a title, an icon, what it gives, and a button.
local function buildCard(parent: Instance, order: number, title: string, onClaim: () -> ()): Card
	local frame = UI.make(Instance.new("Frame"), {
		Name = title,
		LayoutOrder = order,
		BackgroundColor3 = COLORS.panelDark,
		Parent = parent,
	})
	UI.corner(frame, UDim.new(0, 12))
	local stroke = UI.stroke(frame, 3)
	local heading = UI.label({
		Title = true,
		Text = title,
		Position = UDim2.new(0, 4, 0, 4),
		Size = UDim2.new(1, -8, 0, 20),
		Parent = frame,
	})
	UI.maxText(heading, 18)
	local image = UI.make(Instance.new("ImageLabel"), {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 26),
		Size = UDim2.fromOffset(40, 40),
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		Parent = frame,
	})
	local text = UI.label({
		Text = "",
		TextColor3 = COLORS.subtext,
		TextWrapped = true,
		Position = UDim2.new(0, 4, 0, 70),
		Size = UDim2.new(1, -8, 1, -114),
		Parent = frame,
	})
	UI.maxText(text, 16)
	local button = UI.button({
		Name = "Claim",
		Text = "",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.new(1, -8, 0, 36),
		BackgroundColor3 = COLORS.green,
		Parent = frame,
	})
	UI.maxText(button, 18)
	button.Activated:Connect(function()
		UI.pop(button)
		onClaim()
	end)
	return {
		frame = frame,
		image = image,
		text = text,
		button = button,
		stroke = stroke,
	}
end

local function setCard(
	card: Card,
	image: number,
	text: string,
	buttonText: string?,
	canClaim: boolean,
	dim: boolean
)
	card.image.Image = if image ~= 0 then `rbxassetid://{image}` else ""
	card.image.ImageTransparency = if dim then 0.6 else 0
	card.text.Text = text
	card.text.TextTransparency = if dim then 0.5 else 0
	card.button.Visible = buttonText ~= nil
	card.button.Text = buttonText or ""
	UI.setEnabled(card.button, canClaim, COLORS.green)
	-- what's ready glows gold
	card.stroke.Color = if canClaim then COLORS.volt else COLORS.stroke
	card.stroke.Thickness = if canClaim then 5 else 3
end

-- Everything from the snapshot and the clock; returns whether anything is
-- ready to claim.
local function render(): boolean
	local snapshot = State.current
	if not snapshot then
		return false
	end
	local now = workspace:GetServerTimeNow()
	local anyReady = false

	-- the streak: the day to claim, or the day claimed today
	local daily = snapshot.daily
	local today = RewardRules.today(now) + daily.dayOffset
	local canClaim, nextDay = RewardRules.daily(daily.lastDay, today, daily.streak)
	local current = if canClaim then nextDay else daily.streak
	for day, card in dayCards do
		local text, image = describe(Config.DAILY_REWARDS[day], snapshot)
		if day == current and canClaim then
			setCard(card, image, text, "CLAIM", true, false)
		elseif day < current or day == current then
			setCard(card, image, text, "✓", false, false)
		else
			setCard(card, image, text, nil, false, true)
		end
	end
	anyReady = canClaim
	nextLabel.Text = if canClaim
		then `Day {nextDay} is ready to claim!`
		else `Next reward in {hoursMinutes(RewardRules.untilNextDay(now))}`

	-- this visit's playtime gifts
	local elapsed = now - snapshot.gifts.startedAt
	for index, card in giftCards do
		local gift = Config.PLAYTIME_GIFTS[index]
		local text, image = describe(gift.reward, snapshot)
		if snapshot.gifts.claimed[index] then
			setCard(card, image, text, "✓", false, true)
		elseif RewardRules.giftReady(gift, elapsed, false) then
			setCard(card, image, text, "CLAIM", true, false)
			anyReady = true
		else
			local left = math.ceil(gift.minutes * 60 - elapsed)
			setCard(
				card,
				image,
				text,
				string.format("in %d:%02d", left // 60, left % 60),
				false,
				false
			)
		end
	end
	return anyReady
end

local function heading(parent: Instance, order: number, text: string): TextLabel
	local label = UI.label({
		Title = true,
		Name = "Heading",
		LayoutOrder = order,
		Text = text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -12, 0, HEADING),
		Parent = parent,
	})
	UI.maxText(label, 24)
	return label
end

local function grid(
	parent: Instance,
	order: number,
	name: string,
	height: number,
	cellSize: UDim2
): Frame
	local frame = UI.make(Instance.new("Frame"), {
		Name = name,
		LayoutOrder = order,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -12, 0, height),
		Parent = parent,
	})
	UI.make(Instance.new("UIGridLayout"), {
		CellSize = cellSize,
		CellPadding = UDim2.fromOffset(GAP, GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = frame,
	})
	return frame
end

-- "Got +1.2K Volts and 2x Volts for 10 min!"
local function onRewarded(rewarded: Types.Rewarded)
	local parts: { string } = {}
	if rewarded.volts > 0 then
		table.insert(parts, `+{Format.abbreviate(rewarded.volts)} ⚡ Volts`)
	end
	for _, boost in rewarded.boosts do
		local def = BoostRules.def(boost.key)
		if def then
			table.insert(parts, `{def.name} for {boost.minutes} min`)
		end
	end
	Celebrate.sparks()
	UI.toast(`🎁 You got {table.concat(parts, " and ")}!`, "good", 5)
	if #rewarded.swapped > 0 then
		UI.toast("You already own that boost's pass, so it paid Volts instead", "info", 5)
	end
end

function RewardsUI.init()
	local _, root = Layout.screen("StormBottlerRewards", 5)
	local window = UI.window(root, "RewardsPanel", "🎁 REWARDS", PINK, Vector2.new(680, 560))
	panel = window.panel
	-- one scrolling column: it all fits on a monitor, and scrolls on a phone
	local list = UI.make(Instance.new("ScrollingFrame"), {
		Name = "List",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = window.body,
	})
	UI.make(Instance.new("UIListLayout"), {
		Padding = UDim.new(0, GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = list,
	})

	heading(list, 1, "📅 DAILY STREAK")
	local days = grid(list, 2, "Days", DAY_HEIGHT, UDim2.new(1 / 7, -GAP, 1, 0))
	local claimDaily = Net.get("ClaimDaily")
	for day = 1, #Config.DAILY_REWARDS do
		table.insert(
			dayCards,
			buildCard(days, day, `DAY {day}`, function()
				claimDaily:FireServer()
			end)
		)
	end
	nextLabel = UI.label({
		Name = "Next",
		LayoutOrder = 3,
		Text = "",
		TextColor3 = COLORS.volt,
		Size = UDim2.new(1, -12, 0, 22),
		Parent = list,
	})
	UI.maxText(nextLabel, 18)

	heading(list, 4, "⏱ PLAYTIME GIFTS (this visit)")
	local rows = math.ceil(#Config.PLAYTIME_GIFTS / 3)
	local gifts = grid(
		list,
		5,
		"Gifts",
		rows * GIFT_HEIGHT + (rows - 1) * GAP,
		UDim2.new(1 / 3, -GAP, 0, GIFT_HEIGHT)
	)
	local claimGift = Net.get("ClaimGift")
	for index, gift in Config.PLAYTIME_GIFTS do
		table.insert(
			giftCards,
			buildCard(gifts, index, `{gift.minutes} MIN`, function()
				claimGift:FireServer(index)
			end)
		)
	end
end

function RewardsUI.start()
	Net.get("Rewarded").OnClientEvent:Connect(onRewarded)
	State.Changed:Connect(function()
		render()
	end)
	-- countdowns, and the menu's dot
	while true do
		local nowReady = render()
		if nowReady ~= ready then
			ready = nowReady
			RewardsUI.ReadyChanged:Fire(ready)
		end
		task.wait(1)
	end
end

return RewardsUI
