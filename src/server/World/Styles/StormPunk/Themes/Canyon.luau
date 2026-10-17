--!strict
-- Canyon theme ("Thunderhead Mesa"): a raised plateau over strongly
-- shifted terraces of striped sandstone and limestone (wide ledges on one
-- side, a sheer drop to the beach on the other), a rock ridge behind the
-- field, hoodoos, a natural arch, and the Thunder Spire (a rock pinnacle
-- crowned with a brass lightning rod). Field: deep sage and cream
-- checkerboard. Works for any slot and any floor height.

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
local L = Palette.light
local TERRAIN = Enum.Material
local SEA_FLOOR = Geo.SEA_FLOOR
local UP = Vector3.new(0, 1, 0)

local STRATA = { TERRAIN.Limestone, TERRAIN.Rock, TERRAIN.Ground }
local SPIRE_R = 12

local Canyon = {}

Canyon.bridge = {
	deck = C.iron,
	deckMaterial = M.plate,
	rail = C.brass,
	pile = T.copperDark,
	stack = TERRAIN.Sandstone,
} :: Zone.BridgeStyle

local layersByZone: { [string]: { Land.Layer } } = {}
local spireByZone: { [string]: Vector3 } = {}

function Canyon.layers(zone: ZoneContext): { Land.Layer }
	return layersByZone[Geo.zoneKey(zone)] or {}
end

-- Spire candidates behind the field (slot-frame x, z): first clear wins.
local function spireSpots(zone: ZoneContext): { Vector3 }
	local hw, hd = zone.slot.width / 2, zone.slot.depth / 2
	return {
		Vector3.new(-hw * 0.4, 0, hd + 30),
		Vector3.new(hw * 0.4, 0, hd + 30),
		Vector3.new(0, 0, hd + 36),
	}
end

function Canyon.ground(ctx: Context, zone: ZoneContext)
	local slot = zone.slot
	local F = slot.floor
	local w, d = slot.width, slot.depth
	local key = Geo.zoneKey(zone)
	local rng = Geo.rng(ctx, key .. "-ground")
	local guard = Geo.guard(ctx, zone)
	local layers: { Land.Layer } = {}

	-- up to three terraces stepping up toward the plateau: 6-stud steps
	-- for low mesas, taller cliffs (multiples of 4) for high ones
	local rise = 6
	if (F - 4) / 6 > 3 then
		rise = math.max(4, math.floor((F - 4) / 16 + 0.5) * 4)
	end
	local steps = {}
	local y = F - rise
	while y > 4 and #steps < 3 do
		table.insert(steps, 1, y)
		y -= rise
	end
	local ledge = if #steps >= 3 then 18 else 22
	local outer = 12 + #steps * ledge
	Land.fill(
		ctx,
		Land.organic(slot.frame, w + outer + 36, d + outer + 36, rng, { edge = 16, jitter = 10, bays = 2 }),
		SEA_FLOOR,
		-3,
		TERRAIN.Sand,
		0,
		guard
	)
	local beach = Land.organic(slot.frame, w + outer + 20, d + outer + 20, rng, {
		edge = 14,
		jitter = 8,
		bays = 2,
		bayDepth = 14,
		spits = 1,
		spitLength = 24,
	})
	Land.fill(ctx, beach, SEA_FLOOR, 2, TERRAIN.Sand, 0, guard)

	-- terraces shift well off-centre: wide ledges on one side; on the
	-- opposite side they are dropped so the plateau falls sheer to the sand
	local shiftDir = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(0.2, 1)).Unit
	local hw, hd = w / 2, d / 2
	for i, top in steps do
		local grow = 12 + (#steps - i + 1) * ledge
		local shift = CFrame.new(shiftDir * grow * 0.3)
		local frame = slot.frame * shift
		local outline = Land.clip(
			Land.organic(frame, w + grow, d + grow, rng, { edge = 8 + i, jitter = 7, bays = 1 }),
			function(c)
				-- the sheer side: nothing past the plateau edge opposite the shift
				local l = slot.frame:PointToObjectSpace(Vector3.new(c.x, F, c.z))
				local along = l.X * -shiftDir.X + l.Z * -shiftDir.Z
				local limit = math.abs(shiftDir.X) * hw + math.abs(shiftDir.Z) * hd
				return along < limit + 2
			end
		)
		local terrace = Land.cliff(
			ctx,
			outline,
			SEA_FLOOR,
			top,
			TERRAIN.Sandstone,
			STRATA,
			if i == 1 then TERRAIN.LeafyGrass else TERRAIN.Sandstone,
			rng,
			{ guard = guard, lean = 6, foot = 0 }
		)
		table.insert(layers, 1, { outline = terrace, top = top })
	end
	-- the plateau itself
	local plateau = Land.cliff(
		ctx,
		Land.organic(slot.frame, w + 12, d + 12, rng, { edge = 6, jitter = 3 }),
		SEA_FLOOR,
		F,
		TERRAIN.Sandstone,
		STRATA,
		TERRAIN.Limestone,
		rng,
		{ guard = guard, lean = 7, foot = 0 }
	)
	Land.flatRect(ctx, slot.frame, w + 4, d + 4, F, 8, TERRAIN.Limestone)
	Land.talus(ctx, plateau, 2, rng, 10, TERRAIN.Sandstone, guard)

	-- a broken ridge behind the field, standing 8-16 above it
	local ridgeA = Geo.slotPoint(zone, -hw * 0.95, hd + 18)
	local ridgeB = Geo.slotPoint(zone, hw * 0.1, hd + 22)
	Land.ridge(
		ctx,
		ridgeA,
		ridgeB,
		F + 8,
		F + 16,
		16,
		rng,
		TERRAIN.Sandstone,
		STRATA,
		TERRAIN.Sandstone,
		guard
	)

	-- hoodoos around the base
	for _ = 1, 5 do
		local p = Geo.slotPoint(
			zone,
			rng:NextNumber(-0.65, 0.65) * w,
			rng:NextNumber(0.1, 0.5) * d + rng:NextNumber(30, 44)
		)
		local r = rng:NextNumber(3.5, 6)
		if Geo.isClear(ctx, p, r + 2) then
			Land.pinnacle(
				ctx,
				Vector3.new(p.X, SEA_FLOOR, p.Z),
				F - SEA_FLOOR + rng:NextNumber(-10, 8),
				r,
				rng,
				{ TERRAIN.Sandstone, TERRAIN.Limestone, TERRAIN.Sandstone, TERRAIN.Rock },
				r * 0.7,
				nil,
				guard
			)
		end
	end

	-- the Thunder Spire (terrain part of the hero), on the first clear spot
	for _, s in spireSpots(zone) do
		local spire = Geo.slotPoint(zone, s.X, s.Z)
		if Geo.isClear(ctx, spire, SPIRE_R) then
			spireByZone[key] = spire
			Land.fill(
				ctx,
				Land.blob(spire, SPIRE_R + 10, rng, 6, 3),
				SEA_FLOOR,
				6,
				TERRAIN.Sandstone,
				0,
				guard
			)
			Land.pinnacle(
				ctx,
				Vector3.new(spire.X, SEA_FLOOR, spire.Z),
				F - SEA_FLOOR + 30,
				SPIRE_R,
				rng,
				{
					TERRAIN.Sandstone,
					TERRAIN.Limestone,
					TERRAIN.Sandstone,
					TERRAIN.Rock,
					TERRAIN.Sandstone,
				},
				SPIRE_R * 0.55,
				nil,
				guard
			)
			break
		end
	end

	-- natural arch off whichever side is clear, feet on the sea bed
	for _, side in { 1, -1 } do
		local mid = Geo.slotPoint(zone, side * (hw + outer * 0.5 + 6), hd * 0.1)
		local along = slot.frame.LookVector
		local a = mid - along * 13
		local b = mid + along * 13
		if Geo.isClear(ctx, a, 6) and Geo.isClear(ctx, b, 6) then
			Land.arch(
				ctx,
				Vector3.new(a.X, SEA_FLOOR, a.Z),
				Vector3.new(b.X, SEA_FLOOR, b.Z),
				F + 4 - SEA_FLOOR,
				6,
				rng,
				{ TERRAIN.Sandstone, TERRAIN.Limestone, TERRAIN.Sandstone },
				guard
			)
			break
		end
	end

	table.insert(layers, 1, { outline = plateau, top = F })
	table.insert(layers, { outline = beach, top = 2 })
	layersByZone[key] = layers

	-- the field: deep sage tiles on cream limestone, framed in brass with
	-- a glowing zone-colour strip
	Zone.checker(zone, 16, T.sageDark, TERRAIN.Grass)
	Zone.floorFrame(zone, C.brass, 1.5)
end

-- Brass lightning-rod rig on top of the spire, chunky enough to read from
-- the hub. Returns the orb position.
local function spireRig(parent: Instance, top: Vector3, color: Color3): Vector3
	Kit.cylinder(parent, top - UP * 0.6, 1.4, 10, { Color = C.brass, Material = M.metal })
	for i = 0, 3 do
		local d = Geo.dir(i * 90 + 45)
		Pieces.strut(parent, top + d * 4.2, top + UP * 13, 0.9, C.iron)
	end
	Pieces.insulator(parent, top + UP * 0.8, 1.5, 3)
	Pieces.column(parent, top + UP * 4, 16, 2, C.copper)
	Pieces.torus(parent, top + UP * 13, 3.8, 2.4, 8, C.copper)
	local orbAt = top + UP * 22
	Pieces.orb(parent, orbAt, 4.5, C.volt, 50, true)
	Pieces.column(parent, top + UP * 24, 6, 0.6, C.copper)
	Pieces.ball(parent, top + UP * 30.4, 1.2, color, M.neon)
	return orbAt
end

local function cactusRod(parent: Instance, bottom: Vector3, rng: Random)
	local h = rng:NextNumber(4.5, 7)
	Pieces.column(parent, bottom - UP * 0.3, h, 1.2, C.copper, M.metal, true)
	Pieces.ball(parent, bottom + UP * (h + 0.1), 1, C.volt, M.neon)
	local yaw = rng:NextNumber(0, math.pi * 2)
	local dir = Vector3.new(math.cos(yaw), 0, math.sin(yaw))
	local armY = h * rng:NextNumber(0.4, 0.6)
	local elbow = bottom + UP * armY + dir * 1.6
	Pieces.strut(parent, bottom + UP * armY, elbow + UP * 0.3, 0.6, C.patina)
	Pieces.strut(parent, elbow, elbow + UP * rng:NextNumber(1.4, 2.4), 0.6, C.patina)
end

local function headframe(ctx: Context, parent: Instance, frame: CFrame)
	-- timber A-frame over a mine shaft, with a sheave wheel
	for _, s in { -1, 1 } do
		Pieces.strut(
			parent,
			(frame * CFrame.new(s * 3, 0, -2)).Position,
			(frame * CFrame.new(s * 1, 12, 0)).Position,
			0.8,
			T.timberDark,
			M.wood
		)
		Pieces.strut(
			parent,
			(frame * CFrame.new(s * 3, 0, 3)).Position,
			(frame * CFrame.new(s * 1, 12, 0)).Position,
			0.8,
			T.timberDark,
			M.wood
		)
	end
	local hub = (frame * CFrame.new(0, 12.4, 0)).Position
	Pieces.pipe(parent, hub - frame.RightVector * 0.3, hub + frame.RightVector * 0.3, 4.4, C.copper)
	Pieces.block(parent, frame * CFrame.new(0, 0.6, 0.5), Vector3.new(5, 1.2, 5), T.timberDark, M.planks, true)
	Kit.cable(ctx, hub - UP * 2, (frame * CFrame.new(0, 1.2, 0.5)).Position, { Color = C.soot, Width = 0.2 })
end

local function oreCart(parent: Instance, frame: CFrame)
	Pieces.block(parent, frame * CFrame.new(0, 1.6, 0), Vector3.new(2.6, 1.6, 3.6), T.copperDark, M.rusty, true)
	Pieces.block(parent, frame * CFrame.new(0, 2.5, 0), Vector3.new(2.2, 0.6, 3.2), C.copper, Enum.Material.Rock)
	for _, z in { -1.1, 1.1 } do
		Pieces.pipe(
			parent,
			(frame * CFrame.new(-1.4, 0.7, z)).Position,
			(frame * CFrame.new(1.4, 0.7, z)).Position,
			1.2,
			C.iron
		)
	end
end

local function windpump(parent: Instance, bottom: Vector3, yaw: number, rng: Random)
	local _, _, tip = Pieces.pylon(parent, bottom, 16, yaw, 2.4, 0.6)
	local cf = CFrame.new(tip - UP * 2.4) * CFrame.Angles(0, math.rad(yaw), 0)
	local hub = (cf * CFrame.new(0, 0, -1.4)).Position
	Pieces.ball(parent, hub, 1.4, C.brass)
	local spin = rng:NextNumber(0, 60)
	for i = 0, 3 do
		local a = math.rad(spin + i * 90)
		local tipP = hub + (cf.RightVector * math.cos(a) + UP * math.sin(a)) * 3.8
		Pieces.strut(parent, hub, tipP, 0.5, if i % 2 == 0 then C.ceramic else C.copper)
	end
	Pieces.wedge(parent, cf * CFrame.new(0, 0.4, 3), Vector3.new(0.25, 2, 3), C.patina)
end

function Canyon.dress(ctx: Context, zone: ZoneContext)
	local slot = zone.slot
	local F = slot.floor
	local hw, hd = slot.width / 2, slot.depth / 2
	local parent = zone.folder
	local key = Geo.zoneKey(zone)
	local rng = Geo.rng(ctx, key .. "-dress")
	local center = slot.frame.Position
	local place = Zone.placer(ctx, zone, Canyon.layers(zone))
	local V2 = Vector2.new

	-- hero: the Thunder Spire's lightning rod, wired to the mesa rim
	local spire = spireByZone[key]
	if spire then
		local orb = spireRig(parent, Vector3.new(spire.X, F + 30 - 0.5, spire.Z), zone.color)
		for _, u in { -1, 1 } do
			local corner = Geo.slotPoint(zone, u * hw, hd, Zone.POST_HEIGHT - 1.35)
			Pieces.liveCable(ctx, orb - UP * 9, corner, zone.color, 0.4, 5)
		end
	end

	-- vignette: a mine headframe with an ore cart, crates and a lamp
	local mine = place.find({
		V2(hw + 10, hd * 0.3),
		V2(-hw - 10, hd * 0.3),
		V2(hw + 12, -hd * 0.2),
		V2(-hw - 12, -hd * 0.2),
		V2(hw * 0.6, hd + 10),
		V2(-hw * 0.6, hd + 10),
	}, 7)
	if mine then
		local frame = Geo.facing(mine, Vector3.new(center.X, mine.Y, center.Z))
		headframe(ctx, parent, frame)
		oreCart(parent, frame * CFrame.new(0, 0, 6.5) * CFrame.Angles(0, math.rad(80), 0))
		Pieces.crate(parent, (frame * CFrame.new(-4, 0, 5)).Position, 2, 25, nil, true)
		Pieces.lamp(parent, (frame * CFrame.new(3.6, 0, -2.5)).Position, 7, L.warm, 18, true)
	end

	-- vignette: a windpump over a trough
	local pump = place.find({
		V2(-hw - 9, hd * 0.75),
		V2(hw + 9, hd * 0.75),
		V2(-hw - 14, -hd * 0.4),
		V2(hw + 14, -hd * 0.4),
		V2(hw * 0.9, hd + 14),
	}, 6)
	if pump then
		windpump(parent, pump, math.deg(slot.angle) + 90, rng)
		Pieces.block(
			parent,
			Geo.facing(pump, center) * CFrame.new(0, 0.6, -3.2),
			Vector3.new(4, 1.2, 1.6),
			C.copper,
			M.metal,
			true
		)
	end

	-- vignettes: clusters of copper "cactus" lightning rods with scrub on
	-- the terraces below the field
	for _ = 1, 2 do
		local spot = place.find({
			V2(hw * 0.5, hd + 12),
			V2(-hw - 12, -hd * 0.2),
			V2(hw + 12, hd * 0.1),
			V2(-hw * 0.2, hd + 16),
			V2(hw + 18, hd * 0.6),
			V2(-hw - 18, hd * 0.6),
		}, 5, nil, F - 1)
		if spot then
			cactusRod(parent, spot, rng)
			cactusRod(parent, spot + Vector3.new(3, 0, 1.5), rng)
			Pieces.shrub(parent, spot + Vector3.new(-2, 0, 2.5), rng, C.sage)
		end
	end

	-- a pipe running down the cliff from the rim
	do
		local rim = place.ground(hw * -0.2, hd + 3.5, 1)
		if rim then
			local out = Geo.slotPoint(zone, hw * -0.2, hd + 9, -4.6)
			local foot = Geo.slotPoint(zone, hw * -0.2, hd + 14, -4.6)
			if Geo.isClear(ctx, foot, 1.5) then
				local level = Vector3.new(out.X, rim.Y + 0.6, out.Z)
				Pieces.pipe(parent, rim + UP * 0.6, level, 1.3, C.copper)
				Pieces.pipe(parent, level, out, 1.3, C.copper)
				Pieces.pipe(parent, out, foot, 1.3, C.copper)
				Pieces.column(parent, level - UP * 0.8, 1.6, 1.9, C.brass)
			end
		end
	end
end

return Canyon
