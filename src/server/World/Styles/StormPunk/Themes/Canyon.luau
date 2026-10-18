--!strict
-- Canyon theme ("Thunderhead Mesa"): a raised block plateau over shifted
-- terraces of striped sandstone and limestone (wide ledges on one side and
-- the back, a green ledge halfway, a sheer drop on the other side), a ridge
-- of rock columns behind the field, hoodoos, a natural arch, and the
-- Thunder Spire (a pinnacle of twisting hex tiers crowned with a brass
-- lightning rod). Field: deep sage and cream checkerboard. Works for any
-- slot and any floor height.

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
local G = Palette.ground
local SEA_FLOOR = Geo.SEA_FLOOR
local BOTTOM = SEA_FLOOR - 0.5
local UP = Vector3.new(0, 1, 0)

local STRATA = { G.sandstone, G.limestone }
local SPIRE_R = 12
-- the spire's top, above the field (the rig sits on it)
local SPIRE_TOP = 29.5

local Canyon = {}

Canyon.bridge = {
	deck = C.iron,
	deckMaterial = M.plate,
	rail = C.brass,
	pile = T.copperDark,
	stack = G.sandstone,
} :: Zone.BridgeStyle

local layersByZone: { [string]: { Land.Layer } } = {}
local blockedByZone: { [string]: { Land.Shape } } = {}
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
	local hw, hd = w / 2, d / 2
	local key = Geo.zoneKey(zone)
	local rng = Geo.rng(ctx, key .. "-ground")
	local guard = Geo.guard(ctx, zone)
	local detail = Geo.zoneDetail(zone)
	local parent = ctx.folders.ground

	-- terraces: every stratum steps out a stud all round plus a wide ledge
	-- on one side and the back (the other side drops sheer to the sand);
	-- the second ledge is green
	local side = if rng:NextNumber() < 0.5 then -1 else 1
	local island = Zone.island(ctx, zone, {
		field = G.limestone,
		colors = STRATA,
		grow = 1,
		lean = Vector2.new(side * 7, 4),
		capBand = 2,
		side = 10,
		back = 18,
	})
	local layers = island.layers
	local blocked: { Land.Shape } = {}

	-- a broken ridge of rock columns behind the field, 8-16 above it
	local ridge = Land.ridge(
		parent,
		Geo.slotPoint(zone, -hw * 0.95, hd + 18),
		Geo.slotPoint(zone, hw * 0.1, hd + 22),
		F + 8,
		F + 16,
		16,
		rng,
		STRATA,
		nil,
		guard,
		Geo.count(detail, 2, 3),
		BOTTOM
	)
	table.move(ridge, 1, #ridge, #blocked + 1, blocked)
	local saddle = Zone.saddle(ctx, zone, STRATA, nil)
	table.move(saddle, 1, #saddle, #blocked + 1, blocked)

	-- hoodoos around the base: two-tone columns
	for _ = 1, Geo.count(detail, 1, 4) do
		local p = Geo.slotPoint(
			zone,
			rng:NextNumber(-0.65, 0.65) * w,
			rng:NextNumber(0.1, 0.5) * d + rng:NextNumber(30, 44)
		)
		local r = rng:NextNumber(3.5, 5.5)
		if Geo.isClear(ctx, p, r + 2) and not Land.containsAny(blocked, p, -(r + 2)) then
			local shape = Land.column(
				parent,
				p,
				BOTTOM,
				F + rng:NextNumber(-10, 8),
				r,
				STRATA,
				nil,
				rng:NextNumber(0, math.pi),
				guard
			)
			if shape then
				table.insert(blocked, Land.grown(shape, 1.5))
			end
		end
	end

	-- the Thunder Spire (the rock half of the hero), on the first clear spot
	spireByZone[key] = nil
	for _, s in spireSpots(zone) do
		local spire = Geo.slotPoint(zone, s.X, s.Z)
		if Geo.isClear(ctx, spire, SPIRE_R) then
			local shape = Land.spire(
				parent,
				spire,
				BOTTOM,
				F + SPIRE_TOP,
				SPIRE_R * 0.85,
				SPIRE_R * 0.45,
				4,
				{ G.sandstone, G.limestone, G.earth, G.limestone },
				rng:NextNumber(0, math.pi),
				guard
			)
			if shape then
				spireByZone[key] = spire
				table.insert(blocked, Land.grown(shape, 3))
				break
			end
		end
	end

	-- natural arch off whichever side is clear, feet on the sea bed
	if detail >= 0.5 then
		local apron = island.apron
		local center = slot.frame:PointToObjectSpace(apron.center + UP * F)
		for _, s in { 1, -1 } do
			local mid = Geo.slotPoint(zone, center.X + s * (apron.half.X + 9), hd * 0.1)
			local along = slot.frame.LookVector
			local a = mid - along * 13
			local b = mid + along * 13
			if
				Geo.isClear(ctx, a, 6)
				and Geo.isClear(ctx, b, 6)
				and Land.arch(parent, a, b, BOTTOM, F + 4, 6, STRATA, guard)
			then
				for _, p in { a, b, mid } do
					table.insert(blocked, Land.poly(p, 7, 6))
				end
				break
			end
		end
	end

	-- talus: block rocks fallen at the foot of the cliffs
	local rocks = Geo.count(detail, 2, 5)
	for _ = 1, 16 do
		if rocks <= 0 then
			break
		end
		local p = Geo.edgePoint(
			zone,
			rng:NextNumber(-0.5, 0.5),
			rng:NextNumber(-0.3, 0.5),
			rng:NextNumber(10, 30)
		)
		if
			Land.surfaceAt(layers, p, 2) == Geo.BEACH
			and Geo.isClear(ctx, p, 2)
			and not Land.containsAny(blocked, p, -2)
		then
			rocks -= 1
			Pieces.rocks(
				zone.folder,
				Vector3.new(p.X, Geo.BEACH, p.Z),
				rng:NextNumber(2.5, 4),
				T.rock
			)
		end
	end

	layersByZone[key] = layers
	blockedByZone[key] = blocked

	-- the field: deep sage tiles on cream limestone, framed in brass with
	-- a glowing zone-colour strip
	Zone.checker(zone, 16, T.sageDark, Enum.Material.SmoothPlastic)
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
		C.copper,
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
	local place = Zone.placer(ctx, zone, Canyon.layers(zone), blockedByZone[key])
	local V2 = Vector2.new

	-- hero: the Thunder Spire's lightning rod, wired to the mesa rim
	local spire = spireByZone[key]
	if spire then
		local orb = spireRig(parent, Vector3.new(spire.X, F + SPIRE_TOP, spire.Z), zone.color)
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

	-- a pipe from the rim out over the cliff and down to the ledge below
	do
		local x = hw * -0.2
		local rim = Geo.slotPoint(zone, x, hd + 3, 0.6)
		local out = Geo.slotPoint(zone, x, hd + 12)
		local below = Land.surfaceAt(Canyon.layers(zone), out, 1)
		if below and below < F - 1 and Geo.isClear(ctx, out, 1.5) then
			local level = Vector3.new(out.X, rim.Y, out.Z)
			Pieces.pipe(parent, rim, level, 1.3, C.copper)
			Pieces.pipe(parent, level, Vector3.new(out.X, below, out.Z), 1.3, C.copper)
			Pieces.column(parent, rim - UP * 1.4, 1.6, 1.9, C.brass)
		end
	end
end

return Canyon
