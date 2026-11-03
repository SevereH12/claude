--!strict
-- Ascension's screens (the rules are Util/Ascension, the server side
-- Systems/Ascension). The ASCEND button in the Shop calls AscensionUI.ask();
-- the server checks the rules and sends back an offer with a token, which
-- opens the confirm screen: exactly what resets and what stays, and a
-- countdown (the token runs out). Pressing ASCEND there sends the token
-- back; the server does the reset and answers "done", and this plays the
-- celebration (sparks, the level-up sound and a big banner).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local AscensionRules = require(ReplicatedStorage.Shared.Util.Ascension)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Net = require(ReplicatedStorage.Shared.Net)
local Celebrate = require(script.Parent.Parent.Lib.Celebrate)
local Layout = require(script.Parent.Parent.Lib.Layout)
local Sfx = require(script.Parent.Parent.Lib.Sfx)
local UI = require(script.Parent.Parent.Lib.UI)

local COLORS = UI.COLORS
local PURPLE = Color3.fromRGB(170, 110, 255)
local BANNER_SECONDS = 3.5
local NARROW = 560 -- a panel narrower than this stacks RESETS over STAYS
local HEADING_TEXT = 21 -- the offer's text size, design pixels (at least the smallest legible)
local LINE_TEXT = 18 -- a line in RESETS or STAYS

type Offer = {
	token: string,
	level: number,
	cost: number,
	seconds: number,
	bonus: string,
	moving: { string }?, -- researchers who go back to the Office
}

local AscensionUI = {}

local remote: RemoteEvent
local panel: Frame
local scroller: ScrollingFrame
local heading: TextLabel
local columns: Frame
local columnLayout: UIListLayout
local columnFrames: { Frame } = {}
local lineLabels: { TextLabel } = {}
local countdown: TextLabel
local cancelButton: TextButton
local confirmButton: TextButton
local banner: TextLabel
local current: Offer? = nil
local offerId = 0

-- Asks the server whether the player can ascend (the Shop's ASCEND button).
function AscensionUI.ask()
	remote:FireServer()
end

-- One column of lines (what resets, what stays) in the columns row. It grows
-- to hold its lines, each of which wraps: nothing is cut off, and the
-- panel scrolls if it is long.
local function column(parent: Frame, order: number, title: string, color: Color3, lines: { string })
	local frame = UI.make(Instance.new("Frame"), {
		Name = title,
		LayoutOrder = order,
		Size = UDim2.new(0.5, -6, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = COLORS.panelDark,
		Parent = parent,
	})
	UI.corner(frame, UDim.new(0, 12))
	UI.stroke(frame, 3, color)
	UI.padding(frame, 10)
	UI.make(Instance.new("UIListLayout"), {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = frame,
	})
	local label = UI.label({
		Title = true,
		Text = title,
		TextColor3 = color,
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, 30),
		Parent = frame,
	})
	UI.maxText(label, 24, 14)
	for index, line in lines do
		local item = UI.label({
			Text = `- {line}`,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextScaled = false,
			TextSize = LINE_TEXT,
			TextWrapped = true,
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = frame,
		})
		table.insert(lineLabels, item)
	end
	table.insert(columnFrames, frame)
end

-- Lays the confirm screen out for a body `size`: the offer and the two
-- columns scroll above the countdown and the two buttons, which stay put.
local function fit(size: Vector2)
	local narrow = size.X < NARROW
	local button = UI.tall(54)
	local legible = math.max(UI.textSize(), 1)
	local countdownHeight = (if narrow then 2 else 1) * (math.max(legible, 16) + 4)
	local bottom = button + countdownHeight + 14
	scroller.Size = UDim2.new(1, 0, 1, -bottom)
	heading.TextSize = math.max(HEADING_TEXT, legible)
	for _, item in lineLabels do
		item.TextSize = math.max(LINE_TEXT, legible)
	end
	-- side by side, or one over the other on a narrow panel
	columnLayout.FillDirection = if narrow
		then Enum.FillDirection.Vertical
		else Enum.FillDirection.Horizontal
	for _, frame in columnFrames do
		frame.Size = if narrow then UDim2.new(1, 0, 0, 0) else UDim2.new(0.5, -6, 0, 0)
	end
	countdown.AnchorPoint = Vector2.new(0, 1)
	countdown.Position = UDim2.new(0, 0, 1, -(button + 8))
	countdown.Size = UDim2.new(1, 0, 0, countdownHeight)
	cancelButton.Size = UDim2.new(0.5, -6, 0, button)
	confirmButton.Size = UDim2.new(0.5, -6, 0, button)
end

local function showOffer(offer: Offer)
	current = offer
	offerId += 1
	local mine = offerId
	local moving = if typeof(offer.moving) == "table" then offer.moving else {}
	heading.Text = `Ascend to level {offer.level} {AscensionRules.stars(offer.level)}? `
		.. `Every sale pays {offer.bonus} Volts for good. You need {Format.abbreviate(offer.cost)} Volts.`
		.. (if #moving > 0 then `\nBack to the Office: {table.concat(moving, ", ")}` else "")
	UI.setEnabled(confirmButton, true, PURPLE)
	UI.openPanel(panel)
	-- the countdown: the server's token runs out at the same time
	task.spawn(function()
		local endsAt = os.clock() + offer.seconds
		while offerId == mine and panel.Visible do
			local left = math.max(0, math.ceil(endsAt - os.clock()))
			countdown.Text = `This offer runs out in {left} s`
			if left <= 0 then
				current = nil
				UI.setEnabled(confirmButton, false, PURPLE)
				countdown.Text = "Too slow: close this and press ASCEND again"
				return
			end
			task.wait(0.25)
		end
	end)
end

local bannerToken = 0

local function celebrate(level: number)
	UI.closePanels()
	Sfx.play("level_up")
	banner.Text = `🌟 ASCENDED! Level {level} {AscensionRules.stars(level)}\n`
		.. `{AscensionRules.bonusText(level)} Volts on every sale`
	local outline = banner:FindFirstChildOfClass("UIStroke")
	banner.TextTransparency = 0
	if outline then
		outline.Transparency = 0
	end
	banner.Visible = true
	UI.pop(banner, 1.4)
	for burst = 0, 2 do
		task.delay(burst * 0.35, Celebrate.sparks)
	end
	UI.toast(`🌟 Ascension level {level}! Back to Barometer Bay with a fresh start.`, "volt")
	bannerToken += 1
	local mine = bannerToken
	task.delay(BANNER_SECONDS, function()
		if bannerToken ~= mine then
			return -- another ascension is showing it
		end
		-- the text and its outline fade together, so no outline is left behind
		local info = TweenInfo.new(0.6)
		local fade = TweenService:Create(banner, info, { TextTransparency = 1 })
		if outline then
			TweenService:Create(outline, info, { Transparency = 1 }):Play()
		end
		fade.Completed:Once(function()
			if bannerToken == mine then
				banner.Visible = false
			end
		end)
		fade:Play()
	end)
end

local function onMessage(kind: unknown, data: unknown)
	if kind == "offer" and typeof(data) == "table" then
		showOffer(data :: any)
	elseif kind == "refused" then
		UI.toast(
			`🌟 Can't ascend yet: {if typeof(data) == "string" then data else "not ready"}`,
			"warn"
		)
	elseif kind == "done" and typeof(data) == "number" then
		current = nil
		celebrate(data)
	end
end

function AscensionUI.init()
	remote = Net.get("Ascend")
	local _, screenGui = Layout.screen("StormBottlerAscend", 6)
	local window = UI.window(screenGui, "AscendPanel", "🌟 ASCEND", PURPLE, Vector2.new(620, 540))
	panel = window.panel
	local body = window.body
	scroller = UI.list(body, {
		Name = "Offer",
		Size = UDim2.new(1, 0, 1, -100),
		gap = 10,
	})
	-- the offer: any length, so it grows to its text instead of being cut
	heading = UI.label({
		Text = "",
		LayoutOrder = 1,
		TextScaled = false,
		TextSize = HEADING_TEXT,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = scroller,
	})
	columns = UI.make(Instance.new("Frame"), {
		Name = "Columns",
		LayoutOrder = 2,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = scroller,
	})
	columnLayout = UI.make(Instance.new("UIListLayout"), {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = columns,
	})
	column(columns, 1, "RESETS", COLORS.red, AscensionRules.RESETS :: any)
	column(columns, 2, "STAYS", COLORS.green, AscensionRules.KEEPS :: any)
	countdown = UI.label({
		Text = "",
		TextColor3 = COLORS.subtext,
		TextWrapped = true,
		Parent = body,
	})
	UI.maxText(countdown, 18, 11)
	cancelButton = UI.button({
		Name = "Cancel",
		Text = "NOT YET",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(0.5, -6, 0, 54),
		BackgroundColor3 = COLORS.panelDark,
		Parent = body,
	})
	UI.maxText(cancelButton, 24, 12)
	cancelButton.Activated:Connect(function()
		current = nil
		UI.closePanels()
	end)
	confirmButton = UI.button({
		Name = "Confirm",
		Text = "🌟 ASCEND",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 1, 0),
		Size = UDim2.new(0.5, -6, 0, 54),
		BackgroundColor3 = PURPLE,
		Parent = body,
	})
	UI.maxText(confirmButton, 26, 12)
	confirmButton.Activated:Connect(function()
		local offer = current
		if not offer then
			return
		end
		UI.pop(confirmButton)
		current = nil
		UI.setEnabled(confirmButton, false, PURPLE)
		remote:FireServer(offer.token)
	end)
	-- the celebration banner, across the middle of the screen
	banner = UI.label({
		Name = "AscendBanner",
		Title = true,
		Text = "",
		TextColor3 = PURPLE,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.38),
		Size = UDim2.fromScale(0.8, 0.18),
		Visible = false,
		Parent = screenGui,
	})
	UI.maxText(banner, 64, 20)
	window.onResize(fit)
	remote.OnClientEvent:Connect(onMessage)
end

return AscensionUI
