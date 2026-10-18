--!strict
-- Default theme ("Generator Yard"), used for any zone theme StormPunk has
-- no module for. A block island: a concrete yard on stepped slate and
-- basalt strata with a wide grassy shelf, a basalt column crag behind the
-- field, a plate checker tinted with the zone's colour, the Dynamo Stack on
-- its own concrete pad (smokestack, generator drums and an orb; its height,
-- drum count and side vary per zone), a transformer yard, pipe runs and
-- cable spools. Works for any slot and floor height.

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
local G = Palette.ground
local BOTTOM = Geo.SEA_FLOOR - 0.5
local UP = Vector3.new(0, 1, 0)

local Default = {}

Default.bridge = Zone.defaultBridge

type Hero = { x: number, z: number, height: number, drums: number }

local layersByZone: { [string]: { Land.Layer } } = {}
local blockedByZone: { [string]: { Land.Shape } } = {}
local heroByZone: { [string]: Hero } = {}
local padByZone: { [string]: boolean } = {}

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
	local hw, hd = slot.width / 2, slot.depth / 2
	local key = Geo.zoneKey(zone)
	local rng = Geo.rng(ctx, key .. "-ground")
	local guard = Geo.guard(ctx, zone)
	local detail = Geo.zoneDetail(zone)
	local parent = ctx.folders.ground

	-- a concrete yard on slate and basalt strata, the second one a wide
	-- grassy shelf
	local island = Zone.island(ctx, zone, {
		field = G.concrete,
		colors = { G.slate, G.basalt },
		grow = 2.5,
		capBand = 2,
		capGrow = 6,
	})
	local layers = island.layers

	-- a basalt column crag behind the field (away from the hero), 10-18
	-- above it
	local hero = heroFor(zone)
	heroByZone[key] = hero
	local sign = math.sign(hero.x)
	local blocked = Land.ridge(
		parent,
		Geo.slotPoint(zone, -sign * hw * 0.9, hd + 20),
		Geo.slotPoint(zone, -sign * hw * 0.1, hd + 24),
		F + 10,
		F + 18,
		16,
		rng,
		{ G.basalt, G.slate },
		G.grass,
		guard,
		Geo.count(detail, 2, 3),
		BOTTOM
	)
	local saddle = Zone.saddle(ctx, zone, { G.slate, G.basalt }, G.grass)
	table.move(saddle, 1, #saddle, #blocked + 1, blocked)

	-- the Dynamo Stack's pad behind the field, flush with the yard (same
	-- colour key, so where they meet they are one surface)
	padByZone[key] = false
	local base = Geo.slotPoint(zone, hero.x, hero.z)
	local pad = if Geo.isClear(ctx, base, 10)
		then Land.fit(
			Land.poly(base, 14.5, Geo.sides(detail, 10, 12), Zone.yawOf(slot.frame)),
			F,
			guard,
			0.8
		)
		else nil
	if pad then
		padByZone[key] = true
		local bands: { Land.Band } = { { color = G.concrete, height = 1.5 } }
		if detail > 0 then
			table.insert(bands, { color = G.slate, height = 4, grow = 0.5 })
		end
		table.insert(bands, { color = G.basalt, grow = 1 })
		local built = Land.stack(parent, pad, F, BOTTOM, bands, island.key)
		table.move(built, 1, #built, #layers + 1, layers)
	end
	layersByZone[key] = layers
	blockedByZone[key] = blocked

	-- the field: plates tinted with the zone colour on concrete, framed in
	-- brass with a glowing zone-colour strip
	Zone.checker(zone, 16, T.ironLight:Lerp(zone.color, 0.35), Enum.Material.SmoothPlastic, 1.2)
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
	if padByZone[key] then
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

	-- a pipe run on brackets along the grassy shelf behind the field
	local a = place.ground(-math.sign(hero.x) * hw * 0.85, hd + 9, 1.5)
	local b = place.ground(math.sign(hero.x) * hw * 0.05, hd + 9, 1.5)
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
