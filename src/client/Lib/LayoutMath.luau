--!strict
-- The pure maths behind Lib/Layout: which kind of device this is and how
-- big the UI should be. No Roblox services, so the harness can test it
-- (tools/harness/test_layout.luau).
--
-- Sizes are designed at 1080p on a desktop (UIScale 1). Phones shrink the
-- UI (their screens are measured in points: an iPhone is about 844 x 390),
-- tablets keep 1, bigger screens grow it, and a console grows it a bit more
-- for TV viewing distance. On touch screens every button is still kept at
-- least TAP_MIN points (tapMin) and text at least PHONE_MIN_TEXT points
-- (minTextSize), whatever the scale.

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
LayoutMath.PHONE_MIN_TEXT = 14 -- points
LayoutMath.TAP_MIN = 44 -- points

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
	elseif class == "Phone" then
		return math.clamp(short / 480, 0.75, 1)
	end
	return 1
end

-- Smallest text size for TextScaled labels, in UI units (before UIScale),
-- so it's PHONE_MIN_TEXT real points on a phone.
function LayoutMath.minTextSize(class: DeviceClass, scale: number): number
	return if class == "Phone" then math.ceil(LayoutMath.PHONE_MIN_TEXT / scale) else 1
end

-- Smallest size for a button whose own minimum is `base` (UI units): on a
-- touch screen at least TAP_MIN real points each way.
function LayoutMath.tapMin(class: DeviceClass, scale: number, base: Vector2): Vector2
	if not LayoutMath.isTouch(class) then
		return base
	end
	local need = LayoutMath.TAP_MIN / scale
	return Vector2.new(math.max(base.X, need), math.max(base.Y, need))
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
