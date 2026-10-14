--!strict
-- Small helpers for building UI in code, plus the shared look (colours,
-- font, animation timings) so every screen feels like the same game.

local TweenService = game:GetService("TweenService")

local UI = {}

UI.COLORS = table.freeze({
	panel = Color3.fromRGB(26, 30, 48),
	panelDark = Color3.fromRGB(16, 19, 32),
	stroke = Color3.fromRGB(8, 10, 18),
	text = Color3.fromRGB(255, 255, 255),
	subtext = Color3.fromRGB(185, 192, 220),
	volt = Color3.fromRGB(255, 214, 60),
	storm = Color3.fromRGB(120, 170, 255),
	calm = Color3.fromRGB(130, 220, 150),
	green = Color3.fromRGB(70, 200, 100),
	red = Color3.fromRGB(225, 70, 70),
	disabled = Color3.fromRGB(85, 90, 108),
})

UI.FONT = Enum.Font.FredokaOne

UI.TWEEN = table.freeze({
	popOut = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	popBack = TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	open = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	fast = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	countUp = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
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
		CornerRadius = radius or UDim.new(0.2, 0),
		Parent = parent,
	})
end

function UI.stroke(parent: Instance, thickness: number?)
	UI.make(Instance.new("UIStroke"), {
		Color = UI.COLORS.stroke,
		Thickness = thickness or 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function UI.maxText(parent: Instance, size: number)
	UI.make(Instance.new("UITextSizeConstraint"), { MaxTextSize = size, Parent = parent })
end

function UI.sizeLimits(parent: Instance, min: Vector2, max: Vector2)
	UI.make(Instance.new("UISizeConstraint"), { MinSize = min, MaxSize = max, Parent = parent })
end

local function textStroke(parent: Instance)
	UI.make(Instance.new("UIStroke"), {
		Color = UI.COLORS.stroke,
		Thickness = 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
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

function UI.label(props: { [string]: any }): TextLabel
	local label = UI.make(
		Instance.new("TextLabel"),
		withDefaults({
			BackgroundTransparency = 1,
			Font = UI.FONT,
			TextColor3 = UI.COLORS.text,
			TextScaled = true,
		}, props)
	)
	textStroke(label)
	return label
end

function UI.button(props: { [string]: any }): TextButton
	local button = UI.make(
		Instance.new("TextButton"),
		withDefaults({
			AutoButtonColor = true,
			Font = UI.FONT,
			TextColor3 = UI.COLORS.text,
			TextScaled = true,
		}, props)
	)
	UI.corner(button)
	UI.stroke(button)
	textStroke(button)
	UI.make(Instance.new("UIPadding"), {
		PaddingTop = UDim.new(0.14, 0),
		PaddingBottom = UDim.new(0.14, 0),
		PaddingLeft = UDim.new(0.06, 0),
		PaddingRight = UDim.new(0.06, 0),
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

return UI
