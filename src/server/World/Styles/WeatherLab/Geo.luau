--!strict
-- Geometry helpers for WeatherLab: zone-local coordinates and terrain
-- landmasses (wobbly terraces, irregular discs, painted fields). Zone-local
-- studs: x runs across the zone (right when facing the hub), z runs from
-- the centre toward the back edge (+) or the gate edge (-), y is above
-- the zone floor. Works for any slot position, rotation and size.

local WLTypes = require(script.Parent.WLTypes)

type Context = WLTypes.Context
type ZoneContext = WLTypes.ZoneContext
type Margins = WLTypes.Margins
type FieldLook = WLTypes.FieldLook

local Geo = {}

-- Ground direction for an angle in degrees clockwise from north (-Z),
-- matching World/Layout.
function Geo.dir(angleDeg: number): Vector3
	local a = math.rad(angleDeg)
	return Vector3.new(math.sin(a), 0, -math.cos(a))
end

function Geo.polar(angleDeg: number, radius: number, y: number): Vector3
	return Geo.dir(angleDeg) * radius + Vector3.new(0, y, 0)
end

-- Angle (degrees, 0..360) of a horizontal direction.
function Geo.angleOf(v: Vector3): number
	return math.deg(math.atan2(v.X, -v.Z)) % 360
end

-- Smallest absolute difference between two angles in degrees.
function Geo.angleDiff(a: number, b: number): number
	local d = math.abs((a - b) % 360)
	return math.min(d, 360 - d)
end

function Geo.flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Zone-local studs -> world point.
function Geo.at(zone: ZoneContext, x: number, z: number, y: number?): Vector3
	return zone.slot.frame:PointToWorldSpace(Vector3.new(x, y or 0, z))
end

-- Zone-local CFrame, turned by yaw degrees (0 = facing the hub).
function Geo.cf(zone: ZoneContext, x: number, z: number, y: number?, yaw: number?): CFrame
	return zone.slot.frame * CFrame.new(x, y or 0, z) * CFrame.Angles(0, math.rad(yaw or 0), 0)
end

function Geo.toLocal(zone: ZoneContext, p: Vector3): Vector3
	return zone.slot.frame:PointToObjectSpace(p)
end

-- Upright CFrame at p facing horizontally toward target.
function Geo.facing(p: Vector3, target: Vector3): CFrame
	local d = Geo.flat(target - p)
	if d.Magnitude < 1e-3 then
		return CFrame.new(p)
	end
	return CFrame.lookAt(p, p + d.Unit)
end

-- Zone-local point facing the middle of the zone.
function Geo.faceField(zone: ZoneContext, x: number, z: number, y: number?): CFrame
	return Geo.facing(Geo.at(zone, x, z, y), Geo.at(zone, 0, 0, y))
end

-- How far (studs) a zone-local x/z lies outside the footprint (0 inside).
function Geo.outside(zone: ZoneContext, x: number, z: number): number
	local dx = math.max(math.abs(x) - zone.slot.width / 2, 0)
	local dz = math.max(math.abs(z) - zone.slot.depth / 2, 0)
	return math.sqrt(dx * dx + dz * dz)
end

-- A random zone-local point in the rim around the footprint: at least
-- `near` and at most `far` studs outside the footprint, on the sides and
-- back only when `noFront` is set. Returns x, z.
function Geo.rimPoint(
	zone: ZoneContext,
	rng: Random,
	near: number,
	far: number,
	noFront: boolean?
): (number, number)
	local hw, hd = zone.slot.width / 2, zone.slot.depth / 2
	for _ = 1, 40 do
		local x = rng:NextNumber(-hw - far, hw + far)
		local z = rng:NextNumber(-hd - far, hd + far)
		local out = Geo.outside(zone, x, z)
		local frontOk = not noFront or z > -hd + 4
		if out >= near and out <= far and frontOk then
			return x, z
		end
	end
	return hw + near, 0
end

-- Prop spots: keeps props from piling on top of each other.
export type Spots = { { x: number, z: number, r: number } }

function Geo.free(spots: Spots, x: number, z: number, r: number): boolean
	for _, s in spots do
		local dx, dz = s.x - x, s.z - z
		if dx * dx + dz * dz < (s.r + r) * (s.r + r) then
			return false
		end
	end
	return true
end

function Geo.claim(spots: Spots, x: number, z: number, r: number)
	table.insert(spots, { x = x, z = z, r = r })
end

-- A free zone-local spot in the rim (see rimPoint) that keeps clear of the
-- boardwalk landing in front of the gate. Claims it. Returns nil if none.
function Geo.findSpot(
	zone: ZoneContext,
	rng: Random,
	spots: Spots,
	near: number,
	far: number,
	r: number,
	noFront: boolean?
): (number?, number?)
	local hd = zone.slot.depth / 2
	for _ = 1, 30 do
		local x, z = Geo.rimPoint(zone, rng, near + r, far, noFront)
		local landing = z < -hd + 1 and math.abs(x) < 13 + r
		if not landing and Geo.free(spots, x, z, r) then
			Geo.claim(spots, x, z, r)
			return x, z
		end
	end
	return nil, nil
end

-- Terrain ------------------------------------------------------------------------

-- Filled rounded rectangle [x0,x1] x [z0,z1] in `frame` space from bottomY
-- to topY, with a wobbly, lumpy outline made of overlapping cylinders.
-- `bump` is the size of the wobble; `jag` lowers rim cylinders by up to
-- that much so lower terraces get uneven tops; `wild` (0..1) adds big
-- bays, headlands and sand spits so coastlines never read as rectangles.
function Geo.roundRect(
	ctx: Context,
	frame: CFrame,
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	topY: number,
	bottomY: number,
	material: Enum.Material,
	bump: number,
	jag: number?,
	wild: number?
)
	local rng = ctx.rng
	local terrain = ctx.terrain
	local wildness = wild or 0
	if wildness > 0 then
		-- each side reaches a different distance, so layers never nest evenly
		local spread = wildness * bump * 1.8
		x0 -= rng:NextNumber(0, spread)
		x1 += rng:NextNumber(0, spread)
		z0 -= rng:NextNumber(0, spread)
		z1 += rng:NextNumber(0, spread)
	end
	local inset = bump * (0.75 + wildness * 0.7)
	local height = topY - bottomY
	local w, d = (x1 - x0) - 2 * inset, (z1 - z0) - 2 * inset
	if w > 0 and d > 0 then
		local c = frame:PointToWorldSpace(Vector3.new((x0 + x1) / 2, 0, (z0 + z1) / 2))
		terrain:FillBlock(
			CFrame.new(c.X, bottomY + height / 2, c.Z) * frame.Rotation,
			Vector3.new(w, height, d),
			material
		)
	end
	local ex0, ex1, ez0, ez1 = x0 + inset, x1 - inset, z0 + inset, z1 - inset
	local lenX, lenZ = math.max(ex1 - ex0, 0), math.max(ez1 - ez0, 0)
	local perimeter = 2 * (lenX + lenZ)
	-- point on the inset outline at distance t, with its outward normal
	local function outline(t: number): (number, number, number, number)
		if t < lenX then
			return ex0 + t, ez0, 0, -1
		elseif t < lenX + lenZ then
			return ex1, ez0 + (t - lenX), 1, 0
		elseif t < 2 * lenX + lenZ then
			return ex1 - (t - lenX - lenZ), ez1, 0, 1
		end
		return ex0, ez1 - (t - 2 * lenX - lenZ), -1, 0
	end
	local function fill(x: number, z: number, radius: number)
		local p = frame:PointToWorldSpace(Vector3.new(x, 0, z))
		local top = topY - rng:NextNumber(0, jag or 0)
		terrain:FillCylinder(
			CFrame.new(p.X, (top + bottomY) / 2, p.Z),
			top - bottomY,
			radius,
			material
		)
	end
	local steps = math.max(8, math.floor(perimeter / (bump * 1.05)))
	local phase, phase2 = rng:NextNumber(0, math.pi * 2), rng:NextNumber(0, math.pi * 2)
	local waves = rng:NextInteger(2, 4)
	local amp = bump * (0.45 + wildness * 1.1)
	for i = 0, steps - 1 do
		local t = math.clamp((i + rng:NextNumber(-0.2, 0.2)) / steps * perimeter, 0, perimeter)
		local x, z, nx, nz = outline(t)
		local u = t / perimeter * math.pi * 2
		local wave = (
			math.sin(phase + u * waves) * 0.7 + math.sin(phase2 + u * (waves * 2 + 1)) * 0.3
		) * amp
		local push = wave + rng:NextNumber(-0.3, 0.3) * bump
		fill(x + nx * push, z + nz * push, bump * rng:NextNumber(0.75, 1.2))
	end
	-- headlands and sand spits reaching out from the coast
	if wildness > 0.6 then
		local spits = math.floor(wildness * 2.5 + rng:NextNumber(0, 1.4))
		for _ = 1, spits do
			local x, z, nx, nz = outline(rng:NextNumber(0, perimeter))
			local len = bump * rng:NextNumber(1.8, 3.6) * (0.5 + wildness)
			local bend = rng:NextNumber(-0.5, 0.5)
			for j = 1, 4 do
				local f = j / 4
				local along = len * f
				local sideways = bend * along * f
				fill(
					x + nx * along - nz * sideways,
					z + nz * along + nx * sideways,
					bump * (1.05 - 0.5 * f) * rng:NextNumber(0.85, 1.1)
				)
			end
		end
	end
end

-- A terrace around a zone: its footprint grown by the margins plus `grow`.
function Geo.terrace(
	ctx: Context,
	zone: ZoneContext,
	m: Margins,
	grow: number,
	topY: number,
	bottomY: number,
	material: Enum.Material,
	bump: number,
	jag: number?,
	wild: number?
)
	local slot = zone.slot
	local hw, hd = slot.width / 2, slot.depth / 2
	Geo.roundRect(
		ctx,
		slot.frame,
		-hw - m.side - grow,
		hw + m.side + grow,
		-hd - m.front - grow,
		hd + m.back + grow,
		topY,
		bottomY,
		material,
		bump,
		jag,
		wild
	)
end

-- Layered cliff bands between fromY and toY (up to 4), each a terrace a
-- little smaller than the one below, cycling through `materials`.
function Geo.cliffs(
	ctx: Context,
	zone: ZoneContext,
	m: Margins,
	fromY: number,
	toY: number,
	materials: { Enum.Material },
	growFar: number,
	growNear: number,
	bump: number
)
	local n = math.clamp(math.floor((toY - fromY) / 5), 0, 4)
	for k = 1, n do
		local top = fromY + (toY - fromY) * k / (n + 1)
		local t = if n > 1 then (k - 1) / (n - 1) else 0
		local grow = growFar + (growNear - growFar) * t
		Geo.terrace(
			ctx,
			zone,
			m,
			grow,
			top,
			-16,
			materials[(k - 1) % #materials + 1],
			bump,
			1.5,
			0.45
		)
	end
end

-- Irregular disc: a core cylinder (always covering `core`) plus lobes
-- reaching out to about `reach`. Top at topY.
function Geo.disc(
	ctx: Context,
	center: Vector3,
	core: number,
	reach: number,
	topY: number,
	bottomY: number,
	material: Enum.Material,
	lobes: number,
	jag: number?
)
	local rng = ctx.rng
	local terrain = ctx.terrain
	terrain:FillCylinder(
		CFrame.new(center.X, (topY + bottomY) / 2, center.Z),
		topY - bottomY,
		core,
		material
	)
	local phase = rng:NextNumber(0, math.pi * 2)
	for i = 1, lobes do
		local a = phase + (i / lobes) * math.pi * 2 + rng:NextNumber(-0.25, 0.25)
		local r = (reach - core) * rng:NextNumber(0.9, 1.6) + 4
		local dist = reach - r * rng:NextNumber(0.85, 1.05)
		local p = center + Vector3.new(math.cos(a) * dist, 0, math.sin(a) * dist)
		local top = topY - rng:NextNumber(0, jag or 0)
		terrain:FillCylinder(CFrame.new(p.X, (top + bottomY) / 2, p.Z), top - bottomY, r, material)
	end
end

-- A rounded lump of land at a zone-local spot (headland, lower terrace,
-- grassy hill): an irregular disc from the sea bed up to topY.
function Geo.lobe(
	ctx: Context,
	zone: ZoneContext,
	x: number,
	z: number,
	core: number,
	reach: number,
	topY: number,
	material: Enum.Material,
	jag: number?
)
	local p = Geo.at(zone, x, z, 0)
	Geo.disc(ctx, Vector3.new(p.X, 0, p.Z), core, reach, topY, -16, material, 5, jag)
end

-- Paints the zone's catch floor: a trim band along the footprint edge and
-- a bold two-tone pattern inside, all flat at the floor height.
function Geo.field(ctx: Context, zone: ZoneContext, look: FieldLook)
	local slot = zone.slot
	local frame = slot.frame
	local floor = slot.floor
	local depthPaint = 8
	local function block(x0: number, x1: number, z0: number, z1: number, material: Enum.Material)
		local c = frame:PointToWorldSpace(Vector3.new((x0 + x1) / 2, 0, (z0 + z1) / 2))
		ctx.terrain:FillBlock(
			CFrame.new(c.X, floor - depthPaint / 2, c.Z) * frame.Rotation,
			Vector3.new(x1 - x0, depthPaint, z1 - z0),
			material
		)
	end
	local hw, hd = slot.width / 2, slot.depth / 2
	block(-hw - 3, hw + 3, -hd - 3, hd + 3, look.trim)
	local iw, id = hw - 1, hd - 1
	block(-iw, iw, -id, id, look.base)
	local function count(span: number): number
		local n = math.max(3, math.floor(span / look.cell + 0.5))
		if n % 2 == 0 then
			n += 1
		end
		return n
	end
	if look.pattern == "checker" then
		local nx, nz = count(2 * iw), count(2 * id)
		local sx, sz = 2 * iw / nx, 2 * id / nz
		for i = 0, nx - 1 do
			for j = 0, nz - 1 do
				if (i + j) % 2 == 1 then
					block(
						-iw + i * sx,
						-iw + (i + 1) * sx,
						-id + j * sz,
						-id + (j + 1) * sz,
						look.accent
					)
				end
			end
		end
	elseif look.pattern == "along" then
		local n = count(2 * iw)
		local s = 2 * iw / n
		for i = 1, n - 2, 2 do
			block(-iw + i * s, -iw + (i + 1) * s, -id, id, look.accent)
		end
	else
		local n = count(2 * id)
		local s = 2 * id / n
		for i = 1, n - 2, 2 do
			block(-iw, iw, -id + i * s, -id + (i + 1) * s, look.accent)
		end
	end
end

-- A hoodoo / sea stack: stacked bands of alternating materials, a little
-- narrower each band, with a wider cap rock on top.
function Geo.stack(
	ctx: Context,
	base: Vector3,
	radius: number,
	topY: number,
	materials: { Enum.Material },
	capMaterial: Enum.Material?
)
	local rng = ctx.rng
	local y = base.Y
	local band = 0
	local r = radius
	local wobble = Vector3.zero
	while y < topY - 0.5 do
		local h = math.min(rng:NextNumber(3.5, 6), topY - y)
		band += 1
		local material = materials[(band - 1) % #materials + 1]
		local c = base + wobble
		ctx.terrain:FillCylinder(CFrame.new(c.X, y + h / 2, c.Z), h + 0.5, r, material)
		y += h
		r = math.max(radius * 0.55, r * rng:NextNumber(0.9, 0.99))
		wobble += Vector3.new(rng:NextNumber(-0.6, 0.6), 0, rng:NextNumber(-0.6, 0.6))
	end
	if capMaterial then
		local c = base + wobble
		ctx.terrain:FillCylinder(CFrame.new(c.X, topY - 1.5, c.Z), 3, r * 1.35, capMaterial)
	end
end

return Geo
