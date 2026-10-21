--!strict
-- The pure maths behind Lib/Layout: which kind of device this is and how
-- big the UI should be. No Roblox services, so the harness can test it
-- (tools/harness/test_layout.luau).
--
-- Sizes are designed at 1080p on a desktop (UIScale 1). Phones and tablets
-- keep 1: their screens are measured in points (an iPhone is about
-- 844 x 390), and the UI's scale-based sizes with pixel minimums already fit
-- them while keeping every button at least 44 points. Bigger screens grow
-- the UI, and a console grows it a bit more for TV viewing distance.

export type DeviceClass = "Phone" | "Tablet" | "Desktop" | "Console"

-- What input the player has. `preferred` is UserInputService.PreferredInput
-- where Roblox has it ("Touch", "Gamepad" or "KeyboardAndMouse").
export type Input = {
	touch: boolean,
	keyboard: boolean,
	gamepad: boolean,
	preferred: string?,
}

local LayoutMath = {}

LayoutMath.PHONE_SHORT_SIDE = 500 -- points: a short side under this is a phone
LayoutMath.TV_SAFE = 0.05 -- console: keep everything this far in from each edge
LayoutMath.PHONE_MIN_TEXT = 14

function LayoutMath.classify(viewport: Vector2, input: Input): DeviceClass
	local short = math.min(viewport.X, viewport.Y)
	local preferred = input.preferred
	local gamepadFirst = if preferred
		then preferred == "Gamepad"
		else input.gamepad and not input.keyboard and not input.touch
	if gamepadFirst then
		return "Console"
	end
	local touchFirst = if preferred
		then preferred == "Touch"
		else input.touch and not input.keyboard
	if touchFirst then
		return if short < LayoutMath.PHONE_SHORT_SIDE then "Phone" else "Tablet"
	end
	return "Desktop"
end

-- The UIScale every ScreenGui gets.
function LayoutMath.scale(class: DeviceClass, viewport: Vector2): number
	local short = math.min(viewport.X, viewport.Y)
	if class == "Desktop" then
		return math.clamp(short / 1080, 1, 2)
	elseif class == "Console" then
		return math.clamp(short / 1080 * 1.15, 1.15, 2.3)
	end
	return 1
end

-- Smallest text size for TextScaled labels.
function LayoutMath.minTextSize(class: DeviceClass): number
	return if class == "Phone" then LayoutMath.PHONE_MIN_TEXT else 1
end

-- Fraction of the screen kept clear on every edge (TV-safe area).
function LayoutMath.edgePadding(class: DeviceClass): number
	return if class == "Console" then LayoutMath.TV_SAFE else 0
end

function LayoutMath.isPortrait(viewport: Vector2): boolean
	return viewport.Y > viewport.X
end

function LayoutMath.isTouch(class: DeviceClass): boolean
	return class == "Phone" or class == "Tablet"
end

return LayoutMath
