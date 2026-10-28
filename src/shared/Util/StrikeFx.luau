--!strict
-- Lightning effects as pure maths (tools/harness/test_strikefx.luau tests
-- this). Controllers/StrikeFX asks it how much of a strike to draw, where
-- the bolt's jagged path goes, how bright the bolt is as it flickers and
-- fades, and which strike lights to keep. The numbers are in
-- Config.STRIKE_FX.

local Config = require(script.Parent.Parent.Config)

local StrikeFx = {}

-- How much of a strike to draw: everything, a simple version (the bolt
-- with no branches, sparks or light) or nothing at all.
export type Level = "full" | "simple" | "none"

export type StrikeView = {
	distance: number, -- studs from your camera to the strike
	sameWorld: boolean, -- it landed in the world you're in
	mine: boolean, -- it's yours: you caught it, it's your balloon bolt or it's in your zone
	setting: string, -- SETTINGS > Graphics > Others' lightning: "Off", "Simple" or "Full"
}

local RANK: { [string]: number } = { none = 0, simple = 1, full = 2 }
local SETTING_LEVEL: { [string]: Level } = { Off = "none", Simple = "simple", Full = "full" }

-- The smaller of two levels.
local function lower(a: Level, b: Level): Level
	return if RANK[a] <= RANK[b] then a else b
end

-- Your own strikes are always full. Another world's are none (the caller
-- skips their sound too). Others' past drawDistance are none, past
-- simpleDistance at most simple, and the Others' lightning setting can only
-- lower that.
function StrikeFx.level(view: StrikeView): Level
	if view.mine then
		return "full"
	end
	if not view.sameWorld then
		return "none"
	end
	local fx = Config.STRIKE_FX
	local byDistance: Level = "full"
	if view.distance > fx.drawDistance then
		byDistance = "none"
	elseif view.distance > fx.simpleDistance then
		byDistance = "simple"
	end
	return lower(byDistance, SETTING_LEVEL[view.setting] or "full")
end

-- A random sideways nudge of up to `amount` studs (less up and down).
local function jitter(amount: number, random: Random): Vector3
	return Vector3.new(
		random:NextNumber(-amount, amount),
		random:NextNumber(-amount, amount) * 0.3,
		random:NextNumber(-amount, amount)
	)
end

-- Jagged path from a to b in `segments` straight pieces (segments + 1
-- points): the straight line plus sideways jitter of up to `wobble` studs
-- that shrinks toward the end. It starts exactly at a and ends exactly at b.
function StrikeFx.jaggedPath(
	a: Vector3,
	b: Vector3,
	segments: number,
	wobble: number,
	random: Random
): { Vector3 }
	local points = { a }
	for i = 1, segments - 1 do
		local t = i / segments
		table.insert(points, a:Lerp(b, t) + jitter(wobble * (1 - t * 0.7), random))
	end
	table.insert(points, b)
	return points
end

-- The same path a little different, for the restrike: every point but the
-- two ends moves up to `amount` studs.
function StrikeFx.restrike(points: { Vector3 }, amount: number, random: Random): { Vector3 }
	local moved = table.clone(points)
	for i = 2, #points - 1 do
		moved[i] = points[i] + jitter(amount, random)
	end
	return moved
end

-- When a bolt restrikes (comes back to full after its dip), in seconds.
function StrikeFx.restrikeTime(): number
	local fx = Config.STRIKE_FX
	return fx.dipAt + fx.dipFor
end

-- How bright a bolt is `elapsed` seconds after it appears (1 = full, 0 =
-- gone), or nil once it has faded out. Like a real restrike: full, down to
-- `dim` for one beat, full again, then a fade. It never hides completely
-- before the fade. `calm` (Reduce flashing): just a slow fade.
function StrikeFx.brightness(elapsed: number, calm: boolean): number?
	local fx = Config.STRIKE_FX
	local fadeFrom, fadeFor = 0, fx.calmFade
	if not calm then
		if elapsed < fx.dipAt then
			return 1
		elseif elapsed < StrikeFx.restrikeTime() then
			return fx.dim
		end
		fadeFrom, fadeFor = StrikeFx.restrikeTime() + fx.hold, fx.fade
		if elapsed < fadeFrom then
			return 1
		end
	end
	local t = (elapsed - fadeFrom) / fadeFor
	if t >= 1 then
		return nil
	end
	return (1 - t) ^ 2 -- eases out: quick at first, then gently to nothing
end

return StrikeFx
