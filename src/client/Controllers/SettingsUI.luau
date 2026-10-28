--!strict
-- SETTINGS panel (the ⚙️ menu tile, or Comma): tabs for Controls, Sound,
-- Graphics and Accessibility & HUD. Every row comes from the schema
-- (Util/Settings): a label, a one-line hint and its control (a toggle, a
-- slider with its value, a choice of buttons, or key buttons). Values are
-- read and written through Lib/SettingsStore, which saves them to the
-- profile, so every change applies at once.
--
-- Controls: a Keyboard and a Controller key per action. Tap one, then press
-- the new key ("Press a key…"); Backspace clears it, reserved keys are
-- refused, and a key another action had swaps with it. On touch screens the
-- tab just says to tap the buttons on screen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Rules = require(ReplicatedStorage.Shared.Util.Settings)
local Layout = require(script.Parent.Parent.Lib.Layout)
local SettingsStore = require(script.Parent.Parent.Lib.SettingsStore)
local Sfx = require(script.Parent.Parent.Lib.Sfx)
local UI = require(script.Parent.Parent.Lib.UI)

local COLORS = UI.COLORS
local GREY = Color3.fromRGB(150, 155, 175)
local TAB_HEIGHT = 40
local FOOTER_HEIGHT = 44
local CONFIRM_SECONDS = 4 -- a second tap within this confirms a reset
local CAPTURE_GRACE = 0.3 -- seconds: the tap that started listening isn't the new key
local CONTROL_WIDTH = 0.5 -- of a row: the control's share (the label has the rest)

local SettingsUI = {}

type Tab = { name: string, button: TextButton, page: ScrollingFrame }
type Capture = { key: string, device: Rules.Device, button: TextButton, since: number }

local panel: Frame
local tabs: { Tab } = {}
local current: Tab? = nil
local refreshers: { [string]: { () -> () } } = {} -- setting key -> its row's redraws
local capture: Capture? = nil
local touchNote: TextLabel
local controlRows: { GuiObject } = {}
local resetTab: TextButton
local resetAll: TextButton
local confirming: { [TextButton]: number } = {}

function SettingsUI.open()
	UI.openPanel(panel)
end

-- Is the panel waiting for a new key? (Shortcuts ignores keys meanwhile.)
function SettingsUI.isCapturing(): boolean
	return capture ~= nil
end

local function onRefresh(key: string, fn: () -> ())
	local list = refreshers[key]
	if not list then
		list = {}
		refreshers[key] = list
	end
	table.insert(list, fn)
	fn()
end

local function percent(value: number): string
	return `{math.round(value * 100)}%`
end

-- A row: the label and hint on the left, `height` tall; returns the row and
-- the area for its control on the right.
local function row(page: Instance, order: number, def: Rules.Def, height: number): (Frame, Frame)
	local frame = UI.make(Instance.new("Frame"), {
		Name = def.key,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = COLORS.panelDark,
		Parent = page,
	})
	UI.corner(frame, UDim.new(0, 10))
	UI.padding(frame, 8)
	local label = UI.label({
		Title = true,
		Text = string.upper(def.label),
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1 - CONTROL_WIDTH, -8, 0, 24),
		Parent = frame,
	})
	UI.maxText(label, 20)
	if def.hint ~= "" then
		local hint = UI.label({
			Text = def.hint,
			TextColor3 = COLORS.subtext,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			Position = UDim2.fromOffset(0, 26),
			Size = UDim2.new(1 - CONTROL_WIDTH, -8, 1, -26),
			Parent = frame,
		})
		UI.maxText(hint, 14)
	end
	local area = UI.make(Instance.new("Frame"), {
		Name = "Control",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromScale(CONTROL_WIDTH, 1),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	return frame, area
end

local function buildToggle(page: Instance, order: number, def: Rules.Def)
	local _, area = row(page, order, def, 64)
	local button = UI.button({
		Name = "Toggle",
		Text = "",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.new(0.6, 0, 0, 40),
		BackgroundColor3 = COLORS.panelTop,
		Parent = area,
	})
	UI.maxText(button, 20)
	button.Activated:Connect(function()
		UI.pop(button)
		SettingsStore.set(def.key, not SettingsStore.get(def.key))
	end)
	onRefresh(def.key, function()
		local on = SettingsStore.get(def.key) == true
		button.Text = if on then "ON" else "OFF"
		UI.setEnabled(button, true, if on then COLORS.green else COLORS.panelTop)
	end)
end

local function buildChoice(page: Instance, order: number, def: Rules.Def)
	local choices = def.choices or {}
	local _, area = row(page, order, def, 64)
	UI.make(Instance.new("UIGridLayout"), {
		CellSize = UDim2.new(1 / math.max(#choices, 1), -4, 0, 40),
		CellPadding = UDim2.fromOffset(4, 0),
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = area,
	})
	local buttons: { [string]: TextButton } = {}
	for index, choice in choices do
		local button = UI.button({
			Name = choice,
			Text = string.upper(choice),
			LayoutOrder = index,
			BackgroundColor3 = COLORS.panelTop,
			Parent = area,
		})
		UI.maxText(button, 16)
		button.Activated:Connect(function()
			UI.pop(button)
			SettingsStore.set(def.key, choice)
		end)
		buttons[choice] = button
	end
	onRefresh(def.key, function()
		local value = SettingsStore.get(def.key)
		for choice, button in buttons do
			UI.setEnabled(button, true, if choice == value then COLORS.volt else COLORS.panelTop)
		end
	end)
end

local function buildSlider(page: Instance, order: number, def: Rules.Def)
	local low, high, step = def.min or 0, def.max or 1, def.step or 0.05
	local isVolume = def.section == "Sound"
	local _, area = row(page, order, def, 64)
	local minus = UI.button({
		Name = "Minus",
		Text = "-",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(36, 36),
		BackgroundColor3 = COLORS.panelTop,
		Parent = area,
	})
	local plus = UI.button({
		Name = "Plus",
		Text = "+",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -58, 0.5, 0),
		Size = UDim2.fromOffset(36, 36),
		BackgroundColor3 = COLORS.panelTop,
		Parent = area,
	})
	local valueLabel = UI.label({
		Title = true,
		Text = "",
		TextColor3 = COLORS.volt,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(54, 30),
		Parent = area,
	})
	UI.maxText(valueLabel, 18)
	-- the bar: a wide invisible hit area round a thin track
	local bar = UI.make(Instance.new("TextButton"), {
		Name = "Bar",
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 46, 0.5, 0),
		Size = UDim2.new(1, -150, 0, 36),
		Parent = area,
	})
	local track = UI.make(Instance.new("Frame"), {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 10),
		BackgroundColor3 = COLORS.stroke,
		Parent = bar,
	})
	UI.corner(track, UDim.new(0.5, 0))
	local fill = UI.make(Instance.new("Frame"), {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = COLORS.storm,
		BorderSizePixel = 0,
		Parent = track,
	})
	UI.corner(fill, UDim.new(0.5, 0))
	local knob = UI.make(Instance.new("Frame"), {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(24, 24),
		BackgroundColor3 = COLORS.volt,
		ZIndex = 2,
		Parent = track,
	})
	UI.corner(knob, UDim.new(0.5, 0))
	UI.stroke(knob, 2)

	local function setFromX(x: number)
		local share = (x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1)
		SettingsStore.set(def.key, low + math.clamp(share, 0, 1) * (high - low))
	end
	local dragging: InputObject? = nil
	bar.InputBegan:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			dragging = input
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		local drag = dragging
		if
			drag
			and (
				input == drag
				or (
					input.UserInputType == Enum.UserInputType.MouseMovement
					and drag.UserInputType == Enum.UserInputType.MouseButton1
				)
			)
		then
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		local drag = dragging
		if drag and (input == drag or input.UserInputType == drag.UserInputType) then
			dragging = nil
			if isVolume then
				Sfx.play("click") -- hear the new level
			end
		end
	end)
	minus.Activated:Connect(function()
		SettingsStore.set(def.key, SettingsStore.get(def.key) - step)
	end)
	plus.Activated:Connect(function()
		SettingsStore.set(def.key, SettingsStore.get(def.key) + step)
	end)
	local function redraw()
		local value = SettingsStore.get(def.key)
		local share = (value - low) / math.max(high - low, 1e-6)
		fill.Size = UDim2.fromScale(share, 1)
		knob.Position = UDim2.fromScale(share, 0.5)
		valueLabel.Text = if high <= 1 then percent(value) else tostring(math.round(value))
		local muted = isVolume and SettingsStore.get("muted") == true
		fill.BackgroundColor3 = if muted then GREY else COLORS.storm
	end
	onRefresh(def.key, redraw)
	if isVolume then
		onRefresh("muted", redraw)
	end
end

-- Controls ------------------------------------------------------------------

local function keyButtonText(key: string): string
	if capture and capture.key == key then
		return "Press a key…"
	end
	local name = SettingsStore.get(key)
	return if typeof(name) == "string" and name ~= "" then Rules.keyLabel(name) else "—"
end

local function stopCapture()
	local was = capture
	capture = nil
	if was then
		was.button.Text = keyButtonText(was.key)
		UI.setEnabled(was.button, true, COLORS.panelTop)
	end
end

local function startCapture(key: string, device: Rules.Device, button: TextButton)
	stopCapture()
	capture = { key = key, device = device, button = button, since = os.clock() }
	button.Text = keyButtonText(key)
	UI.setEnabled(button, true, COLORS.volt)
end

-- The key pressed while listening: bind it (or clear, refuse, swap).
local function onCaptureInput(input: InputObject)
	local listening = capture
	if not listening then
		return
	end
	local kind = input.UserInputType
	local isPad = string.sub(kind.Name, 1, 7) == "Gamepad"
	local isKey = kind == Enum.UserInputType.Keyboard
	if not isPad and not isKey then
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			stopCapture() -- clicked elsewhere: cancel
		end
		return
	end
	local name = input.KeyCode.Name
	if
		os.clock() - listening.since < CAPTURE_GRACE
		or name == "Thumbstick1"
		or name == "Thumbstick2"
		or name == "Unknown"
	then
		return -- the press that started it, or a stick moving
	end
	if (listening.device == "Controller") ~= isPad then
		UI.toast(
			if isPad then "Press a key on the keyboard" else "Press a controller button",
			"info"
		)
		return
	end
	if name == "Backspace" then
		name = "" -- clears it
	end
	local values, swapped, reason = Rules.bind(SettingsStore.all(), listening.key, name)
	stopCapture()
	if not values then
		UI.toast(reason or "That key can't be used", "warn")
		return
	end
	SettingsStore.setAll(values)
	if swapped then
		local otherKey = Rules.bindKey(listening.device, swapped)
		local other = Rules.def(otherKey)
		local moved = values[otherKey]
		local where = if typeof(moved) == "string" and moved ~= ""
			then Rules.keyLabel(moved)
			else "no key"
		UI.toast(`Swapped: {if other then other.label else swapped} is now on {where}`, "info", 4)
	end
end

local function buildControls(page: ScrollingFrame)
	touchNote = UI.label({
		Name = "TouchNote",
		Text = "Touch controls: tap the buttons on screen",
		TextColor3 = COLORS.subtext,
		TextWrapped = true,
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, 60),
		Parent = page,
	})
	UI.maxText(touchNote, 20)
	local header = UI.make(Instance.new("Frame"), {
		Name = "Header",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
		Parent = page,
	})
	table.insert(controlRows, header)
	for index, title in { "KEYBOARD", "CONTROLLER" } do
		local label = UI.label({
			Title = true,
			Text = title,
			TextColor3 = COLORS.subtext,
			Position = UDim2.new(1 - CONTROL_WIDTH + (index - 1) * CONTROL_WIDTH / 2, 0, 0, 0),
			Size = UDim2.new(CONTROL_WIDTH / 2, -6, 1, 0),
			Parent = header,
		})
		UI.maxText(label, 16)
	end
	for index, action in Rules.ACTIONS do
		local def = Rules.def(Rules.bindKey("Keyboard", action.id)) :: Rules.Def
		local frame, area = row(page, index + 1, def, 52)
		table.insert(controlRows, frame)
		for column, device in { "Keyboard", "Controller" } :: { Rules.Device } do
			local key = Rules.bindKey(device, action.id)
			local button = UI.button({
				Name = device,
				Text = "",
				Position = UDim2.new((column - 1) / 2, 0, 0, 0),
				Size = UDim2.new(0.5, -6, 1, 0),
				BackgroundColor3 = COLORS.panelTop,
				Parent = area,
			})
			UI.maxText(button, 18)
			button.Activated:Connect(function()
				if capture and capture.key == key then
					stopCapture()
				else
					startCapture(key, device, button)
				end
			end)
			onRefresh(key, function()
				button.Text = keyButtonText(key)
			end)
		end
	end
	local closeNote = UI.label({
		Text = "Esc (keyboard) and B (controller) always close panels.",
		TextColor3 = COLORS.subtext,
		TextWrapped = true,
		LayoutOrder = #Rules.ACTIONS + 2,
		Size = UDim2.new(1, 0, 0, 30),
		Parent = page,
	})
	UI.maxText(closeNote, 14)
	table.insert(controlRows, closeNote)
	local function applyDevice()
		local touch = Layout.class == "Phone" or Layout.class == "Tablet"
		touchNote.Visible = touch
		for _, object in controlRows do
			object.Visible = not touch
		end
	end
	applyDevice()
	Layout.Changed:Connect(applyDevice)
end

-- Tabs, pages and resets ---------------------------------------------------------

local function selectTab(tab: Tab)
	stopCapture()
	current = tab
	for _, other in tabs do
		other.page.Visible = other == tab
		UI.setEnabled(other.button, true, if other == tab then COLORS.volt else COLORS.panelDark)
	end
	resetTab.Text = "RESET THIS TAB"
	resetAll.Text = "RESET ALL"
	confirming = {}
end

local function buildPage(body: Instance, section: string): ScrollingFrame
	local page = UI.list(body, {
		Name = section,
		Position = UDim2.fromOffset(0, TAB_HEIGHT + 8),
		Size = UDim2.new(1, 0, 1, -(TAB_HEIGHT + FOOTER_HEIGHT + 16)),
		Visible = false,
		gap = 8,
	})
	if section == "Controls" then
		buildControls(page)
		return page
	end
	local defs = Rules.inSection(section)
	for order, def in defs do
		if def.kind == "bool" then
			buildToggle(page, order, def)
		elseif def.kind == "slider" then
			buildSlider(page, order, def)
		elseif def.kind == "choice" then
			buildChoice(page, order, def)
		end
	end
	if #defs == 0 then
		local soon = UI.label({
			Text = "Coming soon",
			TextColor3 = COLORS.subtext,
			Size = UDim2.new(1, 0, 0, 60),
			Parent = page,
		})
		UI.maxText(soon, 20)
	end
	return page
end

-- A reset button: the first tap asks, a second within CONFIRM_SECONDS does it.
local function confirmTap(button: TextButton, askText: string, doIt: () -> ())
	local now = os.clock()
	if (confirming[button] or 0) > now then
		confirming[button] = nil
		doIt()
		return
	end
	confirming[button] = now + CONFIRM_SECONDS
	local before = button.Text
	button.Text = askText
	task.delay(CONFIRM_SECONDS, function()
		if (confirming[button] or 0) <= os.clock() and button.Text == askText then
			button.Text = before
		end
	end)
end

function SettingsUI.init()
	local _, root = Layout.screen("StormBottlerSettings", 6)
	local window =
		UI.window(root, "SettingsPanel", "⚙️ SETTINGS", COLORS.panelTop, Vector2.new(640, 560))
	panel = window.panel
	local body = window.body

	local tabBar = UI.make(Instance.new("Frame"), {
		Name = "Tabs",
		Size = UDim2.new(1, 0, 0, TAB_HEIGHT),
		BackgroundTransparency = 1,
		Parent = body,
	})
	UI.make(Instance.new("UIGridLayout"), {
		CellSize = UDim2.new(1 / #Rules.SECTIONS, -6, 1, 0),
		CellPadding = UDim2.fromOffset(6, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = tabBar,
	})

	local footer = UI.make(Instance.new("Frame"), {
		Name = "Footer",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, FOOTER_HEIGHT),
		BackgroundTransparency = 1,
		Parent = body,
	})
	resetTab = UI.button({
		Name = "ResetTab",
		Text = "RESET THIS TAB",
		Size = UDim2.new(0.5, -4, 1, 0),
		BackgroundColor3 = COLORS.panelTop,
		Parent = footer,
	})
	UI.maxText(resetTab, 18)
	resetAll = UI.button({
		Name = "ResetAll",
		Text = "RESET ALL",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.5, -4, 1, 0),
		BackgroundColor3 = COLORS.red,
		Parent = footer,
	})
	UI.maxText(resetAll, 18)

	for order, section in Rules.SECTIONS do
		local button = UI.button({
			Name = section,
			Text = string.upper(section),
			LayoutOrder = order,
			BackgroundColor3 = COLORS.panelDark,
			Parent = tabBar,
		})
		UI.maxText(button, 15)
		local tab: Tab = { name = section, button = button, page = buildPage(body, section) }
		table.insert(tabs, tab)
		button.Activated:Connect(function()
			if current ~= tab then
				UI.pop(button)
				Sfx.play("tab")
				selectTab(tab)
			end
		end)
	end

	resetTab.Activated:Connect(function()
		local tab = current
		if not tab then
			return
		end
		confirmTap(resetTab, `TAP AGAIN: RESET {string.upper(tab.name)}`, function()
			local values = SettingsStore.all()
			for _, def in Rules.inSection(tab.name) do
				values[def.key] = def.default
			end
			SettingsStore.setAll(values)
			resetTab.Text = "RESET THIS TAB"
			UI.toast(`{tab.name} settings reset`, "good")
		end)
	end)
	resetAll.Activated:Connect(function()
		confirmTap(resetAll, "TAP AGAIN: RESET ALL", function()
			-- everything back to default, except what's only remembered
			-- (the device's Quality was set, the flashing question answered)
			local values = Rules.defaults()
			for _, def in Rules.DEFS do
				if def.section == Rules.HIDDEN then
					values[def.key] = SettingsStore.get(def.key)
				end
			end
			SettingsStore.setAll(values)
			resetAll.Text = "RESET ALL"
			UI.toast("Every setting is back to its default", "good")
		end)
	end)

	selectTab(tabs[1])
	SettingsStore.Changed:Connect(function(key: string)
		for _, fn in refreshers[key] or {} do
			fn()
		end
	end)
	UserInputService.InputBegan:Connect(onCaptureInput)
	-- closing the panel stops listening for a key
	panel:GetPropertyChangedSignal("Visible"):Connect(function()
		if not panel.Visible then
			stopCapture()
		end
	end)
end

return SettingsUI
