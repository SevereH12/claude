--!strict
-- Shared zone kit for every StormPunk zone, whatever its theme or slot:
-- the block-built island (field slab, strata, sand apron, beach lobes and
-- shore slopes), the riveted catwalk connector, the insulator-fence border,
-- the insulator arch gate, saddle ridges and the flush two-tone floor
-- patterns. Everything is placed in the slot's own frame, so any position,
-- rotation, size or height works. Props get full detail in every zone; the
-- ground's optional pieces follow Geo.zoneDetail (full for every zone).

local ServerScriptService = game:GetService("ServerScriptService")

local World = ServerScriptService.Server.World
local Kit = require(World.Kit)
local WorldTypes = require(World.Types)
local Geo = require(script.Parent.Geo)
local Land = require(script.Parent.Land)
local Palette = require(script.Parent.Palette)
local Pieces = require(script.Parent.Pieces)

type Context = WorldTypes.Context
type ZoneContext = WorldTypes.ZoneContext

local C = Palette.colors
local T = Palette.tints
local M = Palette.materials

local G = Palette.ground
local UP = Vector3.new(0, 1, 0)
local SEA_FLOOR = Geo.SEA_FLOOR
local BEACH = Geo.BEACH
local BOTTOM = SEA_FLOOR - 0.5

local Zone = {}

-- Gate geometry shared by the gate and the border (posts end at the pillars).
Zone.GATE_HALF = 8.5 -- pillar distance from the gate centre line
Zone.GATE_OUT = 2.2 -- pillars stand this far outside the footprint edge
Zone.GATE_ATTACH_Y = 4.2 -- border cables meet the pillars here
Zone.POST_HEIGHT = 5.5
Zone.POST_SPACING = 22
Zone.DECK_WIDTH = 12
-- The field slab reaches this far past the footprint (the gate pillars and
-- the last studs of the catwalk stand on it).
Zone.MARGIN = 4.5

export type BridgeStyle = {
	deck: Color3,
	deckMaterial: Enum.Material,
	rail: Color3,
	pile: Color3,
	stack: Color3, -- rock columns the long spans hop across
}

Zone.defaultBridge = {
	deck = C.iron,
	deckMaterial = M.plate,
	rail = C.brass,
	pile = C.copper,
	stack = G.basalt,
} :: BridgeStyle

local function name(zone: ZoneContext): string
	local def = zone.def
	return if def then def.displayName else "Coming Soon"
end

-- Connector ------------------------------------------------------------------------

export type CatwalkOptions = {
	stopAt: number?, -- build only this fraction of the deck (the teaser)
	trail: Color3?, -- the light trail colour (default: the zone colour)
}

-- Riveted catwalk from `from` to `to` (points on the walking surface).
-- Piles carry on past an unfinished deck. Long spans over water hop across
-- capped rock columns (block ground). Returns the end of the deck.
function Zone.catwalk(
	ctx: Context,
	parent: Instance,
	from: Vector3,
	to: Vector3,
	color: Color3,
	style: BridgeStyle,
	options: CatwalkOptions?
): Vector3
	local opts: CatwalkOptions = options or {}
	local finish = opts.stopAt or 1
	local deckEnd = from:Lerp(to, finish)
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local run = flat.Magnitude
	local dir = flat.Unit
	local side = dir:Cross(UP)
	local half = Zone.DECK_WIDTH / 2

	Kit.walkway(parent, from, deckEnd, Zone.DECK_WIDTH, 1, {
		Name = "Catwalk",
		Color = style.deck,
		Material = style.deckMaterial,
	})
	-- side girders, railings and the light trail down the middle
	for _, s in { -1, 1 } do
		local off = side * s * (half - 0.3) - UP * 1.3
		Pieces.strut(parent, from + off, deckEnd + off, 1.6, T.copperDark, M.metal)
		Pieces.railing(
			parent,
			from + side * s * (half - 0.4),
			deckEnd + side * s * (half - 0.4),
			3.4,
			18,
			style.rail
		)
	end
	Pieces.trail(parent, from, deckEnd, 1.4, opts.trail or color, M.neon, 0.14)

	-- pile bents all the way (unfinished bridges keep theirs), standing on
	-- rock stacks where the span is long and over open sea
	local rng = Random.new(math.floor(math.abs(from.X * 7 + to.Z * 13)) % 100000 + 1)
	local guard = Geo.guard(ctx, nil)
	local bents = math.max(1, math.floor(run / 34))
	for i = 1, bents do
		local t = i / (bents + 1)
		local p = from:Lerp(to, t)
		local top = p - UP * 2
		Pieces.column(
			parent,
			Vector3.new(top.X, SEA_FLOOR - 2, top.Z),
			top.Y - SEA_FLOOR + 2,
			2.2,
			style.pile,
			M.metal,
			true
		)
		Pieces.strut(
			parent,
			top + side * (half + 0.6),
			top - side * (half + 0.6),
			1.1,
			if t > finish then C.hazard else C.iron
		)
		if run > 70 and i % 2 == 1 and top.Y > 8 then
			Land.column(
				ctx.folders.ground,
				top,
				BOTTOM,
				math.min(top.Y - 4, 14 + rng:NextNumber(0, 8)),
				rng:NextNumber(3.6, 4.8),
				{ style.stack },
				G.grass,
				rng:NextNumber(0, math.pi),
				guard
			)
		end
	end

	-- lantern posts down the right side, strung with a glowing cable
	local stations = math.max(1, math.floor(run * finish / 40 + 0.5))
	local prev: Vector3? = nil
	for i = 1, stations do
		local t = finish * (i - 0.5) / stations
		local p = from:Lerp(to, t) + side * (half - 0.4)
		local lantern = Pieces.lamp(parent, p, 6.5, C.volt, if i == 1 then 18 else nil)
		local top = lantern.CFrame.Position
		if prev then
			Pieces.liveCable(ctx, prev, top, C.volt, 0.25, 1.6)
		end
		prev = top
	end
	return deckEnd
end

function Zone.buildConnector(ctx: Context, zone: ZoneContext, style: BridgeStyle?)
	local slot = zone.slot
	Zone.catwalk(
		ctx,
		ctx.folders.connectors,
		slot.hubExit.Position,
		slot.gate.Position,
		zone.color,
		style or Zone.defaultBridge
	)
end

-- Gate ----------------------------------------------------------------------------------

-- Insulator arch: banded copper pillars, brass arch beam, the zone sign and a
-- Jacob's ladder on top. Returns the two pillar cable points (left, right).
function Zone.buildGate(ctx: Context, zone: ZoneContext): (Vector3, Vector3)
	local parent = zone.folder
	local g = zone.slot.gate * CFrame.new(0, 0, -Zone.GATE_OUT)
	local color = zone.color
	local height = 15
	local attach: { Vector3 } = {}
	for _, s in { -1, 1 } do
		local foot = (g * CFrame.new(s * Zone.GATE_HALF, 0, 0)).Position
		Pieces.column(parent, foot - UP, height + 1, 2.8, C.copper, M.metal, true)
		Pieces.column(parent, foot - UP * 0.2, 2, 4, C.iron, M.metal)
		Pieces.column(
			parent,
			foot + UP * (Zone.GATE_ATTACH_Y - 0.6),
			1.4,
			3.6,
			C.ceramic,
			M.ceramic
		)
		Pieces.ball(parent, foot + UP * (height + 1), 2.6, color, M.neon)
		table.insert(attach, foot + UP * Zone.GATE_ATTACH_Y)
	end
	local arch = Pieces.block(
		parent,
		g * CFrame.new(0, height - 1.4, 0),
		Vector3.new(2 * Zone.GATE_HALF + 2.4, 1.6, 1.6),
		C.brass,
		M.metal
	)
	Pieces.sparks(arch, C.volt, 5)
	Pieces.glow(arch, color, 22, 1.8)
	local def = zone.def
	Pieces.framedSign(
		parent,
		g * CFrame.new(0, height - 5.4, 0),
		15,
		5,
		string.upper(name(zone)),
		if def then def.tagline else nil,
		Palette.sign(color, true)
	)
	Pieces.jacobsLadder(
		ctx,
		parent,
		(g * CFrame.new(0, height - 0.6, 0)).Position,
		g.RightVector,
		5
	)
	-- threshold strip across the entrance
	local a = (zone.slot.gate * CFrame.new(-Zone.GATE_HALF + 1.5, 0, -0.6)).Position
	local b = (zone.slot.gate * CFrame.new(Zone.GATE_HALF - 1.5, 0, -0.6)).Position
	Pieces.trail(parent, a, b, 1.2, color, M.neon, 0.12)
	return attach[1], attach[2]
end

-- Border ---------------------------------------------------------------------------------

-- Chunky insulator posts on the footprint edge joined by glowing cables in
-- the zone colour; every second post carries a lamp cap. Gap at the gate.
function Zone.buildBorder(ctx: Context, zone: ZoneContext)
	local slot = zone.slot
	local parent = zone.folder
	local hd = slot.depth / 2
	local frames = Kit.perimeter(zone, Zone.POST_SPACING)
	local points: { Vector3? } = {}
	for i, cf in frames do
		local localPos = slot.frame:PointToObjectSpace(cf.Position)
		local inGap = math.abs(localPos.Z + hd) < 0.5 and math.abs(localPos.X) < Zone.GATE_HALF + 2
		if inGap then
			points[i] = nil
		else
			points[i] =
				Pieces.insulatorPost(parent, cf.Position, Zone.POST_HEIGHT, zone.color, i % 2 == 1)
		end
	end
	-- pillar attach points so the fence runs into the gate
	local g = slot.gate * CFrame.new(0, 0, -Zone.GATE_OUT)
	local pillarL = (g * CFrame.new(-Zone.GATE_HALF, Zone.GATE_ATTACH_Y, 0)).Position
	local pillarR = (g * CFrame.new(Zone.GATE_HALF, Zone.GATE_ATTACH_Y, 0)).Position
	local count = #frames
	for i = 1, count do
		local a = points[i]
		local b = points[i % count + 1]
		if a and b then
			Pieces.liveCable(ctx, a, b, zone.color, 0.55, 0.9)
		elseif a and not b then
			-- next post is in the gate gap: run to the nearer pillar
			local pillar = if (a - pillarL).Magnitude < (a - pillarR).Magnitude
				then pillarL
				else pillarR
			Pieces.liveCable(ctx, a, pillar, zone.color, 0.55, 0.4)
		elseif b and not a then
			local pillar = if (b - pillarL).Magnitude < (b - pillarR).Magnitude
				then pillarL
				else pillarR
			Pieces.liveCable(ctx, pillar, b, zone.color, 0.55, 0.4)
		end
	end
end

-- Island ------------------------------------------------------------------------------------

export type IslandOptions = {
	field: Color3, -- the catch floor: the top slab, exactly at the floor
	colors: { Color3 }, -- strata under it, alternating
	grow: number?, -- each stratum steps out this far (default 2.5)
	lean: Vector2?, -- extra step-out per stratum toward one side (slot x, z)
	capBand: number?, -- this stratum (1 = first under the field) gets a grass cap
	capGrow: number?, -- ...and steps out this far instead (a wide shelf)
	side: number?, -- beach reach beside the apron (default 10)
	back: number?, -- beach reach behind it (default 22)
}

export type Island = {
	layers: { Land.Layer },
	apron: Land.Shape,
	lobes: { Land.Shape },
	key: Vector3, -- colour key of the field: ground meeting it at the floor shares it
}

local function yawOf(frame: CFrame): number
	local _, yaw, _ = frame:ToEulerAnglesYXZ()
	return yaw
end
Zone.yawOf = yawOf

-- The zone's landmass: a rectangular field slab exactly at the floor over
-- the whole footprint (+ Zone.MARGIN), strata stepping out under it (1-stud
-- walkable steps for a field near sea level, two-tone cliffs for raised
-- ones), a sand apron at beach level round the foot, and polygon beach
-- lobes behind and beside it with shore slopes into the sea. Nothing lands
-- in front (the hub side), so low catwalks cross open water.
function Zone.island(ctx: Context, zone: ZoneContext, opts: IslandOptions): Island
	local slot = zone.slot
	local F = slot.floor
	local detail = Geo.zoneDetail(zone)
	local parent = ctx.folders.ground
	local guard = Geo.guard(ctx, zone)
	local key = Vector3.new(slot.frame.X, 0, slot.frame.Z)
	local grow = opts.grow or 2.5
	local base = Land.rect(
		slot.frame,
		Vector2.new(slot.width / 2 + Zone.MARGIN, slot.depth / 2 + Zone.MARGIN)
	)
	local bands: { Land.Band } = {}
	local drop = F - BEACH
	if drop <= 4.5 then
		local steps = math.max(1, math.ceil(drop - 0.01))
		local h = drop / steps
		table.insert(bands, { color = opts.field, height = h })
		for i = 1, steps - 1 do
			table.insert(
				bands,
				{ color = opts.colors[(i - 1) % #opts.colors + 1], height = h, grow = 2 }
			)
		end
	else
		table.insert(bands, { color = opts.field, height = 2 })
		local n = math.clamp(math.floor((drop - 2) / 5 + 0.5), 1, Geo.count(detail, 3, 4))
		local h = (drop - 2) / n
		for i = 1, n do
			local capped = i == opts.capBand
			table.insert(bands, {
				color = opts.colors[(i - 1) % #opts.colors + 1],
				height = h,
				grow = if capped then opts.capGrow or grow else grow,
				lean = opts.lean,
				cap = if capped then G.grass else nil,
			})
		end
	end
	table.insert(bands, { color = G.sand, grow = 3, key = Land.SHARED })
	local layers = Land.stack(parent, base, F, BOTTOM, bands, key, guard)
	local apron = layers[#layers].shape
	Land.register(ctx, apron)

	-- beach lobes: a big one behind (wide at the back, pulled in at the
	-- front corners) and, in full detail, a bump on one side
	local rng = Geo.rng(ctx, Geo.zoneKey(zone) .. "-island")
	local frame = CFrame.new(apron.center) * apron.rotation
	local hx, hz = apron.half.X, apron.half.Y
	local reach = hx + (opts.side or 10)
	local s = if rng:NextNumber() < 0.5 then -1 else 1
	local specs = {
		{
			x = s * hx * 0.12,
			z = math.max(hz + (opts.back or 22) - reach, -hz * 0.2),
			a = reach,
			n = Geo.sides(detail, 10, 12),
		},
		{ x = -s * (hx + 2), z = -hz * 0.15, a = math.min(hx, hz) * 0.42, n = 10 },
	}
	local lobes: { Land.Shape } = {}
	local yaw = yawOf(slot.frame)
	for i = 1, Geo.count(detail, 1, 2) do
		local spec = specs[i]
		local shape = Land.fit(
			Land.poly(
				frame:PointToWorldSpace(Vector3.new(spec.x, 0, spec.z)),
				spec.a,
				spec.n,
				yaw + rng:NextNumber(0, math.pi)
			),
			BEACH,
			guard,
			0.5
		)
		if shape then
			Land.prism(parent, G.sand, shape, BEACH, BOTTOM, Land.SHARED + UP * BEACH)
			Land.register(ctx, shape)
			table.insert(lobes, shape)
			table.insert(layers, { shape = shape, top = BEACH })
		end
	end
	for _, lobe in lobes do
		Land.skirt(parent, G.wetSand, lobe, BEACH, BOTTOM, Land.registered(ctx))
	end
	return { layers = layers, apron = apron, lobes = lobes, key = key }
end

-- A low two-tier grass dune (6 parts) on the beach at `at`.
function Zone.dune(parent: Instance, at: Vector3, radius: number, yaw: number): Land.Shape
	local shape = Land.poly(at, radius, 6, yaw)
	Land.prism(parent, G.grass, shape, BEACH + 1, BEACH - 0.5)
	Land.prism(parent, G.grassDark, Land.scaled(shape, 0.55), BEACH + 2, BEACH + 1)
	return shape
end

-- Saddle ridge ----------------------------------------------------------------------------

-- A ridge of rock columns in the gap between this slot and the one before
-- it on the spiral, climbing from just above the lower field to above this
-- one, so neighbouring fields read as terraces on one mountain rather than
-- separate islands. Kept off both fields and every deck by the guard.
-- Returns the column outlines (props keep off them).
function Zone.saddle(
	ctx: Context,
	zone: ZoneContext,
	colors: { Color3 },
	cap: Color3?
): { Land.Shape }
	local index = zone.slot.index
	local prev = if zone.isTeaser then ctx.zones[#ctx.zones] else ctx.zones[index - 1]
	if not prev or prev == zone then
		return {}
	end
	local rng = Geo.rng(ctx, Geo.zoneKey(zone) .. "-saddle")
	local a0 = math.deg(prev.slot.angle)
	local a1 = math.deg(zone.slot.angle)
	local mid = a0 + Geo.angleDiff(a1, a0) / 2
	local r0 = Vector3.new(prev.slot.frame.X, 0, prev.slot.frame.Z).Magnitude
	local r1 = Vector3.new(zone.slot.frame.X, 0, zone.slot.frame.Z).Magnitude
	-- from where the gap between the two fields opens to their far edges
	local inner = (r0 + r1) / 2 - 10
	local outer = (r0 + prev.slot.depth / 2 + r1 + zone.slot.depth / 2) / 2 + 6
	local low = math.max(prev.slot.floor, 4) + 6
	local high = math.max(zone.slot.floor, low) + 14
	local detail = Geo.zoneDetail(zone)
	return Land.ridge(
		ctx.folders.ground,
		Geo.polar(mid, inner, 0),
		Geo.polar(mid + rng:NextNumber(-4, 4), outer, 0),
		low,
		high,
		20,
		rng,
		colors,
		if detail > 0 then cap else nil,
		Geo.guard(ctx, zone),
		Geo.count(detail, 2, 3),
		BOTTOM
	)
end

-- Vignette placement ----------------------------------------------------------------------

export type Placer = {
	-- first candidate (slot-frame x, z) that has settled ground (not on a
	-- crumbly edge), is clear of fields and decks and keeps `room` studs
	-- from earlier vignettes; returns the ground point or nil
	find: (candidates: { Vector2 }, room: number, minTop: number?, maxTop: number?) -> Vector3?,
	-- ground under one slot-frame spot (nil if none)
	ground: (x: number, z: number, clearance: number) -> Vector3?,
}

-- `blocked`: ground that is not a layer to stand on (ridges, columns,
-- dunes, arches); nothing is placed inside or against it.
function Zone.placer(
	ctx: Context,
	zone: ZoneContext,
	layers: { Land.Layer },
	blocked: { Land.Shape }?
): Placer
	local used: { { p: Vector3, r: number } } = {}
	local avoid: { Land.Shape } = blocked or {}
	local function ground(x: number, z: number, clearance: number): Vector3?
		local p = Geo.slotPoint(zone, x, z)
		if Land.containsAny(avoid, p, -clearance - 1) then
			return nil
		end
		local top = Land.surfaceAt(layers, p, clearance)
		if top and top > 0.5 and Geo.isClear(ctx, p, clearance) then
			return Vector3.new(p.X, top, p.Z)
		end
		return nil
	end
	local function find(
		candidates: { Vector2 },
		room: number,
		minTop: number?,
		maxTop: number?
	): Vector3?
		for _, c in candidates do
			local p = ground(c.X, c.Y, math.min(room, 4))
			if p and p.Y >= (minTop or -math.huge) and p.Y <= (maxTop or math.huge) then
				local free = true
				for _, u in used do
					if
						(Vector3.new(p.X, 0, p.Z) - Vector3.new(u.p.X, 0, u.p.Z)).Magnitude
						< room + u.r
					then
						free = false
						break
					end
				end
				if free then
					table.insert(used, { p = p, r = room })
					return p
				end
			end
		end
		return nil
	end
	return { find = find, ground = ground }
end

-- Floor patterns (flush inlays, top at floor + 0.12) ----------------------------------------

local INLAY_LIFT = 0.12

local function inlay(
	zone: ZoneContext,
	x: number,
	z: number,
	w: number,
	d: number,
	color: Color3,
	material: Enum.Material,
	lift: number?
): BasePart
	return Kit.decor({
		Name = "FloorInlay",
		Size = Vector3.new(w, 0.4, d),
		CFrame = zone.slot.frame * CFrame.new(x, (lift or INLAY_LIFT) - 0.2, z),
		Color = color,
		Material = material,
		CanCollide = false,
		CastShadow = false,
		Parent = zone.folder,
	})
end

-- Discs sit 0.02 below the bands they scallop, so the two never z-fight.
local function inlayDisc(
	zone: ZoneContext,
	x: number,
	z: number,
	diameter: number,
	color: Color3,
	material: Enum.Material
)
	local bottom = zone.slot.frame:PointToWorldSpace(Vector3.new(x, INLAY_LIFT - 0.42, z))
	Kit.cylinder(zone.folder, bottom, 0.4, diameter, {
		Name = "FloorInlay",
		Color = color,
		Material = material,
		CanCollide = false,
		CastShadow = false,
	})
end

-- Bands across the zone (parallel to the gate edge) with scalloped wave
-- edges: `scallops` big half-discs along each band's back edge.
function Zone.waveStripes(
	zone: ZoneContext,
	bands: number,
	color: Color3,
	material: Enum.Material,
	scallops: number
)
	local cw, cd = zone.catchWidth, zone.catchDepth
	local period = cd / bands
	local bandW = period * 0.46
	local discD = math.min(bandW * 1.05, cw / scallops)
	local discStep = (cw - discD) / math.max(scallops - 1, 1)
	for i = 0, bands - 1 do
		local z = -cd / 2 + (i + 0.5) * period
		inlay(zone, 0, z, cw, bandW, color, material)
		for k = 0, scallops - 1 do
			local x = -cw / 2 + discD / 2 + k * discStep
			inlayDisc(zone, x, z + bandW / 2, discD, color, material)
		end
	end
end

-- Checkerboard of square tiles over the catch area (every other cell).
function Zone.checker(
	zone: ZoneContext,
	cell: number,
	color: Color3,
	material: Enum.Material,
	inset: number?
)
	local cw, cd = zone.catchWidth, zone.catchDepth
	local nx = math.max(1, math.floor(cw / cell + 0.5))
	local nz = math.max(1, math.floor(cd / cell + 0.5))
	local sx, sz = cw / nx, cd / nz
	local pad = inset or 0
	for ix = 0, nx - 1 do
		for iz = 0, nz - 1 do
			if (ix + iz) % 2 == 0 then
				local x = -cw / 2 + (ix + 0.5) * sx
				local z = -cd / 2 + (iz + 0.5) * sz
				inlay(zone, x, z, sx - pad, sz - pad, color, material)
			end
		end
	end
end

-- A frame round the field just inside the footprint edge: a brass band
-- with a glowing strip in the zone colour inside it, so every field's
-- outline reads from far away in its own colour.
function Zone.floorFrame(zone: ZoneContext, brass: Color3, width: number)
	local function ring(
		inset: number,
		w: number,
		color: Color3,
		material: Enum.Material,
		lift: number
	)
		local hw = zone.slot.width / 2 - inset - w / 2
		local hd = zone.slot.depth / 2 - inset - w / 2
		inlay(zone, 0, -hd, 2 * hw + w, w, color, material, lift)
		inlay(zone, 0, hd, 2 * hw + w, w, color, material, lift)
		inlay(zone, -hw, 0, w, 2 * hd - w, color, material, lift)
		inlay(zone, hw, 0, w, 2 * hd - w, color, material, lift)
	end
	ring(0.3, width, brass, M.metal, INLAY_LIFT)
	ring(0.3 + width, 1, zone.color, M.neon, INLAY_LIFT + 0.02)
end

return Zone
