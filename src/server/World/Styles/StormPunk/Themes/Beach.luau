--!strict
-- Beach theme ("Tidewire Beach"): a sand field with patina tide stripes,
-- sloping beaches with an uneven coastline, layered basalt headlands, the
-- Tidewire Lighthouse, a pier, bathing huts, buoys, driftwood and dune grass.
-- Works for any slot: everything is placed in the slot frame.

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

local Beach = {}

Beach.bridge = {
	deck = C.timber,
	deckMaterial = M.planks,
	rail = C.brass,
	pile = C.copper,
} :: Zone.BridgeStyle

-- Headland spots (u, v, out, radius, height above floor). The first one
-- carries the lighthouse.
local HEADLANDS = {
	{ u = 0.5, v = 0.5, out = 20, r = 17, h = 12 },
	{ u = -0.5, v = 0.38, out = 18, r = 13, h = 8 },
	{ u = -0.5, v = -0.32, out = 16, r = 10, h = 5 },
}

local function headlandCenter(
	zone: ZoneContext,
	spot: { u: number, v: number, out: number, r: number, h: number }
): Vector3
	-- push corners out diagonally so the rock never touches the field
	local slot = zone.slot
	local x = spot.u * slot.width
	local z = spot.v * slot.depth
	local dx = if math.abs(spot.u) >= 0.5 then math.sign(spot.u) * spot.out else 0
	local dz = if math.abs(spot.v) >= 0.5 then math.sign(spot.v) * spot.out else 0
	if dx == 0 and dz == 0 then
		dx = math.sign(spot.u) * spot.out
	end
	return slot.frame:PointToWorldSpace(Vector3.new(x + dx, 0, z + dz))
end

local layersByZone: { [string]: { Land.Layer } } = {}

function Beach.layers(zone: ZoneContext): { Land.Layer }
	return layersByZone[Geo.zoneKey(zone)] or {}
end

function Beach.ground(ctx: Context, zone: ZoneContext)
	local slot = zone.slot
	local F = slot.floor
	local w, d = slot.width, slot.depth
	local rng = Geo.rng(ctx, Geo.zoneKey(zone) .. "-ground")
	local layers: { Land.Layer } = {}

	Land.fill(
		ctx,
		Land.rectOutline(slot.frame, w + 52, d + 52, rng, 16, 10, 4),
		SEA_FLOOR,
		-3,
		TERRAIN.Sand
	)
	local beachTop = math.min(F - 2, 2)
	local beach = Land.rectOutline(slot.frame, w + 40, d + 40, rng, 14, 9, 5)
	Land.fill(ctx, beach, SEA_FLOOR, beachTop, TERRAIN.Sand)
	local raised: Land.Outline? = nil
	if F > 8 then
		-- a raised beach: sandstone cliffs under it
		raised = Land.clip(
			Land.rectOutline(slot.frame, w + 22, d + 22, rng, 10, 6),
			Geo.landSafe(ctx, F - 2, zone)
		)
		Land.cliff(
			ctx,
			raised :: Land.Outline,
			SEA_FLOOR,
			F - 2,
			TERRAIN.Sandstone,
			{ TERRAIN.Limestone, TERRAIN.Rock },
			TERRAIN.Sand
		)
	end
	local field = Land.clip(
		Land.rectOutline(slot.frame, w + 12, d + 12, rng, 6, 3),
		Geo.landSafe(ctx, F, zone)
	)
	Land.fill(ctx, field, SEA_FLOOR, F, TERRAIN.Sand)
	Land.flatRect(ctx, slot.frame, w + 6, d + 6, F, F - SEA_FLOOR, TERRAIN.Sand)

	-- layered rocky headlands at the corners
	for i, spot in HEADLANDS do
		local center = headlandCenter(zone, spot)
		if Geo.isClear(ctx, center, spot.r * 0.8, { hub = true }) then
			local outline = Land.clip(
				Land.roundOutline(center, spot.r, rng, 7, 2),
				Geo.landSafe(ctx, F + spot.h, zone)
			)
			Land.fill(
				ctx,
				Land.roundOutline(center, spot.r + 8, rng, 6, 3),
				SEA_FLOOR,
				F - 1,
				TERRAIN.Sand
			)
			Land.cliff(
				ctx,
				outline,
				SEA_FLOOR,
				F + spot.h,
				TERRAIN.Basalt,
				{ TERRAIN.Slate, TERRAIN.Rock },
				if i == 1 then TERRAIN.LeafyGrass else TERRAIN.Rock
			)
			table.insert(layers, { outline = outline, top = F + spot.h })
		end
	end
	-- grassy dunes on the sand ring
	for _ = 1, 9 do
		local at = Geo.edgePoint(
			zone,
			rng:NextNumber(-0.5, 0.5),
			rng:NextNumber(-0.3, 0.5),
			rng:NextNumber(10, 17),
			0
		)
		local r = rng:NextNumber(5, 8)
		if Geo.isClear(ctx, at, r) then
			ctx.terrain:FillBall(Vector3.new(at.X, F + 1.5 - r, at.Z), r, TERRAIN.LeafyGrass)
			table.insert(layers, {
				outline = { box = nil, circles = { { x = at.X, z = at.Z, r = r * 0.45 } } },
				top = F + 1.2,
			})
		end
	end
	table.insert(layers, { outline = field, top = F })
	if raised then
		table.insert(layers, { outline = raised, top = F - 2 })
	end
	table.insert(layers, { outline = beach, top = beachTop })
	layersByZone[Geo.zoneKey(zone)] = layers

	-- the field: warm sand with scalloped patina tide bands and a brass frame
	Zone.waveStripes(zone, 5, C.patina, TERRAIN.Sand)
	Zone.floorFrame(zone, C.brass, 1.2)
end

-- The Tidewire Lighthouse: ceramic and copper bands, a glass lantern with a
-- cyan core, a copper coil ring and a lightning rod. Returns the lantern.
local function lighthouse(parent: Instance, base: Vector3): Vector3
	Pieces.column(parent, base - UP * 2, 4.5, 11, T.rockDark, Enum.Material.Slate, true)
	Pieces.block(
		parent,
		CFrame.new(base + Vector3.new(0, 2.2, 5.1)),
		Vector3.new(2.4, 4, 1),
		C.soot,
		M.metal
	)
	local y = 2.5
	local diameter = 8.4
	for i = 1, 6 do
		Pieces.column(
			parent,
			base + UP * y,
			6.4,
			diameter,
			if i % 2 == 1 then C.ceramic else C.copper,
			if i % 2 == 1 then M.ceramic else M.metal,
			true
		)
		if i == 3 or i == 5 then
			Pieces.block(
				parent,
				CFrame.new(base + Vector3.new(0, y + 3.2, -diameter / 2 + 0.05)),
				Vector3.new(1.2, 1.8, 0.3),
				T.warmLight,
				M.neon
			)
		end
		y += 6.4
		diameter -= 0.5
	end
	-- gallery
	Pieces.column(parent, base + UP * y, 0.9, diameter + 3.4, C.iron)
	for i = 0, 7 do
		local p = base + Geo.dir(i * 45) * (diameter / 2 + 1.4) + UP * (y + 0.9)
		Pieces.strut(parent, p, p + UP * 1.8, 0.25, C.brass)
	end
	-- lantern room
	local lanternY = y + 0.9
	local glass = Pieces.column(parent, base + UP * lanternY, 5, diameter - 1, T.glass, M.glass)
	glass.Transparency = 0.4
	local core = Pieces.orb(parent, base + UP * (lanternY + 2.5), 3, C.volt, 46, true)
	local _ = core
	Pieces.torus(parent, base + UP * (lanternY + 2.5), diameter / 2 + 0.2, 1.1, 12, C.copper)
	-- roof
	Pieces.column(parent, base + UP * (lanternY + 5), 0.9, diameter + 0.8, C.copper)
	Pieces.column(parent, base + UP * (lanternY + 5.9), 0.9, diameter - 1.6, C.patina)
	Pieces.ball(parent, base + UP * (lanternY + 6.8), diameter - 3, C.patina)
	Pieces.column(parent, base + UP * (lanternY + 7.5), 7, 0.45, C.copper)
	Pieces.ball(parent, base + UP * (lanternY + 14.6), 1, C.volt, M.neon)
	return base + UP * (lanternY + 2.5)
end

local function bathingHut(parent: Instance, frame: CFrame, rng: Random)
	-- frame on the sand, LookVector = the hut's door side
	local stripe = if rng:NextNumber() < 0.5 then C.patina else T.copperDark
	Pieces.block(
		parent,
		frame * CFrame.new(0, 3.4, 0),
		Vector3.new(4, 4.6, 4.4),
		C.ceramic,
		M.planks,
		true
	)
	for _, x in { -1.3, 0, 1.3 } do
		Pieces.block(
			parent,
			frame * CFrame.new(x, 3.4, 0),
			Vector3.new(0.6, 4.62, 4.42),
			stripe,
			M.planks
		)
	end
	Pieces.wedge(
		parent,
		frame * CFrame.new(0, 6.5, 1.15),
		Vector3.new(4.6, 1.6, 2.3),
		C.copper,
		M.metal
	)
	Pieces.wedge(
		parent,
		frame * CFrame.new(0, 6.5, -1.15) * CFrame.Angles(0, math.pi, 0),
		Vector3.new(4.6, 1.6, 2.3),
		C.copper,
		M.metal
	)
	for _, z in { -1.4, 1.4 } do
		Pieces.pipe(
			parent,
			(frame * CFrame.new(-2.3, 1, z)).Position,
			(frame * CFrame.new(2.3, 1, z)).Position,
			2,
			C.iron
		)
	end
end

-- Palm: a curved, ringed trunk and a crown of flat fronds with copper nuts.
local function palm(parent: Instance, base: Vector3, lean: Vector3, rng: Random)
	local height = rng:NextNumber(11, 15)
	local bend = rng:NextNumber(2.5, 4.5)
	local segments = 4
	local prev = base
	for i = 1, segments do
		local t = i / segments
		local p = base + UP * height * t + lean * bend * t * t
		Pieces.pipe(
			parent,
			prev - (p - prev).Unit * 0.2,
			p,
			1.25 - t * 0.35,
			if i % 2 == 0 then T.timberPale else C.timber,
			M.wood
		)
		prev = p
	end
	local crown = prev
	local spin = rng:NextNumber(0, 360)
	for i = 0, 6 do
		local d = Geo.dir(spin + i * (360 / 7))
		local length = rng:NextNumber(5.5, 7.5)
		local tip = crown + d * length - UP * rng:NextNumber(2.2, 3.6)
		local mid = crown:Lerp(tip, 0.5) + UP * 0.6
		local cf = CFrame.lookAt(mid, tip) * CFrame.Angles(0, 0, math.rad(90))
		Pieces.wedge(
			parent,
			cf,
			Vector3.new(0.3, 2.2, (tip - crown).Magnitude),
			if i % 2 == 0 then C.sage else T.sageDark,
			Enum.Material.Grass
		)
	end
	for i = 0, 2 do
		Pieces.ball(parent, crown - UP * 0.7 + Geo.dir(spin + 40 + i * 120) * 0.6, 0.9, C.copper)
	end
end

local function buoy(parent: Instance, at: Vector3, color: Color3)
	Pieces.ball(parent, at, 2.6, color)
	Pieces.column(parent, at + UP * 0.8, 1.6, 0.4, C.iron)
	Pieces.ball(parent, at + UP * 2.6, 0.8, C.volt, M.neon)
end

function Beach.dress(ctx: Context, zone: ZoneContext)
	local slot = zone.slot
	local F = slot.floor
	local parent = zone.folder
	local rng = Geo.rng(ctx, Geo.zoneKey(zone) .. "-dress")

	-- hero: the lighthouse on the first headland
	local spot = HEADLANDS[1]
	local hc = headlandCenter(zone, spot)
	if Geo.isClear(ctx, hc, spot.r * 0.8, { hub = true }) then
		local lantern = lighthouse(parent, Vector3.new(hc.X, F + spot.h, hc.Z))
		local corner = Geo.edgePoint(zone, 0.5, 0.5, 0, Zone.POST_HEIGHT - 1.5)
		Pieces.liveCable(ctx, lantern + UP * 1, corner + UP * 0.2, zone.color, 0.35, 6)
	end

	local layers = Beach.layers(zone)

	-- bathing huts outside the fence on the left side
	for i, v in { -0.2, 0.02, 0.24 } do
		local hutSpot = Geo.edgePoint(zone, -0.5, v, 7, 0)
		local top = Land.surfaceAt(layers, hutSpot, 2)
		local p = Vector3.new(hutSpot.X, top or F, hutSpot.Z)
		if top and top >= F - 0.5 and Geo.isClear(ctx, p, 3) then
			local frame = Geo.facing(p, slot.frame.Position)
				* CFrame.Angles(0, math.rad(rng:NextNumber(-6, 6)), 0)
			bathingHut(parent, frame, rng)
			local side = frame.RightVector * (if i % 2 == 0 then 4 else -4)
			if rng:NextNumber() < 0.7 then
				Pieces.crate(parent, p + side, rng:NextNumber(1.6, 2.2), rng:NextNumber(0, 90))
			else
				Pieces.barrel(parent, p + side, C.patina)
			end
		end
	end

	-- pier on the right side, out into the water
	local pierFrom = Geo.edgePoint(zone, 0.5, -0.12, 10, 0)
	local pierTo = Geo.edgePoint(zone, 0.5, -0.12, 42, 0)
	if Geo.isClear(ctx, pierTo, 4) then
		local a = Vector3.new(pierFrom.X, 0, pierFrom.Z)
		local b = Vector3.new(pierTo.X, 0, pierTo.Z)
		Pieces.pier(parent, a, b, 2.6, "PIER")
		local along = (b - a).Unit
		Pieces.skiff(
			parent,
			CFrame.lookAt(b - along * 9 + along:Cross(UP) * 6.5, b + along:Cross(UP) * 6.5)
		)
	end

	-- lamps along the beach outside the fence
	for _, cf in Kit.perimeter(zone, 34 / Geo.detail(zone)) do
		local p = cf.Position + cf.LookVector * 5
		if Geo.isClear(ctx, p, 1) then
			Pieces.lamp(
				parent,
				p,
				7,
				T.warmLight,
				if rng:NextNumber() < 0.45 * Geo.detail(zone) then 18 else nil
			)
		end
	end

	-- buoys bobbing offshore
	for _ = 1, Geo.count(zone, 7) do
		local u = rng:NextNumber(-0.5, 0.5)
		local v = rng:NextNumber(-0.1, 0.5)
		local p = Geo.edgePoint(zone, u, v, rng:NextNumber(30, 44), 0.4)
		p = Vector3.new(p.X, 0.4, p.Z)
		if Geo.isClear(ctx, p, 3) then
			buoy(parent, p, if rng:NextNumber() < 0.5 then C.copper else C.hazard)
		end
	end

	-- palms leaning out toward the sea
	local palms = 0
	for _ = 1, 24 do
		if palms >= Geo.count(zone, 6, 2) then
			break
		end
		local at = Geo.edgePoint(
			zone,
			rng:NextNumber(-0.55, 0.55),
			rng:NextNumber(-0.35, 0.55),
			rng:NextNumber(6.5, 14),
			0
		)
		local top = Land.surfaceAt(layers, at, 2)
		if top and top > 1 and Geo.isClear(ctx, at, 3) then
			palms += 1
			local out =
				Vector3.new(at.X - slot.frame.Position.X, 0, at.Z - slot.frame.Position.Z).Unit
			palm(parent, Vector3.new(at.X, top, at.Z), out, rng)
		end
	end

	-- small stuff on the sand ring: rocks, driftwood, dune grass, barrels
	for _ = 1, Geo.count(zone, 52) do
		local u = rng:NextNumber(-0.55, 0.55)
		local v = rng:NextNumber(-0.5, 0.55)
		local at = Geo.edgePoint(zone, u, v, rng:NextNumber(4.5, 19), 0)
		local top = Land.surfaceAt(layers, at, 1.5)
		local p = Vector3.new(at.X, top or -99, at.Z)
		if top and top > 0.5 and Geo.isClear(ctx, p, 1.2) then
			local roll = rng:NextNumber()
			if roll < 0.45 then
				Pieces.tuft(parent, p, rng, if rng:NextNumber() < 0.5 then C.sage else T.sageDark)
			elseif roll < 0.7 then
				Pieces.rocks(
					parent,
					p,
					rng:NextNumber(1.2, 2.6),
					rng,
					if rng:NextNumber() < 0.5 then T.rock else T.rockDark
				)
			elseif roll < 0.85 then
				local yaw = rng:NextNumber(0, math.pi)
				local half = Vector3.new(math.cos(yaw), 0, math.sin(yaw)) * rng:NextNumber(2, 3.5)
				Pieces.pipe(
					parent,
					p - half + UP * 0.4,
					p + half + UP * 0.5,
					rng:NextNumber(0.7, 1.1),
					T.timberPale,
					M.wood
				)
			else
				Pieces.barrel(parent, p, if rng:NextNumber() < 0.5 then C.copper else C.patina)
			end
		end
	end
end

return Beach
