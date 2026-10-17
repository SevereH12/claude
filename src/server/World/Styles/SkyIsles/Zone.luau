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
local GATE_HALF = 7 -- gate pillars sit this far either side of the bridge
local BRIDGE_WIDTH = 10

local Zone = {}

-- How far the land reaches past the gate edge: less when the zone sits
-- close to the hub so the rim never pushes into the plaza.
local function frontRim(ctx: Context, zone: ZoneContext): number
	local gap = Layout.distanceFromHub(zone.slot) - ctx.layout.hubRadius - 6
	return math.clamp(gap, 2, RIM)
end

-- The guaranteed flat land around a zone's footprint (before terraces
-- and ridge are added). Zone.ground fills it in and returns it; themes get
-- it passed in. (Kept out of module state on purpose: the land travels
-- with the build, not with the module.)
function Zone.newLand(ctx: Context, zone: ZoneContext): Land
	local slot = zone.slot
	return {
		halfW = slot.width / 2 + RIM,
		front = -slot.depth / 2 - frontRim(ctx, zone),
		back = slot.depth / 2 + RIM,
		terraces = {},
		blocked = {},
	}
end

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

-- Is a point on this zone's guaranteed rim (the rounded ring of flat land
-- around the footprint), at least `gap` outside the footprint and at least
-- `inset` inside the land edge?
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
	if ax > hw and (l.Z > hd or l.Z < -hd) then
		local radius = if l.Z > hd then land.back - hd else -hd - land.front
		local cz = if l.Z > hd then hd else -hd
		if Vector2.new(ax - hw, l.Z - cz).Magnitude > radius - margin then
			return false
		end
	end
	return true
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
-- so the field sits in a cove: rocks, canyon walls or hills by theme.
-- Every lump stays clear of the footprint.
function Zone.ridge(
	ctx: Context,
	zone: ZoneContext,
	land: Land,
	spec: ThemeSpec
)
	local height = spec.ridgeHeight
	local slot = zone.slot
	local frame = slot.frame
	local rng = ctx.rng
	local floor = slot.floor
	local hw, hd = slot.width / 2, slot.depth / 2
	local accept = Zone.accept(ctx, zone)
	local spots: { Vector3 } = {}
	-- main row just past the rim, and a second, broken row behind it
	for row = 1, 2 do
		local out = if row == 1 then 13 else 21
		local x = -hw - 6 + rng:NextNumber(0, 6)
		while x <= hw + 6 do
			if row == 1 or rng:NextNumber() < 0.5 then
				table.insert(spots, Vector3.new(x, 0, hd + out + rng:NextNumber(-2, 3)))
			end
			x += rng:NextNumber(8, 15)
		end
		for _, side in { -1, 1 } do
			local z = hd * rng:NextNumber(0.05, 0.4)
			while z <= hd + 4 do
				if row == 1 or rng:NextNumber() < 0.5 then
					table.insert(
						spots,
						Vector3.new(side * (hw + out + rng:NextNumber(-2, 3)), 0, z)
					)
				end
				z += rng:NextNumber(8, 15)
			end
		end
	end
	local shape = spec.ridgeShape or "slabs"
	local spires = 0
	for _, l in spots do
		if rng:NextNumber() < 0.85 then
			local footprintGap =
				math.sqrt(math.max(math.abs(l.X) - hw, 0) ^ 2 + math.max(math.abs(l.Z) - hd, 0) ^ 2)
			local radius = math.min(rng:NextNumber(5, 11), (footprintGap - 1.5) / 1.2)
			local p = frame:PointToWorldSpace(l)
			if radius >= 3 and accept(p, radius) then
				local ground = Vector3.new(p.X, 0, p.Z)
				local outward = Zone.outward(zone, p)
				if shape == "dunes" then
					-- low rounded dunes with a grassy crown
					local top = floor + 4 * math.max(1, math.round(height * rng:NextNumber(0.5, 1) / 4))
					Kit.blob(ctx, ground, radius, top, top - floor + 8, spec.ridge, 5)
					if spec.ridgeCap then
						Kit.blob(ctx, ground, radius * 0.6, top + 1, 3, spec.ridgeCap, 4)
					end
				else
					-- jagged skyline: tilted slabs leaning away from the field
					local top = floor + height * rng:NextNumber(0.45, 1.1)
					Pieces.slabRock(
						ctx,
						ground,
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
				-- the odd sea-stack spire on the second row
				if spec.spires and spires < 3 and footprintGap > 17 and rng:NextNumber() < 0.35 then
					spires += 1
					Pieces.spire(
						ctx,
						Vector3.new(p.X, floor, p.Z),
						height * rng:NextNumber(1.8, 2.4),
						math.min(radius, 6),
						outward,
						spec.spires
					)
				end
			end
		end
	end
end

-- Ground ---------------------------------------------------------------------------

function Zone.ground(ctx: Context, zone: ZoneContext, spec: ThemeSpec): Land
	local slot = zone.slot
	local frame = slot.frame
	local floor = slot.floor
	local rng = ctx.rng
	local hw, hd = slot.width / 2, slot.depth / 2
	local front = -hd - frontRim(ctx, zone)
	local accept = Zone.accept(ctx, zone)
	local land = Zone.newLand(ctx, zone)

	-- tapering underside with hanging spikes
	Pieces.underside(
		ctx,
		frame,
		hw + RIM * 0.5,
		hd + RIM * 0.5,
		floor - 8,
		spec.depth,
		spec.cliffs,
		accept
	)

	-- a rocky shelf just under the rim: the first step of the cliff
	Pieces.landmass(
		ctx,
		frame,
		land.halfW + 3,
		front - 2,
		land.back + 3,
		floor - 4,
		8,
		spec.cliffs[1],
		{
			corner = RIM + 3,
			lobe = 12,
			reach = 0.8,
			accept = accept,
		}
	)

	-- lower terraces hanging off the sides and back: layered cliffs
	local terraceCount = math.max(3, math.floor((slot.width + slot.depth) / 50))
	for i = 1, terraceCount * 4 do
		if #land.terraces >= terraceCount then
			break
		end
		local side = rng:NextInteger(1, 3) -- 1 left, 2 right, 3 back
		local radius = rng:NextNumber(10, 16)
		local out = land.halfW + 3 + radius * 0.3
		local l: Vector3
		if side == 3 then
			l = Vector3.new(rng:NextNumber(-hw, hw), 0, land.back + 3 + radius * 0.3)
		else
			l = Vector3.new(if side == 1 then -out else out, 0, rng:NextNumber(-hd * 0.6, hd))
		end
		local p = frame:PointToWorldSpace(l)
		local top = floor - (if i % 2 == 0 then 12 else 8)
		if accept(p, radius) then
			Kit.blob(ctx, Vector3.new(p.X, 0, p.Z), radius, top, 10, spec.terrace, 5)
			table.insert(
				land.terraces,
				{ center = Vector3.new(p.X, top, p.Z), radius = radius, top = top }
			)
		end
	end

	-- two peninsulas of rim pushing out from the sides or back
	local made = 0
	for _ = 1, 8 do
		if made >= 2 then
			break
		end
		local radius = rng:NextNumber(12, 17)
		local side = rng:NextInteger(1, 3)
		local l: Vector3
		if side == 3 then
			l = Vector3.new(rng:NextNumber(-hw * 0.7, hw * 0.7), 0, land.back + radius * 0.25)
		else
			local out = land.halfW + radius * 0.25
			l = Vector3.new(if side == 1 then -out else out, 0, rng:NextNumber(-hd * 0.4, hd * 0.8))
		end
		local p = frame:PointToWorldSpace(l)
		if accept(p, radius * 1.2) then
			made += 1
			Kit.blob(ctx, Vector3.new(p.X, 0, p.Z), radius * 1.08, floor - 4, 8, spec.cliffs[1], 6)
			Kit.blob(ctx, Vector3.new(p.X, 0, p.Z), radius, floor, 10, spec.rim, 6)
			table.insert(
				land.terraces,
				{ center = Vector3.new(p.X, floor, p.Z), radius = radius, top = floor }
			)
		end
	end

	-- the plateau: guaranteed rounded rim plus a lumpy coastline
	Pieces.landmass(ctx, frame, land.halfW, front, land.back, floor, 10, spec.rim, {
		corner = RIM,
		lobe = 10,
		reach = 0.55,
		accept = accept,
	})

	-- the backdrop ridge behind the field
	Zone.ridge(ctx, zone, land, spec)

	-- the catch floor: terrain exactly at the floor, then the carpet on top
	ctx.terrain:FillBlock(
		CFrame.new(frame.Position.X, floor - 4, frame.Position.Z) * frame.Rotation,
		Vector3.new(slot.width, 8, slot.depth),
		spec.fieldTerrain
	)
	Pieces.field(zone.folder, zone, spec.field)

	-- crystals hanging under the island
	for _ = 1, 3 do
		local l = Vector3.new(rng:NextNumber(-0.4, 0.4) * hw, 0, rng:NextNumber(-0.4, 0.4) * hd)
		local p = frame:PointToWorldSpace(l)
		Pieces.cluster(
			zone.folder,
			rng,
			Vector3.new(p.X, floor - spec.depth * rng:NextNumber(0.45, 0.6), p.Z),
			rng:NextNumber(5, 8),
			spec.accent,
			3,
			true
		)
	end

	-- mooring bollards on the hub-side rim: the hub's iron tethers end here
	for _, point in Zone.tetherPoints(ctx, zone) do
		local foot = point - UP * 2.2
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
	Pieces.bridge(ctx, ctx.folders.connectors, slot.hubExit.Position, slot.gate.Position, {
		glow = zone.color,
		width = BRIDGE_WIDTH,
		startFlat = 4,
		endFlat = Zone.landing(ctx, zone),
	})
end

-- Border -----------------------------------------------------------------------------

-- Rune posts on the footprint edge linked by glowing cables, with a gap
-- at the gate and a taller lit pylon at each corner.
function Zone.border(ctx: Context, zone: ZoneContext)
	local slot = zone.slot
	local folder = zone.folder
	local posts = Kit.perimeter(zone, 14, 0)
	local tops: { Vector3? } = {}
	local hw, hd = slot.width / 2, slot.depth / 2
	for i, cframe in posts do
		local l = slot.frame:PointToObjectSpace(cframe.Position)
		local isCorner = math.abs(math.abs(l.X) - hw) < 0.5 and math.abs(math.abs(l.Z) - hd) < 0.5
		local inGate = l.Z < -hd + 0.5 and math.abs(l.X) < GATE_HALF + 2.5
		if inGate then
			tops[i] = nil
		elseif isCorner then
			local top, cap =
				Pieces.runePost(folder, cframe.Position, 7.5, zone.color, cframe.LookVector, true)
			Pieces.shard(folder, cframe.Position + UP * 7.1, 3.2, 1.1, zone.color, 45, 0)
			Pieces.light(cap, zone.color, 18, 1.2)
			tops[i] = top
		else
			local top = Pieces.runePost(folder, cframe.Position, 4.6, zone.color, cframe.LookVector)
			tops[i] = top
		end
	end
	local count = #posts
	for i = 1, count do
		local a, b = tops[i], tops[i % count + 1]
		if a and b then
			Pieces.runeCable(ctx, a - UP * 0.4, b - UP * 0.4, zone.color, 0.8, 0.32)
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
