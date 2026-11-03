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
-- The HUD sits on the screen's edges and corners, and the middle of the
-- screen (LayoutMath.playArea) stays clear for play. Volts and the storm
-- timer are top left, the next goal top right. The bottle bar is bottom
-- centre (between the thumbstick and the jump button on a sideways phone or
-- tablet; in the top stack on a screen held upright, where the bottom
-- middle is too narrow). MENU is bottom left on a PC or console, under the
-- storm timer on a sideways phone or tablet, and in the left side band
-- upright. Toasts, the zone banner and the cards (the tutorial's step, the
-- Robux offer) are short strips: toasts and the banner across the top, the
-- cards above the bar; upright they share one strip under the bar. The
-- timed chips (boosts, friends, the server chips) are rows along the top or
-- columns in the side bands, always inside the room their text needs. Pieces
-- use the free middle of Roblox's top row and only drop below it where its
-- own buttons are.

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
	boosts: Rect, -- timed boost chips: a row (along the top, or under the storm timer) or a column (a side band)
	goal: Rect,
	serverStorm: Rect, -- a Server Storm's chip (buyer and time left), under the goal
	event: Rect, -- a scheduled event's chip (name and time left), under that
	serverGoal: Rect, -- the server goal meter (tap: top contributors), under the event's chip
	friends: Rect, -- the friends boost's chip ("👥 +10% friends")
	bar: Rect,
	menu: Rect,
	card: Rect, -- the menu's tile card (it opens over a dimmed screen, so it may reach into the play area)
	toasts: Rect,
	banner: Rect, -- the zone banner (PC and console; touch screens show it as a toast)
	tutorial: Rect, -- the tutorial's step card
	offer: Rect, -- the Robux offer card
	test: Rect, -- the ADMIN button's spot (two rows), beside the menu
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
	toastWide = 500, -- a toast across a screen held upright
	toastHeight = 44,
	toastGap = 6,
	toastRows = 2,
	bannerWidth = 560,
	bannerHeight = 100,
	bannerMin = 64, -- the banner shrinks to this to fit above the play area
	tutorialWidth = 440,
	tutorialHeight = 64,
	offerWidth = 440,
	offerHeight = 76, -- touch: a row 44 points tall for SEE and X, with room round it
	offerHeightPc = 60,
	tankHeight = 22, -- the Chemist's TANK count, by the bottle bar
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
LayoutMath.BOOST_SAMPLE = "⚡ 59:59" -- the widest a boost chip's text gets (an hour or more shows minutes: "⚡ 65m")
LayoutMath.FRIENDS_SAMPLE = "👥 +50%" -- the friends chip's shortest wording

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

-- The play area: the middle of the screen, kept clear for play. No HUD
-- piece, toast or card sits in it; they hug the edges and corners. It is
-- PLAY_W of the width and a share of the height (phones and anything held
-- upright have the least room). A bigger Text size makes everything bigger,
-- so the area narrows by PLAY_W_STEP and shortens by PLAY_H_STEP a step.
LayoutMath.PLAY_W = 0.5
LayoutMath.PLAY_W_STEP = 0.05
LayoutMath.PLAY_H_STEP = 0.04
LayoutMath.PLAY_H = {
	Phone = 0.3,
	Tablet = 0.4,
	Desktop = 0.4,
	Console = 0.4,
} :: { [DeviceClass]: number }
LayoutMath.PLAY_H_UPRIGHT = {
	Phone = 0.24,
	Tablet = 0.26,
	Desktop = 0.3,
	Console = 0.3,
} :: { [DeviceClass]: number }

function LayoutMath.playArea(class: DeviceClass, area: Vector2, textLevel: number?): Rect
	local shares = if area.Y > area.X then LayoutMath.PLAY_H_UPRIGHT else LayoutMath.PLAY_H
	local w = LayoutMath.PLAY_W - LayoutMath.PLAY_W_STEP * (textLevel or 0)
	local h = shares[class] - LayoutMath.PLAY_H_STEP * (textLevel or 0)
	return rect(area.X * (1 - w) / 2, area.Y * (1 - h) / 2, area.X * w, area.Y * h)
end

-- The Robux offer card's row, relative to the card's top left: the pass's
-- icon, one line of text, SEE and X. SEE and X are as big as a fingertip
-- needs (tapMin: 44 points on touch) so they never overlap or fall short;
-- the card grows to hold them. `minHeight`: Layout.hud.offer's height.
export type OfferRow = { height: number, icon: Rect, text: Rect, see: Rect, close: Rect }
LayoutMath.OFFER_PAD = 8
LayoutMath.OFFER_GAP = 6
LayoutMath.OFFER_SEE = 80 -- SEE is at least this wide (design pixels)

function LayoutMath.offerRow(
	class: DeviceClass,
	scale: number,
	width: number,
	minHeight: number
): OfferRow
	local pad, gap = LayoutMath.OFFER_PAD, LayoutMath.OFFER_GAP
	local tap = LayoutMath.tapMin(class, scale, Vector2.new(40, 36))
	local buttonH = math.max(36, tap.Y, minHeight - 2 * pad)
	local height = math.max(minHeight, buttonH + 12)
	local closeW = tap.X
	local seeW = math.max(tap.X, LayoutMath.OFFER_SEE)
	local iconSize = math.min(56, height - 2 * pad)
	local textX = pad + iconSize + pad
	local seeX = width - pad - closeW - gap - seeW
	local buttonY = (height - buttonH) / 2
	return {
		height = height,
		icon = rect(pad, (height - iconSize) / 2, iconSize, iconSize),
		text = rect(textX, 4, seeX - pad - textX, height - 8),
		see = rect(seeX, buttonY, seeW, buttonH),
		close = rect(width - pad - closeW, buttonY, closeW, buttonH),
	}
end

-- Where the thumbstick and jump button sit on a touch screen (design
-- pixels, roughly): HUD pieces that stay on screen keep out of these. Held
-- sideways they take less of the width (Roblox's controls are 70 to 120
-- points wide), which leaves the bottom middle for the bottle bar.
function LayoutMath.thumbZones(area: Vector2): { Rect }
	local W, T = area.X, area.Y
	if W > T then
		return {
			rect(0, T * 0.6, W * 0.28, T * 0.4), -- thumbstick: bottom left
			rect(W * 0.78, T * 0.62, W * 0.22, T * 0.38), -- jump: bottom right
		}
	end
	return {
		rect(0, T * 0.6, W * 0.4, T * 0.4),
		rect(W * 0.72, T * 0.62, W * 0.28, T * 0.38),
	}
end

-- Where every HUD piece goes on a safe area of `area` design pixels.
-- `topbar`: Roblox's top row (design pixels); pieces use its free middle
-- and only drop below it where its buttons are.
-- `chipText`: the text size chips are sized for (LayoutMath.chipText).
-- `textLevel`: the Text size setting (it narrows the play area).
--
-- Three arrangements, so nothing wraps or drops to a second line:
--   * PC and console: Volts, the storm timer, the boosts' row and the
--     friends chip top left; the goal and the server chips top right; toasts
--     then the zone banner across the top; the bar bottom middle with MENU
--     in the bottom left corner; cards above the bar.
--   * a phone or tablet held sideways: Volts, the storm timer and MENU down
--     the left edge; the goal and the server chips down the right; the
--     boosts' row (and the friends chip) and toasts across the top; the bar
--     between the thumbstick and the jump button, cards above it.
--   * held upright (or a tall window): Volts and the storm timer left, the
--     goal right, then the bar, then one strip that toasts and cards share;
--     under it MENU and the boosts' column in the left side band, and the
--     friends chip and the server chips in the right one.
function LayoutMath.hud(
	class: DeviceClass,
	area: Vector2,
	topbar: Topbar?,
	chipText: number?,
	textLevel: number?
): Hud
	local H = LayoutMath.HUD
	local M, G = LayoutMath.MARGIN, LayoutMath.GAP
	local W, T = area.X, area.Y
	local bar0: Topbar = topbar or { left = 0, right = W, height = 0 }
	local touch = LayoutMath.isTouch(class)
	local upright = T > W
	local play = LayoutMath.playArea(class, area, textLevel)

	-- every chip is tall enough for its text, and a boost chip wide enough
	-- for "⚡ 59:59" (BOOST_SAMPLE), which is also the widest the others get
	-- in their shortest wording
	local textSize = chipText or LayoutMath.CHIP_TEXT
	local chipH = LayoutMath.chipHeight(textSize)
	local boostW = LayoutMath.chipWidth(LayoutMath.BOOST_SAMPLE, textSize)
	local friendsW = LayoutMath.chipWidth(LayoutMath.FRIENDS_SAMPLE, textSize)
	local count = H.boostCount
	local column = count * chipH + (count - 1) * G
	local meterH = math.max(H.serverGoalHeight, textSize + 6)
	local toastsH = H.toastRows * H.toastHeight + (H.toastRows - 1) * H.toastGap

	-- the top edge for something spanning x .. x + w: the very top in the top
	-- bar's free middle, under the bar where its buttons are
	local function topFor(x: number, w: number): number
		if bar0.height > 0 and (x < bar0.left + G or x + w > bar0.right - G) then
			return bar0.height + M
		end
		return M
	end

	-- The pieces at the left and right edges, so strips can keep clear of
	-- them: the free span left to right for a band y0 .. y1 (inside lo .. hi),
	-- clear of Roblox's own buttons and of those pieces; and a strip of
	-- width `w` centred in it (narrower if that is all there is).
	local edges: { Rect } = {}
	local function edge(r: Rect): Rect
		table.insert(edges, r)
		return r
	end
	local function spanAt(y0: number, y1: number, lo: number, hi: number): (number, number)
		local left, right = lo, hi
		if bar0.height > 0 and y0 < bar0.height then
			left = math.max(left, bar0.left + G)
			right = math.min(right, bar0.right - G)
		end
		for _, r in edges do
			if r.y < y1 + G and r.y + r.h + G > y0 then
				if r.x + r.w / 2 < W / 2 then
					left = math.max(left, r.x + r.w + G)
				else
					right = math.min(right, r.x - G)
				end
			end
		end
		return left, right
	end
	local function across(
		w: number,
		y0: number,
		y1: number,
		lo: number,
		hi: number
	): (number, number)
		local left, right = spanAt(y0, y1, lo, hi)
		local width = math.max(0, math.min(w, right - left))
		return math.clamp((W - width) / 2, left, math.max(left, right - width)), width
	end

	-- Volts and the storm timer top left, the goal top right. A phone held
	-- upright has a top row whose free middle is narrower than Volts' usual
	-- width: Volts shrinks into it (that saves a row's height) and the storm
	-- timer starts the column under the Roblox buttons.
	local volts: Rect
	local storm: Rect
	local middle = bar0.right - bar0.left - 2 * G
	if upright and bar0.height > 0 and middle >= 150 and middle < H.statWidth then
		local width = math.min(H.statWidth, middle)
		volts = edge(rect(bar0.left + G + (middle - width) / 2, M, width, H.voltsHeight))
		storm = edge(rect(M, topFor(M, H.statWidth), H.statWidth, H.stormHeight))
	else
		volts = edge(rect(M, topFor(M, H.statWidth), H.statWidth, H.voltsHeight))
		storm = edge(rect(M, volts.y + volts.h + G, H.statWidth, H.stormHeight))
	end
	local function goalAt(width: number): Rect
		local x = W - M - width
		return rect(x, topFor(x, width), width, H.goalHeight)
	end
	local goal: Rect
	if upright then
		goal = goalAt(math.max(160, math.min(H.goalWidth, W - 2 * M - H.statWidth - G)))
	else
		goal = goalAt(H.goalWidth)
		-- if it would reach into the play area it takes the room beside it
		if goal.x < play.x + play.w and goal.y + goal.h > play.y then
			goal = goalAt(math.max(H.statWidth, W - M - (play.x + play.w)))
		end
	end
	edge(goal)

	local boosts: Rect
	local friends: Rect
	local serverStorm: Rect
	local event: Rect
	local serverGoal: Rect
	local menu: Rect
	local bar: Rect
	local card: Rect
	local toasts: Rect
	local banner: Rect
	local tutorial: Rect
	local offer: Rect
	local test: Rect

	if upright then
		-- Volts and the storm timer left, the goal right, then the bar across,
		-- then the strip toasts and cards share
		local rowY = math.max(storm.y + storm.h, goal.y + goal.h) + G
		local barW = math.min(H.barWidth, W - 2 * M)
		bar = rect((W - barW) / 2, rowY, barW, H.barHeight)
		local stripY = rowY + H.barHeight + G
		local toastW = math.min(W - 2 * M, H.toastWide)
		toasts = rect((W - toastW) / 2, stripY, toastW, toastsH)
		banner = rect(toasts.x, toasts.y, toasts.w, 0) -- no room for the big title: a toast
		local cardW = math.min(W - 2 * M, H.offerWidth)
		tutorial = rect((W - cardW) / 2, stripY, cardW, H.tutorialHeight)
		offer = rect((W - cardW) / 2, stripY, cardW, H.offerHeight)
		-- the side bands under it: MENU and the boosts' column on the left, the
		-- friends chip and the server chips on the right (each as wide as the
		-- shortest wording needs)
		local bandTop = stripY + toastsH + G
		menu = rect(M, bandTop, H.menuSize, H.menuSize)
		boosts = rect(M, menu.y + menu.h + G, boostW, column)
		local x = W - M - boostW
		friends = rect(x, bandTop, boostW, chipH)
		serverStorm = rect(x, friends.y + friends.h + G, boostW, chipH)
		event = rect(x, serverStorm.y + serverStorm.h + G, boostW, chipH)
		serverGoal = rect(x, event.y + event.h + G / 2, boostW, meterH)
		card = rect(menu.x + menu.w + 10, menu.y, H.cardWidth, H.cardHeight)
		test = rect(menu.x + menu.w + G, menu.y, H.testWidth, 2 * H.testHeight + G)
	else
		-- the server chips under the goal; if the goal's width would reach into
		-- the play area they take the room beside it instead
		local function chipColumn(width: number): (Rect, Rect, Rect)
			local x = W - M - width
			local first = rect(x, goal.y + goal.h + G, width, chipH)
			local second = rect(x, first.y + first.h + G, width, chipH)
			local meter = rect(x, second.y + second.h + G / 2, width, meterH)
			return first, second, meter
		end
		serverStorm, event, serverGoal = chipColumn(H.goalWidth)
		local fullX = W - M - H.goalWidth
		if fullX < play.x + play.w and serverGoal.y + serverGoal.h > play.y then
			local room = math.max(boostW, W - M - (play.x + play.w))
			serverStorm, event, serverGoal = chipColumn(math.min(H.goalWidth, room))
		end
		edge(serverStorm)
		edge(event)
		edge(serverGoal)
		local sideways = touch
		local lo, hi = M, W - M -- where cards may sit (sideways: between the thumbs)

		local stripBottom = M -- the bottom of the row of chips along the top
		if sideways then
			local zones = LayoutMath.thumbZones(area)
			lo, hi = zones[1].x + zones[1].w + G, zones[2].x - G
			-- the boosts' row along the top, the friends chip beside it
			local left, right = spanAt(M, M + chipH, M, W - M)
			local rowW = count * boostW + (count - 1) * G
			if rowW <= right - left then
				local both = rowW + G + friendsW <= right - left
				local total = if both then rowW + G + friendsW else rowW
				local x = math.clamp((W - total) / 2, left, math.max(left, right - total))
				boosts = rect(x, M, rowW, chipH)
				friends = if both
					then rect(x + rowW + G, M, friendsW, chipH)
					else rect(
						serverGoal.x,
						serverGoal.y + serverGoal.h + G,
						serverGoal.w,
						chipH
					)
				stripBottom = M + chipH
			else
				-- no room along the top: a column under the storm timer
				boosts = rect(M, storm.y + storm.h + G, boostW, column)
				friends = rect(M, boosts.y + boosts.h + G, H.statWidth, chipH)
				edge(boosts)
				edge(friends)
			end
			local leftBottom = if stripBottom > M then storm.y + storm.h else friends.y + friends.h
			menu = edge(rect(M, leftBottom + G, H.menuSize, H.menuSize))
		else
			-- PC and console: the boosts' row under the storm timer (a column
			-- if the row would reach into the play area or the goal's column),
			-- the friends chip under it
			local chipW = math.max(boostW, (H.statWidth - (count - 1) * G) / count)
			local rowW = count * chipW + (count - 1) * G
			local rowY = storm.y + storm.h + G
			local fits = M + rowW <= goal.x - 2 * G
				and not (rowY + chipH > play.y and M + rowW > play.x)
			boosts = if fits then rect(M, rowY, rowW, chipH) else rect(M, rowY, boostW, column)
			friends = rect(M, boosts.y + boosts.h + G, H.statWidth, chipH)
			edge(boosts)
			edge(friends)
			menu = edge(rect(M, T - M - H.menuSize, H.menuSize, H.menuSize))
		end

		-- the bottle bar
		if sideways then
			-- (math.max: when the bar only just fits, hi - width can come out a
			-- hair under lo, and clamp refuses a max under its min)
			local width = math.min(H.barWidth, hi - lo)
			local x = math.clamp((W - width) / 2, lo, math.max(lo, hi - width))
			bar = rect(x, T - M - H.barHeight, width, H.barHeight)
		else
			bar = rect((W - H.barWidth) / 2, T - M - H.barHeight, H.barWidth, H.barHeight)
		end

		-- toasts across the top, under the chips' row; PC and console put the
		-- zone banner under them (a touch screen shows it as a toast)
		local toastY = if stripBottom > M then stripBottom + G else M
		local toastX, toastW = across(H.toastWidth, toastY, toastY + toastsH, M, W - M)
		toasts = rect(toastX, toastY, toastW, toastsH)
		-- (a touch screen, or one with no room for it above the play area,
		-- shows it as a toast instead: the banner is then zero high)
		banner = rect(toasts.x, toasts.y, toasts.w, 0)
		local bannerY = toastY + toastsH + G
		local bannerH = math.min(H.bannerHeight, play.y - G - bannerY)
		if not touch and bannerH >= H.bannerMin then
			local bannerX, bannerW = across(H.bannerWidth, bannerY, bannerY + bannerH, M, W - M)
			banner = rect(bannerX, bannerY, bannerW, bannerH)
		end

		-- cards above the bar (and the TANK count that sits over its right end)
		local cardsBottom = bar.y - H.tankHeight - 6
		local offerH = if touch then H.offerHeight else H.offerHeightPc
		local function slot(width: number, height: number): Rect
			local y = cardsBottom - height
			local x, w = across(width, y, y + height, lo, hi)
			return rect(x, y, w, height)
		end
		tutorial = slot(H.tutorialWidth, H.tutorialHeight)
		offer = slot(H.offerWidth, offerH)

		-- the menu's card opens above MENU at the corner, beside it on the left
		-- edge (never over the Volts and the storm timer)
		if sideways then
			local top = storm.y + storm.h + G
			local y = math.clamp(
				menu.y + (menu.h - H.cardHeight) / 2,
				top,
				math.max(top, T - M - H.cardHeight)
			)
			card = rect(menu.x + menu.w + 10, y, H.cardWidth, H.cardHeight)
			test = rect(menu.x + menu.w + G, menu.y, H.testWidth, 2 * H.testHeight + G)
		else
			card = rect(M, menu.y - 10 - H.cardHeight, H.cardWidth, H.cardHeight)
			local testH = 2 * H.testHeight + G
			test = rect(menu.x + menu.w + G, T - M - testH, H.testWidth, testH)
		end
	end

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
		menu = menu,
		card = card,
		toasts = toasts,
		banner = banner,
		tutorial = tutorial,
		offer = offer,
		test = test,
	}
end

-- Do two rectangles share any area? (One with no size, like the zone banner
-- where it is shown as a toast, overlaps nothing.)
function LayoutMath.overlaps(a: Rect, b: Rect): boolean
	if a.w <= 0 or a.h <= 0 or b.w <= 0 or b.h <= 0 then
		return false
	end
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

function LayoutMath.inside(a: Rect, area: Vector2): boolean
	return a.x >= 0 and a.y >= 0 and a.x + a.w <= area.X + 1e-6 and a.y + a.h <= area.Y + 1e-6
end

return LayoutMath
