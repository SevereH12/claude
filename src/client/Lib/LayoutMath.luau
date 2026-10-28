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
-- The HUD sits on the screen's edges: Volts, the storm timer and the
-- running boosts' chips top left,
-- the next goal top right (a Server Storm's chip, an event's chip, the
-- slim server goal meter under it), the friends chip under the boosts, the bottle bar bottom centre (top centre on
-- touch, clear of the thumbstick and jump button; on a phone held upright
-- under the top row, beside MENU), MENU on the left edge. Toasts and the zone banner
-- go in the middle of the top, under whatever sits there. Pieces use the
-- free middle of Roblox's top row and only drop below it where its own
-- buttons are, so the top of the screen isn't wasted.

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

-- Roblox's top row, in design pixels: its buttons take the left of `left`
-- and the right of `right`, `height` tall; the middle is free.
export type Topbar = { left: number, right: number, height: number }

export type Hud = {
	volts: Rect,
	storm: Rect,
	boosts: Rect, -- timed boost chips: a row under the storm timer (a column beside Volts on a sideways phone or tablet)
	goal: Rect,
	serverStorm: Rect, -- a Server Storm's chip (buyer and time left), under the goal
	event: Rect, -- a scheduled event's chip (name and time left), under that
	serverGoal: Rect, -- the server goal meter (tap: top contributors), under the event's chip
	friends: Rect, -- the friends boost's chip ("👥 +10% friends"), under the boosts' chips
	bar: Rect,
	menu: Rect,
	card: Rect, -- the menu's tile card, beside the menu button (offers use it too)
	toasts: Rect,
	banner: Rect,
	tutorial: Rect, -- the tutorial's step card, in the middle of the top (the toasts go under it while it shows)
	test: Rect, -- the ADMIN button's spot (two rows), under the menu
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
	boostHeight = 28, -- one boost chip
	boostWidth = 78, -- one chip in the sideways column (at least; wider when its text needs it)
	boostCount = 3, -- boost chips (Config.BOOSTS)
	serverGoalHeight = 24, -- the slim server goal meter
	cardWidth = 398, -- three tiles of 118 + gaps of 10 + padding 12 each side
	cardHeight = 214, -- two rows of 90 + gap 10 + padding 12 each side
	toastWidth = 380,
	toastHeight = 44,
	toastRows = 2,
	bannerWidth = 560,
	bannerHeight = 100,
	tutorialWidth = 440,
	tutorialHeight = 64,
	testWidth = 150,
	testHeight = 50,
})

-- From what the device has, not what was used last: the preferred input
-- only matters for a gamepad (a PC played with one gets the console
-- layout). A click in Studio's phone emulator changes the preferred input
-- to mouse; that must not turn a phone into a PC.
function LayoutMath.classify(viewport: Vector2, input: Input): DeviceClass
	local short = math.min(viewport.X, viewport.Y)
	if
		input.preferred == "Gamepad" or (input.gamepad and not input.keyboard and not input.touch)
	then
		return "Console"
	end
	if input.touch and (not input.keyboard or short < LayoutMath.PHONE_SHORT_SIDE) then
		return if short < LayoutMath.PHONE_SHORT_SIDE then "Phone" else "Tablet"
	end
	return "Desktop"
end

-- SETTINGS > Accessibility & HUD > Text size: 0 Normal, 1 Large, 2 Extra
-- large. Each step nudges the UI scale up (TEXT_BOOST) and raises the
-- smallest text (TEXT_MIN_POINTS).
LayoutMath.TEXT_LEVELS = { Normal = 0, Large = 1, ["Extra large"] = 2 } :: { [string]: number }
LayoutMath.TEXT_BOOST = { [0] = 1, [1] = 1.1, [2] = 1.2 } :: { [number]: number }
LayoutMath.TEXT_MIN_POINTS = { [1] = 16, [2] = 18 } :: { [number]: number }
-- the bigger layout never shrinks the design area below this share of the
-- device's design size (the HUD is laid out for that). Phones have no room
-- to spare: there Text size only raises the smallest text.
LayoutMath.MIN_DESIGN_SHARE = {
	Phone = 1,
	Tablet = 0.82,
	Desktop = 0.82,
	Console = 0.82,
} :: { [DeviceClass]: number }

-- The UIScale every ScreenGui gets (`textLevel`: the Text size setting).
function LayoutMath.scale(class: DeviceClass, viewport: Vector2, textLevel: number?): number
	local short = math.min(viewport.X, viewport.Y)
	local base = short / LayoutMath.DESIGN_SHORT[class]
	local boosted = math.min(
		base * (LayoutMath.TEXT_BOOST[textLevel or 0] or 1),
		short / (LayoutMath.DESIGN_SHORT[class] * LayoutMath.MIN_DESIGN_SHARE[class])
	)
	return math.clamp(math.max(base, boosted), 0.4, 4)
end

function LayoutMath.isTouch(class: DeviceClass): boolean
	return class == "Phone" or class == "Tablet"
end

-- Smallest text size for TextScaled labels, in design pixels, so it's
-- PHONE_MIN_TEXT real points on a phone, and with a bigger Text size
-- setting TEXT_MIN_POINTS everywhere.
function LayoutMath.minTextSize(class: DeviceClass, scale: number, textLevel: number?): number
	local points = LayoutMath.TEXT_MIN_POINTS[textLevel or 0]
	if points then
		return math.ceil(
			math.max(points, if class == "Phone" then LayoutMath.PHONE_MIN_TEXT else 0) / scale
		)
	end
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

-- Chips (the boosts' "⚡ 14:32", the Server Storm's, an event's, the friends
-- chip, the Server Surge text) ------------------------------------------------
-- Their text is the title font (Luckiest Guy), scaled to fit. Roblox can
-- shrink it only down to the smallest text size (minTextSize: bigger on a
-- phone and with a bigger Text size setting); a chip too narrow for its
-- text at that size cuts the text off. So chips are sized here for their
-- text at CHIP_TEXT (or the smallest text size, if that's bigger), and the
-- HUD picks the longest wording that fits (LayoutMath.fitText).
LayoutMath.CHIP_TEXT = 14 -- design pixels: chips are at least this big for their text
LayoutMath.CHIP_PAD = 8 -- design pixels left clear each side of a chip's text (its rounded ends)
LayoutMath.BOOST_SAMPLE = "⚡ 1:05:00" -- the widest a boost chip's text gets

-- The text size chips are sized for on this device and Text size setting.
function LayoutMath.chipText(class: DeviceClass, scale: number, textLevel: number?): number
	return math.max(LayoutMath.CHIP_TEXT, LayoutMath.minTextSize(class, scale, textLevel))
end

-- A chip's height for text of `size`.
function LayoutMath.chipHeight(size: number): number
	return math.max(LayoutMath.HUD.boostHeight, size + 10)
end

-- How wide `text` is in the title font at `size` (design pixels). An
-- estimate on the safe side (measured from Luckiest Guy, every glyph rounded
-- up): it's never narrower than the real text.
local NARROW = {
	[" "] = true,
	[":"] = true,
	["."] = true,
	[","] = true,
	["'"] = true,
	["!"] = true,
	["|"] = true,
}
local WIDE = { m = true, w = true, M = true, W = true, ["%"] = true, ["@"] = true }
function LayoutMath.textWidth(text: string, size: number): number
	local ems = 0
	for _, code in utf8.codes(text) do
		local char = utf8.char(code)
		if code == 0xFE0F or code == 0x200D then
			continue -- emoji style marks and joiners take no room
		elseif code == 0xB7 or NARROW[char] then
			ems += 0.3
		elseif code > 0x7F then
			ems += 1.3 -- an emoji or another symbol
		elseif WIDE[char] then
			ems += 0.95
		else
			ems += 0.71
		end
	end
	return ems * size
end

-- The width a chip needs to show `text` at `size`, its padding included.
function LayoutMath.chipWidth(text: string, size: number): number
	return math.ceil(LayoutMath.textWidth(text, size) + 2 * LayoutMath.CHIP_PAD)
end

-- The first of `options` (longest wording first) that fits a chip `width`
-- wide at text `size`; the last (shortest) if none does.
function LayoutMath.fitText(options: { string }, width: number, size: number): string
	for _, text in options do
		if LayoutMath.chipWidth(text, size) <= width then
			return text
		end
	end
	return options[#options]
end

local function rect(x: number, y: number, w: number, h: number): Rect
	return { x = x, y = y, w = w, h = h }
end

-- The parts of the top row Roblox's own buttons take (left of
-- topbar.left, right of topbar.right), as rectangles.
function LayoutMath.topbarBlocks(area: Vector2, topbar: Topbar): { Rect }
	if topbar.height <= 0 then
		return {}
	end
	return {
		rect(0, 0, topbar.left, topbar.height),
		rect(topbar.right, 0, area.X - topbar.right, topbar.height),
	}
end

-- Where every HUD piece goes on a safe area of `area` design pixels.
-- `topbar`: Roblox's top row (design pixels); pieces use its free middle
-- and only drop below it where its buttons are.
-- `tutorial`: the tutorial's step card is showing (Controllers/Tutorial):
-- it takes the toasts' place and they move down under it; the zone banner
-- covers the card while it shows.
-- `chipText`: the text size chips are sized for (LayoutMath.chipText).
function LayoutMath.hud(
	class: DeviceClass,
	area: Vector2,
	topbar: Topbar?,
	tutorial: boolean?,
	chipText: number?
): Hud
	local H = LayoutMath.HUD
	local M, G = LayoutMath.MARGIN, LayoutMath.GAP
	local W, T = area.X, area.Y
	local bar0: Topbar = topbar or { left = 0, right = W, height = 0 }
	local touch = LayoutMath.isTouch(class)
	local upright = touch and T > W

	-- the top edge for something spanning x .. x + w: the very top in the
	-- top bar's free middle, under the bar where its buttons are
	local function topFor(x: number, w: number): number
		if bar0.height > 0 and (x < bar0.left + G or x + w > bar0.right - G) then
			return bar0.height + M
		end
		return M
	end

	-- top left: Volts, the storm timer under it and the running boosts'
	-- chips; top right: the next goal. The chips are a row under the storm
	-- timer, but a phone or tablet held sideways is short of height (MENU
	-- must stay above the thumbstick), so there they're a column beside
	-- Volts, below a bottle bar along the top.
	-- every chip is tall enough for its text, and a boost chip wide enough
	-- for "⚡ 1:05:00" (BOOST_SAMPLE)
	local textSize = chipText or LayoutMath.CHIP_TEXT
	local chipH = LayoutMath.chipHeight(textSize)
	local boostW = LayoutMath.chipWidth(LayoutMath.BOOST_SAMPLE, textSize)
	local count = H.boostCount
	local volts = rect(M, topFor(M, H.statWidth), H.statWidth, H.voltsHeight)
	local storm = rect(M, volts.y + volts.h + G, H.statWidth, H.stormHeight)
	local goalX = W - M - H.goalWidth
	local sideways = touch and not upright
	local column = count * chipH + (count - 1) * G
	local boosts
	if sideways then
		boosts = rect(
			volts.x + volts.w + G,
			math.max(volts.y, M + H.barHeight + G),
			math.max(H.boostWidth, boostW),
			column
		)
	else
		-- a row under the storm timer (at least as wide as it) if that stays
		-- well clear of the goal column, else a column
		local chipW = math.max(boostW, (H.statWidth - (count - 1) * G) / count)
		local rowW = count * chipW + (count - 1) * G
		boosts = if M + rowW <= goalX - 2 * G
			then rect(M, storm.y + storm.h + G, rowW, chipH)
			else rect(M, storm.y + storm.h + G, boostW, column)
	end
	local goal = rect(goalX, topFor(goalX, H.goalWidth), H.goalWidth, H.goalHeight)
	local serverStorm = rect(goalX, goal.y + goal.h + G, H.goalWidth, chipH)
	-- the friends chip: under the boosts' chips (on a sideways phone or
	-- tablet that's under their column beside Volts, as wide as it)
	local friends = if sideways
		then rect(boosts.x, boosts.y + boosts.h + G, boosts.w, chipH)
		else rect(M, boosts.y + boosts.h + G, H.statWidth, chipH)
	local leftBottom = math.max(storm.y + storm.h, friends.y + friends.h)
	local leftRight = math.max(volts.x + volts.w, boosts.x + boosts.w, friends.x + friends.w)
	-- how far down the left-edge pieces reach (MENU goes under them; the
	-- sideways boosts column is beside Volts, not over MENU)
	local edgeBottom = storm.y + storm.h
	for _, piece in { boosts, friends } do
		if piece.x < M + H.menuSize + G then
			edgeBottom = math.max(edgeBottom, piece.y + piece.h)
		end
	end
	local event = rect(goalX, serverStorm.y + serverStorm.h + G, H.goalWidth, chipH)
	local serverGoal = rect(
		goalX,
		event.y + event.h + G / 2,
		H.goalWidth,
		math.max(H.serverGoalHeight, textSize + 6)
	)
	local rightBottom = serverGoal.y + serverGoal.h

	-- the bottle bar, and on a phone or tablet held upright MENU beside it
	local bar
	local menu: Rect? = nil
	if not touch then
		bar = rect((W - H.barWidth) / 2, T - M - H.barHeight, H.barWidth, H.barHeight)
	elseif upright then
		local rowY = math.max(leftBottom, rightBottom) + G
		menu = rect(M, rowY, H.menuSize, H.menuSize)
		local x = M + H.menuSize + G
		local width = math.min(H.barWidth, W - x - M)
		bar = rect(x, rowY + (H.menuSize - H.barHeight) / 2, width, H.barHeight)
	else
		-- between the two top corners
		local left, right = volts.x + volts.w + 2 * G, goal.x - 2 * G
		local width = math.min(H.barWidth, right - left)
		local x = (left + right - width) / 2
		bar = rect(x, topFor(x, width), width, H.barHeight)
	end

	-- toasts, then the zone banner, in the middle of the top; each drops
	-- below a corner piece it would reach sideways
	local function belowCorners(x: number, w: number, y: number): number
		if x < leftRight + G then
			y = math.max(y, leftBottom + G)
		end
		if x + w > goal.x - G then
			y = math.max(y, rightBottom + G)
		end
		return y
	end
	-- centred, or moved right past the top-left pieces when that keeps it
	-- clear of both corners (so it needn't drop below them; it may narrow
	-- by up to a tenth to fit there): its x and width
	local function middle(w: number): (number, number)
		local x = (W - w) / 2
		local left = leftRight + G
		local room = goal.x - G - left
		if x < left and room >= 0.9 * w then
			return left, math.min(w, room)
		end
		return x, w
	end
	local toastX, toastWidth = middle(math.min(H.toastWidth, W - 2 * M))
	local centerTop = if upright and menu
		then menu.y + menu.h + G
		elseif touch then bar.y + bar.h + G
		else topFor(toastX, toastWidth)
	-- the tutorial's step card first (while it shows, the toasts go under it)
	local tutorialX, tutorialWidth = middle(math.min(H.tutorialWidth, W - 2 * M))
	local tutorialRect = rect(
		tutorialX,
		belowCorners(tutorialX, tutorialWidth, centerTop),
		tutorialWidth,
		H.tutorialHeight
	)
	if tutorial then
		centerTop = tutorialRect.y + tutorialRect.h + G
	end
	local toastHeight = H.toastRows * (H.toastHeight + 6)
	local toasts =
		rect(toastX, belowCorners(toastX, toastWidth, centerTop), toastWidth, toastHeight)
	local bannerWidth = math.min(H.bannerWidth, W - 2 * M)
	local bannerX = (W - bannerWidth) / 2
	-- while the tutorial shows, the (brief) banner covers its card instead
	local banner = rect(
		bannerX,
		belowCorners(
			bannerX,
			bannerWidth,
			if tutorial then tutorialRect.y else toasts.y + toasts.h + G
		),
		bannerWidth,
		H.bannerHeight
	)

	-- MENU on the left edge (unless it's already beside the bar): the middle
	-- on a PC or console, higher on touch (clear of the thumbstick), always
	-- below the top-left stats and below the middle column where that
	-- reaches the left edge
	local card
	if menu then
		-- upright: the card opens under the button
		card = rect(M, menu.y + menu.h + G, H.cardWidth, H.cardHeight)
	else
		local below = edgeBottom + 2 * G
		if banner.x < M + H.menuSize + G or toasts.x < M + H.menuSize + G then
			below = math.max(below, banner.y + banner.h + 2 * G)
		end
		local menuY = if touch then T * 0.36 - H.menuSize / 2 else T / 2 - H.menuSize / 2
		menu = rect(M, math.max(below, menuY), H.menuSize, H.menuSize)
		-- the card opens beside the button, never above the top-left stats
		local placed = menu :: Rect
		local cardTop = leftBottom + G
		local cardY = math.clamp(
			placed.y + (placed.h - H.cardHeight) / 2,
			cardTop,
			math.max(cardTop, T - M - H.cardHeight)
		)
		card = rect(placed.x + placed.w + 10, cardY, H.cardWidth, H.cardHeight)
	end
	local button = menu :: Rect
	local test = rect(M, button.y + button.h + G, H.testWidth, 2 * H.testHeight + G)

	return {
		volts = volts,
		storm = storm,
		boosts = boosts,
		goal = goal,
		serverStorm = serverStorm,
		event = event,
		serverGoal = serverGoal,
		friends = friends,
		bar = bar,
		menu = button,
		card = card,
		toasts = toasts,
		banner = banner,
		tutorial = tutorialRect,
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
