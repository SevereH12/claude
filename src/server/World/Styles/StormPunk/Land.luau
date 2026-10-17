--!strict
-- Terrain landmasses for StormPunk: organic outlines with authored bays,
-- spits and points (never plain circles or rectangles), cliffs that lean
-- back band by band with strata, talus at their feet, sea stacks, ridges
-- and arches. An outline is computed once and can be filled many times at
-- different heights and materials, so strata follow the same coastline.
--
-- Every fill can take a Guard: a predicate that rejects a circle whose top
-- would rise into another zone's footprint or above a connector deck (see
-- Geo.guard). Terrain is clipped by construction; nothing is carved later.

local ServerScriptService = game:GetService("ServerScriptService")

local WorldTypes = require(ServerScriptService.Server.World.Types)

type Context = WorldTypes.Context

export type Circle = { x: number, z: number, r: number }
export type Box = { frame: CFrame, width: number, depth: number }
export type Outline = {
	box: Box?,
	circles: { Circle },
}
-- (x, z, radius, top) -> may terrain stand here?
export type Guard = (x: number, z: number, r: number, top: number) -> boolean

export type OrganicOptions = {
	edge: number, -- typical edge circle radius
	jitter: number, -- how far points push out past the rectangle
	bays: number?, -- bites taken out of the coast
	bayDepth: number?,
	spits: number?, -- tapering points reaching out
	spitLength: number?,
	-- keep features off these edges ("front" = the -Z / hub-facing edge)
	calmFront: boolean?,
}

local Land = {}

local function smooth(u: number): number
	-- 1 at u = 0 falling to 0 at |u| = 1
	local a = math.clamp(math.abs(u), 0, 1)
	local c = math.cos(a * math.pi / 2)
	return c * c
end

-- Organic coast around a rectangle (`frame` gives centre and yaw). Edge
-- circles vary from half to double `edge`, follow a slow wave plus noise,
-- and the coast gets `bays` (bites) and `spits` (tapering points) at random
-- places along it. Coverage is guaranteed: every edge circle reaches the
-- core box, so there are never holes.
function Land.organic(
	frame: CFrame,
	width: number,
	depth: number,
	rng: Random,
	opts: OrganicOptions
): Outline
	local edge = opts.edge
	local jitter = opts.jitter
	local circles: { Circle } = {}
	local hw, hd = width / 2, depth / 2
	local perimeter = 2 * (width + depth)
	local spacing = edge * 0.9
	local steps = math.max(10, math.floor(perimeter / spacing))
	spacing = perimeter / steps
	local inset = edge * 0.8
	local offset = rng:NextNumber(0, perimeter)
	local phase1, phase2 = rng:NextNumber(0, math.pi * 2), rng:NextNumber(0, math.pi * 2)
	local f1 = math.pi * 2 * rng:NextInteger(2, 3) / perimeter
	local f2 = math.pi * 2 * rng:NextInteger(5, 8) / perimeter

	-- t along the perimeter, starting at the front-left corner, clockwise
	-- seen from above: front edge (-Z), right (+X), back (+Z), left (-X)
	local function edgeAt(t: number): (number, number, number, number)
		t %= perimeter
		if t < width then
			return -hw + t, -hd, 0, -1
		elseif t < width + depth then
			return hw, -hd + (t - width), 1, 0
		elseif t < 2 * width + depth then
			return hw - (t - width - depth), hd, 0, 1
		end
		return -hw, hd - (t - 2 * width - depth), -1, 0
	end
	local function pickT(): number
		for _ = 1, 12 do
			local t = rng:NextNumber(0, perimeter)
			if not opts.calmFront or t > width + edge then
				return t
			end
		end
		return width + depth + rng:NextNumber(0, width)
	end

	local bays: { { t: number, half: number, depth: number } } = {}
	for _ = 1, opts.bays or 0 do
		table.insert(bays, {
			t = pickT(),
			half = math.max(edge * 1.6, perimeter * rng:NextNumber(0.04, 0.08)),
			depth = (opts.bayDepth or edge * 1.1) * rng:NextNumber(0.7, 1),
		})
	end
	local function bayPush(t: number): number
		local push = 0
		for _, bay in bays do
			local d = (t - bay.t + perimeter / 2) % perimeter - perimeter / 2
			push -= bay.depth * smooth(d / bay.half)
		end
		return push
	end

	for i = 0, steps - 1 do
		local t = offset + i / steps * perimeter
		local x, z, nx, nz = edgeAt(t)
		local wave = 0.6 * math.sin(t * f1 + phase1) + 0.4 * math.sin(t * f2 + phase2)
		local push = (wave * 0.6 + rng:NextNumber(-0.3, 0.3) + 0.3) * jitter + bayPush(t)
		local size = 0.5 + 1.5 * math.clamp(wave * 0.5 + 0.5 + rng:NextNumber(-0.2, 0.2), 0, 1)
		local r = edge * size
		-- always reach the core box so the coast has no holes
		r = math.max(r, push + inset + spacing * 0.45, edge * 0.5)
		local p = frame:PointToWorldSpace(Vector3.new(x + nx * push, 0, z + nz * push))
		table.insert(circles, { x = p.X, z = p.Z, r = r })
	end
	-- spits: chains of shrinking circles reaching out from the coast
	for _ = 1, opts.spits or 0 do
		local x, z, nx, nz = edgeAt(pickT())
		local length = opts.spitLength or edge * 3
		local links = 4
		local bend = rng:NextNumber(-0.35, 0.35)
		for k = 0, links - 1 do
			local f = k / (links - 1)
			local out = jitter * 0.5 + length * f
			local side = bend * length * f * f
			local px = x + nx * out - nz * side
			local pz = z + nz * out + nx * side
			local p = frame:PointToWorldSpace(Vector3.new(px, 0, pz))
			table.insert(circles, { x = p.X, z = p.Z, r = edge * (1.15 - 0.7 * f) })
		end
	end
	return {
		box = {
			frame = CFrame.new(frame.Position) * frame.Rotation,
			width = math.max(width - 2 * inset, width * 0.4),
			depth = math.max(depth - 2 * inset, depth * 0.4),
		},
		circles = circles,
	}
end

-- Irregular blob around a centre: an elongated core of two discs plus lobes
-- of very different sizes, so it never reads as a circle.
function Land.blob(
	center: Vector3,
	radius: number,
	rng: Random,
	lobes: number,
	wobble: number
): Outline
	local axis = rng:NextNumber(0, math.pi * 2)
	local ax, az = math.sin(axis), -math.cos(axis)
	local stretch = radius * rng:NextNumber(0.15, 0.3)
	local circles: { Circle } = {
		{ x = center.X + ax * stretch, z = center.Z + az * stretch, r = radius * 0.66 },
		{ x = center.X - ax * stretch, z = center.Z - az * stretch, r = radius * 0.6 },
	}
	local start = rng:NextNumber(0, math.pi * 2)
	for i = 1, lobes do
		local a = start + (i / lobes) * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local r = radius * rng:NextNumber(0.24, 0.55)
		local reach = radius - r * rng:NextNumber(0.7, 1.05) + rng:NextNumber(-1, 1) * wobble
		table.insert(circles, {
			x = center.X + math.sin(a) * reach,
			z = center.Z - math.cos(a) * reach,
			r = r,
		})
	end
	return { box = nil, circles = circles }
end

-- Box perimeter sample points (as small circles) for clipping.
local function boxSamples(box: Box, grow: number): { Circle }
	local out: { Circle } = {}
	local hw, hd = box.width / 2 + grow, box.depth / 2 + grow
	local n = 6
	for i = 0, n do
		local f = -1 + 2 * i / n
		for _, p in
			{
				Vector3.new(f * hw, 0, -hd),
				Vector3.new(f * hw, 0, hd),
				Vector3.new(-hw, 0, f * hd),
				Vector3.new(hw, 0, f * hd),
			}
		do
			local w = box.frame:PointToWorldSpace(p)
			table.insert(out, { x = w.X, z = w.Z, r = 2 })
		end
	end
	return out
end

local function shrinkBox(box: Box, keep: (Circle) -> boolean): Box?
	for _, f in { 1, 0.85, 0.7, 0.55, 0.4, 0.25 } do
		local candidate = { frame = box.frame, width = box.width * f, depth = box.depth * f }
		local ok = true
		for _, s in boxSamples(candidate, 0) do
			if not keep(s) then
				ok = false
				break
			end
		end
		if ok then
			return candidate
		end
	end
	return nil
end

-- Copy of an outline keeping only the circles `keep` accepts; the core box
-- shrinks toward its centre until its edge is accepted too.
function Land.clip(outline: Outline, keep: (Circle) -> boolean): Outline
	local circles: { Circle } = {}
	for _, c in outline.circles do
		if keep(c) then
			table.insert(circles, c)
		end
	end
	local box = outline.box
	return { box = if box then shrinkBox(box, keep) else nil, circles = circles }
end

-- Copy of an outline with every circle (and the box) grown by `amount`
-- (negative shrinks; circles that vanish are dropped).
function Land.grown(outline: Outline, amount: number): Outline
	local circles: { Circle } = {}
	for _, c in outline.circles do
		if c.r + amount > 1 then
			table.insert(circles, { x = c.x, z = c.z, r = c.r + amount })
		end
	end
	local box = outline.box
	local newBox: Box? = nil
	if box and box.width + 2 * amount > 2 and box.depth + 2 * amount > 2 then
		newBox = {
			frame = box.frame,
			width = box.width + 2 * amount,
			depth = box.depth + 2 * amount,
		}
	end
	return { box = newBox, circles = circles }
end

local function fillBox(
	ctx: Context,
	box: Box,
	bottomY: number,
	topY: number,
	material: Enum.Material,
	grow: number,
	guard: Guard?
)
	local h = topY - bottomY
	if guard then
		for _, s in boxSamples(box, grow) do
			if not guard(s.x, s.z, 1, topY) then
				return
			end
		end
	end
	local p = box.frame.Position
	ctx.terrain:FillBlock(
		CFrame.new(p.X, (topY + bottomY) / 2, p.Z) * box.frame.Rotation,
		Vector3.new(box.width + 2 * grow, h, box.depth + 2 * grow),
		material
	)
end

-- Fills the outline between two heights. `grow` widens it.
function Land.fill(
	ctx: Context,
	outline: Outline,
	bottomY: number,
	topY: number,
	material: Enum.Material,
	grow: number?,
	guard: Guard?
)
	local g = grow or 0
	local h = topY - bottomY
	if h <= 0 then
		return
	end
	local midY = (topY + bottomY) / 2
	local box = outline.box
	if box then
		fillBox(ctx, box, bottomY, topY, material, g, guard)
	end
	for _, c in outline.circles do
		if not guard or guard(c.x, c.z, c.r + g, topY) then
			ctx.terrain:FillCylinder(CFrame.new(c.x, midY, c.z), h, c.r + g, material)
		end
	end
end

-- Is a point (horizontally) inside the outline, shrunk by `shrink`?
function Land.contains(outline: Outline, position: Vector3, shrink: number?): boolean
	local m = shrink or 0
	local box = outline.box
	if box then
		local l =
			box.frame:PointToObjectSpace(Vector3.new(position.X, box.frame.Position.Y, position.Z))
		if math.abs(l.X) <= box.width / 2 - m and math.abs(l.Z) <= box.depth / 2 - m then
			return true
		end
	end
	for _, c in outline.circles do
		local dx, dz = position.X - c.x, position.Z - c.z
		if c.r > m and dx * dx + dz * dz <= (c.r - m) * (c.r - m) then
			return true
		end
	end
	return false
end

export type Layer = { outline: Outline, top: number }

-- Height of the highest layer under the point (layers listed highest
-- first), or nil. A point on the crumbly edge of a layer (inside it but
-- within `shrink` of its rim) is rejected rather than dropped to the layer
-- below, so props never end up buried inside a cliff.
function Land.surfaceAt(layers: { Layer }, position: Vector3, shrink: number?): number?
	for _, layer in layers do
		if Land.contains(layer.outline, position, 0) then
			if Land.contains(layer.outline, position, shrink) then
				return layer.top
			end
			return nil
		end
	end
	return nil
end

-- Exactly flat rectangle (any yaw) with its top at topY: catch floors.
function Land.flatRect(
	ctx: Context,
	frame: CFrame,
	width: number,
	depth: number,
	topY: number,
	thickness: number,
	material: Enum.Material
)
	local p = frame.Position
	ctx.terrain:FillBlock(
		CFrame.new(p.X, topY - thickness / 2, p.Z) * frame.Rotation,
		Vector3.new(width, thickness, depth),
		material
	)
end

export type CliffOptions = {
	guard: Guard?,
	lean: number?, -- how far the foot spreads beyond the top outline (studs)
	foot: number?, -- below this height the cliff is one plain fill (default 0)
	capDepth: number?,
}

-- Strata cliff: the top outline (`outline`, flat at topY, capped with
-- `cap`) sits on bands that spread out a little further each step down,
-- by a different random amount per circle, so the face leans back with
-- irregular ledges instead of standing as a vertical striped wall. Band
-- heights are jittered per cliff (off the global 4-stud grid); every other
-- band uses the next material from `bands`. Returns the top outline.
function Land.cliff(
	ctx: Context,
	outline: Outline,
	bottomY: number,
	topY: number,
	body: Enum.Material,
	bands: { Enum.Material },
	cap: Enum.Material,
	rng: Random,
	options: CliffOptions?
): Outline
	local opts: CliffOptions = options or {}
	local guard = opts.guard
	local lean = opts.lean or 7
	local foot = math.max(opts.foot or 0, bottomY)
	local capDepth = opts.capDepth or 4
	local n = #outline.circles
	local growth: { number } = table.create(n, 0)
	local boxGrowth = 0

	local function band(y0: number, y1: number, material: Enum.Material)
		if y1 - y0 <= 0.05 then
			return
		end
		local midY = (y0 + y1) / 2
		for i, c in outline.circles do
			local r = c.r + growth[i]
			if not guard or guard(c.x, c.z, r, y1) then
				ctx.terrain:FillCylinder(CFrame.new(c.x, midY, c.z), y1 - y0, r, material)
			end
		end
		local box = outline.box
		if box then
			fillBox(ctx, box, y0, y1, material, boxGrowth, guard)
		end
	end

	-- cap
	local y = topY - capDepth
	band(y, topY, cap)
	-- strata bands, spreading as they go down
	local i = 0
	local first = rng:NextNumber(2.5, 5.5)
	while y > foot + 0.5 do
		i += 1
		local h = if i == 1 then first else rng:NextNumber(3.2, 4.8)
		local y0 = math.max(y - h, foot)
		local total = 0
		for k = 1, n do
			growth[k] = math.min(growth[k] + rng:NextNumber(0.6, 1.5), lean)
			total += growth[k]
		end
		boxGrowth = if n > 0 then total / n else boxGrowth + 1
		local material = body
		if #bands > 0 and i % 2 == 0 then
			material = bands[((i // 2) - 1) % #bands + 1]
		end
		band(y0, y, material)
		y = y0
	end
	-- underwater / buried part in one go
	if y > bottomY then
		band(bottomY, y, body)
	end
	return outline
end

-- Fallen boulders at the foot of a cliff (terrain balls, no parts).
function Land.talus(
	ctx: Context,
	outline: Outline,
	footY: number,
	rng: Random,
	count: number,
	material: Enum.Material,
	guard: Guard?
)
	local circles = outline.circles
	if #circles == 0 then
		return
	end
	for _ = 1, count do
		local c = circles[rng:NextInteger(1, #circles)]
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(2.5, 5)
		local reach = c.r + rng:NextNumber(0.5, 3)
		local x, z = c.x + math.sin(a) * reach, c.z - math.cos(a) * reach
		local center = Vector3.new(x, footY + r * 0.2, z)
		if not guard or guard(x, z, r, center.Y + r) then
			ctx.terrain:FillBall(center, r, material)
		end
	end
end

-- Sea stack / hoodoo: a stack of shrinking, wobbling discs with strata.
function Land.pinnacle(
	ctx: Context,
	base: Vector3,
	height: number,
	radius: number,
	rng: Random,
	materials: { Enum.Material },
	capRadius: number?,
	cap: Enum.Material?,
	guard: Guard?
)
	local layers = math.max(3, math.floor(height / 5))
	local layerH = height / layers
	local x, z = base.X, base.Z
	for i = 1, layers do
		local t = (i - 1) / (layers - 1)
		local r = radius + ((capRadius or radius * 0.45) - radius) * t
		r *= rng:NextNumber(0.85, 1.15)
		x += rng:NextNumber(-1, 1) * radius * 0.1
		z += rng:NextNumber(-1, 1) * radius * 0.1
		local y0 = base.Y + (i - 1) * layerH
		local top = y0 + layerH + 0.5
		if guard and not guard(x, z, math.max(r, 1.5), top) then
			return
		end
		ctx.terrain:FillCylinder(
			CFrame.new(x, y0 + layerH / 2 + 0.25, z),
			layerH + 0.5,
			math.max(r, 1.5),
			if i == layers and cap then cap else materials[(i - 1) % #materials + 1]
		)
	end
end

-- A rocky ridge from a to b (ground points; Y ignored): a chain of leaning
-- crag blobs whose tops rise from h0 to h1 with some noise. Pure terrain.
function Land.ridge(
	ctx: Context,
	a: Vector3,
	b: Vector3,
	h0: number,
	h1: number,
	width: number,
	rng: Random,
	body: Enum.Material,
	bands: { Enum.Material },
	cap: Enum.Material,
	guard: Guard?
)
	local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local length = flat.Magnitude
	local count = math.max(2, math.floor(length / (width * 0.9)))
	for k = 0, count - 1 do
		local f = (k + rng:NextNumber(0.2, 0.8)) / count
		local p = a:Lerp(b, f)
		local side = flat.Unit:Cross(Vector3.new(0, 1, 0)) * rng:NextNumber(-0.3, 0.3) * width
		local top = h0 + (h1 - h0) * f + rng:NextNumber(-3, 3)
		top = math.floor(top / 2 + 0.5) * 2
		local blob =
			Land.blob(p + side, width * rng:NextNumber(0.45, 0.65), rng, rng:NextInteger(4, 6), 2)
		Land.cliff(ctx, blob, -22, top, body, bands, cap, rng, { guard = guard, lean = 5 })
	end
end

-- Natural rock arch from a to b (feet on the sea bed or ground), peak at
-- `height` above the feet.
function Land.arch(
	ctx: Context,
	a: Vector3,
	b: Vector3,
	height: number,
	thickness: number,
	rng: Random,
	materials: { Enum.Material },
	guard: Guard?
)
	Land.pinnacle(ctx, a, height, thickness * 0.95, rng, materials, thickness * 0.6, nil, guard)
	Land.pinnacle(ctx, b, height, thickness * 0.95, rng, materials, thickness * 0.6, nil, guard)
	local segments = 5
	for i = 0, segments - 1 do
		local t0, t1 = i / segments, (i + 1) / segments
		local function at(t: number): Vector3
			local p = a:Lerp(b, t)
			local lift = math.sin(t * math.pi) * 0.18 * height
			return p + Vector3.new(0, height - thickness * 0.4 + lift, 0)
		end
		local p0, p1 = at(t0), at(t1)
		local mid = (p0 + p1) / 2
		if not guard or guard(mid.X, mid.Z, thickness, mid.Y + thickness * 0.4) then
			ctx.terrain:FillBlock(
				CFrame.lookAt(mid, p1),
				Vector3.new(thickness, thickness * 0.8, (p1 - p0).Magnitude + thickness * 0.6),
				materials[(i % #materials) + 1]
			)
		end
	end
end

return Land
