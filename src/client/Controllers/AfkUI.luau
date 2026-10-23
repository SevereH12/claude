--!strict
-- The AFK screen: while you're in the AFK Lounge (snapshot.afk, from
-- Systems/Afk), a calm card across the middle of the screen:
--   "💤 AFK: +12,345 Volts/hour", "10% of your best grinding (Ember Mesa)"
--   (Premium members: 15%, with the Premium icon), what you've earned and
--   for how long, and "How is this worked out?", which opens the breakdown
--   (Util/Afk.rate): best zone, bottle, strikes to fill, fill time, what a
--   bottle sells for, every multiplier, and each running boost's time left
--   (they count down while AFK). Players without Premium see a small
--   "Premium members earn 15% here" line; tapping it opens Roblox's Premium
--   signup (never by itself). Before AFK starts it counts down.
-- Also pulses the lounge's charge tank (parts tagged AfkPulse).

local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local BoostRules = require(ReplicatedStorage.Shared.Util.Boosts)
local Progression = require(ReplicatedStorage.Shared.Util.Progression)
local Layout = require(script.Parent.Parent.Lib.Layout)
local LayoutMath = require(script.Parent.Parent.Lib.LayoutMath)
local UI = require(script.Parent.Parent.Lib.UI)
local State = require(script.Parent.State)

local COLORS = UI.COLORS
local CALM = Color3.fromRGB(150, 140, 255)
local WIDTH = 520
local HEAD = 104 -- the card without the breakdown
local LINE = 22 -- one breakdown line
local PULSE = TweenInfo.new(2.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

local player = Players.LocalPlayer

local AfkUI = {}

local card: Frame
local headline: TextLabel
local share: TextLabel
local upsell: TextButton
local earned: TextLabel
local toggle: TextButton
local details: Frame
local expanded = false
local lines = 0

-- 1234567 -> "1,234,567"
local function commas(n: number): string
	local text = tostring(math.floor(n + 0.5))
	local out = text
	repeat
		local count
		out, count = string.gsub(out, "^(-?%d+)(%d%d%d)", "%1,%2")
	until count == 0
	return out
end

local function clock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	if s >= 3600 then
		return string.format("%d:%02d:%02d", s // 3600, (s // 60) % 60, s % 60)
	end
	return string.format("%d:%02d", s // 60, s % 60)
end

local function minutes(seconds: number): string
	local s = math.floor(seconds + 0.5)
	return if s >= 60 then `{s // 60}m {s % 60}s` else `{s}s`
end

local function percent(fraction: number): string
	return `{math.floor(fraction * 100 + 0.5)}%`
end

-- Where the card goes: centred under the top pieces, never over MENU.
local function place()
	local hud = Layout.hud
	local area = Layout.area
	local width = math.min(WIDTH, area.X - 2 * LayoutMath.MARGIN)
	local x = (area.X - width) / 2
	local y = hud.banner.y
	local menu = hud.menu
	if x < menu.x + menu.w and x + width > menu.x then
		y = math.max(y, menu.y + menu.h + LayoutMath.GAP)
	end
	local height = HEAD + (if expanded then lines * LINE + 10 else 0)
	UI.place(card, { x = x, y = y, w = width, h = height })
end

local function line(order: number, text: string, color: Color3?)
	local label = UI.label({
		Text = text,
		LayoutOrder = order,
		TextColor3 = color or COLORS.subtext,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, LINE - 2),
		Parent = details,
	})
	UI.maxText(label, 17)
end

local function fillDetails(afk: Types.AfkState, snapshot: Types.Snapshot)
	for _, child in details:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local n = 0
	local function add(text: string, color: Color3?)
		n += 1
		line(n, text, color)
	end
	add(`Best zone: {afk.zone}`)
	local big = if afk.bigBottles then ` (Big Bottles: {commas(afk.baseCapacity)} +50%)` else ""
	add(`Bottle: {afk.bottle}, holds {commas(afk.capacity)}{big}`)
	add(`Strikes to fill: {afk.strikes} ({afk.chargeSize} per strike)`)
	add(`Time to fill: {minutes(afk.fillSeconds)} (storms only, strikes you can reach)`)
	add(`One full bottle sells for {commas(afk.bag)} Volts`)
	local parts: { string } = {}
	for _, m in afk.multipliers do
		table.insert(parts, `{m.label} x{m.value}`)
	end
	if afk.luck > 0 then
		table.insert(parts, `Lucky +{percent(afk.luck)}`)
	end
	add(if #parts > 0 then `Multipliers: {table.concat(parts, ", ")}` else "Multipliers: none")
	local now = workspace:GetServerTimeNow()
	for key, ends in snapshot.boosts do
		local def = BoostRules.def(key)
		if def and ends > now then
			add(`{def.name} boost: {clock(ends - now)} left (counts down while AFK)`, COLORS.volt)
		end
	end
	add(
		`You get {percent(afk.fraction)} of grinding: {commas(afk.perHour / afk.fraction)} Volts/hour`
	)
	lines = n
end

local function render(snapshot: Types.Snapshot)
	local afk = snapshot.afk
	card.Visible = afk ~= nil
	if not afk then
		return
	end
	local now = workspace:GetServerTimeNow()
	if afk.active then
		headline.Text = `💤 AFK: +{commas(afk.perHour)} Volts/hour`
		local zone = if afk.zone ~= "" then ` ({afk.zone})` else ""
		share.Text = if afk.premium
			then `{Progression.PREMIUM_ICON} {percent(afk.fraction)} of your best grinding{zone}, Premium bonus`
			else `{percent(afk.fraction)} of your best grinding{zone}`
		earned.Text = `Earned {commas(afk.earned)} Volts in {clock(now - afk.startsAt)}`
	else
		headline.Text = "💤 AFK LOUNGE"
		share.Text = "Rest here to earn Volts while you're away"
		earned.Text = `AFK starts in {math.max(0, math.ceil(afk.startsAt - now))}s`
	end
	upsell.Visible = not afk.premium
	toggle.Visible = afk.active
	details.Visible = expanded and afk.active
	if expanded and afk.active then
		fillDetails(afk, snapshot)
	end
	place()
end

local function pulse(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	TweenService:Create(part, PULSE, { Transparency = 0.55 }):Play()
	local light = part:FindFirstChildWhichIsA("PointLight")
	if light then
		TweenService:Create(light, PULSE, { Brightness = 0.3 }):Play()
	end
end

function AfkUI.init()
	local _, root = Layout.screen("StormBottlerAfk", 3)
	card = UI.panel({
		Name = "AfkCard",
		Visible = false,
		Parent = root,
	})
	UI.stroke(card, 3, CALM)
	headline = UI.label({
		Title = true,
		Text = "",
		TextColor3 = CALM,
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.new(1, -28, 0, 30),
		Parent = card,
	})
	UI.maxText(headline, 30)
	share = UI.label({
		Text = "",
		TextColor3 = COLORS.text,
		Position = UDim2.fromOffset(14, 40),
		Size = UDim2.new(1, -28, 0, 20),
		Parent = card,
	})
	UI.maxText(share, 18)
	earned = UI.label({
		Text = "",
		TextColor3 = COLORS.volt,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(14, 64),
		Size = UDim2.new(0.5, -14, 0, 18),
		Parent = card,
	})
	UI.maxText(earned, 16)
	upsell = UI.make(Instance.new("TextButton"), {
		Name = "PremiumUpsell",
		BackgroundTransparency = 1,
		Font = UI.FONT_BODY,
		Text = `Premium members earn {percent(Config.AFK.premiumRateFraction)} here`,
		TextColor3 = COLORS.subtext,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(0.5, 0, 0, 64),
		Size = UDim2.new(0.5, -14, 0, 18),
		Parent = card,
	})
	UI.maxText(upsell, 14)
	upsell.Activated:Connect(function()
		pcall(MarketplaceService.PromptPremiumPurchase, MarketplaceService, player)
	end)
	toggle = UI.make(Instance.new("TextButton"), {
		Name = "HowToggle",
		BackgroundTransparency = 1,
		Font = UI.FONT_BODY,
		Text = "How is this worked out? ▾",
		TextColor3 = CALM,
		TextScaled = true,
		Position = UDim2.fromOffset(14, 84),
		Size = UDim2.new(1, -28, 0, 18),
		Parent = card,
	})
	UI.maxText(toggle, 15)
	toggle.Activated:Connect(function()
		expanded = not expanded
		toggle.Text = if expanded
			then "How is this worked out? ▴"
			else "How is this worked out? ▾"
		if State.current then
			render(State.current)
		end
	end)
	details = UI.make(Instance.new("Frame"), {
		Name = "Breakdown",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, HEAD),
		Size = UDim2.new(1, -28, 1, -HEAD - 6),
		Visible = false,
		Parent = card,
	})
	UI.make(Instance.new("UIListLayout"), {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = details,
	})
	UI.onLayout(place)
end

function AfkUI.start()
	State.Changed:Connect(render)
	for _, part in CollectionService:GetTagged("AfkPulse") do
		pulse(part)
	end
	CollectionService:GetInstanceAddedSignal("AfkPulse"):Connect(pulse)
	-- the clocks tick between snapshots
	while true do
		task.wait(1)
		local snapshot = State.current
		if snapshot and snapshot.afk then
			render(snapshot)
		end
	end
end

return AfkUI
