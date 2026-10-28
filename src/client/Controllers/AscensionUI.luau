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
local heading: TextLabel
local countdown: TextLabel
local confirmButton: TextButton
local banner: TextLabel
local current: Offer? = nil
local offerId = 0

-- Asks the server whether the player can ascend (the Shop's ASCEND button).
function AscensionUI.ask()
	remote:FireServer()
end

local function column(parent: Frame, x: number, title: string, color: Color3, lines: { string })
	local frame = UI.make(Instance.new("Frame"), {
		Name = title,
		Position = UDim2.new(x, if x > 0 then 6 else 0, 0, 92),
		Size = UDim2.new(0.5, -6, 1, -170),
		BackgroundColor3 = COLORS.panelDark,
		Parent = parent,
	})
	UI.corner(frame, UDim.new(0, 12))
	UI.stroke(frame, 3, color)
	local label = UI.label({
		Title = true,
		Text = title,
		TextColor3 = color,
		Position = UDim2.new(0, 10, 0, 6),
		Size = UDim2.new(1, -20, 0, 30),
		Parent = frame,
	})
	UI.maxText(label, 24)
	for index, line in lines do
		local item = UI.label({
			Text = `• {line}`,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.new(0, 10, 0, 40 + (index - 1) * 34),
			Size = UDim2.new(1, -20, 0, 30),
			Parent = frame,
		})
		UI.maxText(item, 18)
	end
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

local function celebrate(level: number)
	UI.closePanels()
	Sfx.play("level_up")
	banner.Text = `🌟 ASCENDED! Level {level} {AscensionRules.stars(level)}\n`
		.. `{AscensionRules.bonusText(level)} Volts on every sale`
	banner.TextTransparency = 0
	banner.Visible = true
	UI.pop(banner, 1.4)
	for burst = 0, 2 do
		task.delay(burst * 0.35, Celebrate.sparks)
	end
	UI.toast(`🌟 Ascension level {level}! Back to Barometer Bay with a fresh start.`, "volt")
	task.delay(BANNER_SECONDS, function()
		local fade = TweenService:Create(banner, TweenInfo.new(0.6), { TextTransparency = 1 })
		fade.Completed:Once(function()
			banner.Visible = false
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
	heading = UI.label({
		Text = "",
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, 0, 0, 80),
		TextWrapped = true,
		Parent = body,
	})
	UI.maxText(heading, 22)
	column(body, 0, "RESETS", COLORS.red, AscensionRules.RESETS :: any)
	column(body, 0.5, "STAYS", COLORS.green, AscensionRules.KEEPS :: any)
	countdown = UI.label({
		Text = "",
		TextColor3 = COLORS.subtext,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -62),
		Size = UDim2.new(1, 0, 0, 22),
		Parent = body,
	})
	UI.maxText(countdown, 18)
	local cancel = UI.button({
		Name = "Cancel",
		Text = "NOT YET",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(0.5, -6, 0, 54),
		BackgroundColor3 = COLORS.panelDark,
		Parent = body,
	})
	UI.maxText(cancel, 24)
	cancel.Activated:Connect(function()
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
	UI.maxText(confirmButton, 26)
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
	UI.maxText(banner, 64)
	remote.OnClientEvent:Connect(onMessage)
end

return AscensionUI
