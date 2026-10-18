--!strict
-- Barometer Bay harbour: the sea, the hub island and the village square.
-- The red-and-white lighthouse stands in the middle of a cobbled plaza;
-- the Volt Exchange (sell station) is at its door facing the spawn. A
-- ring of cottages and research domes sits between the boardwalk
-- directions of every possible future zone, so new zones never hit a
-- building; a harbour with a brick mole, a slipway, a pier and boats sits
-- on the coast. The island is part-built (Land): a grass 14-gon on earth
-- and stone bands, a sand ring and wedge beach slopes.

local ServerScriptService = game:GetService("ServerScriptService")

local Blocks = require(ServerScriptService.Server.World.Blocks)
local Kit = require(ServerScriptService.Server.World.Kit)
local Geo = require(script.Parent.Geo)
local Land = require(script.Parent.Land)
local Palette = require(script.Parent.Palette)
local Pieces = require(script.Parent.Pieces)
local WLTypes = require(script.Parent.WLTypes)

type Context = WLTypes.Context
type ZoneContext = WLTypes.ZoneContext

local C = Palette.colors
local G = Palette.ground

local Hub = {}

local SELL_DISTANCE = 27 -- pad centre from the lighthouse
local SPAWN_DISTANCE = 52
local RING_RADIUS = 54 -- village buildings
local BEACH_TOP = 1.2 -- the sand ring round the island
local MOLE_TOP = BEACH_TOP + 1 -- one step up from the beach

-- Directions -------------------------------------------------------------------

-- Angles (degrees) of every boardwalk the spiral will ever use (the first
-- 16 slots), so the hub keeps them all clear.
local function corridorAngles(ctx: Context): { number }
	local layout = ctx.layout
	local angles: { number } = {}
	for i = 1, 16 do
		local a = (layout.firstAngle + (i - 1) * layout.angleStep) % 360
		local seen = false
		for _, b in angles do
			if Geo.angleDiff(a, b) < 1 then
				seen = true
			end
		end
		if not seen then
			table.insert(angles, a)
		end
	end
	table.sort(angles)
	return angles
end

-- Midpoints between neighbouring corridors, with the half-width of each gap.
local function gapAngles(corridors: { number }): { { angle: number, half: number } }
	local gaps = {}
	for i, a in corridors do
		local b = corridors[i % #corridors + 1]
		local span = (b - a) % 360
		if span < 1e-3 then
			span = 360
		end
		table.insert(gaps, { angle = (a + span / 2) % 360, half = span / 2 })
	end
	return gaps
end

local function exitAngles(ctx: Context): { number }
	local list = {}
	for _, zone in ctx.zones do
		table.insert(list, math.deg(zone.slot.angle) % 360)
	end
	table.insert(list, math.deg(ctx.teaser.slot.angle) % 360)
	return list
end

-- The spawn faces the lighthouse from the gap between the first two zones.
local function spawnAngle(ctx: Context, gaps: { { angle: number, half: number } }): number
	local target
	if #ctx.zones >= 2 then
		local a = math.deg(ctx.zones[1].slot.angle)
		local b = math.deg(ctx.zones[2].slot.angle)
		local d = ((b - a + 180) % 360) - 180
		target = (a + d / 2) % 360
	else
		target = (math.deg(ctx.teaser.slot.angle) + 180) % 360
	end
	local best, bestDiff = gaps[1].angle, math.huge
	for _, g in gaps do
		local diff = Geo.angleDiff(g.angle, target)
		if diff < bestDiff then
			best, bestDiff = g.angle, diff
		end
	end
	return best
end

-- The gap furthest from every current boardwalk (and not the spawn).
local function coveAngle(
	ctx: Context,
	gaps: { { angle: number, half: number } },
	spawnA: number
): number
	local exits = exitAngles(ctx)
	local best, bestScore = gaps[1].angle, -1
	for _, g in gaps do
		if Geo.angleDiff(g.angle, spawnA) > 1 then
			local score = math.huge
			for _, e in exits do
				score = math.min(score, Geo.angleDiff(g.angle, e))
			end
			if score > bestScore then
				best, bestScore = g.angle, score
			end
		end
	end
	return best
end

-- Is a world point clear of every zone island and the teaser (by `margin`)?
local function clearOfZones(ctx: Context, p: Vector3, margin: number): boolean
	local all = table.clone(ctx.zones)
	table.insert(all, ctx.teaser)
	for _, zone in all do
		local l = Geo.toLocal(zone, p)
		if Geo.outside(zone, l.X, l.Z) < margin then
			return false
		end
	end
	return true
end

-- Base: sea and hub island ---------------------------------------------------------

-- The harbour mole: from the beach beside the pier outward, then a hook
-- part-way across the mouth. Pairs of points at sea level.
local function moleSegments(ctx: Context, coveA: number): { { Vector3 } }
	local R = ctx.layout.hubRadius
	local dir = Geo.dir(coveA)
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local root = dir * (R + 12) + right * 17
	local elbow = dir * (R + 40) + right * 15
	local tip = dir * (R + 44) + right * 4
	return { { root, elbow }, { elbow, tip } }
end

-- A paving slab with its top `lift` studs over the hub floor.
local function slab(
	parent: Instance,
	color: Color3,
	cframe: CFrame,
	size: Vector2,
	lift: number,
	name: string
)
	local floor = cframe.Position.Y
	local p = cframe.Position
	Blocks.box(
		parent,
		color,
		CFrame.new(p.X, floor + lift - 0.3, p.Z) * cframe.Rotation,
		Vector3.new(size.X, 0.6, size.Y),
		{ Color = color, Name = name }
	)
end

function Hub.buildBase(ctx: Context)
	local floor = ctx.layout.hubFloor
	local R = ctx.layout.hubRadius
	local exits = exitAngles(ctx)
	local corridors = corridorAngles(ctx)
	local gaps = gapAngles(corridors)
	local spawnA = spawnAngle(ctx, gaps)
	local coveA = coveAngle(ctx, gaps, spawnA)
	local ground = Land.folder(ctx, "Hub")

	Land.sea(ctx)

	-- hub island: grass top, earth and stone bands, a sand ring and slopes
	Land.island(ctx, "Hub", CFrame.new(0, floor, 0), {
		cap = G.grass,
		strata = { G.earth, G.rock },
		apothem = Land.HUB_CAP,
		sides = Land.HUB_SIDES,
		layer = 3,
		inset = 2,
		beach = G.sand,
		beachTop = BEACH_TOP,
		beachWidth = 7,
		slope = G.beach,
	})

	-- plaza: a cobbled 12-gon with a brick kerb; cream flagstone squares
	-- sit off-centre where the paths meet (no rings, so it never reads as a
	-- target from above): a wide market square on the harbour side, a
	-- smaller one at the lighthouse foot toward the spawn and one by each
	-- boardwalk exit (the trail spokes taper into them)
	local plazaYaw = CFrame.Angles(0, math.rad(spawnA + 15), 0)
	Blocks.disc(
		ground,
		G.cobble,
		CFrame.new(0, floor + 0.2, 0) * plazaYaw,
		37,
		0.6,
		12,
		{ Color = G.cobble, Name = "Plaza" }
	)
	Blocks.ring(
		ground,
		G.brick,
		CFrame.new(0, floor + 0.1, 0) * plazaYaw,
		39.5,
		3.5,
		0.5,
		12,
		{ Color = G.brick, Name = "Kerb" }
	)
	local function square(at: Vector3, size: number, yaw: number, color: Color3, lift: number)
		slab(
			ground,
			color,
			CFrame.new(at.X, floor, at.Z) * CFrame.Angles(0, math.rad(yaw), 0),
			Vector2.new(size, size),
			lift,
			"Square"
		)
	end
	square(Geo.polar(coveA + 8, 30, 0), 22, coveA + 17, G.limestone, 0.3)
	square(Geo.polar(coveA + 8, 30, 0), 12, coveA + 17, G.brick, 0.4)
	square(Geo.polar(spawnA - 25, 15, 0), 14, spawnA + 30, G.limestone, 0.3)
	for _, e in exits do
		square(Geo.polar(e + 9, 27, 0), 9, e + 25, G.limestone, 0.3)
	end

	-- an L-shaped brick mole hugging one side of the harbour and hooking
	-- across the mouth, one step up from the beach (its light is placed
	-- by the harbour dressing)
	local moleHeight = MOLE_TOP - Land.SEABED
	for _, seg in moleSegments(ctx, coveA) do
		local a, b = seg[1], seg[2]
		local m = (a + b) / 2
		local y = Land.SEABED + moleHeight / 2
		Blocks.box(
			ground,
			G.brick,
			CFrame.lookAt(Vector3.new(m.X, y, m.Z), Vector3.new(b.X, y, b.Z)),
			Vector3.new(5, moleHeight, (b - a).Magnitude + 4),
			{ Color = G.brick, Name = "Mole" }
		)
	end
	-- a stone slipway from the grass down into the harbour: the way back
	-- up for anyone who falls in
	local slipA = coveA - 12
	local slipRun = (floor - Land.SEABED) * 2.05
	Blocks.ramp(
		ground,
		Palette.stone,
		Geo.polar(slipA, Land.HUB_CAP + slipRun, Land.SEABED),
		Geo.polar(slipA, Land.HUB_CAP, floor),
		8,
		{ Name = "Slipway" }
	)

	-- sea-stack islets in the bay, clear of every zone island
	local placed = 0
	for i, g in gaps do
		local r = R + 70 + (i % 3) * 14
		local p = Geo.polar(g.angle, r, 0)
		if placed < 4 and Geo.angleDiff(g.angle, coveA) > 1 and clearOfZones(ctx, p, 48) then
			placed += 1
			Blocks.disc(
				ground,
				G.beach,
				CFrame.new(p.X, 1, p.Z) * CFrame.Angles(0, ctx.rng:NextNumber(0, math.pi), 0),
				ctx.rng:NextNumber(7, 9),
				1 - Land.SEABED,
				7,
				{ Color = G.beach, Name = "Islet" }
			)
			Land.stack(
				ctx,
				ground,
				{ G.slate, G.rock },
				Vector3.new(p.X + 1.5, 1, p.Z - 1),
				ctx.rng:NextNumber(7, 9),
				ctx.rng:NextNumber(10, 17),
				5,
				G.meadow
			)
		end
	end
end

-- Lighthouse --------------------------------------------------------------------------

local function lighthouse(ctx: Context, parent: Instance, floor: number, doorDir: Vector3): Vector3
	local o = Vector3.new(0, floor, 0)
	Pieces.cyl(
		parent,
		o - Vector3.new(0, 0.4, 0),
		1.4,
		25,
		Palette.stone,
		Enum.Material.Cobblestone
	)
	local base = o + Vector3.new(0, 1, 0)
	Pieces.cyl(parent, base, 6, 19, C.sailcloth, Enum.Material.Plaster)
	Pieces.cyl(
		parent,
		base + Vector3.new(0, 5.6, 0),
		0.9,
		19.8,
		C.beacon,
		Enum.Material.SmoothPlastic
	)
	-- banded tower
	local y = base.Y + 6.5
	local segments = 6
	for i = 0, segments - 1 do
		local d = 14.6 - i * 0.75
		Pieces.cyl(
			parent,
			Vector3.new(0, y, 0),
			6.5,
			d,
			if i % 2 == 0 then C.beacon else C.sailcloth,
			Enum.Material.SmoothPlastic
		)
		if i % 2 == 1 then
			local w = Pieces.box(
				parent,
				CFrame.lookAt(Vector3.new(0, y + 3.2, 0), doorDir * 10 + Vector3.new(0, y + 3.2, 0))
					* CFrame.new(0, 0, -d / 2 + 0.05),
				Vector3.new(1.4, 2, 0.3),
				Palette.window
			)
			Pieces.glow(w, Palette.window)
		end
		y += 6.5
	end
	-- gallery and railing
	Pieces.cyl(parent, Vector3.new(0, y, 0), 1, 16, C.ink, Enum.Material.Metal)
	local railY = y + 1
	local posts = 10
	for i = 0, posts - 1 do
		local a = i / posts * math.pi * 2
		local p = Vector3.new(math.cos(a) * 7.6, railY, math.sin(a) * 7.6)
		Pieces.cyl(parent, p, 2.4, 0.3, C.ink, Enum.Material.Metal, false)
		local b = (i + 1) / posts * math.pi * 2
		Kit.cable(
			ctx,
			p + Vector3.new(0, 2.3, 0),
			Vector3.new(math.cos(b) * 7.6, railY + 2.3, math.sin(b) * 7.6),
			{
				Color = C.ink,
				Width = 0.22,
			}
		)
	end
	-- lantern room with the storm lens
	local lanternBottom = Vector3.new(0, railY, 0)
	local glass = Pieces.cyl(
		parent,
		lanternBottom,
		7,
		9,
		C.spark:Lerp(C.sailcloth, 0.6),
		Enum.Material.Glass,
		false
	)
	glass.Transparency = 0.4
	for i = 0, 3 do
		local a = i / 4 * math.pi * 2 + math.pi / 4
		Pieces.box(
			parent,
			CFrame.new(math.cos(a) * 4.45, railY + 3.5, math.sin(a) * 4.45),
			Vector3.new(0.4, 7, 0.4),
			C.ink,
			Enum.Material.Metal,
			false
		)
	end
	local lens = Pieces.glow(
		Pieces.ball(parent, lanternBottom + Vector3.new(0, 3.5, 0), 4.4, C.spark),
		C.spark
	)
	Kit.light(lens, C.spark, 60, 2.2)
	Kit.emitter(lens, {
		Texture = Kit.TEXTURES.sparkle,
		Rate = 6,
		Lifetime = NumberRange.new(0.5, 1),
		Speed = NumberRange.new(3, 6),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new(0.9),
		LightEmission = 1,
		Color = ColorSequence.new(C.spark),
	})
	-- stepped red roof, vane and lightning rod
	local roofY = railY + 7
	local roof = { { 1, 10.6 }, { 1.4, 8.2 }, { 1.4, 5.8 }, { 1.2, 3.2 } }
	for _, r in roof do
		Pieces.cyl(
			parent,
			Vector3.new(0, roofY, 0),
			r[1],
			r[2],
			C.beacon,
			Enum.Material.SmoothPlastic
		)
		roofY += r[1]
	end
	Pieces.ball(
		parent,
		Vector3.new(0, roofY + 0.4, 0),
		1.6,
		C.beacon,
		Enum.Material.SmoothPlastic,
		false
	)
	Pieces.weatherVane(parent, Vector3.new(0, roofY + 1, 0), 1.6)
	local rod = Vector3.new(0, roofY + 4.4, 0)
	Pieces.cyl(parent, rod, 4, 0.3, C.ink, Enum.Material.Metal, false)
	Pieces.glow(Pieces.ball(parent, rod + Vector3.new(0, 4.2, 0), 0.8, C.spark), C.spark)
	-- door and name board toward the spawn
	local doorCf = CFrame.lookAt(base, base + doorDir) * CFrame.new(0, 2.9, -9.3)
	Pieces.box(parent, doorCf, Vector3.new(4.6, 6, 0.6), C.piling, Enum.Material.Wood)
	Pieces.box(
		parent,
		doorCf * CFrame.new(0, -0.3, -0.2),
		Vector3.new(3.4, 5.2, 0.4),
		C.seafoam,
		Enum.Material.Wood
	)
	-- text on the face toward the spawn (doorCf looks out of the door)
	Kit.sign(parent, doorCf * CFrame.new(0, 4.4, -0.5), 9, 1.6, "VOLT EXCHANGE", nil, Palette.SIGN)
	return lanternBottom + Vector3.new(0, 3.5, 0)
end

-- Sell station ----------------------------------------------------------------------

-- "SELL" painted on the pad, readable from both ends.
local function paintSell(pad: BasePart)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.MaxDistance = 600
	gui.Parent = pad
	for i, rotation in { 0, 180 } do
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(0.9, 0.42)
		label.Position = UDim2.fromScale(0.05, if i == 1 then 0.53 else 0.05)
		label.Rotation = rotation
		label.Font = Enum.Font.LuckiestGuy
		label.TextScaled = true
		label.TextColor3 = C.beacon
		label.Text = "SELL"
		label.Parent = gui
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 6
		stroke.Color = C.sailcloth
		stroke.Parent = label
	end
end

local function sellStation(
	ctx: Context,
	parent: Instance,
	floor: number,
	dir: Vector3,
	lens: Vector3
)
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local center = dir * SELL_DISTANCE + Vector3.new(0, floor, 0)
	local cf = CFrame.lookAt(center, center + dir)
	Pieces.box(
		parent,
		cf * CFrame.new(0, 0.1, 0),
		Vector3.new(28, 0.8, 28),
		C.ink,
		Enum.Material.SmoothPlastic
	)
	local pad = Kit.part({
		Name = "SellPad",
		Size = Vector3.new(24, 1, 24),
		CFrame = cf * CFrame.new(0, 0.5, 0),
		Color = C.slicker,
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})
	pad.CanTouch = false
	paintSell(pad)
	Kit.sellArea(parent, pad, 12)
	-- glowing cyan edge around the pad
	for _, e in
		{
			{ 0, 12.7, 25.8, 0.7 },
			{ 0, -12.7, 25.8, 0.7 },
			{ 12.7, 0, 0.7, 24 },
			{ -12.7, 0, 0.7, 24 },
		}
	do
		local strip = Pieces.box(
			parent,
			cf * CFrame.new(e[1], 0.58, e[2]),
			Vector3.new(e[3], 0.2, e[4]),
			C.spark,
			nil,
			false
		)
		Pieces.glow(strip, C.spark)
	end
	-- striped arch with the giant SELL board
	local tops = {}
	for _, side in { -1, 1 } do
		local bottom = center + right * side * 15.6
		Pieces.cyl(parent, bottom, 1.2, 3.4, Palette.stone, Enum.Material.Cobblestone)
		local top = Pieces.stripedPole(
			parent,
			bottom + Vector3.new(0, 1.2, 0),
			23,
			2.2,
			{ C.beacon, C.sailcloth },
			8
		)
		local globe = Pieces.glow(
			Pieces.ball(parent, top + Vector3.new(0, 1.6, 0), 1.8, C.slicker),
			C.slicker
		)
		Kit.light(globe, Palette.lamp, 22, 1.6)
		table.insert(tops, top)
	end
	local beamCenter = (tops[1] + tops[2]) / 2 + Vector3.new(0, 0.3, 0)
	local crossbar = Pieces.box(
		parent,
		CFrame.lookAt(beamCenter, beamCenter + dir),
		Vector3.new(33, 1.2, 1.2),
		C.piling,
		Enum.Material.Wood,
		false
	)
	Kit.spotLight(crossbar, C.slicker, 32, 2.2, 70, Enum.NormalId.Bottom)
	local boardCenter = beamCenter + Vector3.new(0, 4.2, 0)
	Pieces.signBoard(
		parent,
		CFrame.lookAt(boardCenter, boardCenter + dir),
		24,
		7.2,
		"SELL",
		"Bottled lightning for Volts",
		Palette.SELL_SIGN,
		nil,
		{ title = "SELL", subtitle = "Bottled lightning for Volts" }
	)
	-- neon lightning bolt on top of the board
	local boltCf = CFrame.lookAt(
		boardCenter + Vector3.new(0, 5.8, 0),
		boardCenter + Vector3.new(0, 5.8, 0) + dir
	)
	for _, b in { { -0.5, 0.9, 25 }, { 0.5, -0.9, 25 }, { 0, 0, -50 } } do
		local part = Pieces.box(
			parent,
			boltCf * CFrame.new(b[1], b[2], 0) * CFrame.Angles(0, 0, math.rad(b[3])),
			Vector3.new(0.9, if b[3] < 0 then 1.6 else 2.4, 0.5),
			C.slicker,
			nil,
			false
		)
		Pieces.glow(part, C.slicker)
	end
	-- charge tanks wired up to the lighthouse lens
	for i, side in { -1, 1 } do
		local bottom = dir * 9 + right * side * 15 + Vector3.new(0, floor, 0)
		Pieces.cyl(parent, bottom, 1, 4.6, C.harbor, Enum.Material.Metal)
		local glass = Pieces.cyl(
			parent,
			bottom + Vector3.new(0, 1, 0),
			7,
			3.8,
			C.sailcloth,
			Enum.Material.Glass
		)
		glass.Transparency = 0.45
		local core = Pieces.glow(
			Pieces.cyl(parent, bottom + Vector3.new(0, 1.3, 0), 6.4, 1.8, C.spark),
			C.spark
		)
		Pieces.cyl(parent, bottom + Vector3.new(0, 8, 0), 0.8, 4.2, C.harbor, Enum.Material.Metal)
		Pieces.ball(
			parent,
			bottom + Vector3.new(0, 9, 0),
			1.2,
			C.slicker,
			Enum.Material.Metal,
			false
		)
		Kit.emitter(core, {
			Texture = Kit.TEXTURES.sparkle,
			Rate = 5,
			Lifetime = NumberRange.new(0.4, 0.9),
			Speed = NumberRange.new(1, 2),
			SpreadAngle = Vector2.new(30, 30),
			Size = NumberSequence.new(0.5),
			LightEmission = 1,
			Color = ColorSequence.new(C.spark),
			EmissionDirection = Enum.NormalId.Top,
		})
		if i == 1 then
			Kit.light(core, C.spark, 18, 1.4)
		end
		Kit.cable(ctx, bottom + Vector3.new(0, 9.2, 0), lens - dir * 3 + right * side * 2, {
			Color = C.spark,
			Width = 0.35,
			CurveSize = 4,
			LightEmission = 1,
		})
	end
end

-- Spawn and wayfinding ----------------------------------------------------------------

local function spawnDeck(parent: Instance, floor: number, dir: Vector3)
	local at = dir * SPAWN_DISTANCE + Vector3.new(0, floor, 0)
	Pieces.cyl(parent, at - Vector3.new(0, 0.2, 0), 0.5, 15, C.driftwood, Enum.Material.WoodPlanks)
	for i = 0, 3 do
		local a = i * math.pi / 2
		local p = at + Vector3.new(math.cos(a) * 6.6, 0.3, math.sin(a) * 6.6)
		Pieces.glow(
			Pieces.box(
				parent,
				CFrame.new(p) * CFrame.Angles(0, a, 0),
				Vector3.new(1.2, 0.1, 0.6),
				C.spark
			),
			C.spark
		)
	end
	Kit.spawn(
		parent,
		CFrame.lookAt(at + Vector3.new(0, 0.5, 0), Vector3.new(0, floor + 0.5, 0)),
		Vector3.new(10, 1, 10),
		{
			Color = C.sailcloth,
			Material = Enum.Material.SmoothPlastic,
		}
	)
end

local function fingerpost(ctx: Context, parent: Instance, floor: number, dir: Vector3)
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local base = dir * SPAWN_DISTANCE + right * 9.5 + Vector3.new(0, floor, 0)
	Pieces.cyl(parent, base, 0.8, 2.2, Palette.stone, Enum.Material.Cobblestone)
	local all = table.clone(ctx.zones)
	table.insert(all, ctx.teaser)
	local h = 7.5 + #all * 1.6
	Pieces.cyl(parent, base, h, 0.9, C.piling, Enum.Material.Wood)
	for i, zone in all do
		local def = zone.def
		local name = if def then string.upper(def.displayName) else "COMING SOON"
		local y = h - 1.4 - (i - 1) * 1.6
		local target = zone.slot.hubExit.Position
		Pieces.arm(parent, base + Vector3.new(0, y, 0), target - base, 7, zone.color, name)
	end
	Pieces.weatherVane(parent, base + Vector3.new(0, h, 0), 1.2)
end

-- Village ring -------------------------------------------------------------------------

type CottageLook = { name: string, roof: string, chimney: boolean, instrument: string? }

local COTTAGES: { CottageLook } = {
	{ name = "SOCIETY", roof = "clay", chimney = true, instrument = "anemometer" },
	{ name = "BOTTLE WORKS", roof = "slate", chimney = false, instrument = "vane" },
	{ name = "TIDE CAFE", roof = "clay", chimney = true, instrument = nil },
	{ name = "THE INN", roof = "slate", chimney = true, instrument = "anemometer" },
	{ name = "POST", roof = "clay", chimney = false, instrument = "vane" },
}

local function village(
	ctx: Context,
	parent: Instance,
	floor: number,
	gaps: { { angle: number, half: number } },
	coveA: number,
	spawnA: number
)
	local rng = ctx.rng
	local cottage = 0
	local domes = 0
	for i, g in gaps do
		local maxHalf = RING_RADIUS * math.sin(math.rad(g.half)) - 8
		local isSpawn = Geo.angleDiff(g.angle, spawnA) < 1
		if Geo.angleDiff(g.angle, coveA) > 1 and maxHalf >= 6 and not isSpawn then
			local at = Geo.polar(g.angle, RING_RADIUS, floor)
			local cf = CFrame.lookAt(at, Vector3.new(0, floor, 0))
			if (i % 4 == 1) and domes < 2 then
				domes += 1
				local diameter = math.min(12, maxHalf * 2 - 1)
				Pieces.dome(parent, cf, diameter, domes == 1)
				if domes == 2 then
					-- a small weather balloon tethered over the radar dome, its
					-- posts just outside the dome's plinth (radius diameter/2 + 0.6)
					local reach = diameter / 2 + 1.4
					local anchors = {
						at + cf.RightVector * reach + Vector3.new(0, 0.4, 0),
						at - cf.RightVector * reach + Vector3.new(0, 0.4, 0),
					}
					for _, a in anchors do
						Pieces.cyl(
							parent,
							a - Vector3.new(0, 0.4, 0),
							1.2,
							0.8,
							C.harbor,
							Enum.Material.Metal
						)
					end
					Pieces.balloon(
						ctx,
						parent,
						at + Vector3.new(0, 34, 0) + Pieces.WIND * 4,
						8,
						C.sailcloth,
						C.seafoam,
						anchors,
						false
					)
				end
			else
				cottage += 1
				local o = COTTAGES[(cottage - 1) % #COTTAGES + 1]
				local w = math.min(10, maxHalf * 1.3)
				Pieces.cottage(parent, cf, {
					width = w,
					depth = 8,
					height = 5.4 + rng:NextNumber(0, 1.2),
					roof = o.roof,
					trim = if cottage % 2 == 0 then C.seafoam else C.harbor:Lerp(C.seafoam, 0.4),
					name = o.name,
					chimney = o.chimney,
					instrument = o.instrument,
				}, rng)
				-- planter or barrels beside the door
				if cottage % 2 == 0 then
					Pieces.planter(
						parent,
						cf * CFrame.new(w / 2 + 1.6, 0, -2.5) * CFrame.Angles(0, math.rad(90), 0),
						3.2,
						rng
					)
				else
					Pieces.barrel(
						parent,
						(cf * CFrame.new(-w / 2 - 1.4, 0, -3)).Position,
						C.seafoam
					)
					Pieces.crate(
						parent,
						cf * CFrame.new(-w / 2 - 1.2, 0, -0.6) * CFrame.Angles(0, 0.4, 0),
						1.6
					)
				end
			end
			-- round trees between the houses and the shore
			-- (one tree per gap once the world has many zones)
			local sides: { number } = if Geo.detail(ctx) < 1 then { (i % 2) * 2 - 1 } else { -1, 1 }
			for _, off in sides do
				local a = g.angle + off * g.half * 0.42
				local r = RING_RADIUS + rng:NextNumber(8, 11)
				Pieces.tree(parent, Geo.polar(a, r, floor - 0.3), rng:NextNumber(0.9, 1.25), rng)
			end
		end
	end
end

-- Lamps around the plaza with festoon lights between them, benches, planters.
local function plaza(
	ctx: Context,
	parent: Instance,
	floor: number,
	gaps: { { angle: number, half: number } },
	spawnA: number
)
	local rng = ctx.rng
	local lampTops = {}
	for _, g in gaps do
		local d = Geo.dir(g.angle)
		-- the spawn axis keeps a clear view of the sell arch: its lamp
		-- stands to one side
		if Geo.angleDiff(g.angle, spawnA) < 1 then
			d = Geo.dir(g.angle + 22)
		end
		local bottom = d * 44 + Vector3.new(0, floor, 0)
		Pieces.lampPost(parent, bottom, 7, -d, true)
		table.insert(lampTops, bottom + Vector3.new(0, 6.8, 0))
	end
	for i, top in lampTops do
		local nextTop = lampTops[i % #lampTops + 1]
		Kit.cable(ctx, top, nextTop, {
			Color = if i % 2 == 0 then C.slicker else Palette.lamp,
			Width = 0.3,
			CurveSize = 3,
			LightEmission = 0.8,
		})
	end
	local benches = 0
	for _, g in gaps do
		local nearSpawn = Geo.angleDiff(g.angle, spawnA)
		if nearSpawn > 1 then
			local d = Geo.dir(g.angle)
			local right = Vector3.new(-d.Z, 0, d.X)
			if nearSpawn > 50 then
				Pieces.planter(
					parent,
					CFrame.lookAt(d * 16.5 + Vector3.new(0, floor, 0), Vector3.new(0, floor, 0)),
					4.4,
					rng
				)
			end
			benches += 1
			if benches % 2 == 1 or nearSpawn < 50 then
				local at = d * 34 + right * 2.5 + Vector3.new(0, floor, 0)
				Pieces.bench(parent, CFrame.lookAt(at, Vector3.new(0, floor, 0)))
			else
				local at = d * 36 + Vector3.new(0, floor, 0)
				Pieces.stall(
					parent,
					CFrame.lookAt(at, Vector3.new(0, floor, 0)),
					if benches % 4 == 0 then C.seafoam else C.beacon,
					rng
				)
			end
		end
	end
end

-- Harbour pier, boats and crane in the cove.
local function harbour(ctx: Context, parent: Instance, floor: number, coveA: number)
	local R = ctx.layout.hubRadius
	local dir = Geo.dir(coveA)
	local right = Vector3.new(-dir.Z, 0, dir.X)
	-- the deck sits 0.2 over the grass it starts on, so the two never flicker
	local from = dir * (R + 6) + Vector3.new(0, floor + 0.2, 0)
	local to = dir * (R + 40) + Vector3.new(0, floor + 0.2, 0)
	Kit.walkway(
		parent,
		from,
		to,
		5,
		0.8,
		{ Name = "Pier", Color = C.driftwood, Material = Enum.Material.WoodPlanks }
	)
	for i = 1, 4 do
		local p = from:Lerp(to, i / 4)
		for _, side in { -1, 1 } do
			local q = p + right * side * 2.1
			Pieces.cyl(
				parent,
				Vector3.new(q.X, -8, q.Z),
				floor + 7.8,
				0.9,
				C.piling,
				Enum.Material.Wood,
				false
			)
		end
		Pieces.cyl(parent, p + right * 2.1, 1.2, 0.8, C.ink, Enum.Material.Metal, false)
	end
	-- harbour light at the pier end
	Pieces.cyl(parent, to - dir * 0.8, 4, 0.7, C.sailcloth, Enum.Material.SmoothPlastic, false)
	local light = Pieces.glow(
		Pieces.ball(parent, to - dir * 0.8 + Vector3.new(0, 4.5, 0), 1.2, C.beacon),
		C.beacon
	)
	Kit.light(light, C.beacon, 18, 1.4)
	-- moored boats
	local boats = {
		{ side = 1, t = 0.62, color = C.seafoam, cabin = true },
		{ side = -1, t = 0.86, color = C.beacon, cabin = false },
	}
	for _, b in boats do
		local side = b.side
		local p = from:Lerp(to, b.t) + right * side * 6.5
		local water = Vector3.new(p.X, 0.3, p.Z)
		Pieces.boat(
			parent,
			CFrame.lookAt(water, water + dir),
			b.color,
			if b.cabin then 12 else 9,
			b.cabin
		)
		Kit.cable(
			ctx,
			water + Vector3.new(0, 1.4, 0) - right * side * 2,
			from:Lerp(to, b.t) + right * side * 2.1 + Vector3.new(0, 1, 0),
			{
				Color = Palette.sand,
				Width = 0.14,
				CurveSize = 1,
			}
		)
	end
	-- crane and cargo on the quay
	local craneAt = Geo.polar(coveA + 13, R + 6, floor)
	Pieces.cyl(parent, craneAt, 1, 3, C.ink, Enum.Material.Metal)
	Pieces.cyl(parent, craneAt, 11, 1, C.slicker, Enum.Material.Metal)
	local armEnd = craneAt + Vector3.new(0, 10.5, 0) + dir * 9
	Pieces.beam(
		parent,
		craneAt + Vector3.new(0, 10.5, 0) - dir * 2,
		armEnd,
		0.8,
		C.slicker,
		Enum.Material.Metal
	)
	local hook = armEnd - Vector3.new(0, 6, 0)
	Kit.cable(ctx, armEnd, hook, { Color = C.ink, Width = 0.12 })
	Pieces.crate(parent, CFrame.new(hook - Vector3.new(0, 2, 0)), 2)
	for i = 1, 3 do
		local p = Geo.polar(coveA - 14 + i * 2.5, R + (i % 2) * 2, floor)
		Pieces.crate(parent, CFrame.new(p) * CFrame.Angles(0, i * 0.5, 0), 1.8 + (i % 2) * 0.4)
	end
	-- light at the end of the mole
	local tip = moleSegments(ctx, coveA)[2][2]
	local foot = Vector3.new(tip.X, MOLE_TOP, tip.Z)
	Pieces.cyl(parent, foot, 1, 3, Palette.stone, Enum.Material.Cobblestone)
	Pieces.stripedPole(parent, foot + Vector3.new(0, 1, 0), 6, 1.4, { C.seafoam, C.sailcloth }, 3)
	Pieces.glow(Pieces.ball(parent, foot + Vector3.new(0, 7.7, 0), 1.4, C.seafoam), C.seafoam)
	Pieces.barrel(parent, Geo.polar(coveA - 18, R, floor), C.beacon)
	Pieces.barrel(parent, Geo.polar(coveA - 20, R + 1, floor), C.seafoam)
end

-- Shore dressing: rocks on the sand ring and buoys out on open water, away
-- from boardwalks.
local function shore(ctx: Context, parent: Instance, corridors: { number }, coveA: number)
	local rng = ctx.rng
	local R = ctx.layout.hubRadius
	local floor = ctx.layout.hubFloor
	local function clear(angle: number): boolean
		for _, c in corridors do
			if Geo.angleDiff(angle, c) < 12 then
				return false
			end
		end
		return Geo.angleDiff(angle, coveA) > 16
	end
	local count = 0
	for _ = 1, 60 do
		if count >= Geo.count(ctx, 10) then
			break
		end
		local a = rng:NextNumber(0, 360)
		local p = Geo.polar(a, Land.HUB_CAP + rng:NextNumber(3, 8), 0)
		local h = Geo.heightAt(ctx, "Hub", p)
		-- on the sand ring, never out at sea
		if clear(a) and h and h < floor - 5 then
			count += 1
			Pieces.rocks(parent, Vector3.new(p.X, h, p.Z), rng:NextNumber(2.5, 4), rng)
		end
	end
	local buoys = 0
	for i = 1, 24 do
		local a = i * 15 + 7
		if buoys < 7 and clear(a) and i % 3 == 0 then
			buoys += 1
			local r = R + 40
			while r < R + 80 and (Geo.heightAt(ctx, "Hub", Geo.polar(a, r, 0)) or -99) > -3 do
				r += 4
			end
			Pieces.buoy(
				parent,
				Geo.polar(a, r, 0.2),
				if buoys % 2 == 0 then C.beacon else C.slicker
			)
		end
	end
end

function Hub.buildHub(ctx: Context)
	local parent = ctx.folders.hub
	local floor = ctx.layout.hubFloor
	local corridors = corridorAngles(ctx)
	local gaps = gapAngles(corridors)
	local spawnA = spawnAngle(ctx, gaps)
	local coveA = coveAngle(ctx, gaps, spawnA)
	local dir = Geo.dir(spawnA)

	local lens = lighthouse(ctx, parent, floor, dir)
	sellStation(ctx, parent, floor, dir, lens)
	spawnDeck(parent, floor, dir)
	fingerpost(ctx, parent, floor, dir)
	village(ctx, parent, floor, gaps, coveA, spawnA)
	plaza(ctx, parent, floor, gaps, spawnA)
	harbour(ctx, parent, floor, coveA)
	shore(ctx, ctx.folders.decor, corridors, coveA)
end

return Hub
