--!strict
-- Geometry helpers for WeatherLab: zone-local coordinates, prop spots,
-- the part budget and the ground registry. Land (the block builder)
-- remembers the top of every flat piece of ground it lays, per island, so
-- props can ask how high the ground is (heightAt/groundAt) or find open
-- water (seaward). Zone-local studs: x runs across the zone (right when
-- facing the hub), z runs from the centre toward the back edge (+) or the
-- gate edge (-), y is above the zone floor. Works for any slot position, rotation and size.

local ServerScriptService = game:GetService("ServerScriptService")

local WLTypes = require(script.Parent.WLTypes)
local WorldTypes = require(ServerScriptService.Server.World.Types)

type Context = WLTypes.Context
type ZoneContext = WLTypes.ZoneContext

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
-- back only when `noFront` is set, and standing on the plateau top at the
-- floor height (on any land above the sea with `anyLand`). Returns x, z.
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
				landOk = h ~= nil
					and (if anyLand then h > 0.5 else math.abs((h :: number) - floor) < 0.3)
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
-- A free spot within `spread` studs of (cx, cz), at least `minOut` studs
-- outside the footprint and on the plateau top: for grouping props into
-- little vignettes instead of spreading them evenly.
function Geo.nearSpot(
	ctx: Context,
	zone: ZoneContext,
	spots: Spots,
	cx: number,
	cz: number,
	spread: number,
	r: number,
	minOut: number
): (number?, number?)
	local rng = ctx.rng
	local key = Geo.key(zone)
	local floor = zone.slot.floor
	for _ = 1, 24 do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = spread * math.sqrt(rng:NextNumber())
		local x, z = cx + math.cos(a) * d, cz + math.sin(a) * d
		if Geo.outside(zone, x, z) >= minOut + r and Geo.free(spots, x, z, r) then
			local h = Geo.heightAt(ctx, key, Geo.at(zone, x, z, 0))
			if h ~= nil and math.abs(h - floor) < 0.3 then
				Geo.claim(spots, x, z, r)
				return x, z
			end
		end
	end
	return nil, nil
end

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

-- Ground registry -------------------------------------------------------------------
-- Every flat top Land lays is remembered under a key ("Hub", a zone id,
-- "ComingSoon"): a regular polygon (as Blocks.disc builds it) or a
-- rectangle, square or with rounded corners. heightAt answers with the highest top under a
-- point. Sloped beach wedges are not remembered: props treat them as sea.
-- The state lives on the build context, so every module (and every
-- rebuild) sees the right one.
type Top = {
	kind: string, -- "poly" or "rect"
	frame: CFrame, -- level, at the shape's centre (its yaw included)
	a: number, -- poly: apothem; rect: half width (local x)
	b: number, -- rect: half depth (local z)
	c: number, -- rect: corner rounding (0 = square corners)
	n: number, -- poly: sides
	top: number,
}
type State = {
	registry: { [string]: { Top } },
	hubParts: number?,
}

local function state(ctx: Context): State
	local holder = ctx :: any
	if not holder.weatherLab then
		holder.weatherLab = { registry = {}, hubParts = nil }
	end
	return holder.weatherLab :: State
end

local function remember(ctx: Context, key: string, entry: Top)
	local registry = state(ctx).registry
	local list = registry[key]
	if not list then
		list = {}
		registry[key] = list
	end
	table.insert(list, entry)
end

-- A regular polygon top laid by Blocks.disc at `frame` (level, yaw included).
function Geo.addPoly(ctx: Context, key: string, frame: CFrame, apothem: number, sides: number)
	remember(ctx, key, {
		kind = "poly",
		frame = frame,
		a = apothem,
		b = 0,
		c = 0,
		n = sides,
		top = frame.Position.Y,
	})
end

-- A rectangle top centred at `frame`; with `round` > 0 its corners are cut
-- by two facets each, as Land.roundRect builds them.
function Geo.addRect(
	ctx: Context,
	key: string,
	frame: CFrame,
	hx: number,
	hz: number,
	round: number
)
	remember(ctx, key, {
		kind = "rect",
		frame = frame,
		a = hx,
		b = hz,
		c = round,
		n = 0,
		top = frame.Position.Y,
	})
end

local FACETS = {
	Vector2.new(math.cos(math.rad(30)), math.sin(math.rad(30))),
	Vector2.new(math.cos(math.rad(60)), math.sin(math.rad(60))),
}

local function contains(t: Top, p: Vector3): boolean
	local l = t.frame:PointToObjectSpace(Vector3.new(p.X, t.frame.Position.Y, p.Z))
	if t.kind == "rect" then
		local x, z = math.abs(l.X), math.abs(l.Z)
		if x > t.a + 1e-6 or z > t.b + 1e-6 then
			return false
		end
		local d = Vector2.new(x - (t.a - t.c), z - (t.b - t.c))
		if t.c > 0 and d.X > 0 and d.Y > 0 then
			for _, facet in FACETS do
				if d:Dot(facet) > t.c + 1e-6 then
					return false
				end
			end
		end
		return true
	end
	-- Blocks.disc puts side i's outward normal at yaw i * 360 / n
	for i = 0, t.n - 1 do
		local phi = i * 2 * math.pi / t.n
		if -math.sin(phi) * l.X - math.cos(phi) * l.Z > t.a + 1e-6 then
			return false
		end
	end
	return true
end

-- Registry key for a zone (or the teaser).
function Geo.key(zone: ZoneContext): string
	return if zone.isTeaser then "ComingSoon" else zone.folder.Name
end

-- Has anything been remembered under this key?
function Geo.hasGround(ctx: Context, key: string): boolean
	local tops = state(ctx).registry[key]
	return tops ~= nil and #tops > 0
end

-- Top of the highest remembered ground under a world point (nil = sea).
function Geo.heightAt(ctx: Context, key: string, p: Vector3): number?
	local best: number? = nil
	local tops: { Top } = state(ctx).registry[key] or {}
	for _, t in tops do
		if (best == nil or t.top > (best :: number)) and contains(t, p) then
			best = t.top
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
-- over water at least `clear` studs deep, then on past the beach slopes
-- (Land does not remember those), or gives up. Returns x, z.
local SLOPE_CLEAR = 16

function Geo.seaward(
	ctx: Context,
	zone: ZoneContext,
	x: number,
	z: number,
	clear: number
): (number, number)
	local len = math.max(math.sqrt(x * x + z * z), 1)
	local ux, uz = x / len, z / len
	for _ = 1, 16 do
		local h = Geo.heightAt(ctx, Geo.key(zone), Geo.at(zone, x, z, 0))
		if h == nil or h <= -clear then
			return x + ux * SLOPE_CLEAR, z + uz * SLOPE_CLEAR
		end
		x += ux * 5
		z += uz * 5
	end
	return x, z
end

-- Part budget -------------------------------------------------------------------
-- The whole map stays under PART_CAP however many zones there are: the
-- hub (with its ground) is counted once, before the first zone, the
-- teaser keeps a fixed reserve and every zone gets an equal share of the
-- rest for its ground, island dressing, boardwalk, border and gate.
-- Themes build their hero landmark and essentials first and ask Geo.room
-- before each optional prop, so the 1st-2nd zones get full detail and
-- later zones a lighter dressing.
-- (2,450 keeps a two-zone world near 2,350 parts and any world under the
-- 2,500 hard cap until the essentials alone outgrow it, past ~6 zones)
local PART_CAP = 2450
local TEASER_RESERVE = 290

local function countParts(root: Instance): number
	local n = 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

-- Call once before the first zone is built: remembers the hub's cost.
function Geo.markHub(ctx: Context)
	local st = state(ctx)
	if st.hubParts == nil then
		st.hubParts = countParts(ctx.map)
	end
end

-- Parts each zone may use (its ground, ZoneArt and connector).
function Geo.allowance(ctx: Context): number
	local hub = state(ctx).hubParts or 650
	return math.floor((PART_CAP - TEASER_RESERVE - hub) / math.max(#ctx.zones, 1))
end

function Geo.used(ctx: Context, zone: ZoneContext): number
	local n = countParts(zone.folder)
	for _, holder in { ctx.folders.connectors, ctx.folders.ground } do
		local folder = holder:FindFirstChild(zone.folder.Name)
		if folder then
			n += countParts(folder)
		end
	end
	return n
end

-- Is there budget left in this zone for `cost` more parts?
function Geo.room(ctx: Context, zone: ZoneContext, cost: number): boolean
	if zone.isTeaser then
		return true
	end
	return Geo.used(ctx, zone) + cost <= Geo.allowance(ctx)
end

-- Neighbours -----------------------------------------------------------------------

-- Ground distance from a world point to a slot's footprint (0 inside).
local function slotDistance(slot: WorldTypes.Slot, p: Vector3): number
	local l = slot.frame:PointToObjectSpace(Vector3.new(p.X, slot.floor, p.Z))
	local dx = math.max(math.abs(l.X) - slot.width / 2, 0)
	local dz = math.max(math.abs(l.Z) - slot.depth / 2, 0)
	return math.sqrt(dx * dx + dz * dz)
end

-- True when a disc of radius r at world point p keeps `margin` studs from
-- every other zone footprint, the teaser and the hub.
function Geo.clearOf(
	ctx: Context,
	zone: ZoneContext,
	p: Vector3,
	r: number,
	margin: number
): boolean
	for _, other in ctx.zones do
		if other.slot ~= zone.slot and slotDistance(other.slot, p) < r + margin then
			return false
		end
	end
	if ctx.teaser.slot ~= zone.slot and slotDistance(ctx.teaser.slot, p) < r + margin then
		return false
	end
	return Vector3.new(p.X, 0, p.Z).Magnitude > ctx.layout.hubRadius + r + margin
end

return Geo
