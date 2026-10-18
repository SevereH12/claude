--!strict
-- Geometry, placement and randomness helpers shared by every StormPunk module.
--
-- Randomness: every zone (and the hub, the base...) draws from its own
-- Random, seeded from one number taken from ctx.rng plus a key. Adding a
-- zone therefore never reshuffles the decoration of the zones before it.

local ServerScriptService = game:GetService("ServerScriptService")

local World = ServerScriptService.Server.World
local Kit = require(World.Kit)
local WorldTypes = require(World.Types)

type Context = WorldTypes.Context
type ZoneContext = WorldTypes.ZoneContext

local Geo = {}

-- Half-width of the clear corridor kept around every connector.
Geo.CORRIDOR = 9
-- Sea levels: the see-through water surface, the solid seabed a few studs
-- under it (walkable, so anyone who falls in wades back out up a shore
-- slope) and the beach tops just above the water.
Geo.WATER = 0
Geo.SEA_FLOOR = -3
Geo.BEACH = 1
-- The spiral visits 8 bearings; slot 9 would sit on slot 1's bearing and
-- its straight connector would cross zone 1. StormPunk supports 7 zones
-- plus the teaser.
Geo.MAX_ZONES = 7

-- Bearings (degrees clockwise from north) -----------------------------------

function Geo.dir(angleDeg: number): Vector3
	local a = math.rad(angleDeg)
	return Vector3.new(math.sin(a), 0, -math.cos(a))
end

function Geo.polar(angleDeg: number, radius: number, y: number): Vector3
	return Geo.dir(angleDeg) * radius + Vector3.new(0, y, 0)
end

-- The yaw (radians, for CFrame.Angles) that points a shape's local -Z, and
-- so one face of every Land polygon, along a bearing.
function Geo.faceYaw(bearing: number): number
	return -math.rad(bearing)
end

function Geo.bearingOf(position: Vector3): number
	return math.deg(math.atan2(position.X, -position.Z)) % 360
end

-- Signed smallest difference a - b in degrees (-180..180).
function Geo.angleDiff(a: number, b: number): number
	return ((a - b + 180) % 360) - 180
end

-- Every bearing the spiral will ever use for an exit (from the layout
-- only, so zones added later always land on one of these).
function Geo.exitBearings(ctx: Context): { number }
	local layout = ctx.layout
	local out: { number } = {}
	for i = 0, 15 do
		local a = (layout.firstAngle + i * layout.angleStep) % 360
		local seen = false
		for _, b in out do
			if math.abs(Geo.angleDiff(a, b)) < 1 then
				seen = true
			end
		end
		if not seen then
			table.insert(out, a)
		end
	end
	table.sort(out)
	return out
end

-- Bearings exactly between the spiral's exit bearings: hub props live on
-- these so a future zone's exit is never blocked.
function Geo.quietBearings(ctx: Context): { number }
	local exits = Geo.exitBearings(ctx)
	local out = {}
	for i, a in exits do
		local nextA = exits[i % #exits + 1]
		local gap = (nextA - a) % 360
		if gap == 0 then
			gap = 360
		end
		table.insert(out, (a + gap / 2) % 360)
	end
	return out
end

-- The quiet bearing for the spawn and the sell station: across the hub
-- from the first zones, so the spawn looks over the plaza toward zones 1-3
-- (from the layout only: adding zones never moves it).
function Geo.spawnBearing(ctx: Context): number
	local layout = ctx.layout
	local ideal = layout.firstAngle + 180 + 1.5 * layout.angleStep
	local best, bestDiff = 0, math.huge
	for _, b in Geo.quietBearings(ctx) do
		local diff = math.abs(Geo.angleDiff(b, ideal))
		if diff < bestDiff then
			best, bestDiff = b, diff
		end
	end
	return best
end

-- Is a hub point within `clearance` of any exit lane (future ones too)?
-- Lanes run from the inner brass ring (r = 26) out to the hub rim.
function Geo.inExitLane(ctx: Context, position: Vector3, clearance: number): boolean
	local R = ctx.layout.hubRadius
	for _, b in Geo.exitBearings(ctx) do
		if
			Geo.segmentDistance(position, Geo.polar(b, 26, 0), Geo.polar(b, R + 6, 0)) < clearance
		then
			return true
		end
	end
	return false
end

-- Seeded randomness ------------------------------------------------------------

-- weak keys: an old build's Context (and its destroyed Map) can be collected
local baseSeeds: { [Context]: number } = setmetatable({}, { __mode = "k" }) :: any

local function hash(text: string): number
	local h = 5381
	for i = 1, #text do
		h = (h * 33 + string.byte(text, i)) % 2147483647
	end
	return h
end
Geo.hash = hash

-- Call first (from atmosphere): takes one number from ctx.rng.
function Geo.init(ctx: Context)
	if baseSeeds[ctx] == nil then
		baseSeeds[ctx] = ctx.rng:NextInteger(1, 1000000)
	end
end

function Geo.rng(ctx: Context, key: string): Random
	Geo.init(ctx)
	return Random.new((baseSeeds[ctx] + hash(key)) % 2147483647)
end

function Geo.zoneKey(zone: ZoneContext): string
	local def = zone.def
	return if def then def.id else `slot{zone.slot.index}`
end

-- Part budget ---------------------------------------------------------------------
-- The ground is part-built, so its optional pieces (beach lobes, column
-- counts, polygon sides, scenery) are allocated here. A zone's ground detail
-- depends only on its own spiral index (zones 1-2 full, later zones leaner,
-- like a distance LOD), so adding a zone never changes an earlier zone's
-- ground or the props standing on it. The hub's scattered scenery thins
-- with the zone count instead. Sized so 7 zones + the teaser stay under the
-- 2,500-part cap (about 1,500 parts with 2 zones).

-- 1 (full) for zones 1-2, 0 (lean) from zone 3 on and for the teaser.
function Geo.zoneDetail(zone: ZoneContext): number
	return if not zone.isTeaser and zone.slot.index <= 2 then 1 else 0
end

-- 1 with up to two zones, 0 at Geo.MAX_ZONES (hub scenery only).
function Geo.worldDetail(ctx: Context): number
	return math.clamp((Geo.MAX_ZONES - #ctx.zones) / (Geo.MAX_ZONES - 2), 0, 1)
end

-- A whole number from `low` (detail 0) to `high` (detail 1).
function Geo.count(detail: number, low: number, high: number): number
	return math.floor(low + (high - low) * detail + 0.5)
end

-- An even polygon side count from `low` (detail 0) to `high` (detail 1).
function Geo.sides(detail: number, low: number, high: number): number
	local n = Geo.count(detail, low, high)
	return n + n % 2
end

-- Space checks -------------------------------------------------------------------

-- Distance on the ground plane from p to segment a-b.
function Geo.segmentDistance(p: Vector3, a: Vector3, b: Vector3): number
	local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local ap = Vector3.new(p.X - a.X, 0, p.Z - a.Z)
	local len2 = ab:Dot(ab)
	local t = if len2 > 0 then math.clamp(ap:Dot(ab) / len2, 0, 1) else 0
	local closest = Vector3.new(a.X, 0, a.Z) + ab * t
	return (Vector3.new(p.X, 0, p.Z) - closest).Magnitude
end

-- Closest approach of two ground segments (sampled).
function Geo.segmentsDistance(a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3): (number, Vector3)
	local best, at = math.huge, a0
	for k = 0, 40 do
		local p = a0:Lerp(a1, k / 40)
		local d = Geo.segmentDistance(p, b0, b1)
		if d < best then
			best, at = d, p
		end
	end
	return best, at
end

function Geo.allSlots(ctx: Context): { ZoneContext }
	local all = table.clone(ctx.zones)
	table.insert(all, ctx.teaser)
	return all
end

-- Fails the build early, before anything is placed, if a connector would
-- cross another slot's footprint (the spiral wrapping past 8 slots).
function Geo.validate(ctx: Context)
	if #ctx.zones > Geo.MAX_ZONES then
		error(
			`[StormPunk] {#ctx.zones} zones: StormPunk supports {Geo.MAX_ZONES} zones + the teaser (slot {Geo.MAX_ZONES + 2} would reuse slot 1's bearing)`,
			0
		)
	end
	for _, zone in Geo.allSlots(ctx) do
		local a, b = zone.slot.hubExit.Position, zone.slot.gate.Position
		for _, other in Geo.allSlots(ctx) do
			if other ~= zone then
				for k = 0, 40 do
					if Kit.inFootprint(other, a:Lerp(b, k / 40), Geo.CORRIDOR - 4) then
						error(
							`[StormPunk] slot {zone.slot.index}'s connector crosses slot {other.slot.index}; StormPunk supports {Geo.MAX_ZONES} zones + the teaser`,
							0
						)
					end
				end
			end
		end
	end
end

-- Is a spot (with a radius) clear of every zone footprint, every connector
-- corridor and (optionally) the hub plaza? Decoration stays outside fields.
function Geo.isClear(
	ctx: Context,
	position: Vector3,
	radius: number,
	options: { hub: boolean?, ignoreCorridors: boolean? }?
): boolean
	local opts: { hub: boolean?, ignoreCorridors: boolean? } = options or {}
	for _, other in Geo.allSlots(ctx) do
		if Kit.inFootprint(other, position, radius + 3) then
			return false
		end
		if not opts.ignoreCorridors then
			local slot = other.slot
			if
				Geo.segmentDistance(position, slot.hubExit.Position, slot.gate.Position)
				< Geo.CORRIDOR + radius
			then
				return false
			end
		end
	end
	if opts.hub ~= false then
		local flat = Vector3.new(position.X, 0, position.Z)
		if flat.Magnitude < ctx.layout.hubRadius + 8 + radius then
			return false
		end
	end
	return true
end

-- Lowest deck height of any connector passing within `reach` studs of
-- (x, z), looking `span` studs either way along the deck (a circle's
-- radius), or nil when no connector passes there.
function Geo.deckHeightAt(ctx: Context, position: Vector3, reach: number, span: number?): number?
	local best: number? = nil
	for _, zone in Geo.allSlots(ctx) do
		local a = zone.slot.hubExit.Position
		local b = zone.slot.gate.Position
		if Geo.segmentDistance(position, a, b) < reach then
			local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
			local length = math.max(ab.Magnitude, 0.001)
			local ap = Vector3.new(position.X - a.X, 0, position.Z - a.Z)
			local t = ap:Dot(ab) / (length * length)
			local dt = (span or 0) / length
			local t0, t1 = math.clamp(t - dt, 0, 1), math.clamp(t + dt, 0, 1)
			local y = math.min(a.Y + (b.Y - a.Y) * t0, a.Y + (b.Y - a.Y) * t1)
			if best == nil or y < (best :: number) then
				best = y
			end
		end
	end
	return best
end

-- The guard every ground block uses (see Land.Guard): a circle (x, z, r)
-- may rise to `top` unless that puts ground above a connector deck,
-- anywhere into another slot's footprint (+4: even below its floor, so a
-- later zone never covers an earlier field), into `own`'s footprint above
-- its floor (unless `allowOwn`: the teaser's island is not a field), or
-- onto the hub plaza above the hub floor.
function Geo.guard(
	ctx: Context,
	own: ZoneContext?,
	allowOwn: boolean?
): (number, number, number, number) -> boolean
	local hubR = ctx.layout.hubRadius + 6
	local hubFloor = ctx.layout.hubFloor
	return function(x: number, z: number, r: number, top: number): boolean
		local p = Vector3.new(x, 0, z)
		local deck = Geo.deckHeightAt(ctx, p, r + 7, r)
		if deck and top > (deck :: number) - 1 then
			return false
		end
		for _, other in Geo.allSlots(ctx) do
			if other == own then
				if
					not allowOwn
					and top > other.slot.floor + 0.3
					and Kit.inFootprint(other, p, r)
				then
					return false
				end
			elseif Kit.inFootprint(other, p, r + 4) then
				return false
			end
		end
		if top > hubFloor - 0.5 and p.Magnitude < hubR + r then
			return false
		end
		return true
	end
end

-- Zone frames ---------------------------------------------------------------------

-- A point outside the footprint: u across (-0.5..0.5 = edge to edge), v from
-- the gate (-0.5) to the back (0.5); `out` pushes it further outward from
-- the nearest edge. y is relative to the zone floor.
function Geo.edgePoint(zone: ZoneContext, u: number, v: number, out: number, y: number?): Vector3
	local slot = zone.slot
	local x = u * slot.width
	local z = v * slot.depth
	local hw, hd = slot.width / 2, slot.depth / 2
	-- push along the dominant axis
	if math.abs(x) / hw >= math.abs(z) / hd then
		x += math.sign(x) * out
	else
		z += math.sign(z) * out
	end
	return slot.frame:PointToWorldSpace(Vector3.new(x, y or 0, z))
end

-- A point in the slot frame (x across, z outward from the hub, y above floor).
function Geo.slotPoint(zone: ZoneContext, x: number, z: number, y: number?): Vector3
	return zone.slot.frame:PointToWorldSpace(Vector3.new(x, y or 0, z))
end

-- Yaw-only CFrame at a world point facing a target (ignores height).
function Geo.facing(position: Vector3, target: Vector3): CFrame
	local flatTarget = Vector3.new(target.X, position.Y, target.Z)
	if (flatTarget - position).Magnitude < 0.01 then
		return CFrame.new(position)
	end
	return CFrame.lookAt(position, flatTarget)
end

function Geo.yawed(position: Vector3, yawDeg: number): CFrame
	return CFrame.new(position) * CFrame.Angles(0, math.rad(yawDeg), 0)
end

return Geo
