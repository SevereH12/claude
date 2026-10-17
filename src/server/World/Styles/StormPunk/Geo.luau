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

-- Bearings (degrees clockwise from north) -----------------------------------

function Geo.dir(angleDeg: number): Vector3
	local a = math.rad(angleDeg)
	return Vector3.new(math.sin(a), 0, -math.cos(a))
end

function Geo.polar(angleDeg: number, radius: number, y: number): Vector3
	return Geo.dir(angleDeg) * radius + Vector3.new(0, y, 0)
end

function Geo.bearingOf(position: Vector3): number
	return math.deg(math.atan2(position.X, -position.Z)) % 360
end

-- Bearings exactly between the spiral's exit bearings: hub props live on
-- these so a future zone's exit (always on a spiral bearing) is never blocked.
function Geo.quietBearings(ctx: Context): { number }
	local layout = ctx.layout
	local step = math.abs(layout.angleStep) % 360
	local out = {}
	local exits = {}
	-- the spiral visits a fixed set of bearings; collect the first 16 of them
	for i = 0, 15 do
		table.insert(exits, (layout.firstAngle + i * step) % 360)
	end
	table.sort(exits)
	local unique: { number } = {}
	for _, a in exits do
		if #unique == 0 or math.abs(a - unique[#unique]) > 1 then
			table.insert(unique, a)
		end
	end
	for i, a in unique do
		local nextA = unique[i % #unique + 1]
		local gap = (nextA - a) % 360
		if gap == 0 then
			gap = 360
		end
		table.insert(out, (a + gap / 2) % 360)
	end
	return out
end

-- Seeded randomness ------------------------------------------------------------

local baseSeeds: { [Context]: number } = {}

local function hash(text: string): number
	local h = 5381
	for i = 1, #text do
		h = (h * 33 + string.byte(text, i)) % 2147483647
	end
	return h
end

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

-- Dressing density for a zone, from its own spiral index only (so adding a
-- zone never changes the ones before it): the first two zones get full
-- detail, later and further zones get progressively leaner dressing, like
-- a distance LOD. Scales scatter counts, lamp/pile spacing and fence posts.
function Geo.detail(zone: ZoneContext): number
	if zone.isTeaser then
		return 0.6
	end
	return math.clamp(1 - (zone.slot.index - 2) * 0.15, 0.45, 1)
end

-- Scaled whole count, at least `minimum`.
function Geo.count(zone: ZoneContext, full: number, minimum: number?): number
	return math.max(minimum or 0, math.floor(full * Geo.detail(zone) + 0.5))
end

function Geo.zoneKey(zone: ZoneContext): string
	local def = zone.def
	return if def then def.id else `slot{zone.slot.index}`
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

function Geo.allSlots(ctx: Context): { ZoneContext }
	local all = table.clone(ctx.zones)
	table.insert(all, ctx.teaser)
	return all
end

-- Is a spot (with a radius) clear of every zone footprint, every connector
-- corridor and (optionally) the hub plaza? `own` is the zone being
-- decorated: its footprint is also off limits (decoration stays outside).
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

-- Predicate for Land.clip: keeps a terrain circle unless its top (`top`)
-- would rise above a connector deck that runs over it, so every catwalk
-- meets flush ground at both ends instead of a step it can't climb.
function Geo.belowDecks(ctx: Context, top: number): ({ x: number, z: number, r: number }) -> boolean
	return function(c)
		local deck = Geo.deckHeightAt(ctx, Vector3.new(c.x, 0, c.z), c.r + 7, c.r)
		return deck == nil or top <= deck - 1
	end
end

-- Predicate for Land.clip on any raised landmass with its top at `top`:
-- drops circles that would rise above a connector deck or into another
-- zone's footprint above that zone's floor (`own` is the zone being built).
function Geo.landSafe(
	ctx: Context,
	top: number,
	own: ZoneContext?
): ({ x: number, z: number, r: number }) -> boolean
	local below = Geo.belowDecks(ctx, top)
	return function(c)
		if not below(c) then
			return false
		end
		for _, other in Geo.allSlots(ctx) do
			if
				other ~= own
				and top > other.slot.floor - 0.5
				and Kit.inFootprint(other, Vector3.new(c.x, 0, c.z), c.r + 4)
			then
				return false
			end
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
