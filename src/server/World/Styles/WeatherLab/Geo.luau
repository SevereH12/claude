--!strict
-- Geometry helpers for WeatherLab: zone-local coordinates and terrain
-- landmasses. Islands are contour-nested terraces (one shared wobble per
-- island, filled as a fan of blocks), kept clear of the hub and of each
-- other; every outline is remembered on the build context so props can
-- ask for ground height (heightAt/groundAt) or open water (seaward).
-- Also irregular blobs, ponds, rim bands and painted fields. Zone-local
-- studs: x runs across the zone (right when facing the hub), z runs from
-- the centre toward the back edge (+) or the gate edge (-), y is above
-- the zone floor. Works for any slot position, rotation and size.

local ServerScriptService = game:GetService("ServerScriptService")

local WLTypes = require(script.Parent.WLTypes)
local WorldTypes = require(ServerScriptService.Server.World.Types)

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
-- back only when `noFront` is set, and standing on the island's top
-- terrace (on any land above the sea with `anyLand`). Returns x, z.
function Geo.rimPoint(
	ctx: Context,
	zone: ZoneContext,
	near: number,
	far: number,
	noFront: boolean?,
	anyLand: boolean?
): (number, number)
	local rng = ctx.rng
	local hw, hd = zone.slot.width / 2, zone.slot.depth / 2
	local key = Geo.key(zone)
	local checkLand = Geo.hasGround(ctx, key)
	local floor = zone.slot.floor
	for _ = 1, 40 do
		local x = rng:NextNumber(-hw - far, hw + far)
		local z = rng:NextNumber(-hd - far, hd + far)
		local out = Geo.outside(zone, x, z)
		local frontOk = not noFront or z > -hd + 4
		if out >= near and out <= far and frontOk then
			local landOk = true
			if checkLand then
				local h = Geo.heightAt(ctx, key, Geo.at(zone, x, z, 0))
				landOk = h ~= nil and (if anyLand then h > 0.5 else h >= floor - 0.5)
			end
			if landOk then
				return x, z
			end
		end
	end
	return hw + near, 0
end

-- Detail budget: 1 with up to two zones, thinning the scattered small
-- props (and widening border post spacing) as more zones are added, so a
-- growing world stays near its part budget.
function Geo.detail(ctx: Context): number
	return math.clamp(1 - 0.25 * (#ctx.zones - 2), 0.35, 1)
end

-- `n` scattered props scaled by the detail budget (at least one).
function Geo.count(ctx: Context, n: number): number
	return math.max(1, math.floor(n * Geo.detail(ctx) + 0.5))
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
	ctx: Context,
	zone: ZoneContext,
	spots: Spots,
	near: number,
	far: number,
	r: number,
	noFront: boolean?,
	anyLand: boolean?
): (number?, number?)
	local hd = zone.slot.depth / 2
	for _ = 1, 30 do
		local x, z = Geo.rimPoint(ctx, zone, near + r, far, noFront, anyLand)
		local landing = z < -hd + 1 and math.abs(x) < 13 + r
		if not landing and Geo.free(spots, x, z, r) then
			Geo.claim(spots, x, z, r)
			return x, z
		end
	end
	return nil, nil
end

-- Terrain ------------------------------------------------------------------------

-- A smooth random wobble round a circle: low harmonics (2..8 lobes) with
-- random phases, roughly in -1..1. theta is in radians.
export type Wave = (theta: number) -> number

function Geo.wave(rng: Random): Wave
	local ks = { 2, 3, rng:NextInteger(4, 5), rng:NextInteger(6, 8) }
	local amps = { 1, 0.8, 0.5, 0.3 }
	local phases = {}
	local total = 0
	for i in ks do
		phases[i] = rng:NextNumber(0, math.pi * 2)
		total += amps[i]
	end
	local scale = 1 / (total * 0.6)
	return function(theta: number): number
		local s = 0
		for i, k in ks do
			s += amps[i] * math.sin(k * theta + phases[i])
		end
		return math.clamp(s * scale, -1, 1)
	end
end

-- Fills the star-shaped region round `frame`'s origin whose edge lies
-- radius(theta) studs out along each local ground direction (theta in
-- radians clockwise from local -Z), from bottomY to topY (world heights).
-- A fan of thin blocks fills the body; cylinders along the outline round
-- it off, their tops dropped by up to `jag` so lower terraces look worn.
function Geo.fan(
	ctx: Context,
	frame: CFrame,
	radius: (theta: number) -> number,
	samples: number,
	topY: number,
	bottomY: number,
	material: Enum.Material,
	jag: number?
)
	local rng = ctx.rng
	local terrain = ctx.terrain
	local height = topY - bottomY
	local midY = (topY + bottomY) / 2
	local origin = frame.Position
	local rotation = frame.Rotation
	local spread = math.tan(math.pi / samples) * 2.5
	for i = 0, samples - 1 do
		local theta = (i + rng:NextNumber(-0.15, 0.15)) / samples * math.pi * 2
		local dir = rotation:VectorToWorldSpace(Vector3.new(math.sin(theta), 0, -math.cos(theta)))
		local r = math.max(radius(theta), 2)
		local width = r * spread + 1.5
		local c = origin + dir * (r / 2)
		local centre = Vector3.new(c.X, midY, c.Z)
		terrain:FillBlock(
			CFrame.lookAt(centre, centre + dir),
			Vector3.new(width, height, r),
			material
		)
		local edgeR = width * 0.55 + 1
		local edge = origin + dir * (r - edgeR * 0.5)
		local top = topY - rng:NextNumber(0, jag or 0)
		terrain:FillCylinder(
			CFrame.new(edge.X, (top + bottomY) / 2, edge.Z),
			top - bottomY,
			edgeR,
			material
		)
	end
end

-- Distance from the centre of a rounded rectangle (half sizes a, b, corner
-- radius c) to its edge along the unit direction (dx, dz).
local function rayToRoundRect(a: number, b: number, c: number, dx: number, dz: number): number
	local lo, hi = 0, math.sqrt(a * a + b * b) + 1
	for _ = 1, 16 do
		local mid = (lo + hi) / 2
		local qx = math.abs(dx * mid) - (a - c)
		local qz = math.abs(dz * mid) - (b - c)
		local ox, oz = math.max(qx, 0), math.max(qz, 0)
		local sdf = math.sqrt(ox * ox + oz * oz) + math.min(math.max(qx, qz), 0) - c
		if sdf > 0 then
			hi = mid
		else
			lo = mid
		end
	end
	return lo
end

-- Every terrace outline is remembered (per zone, or per hub) so props can
-- ask how high the land is at a spot, or find open water for a buoy.
-- Keys are names ("Hub", a zone id, "ComingSoon"). The state lives on the
-- build context, so every module (and every rebuild) sees the right one.
type Layer = { frame: CFrame, radius: (theta: number) -> number, top: number }
type State = { registry: { [string]: { Layer } }, waves: { [string]: Wave } }

local function state(ctx: Context): State
	local holder = ctx :: any
	if not holder.weatherLab then
		holder.weatherLab = { registry = {}, waves = {} }
	end
	return holder.weatherLab :: State
end

-- Registry key for a zone (or the teaser).
function Geo.key(zone: ZoneContext): string
	return if zone.isTeaser then "ComingSoon" else zone.folder.Name
end

function Geo.register(
	ctx: Context,
	key: string,
	frame: CFrame,
	radius: (theta: number) -> number,
	top: number
)
	local registry = state(ctx).registry
	local list = registry[key]
	if not list then
		list = {}
		registry[key] = list
	end
	table.insert(list, { frame = frame, radius = radius, top = top })
end

-- Has anything been remembered under this key?
function Geo.hasGround(ctx: Context, key: string): boolean
	local layers = state(ctx).registry[key]
	return layers ~= nil and #layers > 0
end

-- Top of the highest remembered terrace under a world point (nil = sea).
function Geo.heightAt(ctx: Context, key: string, p: Vector3): number?
	local best: number? = nil
	local layers: { Layer } = state(ctx).registry[key] or {}
	for _, layer in layers do
		local l = layer.frame:PointToObjectSpace(Vector3.new(p.X, layer.frame.Position.Y, p.Z))
		local d = math.sqrt(l.X * l.X + l.Z * l.Z)
		if
			d <= layer.radius(math.atan2(l.X, -l.Z))
			and (best == nil or layer.top > (best :: number))
		then
			best = layer.top
		end
	end
	return best
end

-- Ground height (world y) at a zone-local spot; sea level 0 over water.
function Geo.groundAt(ctx: Context, zone: ZoneContext, x: number, z: number): number
	local h = Geo.heightAt(ctx, Geo.key(zone), Geo.at(zone, x, z, 0))
	return if h and h > 0 then h else 0
end

-- Moves a zone-local spot straight away from the zone centre until it is
-- over water at least `clear` studs deep (or gives up). Returns x, z.
function Geo.seaward(
	ctx: Context,
	zone: ZoneContext,
	x: number,
	z: number,
	clear: number
): (number, number)
	local len = math.max(math.sqrt(x * x + z * z), 1)
	local ux, uz = x / len, z / len
	for _ = 1, 12 do
		local h = Geo.heightAt(ctx, Geo.key(zone), Geo.at(zone, x, z, 0))
		if h == nil or h <= -clear then
			break
		end
		x += ux * 5
		z += uz * 5
	end
	return x, z
end

-- A band of `material` traced along the outline of the zone's terrace whose
-- top is `topY` (cap rock, dune grass, a hedge line): `width` studs wide,
-- flush with the terrace top, on `coverage` (0..1) of the outline.
function Geo.rim(
	ctx: Context,
	zone: ZoneContext,
	topY: number,
	material: Enum.Material,
	width: number,
	coverage: number
)
	local layers: { Layer } = state(ctx).registry[Geo.key(zone)] or {}
	local layer: Layer? = nil
	for _, l in layers do
		if math.abs(l.top - topY) < 0.01 then
			layer = l
		end
	end
	if not layer then
		return
	end
	local rng = ctx.rng
	local frame = layer.frame
	local samples = math.max(24, math.floor(layer.radius(0) * math.pi * 2 / (width * 1.3)))
	for i = 0, samples - 1 do
		if rng:NextNumber() < coverage then
			local theta = (i + rng:NextNumber(-0.35, 0.35)) / samples * math.pi * 2
			local w = width * rng:NextNumber(0.6, 1.35)
			local r = layer.radius(theta) - w * rng:NextNumber(0.35, 0.8)
			local p =
				frame:PointToWorldSpace(Vector3.new(math.sin(theta) * r, 0, -math.cos(theta) * r))
			ctx.terrain:FillCylinder(CFrame.new(p.X, topY - 1.5, p.Z), 3, w, material)
		end
	end
end

-- One shared wobble per zone, so every terrace of an island follows the
-- same headlands and coves like contour lines on a map.
function Geo.zoneWave(ctx: Context, zone: ZoneContext): Wave
	local waves = state(ctx).waves
	local key = Geo.key(zone)
	local wave = waves[key]
	if not wave then
		wave = Geo.wave(ctx.rng)
		waves[key] = wave
	end
	return wave
end

-- How much of a terrace's outward growth survives straight in front of
-- the gate (local -Z, toward the hub): less, so boardwalks arrive over water.
local function frontDamp(theta: number): number
	local dz = -math.cos(theta)
	local f = math.clamp((dz + 0.94) / 0.3, 0, 1)
	return 0.3 + 0.7 * f * f * (3 - 2 * f)
end

-- Islands never reach closer than this to the hub centre, so the bay
-- round the hub stays open water.
local HUB_CLEARANCE = 26
-- Land above water stays at least this much nearer its own footprint than
-- any neighbour's, so neighbouring islands never merge.
local CHANNEL = 14

-- Ground distance from a world point to a slot's footprint (0 inside).
local function slotDistance(slot: WorldTypes.Slot, p: Vector3): number
	local l = slot.frame:PointToObjectSpace(Vector3.new(p.X, slot.floor, p.Z))
	local dx = math.max(math.abs(l.X) - slot.width / 2, 0)
	local dz = math.max(math.abs(l.Z) - slot.depth / 2, 0)
	return math.sqrt(dx * dx + dz * dz)
end
local LANDING_HALF = 16 -- gate-side stretch kept straight for the boardwalk

-- A terrace around a zone: its footprint plus the margins (always covered,
-- apart from small coves on the gate side away from the boardwalk), grown
-- outward by about `grow` studs with big smooth headlands and coves.
-- `wild` (0..1) lets the growth swing from nothing (the terrace above
-- drops straight into the sea) to about twice `grow` (a headland or sand
-- spit); with wild = 0 the terrace only bulges outward a little, so props
-- on the rim always stand on it. `bump` scales the wobble and the corner
-- rounding; `jag` lowers the outline unevenly.
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
	local rng = ctx.rng
	local slot = zone.slot
	local hw, hd = slot.width / 2, slot.depth / 2
	local a = hw + m.side
	local z0, z1 = -hd - m.front, hd + m.back
	local b = (z1 - z0) / 2
	local corner = math.min(a, b, bump * 2 + grow * 0.5)
	local frame = slot.frame * CFrame.new(0, 0, (z0 + z1) / 2)
	local rotation = frame.Rotation
	local shared = Geo.zoneWave(ctx, zone)
	local own = Geo.wave(rng)
	local w = wild or 0
	local amp = if w > 0 then (grow * 0.9 + bump * 1.6) * w else bump * 1.5
	-- coves along the gate side of the top terraces
	local recede = if w == 0 then math.max(m.front - 6, 0) else 0
	local coveFreq, covePhase = math.pi * 2 / rng:NextNumber(34, 46), rng:NextNumber(0, math.pi * 2)
	-- keep out of a circle round the hub
	local centre = frame.Position
	local o = Vector3.new(centre.X, 0, centre.Z)
	local limit = ctx.layout.hubRadius + HUB_CLEARANCE
	local function clip(dir: Vector3, r: number): number
		local od = o:Dot(dir)
		local disc = od * od - (o:Dot(o) - limit * limit)
		if disc <= 0 then
			return r
		end
		local enter = -od - math.sqrt(disc)
		if enter <= 0 then
			return r
		end
		return math.min(r, enter)
	end
	-- neighbouring zones (and the teaser) to keep a channel from
	local neighbours: { WorldTypes.Slot } = {}
	if topY > 0 then
		for _, other in ctx.zones do
			if other.slot ~= slot then
				table.insert(neighbours, other.slot)
			end
		end
		if ctx.teaser.slot ~= slot then
			table.insert(neighbours, ctx.teaser.slot)
		end
	end
	local function channel(dir: Vector3, lo: number, hi: number): number
		local function ok(r: number): boolean
			local p = centre + dir * r
			for _, other in neighbours do
				if slotDistance(other, p) - slotDistance(slot, p) < CHANNEL then
					return false
				end
			end
			return true
		end
		if ok(hi) then
			return hi
		end
		for _ = 1, 10 do
			local mid = (lo + hi) / 2
			if ok(mid) then
				lo = mid
			else
				hi = mid
			end
		end
		return lo
	end
	local function radius(theta: number): number
		local dx, dz = math.sin(theta), -math.cos(theta)
		local n = shared(theta) * 0.7 + own(theta) * 0.3
		local extend = if w > 0 then math.max(0, grow + amp * n) else grow + amp * (0.5 + 0.5 * n)
		local base = rayToRoundRect(a, b, corner, dx, dz)
		local dir = rotation:VectorToWorldSpace(Vector3.new(dx, 0, dz))
		local r = clip(dir, base + extend * frontDamp(theta))
		if #neighbours > 0 and r > base then
			r = channel(dir, base, r)
		end
		r = math.max(r, base)
		if recede > 0 and dz < 0 then
			local lx = dx * base
			local away = math.clamp((math.abs(lx) - LANDING_HALF) / 8, 0, 1)
			local front = math.clamp(-dz * 1.8 - 0.8, 0, 1)
			r -= recede * away * front * (0.5 + 0.5 * math.sin(lx * coveFreq + covePhase))
		end
		return r
	end
	local reach = math.max(a, b) + grow + amp
	local samples = math.clamp(math.floor(reach * math.pi * 2 / 11), 32, 90)
	Geo.fan(ctx, frame, radius, samples, topY, bottomY, material, jag)
	Geo.register(ctx, Geo.key(zone), frame, radius, topY)
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

-- Irregular blob of land: always covers `core` round the centre and
-- reaches out to about `reach` in a few smooth lobes. Top at topY.
function Geo.disc(
	ctx: Context,
	center: Vector3,
	core: number,
	reach: number,
	topY: number,
	bottomY: number,
	material: Enum.Material,
	jag: number?
)
	local wave = Geo.wave(ctx.rng)
	local samples = math.clamp(math.floor(reach * math.pi * 2 / 7), 14, 48)
	Geo.fan(ctx, CFrame.new(center.X, 0, center.Z), function(theta: number): number
		return core + (reach - core) * (0.5 + 0.5 * wave(theta))
	end, samples, topY, bottomY, material, jag)
end

-- An organic pond or lagoon: carves the land above `surfaceY` away and
-- fills water below it down to `depth`, on a sand bed, all in one wobbly
-- outline reaching from `core` to `reach` studs round the centre.
function Geo.pond(
	ctx: Context,
	center: Vector3,
	core: number,
	reach: number,
	surfaceY: number,
	depth: number,
	carveTop: number?
)
	local wave = Geo.wave(ctx.rng)
	local function radius(theta: number): number
		return core + (reach - core) * (0.5 + 0.5 * wave(theta))
	end
	local frame = CFrame.new(center.X, 0, center.Z)
	local samples = math.clamp(math.floor(reach * math.pi * 2 / 6), 14, 40)
	Geo.fan(ctx, frame, function(theta: number): number
		return radius(theta) + 1.5
	end, samples, surfaceY - depth + 0.5, surfaceY - depth - 2, Enum.Material.Sand)
	if carveTop then
		Geo.fan(ctx, frame, radius, samples, carveTop, surfaceY, Enum.Material.Air)
	end
	-- the water itself from cylinders only: a core plus a ring of lobes
	local terrain = ctx.terrain
	local midY = surfaceY - depth / 2
	terrain:FillCylinder(
		CFrame.new(center.X, midY, center.Z),
		depth,
		core + 0.5,
		Enum.Material.Water
	)
	local lobes = math.max(6, math.floor(reach))
	for i = 0, lobes - 1 do
		local theta = i / lobes * math.pi * 2
		local lobeR = math.max((radius(theta) - core) * 0.6 + 2, 2)
		local d = radius(theta) + 1 - lobeR
		terrain:FillCylinder(
			CFrame.new(center.X + math.sin(theta) * d, midY, center.Z - math.cos(theta) * d),
			depth,
			lobeR,
			Enum.Material.Water
		)
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
	Geo.disc(ctx, Vector3.new(p.X, 0, p.Z), core, reach, topY, -16, material, jag)
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
