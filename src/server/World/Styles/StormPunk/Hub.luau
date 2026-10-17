--!strict
-- Bottleworks Plaza: the ocean, the hub island, scenery islets with Tesla
-- pylons, and the hub itself (Grand Coil, Volt Exchange sell station,
-- spawn, light trails, bridgeheads, arrow signs and props).
--
-- Every hub prop stands on a "quiet" bearing halfway between the spiral's
-- exit bearings, so zones added later always find their exit free.

local ServerScriptService = game:GetService("ServerScriptService")

local World = ServerScriptService.Server.World
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
local TERRAIN = Enum.Material

local SEA_FLOOR = -20
local UP = Vector3.new(0, 1, 0)

local Hub = {}

local function slotName(zone: ZoneContext): string
	local def = zone.def
	return if def then def.displayName else "Coming Soon"
end

local function slotColor(zone: ZoneContext): Color3
	return zone.color -- the teaser is grey: not open yet
end

local function bearingOf(zone: ZoneContext): number
	return math.deg(zone.slot.angle) % 360
end

-- The quiet bearing closest to south: spawn and sell station live on it.
local function spawnBearing(ctx: Context): number
	local best, bestDiff = 180, math.huge
	for _, b in Geo.quietBearings(ctx) do
		local diff = math.abs(((b - 180 + 180) % 360) - 180)
		if diff < bestDiff then
			best, bestDiff = b, diff
		end
	end
	return best
end

-- Base: ocean, hub island, islets ------------------------------------------------

local function buildOcean(ctx: Context)
	-- sea bed, then the water above it; every land fill afterwards replaces water
	Kit.fillBox(ctx, CFrame.new(0, SEA_FLOOR - 6, 0), Vector3.new(2400, 12, 2400), TERRAIN.Sand)
	Kit.fillBox(
		ctx,
		CFrame.new(0, SEA_FLOOR / 2, 0),
		Vector3.new(2400, -SEA_FLOOR, 2400),
		TERRAIN.Water
	)
end

-- `upperOnly` re-lays just the terrace and plaza (same seed, same shapes):
-- used after the zone landmasses so the hub always wins where shores merge.
local function buildHubIsland(ctx: Context, upperOnly: boolean?)
	local rng = Geo.rng(ctx, "hub-island")
	local R = ctx.layout.hubRadius
	local floor = ctx.layout.hubFloor
	local origin = Vector3.zero

	-- shallows and beach
	local shallows = Land.roundOutline(origin, R + 38, rng, 11, 8)
	local beach = Land.roundOutline(origin, R + 28, rng, 10, 6)
	if not upperOnly then
		Land.fill(ctx, shallows, SEA_FLOOR, -3, TERRAIN.Sand)
		Land.fill(ctx, beach, SEA_FLOOR, 2, TERRAIN.Sand)
	end
	-- green terrace ring halfway up
	Land.cliff(
		ctx,
		Land.clip(Land.roundOutline(origin, R + 18, rng, 10, 4), Geo.landSafe(ctx, floor - 4)),
		SEA_FLOOR,
		floor - 4,
		TERRAIN.Slate,
		{ TERRAIN.Rock },
		TERRAIN.LeafyGrass
	)
	-- plaza block with layered slate cliffs
	Land.cliff(
		ctx,
		Land.clip(Land.roundOutline(origin, R + 8, rng, 12, 3), Geo.landSafe(ctx, floor)),
		SEA_FLOOR,
		floor,
		TERRAIN.Slate,
		{ TERRAIN.Rock },
		TERRAIN.Brick
	)
	-- guaranteed plaza out to past every exit, pavement core
	ctx.terrain:FillCylinder(CFrame.new(0, floor - 2, 0), 4, R + 4, TERRAIN.Brick)
	ctx.terrain:FillCylinder(CFrame.new(0, floor - 2, 0), 4, 27, TERRAIN.Pavement)
	-- paved spokes toward every exit (and the spawn)
	local spokes = {}
	for _, zone in Geo.allSlots(ctx) do
		table.insert(spokes, bearingOf(zone))
	end
	table.insert(spokes, spawnBearing(ctx))
	for _, b in spokes do
		local a = Geo.polar(b, 20, floor - 2)
		local z = Geo.polar(b, R + 4, floor - 2)
		ctx.terrain:FillBlock(
			CFrame.lookAt(a:Lerp(z, 0.5), z),
			Vector3.new(10, 4, (z - a).Magnitude),
			TERRAIN.Pavement
		)
	end
end

-- Little basalt islets on quiet bearings, each carrying a Tesla pylon, all
-- strung together with power lines: the island's "grid".
local function buildIslets(ctx: Context)
	local rng = Geo.rng(ctx, "islets")
	local folder = ctx.folders.decor
	local R = ctx.layout.hubRadius
	local tips: { { bearing: number, a: Vector3, b: Vector3, tip: Vector3 } } = {}
	local harbour = spawnBearing(ctx) -- the harbour pier uses this bearing
	for _, bearing in Geo.quietBearings(ctx) do
		local radius = R + 58 + rng:NextNumber(-4, 8)
		local center = Geo.polar(bearing, radius, 0)
		local size = rng:NextNumber(10, 14)
		if
			math.abs(bearing - harbour) > 1 and Geo.isClear(ctx, center, size + 4, { hub = false })
		then
			Land.fill(
				ctx,
				Land.roundOutline(center, size + 8, rng, 6, 2),
				SEA_FLOOR,
				-2,
				TERRAIN.Sand
			)
			Land.cliff(
				ctx,
				Land.roundOutline(center, size, rng, 6, 2),
				SEA_FLOOR,
				4,
				TERRAIN.Basalt,
				{ TERRAIN.Slate },
				TERRAIN.LeafyGrass
			)
			local yaw = bearing + 90
			local a, b, tip =
				Pieces.pylon(folder, center + Vector3.new(0, 4, 0), rng:NextNumber(26, 32), yaw, 3)
			table.insert(tips, { bearing = bearing, a = a, b = b, tip = tip })
			for _ = 1, 3 do
				local p = center
					+ Vector3.new(
						rng:NextNumber(-1, 1) * size * 0.6,
						4,
						rng:NextNumber(-1, 1) * size * 0.6
					)
				Pieces.rocks(folder, p, rng:NextNumber(1.5, 3), rng, T.rockDark)
			end
			Pieces.tuft(folder, center + Vector3.new(3, 4, -2), rng, C.sage)
			Pieces.tuft(folder, center + Vector3.new(-2, 4, 3), rng, C.sage)
		end
	end
	-- power lines between neighbouring pylons
	for i, from in tips do
		local to = tips[i % #tips + 1]
		if #tips > 1 and ((to.bearing - from.bearing) % 360) <= 100 then
			-- pair the closer crossarm ends
			local fa, fb = from.a, from.b
			local ta, tb = to.a, to.b
			if
				(fa - ta).Magnitude + (fb - tb).Magnitude
				> (fa - tb).Magnitude + (fb - ta).Magnitude
			then
				ta, tb = tb, ta
			end
			Pieces.wire(ctx, fa, ta, 6)
			Pieces.wire(ctx, fb, tb, 6)
		end
	end
end

-- Free-standing basalt sea stacks: big silhouettes that cost no parts.
local function buildSeaStacks(ctx: Context)
	local rng = Geo.rng(ctx, "stacks")
	local count = 0
	local tries = 0
	while count < 9 and tries < 80 do
		tries += 1
		local bearing = rng:NextNumber(0, 360)
		local radius = rng:NextNumber(100, 330)
		local base = Geo.polar(bearing, radius, SEA_FLOOR)
		local r = rng:NextNumber(5, 9)
		if Geo.isClear(ctx, base, r + 22, { hub = false }) then
			count += 1
			local height = -SEA_FLOOR + rng:NextNumber(10, 30)
			Land.fill(ctx, Land.roundOutline(base, r + 6, rng, 5, 2), SEA_FLOOR, -3, TERRAIN.Sand)
			Land.pinnacle(
				ctx,
				base,
				height,
				r,
				rng,
				{ TERRAIN.Basalt, TERRAIN.Slate, TERRAIN.Basalt, TERRAIN.Rock },
				r * 0.55,
				TERRAIN.LeafyGrass
			)
		end
	end
end

function Hub.restoreIsland(ctx: Context)
	buildHubIsland(ctx, true)
end

function Hub.buildBase(ctx: Context)
	buildOcean(ctx)
	buildHubIsland(ctx)
	buildIslets(ctx)
	buildSeaStacks(ctx)
end

-- Hub pieces ---------------------------------------------------------------------------

-- The Grand Coil: the hub's hero landmark. Returns the crown centre.
local function grandCoil(parent: Instance, floor: number): Vector3
	local o = Vector3.new(0, floor, 0)
	Kit.cylinder(parent, o - Vector3.new(0, 0.4, 0), 1, 19, { Color = C.brass, Material = M.metal })
	Kit.cylinder(parent, o, 0.7, 17.5, { Color = C.iron, Material = M.plate })
	local drumBase = o + Vector3.new(0, 0.7, 0)
	Pieces.column(parent, drumBase, 9, 11, C.copper, M.metal, true)
	Pieces.column(parent, drumBase, 1.3, 11.8, C.patina)
	Pieces.column(parent, drumBase + Vector3.new(0, 7.8, 0), 1.4, 12.2, C.patina)
	for i = 0, 3 do
		local d = Geo.dir(i * 90 + 45)
		local cf = CFrame.lookAt(
			drumBase + d * 5.45 + Vector3.new(0, 4.5, 0),
			drumBase + d * 10 + Vector3.new(0, 4.5, 0)
		)
		Pieces.block(parent, cf, Vector3.new(1.2, 4.5, 0.3), C.volt, M.neon)
	end
	local deckY = floor + 10
	Kit.cylinder(
		parent,
		Vector3.new(0, deckY, 0),
		0.8,
		12.6,
		{ Color = C.brass, Material = M.metal }
	)

	-- lattice tower
	local legs: { Vector3 } = {}
	local heads: { Vector3 } = {}
	for i = 0, 3 do
		local d = Geo.dir(i * 90 + 45)
		local foot = d * 5.2 + Vector3.new(0, deckY + 0.8, 0)
		local head = d * 1.9 + Vector3.new(0, floor + 62, 0)
		Pieces.strut(parent, foot, head, 0.8, C.iron)
		table.insert(legs, foot)
		table.insert(heads, head)
	end
	for _, t in { 0.25, 0.5, 0.75 } do
		for i = 1, 4 do
			Pieces.strut(
				parent,
				legs[i]:Lerp(heads[i], t),
				legs[i % 4 + 1]:Lerp(heads[i % 4 + 1], t),
				0.45,
				C.copper
			)
		end
	end
	Pieces.column(parent, Vector3.new(0, deckY + 0.8, 0), 54, 2.2, C.copper)
	for _, y in { 18, 30, 42, 54 } do
		Pieces.insulator(parent, Vector3.new(0, floor + y, 0), 1.25, 3)
	end
	-- crown: copper torus, brass deck, dome, orb and lightning rod
	local crownY = floor + 66
	Kit.cylinder(
		parent,
		Vector3.new(0, crownY - 1.4, 0),
		1.2,
		10.5,
		{ Color = C.brass, Material = M.metal }
	)
	Pieces.torus(parent, Vector3.new(0, crownY, 0), 6.2, 3.4, 14, C.copper)
	Pieces.ball(parent, Vector3.new(0, crownY + 0.6, 0), 8.5, C.patina)
	Pieces.orb(parent, Vector3.new(0, crownY + 6, 0), 5, C.volt, 60, true)
	Pieces.column(parent, Vector3.new(0, crownY + 8, 0), 7, 0.5, C.copper)
	Pieces.ball(parent, Vector3.new(0, crownY + 15.2, 0), 1, C.volt, M.neon)
	return Vector3.new(0, crownY, 0)
end

-- The Volt Exchange: amber pad, marquee SELL gantry, capacitor towers.
-- Returns the capacitor tops (for the coil's cables).
local function voltExchange(parent: Instance, floor: number, bearing: number): { Vector3 }
	local padPos = Geo.polar(bearing, 19, floor)
	local frame = Geo.facing(padPos, Vector3.new(0, floor, 0)) -- -Z toward the coil, +Z toward spawn
	local toSpawn = frame * CFrame.Angles(0, math.pi, 0)

	local pad = Kit.part({
		Name = "SellPad",
		Size = Vector3.new(18, 1, 18),
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

	-- neon border and brass bollards
	local top = 0.2
	for _, e in { { -9, -9, 9, -9 }, { 9, -9, 9, 9 }, { 9, 9, -9, 9 }, { -9, 9, -9, -9 } } do
		local a = (frame * CFrame.new(e[1], top, e[2])).Position
		local b = (frame * CFrame.new(e[3], top, e[4])).Position
		Pieces.trail(parent, a, b, 0.8, C.hazard, M.neon, 0.06)
	end
	for _, c in { { -10, -10 }, { 10, -10 }, { 10, 10 }, { -10, 10 } } do
		local p = (frame * CFrame.new(c[1], 0, c[2])).Position
		Pieces.column(parent, p, 2.2, 1.4, C.brass, M.metal, true)
		Pieces.ball(parent, p + Vector3.new(0, 2.5, 0), 1.1, C.hazard, M.neon)
	end
	-- chevrons from the spawn side toward the pad
	for i = 1, 3 do
		local at = (frame * CFrame.new(0, 0.02, 9 + i * 3.2)).Position
		Pieces.chevron(parent, at, frame.LookVector, 3.2, C.hazard)
	end

	-- gantry with the giant marquee SELL sign
	local signZ = -5
	for _, side in { -1, 1 } do
		local foot = (frame * CFrame.new(side * 12.5, 0, signZ)).Position
		Pieces.column(parent, foot, 25, 2.2, C.copper, M.metal, true)
		Pieces.column(parent, foot, 1.5, 3.2, C.iron)
		Pieces.column(parent, foot + Vector3.new(0, 11, 0), 1, 2.8, C.brass)
		Pieces.insulator(parent, foot + Vector3.new(0, 25, 0), 0.9, 3)
		Pieces.ball(parent, foot + Vector3.new(0, 27.6, 0), 1.6, C.volt, M.neon)
	end
	local header = Pieces.block(
		parent,
		toSpawn * CFrame.new(0, 24.5, -signZ),
		Vector3.new(27, 3, 1.4),
		C.soot,
		Enum.Material.SmoothPlastic
	)
	Kit.faceText(header, Enum.NormalId.Front, "VOLT EXCHANGE", nil, Palette.sign(C.brass))
	Kit.faceText(header, Enum.NormalId.Back, "VOLT EXCHANGE", nil, Palette.sign(C.brass))
	local signCF = toSpawn * CFrame.new(0, 17.5, -signZ)
	local board =
		Pieces.framedSign(parent, signCF, 22, 8, "SELL", "charges for Volts", Palette.marquee())
	Pieces.glow(board, T.warmLight, 26, 2)
	-- marquee bulbs, alternating amber and cyan
	for i = 0, 10 do
		local x = -11 + i * 2.2
		for _, y in { 4.7, -4.7 } do
			local p = (signCF * CFrame.new(x, y, 0)).Position
			Pieces.ball(
				parent,
				p,
				0.8,
				if (i + (if y > 0 then 0 else 1)) % 2 == 0 then C.hazard else C.volt,
				M.neon
			)
		end
	end
	-- lightning bolt emblem on top
	local boltCF = signCF * CFrame.new(0, 9.6, 0)
	Pieces.block(
		parent,
		boltCF * CFrame.new(-0.8, 1.6, 0) * CFrame.Angles(0, 0, math.rad(-28)),
		Vector3.new(1.4, 3.6, 0.8),
		C.hazard,
		M.neon
	)
	Pieces.block(
		parent,
		boltCF * CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, math.rad(62)),
		Vector3.new(1.2, 3, 0.8),
		C.hazard,
		M.neon
	)
	Pieces.block(
		parent,
		boltCF * CFrame.new(0.8, -1.6, 0) * CFrame.Angles(0, 0, math.rad(-28)),
		Vector3.new(1.4, 3.6, 0.8),
		C.hazard,
		M.neon
	)

	-- capacitor towers
	local caps: { Vector3 } = {}
	for _, side in { -1, 1 } do
		local foot = (frame * CFrame.new(side * 15, 0, 3)).Position
		Pieces.column(parent, foot, 1.6, 6, C.iron, M.metal, true)
		local core = Pieces.column(parent, foot + Vector3.new(0, 1.6, 0), 13, 1.7, C.volt, M.neon)
		Pieces.sparks(core, C.volt, 5)
		local glass =
			Pieces.column(parent, foot + Vector3.new(0, 1.6, 0), 13, 4.6, T.glass, M.glass, true)
		glass.Transparency = 0.45
		Pieces.column(parent, foot + Vector3.new(0, 5.5, 0), 0.6, 5, C.brass)
		Pieces.column(parent, foot + Vector3.new(0, 10.5, 0), 0.6, 5, C.brass)
		Pieces.column(parent, foot + Vector3.new(0, 14.6, 0), 1.2, 5.6, C.copper)
		local capTop = Pieces.insulator(parent, foot + Vector3.new(0, 15.8, 0), 0.9, 3)
		local knob = Pieces.ball(parent, capTop + Vector3.new(0, 0.6, 0), 1.6, C.copper)
		Pieces.glow(knob, C.volt, 16, 1.5)
		table.insert(caps, capTop + Vector3.new(0, 0.6, 0))
	end
	return caps
end

-- Gateway arch at a hub exit, in the zone's colour. Returns the pillar tops.
local function bridgehead(parent: Instance, zone: ZoneContext, floor: number): { Vector3 }
	local exit = zone.slot.hubExit
	local color = slotColor(zone)
	local base = exit.Position - exit.LookVector * 3
	local frame = CFrame.lookAt(base, base - exit.LookVector) -- text faces the hub
	local tops: { Vector3 } = {}
	for _, side in { -1, 1 } do
		local foot = (frame * CFrame.new(side * 7, 0, 0)).Position
		Pieces.column(parent, Vector3.new(foot.X, floor, foot.Z), 12, 2, C.copper, M.metal, true)
		Pieces.column(parent, Vector3.new(foot.X, floor, foot.Z), 1.2, 3, C.iron)
		Pieces.column(parent, Vector3.new(foot.X, floor + 6, foot.Z), 0.8, 2.6, C.brass)
		local top = Pieces.insulator(parent, Vector3.new(foot.X, floor + 12, foot.Z), 0.8, 3)
		local lamp = Pieces.ball(parent, top + Vector3.new(0, 0.7, 0), 1.6, color, M.neon)
		Pieces.glow(lamp, color, 14, 1.4)
		table.insert(tops, top + Vector3.new(0, 0.7, 0))
	end
	Pieces.framedSign(
		parent,
		frame * CFrame.new(0, 10, 0),
		11,
		2.8,
		string.upper(slotName(zone)),
		nil,
		Palette.sign(color, true)
	)
	return tops
end

local function lightTrail(parent: Instance, zone: ZoneContext, floor: number, hubRadius: number)
	local b = bearingOf(zone)
	local color = slotColor(zone)
	local from = Geo.polar(b, 10.5, floor)
	local to = Geo.polar(b, hubRadius + 2, floor)
	local side = Geo.dir(b):Cross(UP)
	Pieces.trail(parent, from, to, 1.4, color, M.neon)
	for _, s in { -1, 1 } do
		Pieces.trail(parent, from + side * s * 2.6, to + side * s * 2.6, 0.45, C.brass, M.metal)
	end
	for _, r in { 24, 34 } do
		Pieces.chevron(parent, Geo.polar(b, r, floor), Geo.dir(b), 3.4, color)
	end
end

-- Props on quiet bearings -------------------------------------------------------------

local function kiosk(parent: Instance, frame: CFrame, rng: Random)
	-- frame: on the floor, LookVector toward the hub centre (shop front)
	Pieces.block(
		parent,
		frame * CFrame.new(0, 2.5, 1.5),
		Vector3.new(9, 5, 5),
		C.timber,
		M.planks,
		true
	)
	Pieces.block(
		parent,
		frame * CFrame.new(0, 1.3, -1.6),
		Vector3.new(9.4, 2.6, 1.4),
		C.copper,
		M.metal,
		true
	)
	for i = 0, 4 do
		local x = -4 + i * 2
		Pieces.wedge(
			parent,
			frame * CFrame.new(x, 6.2, -1) * CFrame.Angles(0, math.pi, 0),
			Vector3.new(2, 1.6, 4),
			if i % 2 == 0 then C.patina else C.ceramic,
			M.fabric
		)
	end
	Pieces.block(
		parent,
		frame * CFrame.new(0, 5.2, 2),
		Vector3.new(9.6, 0.5, 6),
		T.copperDark,
		M.metal
	)
	for i = 0, 3 do
		local p = (frame * CFrame.new(-3 + i * 2, 3, -1.6)).Position
		Pieces.ball(parent, p, 0.9, if rng:NextNumber() < 0.5 then C.volt else C.hazard, M.neon)
	end
	local sign = Pieces.framedSign(
		parent,
		frame * CFrame.new(0, 8.4, -0.2),
		8,
		2,
		"BOTTLES",
		nil,
		Palette.sign(C.volt, true)
	)
	Pieces.glow(sign, T.warmLight, 14, 1.2)
end

local function foundry(parent: Instance, frame: CFrame)
	-- frame: on the floor, LookVector toward the hub
	Pieces.block(
		parent,
		frame * CFrame.new(0, 5, 0),
		Vector3.new(16, 10, 12),
		T.copperDark,
		Enum.Material.Brick,
		true
	)
	Pieces.block(
		parent,
		frame * CFrame.new(0, 0.6, 0),
		Vector3.new(16.6, 1.2, 12.6),
		C.iron,
		M.metal
	)
	for i = 0, 2 do
		local x = -5.4 + i * 5.4
		Pieces.wedge(
			parent,
			frame * CFrame.new(x, 12.5, 0) * CFrame.Angles(0, math.rad(90), 0),
			Vector3.new(12, 5, 5.4),
			C.patina,
			M.metal
		)
	end
	for i = 0, 2 do
		local x = -5.4 + i * 5.4
		Pieces.block(
			parent,
			frame * CFrame.new(x, 6.5, -6.05),
			Vector3.new(3.2, 3.2, 0.2),
			C.hazard,
			M.neon
		)
	end
	Pieces.block(
		parent,
		frame * CFrame.new(0, 2.4, -6.05),
		Vector3.new(4, 4.8, 0.3),
		C.soot,
		M.metal
	)
	Pieces.smokestack(parent, (frame * CFrame.new(-5, 10, 4)).Position, 18, 3, true)
	Pieces.smokestack(parent, (frame * CFrame.new(1, 10, 4.5)).Position, 24, 3.4, true)
	local sign = Pieces.framedSign(
		parent,
		frame * CFrame.new(0, 9.4, -6.6) * CFrame.Angles(0, math.pi, 0),
		12,
		1.8,
		"BOTTLE FOUNDRY",
		nil,
		Palette.sign(C.brass)
	)
	Pieces.glow(sign, T.warmLight, 16, 1.2)
end

local function waterTower(parent: Instance, bottom: Vector3)
	for i = 0, 3 do
		local d = Geo.dir(i * 90 + 45)
		Pieces.strut(parent, bottom + d * 4, bottom + d * 2.6 + Vector3.new(0, 16, 0), 0.6, C.iron)
	end
	Pieces.strut(
		parent,
		bottom + Geo.dir(45) * 3.3 + Vector3.new(0, 8, 0),
		bottom + Geo.dir(225) * 3.3 + Vector3.new(0, 8, 0),
		0.4,
		C.copper
	)
	Pieces.strut(
		parent,
		bottom + Geo.dir(135) * 3.3 + Vector3.new(0, 8, 0),
		bottom + Geo.dir(315) * 3.3 + Vector3.new(0, 8, 0),
		0.4,
		C.copper
	)
	Pieces.column(parent, bottom + Vector3.new(0, 16, 0), 7, 8, C.timber, M.planks, true)
	Pieces.column(parent, bottom + Vector3.new(0, 18, 0), 0.6, 8.4, C.iron)
	Pieces.column(parent, bottom + Vector3.new(0, 21, 0), 0.6, 8.4, C.iron)
	Pieces.ball(parent, bottom + Vector3.new(0, 22.5, 0), 7.6, C.patina)
	Pieces.column(parent, bottom + Vector3.new(0, 26, 0), 3, 0.4, C.copper)
end

local function sirenMast(parent: Instance, bottom: Vector3, yaw: number)
	local _, _, tip = Pieces.pylon(parent, bottom, 22, yaw, 2.2)
	Pieces.column(parent, tip - Vector3.new(0, 4.5, 0), 1.6, 3, C.brass)
	local beacon = Pieces.ball(parent, tip - Vector3.new(0, 2, 0), 1.8, C.hazard, M.neon)
	Pieces.glow(beacon, C.hazard, 18, 1.6)
	local cf = CFrame.new(tip - Vector3.new(0, 3.6, 0)) * CFrame.Angles(0, math.rad(yaw), 0)
	for _, s in { -1, 1 } do
		Pieces.pipe(
			parent,
			(cf * CFrame.new(0, 0, 0)).Position,
			(cf * CFrame.new(s * 3, 0.4, 0)).Position,
			1.2,
			C.ceramic,
			M.ceramic
		)
	end
end

local function weatherMast(parent: Instance, frame: CFrame)
	Pieces.block(
		parent,
		frame * CFrame.new(0, 2.5, 0),
		Vector3.new(6, 5, 6),
		C.ceramic,
		Enum.Material.SmoothPlastic,
		true
	)
	Pieces.wedge(parent, frame * CFrame.new(0, 6, 1.5), Vector3.new(6.6, 2, 3.3), C.patina, M.metal)
	Pieces.wedge(
		parent,
		frame * CFrame.new(0, 6, -1.5) * CFrame.Angles(0, math.pi, 0),
		Vector3.new(6.6, 2, 3.3),
		C.patina,
		M.metal
	)
	Pieces.block(parent, frame * CFrame.new(0, 3, -3.05), Vector3.new(2.6, 2, 0.2), C.volt, M.neon)
	local base = (frame * CFrame.new(2, 7, 2)).Position
	Pieces.column(parent, base, 10, 0.5, C.iron)
	local top = base + Vector3.new(0, 10, 0)
	for i = 0, 2 do
		local d = Geo.dir(i * 120)
		Pieces.strut(parent, top, top + d * 2, 0.2, C.brass)
		Pieces.ball(parent, top + d * 2, 0.9, C.copper)
	end
	Pieces.ball(parent, top + Vector3.new(0, 1.4, 0), 1.2, C.volt, M.neon)
	Pieces.wedge(
		parent,
		CFrame.new(top + Vector3.new(0, 2.6, 0)),
		Vector3.new(0.2, 1.2, 3),
		C.brass,
		M.metal
	)
end

local function bench(parent: Instance, frame: CFrame)
	Pieces.block(
		parent,
		frame * CFrame.new(0, 1.2, 0),
		Vector3.new(5, 0.4, 1.6),
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
	for _, s in { -1, 1 } do
		Pieces.block(
			parent,
			frame * CFrame.new(s * 2.1, 0.6, 0),
			Vector3.new(0.4, 1.2, 1.4),
			C.iron,
			M.metal
		)
	end
end

local function garden(parent: Instance, ctx: Context, center: Vector3, frame: CFrame, rng: Random)
	ctx.terrain:FillCylinder(
		CFrame.new(center.X, center.Y - 2, center.Z),
		4,
		6.5,
		TERRAIN.LeafyGrass
	)
	Kit.cylinder(
		parent,
		center - Vector3.new(0, 0.6, 0),
		1.2,
		14,
		{ Color = C.brass, Material = M.metal }
	)
	Kit.cylinder(
		parent,
		center - Vector3.new(0, 0.5, 0),
		1.2,
		13,
		{ Color = C.sage, Material = Enum.Material.Grass }
	)
	for i = 1, 5 do
		local a = i * 72 + rng:NextNumber(-15, 15)
		local p = center + Geo.dir(a) * rng:NextNumber(1.5, 4.5) + Vector3.new(0, 0.6, 0)
		Pieces.shrub(parent, p, rng, if i % 2 == 0 then C.sage else T.sageDark)
	end
	Pieces.lamp(parent, center + Vector3.new(0, 0.6, 0), 9, T.warmLight, 22)
	bench(parent, frame * CFrame.new(-8.5, 0, 0) * CFrame.Angles(0, math.rad(90), 0))
	bench(parent, frame * CFrame.new(8.5, 0, 0) * CFrame.Angles(0, math.rad(-90), 0))
end

local function fingerPost(parent: Instance, ctx: Context, base: Vector3)
	Pieces.column(parent, base, 12.5, 0.9, C.iron, M.metal, true)
	Pieces.column(parent, base, 1, 2, C.brass)
	Pieces.ball(parent, base + Vector3.new(0, 13, 0), 1.6, C.volt, M.neon)
	local slots = Geo.allSlots(ctx)
	for i, zone in slots do
		local target = zone.slot.hubExit.Position
		local dir = Vector3.new(target.X - base.X, 0, target.Z - base.Z).Unit
		local y = 11 - (i - 1) * 2.4
		Pieces.arrowSign(
			parent,
			base + Vector3.new(0, y, 0) + dir * 4.3,
			dir,
			7,
			1.8,
			string.upper(slotName(zone)),
			slotColor(zone)
		)
	end
end

function Hub.buildHub(ctx: Context)
	local parent = ctx.folders.hub
	local floor = ctx.layout.hubFloor
	local R = ctx.layout.hubRadius
	local rng = Geo.rng(ctx, "hub")
	local sb = spawnBearing(ctx)

	-- spawn: brass pad facing the Volt Exchange and the coil
	local spawnPos = Geo.polar(sb, 41, floor)
	local spawnFrame = Geo.facing(spawnPos, Vector3.new(0, floor, 0))
	Kit.spawn(parent, spawnFrame * CFrame.new(0, 0.5, 0), Vector3.new(12, 1, 12), {
		Color = C.brass,
		Material = M.plate,
	})
	Kit.cylinder(parent, spawnPos - Vector3.new(0, 0.1, 0), 0.25, 17, {
		Color = C.volt,
		Material = M.neon,
		CanCollide = false,
		CastShadow = false,
	})
	Kit.cylinder(parent, spawnPos - Vector3.new(0, 0.05, 0), 0.3, 15.6, {
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
		Pieces.liveCable(ctx, crown + Vector3.new(a * 2.4, 0, 3), cap, C.volt, 0.45, 4)
	end

	-- wayfinding: trails, bridgeheads and power cables to every exit
	for _, zone in Geo.allSlots(ctx) do
		lightTrail(parent, zone, floor, R)
		local tops = bridgehead(parent, zone, floor)
		Pieces.liveCable(ctx, crown, tops[1], slotColor(zone), 0.3, 6)
	end
	local postBase = spawnPos + spawnFrame.LookVector * 9 + spawnFrame.RightVector * 8
	fingerPost(parent, ctx, postBase)

	-- props on the quiet bearings
	for _, b in Geo.quietBearings(ctx) do
		if math.abs(((b - sb + 180) % 360) - 180) > 1 then
			local center = Geo.polar(b, 42, floor)
			local frame = Geo.facing(center, Vector3.new(0, floor, 0))
			-- clockwise from the spawn: kiosk, gasometer, foundry, water
			-- tower, siren, weather mast, garden
			local slotIndex = math.floor(((b - sb) % 360) / 45 + 0.5)
			if slotIndex == 1 then
				kiosk(parent, frame, rng)
			elseif slotIndex == 2 then
				Pieces.tank(parent, Geo.polar(b, 44, floor), 15, 11, true)
			elseif slotIndex == 3 then
				foundry(parent, Geo.facing(Geo.polar(b, 45, floor), Vector3.new(0, floor, 0)))
			elseif slotIndex == 4 then
				waterTower(parent, center)
			elseif slotIndex == 5 then
				sirenMast(parent, center, b)
			elseif slotIndex == 6 then
				weatherMast(parent, frame)
			else
				garden(parent, ctx, Geo.polar(b, 40, floor), frame, rng)
			end
		end
		-- inner lamp ring
		Pieces.lamp(parent, Geo.polar(b, 27, floor), 8, if b < 180 then T.warmLight else C.volt, 20)
	end

	-- brass ring around the pavement core (flush, under the trails)
	Kit.cylinder(parent, Vector3.new(0, floor - 0.3, 0), 0.34, 56, {
		Color = C.brass,
		Material = M.metal,
		CanCollide = false,
		CastShadow = false,
	})
	Kit.cylinder(parent, Vector3.new(0, floor - 0.26, 0), 0.33, 53.4, {
		Color = Color3.fromRGB(150, 148, 140),
		Material = Enum.Material.Pavement,
		CanCollide = false,
		CastShadow = false,
	})

	-- promenade: brass bollards with dark chains round the plaza rim,
	-- open wherever a trail or the spawn meets the rim
	local open = { sb }
	for _, zone in Geo.allSlots(ctx) do
		table.insert(open, bearingOf(zone))
	end
	local prevTop: Vector3? = nil
	local firstTop: Vector3? = nil
	local steps = 40
	for i = 0, steps - 1 do
		local b = i * 360 / steps
		local blocked = false
		for _, o in open do
			if math.abs(((b - o + 180) % 360) - 180) < 10 then
				blocked = true
			end
		end
		if blocked then
			prevTop = nil
		else
			local p = Geo.polar(b, R + 2.5, floor)
			Pieces.column(parent, p, 2.4, 1, C.iron, M.metal, true)
			Pieces.ball(parent, p + Vector3.new(0, 2.6, 0), 0.9, C.brass)
			local top = p + Vector3.new(0, 2.1, 0)
			if prevTop then
				Pieces.wire(ctx, prevTop, top, 0.6, 0.16)
			elseif i == 0 then
				firstTop = top
			end
			if i == steps - 1 and firstTop then
				Pieces.wire(ctx, top, firstTop, 0.6, 0.16)
			end
			prevTop = top
		end
	end

	-- flower planters beside the inner lamps
	for _, b in Geo.quietBearings(ctx) do
		if math.abs(((b - sb + 180) % 360) - 180) > 1 then
			local center = Geo.polar(b, 34, floor)
			local frame = Geo.facing(center, Vector3.new(0, floor, 0))
			Pieces.block(
				parent,
				frame * CFrame.new(0, 0.7, 0),
				Vector3.new(7, 1.4, 2.6),
				C.copper,
				M.metal,
				true
			)
			Pieces.block(
				parent,
				frame * CFrame.new(0, 1.45, 0),
				Vector3.new(6.4, 0.2, 2),
				C.sage,
				Enum.Material.Grass
			)
			for _, x in { -2, 0.2, 2.2 } do
				Pieces.ball(
					parent,
					(frame * CFrame.new(x, 1.9, rng:NextNumber(-0.3, 0.3))).Position,
					rng:NextNumber(1.2, 1.8),
					if rng:NextNumber() < 0.5 then T.sageDark else C.sage,
					Enum.Material.Grass
				)
			end
		end
	end

	-- a little harbour below the spawn: pier, moored skiff, buoys
	do
		local a = Geo.polar(sb, R + 24, 0)
		local b = Geo.polar(sb, R + 46, 0)
		Pieces.pier(parent, a, b, 2.6, "HARBOUR")
		local along = Geo.dir(sb)
		local berth = Geo.polar(sb, R + 38, 0) + along:Cross(Vector3.new(0, 1, 0)) * 6.5
		Pieces.skiff(
			parent,
			CFrame.lookAt(berth + Vector3.new(0, 0.1, 0), berth + along + Vector3.new(0, 0.1, 0))
		)
	end

	-- small dressing around the rim: crates, barrels, tufts
	for _, b in Geo.quietBearings(ctx) do
		for _ = 1, 2 do
			local a = b + rng:NextNumber(-12, 12)
			local p = Geo.polar(a, rng:NextNumber(50, 54), floor)
			if Geo.isClear(ctx, p, 2, { hub = false }) and (p - spawnPos).Magnitude > 10 then
				if rng:NextNumber() < 0.5 then
					Pieces.crate(parent, p, rng:NextNumber(1.8, 2.6), rng:NextNumber(0, 90))
				else
					Pieces.barrel(parent, p, if rng:NextNumber() < 0.5 then C.patina else C.copper)
				end
			end
		end
	end
	-- shrubs and rocks on the green terrace below the plaza
	for _ = 1, 26 do
		local a = rng:NextNumber(0, 360)
		local p = Geo.polar(a, R + rng:NextNumber(9, 13), floor - 4)
		if Geo.isClear(ctx, p, 2, { hub = false }) then
			if rng:NextNumber() < 0.6 then
				Pieces.shrub(parent, p, rng, if rng:NextNumber() < 0.5 then C.sage else T.sageDark)
			else
				Pieces.rocks(parent, p, rng:NextNumber(1.5, 2.8), rng)
			end
		end
	end
end

return Hub
