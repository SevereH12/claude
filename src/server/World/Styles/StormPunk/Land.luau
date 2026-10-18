--!strict
-- Block-built land for StormPunk: islands, strata cliffs, shore slopes,
-- basalt columns, ridges and arches made of chunky SmoothPlastic parts
-- (World/Blocks) in ctx.folders.ground. No terrain anywhere.
--
-- Shapes: a regular polygon with an even number of sides, built from
-- sides/2 overlapping boxes that each span two opposite faces (a 12-gon
-- costs 6 parts, a hex column 3), or a rectangle (1 part). A shape is
-- computed once and built at several heights, grown or leaned, so strata
-- follow the same outline. All boxes of one shape share one colour, and
-- shapes that meet at the same height share a jitter key, so overlapping
-- tops never flicker.
--
-- Every build can take a Guard (Geo.guard): a shape whose outline would
-- rise above a connector deck or into another zone is shrunk or skipped.

local ServerScriptService = game:GetService("ServerScriptService")

local World = ServerScriptService.Server.World
local Blocks = require(World.Blocks)
local WorldTypes = require(World.Types)

type Context = WorldTypes.Context

export type Shape = {
	center: Vector3, -- y ignored
	rotation: CFrame, -- yaw only
	sides: number, -- even; 0 = rectangle
	apothem: number, -- polygon: centre to the middle of a face
	half: Vector2, -- rectangle: half-size along its local X and Z
}
export type Layer = { shape: Shape, top: number }
-- (x, z, radius, top) -> may ground stand here?
export type Guard = (x: number, z: number, r: number, top: number) -> boolean
-- One stratum of a stack, listed from the top down.
export type Band = {
	color: Color3,
	height: number?, -- nil (or the last band): down to the stack's bottom
	grow: number?, -- wider than the band above by this much (negative: overhang)
	lean: Vector2?, -- rectangles: extra growth toward local +/-X and +/-Z
	cap: Color3?, -- a 1-stud cap of this colour, overhanging a little
	key: Vector3?, -- colour jitter key (see Land.SHARED)
}

local Land = {}

local UP = Vector3.new(0, 1, 0)

-- Shore slopes, comfortably under the 28-degree walkable limit.
Land.SHORE_ANGLE = math.rad(24)
-- Jitter key shared by every beach and apron top: beaches that merge at the
-- same height are exactly one colour, so their overlaps never flicker.
Land.SHARED = Vector3.zero
Land.CAP = 1
Land.OVERHANG = 0.4

-- Shapes ----------------------------------------------------------------------------

function Land.poly(center: Vector3, apothem: number, sides: number, yaw: number?): Shape
	local n = math.max(4, sides + sides % 2)
	return {
		center = Vector3.new(center.X, 0, center.Z),
		rotation = CFrame.Angles(0, yaw or 0, 0),
		sides = n,
		apothem = apothem,
		half = Vector2.zero,
	}
end

-- A rectangle centred on `frame` (any yaw), `half` along its local X and Z.
function Land.rect(frame: CFrame, half: Vector2): Shape
	local p = frame.Position
	return {
		center = Vector3.new(p.X, 0, p.Z),
		rotation = frame.Rotation,
		sides = 0,
		apothem = math.min(half.X, half.Y),
		half = half,
	}
end

function Land.grown(shape: Shape, amount: number): Shape
	local copy = table.clone(shape)
	if shape.sides == 0 then
		copy.half =
			Vector2.new(math.max(shape.half.X + amount, 0.5), math.max(shape.half.Y + amount, 0.5))
		copy.apothem = math.min(copy.half.X, copy.half.Y)
	else
		copy.apothem = math.max(shape.apothem + amount, 0.5)
	end
	return copy
end

function Land.scaled(shape: Shape, factor: number): Shape
	local copy = table.clone(shape)
	copy.apothem = shape.apothem * factor
	copy.half = shape.half * factor
	return copy
end

-- A rectangle stretched toward one side: +lean.X widens its +X side (or
-- -X when negative), +lean.Y its +Z side. Polygons are returned as they are.
function Land.leaned(shape: Shape, lean: Vector2): Shape
	if shape.sides ~= 0 then
		return shape
	end
	local copy = table.clone(shape)
	copy.center = shape.center
		+ shape.rotation:VectorToWorldSpace(Vector3.new(lean.X / 2, 0, lean.Y / 2))
	copy.half = shape.half + Vector2.new(math.abs(lean.X) / 2, math.abs(lean.Y) / 2)
	copy.apothem = math.min(copy.half.X, copy.half.Y)
	return copy
end

-- Centre to the farthest corner.
function Land.radius(shape: Shape): number
	if shape.sides == 0 then
		return shape.half.Magnitude
	end
	return shape.apothem / math.cos(math.pi / shape.sides)
end

local function faceNormal(angle: number): Vector3
	return Vector3.new(-math.sin(angle), 0, -math.cos(angle))
end

-- Corners in the shape's own frame, in order round the edge.
local function localCorners(shape: Shape): { Vector3 }
	if shape.sides == 0 then
		local hx, hz = shape.half.X, shape.half.Y
		return {
			Vector3.new(-hx, 0, -hz),
			Vector3.new(hx, 0, -hz),
			Vector3.new(hx, 0, hz),
			Vector3.new(-hx, 0, hz),
		}
	end
	local out: { Vector3 } = {}
	local r = Land.radius(shape)
	for j = 0, shape.sides - 1 do
		table.insert(out, faceNormal((j + 0.5) * 2 * math.pi / shape.sides) * r)
	end
	return out
end

-- World points round the edge (y = 0), about `spacing` studs apart.
function Land.outline(shape: Shape, spacing: number): { Vector3 }
	local corners = localCorners(shape)
	local out: { Vector3 } = {}
	for i, a in corners do
		local b = corners[i % #corners + 1]
		local steps = math.max(1, math.ceil((b - a).Magnitude / spacing))
		for k = 0, steps - 1 do
			table.insert(
				out,
				shape.center + shape.rotation:VectorToWorldSpace(a:Lerp(b, k / steps))
			)
		end
	end
	return out
end

-- Is a point (horizontally) inside the shape shrunk by `shrink` (negative:
-- grown)?
function Land.contains(shape: Shape, position: Vector3, shrink: number?): boolean
	local m = shrink or 0
	local d = shape.rotation:VectorToObjectSpace(
		Vector3.new(position.X - shape.center.X, 0, position.Z - shape.center.Z)
	)
	if shape.sides == 0 then
		return math.abs(d.X) <= shape.half.X - m and math.abs(d.Z) <= shape.half.Y - m
	end
	local limit = shape.apothem - m
	if limit <= 0 then
		return false
	end
	for j = 0, shape.sides - 1 do
		if d:Dot(faceNormal(j * 2 * math.pi / shape.sides)) > limit then
			return false
		end
	end
	return true
end

function Land.containsAny(shapes: { Shape }, position: Vector3, shrink: number?): boolean
	for _, shape in shapes do
		if Land.contains(shape, position, shrink) then
			return true
		end
	end
	return false
end

-- Height of the ground under a point from `layers`, or nil. With a positive
-- `shrink` the spot must be settled: well inside a layer at that height and
-- not hugging the foot of anything higher, so props never sink into a cliff
-- or hang off an edge. A negative `shrink` grows every layer instead.
function Land.surfaceAt(layers: { Layer }, position: Vector3, shrink: number?): number?
	local m = shrink or 0
	local grow = math.min(m, 0)
	local best: number? = nil
	for _, layer in layers do
		if
			Land.contains(layer.shape, position, grow)
			and (best == nil or layer.top > (best :: number))
		then
			best = layer.top
		end
	end
	if best == nil or m <= 0 then
		return best
	end
	local settled = false
	for _, layer in layers do
		if layer.top == best and Land.contains(layer.shape, position, m) then
			settled = true
		elseif layer.top > (best :: number) and Land.contains(layer.shape, position, -m) then
			return nil
		end
	end
	return if settled then best else nil
end

-- Guards -----------------------------------------------------------------------------

-- May the whole shape rise to `top`? Its outline is sampled every few studs
-- (every deck or footprint that reaches into it crosses its edge).
function Land.allows(shape: Shape, top: number, guard: Guard?): boolean
	if not guard then
		return true
	end
	for _, p in Land.outline(shape, 7) do
		if not guard(p.X, p.Z, 2, top) then
			return false
		end
	end
	return true
end

-- The shape, or the biggest shrunk copy of it (down to `minScale`) that the
-- guard allows at `top`; nil if none fits.
function Land.fit(shape: Shape, top: number, guard: Guard?, minScale: number?): Shape?
	for _, f in { 1, 0.9, 0.8, 0.7, 0.6, 0.5 } do
		if f < (minScale or 0.6) - 0.001 then
			break
		end
		local candidate = Land.scaled(shape, f)
		if Land.allows(candidate, top, guard) then
			return candidate
		end
	end
	return nil
end

-- Land registry: every island's outer shapes, so scenery added later
-- (islets, sea stacks) keeps to open water.
local registry: { [Context]: { Shape } } = setmetatable({}, { __mode = "k" }) :: any

function Land.register(ctx: Context, shape: Shape)
	local list = registry[ctx]
	if not list then
		list = {}
		registry[ctx] = list
	end
	table.insert(list, shape)
end

function Land.registered(ctx: Context): { Shape }
	return registry[ctx] or {}
end

-- Is a point at least `margin` studs from every registered island?
function Land.isOpenWater(ctx: Context, position: Vector3, margin: number): boolean
	return not Land.containsAny(Land.registered(ctx), position, -margin)
end

-- Building -----------------------------------------------------------------------------

-- The shape as a solid prism from `bottom` up to `top`, one colour (jittered
-- by `key`, default the shape's centre at that height).
function Land.prism(
	parent: Instance,
	color: Color3,
	shape: Shape,
	top: number,
	bottom: number,
	key: Vector3?
): { BasePart }
	local parts: { BasePart } = {}
	local height = top - bottom
	if height <= 0.01 then
		return parts
	end
	local paint = Blocks.jitter(color, key or Vector3.new(shape.center.X, top, shape.center.Z))
	local base = CFrame.new(shape.center.X, top - height / 2, shape.center.Z) * shape.rotation
	if shape.sides == 0 then
		local part =
			Blocks.box(parent, paint, base, Vector3.new(shape.half.X * 2, height, shape.half.Y * 2))
		part.Color = paint
		table.insert(parts, part)
		return parts
	end
	local n = shape.sides
	local faceLength = 2 * shape.apothem * math.tan(math.pi / n)
	for i = 0, n / 2 - 1 do
		local part = Blocks.box(
			parent,
			paint,
			base * CFrame.Angles(0, i * 2 * math.pi / n, 0),
			Vector3.new(faceLength, height, 2 * shape.apothem)
		)
		part.Color = paint
		table.insert(parts, part)
	end
	return parts
end

-- Strata: `bands` from the top down under `top`, each one `grow` wider (or
-- leaned) than the band above, the last reaching `bottom`. Where the guard
-- refuses a wider band it keeps the band above's outline (a sheer face).
-- `key` (shared by every lobe of one island) keeps equal-height tops one
-- colour. Returns each band's outline and top, for Land.surfaceAt.
function Land.stack(
	parent: Instance,
	base: Shape,
	top: number,
	bottom: number,
	bands: { Band },
	key: Vector3?,
	guard: Guard?
): { Layer }
	local layers: { Layer } = {}
	local shape = base
	local y = top
	for i, band in bands do
		if y <= bottom + 0.01 then
			break
		end
		local h = if band.height and i < #bands
			then math.min(band.height, y - bottom)
			else y - bottom
		local candidate = Land.grown(shape, band.grow or 0)
		local lean = band.lean
		if lean then
			local leaned = Land.leaned(candidate, lean)
			if Land.allows(leaned, y, guard) then
				candidate = leaned
			end
		end
		if i > 1 and not Land.allows(candidate, y, guard) then
			candidate = shape
		end
		shape = candidate
		local bandKey = band.key or key
		local function keyAt(height: number): Vector3?
			return if bandKey then bandKey + UP * height else nil
		end
		local cap = band.cap
		if cap then
			local capH = math.min(Land.CAP, h)
			local capShape = Land.grown(shape, Land.OVERHANG)
			Land.prism(parent, cap, capShape, y, y - capH, keyAt(y))
			Land.prism(parent, band.color, shape, y - capH, y - h, keyAt(y - capH))
			table.insert(layers, { shape = capShape, top = y })
		else
			Land.prism(parent, band.color, shape, y, y - h, keyAt(y))
			table.insert(layers, { shape = shape, top = y })
		end
		y -= h
	end
	return layers
end

-- Walkable shore round a polygon: one wedge per face from `top` at the edge
-- down to `bottom` at Land.SHORE_ANGLE. Each wedge is a little longer than
-- its face so neighbours meet above the water. Faces whose slope would run
-- onto other land (`cover`) are skipped. Returns the parts.
function Land.skirt(
	parent: Instance,
	color: Color3,
	shape: Shape,
	top: number,
	bottom: number,
	cover: { Shape }?
): { BasePart }
	local parts: { BasePart } = {}
	if shape.sides == 0 then
		return parts
	end
	local rise = top - bottom
	local run = rise / math.tan(Land.SHORE_ANGLE)
	local n = shape.sides
	local half = math.tan(math.pi / n)
	local length = 2 * shape.apothem * half + run * half
	local base = CFrame.new(shape.center.X, bottom + rise / 2, shape.center.Z) * shape.rotation
	for j = 0, n - 1 do
		-- the face frame looks out of face j; the wedge's tall end faces in
		local face = base * CFrame.Angles(0, j * 2 * math.pi / n, 0)
		local foot = shape.center + face.LookVector * (shape.apothem + run * 0.6)
		if not (cover and Land.containsAny(cover, foot)) then
			table.insert(
				parts,
				Blocks.wedge(
					parent,
					color,
					face * CFrame.new(0, 0, -(shape.apothem + run / 2 - 0.2)),
					Vector3.new(length, rise, run),
					{ Name = "Shore" }
				)
			)
		end
	end
	return parts
end

-- A basalt-style column: a hex prism from `bottom` to `top` in colors[1];
-- with two colours its top third is a narrower band of colors[2], and with
-- a cap a grass cap crowns it. nil (nothing built) if the guard refuses it.
function Land.column(
	parent: Instance,
	at: Vector3,
	bottom: number,
	top: number,
	apothem: number,
	colors: { Color3 },
	cap: Color3?,
	yaw: number,
	guard: Guard?
): Shape?
	local shape = Land.poly(at, apothem, 6, yaw)
	if top - bottom < 1 or not Land.allows(Land.grown(shape, 0.6), top, guard) then
		return nil
	end
	local bands: { Band } = {}
	if #colors > 1 then
		table.insert(bands, {
			color = colors[2],
			height = math.clamp((top - bottom) * 0.3, 2, 6),
			cap = cap,
		})
		table.insert(bands, { color = colors[1], grow = 0.6 })
	else
		table.insert(bands, { color = colors[1], cap = cap })
	end
	Land.stack(parent, shape, top, bottom, bands)
	return Land.grown(shape, 0.6)
end

-- A cluster of hex columns (a sea stack, a headland, a crag): the main
-- column at `center` reaching `top`, `count - 1` shorter ones leaning on it,
-- alternating `colors`. The main column gets the cap. Returns the outlines.
function Land.cluster(
	parent: Instance,
	rng: Random,
	center: Vector3,
	radius: number,
	bottom: number,
	top: number,
	colors: { Color3 },
	cap: Color3?,
	count: number,
	guard: Guard?
): { Shape }
	local shapes: { Shape } = {}
	local main = radius * 0.6
	local first = Land.column(
		parent,
		center,
		bottom,
		top,
		main,
		{ colors[1] },
		cap,
		rng:NextNumber(0, math.pi),
		guard
	)
	if not first then
		return shapes
	end
	table.insert(shapes, first)
	local start = rng:NextNumber(0, math.pi * 2)
	for i = 1, count - 1 do
		local a = start + i * 2 * math.pi / math.max(count - 1, 1) + rng:NextNumber(-0.3, 0.3)
		local r = radius * rng:NextNumber(0.32, 0.45)
		local p = center + Vector3.new(math.sin(a), 0, -math.cos(a)) * (main + r * 0.75)
		local shape = Land.column(
			parent,
			p,
			bottom,
			bottom + (top - bottom) * rng:NextNumber(0.45, 0.8),
			r,
			{ colors[i % #colors + 1] },
			nil,
			rng:NextNumber(0, math.pi),
			guard
		)
		if shape then
			table.insert(shapes, shape)
		end
	end
	return shapes
end

-- A rocky ridge from a to b (ground points; Y ignored): a chain of hex
-- columns of very different sizes whose tops rise from h0 to h1 with noise,
-- alternating colours, the tallest capped. Returns the column outlines (for
-- keeping props off them).
function Land.ridge(
	parent: Instance,
	a: Vector3,
	b: Vector3,
	h0: number,
	h1: number,
	width: number,
	rng: Random,
	colors: { Color3 },
	cap: Color3?,
	guard: Guard?,
	maxCount: number,
	bottom: number
): { Shape }
	local out: { Shape } = {}
	local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local length = flat.Magnitude
	if length < 1 then
		return out
	end
	local count = math.clamp(math.floor(length / (width * 0.8)), 2, math.max(maxCount, 2))
	local side = flat.Unit:Cross(UP)
	local peak = rng:NextInteger(1, count)
	for k = 0, count - 1 do
		local f = (k + rng:NextNumber(0.2, 0.8)) / count
		local p = a:Lerp(b, f) + side * (rng:NextNumber(-0.3, 0.3) * width)
		local big = k + 1 == peak
		local apothem = width
			* (if big then rng:NextNumber(0.4, 0.5) else rng:NextNumber(0.26, 0.36))
		local top = h0 + (h1 - h0) * f + rng:NextNumber(-3, 3) + (if big then 6 else 0)
		top = math.floor(top / 2 + 0.5) * 2
		local shape = Land.column(
			parent,
			p,
			bottom,
			top,
			apothem,
			{ colors[k % #colors + 1] },
			if big then cap else nil,
			rng:NextNumber(0, math.pi),
			guard
		)
		if shape then
			table.insert(out, shape)
		end
	end
	return out
end

-- A pinnacle of hex tiers from `bottom` to `top`, narrowing from `radius`
-- to `topRadius` and twisting a little per tier, colours alternating.
-- Nothing is built (nil) unless every tier passes the guard.
function Land.spire(
	parent: Instance,
	at: Vector3,
	bottom: number,
	top: number,
	radius: number,
	topRadius: number,
	tiers: number,
	colors: { Color3 },
	yaw: number,
	guard: Guard?
): Shape?
	local h = (top - bottom) / tiers
	local shapes: { Shape } = {}
	for i = 1, tiers do
		local t = if tiers > 1 then (i - 1) / (tiers - 1) else 0
		local shape = Land.poly(at, radius + (topRadius - radius) * t, 6, yaw + i * 0.35)
		if not Land.allows(shape, bottom + i * h, guard) then
			return nil
		end
		table.insert(shapes, shape)
	end
	for i, shape in shapes do
		Land.prism(
			parent,
			colors[(i - 1) % #colors + 1],
			shape,
			bottom + i * h,
			bottom + (i - 1) * h
		)
	end
	return shapes[1]
end

-- Natural arch from a to b: two hex legs from `bottom` and a lintel block
-- whose top is at `top`. Nothing is built (false) unless it all fits.
function Land.arch(
	parent: Instance,
	a: Vector3,
	b: Vector3,
	bottom: number,
	top: number,
	thickness: number,
	colors: { Color3 },
	guard: Guard?
): boolean
	local legTop = top - thickness * 0.5
	local legA = Land.poly(a, thickness * 0.75, 6, 0.3)
	local legB = Land.poly(b, thickness * 0.75, 6, 1.1)
	local fa = Vector3.new(a.X, top, a.Z)
	local fb = Vector3.new(b.X, top, b.Z)
	local span = (fb - fa).Magnitude + thickness
	local lintel =
		Land.rect(CFrame.lookAt((fa + fb) / 2, fb), Vector2.new(thickness * 0.55, span / 2))
	if
		not (
			Land.allows(legA, legTop, guard)
			and Land.allows(legB, legTop, guard)
			and Land.allows(lintel, top, guard)
		)
	then
		return false
	end
	Land.prism(parent, colors[1], legA, legTop, bottom)
	Land.prism(parent, colors[1], legB, legTop, bottom)
	Land.prism(parent, colors[2] or colors[1], lintel, top, top - thickness * 0.8)
	return true
end

-- A path strip 0.2 above the ground at `groundY` from a to b (ground points),
-- on a darker edging strip a stud wider each side. Both are collidable ground.
function Land.path(
	parent: Instance,
	a: Vector3,
	b: Vector3,
	width: number,
	groundY: number,
	color: Color3,
	edging: Color3
)
	local fa = Vector3.new(a.X, groundY, a.Z)
	local fb = Vector3.new(b.X, groundY, b.Z)
	local length = (fb - fa).Magnitude
	if length < 0.5 then
		return
	end
	local frame = CFrame.lookAt((fa + fb) / 2, fb)
	Blocks.box(
		parent,
		edging,
		frame * CFrame.new(0, 0.12 - 0.3, 0),
		Vector3.new(width + 2, 0.6, length),
		{ Name = "Path" }
	)
	Blocks.box(
		parent,
		color,
		frame * CFrame.new(0, 0.2 - 0.3, 0),
		Vector3.new(width, 0.6, length),
		{ Name = "Path" }
	)
end

return Land
