--!strict
-- Default theme ("Generator Yard"), used for any zone theme StormPunk has
-- no module for. A slate island with leaning stepped cliffs and a basalt
-- crag behind the field, a riveted plate checker tinted with the zone's
-- colour, the Dynamo Stack (smokestack, generator drums and an orb; its
-- height, drum count and side vary per zone), a transformer yard, pipe
-- runs and cable spools. Works for any slot and floor height.

local ServerScriptService = game:GetService("ServerScriptService")

local World = ServerScriptService.Server.World
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
local L = Palette.light
local TERRAIN = Enum.Material
local SEA_FLOOR = Geo.SEA_FLOOR
local UP = Vector3.new(0, 1, 0)

local Default = {}

Default.bridge = Zone.defaultBridge

type Hero = { x: number, z: number, height: number, drums: number }

local layersByZone: { [string]: { Land.Layer } } = {}
local blockedByZone: { [string]: { Land.Outline } } = {}
local heroByZone: { [string]: Hero } = {}

-- The Dynamo Stack's look and spot, from a hash of the zone id: every
-- generator yard gets its own silhouette.
local function heroFor(zone: ZoneContext): Hero
	local h = Geo.hash(Geo.zoneKey(zone))
	local side = if h % 2 == 0 then 1 else -1
	return {
		x = side * zone.slot.width * (0.18 + (h // 2 % 3) * 0.08),
		z = zone.slot.depth / 2 + 18,
		height = 34 + (h // 6 % 4) * 4,
		drums = 1 + h // 24 % 2,
	}
end

function Default.ground(ctx: Context, zone: ZoneContext)
	local slot = zone.slot
	local F = slot.floor
	local w, d = slot.width, slot.depth
	local hw, hd = w / 2, d / 2
	local key = Geo.zoneKey(zone)
	local rng = Geo.rng(ctx, key .. "-ground")
	local guard = Geo.guard(ctx, zone)
	local layers: { Land.Layer } = {}

	Land.fill(
		ctx,
		Land.organic(slot.frame, w + 60, d + 60, rng, { edge = 16, jitter = 10, bays = 2 }),
		SEA_FLOOR,
		-3,
		TERRAIN.Sand,
		0,
		guard
	)
	local shore = Land.cliff(
		ctx,
		Land.organic(slot.frame, w + 46, d + 46, rng, {
			edge = 13,
			jitter = 8,
			bays = 2,
			spits = 1,
			spitLength = 20,
		}),
		SEA_FLOOR,
		3,
		TERRAIN.Rock,
		{},
		TERRAIN.Rock,
		rng,
		{ guard = guard, lean = 4, foot = -2 }
	)
	Land.talus(ctx, shore, 0, rng, 8, TERRAIN.Basalt, guard)
	-- a skirt of grassy slate shelves stepping up to the yard
	local shelfTop = math.max(F - 6, 6)
	local shelf: Land.Outline? = nil
	if shelfTop < F then
		shelf = Land.cliff(
			ctx,
			Land.organic(slot.frame, w + 28, d + 28, rng, { edge = 10, jitter = 6, bays = 1 }),
			SEA_FLOOR,
			shelfTop,
			TERRAIN.Slate,
			{ TERRAIN.Rock, TERRAIN.Basalt },
			TERRAIN.LeafyGrass,
			rng,
			{ guard = guard, lean = 7, foot = 0 }
		)
	end
	local yard = Land.cliff(
		ctx,
		Land.organic(slot.frame, w + 12, d + 12, rng, { edge = 8, jitter = 2 }),
		SEA_FLOOR,
		F,
		TERRAIN.Slate,
		{ TERRAIN.Basalt, TERRAIN.Rock },
		TERRAIN.Concrete,
		rng,
		{ guard = guard, lean = 6, foot = 0 }
	)
	Land.flatRect(ctx, slot.frame, w + 4, d + 4, F, 8, TERRAIN.Concrete)

	-- a basalt crag behind the field, standing 10-18 above it
	local hero = heroFor(zone)
	heroByZone[key] = hero
	local blocked = Land.ridge(
		ctx,
		Geo.slotPoint(zone, -math.sign(hero.x) * hw * 0.9, hd + 20),
		Geo.slotPoint(zone, math.sign(hero.x) * hw * 0.05, hd + 24),
		F + 10,
		F + 18,
		16,
		rng,
		TERRAIN.Basalt,
		{ TERRAIN.Slate },
		TERRAIN.LeafyGrass,
		guard
	)
	local saddle =
		Zone.saddle(ctx, zone, TERRAIN.Slate, { TERRAIN.Basalt, TERRAIN.Rock }, TERRAIN.LeafyGrass)
	table.move(saddle, 1, #saddle, #blocked + 1, blocked)
	-- rock pad for the Dynamo Stack behind the field
	local base = Geo.slotPoint(zone, hero.x, hero.z)
	local pad: Land.Outline? = nil
	if Geo.isClear(ctx, base, 10) then
		pad = Land.cliff(
			ctx,
			Land.blob(base, 14, rng, 6, 2),
			SEA_FLOOR,
			F,
			TERRAIN.Slate,
			{ TERRAIN.Basalt },
			TERRAIN.Concrete,
			rng,
			{ guard = guard, lean = 5, foot = 0 }
		)
	end
	if pad then
		table.insert(layers, { outline = pad, top = F })
	end
	table.insert(layers, { outline = yard, top = F })
	if shelf then
		table.insert(layers, { outline = shelf, top = shelfTop })
	end
	table.insert(layers, { outline = shore, top = 3 })
	table.sort(layers, function(la, lb)
		return la.top > lb.top
	end)
	layersByZone[key] = layers
	blockedByZone[key] = blocked

	-- the field: riveted plates tinted with the zone colour on concrete,
	-- framed in brass with a glowing zone-colour strip
	Zone.checker(zone, 16, T.ironLight:Lerp(zone.color, 0.35), M.plate, 1.2)
	Zone.floorFrame(zone, C.brass, 1.5)
end

local function dynamoStack(
	ctx: Context,
	parent: Instance,
	base: Vector3,
	facing: CFrame,
	color: Color3,
	hero: Hero
)
	Pieces.block(
		parent,
		CFrame.new(base + UP * 1) * facing.Rotation,
		Vector3.new(20, 2, 12),
		C.iron,
		M.plate,
		true
	)
	local side = math.sign(hero.x)
	local stackTop = Pieces.smokestack(
		parent,
		base + UP * 2 + facing.RightVector * (side * 6),
		hero.height,
		6,
		true
	)
	-- generator drums lying on their sides
	local orbAt = base
	for k = 1, hero.drums do
		local drumC = base + UP * 6.8 - facing.RightVector * (side * (k * 6.5 - 4))
		Pieces.pipe(
			parent,
			drumC - facing.LookVector * 5,
			drumC + facing.LookVector * 5,
			9.4,
			C.copper
		)
		for _, t in { -3.5, 3.5 } do
			Pieces.pipe(
				parent,
				drumC + facing.LookVector * (t - 0.4),
				drumC + facing.LookVector * (t + 0.4),
				10,
				C.brass
			)
		end
		if k == 1 then
			Pieces.insulator(parent, drumC + UP * 4.6, 1.2, 3)
			orbAt = drumC + UP * 9.2
		end
	end
	Pieces.orb(parent, orbAt, 3.6, C.volt, 40, true)
	Pieces.liveCable(ctx, orbAt, stackTop - UP * 6, color, 0.4, 3)
end

local function transformer(parent: Instance, bottom: Vector3, yaw: number)
	local cf = CFrame.new(bottom + UP * 2.4) * CFrame.Angles(0, math.rad(yaw), 0)
	Pieces.block(parent, cf, Vector3.new(4.6, 4.8, 3.4), T.ironLight, M.metal, true)
	Pieces.block(
		parent,
		cf * CFrame.new(0, -2, 0),
		Vector3.new(5.4, 0.8, 4.2),
		C.iron,
		M.concrete,
		true
	)
	for _, x in { -1.4, 1.4 } do
		Pieces.column(parent, (cf * CFrame.new(x, 2.4, 0)).Position, 2, 1.4, C.ceramic, M.ceramic)
	end
	Pieces.block(parent, cf * CFrame.new(0, 0.6, -1.75), Vector3.new(2.2, 0.8, 0.1), C.volt, M.neon)
end

function Default.dress(ctx: Context, zone: ZoneContext)
	local slot = zone.slot
	local F = slot.floor
	local hw, hd = slot.width / 2, slot.depth / 2
	local parent = zone.folder
	local key = Geo.zoneKey(zone)
	local rng = Geo.rng(ctx, key .. "-dress")
	local center = slot.frame.Position
	local place = Zone.placer(ctx, zone, layersByZone[key] or {}, blockedByZone[key])
	local V2 = Vector2.new

	-- hero: the Dynamo Stack behind the field
	local hero = heroByZone[key] or heroFor(zone)
	local base = Geo.slotPoint(zone, hero.x, hero.z)
	if Geo.isClear(ctx, base, 10) then
		dynamoStack(
			ctx,
			parent,
			Vector3.new(base.X, F, base.Z),
			Geo.facing(base, center),
			zone.color,
			hero
		)
	end

	-- vignette: a transformer yard with a lamp and barrels
	local yard = place.find({
		V2(-math.sign(hero.x) * (hw + 9), hd * 0.25),
		V2(math.sign(hero.x) * (hw + 9), -hd * 0.1),
		V2(-math.sign(hero.x) * hw * 0.5, hd + 9),
	}, 8)
	if yard then
		local frame = Geo.facing(yard, Vector3.new(center.X, yard.Y, center.Z))
		transformer(parent, (frame * CFrame.new(-2.8, 0, 0)).Position, math.deg(slot.angle))
		transformer(parent, (frame * CFrame.new(3.2, 0, 0.6)).Position, math.deg(slot.angle) + 8)
		Pieces.lamp(parent, (frame * CFrame.new(0.2, 0, -3.8)).Position, 7, L.warm, 18, true)
		Pieces.barrel(parent, (frame * CFrame.new(6.6, 0, -2)).Position, C.copper)
		Pieces.barrel(parent, (frame * CFrame.new(7.4, 0, 0.6)).Position, C.patina)
	end

	-- a pipe run on brackets along the back edge
	local a = place.ground(-math.sign(hero.x) * hw * 0.85, hd + 5, 1.5)
	local b = place.ground(math.sign(hero.x) * hw * 0.05, hd + 5, 1.5)
	if a and b and math.abs(a.Y - b.Y) < 0.5 then
		Pieces.pipe(parent, a + UP * 1.8, b + UP * 1.8, 1.6, C.copper)
		Pieces.pipe(parent, a + UP * 3.4, b + UP * 3.4, 1.1, C.patina)
		local n = math.max(1, math.floor((b - a).Magnitude / 16))
		for i = 0, n do
			local p = a:Lerp(b, i / n)
			Pieces.block(parent, CFrame.new(p + UP * 1.9), Vector3.new(0.6, 3.8, 0.6), C.iron)
		end
	end

	-- vignette: cable spools and crates by a lamp
	local spools = place.find({
		V2(math.sign(hero.x) * (hw + 9), hd * 0.55),
		V2(-math.sign(hero.x) * (hw + 10), -hd * 0.35),
		V2(math.sign(hero.x) * (hw + 10), -hd * 0.4),
	}, 6)
	if spools then
		for k = 0, 1 do
			local p = spools + Vector3.new(k * 3.4, 1.4, k * 1.2)
			Pieces.pipe(
				parent,
				p - Vector3.new(0, 0, 0.9),
				p + Vector3.new(0, 0, 0.9),
				2.8,
				T.timberDark,
				M.wood
			)
		end
		Pieces.crate(
			parent,
			spools + Vector3.new(-3, 0, 1.5),
			2.2,
			rng:NextNumber(0, 45),
			nil,
			true
		)
		Pieces.crate(parent, spools + Vector3.new(-3.2, 2.2, 1.6), 1.6, rng:NextNumber(0, 45))
		Pieces.tuft(parent, spools + Vector3.new(1, 0, -2.6), rng, C.sage)
	end
end

return Default
