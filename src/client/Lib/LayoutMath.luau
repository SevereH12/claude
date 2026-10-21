--!strict
-- The pure maths behind Lib/Layout: what kind of device this is, how big
-- the UI is, and where every HUD piece goes. No Roblox services, so the
-- harness tests it (tools/harness/test_layout.luau) for every device.
--
-- Every screen is laid out in DESIGN PIXELS and the whole UI is scaled by
-- one UIScale: scale = the screen's short side / the class's design short
-- side. So a button is the same share of the screen on a phone, an iPad, a
-- 1080p or 4K monitor and a TV; nothing stretches differently on wide and
-- tall screens. Phones use a smaller design short side, so things are a
-- bit bigger there (held close, tapped with thumbs), and a TV a smaller one
-- for viewing distance. On touch every button stays at least TAP_MIN
-- points (tapMin) and phone text at least PHONE_MIN_TEXT points.
--
-- The HUD sits on the screen's edges: Volts and the storm timer top left,
-- the next goal top right, the bottle bar bottom centre (top centre on
-- touch, clear of the thumbstick and jump button; under the top row on a
-- phone held upright), MENU on the left edge. Toasts and the zone banner
-- go in the middle of the top, under whatever sits there.

export type DeviceClass = "Phone" | "Tablet" | "Desktop" | "Console"

-- What input the player has. `preferred` is UserInputService.PreferredInput
-- where Roblox has it ("Touch", "Gamepad" or "KeyboardAndMouse").
export type Input = {
	touch: boolean,
	keyboard: boolean,
	gamepad: boolean,
	preferred: string?,
}

-- A rectangle in design pixels, from the top left of the safe area.
export type Rect = { x: number, y: number, w: number, h: number }

export type Hud = {
	volts: Rect,
	storm: Rect,
	goal: Rect,
	bar: Rect,
	menu: Rect,
	card: Rect, -- the menu's tile card, beside the menu button
	toasts: Rect,
	banner: Rect,
	test: Rect, -- the owner's TEST buttons (two rows), under the menu
}

local LayoutMath = {}

LayoutMath.PHONE_SHORT_SIDE = 500 -- points: a short side under this is a phone
LayoutMath.TV_SAFE = 0.05 -- console: keep everything this far in from each edge
LayoutMath.PHONE_MIN_TEXT = 14 -- points
LayoutMath.TAP_MIN = 44 -- points

-- Design short side per class: the screen's short side is this many design
-- pixels.
LayoutMath.DESIGN_SHORT = {
	Phone = 520,
	Tablet = 720,
	Desktop = 720,
	Console = 640,
} :: { [DeviceClass]: number }

-- HUD sizes in design pixels.
LayoutMath.MARGIN = 12
LayoutMath.GAP = 8
LayoutMath.HUD = table.freeze({
	statWidth = 216,
	voltsHeight = 60,
	stormHeight = 40,
	goalWidth = 270,
	goalHeight = 84,
	barWidth = 420,
	barHeight = 52,
	menuSize = 84,
	cardWidth = 270, -- two tiles of 118 + gap 10 + padding 12 each side
	cardHeight = 214, -- two rows of 90 + gap 10 + padding 12 each side
	toastWidth = 380,
	toastHeight = 44,
	toastRows = 2,
	bannerWidth = 560,
	bannerHeight = 100,
	testWidth = 150,
	testHeight = 50,
})

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
	return math.clamp(short / LayoutMath.DESIGN_SHORT[class], 0.4, 4)
end

function LayoutMath.isTouch(class: DeviceClass): boolean
	return class == "Phone" or class == "Tablet"
end

-- Smallest text size for TextScaled labels, in design pixels, so it's
-- PHONE_MIN_TEXT real points on a phone.
function LayoutMath.minTextSize(class: DeviceClass, scale: number): number
	return if class == "Phone" then math.ceil(LayoutMath.PHONE_MIN_TEXT / scale) else 1
end

-- Smallest size for a button whose own minimum is `base` (design pixels):
-- on a touch screen at least TAP_MIN real points each way.
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

-- A panel's size: its design size, shrunk to fit `area` with a margin.
function LayoutMath.fit(design: Vector2, area: Vector2): Vector2
	local edge = 2 * 16
	return Vector2.new(math.min(design.X, area.X - edge), math.min(design.Y, area.Y - edge))
end

local function rect(x: number, y: number, w: number, h: number): Rect
	return { x = x, y = y, w = w, h = h }
end

-- Where every HUD piece goes on a safe area of `area` design pixels.
function LayoutMath.hud(class: DeviceClass, area: Vector2): Hud
	local H = LayoutMath.HUD
	local M, G = LayoutMath.MARGIN, LayoutMath.GAP
	local W, T = area.X, area.Y
	local touch = LayoutMath.isTouch(class)
	local portrait = T > W

	-- top left: Volts, the storm timer under it; top right: the next goal
	local volts = rect(M, M, H.statWidth, H.voltsHeight)
	local storm = rect(M, M + H.voltsHeight + G, H.statWidth, H.stormHeight)
	local goal = rect(W - M - H.goalWidth, M, H.goalWidth, H.goalHeight)
	local topRow = math.max(H.voltsHeight + G + H.stormHeight, H.goalHeight)

	-- the bottle bar
	local bar
	if not touch then
		bar = rect((W - H.barWidth) / 2, T - M - H.barHeight, H.barWidth, H.barHeight)
	elseif portrait then
		local width = math.min(H.barWidth, W - 2 * M)
		bar = rect((W - width) / 2, M + topRow + G, width, H.barHeight)
	else
		-- between the two top corners
		local left, right = volts.x + volts.w + 2 * G, goal.x - 2 * G
		local width = math.min(H.barWidth, right - left)
		bar = rect((left + right - width) / 2, M, width, H.barHeight)
	end

	-- toasts, then the zone banner, in the middle of the top
	local centerTop = if touch then bar.y + bar.h + G else M
	local toastWidth = math.min(H.toastWidth, W - 2 * M)
	local toasts =
		rect((W - toastWidth) / 2, centerTop, toastWidth, H.toastRows * (H.toastHeight + 6))
	local bannerWidth = math.min(H.bannerWidth, W - 2 * M)
	local banner = rect((W - bannerWidth) / 2, toasts.y + toasts.h + G, bannerWidth, H.bannerHeight)

	-- MENU on the left edge: the middle on a PC or console; higher on touch,
	-- clear of the thumbstick; always below the top-left stats
	local below = M + topRow + 2 * G + (if touch and portrait then H.barHeight + G else 0)
	-- where the toasts and banner reach the left edge (narrow screens held
	-- upright), MENU goes below them too
	if banner.x < M + H.menuSize + G or toasts.x < M + H.menuSize + G then
		below = math.max(below, banner.y + banner.h + 2 * G)
	end
	local menuY = if touch then T * 0.36 - H.menuSize / 2 else T / 2 - H.menuSize / 2
	local menu = rect(M, math.max(below, menuY), H.menuSize, H.menuSize)
	-- the card opens beside the button, never above the top-left stats
	local cardTop = M + topRow + G
	local cardY = math.clamp(
		menu.y + (menu.h - H.cardHeight) / 2,
		cardTop,
		math.max(cardTop, T - M - H.cardHeight)
	)
	local card = rect(menu.x + menu.w + 10, cardY, H.cardWidth, H.cardHeight)
	local test = rect(M, menu.y + menu.h + G, H.testWidth, 2 * H.testHeight + G)

	return {
		volts = volts,
		storm = storm,
		goal = goal,
		bar = bar,
		menu = menu,
		card = card,
		toasts = toasts,
		banner = banner,
		test = test,
	}
end

-- Where the thumbstick and jump button sit on a touch screen (design
-- pixels, roughly): HUD pieces that stay on screen keep out of these.
function LayoutMath.thumbZones(area: Vector2): { Rect }
	local W, T = area.X, area.Y
	return {
		rect(0, T * 0.6, W * 0.4, T * 0.4), -- thumbstick: bottom left
		rect(W * 0.72, T * 0.62, W * 0.28, T * 0.38), -- jump: bottom right
	}
end

function LayoutMath.overlaps(a: Rect, b: Rect): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

function LayoutMath.inside(a: Rect, area: Vector2): boolean
	return a.x >= 0 and a.y >= 0 and a.x + a.w <= area.X + 1e-6 and a.y + a.h <= area.Y + 1e-6
end

return LayoutMath
