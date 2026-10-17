--!strict
-- Shared zone kit for every StormPunk zone, whatever its theme or slot:
-- the riveted catwalk connector, the insulator-fence border, the insulator
-- arch gate and the flush two-tone floor patterns. Everything is placed in
-- the slot's own frame, so any position, rotation, size or height works.

local ServerScriptService = game:GetService("ServerScriptService")

local World = ServerScriptService.Server.World
local Kit = require(World.Kit)
local WorldTypes = require(World.Types)
local Geo = require(script.Parent.Geo)
local Palette = require(script.Parent.Palette)
local Pieces = require(script.Parent.Pieces)

type Context = WorldTypes.Context
type ZoneContext = WorldTypes.ZoneContext

local C = Palette.colors
local T = Palette.tints
local M = Palette.materials

local UP = Vector3.new(0, 1, 0)

local Zone = {}

-- Gate geometry shared by the gate and the border (posts end at the pillars).
Zone.GATE_HALF = 8.5 -- pillar distance from the gate centre line
Zone.GATE_OUT = 2.2 -- pillars stand this far outside the footprint edge
Zone.GATE_ATTACH_Y = 4.2 -- border cables meet the pillars here
Zone.POST_HEIGHT = 5.5
Zone.DECK_WIDTH = 10

export type BridgeStyle = {
	deck: Color3,
	deckMaterial: Enum.Material,
	rail: Color3,
	pile: Color3,
}

Zone.defaultBridge = {
	deck = C.iron,
	deckMaterial = M.plate,
	rail = C.brass,
	pile = C.copper,
} :: BridgeStyle

local function name(zone: ZoneContext): string
	local def = zone.def
	return if def then def.displayName else "Coming Soon"
end

-- Connector ------------------------------------------------------------------------

-- Riveted catwalk from `from` to `to` (points on the walking surface).
-- `stopAt` (0..1) builds only that fraction of the deck (the teaser's
-- unfinished bridge); piles continue the whole way.
function Zone.catwalk(
	ctx: Context,
	parent: Instance,
	from: Vector3,
	to: Vector3,
	color: Color3,
	style: BridgeStyle,
	stopAt: number?,
	detail: number?
): Vector3
	local finish = stopAt or 1
	local density = detail or 1
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
	-- side girders and the zone's light trail down the middle
	for _, s in { -1, 1 } do
		local off = side * s * (half - 0.3) - UP * 1.2
		Pieces.strut(parent, from + off, deckEnd + off, 1.4, T.copperDark, M.metal)
		Pieces.railing(
			parent,
			from + side * s * (half - 0.4),
			deckEnd + side * s * (half - 0.4),
			3.2,
			9 / density,
			style.rail
		)
	end
	Pieces.trail(parent, from, deckEnd, 1.2, color, M.neon, 0.14)

	-- piles under the deck all the way (unfinished bridges keep their piles)
	local piles = math.max(1, math.floor(run * math.sqrt(density) / 22))
	for i = 1, piles do
		local t = i / (piles + 1)
		local p = from:Lerp(to, t)
		local top = p - UP * 1.6
		for _, s in { -1, 1 } do
			local foot = top + side * s * 3.8
			local bottom = Vector3.new(foot.X, -14, foot.Z)
			Pieces.column(parent, bottom, top.Y - bottom.Y, 1.6, style.pile, M.metal, true)
		end
		Pieces.strut(parent, top + side * 4.6, top - side * 4.6, 1, C.iron)
		if t > finish then
			-- bare pile cap on unfinished stretches
			Pieces.strut(
				parent,
				top + side * 4.6 + UP * 0.8,
				top - side * 4.6 + UP * 0.8,
				0.8,
				C.hazard
			)
		end
	end

	-- lamp stations with glowing cables between them
	local stations = math.max(1, math.floor(run * finish * density / 24))
	local prev: { Vector3 }? = nil
	for i = 1, stations do
		local t = finish * (i - 0.4) / stations
		local p = from:Lerp(to, t)
		local tops: { Vector3 } = {}
		for _, s in { -1, 1 } do
			local lantern = Pieces.lamp(
				parent,
				p + side * s * (half - 0.4),
				6.5,
				C.volt,
				if s == 1 and i % 2 == 1 and density >= 0.7 then 18 else nil
			)
			table.insert(tops, lantern.CFrame.Position)
		end
		if prev then
			Pieces.liveCable(ctx, prev[1], tops[1], C.volt, 0.22, 1.6)
			if density >= 0.85 then
				Pieces.liveCable(ctx, prev[2], tops[2], C.volt, 0.22, 1.6)
			end
		end
		prev = tops
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
		style or Zone.defaultBridge,
		nil,
		Geo.detail(zone)
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
		Pieces.column(parent, foot - UP, height + 1, 2.6, C.copper, M.metal, true)
		Pieces.column(parent, foot - UP * 0.2, 1.8, 3.8, C.iron, M.metal)
		Pieces.column(parent, foot + UP * 5, 0.9, 3.1, C.brass)
		Pieces.column(parent, foot + UP * Zone.GATE_ATTACH_Y, 0.6, 3.2, C.ceramic, M.ceramic)
		local top = Pieces.insulator(parent, foot + UP * height, 1, 3)
		local lamp = Pieces.ball(parent, top + UP * 0.9, 2, color, M.neon)
		Pieces.glow(lamp, color, 20, 1.8)
		table.insert(attach, foot + UP * Zone.GATE_ATTACH_Y)
	end
	local arch = Pieces.block(
		parent,
		g * CFrame.new(0, height - 1.4, 0),
		Vector3.new(2 * Zone.GATE_HALF + 2, 1.3, 1.3),
		C.brass,
		M.metal
	)
	if Geo.detail(zone) >= 0.85 then
		Pieces.sparks(arch, C.volt, 5)
	end
	local def = zone.def
	Pieces.framedSign(
		parent,
		g * CFrame.new(0, height - 5.2, 0),
		15,
		5,
		string.upper(name(zone)),
		if def then def.tagline else nil,
		Palette.sign(color, true)
	)
	Pieces.jacobsLadder(
		ctx,
		parent,
		(g * CFrame.new(0, height - 0.7, 0)).Position,
		g.RightVector,
		5
	)
	-- threshold strip across the entrance
	local a = (zone.slot.gate * CFrame.new(-Zone.GATE_HALF + 1.5, 0, -0.6)).Position
	local b = (zone.slot.gate * CFrame.new(Zone.GATE_HALF - 1.5, 0, -0.6)).Position
	Pieces.trail(parent, a, b, 1, color, M.neon, 0.12)
	return attach[1], attach[2]
end

-- Border ---------------------------------------------------------------------------------

-- Insulator posts on the footprint edge joined by glowing cables in the
-- zone colour (upper strand) and a dark lower strand. Gap at the gate.
function Zone.buildBorder(ctx: Context, zone: ZoneContext, spacing: number?)
	local slot = zone.slot
	local parent = zone.folder
	local hd = slot.depth / 2
	local frames = Kit.perimeter(zone, (spacing or 14) / math.sqrt(Geo.detail(zone)))
	local points: { Vector3? } = {}
	for i, cf in frames do
		local localPos = slot.frame:PointToObjectSpace(cf.Position)
		local inGap = math.abs(localPos.Z + hd) < 0.5 and math.abs(localPos.X) < Zone.GATE_HALF + 2
		if inGap then
			points[i] = nil
		else
			points[i] = Pieces.insulatorPost(parent, cf.Position, Zone.POST_HEIGHT, zone.color)
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
			Pieces.liveCable(ctx, a, b, zone.color, 0.32, 0.7)
			if Geo.detail(zone) >= 0.85 then
				Pieces.wire(ctx, a - UP * 2.4, b - UP * 2.4, 0.5, 0.18)
			end
		elseif a and not b then
			-- next post is in the gate gap: run to the nearer pillar
			local pillar = if (a - pillarL).Magnitude < (a - pillarR).Magnitude
				then pillarL
				else pillarR
			Pieces.liveCable(ctx, a, pillar, zone.color, 0.32, 0.4)
		elseif b and not a then
			local pillar = if (b - pillarL).Magnitude < (b - pillarR).Magnitude
				then pillarL
				else pillarR
			Pieces.liveCable(ctx, pillar, b, zone.color, 0.32, 0.4)
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
	material: Enum.Material
): BasePart
	return Kit.decor({
		Name = "FloorInlay",
		Size = Vector3.new(w, 0.4, d),
		CFrame = zone.slot.frame * CFrame.new(x, INLAY_LIFT - 0.2, z),
		Color = color,
		Material = material,
		CanCollide = false,
		CastShadow = false,
		Parent = zone.folder,
	})
end

local function inlayDisc(
	zone: ZoneContext,
	x: number,
	z: number,
	diameter: number,
	color: Color3,
	material: Enum.Material
)
	local bottom = zone.slot.frame:PointToWorldSpace(Vector3.new(x, INLAY_LIFT - 0.4, z))
	Kit.cylinder(zone.folder, bottom, 0.4, diameter, {
		Name = "FloorInlay",
		Color = color,
		Material = material,
		CanCollide = false,
		CastShadow = false,
	})
end

-- Bands across the zone (parallel to the gate edge) with scalloped wave edges.
function Zone.waveStripes(zone: ZoneContext, bands: number, color: Color3, material: Enum.Material)
	local cw, cd = zone.catchWidth, zone.catchDepth
	local period = cd / bands
	local bandW = period * 0.42
	local discD = bandW * 0.9
	local count = math.max(1, math.floor(cw / (discD * 1.25)))
	local discStep = (cw - discD) / math.max(count - 1, 1)
	for i = 0, bands - 1 do
		local z = -cd / 2 + (i + 0.5) * period
		inlay(zone, 0, z, cw, bandW, color, material)
		for k = 0, count - 1 do
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

-- Plate grid: every cell gets a plate, two tones alternating; grout lines
-- of the terrain show between them.
function Zone.plates(
	zone: ZoneContext,
	cell: number,
	colorA: Color3,
	colorB: Color3,
	material: Enum.Material
)
	local cw, cd = zone.catchWidth, zone.catchDepth
	local nx = math.max(1, math.floor(cw / cell + 0.5))
	local nz = math.max(1, math.floor(cd / cell + 0.5))
	local sx, sz = cw / nx, cd / nz
	for ix = 0, nx - 1 do
		for iz = 0, nz - 1 do
			local x = -cw / 2 + (ix + 0.5) * sx
			local z = -cd / 2 + (iz + 0.5) * sz
			inlay(
				zone,
				x,
				z,
				sx - 1.4,
				sz - 1.4,
				if (ix + iz) % 2 == 0 then colorA else colorB,
				material
			)
		end
	end
end

-- A frame of flush strips just inside the footprint edge: makes the field's
-- outline read from far away.
function Zone.floorFrame(zone: ZoneContext, color: Color3, width: number)
	local hw, hd = zone.slot.width / 2 - width / 2 - 0.3, zone.slot.depth / 2 - width / 2 - 0.3
	inlay(zone, 0, -hd, 2 * hw + width, width, color, M.metal)
	inlay(zone, 0, hd, 2 * hw + width, width, color, M.metal)
	inlay(zone, -hw, 0, width, 2 * hd - width, color, M.metal)
	inlay(zone, hw, 0, width, 2 * hd - width, color, M.metal)
end

return Zone
