--!strict
-- Canyon theme ("Thunderhead Mesa"): a raised plateau with stepped terraces
-- of striped sandstone and limestone, hoodoos, a natural arch, and the
-- Thunder Spire (a rock pinnacle crowned with a brass lightning rod). Field:
-- sage and cream checkerboard. Works for any slot and any floor height.

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

local STRATA = { TERRAIN.Limestone, TERRAIN.Rock, TERRAIN.Limestone, TERRAIN.Ground }
local SPIRE = { u = -0.22, v = 0.5, out = 30, r = 12 }
local ARCH = { u = 0.5, v = 0.12, out = 22, span = 26 }

local Canyon = {}

Canyon.bridge = {
	deck = C.iron,
	deckMaterial = M.plate,
	rail = C.brass,
	pile = T.copperDark,
} :: Zone.BridgeStyle

local function spireBase(zone: ZoneContext): Vector3
	return Geo.edgePoint(zone, SPIRE.u, SPIRE.v, SPIRE.out, 0)
end

-- Terrain layers per zone (highest first), kept from ground() for dress().
local layersByZone: { [string]: { Land.Layer } } = {}

function Canyon.layers(zone: ZoneContext): { Land.Layer }
	return layersByZone[Geo.zoneKey(zone)] or {}
end

function Canyon.ground(ctx: Context, zone: ZoneContext)
	local slot = zone.slot
	local F = slot.floor
	local w, d = slot.width, slot.depth
	local rng = Geo.rng(ctx, Geo.zoneKey(zone) .. "-ground")
	local layers: { Land.Layer } = {}

	-- up to three terraces stepping up toward the plateau: 6-stud steps for
	-- low mesas, taller cliffs (multiples of 4) for high ones
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
	local ledge = if #steps >= 3 then 20 else 24
	local outer = 12 + #steps * ledge
	Land.fill(
		ctx,
		Land.rectOutline(slot.frame, w + outer + 34, d + outer + 34, rng, 16, 10, 3),
		SEA_FLOOR,
		-3,
		TERRAIN.Sand
	)
	local beach = Land.rectOutline(slot.frame, w + outer + 20, d + outer + 20, rng, 15, 10, 5)
	Land.fill(ctx, beach, SEA_FLOOR, 2, TERRAIN.Sand)
	for i, top in steps do
		local grow = 12 + (#steps - i + 1) * ledge
		-- shift each terrace a little so ledges are wide on one side and
		-- the cliffs drop straight down on another
		local shift =
			CFrame.new(rng:NextNumber(-1, 1) * grow * 0.16, 0, rng:NextNumber(-1, 1) * grow * 0.16)
		local outline = Land.clip(
			Land.rectOutline(slot.frame * shift, w + grow, d + grow, rng, 9 + i, 8, 3),
			Geo.landSafe(ctx, top, zone)
		)
		Land.cliff(
			ctx,
			outline,
			SEA_FLOOR,
			top,
			TERRAIN.Sandstone,
			STRATA,
			if i == 1 then TERRAIN.LeafyGrass else TERRAIN.Sandstone
		)
		table.insert(layers, 1, { outline = outline, top = top })
	end
	-- the plateau itself
	local plateau = Land.clip(
		Land.rectOutline(slot.frame, w + 12, d + 12, rng, 6, 3),
		Geo.landSafe(ctx, F, zone)
	)
	Land.cliff(ctx, plateau, SEA_FLOOR, F, TERRAIN.Sandstone, STRATA, TERRAIN.Limestone)
	Land.flatRect(ctx, slot.frame, w + 4, d + 4, F, 8, TERRAIN.Limestone)
	table.insert(layers, 1, { outline = plateau, top = F })
	table.insert(layers, { outline = beach, top = 2 })
	layersByZone[Geo.zoneKey(zone)] = layers

	-- hoodoos around the base
	for _ = 1, 7 do
		local u = rng:NextNumber(-0.6, 0.6)
		local v = rng:NextNumber(-0.3, 0.6)
		local p = Geo.edgePoint(zone, u, v, rng:NextNumber(24, 40), 0)
		local r = rng:NextNumber(3.5, 6)
		if Geo.isClear(ctx, p, r + 2) then
			Land.pinnacle(
				ctx,
				Vector3.new(p.X, SEA_FLOOR, p.Z),
				F - SEA_FLOOR + rng:NextNumber(-8, 12),
				r,
				rng,
				{ TERRAIN.Sandstone, TERRAIN.Limestone, TERRAIN.Sandstone, TERRAIN.Rock },
				r * 0.7
			)
		end
	end

	-- the Thunder Spire (terrain part of the hero)
	local spire = spireBase(zone)
	if Geo.isClear(ctx, spire, SPIRE.r) then
		Land.fill(
			ctx,
			Land.roundOutline(spire, SPIRE.r + 10, rng, 6, 3),
			SEA_FLOOR,
			6,
			TERRAIN.Sandstone
		)
		Land.pinnacle(
			ctx,
			Vector3.new(spire.X, SEA_FLOOR, spire.Z),
			F - SEA_FLOOR + 30,
			SPIRE.r,
			rng,
			{
				TERRAIN.Sandstone,
				TERRAIN.Limestone,
				TERRAIN.Sandstone,
				TERRAIN.Rock,
				TERRAIN.Sandstone,
			},
			SPIRE.r * 0.55
		)
	end

	-- natural arch off one side
	local archMid = Geo.edgePoint(zone, ARCH.u, ARCH.v, ARCH.out, 0)
	local along = zone.slot.frame.LookVector
	local a = archMid - along * ARCH.span / 2
	local b = archMid + along * ARCH.span / 2
	if Geo.isClear(ctx, a, 6) and Geo.isClear(ctx, b, 6) then
		Land.arch(
			ctx,
			Vector3.new(a.X, 0, a.Z),
			Vector3.new(b.X, 0, b.Z),
			F + 4,
			6,
			rng,
			{ TERRAIN.Sandstone, TERRAIN.Limestone, TERRAIN.Sandstone }
		)
	end

	-- the field: sage and cream checkerboard with a brass frame
	Zone.checker(zone, 15, C.sage, TERRAIN.Grass)
	Zone.floorFrame(zone, C.brass, 1.2)
end

-- Brass lightning-rod rig on top of the spire. Returns the orb position.
local function spireRig(ctx: Context, parent: Instance, top: Vector3, color: Color3): Vector3
	Kit.cylinder(parent, top - UP * 0.6, 1.2, 9, { Color = C.brass, Material = M.metal })
	for i = 0, 3 do
		local d = Geo.dir(i * 90 + 45)
		Pieces.strut(parent, top + d * 3.8, top + UP * 12, 0.5, C.iron)
	end
	Pieces.insulator(parent, top + UP * 0.6, 1.3, 4)
	Pieces.column(parent, top + UP * 3.5, 16, 1, C.copper)
	Pieces.torus(parent, top + UP * 12, 3.4, 1.6, 10, C.copper)
	Pieces.torus(parent, top + UP * 15.5, 2.4, 1.2, 8, C.brass)
	local orb = Pieces.orb(parent, top + UP * 21, 4, C.volt, 50, true)
	local _ = orb
	Pieces.column(parent, top + UP * 23, 6, 0.4, C.copper)
	Pieces.ball(parent, top + UP * 29.2, 0.9, color, M.neon)
	local _ctx = ctx
	return top + UP * 21
end

local function cactusRod(parent: Instance, bottom: Vector3, rng: Random)
	local h = rng:NextNumber(4, 6.5)
	Pieces.column(parent, bottom - UP * 0.3, h, 1.1, C.copper, M.metal, true)
	Pieces.ball(parent, bottom + UP * (h + 0.1), 0.9, C.volt, M.neon)
	local yaw = rng:NextNumber(0, math.pi * 2)
	local dir = Vector3.new(math.cos(yaw), 0, math.sin(yaw))
	for _, s in { 1, -1 } do
		local armY = h * rng:NextNumber(0.35, 0.6)
		local elbow = bottom + UP * armY + dir * s * 1.6
		Pieces.strut(parent, bottom + UP * armY, elbow, 0.6, C.patina)
		Pieces.strut(parent, elbow, elbow + UP * rng:NextNumber(1.2, 2.2), 0.6, C.patina)
	end
end

local function headframe(ctx: Context, parent: Instance, frame: CFrame)
	-- timber A-frame over a mine shaft, with a sheave wheel
	for _, s in { -1, 1 } do
		Pieces.strut(
			parent,
			(frame * CFrame.new(s * 3, 0, -2)).Position,
			(frame * CFrame.new(s * 1, 12, 0)).Position,
			0.7,
			T.timberDark,
			M.wood
		)
		Pieces.strut(
			parent,
			(frame * CFrame.new(s * 3, 0, 3)).Position,
			(frame * CFrame.new(s * 1, 12, 0)).Position,
			0.7,
			T.timberDark,
			M.wood
		)
	end
	Pieces.strut(
		parent,
		(frame * CFrame.new(-1.6, 12, 0)).Position,
		(frame * CFrame.new(1.6, 12, 0)).Position,
		0.6,
		C.iron
	)
	local hub = (frame * CFrame.new(0, 12.4, 0)).Position
	Pieces.pipe(parent, hub - frame.RightVector * 0.3, hub + frame.RightVector * 0.3, 4.2, C.copper)
	Pieces.pipe(parent, hub - frame.RightVector * 0.4, hub + frame.RightVector * 0.4, 1.2, C.brass)
	Pieces.block(
		parent,
		frame * CFrame.new(0, 0.6, 0.5),
		Vector3.new(5, 1.2, 5),
		T.timberDark,
		M.planks,
		true
	)
	Kit.cable(
		ctx,
		hub - UP * 2,
		(frame * CFrame.new(0, 1.2, 0.5)).Position,
		{ Color = C.soot, Width = 0.2 }
	)
end

local function oreCart(parent: Instance, frame: CFrame)
	Pieces.block(
		parent,
		frame * CFrame.new(0, 1.6, 0),
		Vector3.new(2.6, 1.6, 3.6),
		T.copperDark,
		M.rusty,
		true
	)
	Pieces.block(
		parent,
		frame * CFrame.new(0, 2.5, 0),
		Vector3.new(2.2, 0.6, 3.2),
		C.hazard,
		Enum.Material.Rock
	)
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
	local _, _, tip = Pieces.pylon(parent, bottom, 16, yaw, 2.4)
	local cf = CFrame.new(tip - UP * 2.2) * CFrame.Angles(0, math.rad(yaw), 0)
	Pieces.block(parent, cf, Vector3.new(1.2, 1.2, 2.4), C.iron)
	local hub = (cf * CFrame.new(0, 0, -1.4)).Position
	Pieces.ball(parent, hub, 1.2, C.brass)
	local spin = rng:NextNumber(0, 60)
	for i = 0, 5 do
		local a = math.rad(spin + i * 60)
		local tipP = hub + (cf.RightVector * math.cos(a) + UP * math.sin(a)) * 3.6
		Pieces.strut(parent, hub, tipP, 0.4, if i % 2 == 0 then C.ceramic else C.copper)
	end
	Pieces.wedge(parent, cf * CFrame.new(0, 0.4, 3.2), Vector3.new(0.2, 1.8, 2.6), C.patina)
end

function Canyon.dress(ctx: Context, zone: ZoneContext)
	local slot = zone.slot
	local F = slot.floor
	local parent = zone.folder
	local rng = Geo.rng(ctx, Geo.zoneKey(zone) .. "-dress")

	-- hero: the Thunder Spire's lightning rod, wired to the mesa rim
	local spire = spireBase(zone)
	if Geo.isClear(ctx, spire, SPIRE.r) then
		local top = Vector3.new(spire.X, F + 30 - 0.5, spire.Z)
		local orb = spireRig(ctx, parent, top, zone.color)
		for _, u in { -0.5, 0.5 } do
			local corner = Geo.edgePoint(zone, u, 0.5, 0, Zone.POST_HEIGHT - 1.5)
			Pieces.liveCable(ctx, orb - UP * 9, corner, zone.color, 0.35, 5)
		end
	end

	local layers = Canyon.layers(zone)
	local function ground(p: Vector3, shrink: number): Vector3?
		local top = Land.surfaceAt(layers, p, shrink)
		return if top and top > 1 then Vector3.new(p.X, top, p.Z) else nil
	end

	-- mine headframe and an ore cart on the left side
	local hf = ground(Geo.edgePoint(zone, -0.5, 0.25, 7, 0), 4)
	if hf and Geo.isClear(ctx, hf, 4) then
		local frame = Geo.facing(hf, slot.frame.Position)
		headframe(ctx, parent, frame)
		local cart = ground((frame * CFrame.new(0, 0, 7)).Position, 2)
		if cart then
			oreCart(
				parent,
				Geo.facing(cart, slot.frame.Position) * CFrame.Angles(0, math.rad(80), 0)
			)
		end
	end

	-- windpump on a front corner
	local wp = ground(Geo.edgePoint(zone, 0.5, -0.5, 14, 0), 3)
	if wp and Geo.isClear(ctx, wp, 4) then
		windpump(parent, wp, math.deg(zone.slot.angle) + 90, rng)
	end

	-- lamps on the plateau rim
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

	-- copper "cactus" lightning rods on the terraces
	for _ = 1, Geo.count(zone, 12) do
		local p = ground(
			Geo.edgePoint(
				zone,
				rng:NextNumber(-0.55, 0.55),
				rng:NextNumber(-0.4, 0.55),
				rng:NextNumber(14, 30),
				0
			),
			2
		)
		if p and p.Y < F and Geo.isClear(ctx, p, 2) then
			cactusRod(parent, p, rng)
		end
	end

	-- pipes running down the cliff
	for _, u in { -0.3, 0.25 } do
		local rim = Geo.edgePoint(zone, u, 0.5, 3.5, 0.6)
		local out = Geo.edgePoint(zone, u, 0.5, 11, -5.4)
		local foot = Geo.edgePoint(zone, u, 0.5, 18, -5.4)
		if Geo.isClear(ctx, foot, 1.5) then
			Pieces.pipe(parent, rim, Vector3.new(out.X, rim.Y, out.Z), 1.2, C.copper)
			Pieces.pipe(parent, Vector3.new(out.X, rim.Y, out.Z), out, 1.2, C.copper)
			Pieces.pipe(parent, out, foot, 1.2, C.copper)
			Pieces.column(parent, Vector3.new(out.X, rim.Y - 0.8, out.Z), 1.6, 1.8, C.brass)
		end
	end

	-- small stuff: rocks, scrub, crates on the rim and terraces
	for _ = 1, Geo.count(zone, 48) do
		local u = rng:NextNumber(-0.56, 0.56)
		local v = rng:NextNumber(-0.5, 0.56)
		local p = ground(Geo.edgePoint(zone, u, v, rng:NextNumber(4.5, 34), 0), 1.5)
		if p and Geo.isClear(ctx, p, 1.2) then
			local roll = rng:NextNumber()
			if roll < 0.4 then
				Pieces.shrub(parent, p, rng, if rng:NextNumber() < 0.5 then C.sage else T.sageDark)
			elseif roll < 0.75 then
				Pieces.rocks(
					parent,
					p,
					rng:NextNumber(1.2, 3),
					rng,
					if rng:NextNumber() < 0.5 then T.rock else C.copper
				)
			elseif roll < 0.88 then
				Pieces.crate(parent, p, rng:NextNumber(1.6, 2.4), rng:NextNumber(0, 90))
			else
				Pieces.tuft(parent, p, rng, C.sage)
			end
		end
	end
end

return Canyon
