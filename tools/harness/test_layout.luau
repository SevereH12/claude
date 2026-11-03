--!nocheck
-- Device class, UI scale and the edge-anchored HUD layout (client/Lib/
-- LayoutMath) on every screen the game must fit.
--   lune run tools/harness/test_layout.luau [preview.json]
-- The rules it enforces, on every device at every Text size:
--   * every piece is on screen, clear of Roblox's top bar buttons and of
--     each other;
--   * nothing sits in the play area (the middle of the screen,
--     LayoutMath.playArea): not a HUD piece, a toast, the zone banner, the
--     tutorial's card or the Robux offer card. The timed chips (boosts,
--     friends, server chips) are held to it at Normal text size; bigger
--     text makes them bigger than the side bands can hold;
--   * nothing wraps or drops to a second line: every chip is wide enough
--     for its shortest wording, the strips are wide enough for their text;
--   * on touch, nothing is under the thumbstick or the jump button, and
--     the offer card's SEE and X are at least 44 points and never overlap.
-- With a path, also writes every device's HUD rectangles there, for
-- tools/render_ui.py to draw.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local World = require("./World")

local Vector2 = roblox.Vector2
local world = World.new("src")
local LayoutMath = world:require("StarterPlayer.StarterPlayerScripts.Client.Lib.LayoutMath")

local failures = 0
local function check(condition, message)
	if not condition then
		failures += 1
		print("FAIL: " .. message)
	end
end

local touch = { touch = true, keyboard = false, gamepad = false }
local pc = { touch = false, keyboard = true, gamepad = false }
local pad = { touch = false, keyboard = false, gamepad = true }
-- Roblox's top row (real pixels): its buttons take the left corner and
-- (to be safe) a bit of the right one; the middle is free. Consoles have none.
local TOPBAR = 58
local TOPBAR_LEFT = { Phone = 170, Tablet = 230, Desktop = 230, Console = 0 }
local TOPBAR_RIGHT = 70

local devices = {
	-- name, viewport, input, class
	{ "iPhone portrait", Vector2.new(390, 844), touch, "Phone" },
	{ "iPhone landscape", Vector2.new(844, 390), touch, "Phone" },
	{ "small phone portrait", Vector2.new(360, 640), touch, "Phone" },
	{ "small phone landscape", Vector2.new(640, 360), touch, "Phone" },
	{ "iPhone SE portrait", Vector2.new(375, 667), touch, "Phone" },
	{ "iPhone SE landscape", Vector2.new(667, 375), touch, "Phone" },
	{ "iPad landscape", Vector2.new(1024, 768), touch, "Tablet" },
	{ "iPad portrait", Vector2.new(768, 1024), touch, "Tablet" },
	{ "1080p desktop", Vector2.new(1920, 1080), pc, "Desktop" },
	{ "4K desktop", Vector2.new(3840, 2160), pc, "Desktop" },
	{ "small window", Vector2.new(800, 600), pc, "Desktop" },
	{ "tall window", Vector2.new(600, 900), pc, "Desktop" },
	{ "ultrawide", Vector2.new(3440, 1440), pc, "Desktop" },
	{ "console at 1080p", Vector2.new(1920, 1080), pad, "Console" },
}

-- always on screen, and never over one another
local STAY = {
	"volts",
	"storm",
	"boosts",
	"goal",
	"serverStorm",
	"event",
	"serverGoal",
	"friends",
	"bar",
	"menu",
}
-- the pieces that hold to the play area at every Text size
local CORE = { "volts", "storm", "goal", "bar", "menu", "toasts", "banner", "tutorial", "offer" }
-- the timed chips: held to the play area and the thumb zones at Normal text
local CHIPS = { "boosts", "serverStorm", "event", "serverGoal", "friends" }
-- strips for passing things: they appear one at a time
local STRIPS = { "toasts", "banner", "tutorial", "offer" }
-- each chip's shortest wording (the HUD shows the longest that fits)
local SHORTEST = {
	serverStorm = "🌩️ 59:59",
	event = "🎉 59:59",
	serverGoal = "⚡ 100%",
	friends = LayoutMath.FRIENDS_SAMPLE,
}

local function solid(r)
	return r.w > 0 and r.h > 0
end
local function rectOf(x, y, w, h)
	return { x = x, y = y, w = w, h = h }
end

local preview = {}

-- every device at every Text size setting (0 Normal, 1 Large, 2 Extra large)
for _, level in { 0, 1, 2 } do
	for _, device in devices do
		local deviceName, viewport, input, class = table.unpack(device)
		local name = if level == 0 then deviceName else `{deviceName} (text size {level})`
		local got = LayoutMath.classify(viewport, input)
		check(got == class, `{name}: is a {class} (got {got})`)
		local scale = LayoutMath.scale(got, viewport, level)
		check(
			scale >= LayoutMath.scale(got, viewport) - 1e-9,
			`{name}: a bigger text size never shrinks the UI`
		)
		local edge = LayoutMath.edgePadding(got)
		-- the safe area in design pixels: inside the TV edge on a console
		local area = viewport * (1 - 2 * edge) / scale
		local topbar = if got == "Console"
			then { left = 0, right = area.X, height = 0 }
			else {
				left = TOPBAR_LEFT[got] / scale,
				right = (viewport.X - TOPBAR_RIGHT) / scale,
				height = TOPBAR / scale,
			}
		local chipText = LayoutMath.chipText(got, scale, level)
		local hud = LayoutMath.hud(got, area, topbar, chipText, level)
		local play = LayoutMath.playArea(got, area, level)
		local upright = area.Y > area.X
		local isTouch = LayoutMath.isTouch(got)

		-- the play area is a box in the middle of the screen
		check(LayoutMath.inside(play, area), `{name}: the play area is on screen`)
		check(
			math.abs(play.x + play.w / 2 - area.X / 2) < 1e-6
				and math.abs(play.y + play.h / 2 - area.Y / 2) < 1e-6,
			`{name}: the play area is centred`
		)
		check(play.w >= 0.4 * area.X - 1e-6, `{name}: the play area is at least 40% of the width`)

		-- chips: tall enough for their text at the smallest size Roblox may
		-- draw it, and wide enough for the whole of it (no cut-off numbers)
		check(
			chipText >= LayoutMath.minTextSize(got, scale, level),
			`{name}: chips are sized for at least the smallest text`
		)
		local chipH = LayoutMath.chipHeight(chipText)
		local count = LayoutMath.HUD.boostCount
		local G = LayoutMath.GAP
		local across = hud.boosts.h < 2 * chipH
		local boostChip = if across
			then Vector2.new((hud.boosts.w - (count - 1) * G) / count, hud.boosts.h)
			else Vector2.new(hud.boosts.w, (hud.boosts.h - (count - 1) * G) / count)
		check(
			boostChip.X + 1e-6 >= LayoutMath.chipWidth(LayoutMath.BOOST_SAMPLE, chipText),
			`{name}: a boost chip fits "{LayoutMath.BOOST_SAMPLE}" ({boostChip.X} wide)`
		)
		check(boostChip.Y + 1e-6 >= chipH, `{name}: a boost chip is tall enough for its text`)
		-- every other chip's shortest wording fits: nothing wraps or is cut off
		for key, text in SHORTEST do
			check(
				LayoutMath.chipWidth(text, chipText) <= hud[key].w + 1e-6,
				`{name}: {key} fits "{text}" ({hud[key].w} wide)`
			)
			check(hud[key].h >= chipText + 6, `{name}: {key} is tall enough for its text`)
		end
		-- the strips are wide enough for their text; the banner is a big card
		-- where it has room (PC, console) and zero high where it is a toast
		check(hud.toasts.w >= 260, `{name}: toasts are wide enough ({hud.toasts.w})`)
		check(hud.tutorial.w >= 380, `{name}: the tutorial card is wide enough`)
		check(hud.offer.w >= 380, `{name}: the offer card is wide enough`)
		check(
			hud.banner.h == 0 or hud.banner.w >= 260,
			`{name}: the zone banner is wide enough or a toast`
		)
		check(
			hud.banner.h == 0 or not isTouch,
			`{name}: a touch screen shows the zone banner as a toast`
		)

		for _, block in LayoutMath.topbarBlocks(area, topbar) do
			for key, r in hud do
				check(
					not LayoutMath.overlaps(r, block),
					`{name}: {key} is clear of Roblox's top bar buttons`
				)
			end
		end
		for key, r in hud do
			if key ~= "test" then
				check(LayoutMath.inside(r, area), `{name}: {key} is on screen`)
			end
		end

		-- nothing overlaps: the always-on pieces with each other, the strips
		-- with every piece
		for i, a in STAY do
			for j = i + 1, #STAY do
				local b = STAY[j]
				check(not LayoutMath.overlaps(hud[a], hud[b]), `{name}: {a} and {b} don't overlap`)
			end
			for _, strip in STRIPS do
				check(not LayoutMath.overlaps(hud[strip], hud[a]), `{name}: {strip} clears {a}`)
			end
		end
		-- the strips apart: held upright they share the one strip under the bar
		-- (one shows at a time: Offers wait for the tutorial, a banner is a
		-- toast); elsewhere the toasts are across the top and the cards above
		-- the bar, and the offer and the tutorial's card share their slot
		if upright then
			for _, strip in { "tutorial", "offer" } do
				check(
					math.abs(hud[strip].y - hud.toasts.y) < 1e-6,
					`{name}: the {strip} card shares the toasts' strip`
				)
			end
		else
			for _, strip in { "banner", "tutorial", "offer" } do
				check(
					not LayoutMath.overlaps(hud.toasts, hud[strip]),
					`{name}: toasts clear the {strip}`
				)
			end
			check(
				not LayoutMath.overlaps(hud.banner, hud.tutorial)
					and not LayoutMath.overlaps(hud.banner, hud.offer),
				`{name}: the banner clears the cards`
			)
		end

		-- the middle of the screen stays clear (the chips at Normal text size)
		for _, key in CORE do
			check(not LayoutMath.overlaps(hud[key], play), `{name}: {key} is clear of the play area`)
		end
		if level == 0 then
			for _, key in CHIPS do
				check(
					not LayoutMath.overlaps(hud[key], play),
					`{name}: {key} is clear of the play area`
				)
			end
		end

		-- the menu's card opens over a dimmed screen, so it may reach into the
		-- middle, but it must be on screen and clear of the button and of the
		-- core pieces
		check(
			not LayoutMath.overlaps(hud.card, hud.menu),
			`{name}: the menu card opens beside the button`
		)
		for _, key in { "volts", "storm", "goal", "bar" } do
			check(
				not LayoutMath.overlaps(hud.card, hud[key]),
				`{name}: the open menu card clears {key}`
			)
		end

		-- the offer card: its row (icon, text, SEE, X) fits the card, SEE and
		-- X are fingertip-sized and apart, and the card (grown to hold them)
		-- keeps clear of the middle and the thumb controls
		local row = LayoutMath.offerRow(got, scale, hud.offer.w, hud.offer.h)
		local cardBox = rectOf(0, 0, hud.offer.w, row.height)
		for _, key in { "icon", "text", "see", "close" } do
			check(LayoutMath.inside(row[key], Vector2.new(cardBox.w, cardBox.h)), `{name}: offer {key} is in the card`)
		end
		local parts = { "icon", "text", "see", "close" }
		for i, a in parts do
			for j = i + 1, #parts do
				check(
					not LayoutMath.overlaps(row[a], row[parts[j]]),
					`{name}: offer {a} and {parts[j]} don't overlap`
				)
			end
		end
		check(row.text.w >= 150, `{name}: the offer's text has room ({row.text.w})`)
		if isTouch then
			for _, key in { "see", "close" } do
				check(
					row[key].w * scale >= 44 - 1e-6 and row[key].h * scale >= 44 - 1e-6,
					`{name}: offer {key} is at least 44 points`
				)
			end
		end
		local grown = rectOf(hud.offer.x, hud.offer.y, hud.offer.w, row.height)
		check(LayoutMath.inside(grown, area), `{name}: the offer card still fits on screen`)
		check(not LayoutMath.overlaps(grown, play), `{name}: the offer card is clear of the play area`)
		check(not LayoutMath.overlaps(grown, hud.bar), `{name}: the offer card clears the bar`)
		-- the tutorial's SKIP (and YES / NO) fit the card at fingertip size
		if isTouch then
			check(
				hud.tutorial.h * scale >= 44 - 1e-6,
				`{name}: the tutorial card is tall enough for a 44 point button`
			)
		end

		if isTouch then
			local pieces = {}
			for _, key in STAY do
				if level == 0 or not table.find(CHIPS, key) then
					pieces[key] = hud[key]
				end
			end
			pieces.tutorial = hud.tutorial
			pieces.offer = grown
			pieces.toasts = hud.toasts
			for _, zone in LayoutMath.thumbZones(area) do
				for key, r in pieces do
					check(
						not LayoutMath.overlaps(r, zone),
						`{name}: {key} is clear of the thumb controls`
					)
				end
			end
			-- every button at least 44 points, phone text at least 14
			local tap = LayoutMath.tapMin(got, scale, Vector2.new(30, 20)) * scale
			check(
				tap.X >= 44 - 1e-6 and tap.Y >= 44 - 1e-6,
				`{name}: a small button grows to 44 points`
			)
			check(
				hud.menu.w * scale >= 44 - 1e-6 and hud.menu.h * scale >= 44 - 1e-6,
				`{name}: MENU is at least 44 points`
			)
		end
		if got == "Phone" then
			check(
				LayoutMath.minTextSize(got, scale, level) * scale >= 14,
				`{name}: text is at least 14 points`
			)
		end
		local wantPoints = LayoutMath.TEXT_MIN_POINTS[level]
		if wantPoints then
			check(
				LayoutMath.minTextSize(got, scale, level) * scale >= wantPoints - 1e-6,
				`{name}: text is at least {wantPoints} points`
			)
		end
		-- the same share of the screen everywhere: the menu button is the same
		-- fraction of the short side on every desktop
		if got == "Desktop" and level == 0 then
			local share = hud.menu.w * scale / math.min(viewport.X, viewport.Y)
			check(
				math.abs(share - 84 / 720) < 0.01,
				`{name}: the menu button is the same share of the screen`
			)
		end
		-- a big panel always fits
		local panel = LayoutMath.fit(Vector2.new(620, 520), area - Vector2.new(0, topbar.height))
		check(panel.X <= area.X - 32 + 1e-6 and panel.Y <= area.Y - 32 + 1e-6, `{name}: panels fit`)

		local rects = {}
		for key, r in hud do
			rects[key] = { r.x, r.y, r.w, r.h }
		end
		if level > 0 then
			continue -- the preview shows the Normal text size
		end
		table.insert(preview, {
			name = name,
			class = got,
			scale = scale,
			viewport = { viewport.X, viewport.Y },
			area = { area.X, area.Y },
			edge = edge,
			topbar = { topbar.left, topbar.right, topbar.height },
			hud = rects,
			play = { play.x, play.y, play.w, play.h },
			panel = { panel.X, panel.Y },
			thumbs = if isTouch
				then (function()
					local out = {}
					for _, z in LayoutMath.thumbZones(area) do
						table.insert(out, { z.x, z.y, z.w, z.h })
					end
					return out
				end)()
				else {},
		})
	end
end

check(
	LayoutMath.scale("Phone", Vector2.new(390, 844))
		< LayoutMath.scale("Desktop", Vector2.new(1920, 1080)),
	"phones scale smaller than a 1080p monitor"
)
check(
	LayoutMath.scale("Desktop", Vector2.new(3840, 2160))
		== 2 * LayoutMath.scale("Desktop", Vector2.new(1920, 1080)),
	"4K is twice 1080p"
)
-- a zero-size rectangle (the banner shown as a toast) overlaps nothing
check(
	not LayoutMath.overlaps(rectOf(5, 5, 0, 0), rectOf(0, 0, 100, 100)),
	"a zero-size rectangle overlaps nothing"
)
-- the HUD picks the longest wording that fits, else the shortest
check(
	LayoutMath.fitText({ "a long long long long text", "short" }, 80, 14) == "short",
	"fitText falls back to a shorter wording"
)
check(
	LayoutMath.fitText({ "fits", "f" }, 200, 14) == "fits",
	"fitText keeps the full wording when it fits"
)
check(
	LayoutMath.textWidth("⚡ 1:05:00", 10) > LayoutMath.textWidth("⚡ 14:32", 10),
	"a longer time is measured wider"
)
local laptopWithPad = { touch = false, keyboard = true, gamepad = true, preferred = "Gamepad" }
check(
	LayoutMath.classify(Vector2.new(1920, 1080), laptopWithPad) == "Console",
	"playing with a gamepad on a PC uses console layout"
)
-- a click in Studio's phone emulator reports the mouse as the preferred
-- input: the phone must stay a phone
local clicked = { touch = true, keyboard = false, gamepad = false, preferred = "KeyboardAndMouse" }
check(
	LayoutMath.classify(Vector2.new(844, 390), clicked) == "Phone",
	"a click doesn't turn a phone into a PC"
)
check(LayoutMath.classify(Vector2.new(1024, 768), clicked) == "Tablet", "or a tablet into a PC")
local touchLaptop = { touch = true, keyboard = true, gamepad = false }
check(
	LayoutMath.classify(Vector2.new(1366, 768), touchLaptop) == "Desktop",
	"a touchscreen laptop with a keyboard is a desktop"
)

if process.args[1] then
	fs.writeFile(process.args[1], serde.encode("json", preview))
end
if failures > 0 then
	error(`{failures} layout checks failed`)
end
print("layout checks passed")
