--!strict
-- Helpers for building UI in code, plus the shared look (colours, fonts,
-- animation timings) so every screen feels like the same game.

local TweenService = game:GetService("TweenService")

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

function UI.maxText(parent: Instance, size: number)
	UI.make(Instance.new("UITextSizeConstraint"), { MaxTextSize = size, Parent = parent })
end

function UI.sizeLimits(parent: Instance, min: Vector2, max: Vector2)
	UI.make(Instance.new("UISizeConstraint"), { MinSize = min, MaxSize = max, Parent = parent })
end

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

-- Opens or closes a panel with a bouncy scale. Returns the new open state.
function UI.togglePanel(panel: GuiObject): boolean
	local scale = panel:FindFirstChildOfClass("UIScale")
		or UI.make(Instance.new("UIScale"), { Parent = panel })
	if panel.Visible then
		panel.Visible = false
		return false
	end
	panel.Visible = true
	scale.Scale = 0.6
	TweenService:Create(scale, UI.TWEEN.open, { Scale = 1 }):Play()
	return true
end

return UI
