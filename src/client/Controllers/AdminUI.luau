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
--   * TEST NOTIFY: sends you a "daily reward ready" phone notification
--     now (live servers only; Roblox delivers it if you've allowed this
--     game's notifications, at most one a day)
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
local ROW = 44 -- one row's height in design pixels (taller on touch: UI.tall)
local GAP = 8

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

-- The panel is one scrolling column of strips. A strip is a row of cells
-- (boxes, buttons) that share its width; fit sets the sizes from the
-- panel's width. A strip with a `least` width per cell puts its cells on
-- as many lines as that needs, instead of squeezing them.
type Cell = { object: GuiObject, share: number }
type Strip = { frame: Frame, cells: { Cell }, least: number? }
local strips: { Strip } = {}

local function strip(parent: Instance, index: number, least: number?): Strip
	local frame = UI.make(Instance.new("Frame"), {
		Name = `Row{index}`,
		LayoutOrder = index,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, ROW),
		Parent = parent,
	})
	local made: Strip = { frame = frame, cells = {}, least = least }
	table.insert(strips, made)
	return made
end

local function add(row: Strip, object: GuiObject, share: number)
	object.Parent = row.frame
	table.insert(row.cells, { object = object, share = share })
end

local function box(name: string, hint: string): TextBox
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
	})
	UI.corner(textBox, UDim.new(0, 10))
	UI.maxText(textBox, 20, 11)
	return textBox
end

local function button(name: string, text: string, color: Color3): TextButton
	local made = UI.button({
		Name = name,
		Text = text,
		BackgroundColor3 = color,
	})
	UI.maxText(made, 18, 11)
	return made
end

-- Sizes every strip for items `width` wide: each cell its share of the
-- width, in one line, or, where a strip has a `least` and the cells would
-- be narrower than that, in as many lines as needed.
local function fitStrips(width: number)
	local height = UI.tall(ROW)
	for _, row in strips do
		local count = #row.cells
		local columns = count
		if row.least then
			columns = UI.columns(width, row.least, GAP, count)
		end
		if columns == count then
			local total = 0
			for _, cell in row.cells do
				total += cell.share
			end
			local room = width - GAP * (count - 1)
			local x = 0
			for _, cell in row.cells do
				local across = math.floor(room * cell.share / total)
				cell.object.Position = UDim2.fromOffset(x, 0)
				cell.object.Size = UDim2.fromOffset(across, height)
				x += across + GAP
			end
			row.frame.Size = UDim2.new(1, 0, 0, height)
		else
			local across = math.floor((width - GAP * (columns - 1)) / columns)
			for index, cell in row.cells do
				local column, line = (index - 1) % columns, (index - 1) // columns
				local x, y = column * (across + GAP), line * (height + GAP)
				cell.object.Position = UDim2.fromOffset(x, y)
				cell.object.Size = UDim2.fromOffset(across, height)
			end
			local lines = math.ceil(count / columns)
			row.frame.Size = UDim2.new(1, 0, 0, lines * height + (lines - 1) * GAP)
		end
	end
end

local function build(root: Frame)
	local window =
		UI.window(root, "AdminPanel", "🛡 ADMIN", COLORS.stormDeep, Vector2.new(660, 660))
	panel = window.panel
	local scroller = UI.list(window.body, {
		Name = "Admin",
		Size = UDim2.fromScale(1, 1),
		gap = GAP,
	})

	-- 1. who
	local r1 = strip(scroller, 1)
	targetBox = box("Target", "Username or user id")
	add(r1, targetBox, 0.6)
	local lookupButton = button("Lookup", "🔎 LOOK UP", COLORS.storm)
	add(r1, lookupButton, 0.4)

	-- 2. why
	local r2 = strip(scroller, 2)
	reasonBox = box("Reason", "Reason (for kick and ban)")
	add(r2, reasonBox, 1)

	-- 3. kick, ban (for how long), unban
	local r3 = strip(scroller, 3)
	local kickButton = button("Kick", "👢 KICK", COLORS.voltDeep)
	add(r3, kickButton, 0.22)
	local banButton = button("Ban", "⛔ BAN", COLORS.red)
	add(r3, banButton, 0.22)
	local banLength = button("BanLength", "", COLORS.panelTop)
	add(r3, banLength, 0.3)
	local unbanButton = button("Unban", "✅ UNBAN", COLORS.green)
	add(r3, unbanButton, 0.26)

	-- 4. give Volts
	local r4 = strip(scroller, 4)
	voltsBox = box("Amount", "Volts to give (up to 1000000000000)")
	add(r4, voltsBox, 0.6)
	local voltsButton = button("GiveVolts", "⚡ GIVE VOLTS", COLORS.volt)
	add(r4, voltsButton, 0.4)

	-- 5. give a boost
	local r5 = strip(scroller, 5)
	local boostKind = button("BoostKind", "", COLORS.panelTop)
	add(r5, boostKind, 0.4)
	local boostLength = button("BoostLength", "", COLORS.panelTop)
	add(r5, boostLength, 0.2)
	local boostButton = button("GiveBoost", "🚀 GIVE BOOST", COLORS.calm)
	add(r5, boostButton, 0.4)

	-- 6. reset, test error, test notification (a line each on a narrow panel)
	local r6 = strip(scroller, 6, 150)
	local resetButton = button("Reset", "🧨 RESET PROFILE", COLORS.red)
	add(r6, resetButton, 0.36)
	local testButton = button("TestError", "🐞 TEST ERROR", COLORS.panelTop)
	add(r6, testButton, 0.32)
	local notifyButton = button("TestNotify", "🔔 TEST NOTIFY", COLORS.panelTop)
	add(r6, notifyButton, 0.32)

	-- 7. what the server said (two lines at most, shrunk to fit)
	status = UI.label({
		Name = "Status",
		Text = "",
		TextColor3 = COLORS.subtext,
		TextWrapped = true,
		LayoutOrder = 7,
		Size = UDim2.new(1, 0, 0, 40),
		Parent = scroller,
	})
	UI.maxText(status, 18, 11)

	-- 8. errors or a lookup: a title and ERRORS, then the text, which
	-- grows to fit and scrolls with the rest of the panel
	local r8 = strip(scroller, 8)
	outputTitle = UI.label({
		Name = "Title",
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	UI.maxText(outputTitle, 18, 11)
	add(r8, outputTitle, 0.68)
	local refresh = button("Errors", "🔄 ERRORS", COLORS.panelTop)
	add(r8, refresh, 0.32)
	local outputBox = UI.make(Instance.new("Frame"), {
		Name = "Output",
		LayoutOrder = 9,
		BackgroundColor3 = COLORS.panelDark,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = scroller,
	})
	UI.corner(outputBox, UDim.new(0, 10))
	UI.padding(outputBox, 8)
	output = UI.label({
		Name = "Text",
		Text = "",
		TextScaled = false,
		TextSize = 15,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		Parent = outputBox,
	})
	window.onResize(function(size: Vector2)
		fitStrips(UI.listWidth(size.X))
		status.Size = UDim2.new(1, 0, 0, 2 * (math.max(UI.textSize(), 16) + 4))
		output.TextSize = math.max(15, UI.textSize())
	end)

	-- the cycling choices
	local banChoices = Config.ADMIN.banSeconds
	local boostChoices = Config.BOOSTS
	local minuteChoices = Config.ADMIN.boostMinutes
	local function showChoices()
		banLength.Text = `⏱️ {Ops.banLabel(banChoices[banIndex])}`
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
			resetButton.Text = `⚠️ TAP AGAIN: RESET {string.upper(name)}?`
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
	notifyButton.Activated:Connect(function()
		send("testNotify")
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
	-- (LayoutMath.hud.test)
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
