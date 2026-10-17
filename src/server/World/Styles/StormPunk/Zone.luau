--!strict
-- Shared zone kit for every StormPunk zone, whatever its theme or slot:
-- the riveted catwalk connector, the insulator-fence border, the insulator
-- arch gate and the flush two-tone floor patterns. Everything is placed in
-- the slot's own frame, so any position, rotation, size or height works.
-- Every zone gets the same full detail (no distance LOD): the pieces are
-- cheap enough that 7 zones fit the part budget.

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

local UP = Vector3.new(0, 1, 0)
local SEA_FLOOR = Geo.SEA_FLOOR

local Zone = {}

-- Gate geometry shared by the gate and the border (posts end at the pillars).
Zone.GATE_HALF = 8.5 -- pillar distance from the gate centre line
Zone.GATE_OUT = 2.2 -- pillars stand this far outside the footprint edge
Zone.GATE_ATTACH_Y = 4.2 -- border cables meet the pillars here
Zone.POST_HEIGHT = 5.5
Zone.POST_SPACING = 22
Zone.DECK_WIDTH = 10

export type BridgeStyle = {
	deck: Color3,
	deckMaterial: Enum.Material,
	rail: Color3,
	pile: Color3,
	stack: Enum.Material, -- terrain rock the long spans hop across
}

Zone.defaultBridge = {
	deck = C.iron,
	deckMaterial = M.plate,
	rail = C.brass,
	pile = C.copper,
	stack = Enum.Material.Basalt,
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
-- basalt stacks (terrain, no parts). Returns the end of the deck.
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
			Land.pinnacle(
				ctx,
				Vector3.new(top.X, SEA_FLOOR, top.Z),
				math.min(top.Y - 4, 14 + rng:NextNumber(0, 8)) - SEA_FLOOR,
				rng:NextNumber(4.5, 6.5),
				rng,
				{ style.stack, Enum.Material.Rock, style.stack },
				2.6,
				Enum.Material.LeafyGrass,
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
		local top = lantern.Position
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
		Pieces.column(parent, foot + UP * (Zone.GATE_ATTACH_Y - 0.6), 1.4, 3.6, C.ceramic, M.ceramic)
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
	Pieces.jacobsLadder(ctx, parent, (g * CFrame.new(0, height - 0.6, 0)).Position, g.RightVector, 5)
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
	local function ring(inset: number, w: number, color: Color3, material: Enum.Material, lift: number)
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
