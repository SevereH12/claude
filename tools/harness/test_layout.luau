--!nocheck
-- Device class, UI scale and the edge-anchored HUD layout (client/Lib/
-- LayoutMath) on every screen the game must fit.
--   lune run tools/harness/test_layout.luau [preview.json]
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
	{ "iPad landscape", Vector2.new(1024, 768), touch, "Tablet" },
	{ "iPad portrait", Vector2.new(768, 1024), touch, "Tablet" },
	{ "1080p desktop", Vector2.new(1920, 1080), pc, "Desktop" },
	{ "4K desktop", Vector2.new(3840, 2160), pc, "Desktop" },
	{ "small window", Vector2.new(800, 600), pc, "Desktop" },
	{ "ultrawide", Vector2.new(3440, 1440), pc, "Desktop" },
	{ "console at 1080p", Vector2.new(1920, 1080), pad, "Console" },
}

local STAY = { "volts", "storm", "boosts", "goal", "serverStorm", "event", "bar", "menu" } -- always on screen
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
		local hud = LayoutMath.hud(got, area, topbar)
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
		for i, a in STAY do
			for j = i + 1, #STAY do
				local b = STAY[j]
				check(not LayoutMath.overlaps(hud[a], hud[b]), `{name}: {a} and {b} don't overlap`)
			end
			check(not LayoutMath.overlaps(hud.toasts, hud[a]), `{name}: toasts clear {a}`)
			check(not LayoutMath.overlaps(hud.banner, hud[a]), `{name}: zone banner clears {a}`)
		end
		check(
			not LayoutMath.overlaps(hud.card, hud.menu),
			`{name}: the menu card opens beside the button`
		)
		for _, key in { "volts", "storm", "boosts", "goal", "serverStorm", "event", "bar" } do
			check(
				not LayoutMath.overlaps(hud.card, hud[key]),
				`{name}: the open menu card clears {key}`
			)
		end
		if LayoutMath.isTouch(got) then
			for _, zone in LayoutMath.thumbZones(area) do
				for _, key in STAY do
					check(
						not LayoutMath.overlaps(hud[key], zone),
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
			panel = { panel.X, panel.Y },
			thumbs = if LayoutMath.isTouch(got)
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
