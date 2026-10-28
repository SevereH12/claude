--!nocheck
-- Lightning effects (Util/StrikeFx): how much of a strike is drawn (your
-- own, another world's, each distance band, each Others' lightning
-- setting), whose light casts shadows, the flicker (it never hides before
-- the fade), the jagged path and the restrike, and the light budget.
--   lune run tools/harness/test_strikefx.luau
local roblox = require("@lune/roblox")
local World = require("./World")

local Vector3 = roblox.Vector3
local world = World.new("src")
local Config = world:require("ReplicatedStorage.Shared.Config")
local StrikeFx = world:require("ReplicatedStorage.Shared.Util.StrikeFx")
local fx = Config.STRIKE_FX

local failures = 0
local function check(condition, message)
	if not condition then
		failures += 1
		print("FAIL: " .. message)
	end
end

-- a seeded stand-in for Roblox's Random (only NextNumber is used)
math.randomseed(7)
local random = {
	NextNumber = function(_, min, max)
		return min + (max - min) * math.random()
	end,
}

-- the numbers ----------------------------------------------------------------------
check(fx.simpleDistance < fx.drawDistance, "simple starts before strikes stop being drawn")
check(fx.dim > 0 and fx.dim < 1, "the flicker dims but never hides")

-- how much is drawn ------------------------------------------------------------------
local function level(distance, sameWorld, mine, setting)
	return StrikeFx.level({
		distance = distance,
		sameWorld = sameWorld,
		mine = mine,
		setting = setting,
	})
end
local near = fx.simpleDistance / 2
local middle = (fx.simpleDistance + fx.drawDistance) / 2
local far = fx.drawDistance + 100

-- your own strikes are always full, whatever the distance, world or setting
for _, setting in { "Off", "Simple", "Full" } do
	for _, distance in { near, middle, far } do
		check(level(distance, true, true, setting) == "full", `own strike full ({setting}, {distance})`)
	end
	check(level(near, false, true, setting) == "full", `own strike full in another world ({setting})`)
end

-- another world's strikes are none
for _, setting in { "Off", "Simple", "Full" } do
	check(level(0, false, false, setting) == "none", `another world's strike is none ({setting})`)
end

-- each distance band with each setting (the setting can only lower it)
local expected = {
	Full = { near = "full", middle = "simple", far = "none" },
	Simple = { near = "simple", middle = "simple", far = "none" },
	Off = { near = "none", middle = "none", far = "none" },
}
for setting, bands in expected do
	for band, want in bands do
		local distance = if band == "near" then near elseif band == "middle" then middle else far
		local got = level(distance, true, false, setting)
		check(got == want, `{setting} at {band} ({distance} studs) is {want} (got {got})`)
	end
end
check(level(fx.simpleDistance, true, false, "Full") == "full", "exactly simpleDistance is still full")
check(level(fx.drawDistance, true, false, "Full") == "simple", "exactly drawDistance is still drawn")
check(level(near, true, false, "Nonsense") == "full", "an unknown setting counts as Full")

-- the flicker ----------------------------------------------------------------------
check(StrikeFx.restrikeTime() == fx.dipAt + fx.dipFor, "the restrike comes after the dip")
check(StrikeFx.brightness(0, false) == 1, "a bolt starts at full")
check(
	StrikeFx.brightness(fx.dipAt + fx.dipFor / 2, false) == fx.dim,
	"it dips to `dim` for one beat"
)
check(StrikeFx.brightness(StrikeFx.restrikeTime(), false) == 1, "the restrike is full again")
local fadeFrom = StrikeFx.restrikeTime() + fx.hold
local lowest, t = 1, 0
while t < fadeFrom do
	lowest = math.min(lowest, StrikeFx.brightness(t, false))
	t += 0.002
end
check(lowest >= fx.dim, `it never drops below dim before the fade (lowest {lowest})`)
local previous = 1
local falling = true
t = fadeFrom
while t < fadeFrom + fx.fade - 0.01 do
	local now = StrikeFx.brightness(t, false)
	if now == nil or now > previous or now <= 0 then
		falling = false
	end
	previous = now or 0
	t += 0.01
end
check(falling, "it fades steadily after the restrike")
check(StrikeFx.brightness(fadeFrom + fx.fade + 0.01, false) == nil, "then it's gone")

-- Reduce flashing: just the slow fade, no dip
check(StrikeFx.brightness(0, true) == 1, "calm: starts at full")
previous = 1
falling = true
t = 0.01
while t < fx.calmFade - 0.01 do
	local now = StrikeFx.brightness(t, true)
	if now == nil or now > previous or now <= 0 then
		falling = false
	end
	previous = now or 0
	t += 0.01
end
check(falling, "calm: only ever fades (no dip and back)")
check(StrikeFx.brightness(fx.calmFade + 0.01, true) == nil, "calm: then it's gone")

-- the jagged path ------------------------------------------------------------------
local function same(a, b)
	return (a - b).Magnitude < 1e-6
end
local top = Vector3.new(10, 170, -4)
local ground = Vector3.new(0, 10, 0)
for _, segments in { 4, 9 } do
	local wobble = 9
	local path = StrikeFx.jaggedPath(top, ground, segments, wobble, random)
	check(#path == segments + 1, `{segments} segments make {segments + 1} points (got {#path})`)
	check(same(path[1], top), "the path starts at the top")
	check(same(path[#path], ground), "the path ends at the strike")
	local inside = true
	for i = 2, #path - 1 do
		local offset = path[i] - top:Lerp(ground, (i - 1) / segments)
		local sideways = math.max(math.abs(offset.X), math.abs(offset.Z))
		if sideways > wobble or math.abs(offset.Y) > wobble * 0.3 then
			inside = false
		end
	end
	check(inside, `every joint stays within the wobble ({segments} segments)`)

	local before = path[2]
	local moved = StrikeFx.restrike(path, 3, random)
	check(#moved == #path, "the restrike keeps the point count")
	check(same(moved[1], top) and same(moved[#moved], ground), "the restrike keeps both ends")
	local close, changed = true, false
	for i = 2, #path - 1 do
		local offset = moved[i] - path[i]
		if math.abs(offset.X) > 3 or math.abs(offset.Z) > 3 then
			close = false
		end
		if offset.Magnitude > 1e-6 then
			changed = true
		end
	end
	check(close, "the restrike moves each joint only a little")
	check(changed, "the restrike path is a little different")
	check(same(path[2], before), "the original path is left as it was")
end

if failures > 0 then
	error(`{failures} strike effect checks failed`)
end
print("strike effect checks passed")
