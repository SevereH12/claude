--!nocheck
-- Device class and UI scale (client/Lib/LayoutMath) for the devices the
-- game must fit.
--   lune run tools/harness/test_layout.luau
local roblox = require("@lune/roblox")
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

local cases = {
	-- name, viewport, input, class, UIScale, edge padding
	{ "phone portrait", Vector2.new(390, 844), touch, "Phone", 390 / 480, 0 },
	{ "phone landscape", Vector2.new(844, 390), touch, "Phone", 390 / 480, 0 },
	{ "iPad", Vector2.new(1024, 768), touch, "Tablet", 1, 0 },
	{ "1080p desktop", Vector2.new(1920, 1080), pc, "Desktop", 1, 0 },
	{ "4K desktop", Vector2.new(3840, 2160), pc, "Desktop", 2, 0 },
	{ "console at 1080p", Vector2.new(1920, 1080), pad, "Console", 1.15, 0.05 },
}
for _, case in cases do
	local name, viewport, input, class, scale, edge = table.unpack(case)
	local got = LayoutMath.classify(viewport, input)
	check(got == class, `{name}: is a {class} (got {got})`)
	local s = LayoutMath.scale(got, viewport)
	check(math.abs(s - scale) < 1e-6, `{name}: UIScale {scale} (got {s})`)
	check(LayoutMath.edgePadding(got) == edge, `{name}: edge padding {edge}`)
	-- on screen, after the UIScale
	local text = LayoutMath.minTextSize(got, s) * s
	local tap = LayoutMath.tapMin(got, s, Vector2.new(30, 20)) * s
	if got == "Phone" then
		check(text >= LayoutMath.PHONE_MIN_TEXT, `{name}: text is at least 14 points ({text})`)
	end
	if LayoutMath.isTouch(got) then
		check(tap.X >= 44 - 1e-6 and tap.Y >= 44 - 1e-6, `{name}: a small button grows to 44 points`)
	else
		check(tap == Vector2.new(30, 20) * s, `{name}: no tap minimum without touch`)
	end
	local big = LayoutMath.tapMin(got, s, Vector2.new(96, 46))
	check(big.X >= 96 and big.Y >= 46, `{name}: a button's own minimum is kept`)
end
check(LayoutMath.scale("Phone", Vector2.new(390, 844)) < 1, "phones shrink the UI")
check(LayoutMath.scale("Phone", Vector2.new(320, 568)) >= 0.75, "but never below 0.75")

check(LayoutMath.isPortrait(Vector2.new(390, 844)), "a tall viewport is portrait")
check(not LayoutMath.isPortrait(Vector2.new(844, 390)), "a wide one isn't")
-- the preferred input wins over what's merely plugged in
local laptopWithPad = { touch = false, keyboard = true, gamepad = true, preferred = "Gamepad" }
check(LayoutMath.classify(Vector2.new(1920, 1080), laptopWithPad) == "Console", "playing with a gamepad on a PC uses console layout")
local touchLaptop = { touch = true, keyboard = true, gamepad = false }
check(LayoutMath.classify(Vector2.new(1366, 768), touchLaptop) == "Desktop", "a touchscreen laptop with a keyboard is a desktop")
check(LayoutMath.isTouch("Phone") and LayoutMath.isTouch("Tablet") and not LayoutMath.isTouch("Desktop"), "touch classes")

if failures > 0 then
	error(`{failures} layout checks failed`)
end
print("layout checks passed")
