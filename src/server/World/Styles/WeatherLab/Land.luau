--!strict
-- WeatherLab ground, built from World/Blocks parts in Map.Ground/<key>: the
-- sea and its wadeable bed, polygon islands (grass cap, strata bands, a
-- sand ring and wedge beach slopes), the plateau under every zone (catch
-- floor blocks laid in the theme's pattern, flush at the floor, a cap out
-- to the margins, stepped strata and a rounded beach tier), mesas, rock
-- stacks and ramps. Every flat top is remembered with Geo.addPoly /
-- Geo.addRect so props stand on real ground (Geo.heightAt).
--
-- Overlapping pieces whose tops share a height use one exact colour (no
-- Blocks jitter) so they never flicker; anything laid over other ground
-- sits at least 0.1 stud above it.

local ServerScriptService = game:GetService("ServerScriptService")

local Blocks = require(ServerScriptService.Server.World.Blocks)
local Geo = require(script.Parent.Geo)
local Palette = require(script.Parent.Palette)
local WLTypes = require(script.Parent.WLTypes)

type Context = WLTypes.Context
type ZoneContext = WLTypes.ZoneContext
type Margins = WLTypes.Margins
type FieldLook = WLTypes.FieldLook
type IslandLook = WLTypes.IslandLook

local G = Palette.ground

local Land = {}

Land.SEA = 0 -- water surface
Land.SEABED = -4 -- top of the sea bed: wading depth, so nobody is stuck at sea
Land.RUN = 2 -- beach slopes: studs of run per stud of rise (26.6 degrees)
Land.CAP = 1 -- grass / sand cap thickness
Land.OVERHANG = 0.6 -- caps reach this far past the band below
Land.TRIM = 3 -- the field trim reaches this far past the footprint
-- The hub island's grass top (Hub builds it; boardwalks stay flat until
-- they have cleared it).
Land.HUB_CAP = 69
Land.HUB_SIDES = 14

-- Wedges run this share of the way round a corner: enough to close the
-- gap above the water line, not so far that their ends poke out.
local SLOPE_REACH = 0.7

function Land.hubEdge(): number
	return Land.HUB_CAP / math.cos(math.pi / Land.HUB_SIDES)
end

-- Map.Ground/<key>: one folder per island, so the part budget can count it.
function Land.folder(ctx: Context, key: string): Folder
	local existing = ctx.folders.ground:FindFirstChild(key)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = key
	folder.Parent = ctx.folders.ground
	return folder
end

-- Props for an exactly coloured (unjittered) ground part.
local function exact(color: Color3, name: string?): { [string]: any }
	return { Color = color, Name = name or "Ground" }
end

-- `top` moved to height y, keeping its position and yaw.
local function atHeight(top: CFrame, y: number): CFrame
	local p = top.Position
	return CFrame.new(p.X, y, p.Z) * top.Rotation
end

-- Bands from fromY down to toY, about `layer` studs each (1 to 6 of them);
-- the last one carries on down to the sea bed so no band top lies on toY.
local function bandsTo(fromY: number, toY: number, layer: number): { number }
	local span = fromY - toY
	if span < 0.3 then
		local deep = fromY - Land.SEABED
		return { deep / 2, deep / 2 }
	end
	local n = math.clamp(math.floor(span / layer + 0.5), 1, 6)
	local heights = table.create(n, span / n)
	heights[n] += toY - Land.SEABED
	return heights
end

-- Corners of a regular polygon laid like Blocks.disc (side i faces yaw
-- i * 360 / sides), local x / z.
local function polygon(apothem: number, sides: number): { Vector2 }
	local points = {}
	local corner = apothem / math.cos(math.pi / sides)
	for i = 0, sides - 1 do
		local phi = (i + 0.5) * 2 * math.pi / sides
		table.insert(points, Vector2.new(-math.sin(phi), -math.cos(phi)) * corner)
	end
	return points
end

-- Corners of a hx by hz rectangle whose corners are rounded off by two
-- facets each (a 12-gon turning 30 degrees at a time) round arcs of
-- radius r. Local x / z.
local function roundRect(hx: number, hz: number, r: number): { Vector2 }
	local points = {}
	local corner = r / math.cos(math.rad(15))
	for quarter = 0, 3 do
		local sx = if quarter == 0 or quarter == 3 then 1 else -1
		local sz = if quarter <= 1 then 1 else -1
		local q = Vector2.new(sx * (hx - r), sz * (hz - r))
		for _, j in { 15, 45, 75 } do
			local a = math.rad(quarter * 90 + j)
			table.insert(points, q + Vector2.new(math.cos(a), math.sin(a)) * corner)
		end
	end
	return points
end

-- The sea ------------------------------------------------------------------------

-- One see-through water sheet (outside Map.Ground) over a solid sea bed.
function Land.sea(ctx: Context)
	Blocks.box(
		Land.folder(ctx, "Sea"),
		G.seabed,
		CFrame.new(0, Land.SEABED - 2, 0),
		Vector3.new(Blocks.MAX_SIZE, 4, Blocks.MAX_SIZE),
		exact(G.seabed, "Seabed")
	)
	Blocks.water(
		ctx.folders.base,
		Palette.water,
		Vector3.zero,
		Vector2.new(Blocks.MAX_SIZE, Blocks.MAX_SIZE),
		Land.SEA,
		{ Transparency = 0.35 }
	)
end

-- Basic pieces ---------------------------------------------------------------------

-- A solid regular polygon with its top at `top` (yaw included), down to the
-- sea bed unless `height` is given. Remembered as ground.
function Land.disc(
	ctx: Context,
	key: string,
	color: Color3,
	top: CFrame,
	apothem: number,
	sides: number,
	height: number?
): { BasePart }
	Geo.addPoly(ctx, key, top, apothem, sides)
	return Blocks.disc(
		Land.folder(ctx, key),
		color,
		top,
		apothem,
		height or (top.Position.Y - Land.SEABED),
		sides,
		exact(color)
	)
end

-- Strata bands under a polygon cap whose underside is at under.Y: band i
-- (colours alternate) reaches apothem + (i - 1) * inset. Hollow rings (the
-- cap above hides the inside); every exposed ledge is remembered.
function Land.cliff(
	ctx: Context,
	key: string,
	colors: { Color3 },
	under: CFrame,
	apothem: number,
	heights: { number },
	inset: number,
	sides: number
)
	local folder = Land.folder(ctx, key)
	local depth = 0
	for i, h in heights do
		local r = apothem + (i - 1) * inset
		local band = under * CFrame.new(0, -depth, 0)
		Blocks.ring(
			folder,
			colors[(i - 1) % #colors + 1],
			band,
			r,
			math.min(r, inset + 6),
			h,
			sides
		)
		if i > 1 then
			Geo.addPoly(ctx, key, band, r, sides)
		end
		depth += h
	end
end

-- Beach slopes: one wedge per edge of a convex outline (`points`, local
-- x / z of the level frame `top`, in order round it) falling from top.Y to
-- the sea bed. `skip` leaves out edges whose midpoint (world) it accepts.
function Land.slopes(
	ctx: Context,
	key: string,
	color: Color3,
	top: CFrame,
	points: { Vector2 },
	skip: ((Vector3) -> boolean)?
)
	local rise = top.Position.Y - Land.SEABED
	if rise < 0.3 then
		return
	end
	local folder = Land.folder(ctx, key)
	local run = rise * Land.RUN
	local count = #points
	local centroid = Vector2.zero
	for _, p in points do
		centroid += p
	end
	centroid /= count
	local function reach(k: number): number
		local prev = points[(k - 2) % count + 1]
		local here = points[k]
		local nextPoint = points[k % count + 1]
		local turn = math.acos(math.clamp((here - prev).Unit:Dot((nextPoint - here).Unit), -1, 1))
		return SLOPE_REACH * run * math.tan(turn / 2)
	end
	for k = 1, count do
		local a, b = points[k], points[k % count + 1]
		local edge = b - a
		if edge.Magnitude > 0.1 then
			local along = edge.Unit
			local normal = Vector2.new(along.Y, -along.X)
			local mid = (a + b) / 2
			if normal:Dot(mid - centroid) < 0 then
				normal = -normal
			end
			local ra, rb = reach(k), reach(k % count + 1)
			local midWorld = top:PointToWorldSpace(Vector3.new(mid.X, 0, mid.Y))
			if not (skip and skip(midWorld)) then
				local c = mid + along * (rb - ra) / 2
				local world = top:PointToWorldSpace(Vector3.new(c.X, 0, c.Y))
				local outward = top:VectorToWorldSpace(Vector3.new(normal.X, 0, normal.Y))
				local base = Vector3.new(world.X, Land.SEABED + rise / 2, world.Z)
				-- tall end (local +Z) on the outline, falling outward
				Blocks.wedge(
					folder,
					color,
					CFrame.lookAt(base, base + outward) * CFrame.new(0, 0, -run / 2),
					Vector3.new(edge.Magnitude + ra + rb, rise, run),
					exact(color, "Beach")
				)
			end
		end
	end
end

-- A rounded rectangle (see roundRect) from top.Y down to the sea bed: two
-- crossed blocks plus two facet blocks per corner, one exact colour.
function Land.roundRect(
	ctx: Context,
	key: string,
	color: Color3,
	top: CFrame,
	hx: number,
	hz: number,
	r: number
): { Vector2 }
	local folder = Land.folder(ctx, key)
	r = math.clamp(r, 1, math.min(hx, hz) * 0.8)
	local h = top.Position.Y - Land.SEABED
	local t = r * math.tan(math.rad(15))
	local props = exact(color)
	local mid = top * CFrame.new(0, -h / 2, 0)
	Blocks.box(folder, color, mid, Vector3.new(2 * hx, h, 2 * (hz - r + t)), props)
	Blocks.box(folder, color, mid, Vector3.new(2 * (hx - r + t), h, 2 * hz), props)
	for quarter = 0, 3 do
		local sx = if quarter == 0 or quarter == 3 then 1 else -1
		local sz = if quarter <= 1 then 1 else -1
		local q = mid * CFrame.new(sx * (hx - r), 0, sz * (hz - r))
		for _, j in { 30, 60 } do
			local a = math.rad(quarter * 90 + j)
			local facing = CFrame.lookAt(Vector3.zero, Vector3.new(math.cos(a), 0, math.sin(a)))
			Blocks.box(
				folder,
				color,
				q * facing * CFrame.new(0, 0, -r / 2),
				Vector3.new(2 * t + 0.05, h, r),
				props
			)
		end
	end
	Geo.addRect(ctx, key, top, hx, hz, r)
	return roundRect(hx, hz, r)
end

-- A stepped mesa: rectangular strata from `top` (yaw included) down to the
-- sea bed, about `layer` studs per band, none ending on `avoid` (the beach
-- height, so no band top lies flush with the beach).
function Land.mesa(
	ctx: Context,
	key: string,
	colors: { Color3 },
	top: CFrame,
	size: Vector2,
	layer: number,
	inset: number,
	avoid: number
): { BasePart }
	Geo.addRect(ctx, key, top, size.X / 2, size.Y / 2, 0)
	return Blocks.strataBox(
		Land.folder(ctx, key),
		colors,
		top,
		size,
		bandsTo(top.Position.Y, avoid, layer),
		inset
	)
end

-- A sea stack or hoodoo standing on `bottom`: blocks of alternating
-- colours, each turned and nudged a little and narrower than the one
-- below, up to topY, then a wider cap block if `cap` is given.
function Land.stack(
	ctx: Context,
	parent: Instance,
	colors: { Color3 },
	bottom: Vector3,
	width: number,
	topY: number,
	band: number,
	cap: Color3?
)
	local rng = ctx.rng
	local y = bottom.Y
	local w = width
	local offset = Vector3.zero
	local i = 0
	while y < topY - 0.5 do
		i += 1
		local h = math.min(band * rng:NextNumber(0.8, 1.15), topY - y)
		if topY - y - h < band * 0.4 then
			h = topY - y
		end
		local c = bottom + offset
		Blocks.box(
			parent,
			colors[(i - 1) % #colors + 1],
			CFrame.new(c.X, y + h / 2, c.Z) * CFrame.Angles(0, rng:NextNumber(0, math.pi / 2), 0),
			Vector3.new(w, h, w * rng:NextNumber(0.8, 1)),
			{ Name = "Stack" }
		)
		y += h
		w = math.max(width * 0.5, w * rng:NextNumber(0.82, 0.94))
		offset += Vector3.new(rng:NextNumber(-0.8, 0.8), 0, rng:NextNumber(-0.8, 0.8))
	end
	if cap then
		local c = bottom + offset
		Blocks.box(
			parent,
			cap,
			CFrame.new(c.X, topY + 0.6, c.Z) * CFrame.Angles(0, rng:NextNumber(0, math.pi / 2), 0),
			Vector3.new(w * 1.3, 1.2, w * 1.2),
			{ Name = "StackCap" }
		)
	end
end

-- One band of an octagonal column: two blocks crossed at 45 degrees
-- standing on `bottom` (level, yaw included), one exact colour.
function Land.octBand(
	parent: Instance,
	color: Color3,
	bottom: CFrame,
	apothem: number,
	height: number
)
	for k = 0, 1 do
		Blocks.box(
			parent,
			color,
			bottom * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, k * math.pi / 4, 0),
			Vector3.new(2 * apothem, height, 2 * apothem),
			exact(color, "Spire")
		)
	end
end

-- Islands ----------------------------------------------------------------------------

export type IslandSpec = {
	cap: Color3, -- grass / sand top, Land.CAP deep
	strata: { Color3 }, -- cliff bands under it, alternating
	apothem: number,
	sides: number,
	layer: number, -- about this tall per band
	inset: number, -- each band steps out this far
	beach: Color3?, -- a sand ring at beachTop round the cliff foot
	beachTop: number?,
	beachWidth: number?,
	slope: Color3?, -- wedge slopes from the sand ring to the sea bed
}

-- A polygon island with its top at `top` (yaw included): cap, strata
-- bands down to the sea bed and, optionally, a sand ring with slopes.
function Land.island(ctx: Context, key: string, top: CFrame, spec: IslandSpec)
	local folder = Land.folder(ctx, key)
	Land.disc(ctx, key, spec.cap, top, spec.apothem, spec.sides, Land.CAP)
	local under = top * CFrame.new(0, -Land.CAP, 0)
	local beach = spec.beach
	local beachTop = if beach then spec.beachTop or 1 else Land.SEABED
	local heights = bandsTo(under.Position.Y, beachTop, spec.layer)
	local inner = spec.apothem - Land.OVERHANG
	Land.cliff(ctx, key, spec.strata, under, inner, heights, spec.inset, spec.sides)
	if beach then
		local width = spec.beachWidth or 6
		local reach = inner + spec.inset * (#heights - 1) + width
		local ring = atHeight(top, beachTop)
		Blocks.ring(
			folder,
			beach,
			ring,
			reach,
			width + spec.inset + 3,
			beachTop - Land.SEABED,
			spec.sides,
			exact(beach, "Beach")
		)
		Geo.addPoly(ctx, key, ring, reach, spec.sides)
		local slope = spec.slope
		if slope then
			Land.slopes(ctx, key, slope, ring, polygon(reach, spec.sides))
		end
	end
end

-- A polygon lobe unioned onto ground of the same height and colour (a
-- beach bulge, a sand spit): wedge slopes only on the edges that face open
-- water, i.e. whose midpoint is not already on ground this high.
function Land.lobe(
	ctx: Context,
	key: string,
	color: Color3,
	slope: Color3,
	top: CFrame,
	apothem: number,
	sides: number
)
	local y = top.Position.Y
	Land.slopes(ctx, key, slope, top, polygon(apothem, sides), function(mid: Vector3): boolean
		local h = Geo.heightAt(ctx, key, mid)
		return h ~= nil and h >= y - 0.1
	end)
	Land.disc(ctx, key, color, top, apothem, sides)
end

-- Zone plateaus ---------------------------------------------------------------------

local function count(span: number, cell: number): number
	local n = math.max(3, math.floor(span / cell + 0.5))
	if n % 2 == 0 then
		n += 1
	end
	return n
end

-- The catch floor: blocks 1 stud deep with their tops exactly at the floor,
-- laid edge to edge in the theme's two-tone pattern, inside a trim band
-- reaching Land.TRIM past the footprint (the border kerb stands on it).
function Land.field(ctx: Context, zone: ZoneContext, look: FieldLook)
	local folder = Land.folder(ctx, Geo.key(zone))
	local hw, hd = zone.slot.width / 2, zone.slot.depth / 2
	local iw, id = hw - 1, hd - 1
	local tx, tz = hw + Land.TRIM, hd + Land.TRIM
	local function tile(x0: number, x1: number, z0: number, z1: number, color: Color3)
		if x1 - x0 > 0.01 and z1 - z0 > 0.01 then
			Blocks.box(
				folder,
				color,
				Geo.cf(zone, (x0 + x1) / 2, (z0 + z1) / 2, -0.5),
				Vector3.new(x1 - x0, 1, z1 - z0),
				{ Name = "Field" }
			)
		end
	end
	tile(-tx, tx, -tz, -id, look.trim)
	tile(-tx, tx, id, tz, look.trim)
	tile(-tx, -iw, -id, id, look.trim)
	tile(iw, tx, -id, id, look.trim)
	if look.pattern == "checker" then
		local nx, nz = count(2 * iw, look.cell), count(2 * id, look.cell)
		local sx, sz = 2 * iw / nx, 2 * id / nz
		for i = 0, nx - 1 do
			for j = 0, nz - 1 do
				tile(
					-iw + i * sx,
					-iw + (i + 1) * sx,
					-id + j * sz,
					-id + (j + 1) * sz,
					if (i + j) % 2 == 1 then look.accent else look.base
				)
			end
		end
		return
	end
	local along = look.pattern == "along"
	local span = if along then iw else id
	local n = count(2 * span, look.cell)
	local s = 2 * span / n
	local function band(a0: number, a1: number, color: Color3)
		if along then
			tile(a0, a1, -id, id, color)
		else
			tile(-iw, iw, a0, a1, color)
		end
	end
	for i = 0, n - 1 do
		local a0, a1 = -span + i * s, -span + (i + 1) * s
		local piping = look.piping
		if i % 2 == 0 then
			band(a0, a1, look.base)
		elseif piping and s > 4 then
			band(a0, a0 + 1, piping)
			band(a0 + 1, a1 - 1, look.accent)
			band(a1 - 1, a1, piping)
		else
			band(a0, a1, look.accent)
		end
	end
end

-- Height (world y) of the plateau cliff `k` bands below its cap (k may be
-- fractional: 1.5 is the middle of the second band). Themes set landforms
-- beside the plateau at these heights so no top lies flush with a ledge.
function Land.ledge(zone: ZoneContext, look: IslandLook, k: number): number
	local floor = zone.slot.floor
	local beachTop = math.min(look.beachTop, floor - Land.CAP)
	local span = floor - Land.CAP - beachTop
	if span < 0.3 then
		return beachTop
	end
	local n = math.clamp(math.floor(span / look.layer + 0.5), 1, 6)
	return math.max(floor - Land.CAP - k * span / n, beachTop + 0.5)
end

-- A zone's island: the field and a cap round it out to the margins (one
-- flush surface at the floor), stepped strata under it down to the sea bed,
-- a rounded beach tier round its sides and back with wedge slopes, and
-- (with look.ramp) a ramp from the beach up the cliff by the front corner.
function Land.plateau(
	ctx: Context,
	zone: ZoneContext,
	m: Margins,
	look: IslandLook,
	field: FieldLook
)
	local key = Geo.key(zone)
	local folder = Land.folder(ctx, key)
	local floor = zone.slot.floor
	local hw, hd = zone.slot.width / 2, zone.slot.depth / 2
	local tx, tz = hw + Land.TRIM, hd + Land.TRIM
	local ax = hw + m.side
	local z0, z1 = -(hd + m.front), hd + m.back
	local zc = (z0 + z1) / 2

	Land.field(ctx, zone, field)
	local function cap(x0: number, x1: number, za: number, zb: number)
		if x1 - x0 > 0.01 and zb - za > 0.01 then
			Blocks.box(
				folder,
				look.cap,
				Geo.cf(zone, (x0 + x1) / 2, (za + zb) / 2, -Land.CAP / 2),
				Vector3.new(x1 - x0, Land.CAP, zb - za),
				{ Name = "Cap" }
			)
		end
	end
	cap(-ax, ax, z0, -tz)
	cap(-ax, ax, tz, z1)
	cap(-ax, -tx, -tz, tz)
	cap(tx, ax, -tz, tz)
	Geo.addRect(ctx, key, Geo.cf(zone, 0, zc, 0), ax, (z1 - z0) / 2, 0)

	-- strata, stepping out band by band
	local beachTop = math.min(look.beachTop, floor - Land.CAP)
	local heights = bandsTo(floor - Land.CAP, beachTop, look.layer)
	local under = Geo.cf(zone, 0, zc, -Land.CAP)
	local hx, hz = ax - Land.OVERHANG, (z1 - z0) / 2 - Land.OVERHANG
	Blocks.strataBox(folder, look.strata, under, Vector2.new(2 * hx, 2 * hz), heights, look.inset)
	local depth = heights[1]
	for i = 2, #heights do
		local grow = (i - 1) * look.inset
		Geo.addRect(ctx, key, under * CFrame.new(0, -depth, 0), hx + grow, hz + grow, 0)
		depth += heights[i]
	end
	local reach = ax - Land.OVERHANG + look.inset * (#heights - 1)

	-- the beach tier and its slopes (none under the plateau's front)
	local bx = ax + look.beachSide
	local bz0, bz1 = z0 - look.beachFront, z1 + look.beachBack
	local beachFrame = Geo.cf(zone, 0, (bz0 + bz1) / 2, beachTop - floor)
	local outline =
		Land.roundRect(ctx, key, look.beach, beachFrame, bx, (bz1 - bz0) / 2, look.chamfer)
	Land.slopes(ctx, key, look.beach, beachFrame, outline, function(mid: Vector3): boolean
		local l = Geo.toLocal(zone, mid)
		return math.abs(l.X) < reach and l.Z > z0 - 1 and l.Z < z1 + 1
	end)

	-- a ramp up the cliff on one side, rising toward the front corner, and
	-- a landing that bridges the strata steps to the cap
	local cliff = floor - beachTop
	local ramp = look.ramp
	if ramp and cliff > 1.2 then
		local w = 5
		local gap = math.max(reach - ax, 0) + 0.3
		local x = ramp * (ax + gap + w / 2)
		local zh = z0 + 5
		local run = cliff * 2.05
		Blocks.ramp(
			folder,
			look.cap,
			Geo.at(zone, x, zh + run, beachTop - floor),
			Geo.at(zone, x, zh, 0),
			w,
			{ Name = "Ramp" }
		)
		local lx = ramp * (ax + (gap + w) / 2)
		local pillar = floor - Land.CAP - Land.SEABED
		Blocks.box(
			folder,
			look.strata[1],
			Geo.cf(zone, lx, zh - 2.5, -Land.CAP - pillar / 2),
			Vector3.new(gap + w, pillar, 5),
			{ Name = "Landing" }
		)
		Blocks.box(
			folder,
			look.cap,
			Geo.cf(zone, lx, zh - 2.5, -Land.CAP / 2),
			Vector3.new(gap + w, Land.CAP, 5),
			{ Name = "Landing" }
		)
		Geo.addRect(ctx, key, Geo.cf(zone, lx, zh - 2.5, 0), (gap + w) / 2, 2.5, 0)
	end
end

return Land
