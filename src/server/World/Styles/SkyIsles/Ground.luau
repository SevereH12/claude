--!strict
-- SkyIsles ground: every island, headland, ridge and hanging rock point is
-- built here from chunky SmoothPlastic blocks (World/Blocks) in Map.Ground.
-- Colour carries the look: each layer of an island is one flat colour (a
-- light cap overhanging a darker soil band over alternating rock strata
-- that taper to hanging points), so overlapping pieces of one layer merge
-- into a single shape and never flicker.
--
-- Every ground part is logged on the build context, so the style can ask
-- "is this point inside land?" (waterfall lips, tether checks) and "how
-- high is the ground here?" (seating props) without reading parts back.

local ServerScriptService = game:GetService("ServerScriptService")

local World = ServerScriptService.Server.World
local Blocks = require(World.Blocks)
local WorldTypes = require(World.Types)

type Context = WorldTypes.Context

-- Colours of one island, top to bottom.
export type Tones = {
	cap: Color3, -- the light walkable top layer
	soil: Color3, -- the band under the cap
	rocks: { Color3 }, -- underside strata, alternated from the top down
	tip: Color3, -- hanging rock points
}

export type IsleOptions = {
	sides: number?, -- polygon sides (even), default 12
	soil: number?, -- soil band depth
	tiers: number?, -- underside tiers before the point (0..3)
	points: number?, -- hanging points (default 1)
}

type Shape = {
	cframe: CFrame,
	half: Vector3,
	wedge: boolean,
	center: Vector3,
	reach: number,
}

local UP = Vector3.yAxis

local Ground = {}

Ground.CAP = 1 -- cap thickness
Ground.OVERHANG = 0.6 -- how far a cap sticks out past its soil

local function logOf(ctx: Context): { Shape }
	local store = ctx :: any
	local log = store.skyGround
	if not log then
		log = {}
		store.skyGround = log
	end
	return log
end

-- Forget the logged ground (start of a build).
function Ground.install(ctx: Context)
	(ctx :: any).skyGround = {}
end

local function record(ctx: Context, part: BasePart): BasePart
	table.insert(logOf(ctx), {
		cframe = part.CFrame,
		half = part.Size / 2,
		wedge = part:IsA("WedgePart"),
		center = part.CFrame.Position,
		reach = part.Size.Magnitude / 2,
	})
	return part
end

-- Pieces ---------------------------------------------------------------------------

-- One ground block in exactly `color` (no jitter, so the pieces of one
-- layer can overlap without flickering).
function Ground.box(
	ctx: Context,
	color: Color3,
	cframe: CFrame,
	size: Vector3,
	name: string?
): BasePart
	return record(
		ctx,
		Blocks.box(
			ctx.folders.ground,
			color,
			cframe,
			size,
			{ Color = color, Name = name or "Ground" }
		)
	)
end

-- A ground wedge: tall end at its local +Z, slope falling toward -Z.
function Ground.wedge(
	ctx: Context,
	color: Color3,
	cframe: CFrame,
	size: Vector3,
	name: string?
): BasePart
	return record(
		ctx,
		Blocks.wedge(
			ctx.folders.ground,
			color,
			cframe,
			size,
			{ Color = color, Name = name or "Ground" }
		)
	)
end

-- A flat-topped regular polygon. `top` is a level CFrame at the centre of
-- its top face (its rotation sets the yaw), `apothem` the distance from
-- the centre to each flat side. An even 2k-gon is exactly the union of k
-- rectangles (2 * apothem by one side length) turned pi/k apart, so it
-- costs only sides/2 parts.
function Ground.poly(
	ctx: Context,
	color: Color3,
	top: CFrame,
	apothem: number,
	height: number,
	sides: number,
	name: string?
)
	local k = math.max(3, math.round(sides / 2))
	local side = 2 * apothem * math.tan(math.pi / (2 * k)) + 0.02
	local base = top * CFrame.new(0, -height / 2, 0)
	for i = 0, k - 1 do
		Ground.box(
			ctx,
			color,
			base * CFrame.Angles(0, i * math.pi / k, 0),
			Vector3.new(apothem * 2, height, side),
			name
		)
	end
end

-- A level rectangle sx by sz (`top` = level CFrame at the centre of its
-- top face), `height` deep, with 45 degree chamfered corners cut `chamfer`
-- studs in: two crossed boxes plus a turned square in each corner.
function Ground.rect(
	ctx: Context,
	color: Color3,
	top: CFrame,
	sx: number,
	sz: number,
	height: number,
	chamfer: number,
	name: string?
)
	local c = math.clamp(chamfer, 0, math.min(sx, sz) / 2 - 0.5)
	local mid = top * CFrame.new(0, -height / 2, 0)
	if c < 0.5 then
		Ground.box(ctx, color, mid, Vector3.new(sx, height, sz), name)
		return
	end
	Ground.box(ctx, color, mid, Vector3.new(sx, height, sz - 2 * c), name)
	Ground.box(ctx, color, mid, Vector3.new(sx - 2 * c, height, sz), name)
	local square = c * math.sqrt(2)
	for _, s in { Vector2.new(1, 1), Vector2.new(-1, 1), Vector2.new(1, -1), Vector2.new(-1, -1) } do
		Ground.box(
			ctx,
			color,
			mid
				* CFrame.new(s.X * (sx / 2 - c), 0, s.Y * (sz / 2 - c))
				* CFrame.Angles(0, math.pi / 4, 0),
			Vector3.new(square, height, square),
			name
		)
	end
end

-- An eight-point star prism (two squares, one turned 45 degrees): mounds,
-- dunes and crowns in the style's compass motif.
function Ground.star(
	ctx: Context,
	color: Color3,
	top: CFrame,
	size: number,
	height: number,
	name: string?
)
	local mid = top * CFrame.new(0, -height / 2, 0)
	Ground.box(ctx, color, mid, Vector3.new(size, height, size), name)
	Ground.box(
		ctx,
		color,
		mid * CFrame.Angles(0, math.pi / 4, 0),
		Vector3.new(size, height, size),
		name
	)
end

-- Turns a cube so one corner points straight down.
local ON_CORNER = CFrame.fromAxisAngle(Vector3.new(-1, 0, 1).Unit, math.acos(1 / math.sqrt(3)))

-- A hanging rock point: two shrinking blocks turned 45 degrees apart and a
-- cube balanced on its corner for the tip, hanging from `top` about
-- `length` studs. Returns the very tip.
function Ground.point(
	ctx: Context,
	color: Color3,
	top: Vector3,
	width: number,
	length: number,
	yaw: number
): Vector3
	local w2 = width * 0.6
	local t = w2 * 0.85
	local drop = t * math.sqrt(3) / 2
	local body = math.max(length - drop, 2)
	local h1, h2 = body * 0.55, body * 0.45
	local turn = CFrame.Angles(0, yaw, 0)
	Ground.box(
		ctx,
		color,
		CFrame.new(top - UP * (h1 / 2)) * turn,
		Vector3.new(width, h1, width),
		"Rock"
	)
	local second = top - UP * (h1 + h2 / 2)
	Ground.box(
		ctx,
		color,
		CFrame.new(second) * turn * CFrame.Angles(0, math.pi / 4, 0),
		Vector3.new(w2, h2, w2),
		"Rock"
	)
	local tipAt = top - UP * (h1 + h2)
	Ground.box(ctx, color, CFrame.new(tipAt) * turn * ON_CORNER, Vector3.new(t, t, t), "Rock")
	return tipAt - UP * drop
end

-- A walkable ramp from `low` up to `high` (centre line of the slope).
function Ground.ramp(
	ctx: Context,
	color: Color3,
	low: Vector3,
	high: Vector3,
	width: number
): BasePart
	return record(
		ctx,
		Blocks.ramp(ctx.folders.ground, color, low, high, width, { Color = color, Name = "Ramp" })
	)
end

-- A see-through water sheet (pool, spill channel) whose surface is `top`
-- (a level CFrame at its centre). Not collidable, not hit by raycasts.
function Ground.water(
	parent: Instance,
	color: Color3,
	top: CFrame,
	size: Vector2,
	name: string
): BasePart
	local part = Blocks.water(parent, color, top.Position, size, top.Position.Y, { Name = name })
	part.Size = Vector3.new(size.X, 0.3, size.Y)
	part.CFrame = top * CFrame.new(0, -0.15, 0)
	return part
end

-- Islands --------------------------------------------------------------------------

-- Tapering underside under a polygon whose bottom face is `top`: `tiers`
-- shrinking polygons in alternating rock tones, then a hanging point.
-- Returns the tip.
function Ground.taperPoly(
	ctx: Context,
	tones: Tones,
	top: CFrame,
	radius: number,
	depth: number,
	sides: number,
	tiers: number,
	points: number?
): Vector3
	local rng = ctx.rng
	if depth < 3 then
		return top.Position
	end
	local at = top
	local apothem = radius
	local used = 0
	local tierDepth = if tiers > 0 then depth * 0.68 else 0
	for k = 1, tiers do
		local share = (0.8 + 0.3 * k) / (tiers * 0.8 + 0.15 * tiers * (tiers + 1))
		local height = tierDepth * share
		local a = radius * (1 - 0.68 * k / (tiers + 0.6))
		local shift = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) * radius * 0.05
		at = CFrame.new(at.Position + shift) * at.Rotation
		Ground.poly(
			ctx,
			tones.rocks[(k - 1) % #tones.rocks + 1],
			at,
			a,
			height,
			if a >= 10 then math.min(sides, 12) else 8,
			"Rock"
		)
		at *= CFrame.new(0, -height, 0)
		used += height
		apothem = a
	end
	local tip = Ground.point(
		ctx,
		tones.tip,
		at.Position,
		math.min(apothem * 1.1, 14),
		depth - used,
		rng:NextNumber(0, math.pi)
	)
	-- smaller points hanging off the bigger tier above
	for _ = 2, points or 1 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local spot = top.Position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius * 0.62
		Ground.point(ctx, tones.tip, spot, radius * 0.22, depth * 0.35, angle)
	end
	return tip
end

-- A floating polygon island whose walkable top is `top` (a level CFrame):
-- a light cap overhanging a soil band, a tapering underside and a hanging
-- rock point. Returns the tip of the point.
function Ground.isle(
	ctx: Context,
	tones: Tones,
	top: CFrame,
	radius: number,
	depth: number,
	options: IsleOptions?
): Vector3
	local o: IsleOptions = options or {}
	local sides = o.sides or 12
	local soil = o.soil or math.clamp(radius * 0.4, 3, 7)
	Ground.poly(ctx, tones.cap, top, radius + Ground.OVERHANG, Ground.CAP, sides, "Cap")
	local soilTop = top * CFrame.new(0, -Ground.CAP, 0)
	Ground.poly(ctx, tones.soil, soilTop, radius, soil, sides, "Soil")
	return Ground.taperPoly(
		ctx,
		tones,
		soilTop * CFrame.new(0, -soil, 0),
		radius,
		depth - Ground.CAP - soil,
		sides,
		o.tiers or (if radius >= 14 then 2 else 1),
		o.points
	)
end

-- Tapering underside below a level rectangle (`top` = level CFrame at the
-- centre of the underside's top, hx/hz its half extents): a chamfered
-- slab, a slab with stepped corners, then two polygons, shrinking downward in alternating rock tones,
-- with `points` hanging rock points. Returns spots on the exposed bottom
-- faces (for hanging crystals).
function Ground.taperRect(
	ctx: Context,
	tones: Tones,
	top: CFrame,
	hx: number,
	hz: number,
	depth: number,
	points: number
): { Vector3 }
	local rng = ctx.rng
	local small = math.min(hx, hz)
	local tierDepth = depth * 0.7
	local shares = { 0.2, 0.24, 0.26, 0.3 }
	local scales = { 0.88, 0.7, 0.5, 0.3 }
	local at = top
	local hangs: { Vector3 } = {}
	local last = small
	for k = 1, 4 do
		local height = tierDepth * shares[k]
		local s = scales[k]
		local color = tones.rocks[(k - 1) % #tones.rocks + 1]
		local shift = Vector3.new(rng:NextNumber(-1, 1) * hx, 0, rng:NextNumber(-1, 1) * hz) * 0.04
		at = at * CFrame.new(shift)
		if k == 1 then
			Ground.rect(ctx, color, at, hx * 2 * s, hz * 2 * s, height, small * s * 0.4, "Rock")
		elseif k == 2 then
			-- stepped corners: two crossed boxes
			local notch = small * s * 0.3
			Ground.box(
				ctx,
				color,
				at * CFrame.new(0, -height / 2, 0),
				Vector3.new(hx * 2 * s, height, hz * 2 * s - 2 * notch),
				"Rock"
			)
			Ground.box(
				ctx,
				color,
				at * CFrame.new(0, -height / 2, 0),
				Vector3.new(hx * 2 * s - 2 * notch, height, hz * 2 * s),
				"Rock"
			)
		else
			Ground.poly(ctx, color, at, small * s, height, if k == 3 then 12 else 8, "Rock")
		end
		-- the bottom of this tier shows round the smaller one under it
		local nextScale = scales[k + 1]
		if nextScale then
			local u = rng:NextNumber(-0.5, 0.5)
			local side = if rng:NextNumber() < 0.5 then -1 else 1
			local reach = (s + nextScale) / 2 * 0.95
			local l = if rng:NextNumber() < 0.5
				then Vector3.new(side * small * reach, -height, u * small * nextScale)
				else Vector3.new(u * small * nextScale, -height, side * small * reach)
			table.insert(hangs, at:PointToWorldSpace(l))
		end
		at *= CFrame.new(0, -height, 0)
		last = small * s
	end
	Ground.point(
		ctx,
		tones.tip,
		at.Position,
		last * 1.1,
		depth - tierDepth,
		rng:NextNumber(0, math.pi)
	)
	-- extra points under the second tier, off to the sides
	for p = 2, points do
		local angle = (p - 1) / math.max(points - 1, 1) * math.pi * 2 + rng:NextNumber(-0.5, 0.5)
		local reach = small * 0.6
		local spot = (top * CFrame.new(0, -tierDepth * 0.44, 0)):PointToWorldSpace(
			Vector3.new(math.cos(angle) * reach, 0, math.sin(angle) * reach)
		)
		Ground.point(ctx, tones.tip, spot, small * 0.16, depth * 0.3, angle)
	end
	return hangs
end

-- Queries --------------------------------------------------------------------------

local function clip(lo: number, hi: number, p: number, d: number, h: number): (number, number)
	if math.abs(d) < 1e-9 then
		if math.abs(p) > h then
			return 1, 0
		end
		return lo, hi
	end
	local t1, t2 = (-h - p) / d, (h - p) / d
	if t1 > t2 then
		t1, t2 = t2, t1
	end
	return math.max(lo, t1), math.min(hi, t2)
end

-- The solid span [lo, hi] of a shape along the vertical line through (x, z).
local function span(shape: Shape, x: number, z: number): (number?, number?)
	local a = shape.cframe:PointToObjectSpace(Vector3.new(x, 0, z))
	local b = shape.cframe:VectorToObjectSpace(UP)
	local h = shape.half
	local lo, hi = -math.huge, math.huge
	lo, hi = clip(lo, hi, a.X, b.X, h.X)
	lo, hi = clip(lo, hi, a.Y, b.Y, h.Y)
	lo, hi = clip(lo, hi, a.Z, b.Z, h.Z)
	if shape.wedge then
		-- solid under the slope: y * hz - z * hy <= 0
		local A = a.Y * h.Z - a.Z * h.Y
		local B = b.Y * h.Z - b.Z * h.Y
		if math.abs(B) < 1e-9 then
			if A > 0 then
				return nil, nil
			end
		elseif B > 0 then
			hi = math.min(hi, -A / B)
		else
			lo = math.max(lo, -A / B)
		end
	end
	if lo > hi then
		return nil, nil
	end
	return lo, hi
end

-- Height of the ground you'd land on dropping from `p` (anything whose
-- bottom is above p.Y + `reach` is ignored), or nil over thin air.
function Ground.topAt(ctx: Context, p: Vector3, reach: number?): number?
	local limit = p.Y + (reach or 0.5)
	local best: number? = nil
	for _, shape in logOf(ctx) do
		local dx, dz = shape.center.X - p.X, shape.center.Z - p.Z
		if dx * dx + dz * dz <= shape.reach * shape.reach then
			local lo, hi = span(shape, p.X, p.Z)
			if lo and hi and lo <= limit and (best == nil or hi > best) then
				best = hi
			end
		end
	end
	return best
end

-- Is p inside ground (every piece grown by `pad`, default 0.5)?
function Ground.solidAt(ctx: Context, p: Vector3, pad: number?): boolean
	local grow = pad or 0.5
	for _, shape in logOf(ctx) do
		local r = shape.reach + grow
		if (shape.center - p).Magnitude <= r then
			local l = shape.cframe:PointToObjectSpace(p)
			local h = shape.half + Vector3.one * grow
			if math.abs(l.X) <= h.X and math.abs(l.Y) <= h.Y and math.abs(l.Z) <= h.Z then
				if not shape.wedge or (l.Y + h.Y) / (2 * h.Y) <= (l.Z + h.Z) / (2 * h.Z) + 0.05 then
					return true
				end
			end
		end
	end
	return false
end

-- Is the whole column under p (to `depth` studs down) free of ground?
function Ground.clearBelow(ctx: Context, p: Vector3, depth: number, pad: number?): boolean
	local d = 0
	while d <= depth do
		if Ground.solidAt(ctx, p - UP * d, pad) then
			return false
		end
		d += 3
	end
	return true
end

-- Point on a cubic Bezier.
function Ground.bezier(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local u = 1 - t
	return p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t)
end

-- How many of `samples` points along the curve are inside ground.
function Ground.buried(
	ctx: Context,
	p0: Vector3,
	p1: Vector3,
	p2: Vector3,
	p3: Vector3,
	samples: number
): number
	local n = 0
	for i = 1, samples - 1 do
		if Ground.solidAt(ctx, Ground.bezier(p0, p1, p2, p3, i / samples), 0.25) then
			n += 1
		end
	end
	return n
end

return Ground
