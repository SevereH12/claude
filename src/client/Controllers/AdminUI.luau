--!strict
-- The admin panel. Admins (the group's owner, group ranks at
-- Config.ADMIN_RANK and up, and everyone in Studio: Systems/Admin) see an
-- ADMIN button under the MENU button; it opens this panel:
--   * a username (or user id) box, then KICK, BAN (for the length on the
--     button beside it), UNBAN, LOOK UP (their saved data, read only)
--   * a reason box, used by KICK and BAN
--   * GIVE VOLTS (the amount box), GIVE BOOST (the boost and length on the
--     buttons beside it), both for a player in this server
--   * RESET PROFILE: tap twice to confirm; it starts their save again
--   * TEST ERROR: a test error on the server and on this device, to check
--     error reporting
--   * the box at the bottom: this server's most recent errors (Systems/
--     Errors), or a looked-up player's data
-- The button only shows; the server checks every request (Systems/Admin).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Ops = require(ReplicatedStorage.Shared.Util.Ops)
local Layout = require(script.Parent.Parent.Lib.Layout)
local LayoutMath = require(script.Parent.Parent.Lib.LayoutMath)
local UI = require(script.Parent.Parent.Lib.UI)

local COLORS = UI.COLORS
local ATTRIBUTE = "Admin"
local CONFIRM_SECONDS = 4
local ROW = 0.075 -- one row's height, as a share of the panel body
local GAP = 0.012

local player = Players.LocalPlayer

local AdminUI = {}

local remote: RemoteEvent
local panel: Frame
local targetBox: TextBox
local reasonBox: TextBox
local voltsBox: TextBox
local status: TextLabel
local outputTitle: TextLabel
local output: TextLabel

local banIndex = 1
local boostIndex = 1
local minutesIndex = 2
local showing = "errors" -- what the box at the bottom shows: "errors" or "lookup"
local lastErrors: { any } = {}
local resetArmed: string? = nil -- the name a first RESET tap was for
local resetToken = 0

local function send(action: string, args: { [string]: any }?)
	remote:FireServer(action, args or {})
end

local function setStatus(text: string, ok: boolean)
	status.Text = text
	status.TextColor3 = if ok then COLORS.calm else COLORS.red
end

local function target(): string?
	local name = Ops.parseTarget(targetBox.Text)
	if not name then
		setStatus("Type a username (or a user id) first", false)
	end
	return name
end

local function showErrors()
	showing = "errors"
	outputTitle.Text = `RECENT ERRORS IN THIS SERVER ({#lastErrors})`
	if #lastErrors == 0 then
		output.Text = "No errors yet."
		return
	end
	local lines = {}
	for _, entry in lastErrors do
		local who = if entry.who ~= "" then ` · {entry.who}` else ""
		local time = os.date("!%H:%M", entry.time)
		table.insert(
			lines,
			`[{entry.source}] {entry.count}x  {time} UTC{who}\n   {entry.fingerprint}\n   {entry.message}`
		)
	end
	output.Text = table.concat(lines, "\n")
end

local function row(parent: Instance, index: number): Frame
	return UI.make(Instance.new("Frame"), {
		Name = `Row{index}`,
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0, (index - 1) * (ROW + GAP)),
		Size = UDim2.fromScale(1, ROW),
		Parent = parent,
	})
end

-- Pieces of a row, left to right, each `share` of its width.
local function cells(shares: { number }): { UDim2 }
	local spots = {}
	local x = 0
	for _, share in shares do
		table.insert(spots, UDim2.new(x, if x > 0 then 4 else 0, 0, 0))
		x += share
	end
	return spots
end

local function box(parent: Instance, name: string, hint: string, x: UDim2, width: number): TextBox
	local textBox = UI.make(Instance.new("TextBox"), {
		Name = name,
		PlaceholderText = hint,
		Text = "",
		ClearTextOnFocus = false,
		Font = UI.FONT_BODY,
		TextScaled = true,
		TextColor3 = COLORS.text,
		PlaceholderColor3 = COLORS.subtext,
		BackgroundColor3 = COLORS.panelDark,
		Position = x,
		Size = UDim2.new(width, -4, 1, 0),
		Parent = parent,
	})
	UI.corner(textBox, UDim.new(0, 10))
	UI.maxText(textBox, 20)
	return textBox
end

local function button(
	parent: Instance,
	name: string,
	text: string,
	color: Color3,
	x: UDim2,
	width: number
): TextButton
	local made = UI.button({
		Name = name,
		Text = text,
		BackgroundColor3 = color,
		Position = x,
		Size = UDim2.new(width, -4, 1, 0),
		Parent = parent,
	})
	UI.maxText(made, 18)
	return made
end

local function build(root: Frame)
	local window =
		UI.window(root, "AdminPanel", "🛡 ADMIN", COLORS.stormDeep, Vector2.new(660, 660))
	panel = window.panel
	local body = window.body

	-- 1. who
	local r1 = row(body, 1)
	local s1 = cells({ 0.6, 0.4 })
	targetBox = box(r1, "Target", "Username or user id", s1[1], 0.6)
	local lookupButton = button(r1, "Lookup", "🔎 LOOK UP", COLORS.storm, s1[2], 0.4)

	-- 2. why
	local r2 = row(body, 2)
	reasonBox = box(r2, "Reason", "Reason (for kick and ban)", UDim2.new(), 1)

	-- 3. kick, ban (for how long), unban
	local r3 = row(body, 3)
	local s3 = cells({ 0.22, 0.22, 0.3, 0.26 })
	local kickButton = button(r3, "Kick", "👢 KICK", COLORS.voltDeep, s3[1], 0.22)
	local banButton = button(r3, "Ban", "⛔ BAN", COLORS.red, s3[2], 0.22)
	local banLength = button(r3, "BanLength", "", COLORS.panelTop, s3[3], 0.3)
	local unbanButton = button(r3, "Unban", "✅ UNBAN", COLORS.green, s3[4], 0.26)

	-- 4. give Volts
	local r4 = row(body, 4)
	local s4 = cells({ 0.6, 0.4 })
	voltsBox = box(r4, "Amount", "Volts to give (up to 1000000000000)", s4[1], 0.6)
	local voltsButton = button(r4, "GiveVolts", "⚡ GIVE VOLTS", COLORS.volt, s4[2], 0.4)

	-- 5. give a boost
	local r5 = row(body, 5)
	local s5 = cells({ 0.4, 0.2, 0.4 })
	local boostKind = button(r5, "BoostKind", "", COLORS.panelTop, s5[1], 0.4)
	local boostLength = button(r5, "BoostLength", "", COLORS.panelTop, s5[2], 0.2)
	local boostButton = button(r5, "GiveBoost", "🚀 GIVE BOOST", COLORS.calm, s5[3], 0.4)

	-- 6. reset, test error
	local r6 = row(body, 6)
	local s6 = cells({ 0.5, 0.5 })
	local resetButton = button(r6, "Reset", "🧨 RESET PROFILE", COLORS.red, s6[1], 0.5)
	local testButton = button(r6, "TestError", "🐞 TEST ERROR", COLORS.panelTop, s6[2], 0.5)

	-- 7. what the server said
	status = UI.label({
		Name = "Status",
		Text = "",
		TextColor3 = COLORS.subtext,
		Position = UDim2.fromScale(0, 6 * (ROW + GAP)),
		Size = UDim2.fromScale(1, ROW * 0.8),
		Parent = body,
	})
	UI.maxText(status, 18)

	-- 8. errors or a lookup
	local top = 7 * (ROW + GAP)
	local r8 = UI.make(Instance.new("Frame"), {
		Name = "OutputBar",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0, top),
		Size = UDim2.fromScale(1, ROW),
		Parent = body,
	})
	outputTitle = UI.label({
		Name = "Title",
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromScale(0.68, 1),
		Parent = r8,
	})
	UI.maxText(outputTitle, 18)
	local refresh =
		button(r8, "Errors", "🔄 ERRORS", COLORS.panelTop, UDim2.fromScale(0.68, 0), 0.32)
	local scroll = UI.make(Instance.new("ScrollingFrame"), {
		Name = "Output",
		BackgroundColor3 = COLORS.panelDark,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0, top + ROW + GAP),
		Size = UDim2.fromScale(1, 1 - (top + ROW + GAP)),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = body,
	})
	UI.corner(scroll, UDim.new(0, 10))
	UI.padding(scroll, 8)
	output = UI.label({
		Name = "Text",
		Text = "",
		TextScaled = false,
		TextSize = 15,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, -8, 0, 0),
		Parent = scroll,
	})

	-- the cycling choices
	local banChoices = Config.ADMIN.banSeconds
	local boostChoices = Config.BOOSTS
	local minuteChoices = Config.ADMIN.boostMinutes
	local function showChoices()
		banLength.Text = `⏱ {Ops.banLabel(banChoices[banIndex])}`
		local boost = boostChoices[boostIndex]
		boostKind.Text = if boost then `{boost.icon} {boost.name}` else "-"
		boostLength.Text = `{minuteChoices[minutesIndex]} min`
	end
	showChoices()
	banLength.Activated:Connect(function()
		banIndex = banIndex % #banChoices + 1
		showChoices()
	end)
	boostKind.Activated:Connect(function()
		boostIndex = boostIndex % math.max(#boostChoices, 1) + 1
		showChoices()
	end)
	boostLength.Activated:Connect(function()
		minutesIndex = minutesIndex % #minuteChoices + 1
		showChoices()
	end)

	-- the actions (the server checks and answers every one)
	lookupButton.Activated:Connect(function()
		local name = target()
		if name then
			setStatus(`Looking up {name}...`, true)
			send("lookup", { target = name })
		end
	end)
	kickButton.Activated:Connect(function()
		local name = target()
		if name then
			send("kick", { target = name, reason = reasonBox.Text })
		end
	end)
	banButton.Activated:Connect(function()
		local name = target()
		if name then
			send("ban", { target = name, seconds = banChoices[banIndex], reason = reasonBox.Text })
		end
	end)
	unbanButton.Activated:Connect(function()
		local name = target()
		if name then
			send("unban", { target = name })
		end
	end)
	voltsButton.Activated:Connect(function()
		local name = target()
		local amount = tonumber((string.gsub(voltsBox.Text, "[,%s_]", "")))
		if not name then
			return
		elseif not amount then
			setStatus("Type how many Volts to give", false)
			return
		end
		send("volts", { target = name, amount = amount })
	end)
	boostButton.Activated:Connect(function()
		local name = target()
		local boost = boostChoices[boostIndex]
		if name and boost then
			send("boost", { target = name, key = boost.key, minutes = minuteChoices[minutesIndex] })
		end
	end)
	resetButton.Activated:Connect(function()
		local name = target()
		if not name then
			return
		end
		if resetArmed ~= name then
			resetArmed = name
			resetToken += 1
			local mine = resetToken
			resetButton.Text = `⚠ TAP AGAIN: RESET {string.upper(name)}?`
			task.delay(CONFIRM_SECONDS, function()
				if resetToken == mine then
					resetArmed = nil
					resetButton.Text = "🧨 RESET PROFILE"
				end
			end)
			return
		end
		resetArmed = nil
		resetToken += 1
		resetButton.Text = "🧨 RESET PROFILE"
		send("reset", { target = name, confirm = "RESET" })
	end)
	testButton.Activated:Connect(function()
		send("testError")
		task.spawn(function()
			error("[Admin] test error from the client")
		end)
	end)
	refresh.Activated:Connect(function()
		send("open")
		showErrors()
	end)
end

local function onMessage(kind: unknown, data: unknown)
	if typeof(data) ~= "table" then
		return
	end
	local info = data :: any
	if kind == "result" then
		setStatus(tostring(info.text), info.ok == true)
	elseif kind == "state" then
		lastErrors = if typeof(info.errors) == "table" then info.errors else {}
		if showing == "errors" then
			showErrors()
		end
	elseif kind == "lookup" then
		showing = "lookup"
		outputTitle.Text = `{info.name} ({info.userId}): {info.where}`
		output.Text = if typeof(info.lines) == "table" then table.concat(info.lines, "\n") else ""
		setStatus(`Showing {info.name}'s data (read only)`, true)
	end
end

function AdminUI.init()
	remote = Net.get("Admin")
	local _, root = Layout.screen("StormBottlerAdmin", 8)
	build(root)
	remote.OnClientEvent:Connect(onMessage)

	-- the ADMIN button: the first row under the MENU button
	-- (LayoutMath.hud.test; the Studio TEST buttons are the rows under it)
	local open = UI.button({
		Name = "AdminButton",
		Text = "🛡 ADMIN",
		BackgroundColor3 = COLORS.stormDeep,
		Visible = false,
		Parent = root,
	})
	UI.maxText(open, 20)
	UI.onLayout(function()
		local area = Layout.hud.test
		local height = (area.h - LayoutMath.GAP) / 2
		UI.place(open, { x = area.x, y = area.y, w = area.w, h = height })
	end)
	local function showButton()
		open.Visible = player:GetAttribute(ATTRIBUTE) == true
		if not open.Visible and panel.Visible then
			UI.closePanels()
		end
	end
	showButton()
	player:GetAttributeChangedSignal(ATTRIBUTE):Connect(showButton)
	open.Activated:Connect(function()
		UI.pop(open)
		if UI.togglePanel(panel) then
			send("open")
			showErrors()
		end
	end)
end

return AdminUI
