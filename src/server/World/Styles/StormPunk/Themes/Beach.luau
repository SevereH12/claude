--!strict
-- Beach theme ("Tidewire Beach"): a sand field with scalloped patina tide
-- bands on a block island (limestone and sandstone steps down to a sand
-- apron, beach lobes wide at the back and pulled in on the hub side, shore
-- slopes into the sea); basalt headlands and column clusters that break the
-- coastline out to sea; grassy dunes; the Tidewire Lighthouse; and a few
-- composed vignettes (bathing huts, the pier and skiff, a driftwood beach,
-- palm groves) with open sand between them. Works for any slot: everything
-- is placed in the slot frame.

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
local SEA_FLOOR = Geo.SEA_FLOOR
local BEACH = Geo.BEACH
local BOTTOM = SEA_FLOOR - 0.5
local UP = Vector3.new(0, 1, 0)

local Beach = {}

Beach.bridge = {
	deck = C.timber,
	deckMaterial = M.planks,
	rail = C.brass,
	pile = C.copper,
	stack = G.basalt,
} :: Zone.BridgeStyle

-- Coast margins outside the footprint: wide behind, narrower at the sides
-- (the hub side has no beach: the field's steps meet open water).
local SIDE, BACK = 14, 34

type Spot = { x: number, z: number, r: number, h: number }

-- Headlands in slot-frame offsets from the footprint's back corners and
-- sides (x across, z outward); they sit out past the beach edge so they
-- break the coastline. The first clear "lighthouse" spot carries the hero.
local function headlandSpots(zone: ZoneContext): ({ Spot }, { Spot })
	local hw, hd = zone.slot.width / 2, zone.slot.depth / 2
	local lighthouse = {
		{ x = hw + 10, z = hd + BACK - 4, r = 17, h = 12 },
		{ x = -hw - 10, z = hd + BACK - 4, r = 17, h = 12 },
		{ x = hw * 0.2, z = hd + BACK + 6, r = 17, h = 12 },
	}
	local minor = {
		{ x = -hw * 0.45, z = hd + BACK + 4, r = 11, h = 5 },
		{ x = hw + SIDE + 8, z = -hd * 0.1, r = 12, h = 7 },
		{ x = -hw - SIDE - 8, z = hd * 0.2, r = 10, h = 6 },
	}
	return lighthouse, minor
end

type Hero = { x: number, z: number, top: number }

local layersByZone: { [string]: { Land.Layer } } = {}
local blockedByZone: { [string]: { Land.Shape } } = {}
local heroByZone: { [string]: Hero } = {}

function Beach.layers(zone: ZoneContext): { Land.Layer }
	return layersByZone[Geo.zoneKey(zone)] or {}
end

function Beach.ground(ctx: Context, zone: ZoneContext)
	local slot = zone.slot
	local F = slot.floor
	local w, d = slot.width, slot.depth
	local key = Geo.zoneKey(zone)
	local rng = Geo.rng(ctx, key .. "-ground")
	local guard = Geo.guard(ctx, zone)
	local detail = Geo.zoneDetail(zone)
	local parent = ctx.folders.ground
	local yaw = Zone.yawOf(slot.frame)
	local island = Zone.island(ctx, zone, {
		field = G.sand,
		colors = { G.limestone, G.sandstone },
		side = SIDE,
		back = BACK,
	})
	local layers = island.layers
	local blocked: { Land.Shape } = {}

	-- basalt headlands breaking the coast: the first clear big spot is the
	-- lighthouse's (slate and basalt strata, grass cap), the minor ones are
	-- column clusters
	local lighthouseSpots, minorSpots = headlandSpots(zone)
	local base = math.max(F, BEACH)
	heroByZone[key] = nil
	for _, spot in lighthouseSpots do
		local p = Geo.slotPoint(zone, spot.x, spot.z)
		local top = base + spot.h
		local shape = if Geo.isClear(ctx, p, spot.r * 0.9)
			then Land.fit(
				Land.poly(p, spot.r * 0.7, 10, rng:NextNumber(0, math.pi)),
				top,
				guard,
				0.7
			)
			else nil
		if shape then
			local built = Land.stack(parent, shape, top, BOTTOM, {
				{ color = G.slate, height = 4, cap = G.grass },
				{ color = G.basalt, grow = 1.2 },
			})
			table.move(built, 1, #built, #layers + 1, layers)
			Land.register(ctx, Land.grown(shape, 1.2))
			heroByZone[key] = { x = spot.x, z = spot.z, top = top }
			break
		end
	end
	for i, spot in minorSpots do
		local center = Geo.slotPoint(zone, spot.x, spot.z)
		if i <= Geo.count(detail, 1, 3) and Geo.isClear(ctx, center, spot.r * 0.7) then
			local columns = Land.cluster(
				parent,
				rng,
				center,
				spot.r,
				BOTTOM,
				base + spot.h,
				{ G.basalt, G.slate },
				nil,
				3,
				guard
			)
			for _, shape in columns do
				Land.register(ctx, shape)
				table.insert(blocked, shape)
			end
		end
	end
	local saddle = Zone.saddle(ctx, zone, { G.basalt, G.slate }, G.grass)
	table.move(saddle, 1, #saddle, #blocked + 1, blocked)

	-- grassy dunes in clumps on the wide back beach
	local dunes = Geo.count(detail, 1, 4)
	for _ = 1, 8 do
		if dunes <= 0 then
			break
		end
		local at = Geo.slotPoint(
			zone,
			rng:NextNumber(-0.5, 0.5) * (w + SIDE),
			d / 2 + rng:NextNumber(10, BACK - 4)
		)
		local r = rng:NextNumber(4, 6)
		if
			Geo.isClear(ctx, at, r)
			and Land.surfaceAt(layers, at, r + 1) == BEACH
			and not Land.containsAny(blocked, at, -(r + 2))
			and Land.allows(Land.poly(at, r, 6, yaw), BEACH + 2, guard)
		then
			dunes -= 1
			table.insert(blocked, Zone.dune(parent, at, r, yaw + rng:NextNumber(0, math.pi)))
		end
	end
	layersByZone[key] = layers
	blockedByZone[key] = blocked

	-- the field: warm sand with scalloped patina tide bands, framed in
	-- brass with a glowing zone-colour strip
	Zone.waveStripes(zone, 5, C.patina, Enum.Material.SmoothPlastic, 5)
	Zone.floorFrame(zone, C.brass, 1.5)
end

-- The Tidewire Lighthouse, built in a frame facing the field: banded
-- ceramic and copper tower, warm windows on the sea side, a gallery, a
-- glass lantern with a cyan core inside a copper coil ring, a patina dome
-- and a lightning rod (25 parts). Returns the lantern centre.
local function lighthouse(parent: Instance, base: Vector3, toward: Vector3): Vector3
	local f = Geo.facing(base, toward)
	Pieces.column(parent, base - UP * 2, 4.5, 12, T.rockDark, Enum.Material.Slate, true)
	local y = 2.5
	local diameter = 9
	for i = 1, 5 do
		Pieces.column(
			parent,
			base + UP * y,
			7,
			diameter,
			if i % 2 == 1 then C.ceramic else C.copper,
			if i % 2 == 1 then M.ceramic else M.metal,
			true
		)
		y += 7
		diameter -= 0.6
	end
	-- door facing the field, warm windows facing the sea
	Pieces.block(parent, f * CFrame.new(0, 4.5, -4.3), Vector3.new(2.4, 4, 0.8), C.soot, M.metal)
	for _, wy in { 13, 27 } do
		local r = 4.5 - (wy / 7) * 0.3
		Pieces.block(parent, f * CFrame.new(0, wy, r), Vector3.new(1.4, 2.2, 0.5), L.warm, M.neon)
	end
	-- gallery and parapet
	Pieces.column(parent, base + UP * y, 1, diameter + 3.6, C.iron)
	Pieces.column(parent, base + UP * (y + 1), 1.2, diameter + 3.2, C.brass)
	-- lantern room
	local lanternY = y + 1
	local glass = Pieces.column(parent, base + UP * lanternY, 5.5, diameter - 1, T.glass, M.glass)
	glass.Transparency = 0.4
	Pieces.orb(parent, base + UP * (lanternY + 2.8), 3.4, C.volt, 46, true)
	Pieces.torus(parent, base + UP * (lanternY + 2.8), diameter / 2 + 0.4, 1.5, 8, C.copper)
	-- roof
	Pieces.column(parent, base + UP * (lanternY + 5.5), 1, diameter + 1, C.copper)
	Pieces.ball(parent, base + UP * (lanternY + 6.5), diameter - 1.5, C.patina)
	Pieces.column(parent, base + UP * (lanternY + 8), 7, 0.6, C.copper)
	Pieces.ball(parent, base + UP * (lanternY + 15.2), 1.2, C.volt, M.neon)
	return base + UP * (lanternY + 2.8)
end

-- Striped bathing hut (8 parts): plinth, ceramic body with two stripes,
-- gable roof, door and a finial.
local function bathingHut(parent: Instance, frame: CFrame, stripe: Color3)
	Pieces.block(
		parent,
		frame * CFrame.new(0, 0.4, 0),
		Vector3.new(5, 0.8, 5.4),
		C.timber,
		M.planks,
		true
	)
	Pieces.block(
		parent,
		frame * CFrame.new(0, 3.1, 0),
		Vector3.new(4, 4.6, 4.4),
		C.ceramic,
		M.planks,
		true
	)
	for _, x in { -1.1, 1.1 } do
		Pieces.block(
			parent,
			frame * CFrame.new(x, 3.1, 0),
			Vector3.new(0.8, 4.62, 4.42),
			stripe,
			M.planks
		)
	end
	Pieces.gable(parent, frame * CFrame.new(0, 5.4, 0), 3.4, 3.8, 1.8, C.copper, M.metal)
	Pieces.block(
		parent,
		frame * CFrame.new(0, 2.4, -2.25),
		Vector3.new(1.6, 3.2, 0.2),
		T.copperDark,
		M.wood
	)
	Pieces.ball(parent, (frame * CFrame.new(0, 7.6, 0)).Position, 0.7, C.brass)
end

local function buoy(parent: Instance, at: Vector3, color: Color3)
	Pieces.ball(parent, at, 2.6, color)
	Pieces.column(parent, at + UP * 0.8, 1.6, 0.4, C.iron)
	Pieces.ball(parent, at + UP * 2.6, 0.9, C.volt, M.neon)
end

function Beach.dress(ctx: Context, zone: ZoneContext)
	local slot = zone.slot
	local hw, hd = slot.width / 2, slot.depth / 2
	local parent = zone.folder
	local key = Geo.zoneKey(zone)
	local rng = Geo.rng(ctx, key .. "-dress")
	local layers = Beach.layers(zone)
	local center = slot.frame.Position
	local place = Zone.placer(ctx, zone, layers, blockedByZone[key])
	local V2 = Vector2.new

	local function isWater(p: Vector3): boolean
		return Land.isOpenWater(ctx, p, 3)
	end

	-- hero: the lighthouse on its headland, wired to the field corner
	local hero = heroByZone[key]
	if hero then
		local p = Geo.slotPoint(zone, hero.x, hero.z)
		local lantern = lighthouse(parent, Vector3.new(p.X, hero.top, p.Z), center)
		local corner = Geo.slotPoint(zone, math.sign(hero.x) * hw, hd, Zone.POST_HEIGHT - 1.35)
		Pieces.liveCable(ctx, lantern + UP * 1, corner, zone.color, 0.4, 6)
	end

	-- vignette: two bathing huts with a lamp, a crate, a barrel and dune
	-- grass, preferably on the side away from the next zone
	local huts = place.find({
		V2(hw + SIDE * 0.6, -hd * 0.1),
		V2(hw + SIDE * 0.6, hd * 0.3),
		V2(hw * 0.4, hd + 10),
		V2(-hw - SIDE * 0.6, hd * 0.2),
	}, 9)
	if huts then
		local face = Vector3.new(center.X, huts.Y, center.Z)
		local frame = Geo.facing(huts, face)
		local side = frame.RightVector
		for i, s in { -1, 1 } do
			local at = huts + side * (s * 3.4)
			local hut = Geo.facing(at, face) * CFrame.Angles(0, math.rad(rng:NextNumber(-8, 8)), 0)
			bathingHut(parent, hut, if i == 1 then C.patina else T.copperDark)
		end
		Pieces.lamp(parent, (frame * CFrame.new(0, 0, -4)).Position, 7, L.warm, 18, true)
		Pieces.crate(parent, (frame * CFrame.new(-7.6, 0, -1)).Position, 2, 15, nil, true)
		Pieces.barrel(parent, (frame * CFrame.new(7.4, 0, 0.5)).Position, C.patina)
		Pieces.tuft(parent, (frame * CFrame.new(-7, 0, 2.6)).Position, rng, C.sage)
		Pieces.tuft(parent, (frame * CFrame.new(6.6, 0, -2.4)).Position, rng, T.sageDark)
	end

	-- vignette: the pier out from the back beach with a moored skiff; it
	-- starts at the water's edge wherever the coast happens to be
	for _, x in { -hw * 0.55, hw * 0.1, -hw * 0.9 } do
		local startZ: number? = nil
		for k = 0, 30 do
			local z = hd + 6 + k * 2
			if isWater(Geo.slotPoint(zone, x, z)) then
				startZ = z - 6
				break
			end
		end
		if startZ then
			local a = Geo.slotPoint(zone, x, startZ :: number)
			local b = Geo.slotPoint(zone, x, (startZ :: number) + 26)
			if Geo.isClear(ctx, b, 6) and isWater(b) then
				Pieces.pier(
					parent,
					Vector3.new(a.X, 0, a.Z),
					Vector3.new(b.X, 0, b.Z),
					BEACH + 0.8,
					"PIER",
					SEA_FLOOR
				)
				local along = (b - a).Unit
				local berth = Vector3.new(b.X, 0.1, b.Z) - along * 9 + along:Cross(UP) * 6.5
				if isWater(berth) then
					Pieces.skiff(parent, CFrame.lookAt(berth, berth + along))
				end
				break
			end
		end
	end

	-- vignette: a driftwood beach with a stranded buoy and rocks
	local drift = place.find({
		V2(hw * 0.3, hd + BACK * 0.55),
		V2(-hw * 0.2, hd + BACK * 0.5),
		V2(-hw - SIDE * 0.5, hd * 0.6),
	}, 6, nil, 3)
	if drift then
		for k = 0, 1 do
			local yaw = rng:NextNumber(0, math.pi)
			local half = Vector3.new(math.cos(yaw), 0, math.sin(yaw)) * rng:NextNumber(2.5, 3.5)
			local at = drift + Vector3.new(k * 2.4, 0, k * 1.6)
			Pieces.pipe(
				parent,
				at - half + UP * 0.4,
				at + half + UP * 0.6,
				1.1 - k * 0.3,
				T.timberPale,
				M.wood
			)
		end
		Pieces.rocks(parent, drift + Vector3.new(-3, 0, 2), 2.4, T.rockDark)
		buoy(parent, drift + Vector3.new(3.5, 1, -2.5), C.copper)
		Pieces.tuft(parent, drift + Vector3.new(-1, 0, -3), rng, C.sage)
	end

	-- buoys bobbing offshore (only on open water)
	local placed = 0
	for _ = 1, 14 do
		if placed >= 3 then
			break
		end
		local x = rng:NextNumber(-0.6, 0.6) * slot.width
		local z = hd + BACK + rng:NextNumber(10, 26)
		local p = Geo.slotPoint(zone, x, z)
		p = Vector3.new(p.X, 0.4, p.Z)
		if isWater(p) and Geo.isClear(ctx, p, 3) then
			placed += 1
			buoy(parent, p, if placed % 2 == 0 then C.copper else C.patina)
		end
	end

	-- palm groves leaning out to sea: two clumps on the back beach
	for _ = 1, 2 do
		local grove = place.find({
			V2(hw * 0.7, hd + 12),
			V2(-hw * 0.15, hd + 14),
			V2(-hw * 0.75, hd + 11),
			V2(hw + SIDE * 0.6, hd * 0.5),
			V2(-hw - SIDE * 0.6, -hd * 0.3),
		}, 6)
		if grove then
			local out = Vector3.new(grove.X - center.X, 0, grove.Z - center.Z).Unit
			local side = out:Cross(UP)
			Pieces.palm(parent, grove, out, rng)
			local second = grove + side * 4.5 + out * 2
			local top = Land.surfaceAt(layers, second, 1.5)
			if top and math.abs(top - grove.Y) < 1 and Geo.isClear(ctx, second, 2) then
				Pieces.palm(
					parent,
					Vector3.new(second.X, top, second.Z),
					(out + side * 0.4).Unit,
					rng
				)
			end
			Pieces.tuft(parent, grove - side * 2.5, rng, C.sage)
		end
	end
end

return Beach
