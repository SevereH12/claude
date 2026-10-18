--!strict
-- What every SkyIsles zone shares, whatever its theme: the floating island
-- around the footprint, the patterned catch floor, the rune-post border,
-- the gate and the rune bridge to the hub. Everything is placed from the
-- zone's slot, so a new Config.ZONES entry gets all of it automatically.

local ServerScriptService = game:GetService("ServerScriptService")

local World = ServerScriptService.Server.World
local Kit = require(World.Kit)
local Layout = require(World.Layout)
local WorldTypes = require(World.Types)
local Ground = require(script.Parent.Ground)
local Palette = require(script.Parent.Palette)
local Pieces = require(script.Parent.Pieces)
local SkyTypes = require(script.Parent.SkyTypes)

type Context = WorldTypes.Context
type ZoneContext = WorldTypes.ZoneContext
type ThemeSpec = SkyTypes.ThemeSpec
type Land = SkyTypes.Land

local C = Palette.C
local UP = Vector3.yAxis

local RIM = 10 -- guaranteed flat land around the footprint
local CHAMFER = 6 -- the plateau's corners are cut this far in
local SOIL = 6 -- soil band under the plateau cap
local GATE_HALF = 7 -- gate pillars sit this far either side of the bridge
local BRIDGE_WIDTH = 10
local BRIDGE_LIFT = 0.2 -- bridge decks sit this far above the ground they land on

local Zone = {}

-- How far the land reaches past the gate edge: less when the zone sits
-- close to the hub so the rim never pushes into the plaza.
local function frontRim(ctx: Context, zone: ZoneContext): number
	local gap = Layout.distanceFromHub(zone.slot) - ctx.layout.hubRadius - 6
	return math.clamp(gap, 2, RIM)
end

-- The guaranteed flat land around a zone's footprint (before lobes and
-- ridge are added): a chamfered rectangle, wider by spec.shore on the
-- sides and back. Zone.ground builds it and returns it; themes get it
-- passed in. (Kept out of module state on purpose: the land travels with
-- the build, not with the module.)
function Zone.newLand(ctx: Context, zone: ZoneContext, spec: ThemeSpec?): Land
	local slot = zone.slot
	local shore = if spec then spec.shore or 0 else 0
	return {
		halfW = slot.width / 2 + RIM + shore,
		front = -slot.depth / 2 - frontRim(ctx, zone),
		back = slot.depth / 2 + RIM + shore,
		terraces = {},
		blocked = {},
	}
end

-- The colours of a zone's island, from its theme.
function Zone.tones(spec: ThemeSpec): Ground.Tones
	local cliffs = spec.cliffs
	return {
		cap = spec.rim,
		soil = spec.soil,
		rocks = { cliffs[1], cliffs[math.min(2, #cliffs)] },
		tip = cliffs[#cliffs],
	}
end

-- How far bridge decks sit above the ground they land on.
Zone.BRIDGE_LIFT = BRIDGE_LIFT

-- Bridge landing length (covers the land in front of the gate).
function Zone.landing(ctx: Context, zone: ZoneContext): number
	return frontRim(ctx, zone) + 2
end

-- Accept function for terrain belonging to `zone`: clear of other zones,
-- connector corridors and the hub.
function Zone.accept(ctx: Context, zone: ZoneContext): Pieces.Accept
	return function(p: Vector3, r: number): boolean
		return Pieces.clearOf(ctx, p, r, zone, 4)
	end
end

-- Is a point on this zone's guaranteed rim (the chamfered ring of flat
-- land around the footprint), at least `gap` outside the footprint and at
-- least `inset` inside the land edge?
function Zone.onRim(zone: ZoneContext, land: Land, p: Vector3, gap: number, inset: number?): boolean
	local slot = zone.slot
	local l = slot.frame:PointToObjectSpace(p)
	local margin = inset or 1
	local hw, hd = slot.width / 2, slot.depth / 2
	local ax = math.abs(l.X)
	local dx = math.max(ax - hw, 0)
	local dz = math.max(math.abs(l.Z) - hd, 0)
	if math.sqrt(dx * dx + dz * dz) < gap then
		return false
	end
	if ax > land.halfW - margin or l.Z < land.front + margin or l.Z > land.back - margin then
		return false
	end
	-- the chamfered corners
	local inX = land.halfW - ax
	local inZ = if l.Z > 0 then land.back - l.Z else l.Z - land.front
	return inX + inZ >= CHAMFER + margin * 1.42
end

-- Horizontal unit vector from the zone's footprint out toward p.
function Zone.outward(zone: ZoneContext, p: Vector3): Vector3
	local slot = zone.slot
	local l = slot.frame:PointToObjectSpace(p)
	local nearest = Vector3.new(
		math.clamp(l.X, -slot.width / 2, slot.width / 2),
		0,
		math.clamp(l.Z, -slot.depth / 2, slot.depth / 2)
	)
	local out = Vector3.new(l.X, 0, l.Z) - nearest
	if out.Magnitude < 0.01 then
		out = Vector3.new(0, 0, 1)
	end
	return slot.frame:VectorToWorldSpace(out.Unit)
end

-- Random points on the rim ring (world, at floor height), at least `gap`
-- outside the footprint, clear of the ridge, the bridge and other zones.
-- Samples the ring directly so even a thin rim fills up.
function Zone.rimPoints(
	ctx: Context,
	zone: ZoneContext,
	land: Land,
	count: number,
	gap: number,
	clearance: number
): { Vector3 }
	local rng = ctx.rng
	local slot = zone.slot
	local hw, hd = slot.width / 2, slot.depth / 2
	local sides = {
		{ length = slot.width, out = -hd - land.front }, -- front (gate side)
		{ length = slot.depth, out = land.halfW - hw }, -- right
		{ length = slot.width, out = land.back - hd }, -- back
		{ length = slot.depth, out = land.halfW - hw }, -- left
	}
	local total = 2 * (slot.width + slot.depth)
	return Kit.scatter(count, function()
		local t = rng:NextNumber(0, total)
		local index = 1
		while index < 4 and t > sides[index].length do
			t -= sides[index].length
			index += 1
		end
		local side = sides[index]
		local d = rng:NextNumber(gap, math.max(gap, side.out - 1.5))
		local l: Vector3
		if index == 1 then
			l = Vector3.new(-hw + t, 0, -hd - d)
		elseif index == 2 then
			l = Vector3.new(hw + d, 0, -hd + t)
		elseif index == 3 then
			l = Vector3.new(hw - t, 0, hd + d)
		else
			l = Vector3.new(-hw - d, 0, hd - t)
		end
		return slot.frame:PointToWorldSpace(l)
	end, function(p: Vector3): boolean
		return Zone.onRim(zone, land, p, gap, 1.5)
			and Zone.unblocked(land, p, clearance)
			and Pieces.clearOf(ctx, p, clearance, zone)
	end)
end

-- Is p clear of the zone's ridge lumps?
function Zone.unblocked(land: Land, p: Vector3, clearance: number): boolean
	for _, lump in land.blocked do
		local d = Vector2.new(p.X - lump.center.X, p.Z - lump.center.Z).Magnitude
		if d < lump.radius + clearance then
			return false
		end
	end
	return true
end

-- A ragged backdrop ridge along the back edge and the back of both sides,
-- so the field sits in a cove: stepped mounds or tilted rock slabs by
-- theme, standing on the land edge. Every lump stays clear of the
-- footprint and of the coast lobes (which themes dress).
function Zone.ridge(ctx: Context, zone: ZoneContext, land: Land, spec: ThemeSpec)
	local height = spec.ridgeHeight
	local slot = zone.slot
	local frame = slot.frame
	local rng = ctx.rng
	local floor = slot.floor
	local hw, hd = slot.width / 2, slot.depth / 2
	local accept = Zone.accept(ctx, zone)
	local backOut = land.back - hd
	local sideOut = land.halfW - hw
	local spots: { Vector3 } = {}
	local x = -hw - 4 + rng:NextNumber(0, 6)
	while x <= hw + 4 do
		table.insert(spots, Vector3.new(x, 0, hd + backOut + rng:NextNumber(-3, 0)))
		x += rng:NextNumber(9, 14)
	end
	for _, side in { -1, 1 } do
		local z = hd * rng:NextNumber(0.05, 0.4)
		while z <= hd - 2 do
			table.insert(spots, Vector3.new(side * (hw + sideOut + rng:NextNumber(-3, 0)), 0, z))
			z += rng:NextNumber(9, 14)
		end
	end
	local shape = spec.ridgeShape or "slabs"
	local spires = 0
	for _, l in spots do
		if rng:NextNumber() < 0.85 then
			local footprintGap =
				math.sqrt(math.max(math.abs(l.X) - hw, 0) ^ 2 + math.max(math.abs(l.Z) - hd, 0) ^ 2)
			local radius = math.min(rng:NextNumber(5, 10), (footprintGap - 1.5) / 1.2)
			local p = frame:PointToWorldSpace(l)
			local clearOfLobes = true
			for _, lobe in land.terraces do
				local d = Vector2.new(p.X - lobe.center.X, p.Z - lobe.center.Z).Magnitude
				if d < lobe.radius * 0.6 + radius then
					clearOfLobes = false
				end
			end
			if radius >= 3 and clearOfLobes and accept(p, radius) then
				local outward = Zone.outward(zone, p)
				if shape == "dunes" then
					local top = floor
						+ 2 * math.max(1, math.round(height * rng:NextNumber(0.5, 1) / 2))
					Pieces.mound(ctx, p, radius, floor, top, spec.ridge, spec.ridgeCap)
				else
					-- jagged skyline: tilted slabs leaning away from the field
					local top = floor + height * rng:NextNumber(0.45, 1.1)
					Pieces.slabRock(
						ctx,
						p,
						outward,
						radius * rng:NextNumber(0.7, 0.85),
						radius * rng:NextNumber(0.4, 0.55),
						top,
						floor - 10,
						rng:NextNumber(10, 25),
						rng:NextNumber(-30, 30),
						spec.ridge
					)
				end
				table.insert(land.blocked, { center = p, radius = radius * 1.17 })
				-- the odd rock spire standing up out of the ridge
				if spec.spires and spires < 2 and rng:NextNumber() < 0.3 then
					spires += 1
					Pieces.spire(
						ctx,
						Vector3.new(p.X, floor, p.Z),
						height * rng:NextNumber(1.8, 2.4),
						math.min(radius * 0.6, 4),
						outward,
						{ spec.spires, spec.ridge }
					)
				end
			end
		end
	end
end

-- Ground ---------------------------------------------------------------------------

-- Coast lobes: polygons of land pushing the coastline out round the sides
-- and back, so the plateau never reads as a plain rectangle. Each one is
-- recorded in land.terraces (top at the floor) for the theme to dress.
local function lobes(ctx: Context, zone: ZoneContext, land: Land, tones: Ground.Tones)
	local slot = zone.slot
	local frame = slot.frame
	local rng = ctx.rng
	local floor = slot.floor
	local accept = Zone.accept(ctx, zone)
	local want = math.clamp(math.round((slot.width + slot.depth) / 45), 4, 6)
	local sideLength = land.back - land.front - 2 * CHAMFER
	local backLength = land.halfW * 2 - 2 * CHAMFER
	for _ = 1, want * 6 do
		if #land.terraces >= want then
			break
		end
		local radius = rng:NextNumber(8, 14)
		local t = rng:NextNumber(0, 2 * sideLength + backLength)
		local edge: Vector3
		local normal: Vector3
		if t < sideLength then
			edge, normal =
				Vector3.new(-land.halfW, 0, land.front + CHAMFER + t), Vector3.new(-1, 0, 0)
		elseif t < 2 * sideLength then
			edge, normal =
				Vector3.new(land.halfW, 0, land.front + CHAMFER + t - sideLength),
				Vector3.new(1, 0, 0)
		else
			edge, normal =
				Vector3.new(-land.halfW + CHAMFER + t - 2 * sideLength, 0, land.back),
				Vector3.new(0, 0, 1)
		end
		local l = edge + normal * radius * rng:NextNumber(-0.4, 0.15)
		local p = frame:PointToWorldSpace(l)
		local spaced = true
		for _, other in land.terraces do
			local d = Vector2.new(p.X - other.center.X, p.Z - other.center.Z).Magnitude
			if d < (radius + other.radius) * 1.1 then
				spaced = false
			end
		end
		if spaced and accept(p, radius * 1.1) then
			local top = CFrame.new(p)
				* frame.Rotation
				* CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
			Ground.poly(ctx, tones.cap, top, radius + Ground.OVERHANG, Ground.CAP, 10, "Cap")
			Ground.poly(
				ctx,
				tones.soil,
				top * CFrame.new(0, -Ground.CAP, 0),
				radius,
				SOIL + 2,
				10,
				"Soil"
			)
			table.insert(land.terraces, { center = p, radius = radius, top = floor })
		end
	end
end

function Zone.ground(ctx: Context, zone: ZoneContext, spec: ThemeSpec): Land
	local slot = zone.slot
	local frame = slot.frame
	local rng = ctx.rng
	local land = Zone.newLand(ctx, zone, spec)
	local tones = Zone.tones(spec)

	-- the plateau: a light cap over a soil band, its top exactly at the
	-- floor across the whole footprint (the catch floor) and the rim
	local sx, sz = land.halfW * 2, land.back - land.front
	local top = frame * CFrame.new(0, 0, (land.front + land.back) / 2)
	local over = Ground.OVERHANG
	Ground.rect(
		ctx,
		tones.cap,
		top,
		sx + 2 * over,
		sz + 2 * over,
		Ground.CAP,
		CHAMFER + 0.35,
		"Cap"
	)
	local soilTop = top * CFrame.new(0, -Ground.CAP, 0)
	Ground.rect(ctx, tones.soil, soilTop, sx, sz, SOIL, CHAMFER, "Soil")

	-- the coast, then the backdrop ridge behind the field
	lobes(ctx, zone, land, tones)
	Zone.ridge(ctx, zone, land, spec)

	-- tapering underside: stepped strata down to hanging rock points
	local hangs = Ground.taperRect(
		ctx,
		tones,
		soilTop * CFrame.new(0, -SOIL, 0),
		land.halfW,
		sz / 2,
		spec.depth - Ground.CAP - SOIL,
		2
	)

	-- the catch floor carpet, flush on the plateau cap
	Pieces.field(zone.folder, zone, spec.field)

	-- crystals hanging from the underside's ledges
	for i, spot in hangs do
		if i <= 3 then
			Pieces.cluster(zone.folder, rng, spot, rng:NextNumber(5, 8), spec.accent, 3, true)
		end
	end

	-- mooring bollards on the hub-side rim: the hub's iron tethers end here
	for _, point in Zone.tetherPoints(ctx, zone) do
		local foot = point - UP * 2.6
		Pieces.cylinder(
			zone.folder,
			foot,
			2.4,
			2.4,
			C.iron,
			Enum.Material.Metal,
			{ CanCollide = true, Name = "MooringBollard" }
		)
		Pieces.cylinder(zone.folder, foot + UP * 1.6, 0.35, 2.6, zone.color, Enum.Material.Neon, {
			CastShadow = false,
		})
		Pieces.cylinder(zone.folder, foot + UP * 2.4, 0.5, 3, C.iron, Enum.Material.Metal)
	end
	return land
end

-- Where the hub's tethers for this zone are moored (left and right): the
-- top of a bollard on the rim, 2.5 studs inside the hub-side land edge and
-- well clear of the bridge.
function Zone.tetherPoints(ctx: Context, zone: ZoneContext): { Vector3 }
	local slot = zone.slot
	local front = -slot.depth / 2 - frontRim(ctx, zone)
	local points = {}
	for _, u in { -0.3, 0.3 } do
		table.insert(
			points,
			slot.frame:PointToWorldSpace(Vector3.new(u * slot.width, 2.6, front + 3))
		)
	end
	return points
end

-- Connector --------------------------------------------------------------------------

function Zone.connector(ctx: Context, zone: ZoneContext)
	local slot = zone.slot
	-- the deck lies on the ground at both ends, a touch above it
	local lift = UP * BRIDGE_LIFT
	Pieces.bridge(
		ctx,
		ctx.folders.connectors,
		slot.hubExit.Position + lift,
		slot.gate.Position + lift,
		{
			glow = zone.color,
			width = BRIDGE_WIDTH,
			startFlat = 4,
			endFlat = Zone.landing(ctx, zone),
		}
	)
end

-- Border -----------------------------------------------------------------------------

-- Rune posts on the footprint edge linked by glowing cables, with a gap
-- at the gate and a taller lit pylon at each corner.
function Zone.border(ctx: Context, zone: ZoneContext)
	local slot = zone.slot
	local folder = zone.folder
	local posts = Kit.perimeter(zone, 24, 0)
	local tops: { Vector3? } = {}
	local corners: { [number]: boolean } = {}
	local hw, hd = slot.width / 2, slot.depth / 2
	for i, cframe in posts do
		local l = slot.frame:PointToObjectSpace(cframe.Position)
		local isCorner = math.abs(math.abs(l.X) - hw) < 0.5 and math.abs(math.abs(l.Z) - hd) < 0.5
		local inGate = l.Z < -hd + 0.5 and math.abs(l.X) < GATE_HALF + 2.5
		if inGate then
			tops[i] = nil
		elseif isCorner then
			local _, cap =
				Pieces.runePost(folder, cframe.Position, 7.5, zone.color, cframe.LookVector, true)
			Pieces.shard(folder, cframe.Position + UP * 7.1, 3.2, 1.1, zone.color, 45, 0)
			Pieces.light(cap, zone.color, 18, 1.2)
			tops[i] = cframe.Position + UP * 3.4
			corners[i] = true
		else
			local top = Pieces.runePost(folder, cframe.Position, 4.6, zone.color, cframe.LookVector)
			tops[i] = top
		end
	end
	-- one glowing cable per straight run (corner to corner, or corner to
	-- the gate gap), resting on the post tops: few beams, same look
	local count = #posts
	local runStart: Vector3? = nil
	for step = 0, count do
		local i = step % count + 1
		local top = tops[i]
		if top == nil then
			runStart = nil
		elseif corners[i] or tops[(i % count) + 1] == nil then
			if runStart and step > 0 then
				Pieces.runeCable(ctx, runStart, top, zone.color, 0.3, 0.32)
			end
			runStart = top
		elseif runStart == nil then
			runStart = top
		end
	end
end

-- Gate ----------------------------------------------------------------------------------

function Zone.gate(_ctx: Context, zone: ZoneContext)
	local def = zone.def :: any
	local slot = zone.slot
	-- 2 studs toward the hub so the pillars stand on the rim, outside the floor
	local base = slot.gate * CFrame.new(0, 0, -2.5)
	Pieces.gateway(
		zone.folder,
		base,
		GATE_HALF,
		16,
		zone.color,
		string.upper(def.displayName),
		def.tagline,
		"STORMSPIRE",
		"Sell your charge at the altar",
		true
	)
end

return Zone
