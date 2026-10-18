--!strict
-- Bottleworks Plaza: the sea, the block-built hub island with its crags,
-- scenery islets with Tesla pylons and basalt sea stacks, and the hub itself
-- (Grand Coil, Volt Exchange sell station, spawn, light trails, bridgeheads,
-- arrow signs and props).
--
-- Every hub prop stands on a "quiet" bearing halfway between the spiral's
-- exit bearings and is checked against every (future) exit lane, so zones
-- added later always find their exit free.

local ServerScriptService = game:GetService("ServerScriptService")

local World = ServerScriptService.Server.World
local Blocks = require(World.Blocks)
local Kit = require(World.Kit)
local WorldTypes = require(World.Types)
local Geo = require(script.Parent.Geo)
local Land = require(script.Parent.Land)
local Palette = require(script.Parent.Palette)
local Pieces = require(script.Parent.Pieces)

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
local TEASER_TRAIL = C.soot

local Hub = {}

local function slotName(zone: ZoneContext): string
	local def = zone.def
	return if def then def.displayName else "Coming Soon"
end

local function bearingOf(zone: ZoneContext): number
	return math.deg(zone.slot.angle) % 360
end

-- Base: sea, hub island ------------------------------------------------------------

type HubGround = {
	layers: { Land.Layer },
	plaza: Land.Shape,
	ramp: { Vector3 }, -- the harbour path: plaza edge, beach foot
}

-- weak keys: an old build's Context (and its destroyed Map) can be collected
local hubGrounds: { [Context]: HubGround } = setmetatable({}, { __mode = "k" }) :: any

-- One see-through water surface and a solid seabed a few studs under it.
local function buildSea(ctx: Context)
	local size = Blocks.MAX_SIZE
	Blocks.water(ctx.folders.base, Palette.water, Vector3.zero, Vector2.new(size, size), Geo.WATER)
	Blocks.box(
		ctx.folders.ground,
		G.seabed,
		CFrame.new(0, SEA_FLOOR - 1, 0),
		Vector3.new(size, 2, size),
		{ Name = "Seabed", CastShadow = false }
	)
end

-- The hub island, a round terraced citadel: a brick plaza on a slate band,
-- a green terrace on slate and basalt strata, a sand beach with a shore
-- slope all round (and two lobes for the crags to stand on), a paved
-- harbour path down from the spawn side and path strips out to every exit.
-- The 16-gons turn a face down every exit and quiet bearing.
local function buildHubIsland(ctx: Context)
	local parent = ctx.folders.ground
	local R = ctx.layout.hubRadius
	local F = ctx.layout.hubFloor
	local sb = Geo.spawnBearing(ctx)
	local yaw = Geo.faceYaw(Geo.exitBearings(ctx)[1])
	local key = Vector3.new(0, 0, 1)
	local layers: { Land.Layer } = {}
	local function keep(list: { Land.Layer })
		table.move(list, 1, #list, #layers + 1, layers)
	end

	local plaza = Land.poly(Vector3.zero, R + 5.5, 16, yaw)
	keep(Land.stack(parent, plaza, F, F - 6, {
		{ color = G.brick, height = 1.2 },
		{ color = G.slate, grow = -0.6 },
	}, key))
	keep(Land.stack(parent, Land.poly(Vector3.zero, R + 18, 16, yaw), F - 4, BEACH - 1, {
		{ color = G.slate, height = 4, cap = G.grass },
		{ color = G.basalt, grow = 0.9 },
	}, key))

	local beach = Land.poly(Vector3.zero, R + 33, 16, yaw)
	local beaches = { beach }
	for i, offset in { 180, 270 } do
		if i <= Geo.count(Geo.worldDetail(ctx), 0, 2) then
			table.insert(beaches, Land.poly(Geo.polar(sb + offset, R + 36, 0), 20, 12, yaw))
		end
	end
	for _, shape in beaches do
		Land.prism(parent, G.sand, shape, BEACH, BOTTOM, Land.SHARED + UP * BEACH)
		Land.register(ctx, shape)
		table.insert(layers, { shape = shape, top = BEACH })
	end
	for _, shape in beaches do
		Land.skirt(parent, G.wetSand, shape, BEACH, BOTTOM, beaches)
	end

	-- the harbour path: plaza -> terrace -> beach, two paved ramps (23 and
	-- 26 degrees) with a landing on the terrace
	local top = Geo.polar(sb, R + 4.5, F)
	local foot = Geo.polar(sb, R + 32.5, BEACH)
	Blocks.ramp(parent, G.pavement, Geo.polar(sb, R + 14, F - 4), top, 10, { Name = "Path" })
	Land.path(
		parent,
		Geo.polar(sb, R + 14, 0),
		Geo.polar(sb, R + 18.4, 0),
		10,
		F - 4,
		G.pavement,
		G.edging
	)
	Blocks.ramp(parent, G.pavement, foot, Geo.polar(sb, R + 18.4, F - 4), 10, { Name = "Path" })

	-- path strips toward every exit (the light trails run on them)
	for _, zone in Geo.allSlots(ctx) do
		local b = bearingOf(zone)
		Land.path(
			parent,
			Geo.polar(b, 26.7, 0),
			Geo.polar(b, R - 0.4, 0),
			10,
			F,
			G.pavement,
			G.edging
		)
	end
	hubGrounds[ctx] = { layers = layers, plaza = plaza, ramp = { top, foot } }
end

-- Crags: basalt column ridges on three quiet bearings, the island's
-- silhouette and a backdrop behind the coil, standing on the terrace and
-- the beach lobes (built once every zone is down, so decks are known).
local function buildCrags(ctx: Context): { Land.Shape }
	local R = ctx.layout.hubRadius
	local sb = Geo.spawnBearing(ctx)
	local rng = Geo.rng(ctx, "hub-crags")
	local guard = Geo.guard(ctx, nil)
	local crags: { Land.Shape } = {}
	for k, offset in { 180, 225, 270 } do
		local b = sb + offset
		local columns = Land.ridge(
			ctx.folders.ground,
			Geo.polar(b, R + 12, 0),
			Geo.polar(b, R + 32, 0),
			22 + k * 3,
			30 + k * 4,
			15,
			rng,
			{ G.basalt, G.slate },
			G.grass,
			guard,
			Geo.count(Geo.worldDetail(ctx), 2, 3),
			BEACH - 1
		)
		table.move(columns, 1, #columns, #crags + 1, crags)
	end
	return crags
end

-- Little basalt islets on quiet bearings, each carrying a Tesla pylon,
-- strung together with power lines where they clear every deck. Built
-- after the zone islands, in open water clear of all of them.
local function buildIslets(ctx: Context)
	local rng = Geo.rng(ctx, "islets")
	local folder = ctx.folders.decor
	local R = ctx.layout.hubRadius
	local tips: { { bearing: number, a: Vector3, b: Vector3 } } = {}
	local harbour = Geo.spawnBearing(ctx)
	local budget = Geo.count(Geo.worldDetail(ctx), 1, 5)
	for _, bearing in Geo.quietBearings(ctx) do
		local radius = R + 60 + rng:NextNumber(-4, 8)
		local center = Geo.polar(bearing, radius, 0)
		local size = rng:NextNumber(8, 11)
		if
			#tips < budget
			and math.abs(Geo.angleDiff(bearing, harbour)) > 1
			and Geo.isClear(ctx, center, size + 40, { hub = false })
			and Land.isOpenWater(ctx, center, size + 12)
		then
			local shape = Land.poly(center, size, 10, rng:NextNumber(0, math.pi))
			Land.stack(ctx.folders.ground, shape, 4, BOTTOM, {
				{ color = G.slate, height = 2, cap = G.grass },
				{ color = G.basalt, grow = 0.8 },
			})
			Land.register(ctx, Land.grown(shape, 0.8))
			local a, b =
				Pieces.pylon(folder, center + UP * 4, rng:NextNumber(26, 32), bearing + 90, 3, 0.8)
			table.insert(tips, { bearing = bearing, a = a, b = b })
			Pieces.tuft(folder, center + Vector3.new(3, 4, -2), rng, C.sage)
			Pieces.tuft(folder, center + Vector3.new(-2, 4, 3), rng, T.sageDark)
		end
	end
	-- power lines between neighbouring pylons, kept 10 studs over any deck
	for i, from in tips do
		local to = tips[i % #tips + 1]
		if #tips > 1 and ((to.bearing - from.bearing) % 360) <= 50 then
			local fa, fb = from.a, from.b
			local ta, tb = to.a, to.b
			if
				(fa - ta).Magnitude + (fb - tb).Magnitude
				> (fa - tb).Magnitude + (fb - ta).Magnitude
			then
				ta, tb = tb, ta
			end
			local sag = 6
			local lowest = math.min(fa.Y, ta.Y) - 0.75 * sag
			local clear = true
			for _, zone in Geo.allSlots(ctx) do
				local d, at = Geo.segmentsDistance(
					fa,
					ta,
					zone.slot.hubExit.Position,
					zone.slot.gate.Position
				)
				if d < Geo.CORRIDOR then
					local deck = Geo.deckHeightAt(ctx, at, Geo.CORRIDOR + 1, 6)
					if deck and lowest < (deck :: number) + 10 then
						clear = false
					end
				end
			end
			if clear then
				Pieces.wire(ctx, fa, ta, sag)
				Pieces.wire(ctx, fb, tb, sag)
			end
		end
	end
end

-- Free-standing basalt sea stacks: clusters of hex columns in open water,
-- fewer as the world fills up.
local function buildSeaStacks(ctx: Context)
	local rng = Geo.rng(ctx, "stacks")
	local guard = Geo.guard(ctx, nil)
	local wanted = Geo.count(Geo.worldDetail(ctx), 2, 8)
	local count = 0
	local tries = 0
	while count < wanted and tries < 120 do
		tries += 1
		local base = Geo.polar(rng:NextNumber(0, 360), rng:NextNumber(100, 340), 0)
		local r = rng:NextNumber(7, 11)
		if
			Geo.isClear(ctx, base, r + 30, { hub = false })
			and Land.isOpenWater(ctx, base, r + 14)
		then
			local columns = Land.cluster(
				ctx.folders.ground,
				rng,
				base,
				r,
				BOTTOM,
				Geo.WATER + rng:NextNumber(10, 30),
				{ G.basalt, G.slate },
				G.grass,
				rng:NextInteger(2, 3),
				guard
			)
			if #columns > 0 then
				count += 1
				for _, shape in columns do
					Land.register(ctx, shape)
				end
			end
		end
	end
end

-- Shrub clumps on the green terrace: off the plaza's cliff, off the crags
-- and the harbour path, out of every exit lane.
local function dressTerrace(ctx: Context, crags: { Land.Shape })
	local parent = ctx.folders.hub
	local ground = hubGrounds[ctx]
	if not ground then
		return
	end
	local rng = Geo.rng(ctx, "hub-terrace")
	local R = ctx.layout.hubRadius
	local floor = ctx.layout.hubFloor
	local sb = Geo.spawnBearing(ctx)
	for k = 1, 10 do
		local a = sb + 18 + k * 33 + rng:NextNumber(-8, 8)
		for _, r in { R + 12, R + 15, R + 9 } do
			local p = Geo.polar(a, r, floor - 4)
			if
				not Land.containsAny(crags, p, -4)
				and not Land.contains(ground.plaza, p, -3)
				and Land.surfaceAt(ground.layers, p, 2.5) == floor - 4
				and Geo.segmentDistance(p, ground.ramp[1], ground.ramp[2]) > 9
				and not Geo.inExitLane(ctx, p, 8)
				and Geo.isClear(ctx, p, 3, { hub = false })
			then
				Pieces.shrub(parent, p, rng, if k % 2 == 0 then C.sage else T.sageDark)
				Pieces.tuft(parent, p + Geo.dir(a + 90) * 2.5, rng, T.sageDark)
				break
			end
		end
	end
end

-- After every zone island (so decks and shores are known): the crags, the
-- terrace shrubs, the islets and the sea stacks.
function Hub.buildScenery(ctx: Context)
	local crags = buildCrags(ctx)
	dressTerrace(ctx, crags)
	buildIslets(ctx)
	buildSeaStacks(ctx)
end

function Hub.buildBase(ctx: Context)
	buildSea(ctx)
	buildHubIsland(ctx)
end

-- Hub pieces ---------------------------------------------------------------------------

-- The Grand Coil, the hub's hero: a fat copper secondary banded in brass
-- and ceramic inside a chunky lattice, standing on a copper drum, crowned
-- with a big copper torus and a sparking cyan orb. Returns the crown centre.
local function grandCoil(parent: Instance, floor: number): Vector3
	local o = Vector3.new(0, floor, 0)
	Kit.cylinder(parent, o - UP * 0.4, 1, 19, { Color = C.brass, Material = M.metal })
	Kit.cylinder(parent, o, 0.7, 17.5, { Color = C.iron, Material = M.plate })
	local drumBase = o + UP * 0.7
	Pieces.column(parent, drumBase, 9, 12, C.copper, M.metal, true)
	Pieces.column(parent, drumBase, 1.3, 12.8, C.patina)
	Pieces.column(parent, drumBase + UP * 7.8, 1.4, 13.2, C.patina)
	for i = 0, 3 do
		local d = Geo.dir(i * 90 + 45)
		local cf = CFrame.lookAt(drumBase + d * 5.95 + UP * 4.5, drumBase + d * 10 + UP * 4.5)
		Pieces.block(parent, cf, Vector3.new(1.4, 4.5, 0.3), C.volt, M.neon)
	end
	local deckY = floor + 10
	Kit.cylinder(parent, Vector3.new(0, deckY, 0), 0.9, 14, { Color = C.brass, Material = M.metal })

	-- the secondary: a fat copper column banded every ~9 studs
	local coilTop = floor + 66
	Pieces.column(parent, Vector3.new(0, deckY + 0.9, 0), coilTop - deckY - 0.9, 6.6, C.copper)
	for k, y in { 20, 38, 47, 56 } do
		Pieces.column(
			parent,
			Vector3.new(0, floor + y, 0),
			1.4,
			7.8,
			if k % 2 == 1 then C.brass else C.ceramic,
			if k % 2 == 1 then M.metal else M.ceramic
		)
	end
	-- a glowing band low enough to sit in the spawn's first frame
	local glowBand = Pieces.column(parent, Vector3.new(0, floor + 28, 0), 2.6, 7.4, C.volt, M.neon)
	Pieces.glow(glowBand, C.volt, 26, 1.6)

	-- lattice legs and two rings, thick enough to read from the zones
	local legs: { Vector3 } = {}
	local heads: { Vector3 } = {}
	for i = 0, 3 do
		local d = Geo.dir(i * 90 + 45)
		local foot = d * 6.2 + Vector3.new(0, deckY + 0.9, 0)
		local head = d * 5 + Vector3.new(0, coilTop - 4, 0)
		Pieces.strut(parent, foot, head, 1.5, C.iron)
		table.insert(legs, foot)
		table.insert(heads, head)
	end
	for _, t in { 0.33, 0.66 } do
		for i = 1, 4 do
			Pieces.strut(
				parent,
				legs[i]:Lerp(heads[i], t),
				legs[i % 4 + 1]:Lerp(heads[i % 4 + 1], t),
				0.9,
				C.copper
			)
		end
	end
	-- crown: brass deck, big copper torus, patina dome, orb and rod
	local crownY = coilTop + 2
	Kit.cylinder(
		parent,
		Vector3.new(0, coilTop - 1, 0),
		1.6,
		13,
		{ Color = C.brass, Material = M.metal }
	)
	Pieces.torus(parent, Vector3.new(0, crownY, 0), 8, 4.5, 12, C.copper)
	Pieces.ball(parent, Vector3.new(0, crownY + 0.4, 0), 11, C.patina)
	Pieces.orb(parent, Vector3.new(0, crownY + 7.5, 0), 6, C.volt, 60, true)
	Pieces.column(parent, Vector3.new(0, crownY + 10, 0), 8, 0.8, C.copper)
	Pieces.ball(parent, Vector3.new(0, crownY + 18.5, 0), 1.4, C.volt, M.neon)
	return Vector3.new(0, crownY, 0)
end

-- The Volt Exchange: amber pad, marquee SELL gantry, capacitor towers. The
-- only amber in the hub. Kept inside r < 26 sideways so it never reaches
-- an exit lane. Returns the capacitor tops (for the coil's cables).
local function voltExchange(parent: Instance, floor: number, bearing: number): { Vector3 }
	local padPos = Geo.polar(bearing, 19, floor)
	local frame = Geo.facing(padPos, Vector3.new(0, floor, 0)) -- -Z toward the coil, +Z toward spawn
	local toSpawn = frame * CFrame.Angles(0, math.pi, 0)
	local half = 7

	local pad = Kit.part({
		Name = "SellPad",
		Size = Vector3.new(2 * half, 1, 2 * half),
		CFrame = frame * CFrame.new(0, -0.3, 0),
		Color = C.hazard,
		Material = M.plate,
		Parent = parent,
	})
	pad.CanTouch = false
	Kit.faceText(pad, Enum.NormalId.Top, "SELL", nil, {
		boardColor = C.hazard,
		titleColor = C.ceramic,
		strokeColor = C.soot,
		titleFont = Enum.Font.LuckiestGuy,
	})
	Kit.sellArea(parent, pad)

	-- neon border and chevrons from the spawn side toward the pad
	local top = 0.2
	local e = half
	for _, s in { { -e, -e, e, -e }, { e, -e, e, e }, { e, e, -e, e }, { -e, e, -e, -e } } do
		local a = (frame * CFrame.new(s[1], top, s[2])).Position
		local b = (frame * CFrame.new(s[3], top, s[4])).Position
		Pieces.trail(parent, a, b, 0.9, C.hazard, M.neon, 0.06)
	end
	for i = 1, 3 do
		local at = (frame * CFrame.new(0, 0.02, half + i * 3)).Position
		Pieces.chevron(parent, at, frame.LookVector, 3.2, C.hazard)
	end

	-- gantry with the giant marquee SELL sign
	local signZ = -4
	local legX = 10.5
	for _, side in { -1, 1 } do
		local foot = (frame * CFrame.new(side * legX, 0, signZ)).Position
		Pieces.column(parent, foot, 23, 2.2, C.copper, M.metal, true)
		Pieces.column(parent, foot, 1.6, 3.4, C.iron)
		Pieces.column(parent, foot + UP * 22.6, 1.6, 3, C.ceramic, M.ceramic)
		Pieces.ball(parent, foot + UP * 25.4, 1.8, C.hazard, M.neon)
	end
	local header = Pieces.block(
		parent,
		toSpawn * CFrame.new(0, 22.4, -signZ),
		Vector3.new(2 * legX + 2.4, 3, 1.4),
		C.soot,
		Enum.Material.SmoothPlastic
	)
	Kit.faceText(header, Enum.NormalId.Front, "VOLT EXCHANGE", nil, Palette.sign(C.brass))
	Kit.faceText(header, Enum.NormalId.Back, "VOLT EXCHANGE", nil, Palette.sign(C.brass))
	local signCF = toSpawn * CFrame.new(0, 15.6, -signZ)
	local signW = 2 * legX - 3
	local board =
		Pieces.framedSign(parent, signCF, signW, 8, "SELL", "charges for Volts", Palette.marquee())
	Pieces.glow(board, L.warm, 26, 2)
	-- marquee bulbs, alternating amber and cyan
	local bulbs = 8
	for i = 0, bulbs do
		local x = -signW / 2 + i * signW / bulbs
		for _, y in { 4.75, -4.75 } do
			local p = (signCF * CFrame.new(x, y, 0)).Position
			Pieces.ball(
				parent,
				p,
				0.9,
				if (i + (if y > 0 then 0 else 1)) % 2 == 0 then C.hazard else C.volt,
				M.neon
			)
		end
	end
	-- lightning bolt emblem on top
	local boltCF = signCF * CFrame.new(0, 10.6, 0)
	for _, b in
		{
			{ -0.8, 1.6, -28, 1.4, 3.6 },
			{ 0, 0, 62, 1.2, 3 },
			{ 0.8, -1.6, -28, 1.4, 3.6 },
		}
	do
		Pieces.block(
			parent,
			boltCF * CFrame.new(b[1], b[2], 0) * CFrame.Angles(0, 0, math.rad(b[3])),
			Vector3.new(b[4], b[5], 0.8),
			C.hazard,
			M.neon
		)
	end

	-- capacitor towers beside the pad, fed from the coil
	local caps: { Vector3 } = {}
	for _, side in { -1, 1 } do
		local foot = (frame * CFrame.new(side * 14.8, 0, -5)).Position
		Pieces.column(parent, foot, 1.6, 6, C.iron, M.metal, true)
		local core = Pieces.column(parent, foot + UP * 1.6, 13, 1.8, C.volt, M.neon)
		Pieces.sparks(core, C.volt, 5)
		local glass = Pieces.column(parent, foot + UP * 1.6, 13, 4.6, T.glass, M.glass, true)
		glass.Transparency = 0.45
		Pieces.column(parent, foot + UP * 8, 0.7, 5, C.brass)
		Pieces.column(parent, foot + UP * 14.6, 1.4, 5.6, C.copper)
		Pieces.column(parent, foot + UP * 16, 1.6, 2.6, C.ceramic, M.ceramic)
		local knob = Pieces.ball(parent, foot + UP * 18.2, 1.8, C.copper)
		Pieces.glow(knob, C.volt, 16, 1.5)
		table.insert(caps, foot + UP * 18.2)
	end
	return caps
end

-- Gateway arch at a hub exit, in the zone's colour. Returns a pillar top.
local function bridgehead(
	parent: Instance,
	zone: ZoneContext,
	floor: number,
	color: Color3
): Vector3
	local exit = zone.slot.hubExit
	local base = exit.Position - exit.LookVector * 3
	local frame = CFrame.lookAt(base, base - exit.LookVector) -- text faces the hub
	local tops: { Vector3 } = {}
	for _, side in { -1, 1 } do
		local foot = (frame * CFrame.new(side * 7, 0, 0)).Position
		local f = Vector3.new(foot.X, floor, foot.Z)
		Pieces.column(parent, f, 12, 2.2, C.copper, M.metal, true)
		Pieces.column(parent, f + UP * 10.4, 1.6, 3, C.ceramic, M.ceramic)
		Pieces.ball(parent, f + UP * 12.9, 2, color, M.neon)
		table.insert(tops, f + UP * 12.9)
	end
	Pieces.framedSign(
		parent,
		frame * CFrame.new(0, 9.6, 0),
		11,
		2.8,
		string.upper(slotName(zone)),
		nil,
		Palette.sign(if zone.isTeaser then C.ceramic else color, true)
	)
	return tops[1]
end

local function lightTrail(parent: Instance, zone: ZoneContext, floor: number, hubRadius: number)
	local b = bearingOf(zone)
	local color = if zone.isTeaser then TEASER_TRAIL else zone.color
	local chevrons = if zone.isTeaser then C.hazard else zone.color
	-- on the path strip, 0.2 above the plaza
	local from = Geo.polar(b, 28, floor + 0.2)
	local to = Geo.polar(b, hubRadius + 2, floor + 0.2)
	Pieces.trail(parent, from, to, 1.6, color, if zone.isTeaser then M.metal else M.neon)
	for _, r in { 34, 44 } do
		Pieces.chevron(parent, Geo.polar(b, r, floor + 0.2), Geo.dir(b), 3.4, chevrons)
	end
end

-- Props on quiet bearings -------------------------------------------------------------

local function kiosk(parent: Instance, frame: CFrame)
	-- frame: on the floor, LookVector toward the hub centre (shop front)
	local roof = Pieces.building(
		parent,
		frame * CFrame.new(0, 0, 1.5),
		Vector3.new(9, 5, 5),
		C.timber,
		M.planks
	)
	Pieces.block(
		parent,
		frame * CFrame.new(0, 1.3, -1.7),
		Vector3.new(9.4, 2.6, 1.4),
		C.copper,
		M.metal,
		true
	)
	-- striped awning sloping down toward the customers
	for i = 0, 2 do
		local x = -3 + i * 3
		Pieces.wedge(
			parent,
			frame * CFrame.new(x, 6.4, -1.8),
			Vector3.new(3, 1.6, 3.6),
			if i % 2 == 0 then C.patina else C.ceramic,
			M.fabric
		)
	end
	local _ = roof
	local sign = Pieces.framedSign(
		parent,
		frame * CFrame.new(0, 8.6, 0.4),
		8,
		2,
		"BOTTLES",
		nil,
		Palette.sign(C.volt, true)
	)
	Pieces.glow(sign, L.warm, 14, 1.2)
	for _, x in { -3, 3 } do
		Pieces.ball(parent, (frame * CFrame.new(x, 3.1, -1.7)).Position, 0.9, C.volt, M.neon)
	end
end

local function foundry(parent: Instance, frame: CFrame)
	-- frame: on the floor, LookVector toward the hub
	local roof =
		Pieces.building(parent, frame, Vector3.new(16, 10, 12), T.copperDark, M.brick, C.copper)
	-- sawtooth roof
	for i = 0, 2 do
		local x = -5.4 + i * 5.4
		Pieces.wedge(
			parent,
			roof * CFrame.new(x, 2.5, 0) * CFrame.Angles(0, math.rad(90), 0),
			Vector3.new(13, 5, 5.4),
			C.patina,
			M.metal
		)
	end
	-- warm windows and a big door on the hub side
	local wall = frame * CFrame.new(0, 0, -6) * CFrame.Angles(0, math.pi, 0)
	for _, x in { -4.8, 4.8 } do
		Pieces.window(parent, wall * CFrame.new(x, 6.6, 0) * CFrame.Angles(0, math.pi, 0), 3, 3.2)
	end
	Pieces.block(
		parent,
		frame * CFrame.new(0, 3.3, -6.05),
		Vector3.new(4, 4.8, 0.3),
		C.soot,
		M.metal
	)
	Pieces.smokestack(parent, (frame * CFrame.new(-5, 11, 4)).Position, 18, 3, true)
	Pieces.smokestack(parent, (frame * CFrame.new(1.5, 11, 4.5)).Position, 24, 3.4, true)
	-- the sign hangs on the hub-facing wall, text toward the hub
	local sign = Pieces.framedSign(
		parent,
		frame * CFrame.new(0, 9.7, -6.9),
		12,
		1.8,
		"BOTTLE FOUNDRY",
		nil,
		Palette.sign(C.brass)
	)
	Pieces.glow(sign, L.warm, 16, 1.2)
end

local function waterTower(parent: Instance, bottom: Vector3)
	for i = 0, 3 do
		local d = Geo.dir(i * 90 + 45)
		Pieces.strut(parent, bottom + d * 4, bottom + d * 2.8 + UP * 16, 0.9, C.iron)
	end
	Pieces.strut(
		parent,
		bottom + Geo.dir(45) * 3.4 + UP * 8,
		bottom + Geo.dir(225) * 3.4 + UP * 8,
		0.5,
		C.copper
	)
	Pieces.column(parent, bottom + UP * 16, 7, 8, C.timber, M.planks, true)
	Pieces.column(parent, bottom + UP * 18, 0.7, 8.5, C.iron)
	Pieces.column(parent, bottom + UP * 21, 0.7, 8.5, C.iron)
	Pieces.ball(parent, bottom + UP * 22.5, 7.8, C.patina)
	Pieces.ball(parent, bottom + UP * 26.6, 1.2, C.volt, M.neon)
end

local function sirenMast(parent: Instance, bottom: Vector3, yaw: number)
	local _, _, tip = Pieces.pylon(parent, bottom, 22, yaw, 2.2, 0.7)
	local beacon = Pieces.ball(parent, tip + UP * 1.2, 1.8, C.volt, M.neon)
	Pieces.glow(beacon, C.volt, 18, 1.6)
	local cf = CFrame.new(tip - UP * 3.6) * CFrame.Angles(0, math.rad(yaw), 0)
	for _, s in { -1, 1 } do
		Pieces.pipe(
			parent,
			cf.Position,
			(cf * CFrame.new(s * 3, 0.4, 0)).Position,
			1.4,
			C.ceramic,
			M.ceramic
		)
	end
end

local function weatherHut(parent: Instance, frame: CFrame)
	local roof = Pieces.building(parent, frame, Vector3.new(6, 5, 6), C.ceramic, M.ceramic, C.brass)
	Pieces.gable(parent, roof, 6, 6, 2.2, C.patina, M.metal)
	Pieces.window(parent, frame * CFrame.new(0, 3.4, -3), 2.4, 1.8, C.volt)
	local base = (frame * CFrame.new(2, 0, 2)).Position + UP * (roof.Position.Y - frame.Position.Y)
	Pieces.column(parent, base, 10, 0.6, C.iron)
	local top = base + UP * 10
	for i = 0, 2 do
		Pieces.ball(parent, top + Geo.dir(i * 120) * 1.8, 1, C.copper)
	end
	Pieces.ball(parent, top + UP * 1.4, 1.2, C.volt, M.neon)
	Pieces.wedge(parent, CFrame.new(top + UP * 2.6), Vector3.new(0.2, 1.2, 3), C.brass, M.metal)
end

local function bench(parent: Instance, frame: CFrame)
	Pieces.block(
		parent,
		frame * CFrame.new(0, 1.2, 0),
		Vector3.new(5, 0.5, 1.6),
		C.timber,
		M.planks,
		true
	)
	Pieces.block(
		parent,
		frame * CFrame.new(0, 2.2, 0.7),
		Vector3.new(5, 1.4, 0.3),
		C.timber,
		M.planks
	)
	Pieces.block(parent, frame * CFrame.new(0, 0.5, 0), Vector3.new(4.2, 1, 0.5), C.iron, M.metal)
end

local function garden(parent: Instance, center: Vector3, frame: CFrame, rng: Random)
	Kit.cylinder(parent, center - UP * 0.6, 1.2, 14, { Color = C.brass, Material = M.metal })
	Kit.cylinder(
		parent,
		center - UP * 0.5,
		1.2,
		13,
		{ Color = C.sage, Material = Enum.Material.Grass }
	)
	for i = 1, 4 do
		local a = i * 90 + rng:NextNumber(-15, 15)
		local p = center + Geo.dir(a) * rng:NextNumber(2.5, 4.5) + UP * 0.6
		Pieces.shrub(parent, p, rng, if i % 2 == 0 then C.sage else T.sageDark)
	end
	Pieces.lamp(parent, center + UP * 0.6, 9, L.warm, 22, true)
	bench(parent, frame * CFrame.new(-8.5, 0, 0) * CFrame.Angles(0, math.rad(90), 0))
	bench(parent, frame * CFrame.new(8.5, 0, 0) * CFrame.Angles(0, math.rad(-90), 0))
end

-- Arrow posts by the spawn: up to four arrows per post, one post per four
-- slots, so arrows never pile up or sink however many zones there are.
local function fingerPosts(parent: Instance, ctx: Context, base: Vector3, along: Vector3)
	local slots = Geo.allSlots(ctx)
	local perPost = 4
	local posts = math.ceil(#slots / perPost)
	for p = 1, posts do
		local postBase = base + along * ((p - 1) * 5)
		local first = (p - 1) * perPost + 1
		local last = math.min(#slots, p * perPost)
		local n = last - first + 1
		Pieces.column(parent, postBase, 9 + n * 2.2, 0.9, C.iron, M.metal, true)
		Pieces.column(parent, postBase, 1, 2, C.brass)
		Pieces.ball(parent, postBase + UP * (9.6 + n * 2.2), 1.6, C.volt, M.neon)
		for i = first, last do
			local zone = slots[i]
			local target = zone.slot.hubExit.Position
			local dir = Vector3.new(target.X - postBase.X, 0, target.Z - postBase.Z).Unit
			local y = 8 + (last - i) * 2.2
			Pieces.arrowSign(
				parent,
				postBase + UP * y + dir * 4.3,
				dir,
				7,
				1.8,
				string.upper(slotName(zone)),
				if zone.isTeaser then C.ceramic else zone.color
			)
		end
	end
end

function Hub.buildHub(ctx: Context)
	local parent = ctx.folders.hub
	local floor = ctx.layout.hubFloor
	local R = ctx.layout.hubRadius
	local rng = Geo.rng(ctx, "hub")
	local sb = Geo.spawnBearing(ctx)

	-- spawn: brass pad on the spawn bearing, turned from the coil toward
	-- zone 1's exit so the first frame holds SELL, the coil and zone 1
	local spawnPos = Geo.polar(sb, 41, floor)
	local toCoil = Geo.bearingOf(-spawnPos)
	local firstExit = (ctx.zones[1] or ctx.teaser).slot.hubExit.Position
	local toFirst = Geo.bearingOf(firstExit - spawnPos)
	local turn = math.clamp(Geo.angleDiff(toFirst, toCoil), -36, 36)
	local spawnYaw = toCoil + turn
	local spawnFrame = Geo.facing(spawnPos, spawnPos + Geo.dir(spawnYaw))
	Kit.spawn(parent, spawnFrame * CFrame.new(0, 0.5, 0), Vector3.new(12, 1, 12), {
		Color = C.brass,
		Material = M.plate,
	})
	Kit.cylinder(parent, spawnPos - UP * 0.1, 0.25, 17, {
		Color = C.volt,
		Material = M.neon,
		CanCollide = false,
		CastShadow = false,
	})
	Kit.cylinder(parent, spawnPos - UP * 0.05, 0.3, 15.6, {
		Color = C.iron,
		Material = M.plate,
		CanCollide = false,
		CastShadow = false,
	})

	-- the Grand Coil and the Volt Exchange in front of it
	local crown = grandCoil(parent, floor)
	local caps = voltExchange(parent, floor, sb)
	for i, cap in caps do
		local a = (i - 1.5) * 2
		Pieces.liveCable(ctx, crown + Vector3.new(a * 3, -1, 0), cap, C.volt, 0.5, 5)
	end

	-- wayfinding: trails, bridgeheads and power cables to every exit
	for _, zone in Geo.allSlots(ctx) do
		lightTrail(parent, zone, floor, R)
		local color = if zone.isTeaser then C.ceramic else zone.color
		local top = bridgehead(parent, zone, floor, color)
		if not zone.isTeaser then
			Pieces.liveCable(ctx, crown + UP * 2, top, color, 0.35, 6)
		end
	end
	-- arrow posts on the spawn's far side from zone 1, clear of the lanes
	local postSide = if turn >= 0 then -1 else 1
	local postBase = spawnPos + Geo.dir(sb + 90) * (postSide * 9) + Geo.dir(sb) * 2
	fingerPosts(parent, ctx, postBase, Geo.dir(sb))

	-- props on the quiet bearings
	local lampIndex = 0
	for _, b in Geo.quietBearings(ctx) do
		local onSpawn = math.abs(Geo.angleDiff(b, sb)) < 1
		if not onSpawn then
			local center = Geo.polar(b, 42, floor)
			local frame = Geo.facing(center, Vector3.new(0, floor, 0))
			-- clockwise from the spawn: kiosk, gasometer, foundry, water
			-- tower, siren, weather hut, garden
			local slotIndex = math.floor(((b - sb) % 360) / 45 + 0.5)
			if slotIndex == 1 then
				kiosk(parent, frame)
				Pieces.crate(parent, (frame * CFrame.new(6.5, 0, 2)).Position, 2.2, 20, nil, true)
				Pieces.barrel(parent, (frame * CFrame.new(-6.8, 0, 2.5)).Position, C.patina)
			elseif slotIndex == 2 then
				Pieces.tank(parent, Geo.polar(b, 44, floor), 15, 11, true)
				Pieces.barrel(parent, Geo.polar(b + 9, 46, floor), C.copper)
			elseif slotIndex == 3 then
				foundry(parent, Geo.facing(Geo.polar(b, 45, floor), Vector3.new(0, floor, 0)))
				Pieces.crate(parent, Geo.polar(b - 12, 47, floor), 2.4, 10, nil, true)
				Pieces.crate(parent, Geo.polar(b - 12.5, 49.5, floor), 1.8, 35)
			elseif slotIndex == 4 then
				waterTower(parent, center)
			elseif slotIndex == 5 then
				sirenMast(parent, center, b)
			elseif slotIndex == 6 then
				weatherHut(parent, frame)
			else
				garden(parent, Geo.polar(b, 40, floor), frame, rng)
			end
			-- inner lamp ring, alternating warm and cyan
			lampIndex += 1
			local lampColor = if lampIndex % 2 == 0 then C.volt else L.warm
			Pieces.lamp(parent, Geo.polar(b, 27, floor), 8, lampColor, 20, true)
			-- planter beside it
			local pc = Geo.polar(b, 33.5, floor)
			local pf = Geo.facing(pc, Vector3.new(0, floor, 0))
			Pieces.block(
				parent,
				pf * CFrame.new(0, 0.7, 0),
				Vector3.new(7, 1.4, 2.6),
				C.copper,
				M.metal,
				true
			)
			Pieces.block(
				parent,
				pf * CFrame.new(0, 1.45, 0),
				Vector3.new(6.4, 0.2, 2),
				C.sage,
				Enum.Material.Grass
			)
			Pieces.ball(
				parent,
				(pf * CFrame.new(rng:NextNumber(-1.5, 1.5), 2, 0)).Position,
				rng:NextNumber(1.8, 2.4),
				if rng:NextNumber() < 0.5 then T.sageDark else C.sage,
				Enum.Material.Grass
			)
		end
	end

	-- brass ring around the pavement core (flush on the brick, under the
	-- path strips and trails)
	Kit.cylinder(parent, Vector3.new(0, floor - 0.3, 0), 0.35, 56, {
		Color = C.brass,
		Material = M.metal,
		CanCollide = false,
		CastShadow = false,
	})
	Kit.cylinder(parent, Vector3.new(0, floor - 0.3, 0), 0.38, 53.4, {
		Color = G.pavement,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CastShadow = false,
	})

	-- promenade: brass-capped bollards with dark chains round the plaza
	-- rim, open wherever an exit lane (present or future) or the spawn
	-- ramp meets the rim
	local open = Geo.exitBearings(ctx)
	table.insert(open, sb)
	local prevTop: Vector3? = nil
	local firstTop: Vector3? = nil
	local steps = 32
	for i = 0, steps - 1 do
		local b = i * 360 / steps + 360 / steps / 2
		local blocked = false
		for _, o in open do
			if math.abs(Geo.angleDiff(b, o)) < 9 then
				blocked = true
			end
		end
		if blocked then
			prevTop = nil
		else
			local p = Geo.polar(b, R + 2.5, floor)
			Pieces.column(parent, p, 2.6, 1.2, C.iron, M.metal, true)
			local top = p + UP * 2.2
			if prevTop then
				Pieces.wire(ctx, prevTop, top, 0.6, 0.18)
			elseif i == 0 then
				firstTop = top
			end
			if i == steps - 1 and firstTop then
				Pieces.wire(ctx, top, firstTop, 0.6, 0.18)
			end
			prevTop = top
		end
	end

	-- a little harbour at the foot of the spawn ramp: pier (deck 0.8 over
	-- the beach) and a skiff moored past the shore slope
	do
		local a = Geo.polar(sb, R + 32.5, 0)
		local b = Geo.polar(sb, R + 54, 0)
		Pieces.pier(parent, a, b, BEACH + 0.8, "HARBOUR", SEA_FLOOR)
		local along = Geo.dir(sb)
		local berth = Geo.polar(sb, R + 48, 0) + along:Cross(UP) * 6.5
		Pieces.skiff(parent, CFrame.lookAt(berth + UP * 0.1, berth + along + UP * 0.1))
	end
end

return Hub
