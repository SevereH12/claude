--!strict
-- Helpers for building UI in code, plus the shared look (colours, fonts,
-- animation timings) so every screen feels like the same game. Also
-- UI.toast: the one way to put a warning, hint or notice on screen.

local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")

local Layout = require(script.Parent.Layout)
local LayoutMath = require(script.Parent.LayoutMath)
local ToastQueue = require(script.Parent.ToastQueue)

local UI = {}

UI.COLORS = table.freeze({
	panelTop = Color3.fromRGB(44, 52, 92),
	panelBottom = Color3.fromRGB(20, 23, 44),
	panelDark = Color3.fromRGB(12, 14, 28),
	stroke = Color3.fromRGB(6, 8, 18),
	text = Color3.fromRGB(255, 255, 255),
	subtext = Color3.fromRGB(190, 200, 235),
	volt = Color3.fromRGB(255, 214, 60),
	voltDeep = Color3.fromRGB(255, 150, 30),
	storm = Color3.fromRGB(100, 160, 255),
	stormDeep = Color3.fromRGB(70, 90, 230),
	calm = Color3.fromRGB(110, 220, 140),
	green = Color3.fromRGB(80, 210, 100),
	red = Color3.fromRGB(235, 75, 75),
	disabled = Color3.fromRGB(85, 90, 110),
})

UI.FONT_TITLE = Enum.Font.LuckiestGuy -- big numbers, headings
UI.FONT_BODY = Enum.Font.BuilderSansExtraBold -- everything else

UI.TWEEN = table.freeze({
	popOut = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	popBack = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	open = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	fast = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	countUp = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
})

-- Sets properties on an instance (Parent last) and returns it, typed.
function UI.make<T>(instance: T, props: { [string]: any }): T
	local parent = props.Parent
	for key, value in props do
		if key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end
	if parent then
		(instance :: any).Parent = parent
	end
	return instance
end

function UI.corner(parent: Instance, radius: UDim?): UICorner
	return UI.make(Instance.new("UICorner"), {
		CornerRadius = radius or UDim.new(0.25, 0),
		Parent = parent,
	})
end

function UI.stroke(parent: Instance, thickness: number?, color: Color3?): UIStroke
	return UI.make(Instance.new("UIStroke"), {
		Color = color or UI.COLORS.stroke,
		Thickness = thickness or 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

-- Vertical gradient. Gradients multiply the background colour, so white to
-- grey on a coloured button gives it a lit-from-above look.
function UI.gradient(parent: Instance, top: Color3, bottom: Color3): UIGradient
	return UI.make(Instance.new("UIGradient"), {
		Color = ColorSequence.new(top, bottom),
		Rotation = 90,
		Parent = parent,
	})
end

-- Every text size limit, so phones can raise the minimum (readable text).
local textLimits: { [UITextSizeConstraint]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function minText(limit: UITextSizeConstraint)
	limit.MinTextSize =
		math.min(LayoutMath.minTextSize(Layout.class, Layout.scale), limit.MaxTextSize)
end

function UI.maxText(parent: Instance, size: number)
	local limit = UI.make(Instance.new("UITextSizeConstraint"), {
		MaxTextSize = size,
		Parent = parent,
	})
	textLimits[limit] = true
	minText(limit)
end

-- Every button's size limit, so touch screens can keep it TAP_MIN points.
local tapLimits: { [UISizeConstraint]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local HUGE = Vector2.new(math.huge, math.huge)

local function vectorAttribute(limit: Instance, name: string, default: Vector2): Vector2
	local value = limit:GetAttribute(name)
	return if typeof(value) == "Vector2" then value else default
end

local function applyTap(limit: UISizeConstraint)
	local min = LayoutMath.tapMin(
		Layout.class,
		Layout.scale,
		vectorAttribute(limit, "BaseMin", Vector2.zero)
	)
	local max = vectorAttribute(limit, "BaseMax", HUGE)
	limit.MinSize = min
	limit.MaxSize = Vector2.new(math.max(max.X, min.X), math.max(max.Y, min.Y))
end

-- One size constraint per object (made here or reused), so a button's
-- limits and its touch minimum never fight.
function UI.sizeLimits(parent: Instance, min: Vector2, max: Vector2)
	local limit = parent:FindFirstChildOfClass("UISizeConstraint")
		or UI.make(Instance.new("UISizeConstraint"), { Parent = parent })
	limit:SetAttribute("BaseMin", min)
	limit:SetAttribute("BaseMax", max)
	if tapLimits[limit] then
		applyTap(limit)
	else
		limit.MinSize = min
		limit.MaxSize = max
	end
end

Layout.Changed:Connect(function()
	for limit in textLimits do
		minText(limit)
	end
	for limit in tapLimits do
		applyTap(limit)
	end
end)

-- `amount` pixels of padding on every side.
function UI.padding(parent: Instance, amount: number)
	local pad = UDim.new(0, amount)
	UI.make(Instance.new("UIPadding"), {
		PaddingTop = pad,
		PaddingBottom = pad,
		PaddingLeft = pad,
		PaddingRight = pad,
		Parent = parent,
	})
end

local function textStroke(parent: Instance, thickness: number)
	UI.make(Instance.new("UIStroke"), {
		Color = UI.COLORS.stroke,
		Thickness = thickness,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = parent,
	})
end

local function withDefaults(
	defaults: { [string]: any },
	props: { [string]: any }
): { [string]: any }
	for key, value in props do
		defaults[key] = value
	end
	return defaults
end

-- Text with a dark outline. Pass Title = true for the big chunky font.
function UI.label(props: { [string]: any }): TextLabel
	local isTitle = props.Title == true
	props.Title = nil
	local label = UI.make(
		Instance.new("TextLabel"),
		withDefaults({
			BackgroundTransparency = 1,
			Font = if isTitle then UI.FONT_TITLE else UI.FONT_BODY,
			TextColor3 = UI.COLORS.text,
			TextScaled = true,
		}, props)
	)
	textStroke(label, if isTitle then 3 else 2)
	return label
end

-- Dark rounded panel with a soft gradient and outline.
function UI.panel(props: { [string]: any }): Frame
	local panel = UI.make(
		Instance.new("Frame"),
		withDefaults({
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
		}, props)
	)
	UI.corner(panel, UDim.new(0, 14))
	UI.stroke(panel, 3)
	UI.gradient(panel, UI.COLORS.panelTop, UI.COLORS.panelBottom)
	UI.make(Instance.new("UIScale"), { Parent = panel })
	return panel
end

-- Chunky button: lit gradient, outline, and a darker "base" under it.
function UI.button(props: { [string]: any }): TextButton
	local button = UI.make(
		Instance.new("TextButton"),
		withDefaults({
			AutoButtonColor = true,
			Font = UI.FONT_TITLE,
			TextColor3 = UI.COLORS.text,
			TextScaled = true,
		}, props)
	)
	UI.corner(button, UDim.new(0.3, 0))
	UI.stroke(button, 3)
	UI.gradient(button, Color3.new(1, 1, 1), Color3.fromRGB(175, 175, 185))
	textStroke(button, 2.5)
	UI.make(Instance.new("UIPadding"), {
		PaddingTop = UDim.new(0.16, 0),
		PaddingBottom = UDim.new(0.16, 0),
		PaddingLeft = UDim.new(0.08, 0),
		PaddingRight = UDim.new(0.08, 0),
		Parent = button,
	})
	-- every button is a tap target: at least TAP_MIN points on touch
	local limit = UI.make(Instance.new("UISizeConstraint"), { Parent = button })
	tapLimits[limit] = true
	applyTap(limit)
	return button
end

function UI.setEnabled(button: TextButton, enabled: boolean, color: Color3)
	button.BackgroundColor3 = if enabled then color else UI.COLORS.disabled
	button.AutoButtonColor = enabled
end

-- Quick squash-and-bounce on press or reward.
function UI.pop(target: GuiObject, amount: number?)
	local scale = target:FindFirstChildOfClass("UIScale")
		or UI.make(Instance.new("UIScale"), { Parent = target })
	local out = TweenService:Create(scale, UI.TWEEN.popOut, { Scale = amount or 0.9 })
	out.Completed:Once(function()
		TweenService:Create(scale, UI.TWEEN.popBack, { Scale = 1 }):Play()
	end)
	out:Play()
end

-- Panels ------------------------------------------------------------------------------
-- One panel open at a time. Opening pops it in (scale up with a little
-- overshoot) over a dimmed backdrop; closing shrinks it away. Tapping the
-- backdrop, Esc or gamepad B closes it. With a gamepad, opening selects the
-- panel's first button.

local PANEL_IN = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local PANEL_OUT = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local BACKDROP_FADE = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local BACKDROP_DIM = 0.45 -- backdrop transparency while a panel is open

local openPanels: { [GuiObject]: boolean } = {}
local panelTokens: { [GuiObject]: number } = {}
local backdrop: TextButton? = nil

local function panelScale(panel: GuiObject): UIScale
	return panel:FindFirstChildOfClass("UIScale")
		or UI.make(Instance.new("UIScale"), { Parent = panel })
end

local function getBackdrop(): TextButton
	local existing = backdrop
	if existing and existing.Parent then
		return existing
	end
	-- its own screen just under the panels (DisplayOrder 5+) and over the HUD
	local _, root = Layout.screen("Backdrop", 4)
	local button = UI.make(Instance.new("TextButton"), {
		Name = "Backdrop",
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(-0.5, -0.5),
		Size = UDim2.fromScale(2, 2), -- past the safe area to the screen edges
		Visible = false,
		Parent = root,
	})
	button.Activated:Connect(function()
		UI.closePanels()
	end)
	backdrop = button
	return button
end

local function updateBackdrop()
	local dim = getBackdrop()
	if next(openPanels) then
		dim.Visible = true
		TweenService:Create(dim, BACKDROP_FADE, { BackgroundTransparency = BACKDROP_DIM }):Play()
	else
		local fade = TweenService:Create(dim, BACKDROP_FADE, { BackgroundTransparency = 1 })
		fade.Completed:Once(function()
			if not next(openPanels) then
				dim.Visible = false
			end
		end)
		fade:Play()
	end
end

-- The first button in a panel, top to bottom then left to right, for the
-- gamepad selection.
local function firstButton(panel: GuiObject): GuiObject?
	local best: GuiObject? = nil
	for _, descendant in panel:GetDescendants() do
		if descendant:IsA("GuiButton") and descendant.Visible and descendant.Selectable then
			local p = descendant.AbsolutePosition
			if
				best == nil
				or p.Y < best.AbsolutePosition.Y - 2
				or (math.abs(p.Y - best.AbsolutePosition.Y) <= 2 and p.X < best.AbsolutePosition.X)
			then
				best = descendant
			end
		end
	end
	return best
end

-- Selects `target`'s first button when playing with a gamepad.
function UI.selectFirst(target: GuiObject)
	if Layout.class == "Console" then
		task.defer(function()
			if target.Visible then
				GuiService.SelectedObject = firstButton(target)
			end
		end)
	end
end

local function closePanel(panel: GuiObject)
	openPanels[panel] = nil
	local token = (panelTokens[panel] or 0) + 1
	panelTokens[panel] = token
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(panel) then
		GuiService.SelectedObject = nil
	end
	local shrink = TweenService:Create(panelScale(panel), PANEL_OUT, { Scale = 0.85 })
	shrink.Completed:Once(function()
		if panelTokens[panel] == token then
			panel.Visible = false
		end
	end)
	shrink:Play()
	updateBackdrop()
end

-- Opens a panel (closing any other). Does nothing if it's already open.
function UI.openPanel(panel: GuiObject)
	if openPanels[panel] then
		return
	end
	for other in table.clone(openPanels) do
		closePanel(other)
	end
	openPanels[panel] = true
	panelTokens[panel] = (panelTokens[panel] or 0) + 1
	local scale = panelScale(panel)
	scale.Scale = 0.8
	panel.Visible = true
	TweenService:Create(scale, PANEL_IN, { Scale = 1 }):Play()
	updateBackdrop()
	UI.selectFirst(panel)
end

-- Opens or closes a panel. Returns the new open state.
function UI.togglePanel(panel: GuiObject): boolean
	if openPanels[panel] then
		closePanel(panel)
		return false
	end
	UI.openPanel(panel)
	return true
end

-- Is any panel open? (Offers never show over one.)
function UI.anyPanelOpen(): boolean
	return next(openPanels) ~= nil
end

-- Closes the open panel (Esc, gamepad B, the backdrop). True if one was open.
function UI.closePanels(): boolean
	local closed = false
	for panel in table.clone(openPanels) do
		closePanel(panel)
		closed = true
	end
	return closed
end

function UI.anyPanelOpen(): boolean
	return next(openPanels) ~= nil
end

export type Window = { panel: Frame, body: Frame, close: TextButton }

-- A standard panel: a header in `color` with the title and a close button,
-- and a body frame under it to fill. Centred, hidden until opened. It's
-- `design` pixels, shrunk to fit smaller screens (LayoutMath.fit), so it
-- looks the same on every device.
function UI.window(
	parent: Instance,
	name: string,
	title: string,
	color: Color3,
	design: Vector2
): Window
	local panel = UI.panel({
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Visible = false,
		Parent = parent,
	})
	-- centred in the space under Roblox's top bar
	UI.onLayout(function()
		local top = Layout.topbar.height
		local size = LayoutMath.fit(design, Layout.area - Vector2.new(0, top))
		panel.Size = UDim2.fromOffset(size.X, size.Y)
		panel.Position = UDim2.new(0.5, 0, 0.5, top / 2)
	end)
	local header = UI.make(Instance.new("Frame"), {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 58),
		BackgroundColor3 = color,
		Parent = panel,
	})
	UI.corner(header, UDim.new(0, 14))
	UI.gradient(header, Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 185))
	local heading = UI.label({
		Title = true,
		Text = title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.new(0, 18, 0.15, 0),
		Size = UDim2.new(1, -90, 0.7, 0),
		Parent = header,
	})
	UI.maxText(heading, 34)
	local close = UI.button({
		Name = "Close",
		Text = "X",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(42, 42),
		BackgroundColor3 = UI.COLORS.red,
		Parent = header,
	})
	close.Activated:Connect(function()
		UI.togglePanel(panel)
	end)
	local body = UI.make(Instance.new("Frame"), {
		Name = "Body",
		Position = UDim2.new(0, 14, 0, 70),
		Size = UDim2.new(1, -28, 1, -82),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	return { panel = panel, body = body, close = close }
end

-- Puts `object` at a layout rectangle (design pixels, LayoutMath.Rect).
function UI.place(object: GuiObject, rect: LayoutMath.Rect)
	object.AnchorPoint = Vector2.zero
	object.Position = UDim2.fromOffset(rect.x, rect.y)
	object.Size = UDim2.fromOffset(rect.w, rect.h)
end

-- Runs `apply` now and again whenever the device, screen size or
-- orientation changes.
function UI.onLayout(apply: () -> ())
	apply()
	Layout.Changed:Connect(function()
		apply()
	end)
end

-- A small gamepad button chip in a button's corner ("Y"), shown only to
-- players on a gamepad (Layout class Console); nothing on PC or touch.
function UI.padHint(button: GuiObject, padButton: string)
	local hint = UI.label({
		Name = "PadHint",
		Text = padButton,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 6, 0, -6),
		Size = UDim2.fromOffset(24, 24),
		BackgroundColor3 = UI.COLORS.panelDark,
		BackgroundTransparency = 0,
		ZIndex = 5,
		Parent = button,
	})
	UI.corner(hint, UDim.new(0.5, 0))
	local function apply()
		hint.Visible = Layout.class == "Console"
	end
	apply()
	Layout.Changed:Connect(apply)
end

-- Toasts ---------------------------------------------------------------------------
-- Short messages in the middle of the top (where Layout.hud.toasts puts
-- them: under the bottle bar on touch screens). Each fades out
-- after its time; the same text again restarts its timer; at most two at
-- once (the oldest goes first). Bookkeeping: Lib/ToastQueue.

export type ToastKind = "info" | "warn" | "good" | "volt"
-- A toast can carry one action ("OPEN"): tapping anywhere on it does it.
export type ToastAction = { text: string, onTap: () -> () }

UI.TOAST_TIME = 3
UI.TOAST_HEIGHT = LayoutMath.HUD.toastHeight
UI.TOAST_GAP = 6
local TOAST_MAX = 2
local TOAST_COLORS: { [ToastKind]: Color3 } = {
	info = UI.COLORS.text,
	warn = UI.COLORS.red,
	good = UI.COLORS.green,
	volt = UI.COLORS.volt,
}

-- The bottle-full warning: when it fills, then at most every
-- FULL_REMINDER seconds while it stays full (HUD, StrikeFX).
UI.FULL_MESSAGE = "Bottle full! Sell at the Power Plant"
UI.FULL_REMINDER = 20

local toasts = ToastQueue.new(os.clock, TOAST_MAX)
local toastFrames: { [number]: CanvasGroup } = {}
local toastStack: Frame? = nil
local lastToastAt: { [string]: number } = {}

local function stack(): Frame
	local existing = toastStack
	if existing and existing.Parent then
		return existing
	end
	local _, gui = Layout.screen("Toasts", 7)
	local frame = UI.make(Instance.new("Frame"), {
		Name = "Stack",
		BackgroundTransparency = 1,
		Parent = gui,
	})
	UI.onLayout(function()
		UI.place(frame, Layout.hud.toasts)
	end)
	UI.make(Instance.new("UIListLayout"), {
		Padding = UDim.new(0, UI.TOAST_GAP),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = frame,
	})
	toastStack = frame
	return frame
end

local function removeToast(id: number)
	local frame = toastFrames[id]
	if not frame then
		return
	end
	toastFrames[id] = nil
	local fade = TweenService:Create(frame, UI.TWEEN.fast, { GroupTransparency = 1 })
	fade.Completed:Once(function()
		frame:Destroy()
	end)
	fade:Play()
end

local function buildToast(entry: ToastQueue.Entry, action: ToastAction?): CanvasGroup
	local group = UI.make(Instance.new("CanvasGroup"), {
		Name = "Toast",
		Size = UDim2.new(1, 0, 0, UI.TOAST_HEIGHT),
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		LayoutOrder = entry.id,
		Parent = stack(),
	})
	local panel = UI.panel({ Size = UDim2.fromScale(1, 1), Parent = group })
	local label = UI.label({
		Name = "Text",
		Text = entry.text,
		TextColor3 = TOAST_COLORS[entry.kind :: ToastKind] or UI.COLORS.text,
		Position = UDim2.fromScale(0.04, 0.14),
		Size = UDim2.fromScale(0.92, 0.72),
		Parent = panel,
	})
	UI.maxText(label, 22)
	if action then
		-- the whole toast is the button (it's bigger than a button that fits
		-- in it); the action's name sits on the right
		label.Size = UDim2.fromScale(0.68, 0.72)
		local hint = UI.label({
			Title = true,
			Name = "Action",
			Text = `{action.text} ›`,
			TextColor3 = UI.COLORS.volt,
			TextXAlignment = Enum.TextXAlignment.Right,
			Position = UDim2.fromScale(0.72, 0.14),
			Size = UDim2.fromScale(0.25, 0.72),
			Parent = panel,
		})
		UI.maxText(hint, 22)
		local tap = UI.make(Instance.new("TextButton"), {
			Name = "Tap",
			Text = "",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 5,
			Parent = group,
		})
		tap.Activated:Connect(function()
			ToastQueue.dismiss(toasts, entry.id)
			removeToast(entry.id)
			action.onTap()
		end)
	end
	TweenService:Create(group, UI.TWEEN.fast, { GroupTransparency = 0 }):Play()
	return group
end

-- Shows a message for `seconds` (UI.TOAST_TIME by default), with an
-- optional action (tap the toast to do it).
function UI.toast(text: string, kind: ToastKind?, seconds: number?, action: ToastAction?)
	local duration = seconds or UI.TOAST_TIME
	local entry, evicted = ToastQueue.push(toasts, text, kind or "info", duration)
	for _, old in evicted do
		removeToast(old.id)
	end
	local frame = toastFrames[entry.id]
	if frame then
		local label = frame:FindFirstChild("Text", true)
		if label and label:IsA("TextLabel") then
			label.TextColor3 = TOAST_COLORS[entry.kind :: ToastKind] or UI.COLORS.text
		end
		UI.pop(frame, 1.06)
	else
		toastFrames[entry.id] = buildToast(entry, action)
	end
	local id, generation = entry.id, entry.generation
	task.delay(duration, function()
		if ToastQueue.hide(toasts, id, generation) then
			removeToast(id)
		end
	end)
end

-- A toast that shows at most once every `cooldown` seconds for `key`, for
-- reminders that would otherwise repeat (bottle full). `force` shows it
-- now anyway and restarts the cooldown (the moment the bottle fills).
function UI.toastEvery(
	key: string,
	cooldown: number,
	text: string,
	kind: ToastKind?,
	force: boolean?
)
	local now = os.clock()
	local last = lastToastAt[key]
	if force or last == nil or now - last >= cooldown then
		lastToastAt[key] = now
		UI.toast(text, kind)
	end
end

return UI
