--!strict
-- Beach theme ("Tidewire Beach"): a sand field with scalloped patina tide
-- bands; a coast with bays and sand spits, pulled in close on the hub side
-- and wide at the back; basalt headlands that break the coastline out to
-- sea; the Tidewire Lighthouse; and a few composed vignettes (bathing huts,
-- the pier and skiff, a driftwood beach, palm groves) with open sand
-- between them. Works for any slot: everything is placed in the slot frame.

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

local Beach = {}

Beach.bridge = {
	deck = C.timber,
	deckMaterial = M.planks,
	rail = C.brass,
	pile = C.copper,
	stack = TERRAIN.Basalt,
} :: Zone.BridgeStyle

-- Coast margins outside the footprint: tight on the hub side, wide behind.
local FRONT, SIDE, BACK = 9, 14, 34

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

local layersByZone: { [string]: { Land.Layer } } = {}
local heroByZone: { [string]: Spot } = {}

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
	local layers: { Land.Layer } = {}
	-- the coast's rectangle: shifted back so the hub side stays close
	local coastFrame = slot.frame * CFrame.new(0, 0, (BACK - FRONT) / 2)
	local coastW, coastD = w + 2 * SIDE, d + FRONT + BACK

	Land.fill(
		ctx,
		Land.organic(coastFrame, coastW + 30, coastD + 30, rng, {
			edge = 16,
			jitter = 10,
			bays = 2,
			calmFront = true,
		}),
		SEA_FLOOR,
		-3,
		TERRAIN.Sand,
		0,
		guard
	)
	local beachTop = math.min(F - 2, 2)
	local beach = Land.organic(coastFrame, coastW, coastD, rng, {
		edge = 12,
		jitter = 6,
		bays = 2,
		bayDepth = 12,
		spits = 2,
		spitLength = 26,
		calmFront = true,
	})
	Land.fill(ctx, beach, SEA_FLOOR, beachTop, TERRAIN.Sand, 0, guard)
	local raised: Land.Outline? = nil
	if F > 8 then
		-- a raised beach: sandstone cliffs under it
		raised = Land.cliff(
			ctx,
			Land.organic(slot.frame, w + 16, d + 16, rng, { edge = 9, jitter = 5, bays = 1 }),
			SEA_FLOOR,
			F - 2,
			TERRAIN.Sandstone,
			{ TERRAIN.Limestone, TERRAIN.Rock },
			TERRAIN.Sand,
			rng,
			{ guard = guard, lean = 8, foot = 0 }
		)
	end
	local field = Land.organic(slot.frame, w + 10, d + 10, rng, { edge = 5, jitter = 2 })
	Land.fill(ctx, field, SEA_FLOOR, F, TERRAIN.Sand, 0, guard)
	Land.flatRect(ctx, slot.frame, w + 6, d + 6, F, F - SEA_FLOOR, TERRAIN.Sand)

	-- basalt headlands breaking the coast; the first clear big one is the
	-- lighthouse's
	local lighthouseSpots, minorSpots = headlandSpots(zone)
	local spots: { Spot } = {}
	for _, spot in lighthouseSpots do
		local p = Geo.slotPoint(zone, spot.x, spot.z)
		if Geo.isClear(ctx, p, spot.r * 0.9) then
			table.insert(spots, spot)
			heroByZone[key] = spot
			break
		end
	end
	for _, spot in minorSpots do
		table.insert(spots, spot)
	end
	for _, spot in spots do
		local center = Geo.slotPoint(zone, spot.x, spot.z)
		if Geo.isClear(ctx, center, spot.r * 0.7) then
			local top = math.max(F, 2) + spot.h
			Land.fill(
				ctx,
				Land.blob(center, spot.r + 8, rng, 6, 3),
				SEA_FLOOR,
				beachTop - 1,
				TERRAIN.Sand,
				0,
				guard
			)
			local outline = Land.cliff(
				ctx,
				Land.blob(center, spot.r, rng, 7, 2),
				SEA_FLOOR,
				top,
				TERRAIN.Basalt,
				{ TERRAIN.Slate, TERRAIN.Rock },
				if spot == heroByZone[key] then TERRAIN.LeafyGrass else TERRAIN.Rock,
				rng,
				{ guard = guard, lean = 6, foot = -2 }
			)
			Land.talus(ctx, outline, -1, rng, 4, TERRAIN.Basalt, guard)
			table.insert(layers, { outline = outline, top = top })
		end
	end
	-- grassy dunes in clumps on the wide back beach
	for _ = 1, 7 do
		local at = Geo.slotPoint(
			zone,
			rng:NextNumber(-0.5, 0.5) * (w + SIDE),
			d / 2 + rng:NextNumber(8, BACK - 6)
		)
		local r = rng:NextNumber(5, 8)
		local top = beachTop + 1.5
		if Geo.isClear(ctx, at, r) and guard(at.X, at.Z, r, top) then
			ctx.terrain:FillBall(Vector3.new(at.X, top - r, at.Z), r, TERRAIN.LeafyGrass)
		end
	end
	table.insert(layers, { outline = field, top = F })
	if raised then
		table.insert(layers, { outline = raised, top = F - 2 })
	end
	table.insert(layers, { outline = beach, top = beachTop })
	layersByZone[key] = layers

	-- the field: warm sand with scalloped patina tide bands, framed in
	-- brass with a glowing zone-colour strip
	Zone.waveStripes(zone, 5, C.patina, TERRAIN.Sand, 5)
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
		Pieces.block(
			parent,
			f * CFrame.new(0, wy, r),
			Vector3.new(1.4, 2.2, 0.5),
			L.warm,
			M.neon
		)
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
	Pieces.block(parent, frame * CFrame.new(0, 0.4, 0), Vector3.new(5, 0.8, 5.4), C.timber, M.planks, true)
	Pieces.block(parent, frame * CFrame.new(0, 3.1, 0), Vector3.new(4, 4.6, 4.4), C.ceramic, M.planks, true)
	for _, x in { -1.1, 1.1 } do
		Pieces.block(parent, frame * CFrame.new(x, 3.1, 0), Vector3.new(0.8, 4.62, 4.42), stripe, M.planks)
	end
	Pieces.gable(parent, frame * CFrame.new(0, 5.4, 0), 3.4, 3.8, 1.8, C.copper, M.metal)
	Pieces.block(parent, frame * CFrame.new(0, 2.4, -2.25), Vector3.new(1.6, 3.2, 0.2), T.copperDark, M.wood)
	Pieces.ball(parent, (frame * CFrame.new(0, 7.6, 0)).Position, 0.7, C.brass)
end

local function buoy(parent: Instance, at: Vector3, color: Color3)
	Pieces.ball(parent, at, 2.6, color)
	Pieces.column(parent, at + UP * 0.8, 1.6, 0.4, C.iron)
	Pieces.ball(parent, at + UP * 2.6, 0.9, C.volt, M.neon)
end

function Beach.dress(ctx: Context, zone: ZoneContext)
	local slot = zone.slot
	local F = slot.floor
	local hw, hd = slot.width / 2, slot.depth / 2
	local parent = zone.folder
	local key = Geo.zoneKey(zone)
	local rng = Geo.rng(ctx, key .. "-dress")
	local layers = Beach.layers(zone)
	local center = slot.frame.Position

	-- ground height at a slot-frame spot, if it is dry, settled land clear
	-- of fields and decks
	local function ground(x: number, z: number, clearance: number): Vector3?
		local p = Geo.slotPoint(zone, x, z)
		local top = Land.surfaceAt(layers, p, clearance)
		if top and top > 0.5 and Geo.isClear(ctx, p, clearance) then
			return Vector3.new(p.X, top, p.Z)
		end
		return nil
	end
	local function isWater(p: Vector3): boolean
		return Land.surfaceAt(layers, p, -3) == nil and Land.surfaceAt(layers, p, 0) == nil
	end

	-- hero: the lighthouse on its headland, wired to the field corner
	local hero = heroByZone[key]
	if hero then
		local p = Geo.slotPoint(zone, hero.x, hero.z)
		local lantern =
			lighthouse(parent, Vector3.new(p.X, math.max(F, 2) + hero.h, p.Z), center)
		local corner = Geo.slotPoint(
			zone,
			math.sign(hero.x) * hw,
			hd,
			Zone.POST_HEIGHT - 1.35
		)
		Pieces.liveCable(ctx, lantern + UP * 1, corner, zone.color, 0.4, 6)
	end

	-- vignette: bathing huts with a lamp, crates and dune grass, on the
	-- side away from the next zone
	local hutX = hw + SIDE * 0.55
	for i, z in { -hd * 0.2, hd * 0.05 } do
		local p = ground(hutX, z, 3)
		if p then
			local frame = Geo.facing(p, Geo.slotPoint(zone, 0, z, p.Y - F))
				* CFrame.Angles(0, math.rad(rng:NextNumber(-8, 8)), 0)
			bathingHut(parent, frame, if i == 1 then C.patina else T.copperDark)
			if i == 1 then
				local lampAt = frame * CFrame.new(3.8, 0, -1.5)
				Pieces.lamp(parent, lampAt.Position, 7, L.warm, 18, true)
				Pieces.crate(parent, (frame * CFrame.new(-3.6, 0, -1)).Position, 2, 15, nil, true)
				Pieces.tuft(parent, (frame * CFrame.new(-3, 0, 2.5)).Position, rng, C.sage)
			else
				Pieces.barrel(parent, (frame * CFrame.new(3.4, 0, 0.5)).Position, C.patina)
				Pieces.tuft(parent, (frame * CFrame.new(2.6, 0, -2.6)).Position, rng, T.sageDark)
			end
		end
	end

	-- vignette: the pier out from the back beach with a moored skiff; it
	-- starts at the water's edge wherever the coast happens to be
	do
		local x = -hw * 0.55
		local z0 = hd + 6
		local startZ: number? = nil
		for k = 0, 30 do
			local z = z0 + k * 2
			if isWater(Geo.slotPoint(zone, x, z)) then
				startZ = z - 6
				break
			end
		end
		if startZ then
			local a = Geo.slotPoint(zone, x, startZ :: number)
			local b = Geo.slotPoint(zone, x, (startZ :: number) + 26)
			if Geo.isClear(ctx, b, 6) and isWater(b) then
				Pieces.pier(parent, Vector3.new(a.X, 0, a.Z), Vector3.new(b.X, 0, b.Z), 2.6, "PIER", SEA_FLOOR)
				local along = (b - a).Unit
				local side = along:Cross(UP)
				local berth = Vector3.new(b.X, 0.1, b.Z) - along * 9 + side * 6.5
				if isWater(berth) then
					Pieces.skiff(parent, CFrame.lookAt(berth, berth + along))
				end
			end
		end
	end

	-- vignette: a driftwood beach with a stranded buoy and rocks
	do
		local p = ground(hw * 0.35, hd + BACK * 0.55, 2)
		if p then
			for k = 0, 1 do
				local yaw = rng:NextNumber(0, math.pi)
				local half = Vector3.new(math.cos(yaw), 0, math.sin(yaw)) * rng:NextNumber(2.5, 3.5)
				local at = p + Vector3.new(k * 2.4, 0, k * 1.6)
				Pieces.pipe(parent, at - half + UP * 0.4, at + half + UP * 0.6, 1.1 - k * 0.3, T.timberPale, M.wood)
			end
			Pieces.rocks(parent, p + Vector3.new(-3, 0, 2), 2.4, rng, T.rockDark)
			buoy(parent, p + Vector3.new(3.5, 1, -2.5), C.copper)
			Pieces.tuft(parent, p + Vector3.new(-1, 0, -3), rng, C.sage)
		end
	end

	-- buoys bobbing offshore (only on open water)
	local placed = 0
	for _ = 1, 12 do
		if placed >= 3 then
			break
		end
		local x = rng:NextNumber(-0.6, 0.6) * slot.width
		local z = hd + BACK + rng:NextNumber(12, 26)
		local p = Geo.slotPoint(zone, x, z)
		p = Vector3.new(p.X, 0.4, p.Z)
		if isWater(p) and Geo.isClear(ctx, p, 3) then
			placed += 1
			buoy(parent, p, if placed % 2 == 0 then C.copper else C.patina)
		end
	end

	-- palm groves leaning out to sea: two clumps on the back beach
	for _, g in { { x = hw * 0.7, z = hd + 12 }, { x = -hw * 0.15, z = hd + 15 } } do
		for k = 0, 1 do
			local p = ground(g.x + k * 5, g.z + k * 3.5, 3)
			if p then
				local out = Vector3.new(p.X - center.X, 0, p.Z - center.Z).Unit
				Pieces.palm(parent, p, out, rng)
				if k == 0 then
					Pieces.tuft(parent, p + out * 2.5, rng, C.sage)
				end
			end
		end
	end
end

return Beach
