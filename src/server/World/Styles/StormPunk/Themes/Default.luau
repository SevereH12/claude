--!strict
-- Default theme ("Generator Yard"), used for any zone theme StormPunk has no
-- module for. A slate island with stepped cliffs, a riveted two-tone plate
-- field, the Dynamo Stack (banded smokestack + generator drum + orb),
-- transformers, pipe runs and barrels. Works for any slot and floor height.

local ServerScriptService = game:GetService("ServerScriptService")

local World = ServerScriptService.Server.World
local Kit = require(World.Kit)
local WorldTypes = require(World.Types)
local Geo = require(script.Parent.Parent.Geo)
local Land = require(script.Parent.Parent.Land)
local Palette = require(script.Parent.Parent.Palette)
local Pieces = require(script.Parent.Parent.Pieces)
local Zone = require(script.Parent.Parent.Zone)

type Context = WorldTypes.Context
type ZoneContext = WorldTypes.ZoneContext

local C = Palette.colors
local T = Palette.tints
local M = Palette.materials
local TERRAIN = Enum.Material
local SEA_FLOOR = -20
local UP = Vector3.new(0, 1, 0)

local STACK = { u = 0.28, v = 0.5, out = 18 }

local Default = {}

Default.bridge = Zone.defaultBridge

local layersByZone: { [string]: { Land.Layer } } = {}

function Default.ground(ctx: Context, zone: ZoneContext)
	local slot = zone.slot
	local F = slot.floor
	local w, d = slot.width, slot.depth
	local rng = Geo.rng(ctx, Geo.zoneKey(zone) .. "-ground")
	local layers: { Land.Layer } = {}

	Land.fill(
		ctx,
		Land.rectOutline(slot.frame, w + 58, d + 58, rng, 16, 10, 3),
		SEA_FLOOR,
		-3,
		TERRAIN.Sand
	)
	local shore = Land.rectOutline(slot.frame, w + 46, d + 46, rng, 13, 8, 4)
	Land.cliff(ctx, shore, SEA_FLOOR, 3, TERRAIN.Rock, {}, TERRAIN.Rock)
	-- a skirt of slate shelves stepping up to the yard
	local shelfTop = math.max(F - 6, 6)
	local shelf = Land.clip(
		Land.rectOutline(slot.frame, w + 28, d + 28, rng, 10, 6, 2),
		Geo.landSafe(ctx, shelfTop, zone)
	)
	if shelfTop < F then
		Land.cliff(
			ctx,
			shelf,
			SEA_FLOOR,
			shelfTop,
			TERRAIN.Slate,
			{ TERRAIN.Rock, TERRAIN.Basalt },
			TERRAIN.LeafyGrass
		)
	end
	local yard = Land.clip(
		Land.rectOutline(slot.frame, w + 12, d + 12, rng, 5, 2),
		Geo.landSafe(ctx, F, zone)
	)
	Land.cliff(
		ctx,
		yard,
		SEA_FLOOR,
		F,
		TERRAIN.Slate,
		{ TERRAIN.Basalt, TERRAIN.Rock },
		TERRAIN.Concrete
	)
	Land.flatRect(ctx, slot.frame, w + 4, d + 4, F, 8, TERRAIN.Concrete)
	-- rock pad for the Dynamo Stack behind the field
	local base = Geo.edgePoint(zone, STACK.u, STACK.v, STACK.out, 0)
	if Geo.isClear(ctx, base, 10) then
		local pad = Land.clip(Land.roundOutline(base, 13, rng, 6, 2), Geo.landSafe(ctx, F, zone))
		Land.cliff(ctx, pad, SEA_FLOOR, F, TERRAIN.Slate, { TERRAIN.Basalt }, TERRAIN.Concrete)
		table.insert(layers, { outline = pad, top = F })
	end
	table.insert(layers, { outline = yard, top = F })
	if shelfTop < F then
		table.insert(layers, { outline = shelf, top = shelfTop })
	end
	table.insert(layers, { outline = shore, top = 3 })
	layersByZone[Geo.zoneKey(zone)] = layers

	-- the field: riveted two-tone plates with grout lines
	Zone.plates(zone, 16, T.ironLight, T.patinaDark, M.plate)
	Zone.floorFrame(zone, C.brass, 1.2)
end

local function dynamoStack(
	ctx: Context,
	parent: Instance,
	base: Vector3,
	facing: CFrame,
	color: Color3
)
	Pieces.block(
		parent,
		CFrame.new(base + UP * 1) * facing.Rotation,
		Vector3.new(18, 2, 12),
		C.iron,
		M.plate,
		true
	)
	local stackTop =
		Pieces.smokestack(parent, base + UP * 2 + facing.RightVector * 5, 40, 5.5, true)
	local _ = stackTop
	-- generator drum lying on its side
	local drumC = base + UP * 6.5 - facing.RightVector * 3
	Pieces.pipe(parent, drumC - facing.LookVector * 5, drumC + facing.LookVector * 5, 9, C.copper)
	for _, t in { -3.5, 0, 3.5 } do
		Pieces.pipe(
			parent,
			drumC + facing.LookVector * (t - 0.4),
			drumC + facing.LookVector * (t + 0.4),
			9.6,
			if t == 0 then C.patina else C.brass
		)
	end
	Pieces.insulator(parent, drumC + UP * 4.4, 1.1, 3)
	local orb = Pieces.orb(parent, drumC + UP * 8.6, 3.2, C.volt, 40, true)
	Pieces.liveCable(
		ctx,
		orb.CFrame.Position,
		base + UP * 30 + facing.RightVector * 5,
		color,
		0.35,
		3
	)
end

local function transformer(parent: Instance, bottom: Vector3, yaw: number)
	local cf = CFrame.new(bottom + UP * 2.2) * CFrame.Angles(0, math.rad(yaw), 0)
	Pieces.block(parent, cf, Vector3.new(4.4, 4.4, 3.2), T.ironLight, M.metal, true)
	for _, x in { -1.6, 0, 1.6 } do
		Pieces.block(parent, cf * CFrame.new(x, 0, 1.7), Vector3.new(0.4, 3.8, 0.4), C.iron)
	end
	for _, x in { -1.3, 1.3 } do
		Pieces.insulator(parent, (cf * CFrame.new(x, 2.2, 0)).Position, 0.7, 3)
	end
	Pieces.block(parent, cf * CFrame.new(0, 0.6, -1.65), Vector3.new(1.6, 1, 0.1), C.hazard, M.neon)
end

function Default.dress(ctx: Context, zone: ZoneContext)
	local slot = zone.slot
	local F = slot.floor
	local parent = zone.folder
	local rng = Geo.rng(ctx, Geo.zoneKey(zone) .. "-dress")
	local layers = layersByZone[Geo.zoneKey(zone)] or {}
	local function ground(p: Vector3, shrink: number): Vector3?
		local top = Land.surfaceAt(layers, p, shrink)
		return if top and top > 1 then Vector3.new(p.X, top, p.Z) else nil
	end

	-- hero: the Dynamo Stack behind the field
	local base = Geo.edgePoint(zone, STACK.u, STACK.v, STACK.out, 0)
	if Geo.isClear(ctx, base, 10) then
		dynamoStack(
			ctx,
			parent,
			Vector3.new(base.X, F, base.Z),
			Geo.facing(base, slot.frame.Position),
			zone.color
		)
	end

	-- transformers along the sides, lamps around the rim
	for i, v in { -0.25, 0.1, 0.4 } do
		local p = ground(Geo.edgePoint(zone, if i % 2 == 0 then 0.5 else -0.5, v, 8, 0), 3)
		if p and Geo.isClear(ctx, p, 3) then
			transformer(parent, p, math.deg(slot.angle) + 90)
		end
	end
	for _, cf in Kit.perimeter(zone, 30 / Geo.detail(zone)) do
		local p = cf.Position + cf.LookVector * 4.6
		if Geo.isClear(ctx, p, 1) then
			Pieces.lamp(
				parent,
				p,
				7,
				T.warmLight,
				if rng:NextNumber() < 0.4 * Geo.detail(zone) then 18 else nil
			)
		end
	end
	-- pipe run along the back
	local a = ground(Geo.edgePoint(zone, -0.45, 0.5, 5, 0), 1)
	local b = ground(Geo.edgePoint(zone, 0.1, 0.5, 5, 0), 1)
	if a and b and Geo.isClear(ctx, a, 1.5) and Geo.isClear(ctx, b, 1.5) then
		Pieces.pipe(parent, a + UP * 1.6, b + UP * 1.6, 1.4, C.copper)
		Pieces.pipe(parent, a + UP * 3.2, b + UP * 3.2, 1, C.patina)
		local n = math.max(1, math.floor((b - a).Magnitude / 10))
		for i = 0, n do
			local p = a:Lerp(b, i / n)
			Pieces.block(parent, CFrame.new(p + UP * 1.7), Vector3.new(0.5, 3.4, 0.5), C.iron)
		end
	end
	-- small stuff
	for _ = 1, Geo.count(zone, 40) do
		local p = ground(
			Geo.edgePoint(
				zone,
				rng:NextNumber(-0.55, 0.55),
				rng:NextNumber(-0.5, 0.55),
				rng:NextNumber(4.5, 20),
				0
			),
			1.5
		)
		if p and Geo.isClear(ctx, p, 1.2) then
			local roll = rng:NextNumber()
			if roll < 0.35 then
				Pieces.rocks(parent, p, rng:NextNumber(1.2, 2.8), rng, T.rockDark)
			elseif roll < 0.6 then
				Pieces.barrel(parent, p, if rng:NextNumber() < 0.5 then C.copper else C.patina)
			elseif roll < 0.8 then
				Pieces.crate(parent, p, rng:NextNumber(1.6, 2.4), rng:NextNumber(0, 90))
			else
				Pieces.tuft(parent, p, rng, C.sage)
			end
		end
	end
end

return Default
