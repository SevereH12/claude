--!strict
-- Canyon theme ("Anvil Mesa"): a stepped sandstone-and-limestone mesa rising
-- out of the bay with a terracotta-and-cream checkerboard field, lower mesa
-- steps, a tall butte, hoodoos, a trail ramp up the cliff, a farm
-- windmill, adobe weather huts, cacti and tumbleweeds. Hero: the Anvil
-- Observatory, a white telescope dome on a banded rock spire.

local ServerScriptService = game:GetService("ServerScriptService")

local Blocks = require(ServerScriptService.Server.World.Blocks)
local Kit = require(ServerScriptService.Server.World.Kit)
local Geo = require(script.Parent.Parent.Geo)
local Land = require(script.Parent.Parent.Land)
local Palette = require(script.Parent.Parent.Palette)
local Pieces = require(script.Parent.Parent.Pieces)
local WLTypes = require(script.Parent.Parent.WLTypes)

type Context = WLTypes.Context
type ZoneContext = WLTypes.ZoneContext
type Theme = WLTypes.Theme

local C = Palette.colors
local G = Palette.ground

local MARGINS = { front = 12, side = 16, back = 26 }
local ISLAND: WLTypes.IslandLook = {
	cap = G.mesa,
	strata = { G.sandstone, G.limestone },
	layer = 4.5,
	inset = 1.6,
	beach = G.beach,
	beachTop = 1.5,
	beachSide = 12,
	beachBack = 12,
	beachFront = -4,
	chamfer = 14,
	ramp = 1,
}
local SPIRE_RISE = 26 -- observatory spire top above the floor
local ADOBE = C.driftwood:Lerp(C.beacon, 0.3)

local Canyon = {}

local function ground(ctx: Context, zone: ZoneContext)
	local rng = ctx.rng
	local key = Geo.key(zone)
	local floor = zone.slot.floor
	local hw, hd = zone.slot.width / 2, zone.slot.depth / 2
	local m = MARGINS
	local folder = Land.folder(ctx, key)
	local beachTop = math.min(ISLAND.beachTop, floor - Land.CAP)
	local tones = { G.limestone, G.sandstone }
	-- a stepped mesa beside the plateau, its top half way down a cliff band
	-- so no ledge lies flush with another
	local function step(x: number, z: number, band: number, size: Vector2, yaw: number)
		local p = Geo.at(zone, x, z)
		local r = math.max(size.X, size.Y) / 2 + 4
		if Geo.clearOf(ctx, zone, p, r, 10) then
			local top = Land.ledge(zone, ISLAND, band)
			Land.mesa(ctx, key, tones, Geo.cf(zone, x, z, top - floor, yaw), size, 5, 1.8, beachTop)
		end
	end
	-- lower mesa steps breaking out of the plateau on both sides and a
	-- headland off one back corner, so the island is never a plain block
	if floor >= 10 then
		step(-(hw + m.side + 6), -hd * 0.05, 1.5, Vector2.new(20, 26), 18)
		step(hw + m.side + 5, hd * 0.55, 2.5, Vector2.new(18, 22), -24)
	end
	step(-(hw + m.side - 2), hd + m.back + 7, 0.5, Vector2.new(24, 18), 32)
	-- a sand bar bulging off the back-right corner of the beach
	local sx, sz = hw + m.side + ISLAND.beachSide - 4, hd + m.back + 4
	if Geo.clearOf(ctx, zone, Geo.at(zone, sx, sz), 20, 10) then
		Land.lobe(
			ctx,
			key,
			ISLAND.beach,
			ISLAND.beach,
			Geo.cf(zone, sx, sz, beachTop - floor, 10),
			14,
			9
		)
	end
	-- a tall stepped butte behind the field
	local bx, bz = hw * 0.45, hd + m.back + 17
	if Geo.clearOf(ctx, zone, Geo.at(zone, bx, bz), 30, 10) then
		Land.mesa(
			ctx,
			key,
			{ G.sandstone, G.limestone, G.sandstone, G.rock },
			Geo.cf(zone, bx, bz, SPIRE_RISE, 12),
			Vector2.new(12, 10),
			9,
			2.6,
			beachTop
		)
	end
	-- hoodoos standing in the shallows round the mesa
	local hoodoos = {
		{ hw + m.side + 17, -hd * 0.12, 10 },
		{ -(hw + m.side + 16), hd * 0.45, 14 },
		{ -hw * 0.55, hd + m.back + 15, 8 },
		{ hw + 8, hd + m.back + 14, 16 },
		{ -(hw + m.side + 12), -hd * 0.7, 6 },
	}
	for _, h in hoodoos do
		local base = Geo.at(zone, h[1], h[2], 0)
		if Geo.clearOf(ctx, zone, base, 6, 6) then
			Land.stack(
				ctx,
				folder,
				{ G.sandstone, G.limestone, G.sandstone, G.rock },
				Vector3.new(base.X, Land.SEABED, base.Z),
				rng:NextNumber(9, 12),
				floor + h[3],
				11,
				G.sandstone
			)
		end
	end
	-- the observatory spire behind the field: square stone bands of cream
	-- and terracotta, the second turned 45 degrees, flat faces toward the
	-- field where the stair climbs past and a top wide enough for the deck
	-- (height, half width, turn)
	local bands = { { 7.5, 8, 0 }, { 6.5, 6, 45 }, { 6.5, 7.2, 0 }, { 6.5, 8.6, 0 } }
	local y = -1
	for i, b in bands do
		local tone = if i % 2 == 1 then G.limestone else G.sandstone
		Blocks.box(
			folder,
			tone,
			Geo.cf(zone, 0, hd + 15, y + b[1] / 2, b[3]),
			Vector3.new(2 * b[2], b[1], 2 * b[2]),
			{ Name = "Spire" }
		)
		y += b[1]
	end
end

-- The Anvil Observatory on top of the spire.
local function observatory(ctx: Context, zone: ZoneContext)
	local folder = zone.folder
	local hd = zone.slot.depth / 2
	local top = Geo.at(zone, 0, hd + 15, SPIRE_RISE)
	local toHub = zone.slot.frame.LookVector
	Pieces.cyl(
		folder,
		top - Vector3.new(0, 0.6, 0),
		1,
		17,
		Palette.stone,
		Enum.Material.Cobblestone
	)
	Pieces.cyl(folder, top, 4.4, 12, C.sailcloth, Enum.Material.Plaster)
	Pieces.cyl(
		folder,
		top + Vector3.new(0, 4.2, 0),
		0.6,
		12.6,
		C.seafoam,
		Enum.Material.SmoothPlastic,
		false
	)
	local domeCenter = top + Vector3.new(0, 4.6, 0)
	Pieces.ball(folder, domeCenter, 11.6, C.sailcloth, Enum.Material.SmoothPlastic)
	-- slit facing the field, a telescope poking out of it
	local slitCf = CFrame.lookAt(domeCenter, domeCenter + toHub) * CFrame.Angles(0, math.rad(90), 0)
	Kit.decor({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.8, 11.95, 11.95),
		CFrame = slitCf,
		Color = C.ink,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = folder,
	})
	local aim = (toHub * 0.65 + Vector3.new(0, 0.75, 0)).Unit
	Pieces.rod(
		folder,
		domeCenter + aim * 2,
		domeCenter + aim * 9.5,
		1.6,
		C.harbor,
		Enum.Material.Metal
	)
	Pieces.rod(
		folder,
		domeCenter + aim * 9.3,
		domeCenter + aim * 9.9,
		2.1,
		C.ink,
		Enum.Material.Metal
	)
	-- door and porch light toward the field
	local door = CFrame.lookAt(top, top + toHub) * CFrame.new(0, 1.9, -6)
	Pieces.box(folder, door, Vector3.new(2.2, 3.6, 0.3), C.seafoam, Enum.Material.Wood)
	Pieces.lantern(folder, (door * CFrame.new(1.8, 1.6, -0.6)).Position, nil, 16)
	-- lightning rod with a glowing tip
	local rodBase = domeCenter + Vector3.new(0, 5.6, 0)
	Pieces.cyl(folder, rodBase, 7, 0.4, C.ink, Enum.Material.Metal, false)
	local tip =
		Pieces.glow(Pieces.ball(folder, rodBase + Vector3.new(0, 7.2, 0), 1.2, C.spark), C.spark)
	Kit.light(tip, C.spark, 30, 1.8)
	Kit.emitter(tip, {
		Texture = Kit.TEXTURES.sparkle,
		Rate = 4,
		Lifetime = NumberRange.new(0.4, 0.8),
		Speed = NumberRange.new(2, 4),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new(0.6),
		LightEmission = 1,
		Color = ColorSequence.new(C.spark),
	})
	-- railing posts around the platform
	for i = 0, 7 do
		local a = math.rad(i * 45 + 22.5)
		local p = top + Vector3.new(math.cos(a) * 7.8, 0, math.sin(a) * 7.8)
		Pieces.cyl(folder, p, 2.4, 0.4, C.piling, Enum.Material.Wood, false)
		local nextA = math.rad((i + 1) * 45 + 22.5)
		Kit.cable(
			ctx,
			p + Vector3.new(0, 2.2, 0),
			top + Vector3.new(math.cos(nextA) * 7.8, 2.2, math.sin(nextA) * 7.8),
			{ Color = Palette.sand, Width = 0.14, CurveSize = 0.3 }
		)
	end
	-- zigzag stair down the spire face toward the field
	local floorY = 0
	local flights = 4
	for i = 1, flights do
		local side = if i % 2 == 0 then -1 else 1
		local y0 = floorY + (i - 1) * SPIRE_RISE / flights
		local y1 = floorY + i * SPIRE_RISE / flights
		local a = Geo.at(zone, -side * 5, hd + 5, y0)
		local b = Geo.at(zone, side * 5, hd + 5, y1)
		Pieces.plank(folder, a, b, 2.2, 0.5, C.driftwood)
	end
	-- zip line from the observatory down to the plateau
	local post = Geo.at(zone, zone.slot.width / 2 + 9, hd + 6, 0)
	Pieces.cyl(folder, post, 6, 0.7, C.piling, Enum.Material.Wood)
	Kit.cable(
		ctx,
		top + Vector3.new(0, 3, 0) + zone.slot.frame.RightVector * 6,
		post + Vector3.new(0, 5.6, 0),
		{
			Color = C.ink,
			Width = 0.18,
			CurveSize = 3,
		}
	)
end

-- Old farm windmill pumping water, turned into the wind.
local function windmill(parent: Instance, bottom: Vector3)
	local h = 17
	local top = bottom + Vector3.new(0, h, 0)
	for _, c in { { 1, 1 }, { 1, -1 }, { -1, -1 }, { -1, 1 } } do
		local foot = bottom + Vector3.new(c[1] * 2.8, 0, c[2] * 2.8)
		local head = top + Vector3.new(c[1] * 0.7, 0, c[2] * 0.7)
		Pieces.beam(parent, foot, head, 0.35, C.harbor, Enum.Material.Metal)
	end
	for _, y in { 5, 11 } do
		local s = 2.8 - (2.1 * y / h)
		Pieces.beam(
			parent,
			bottom + Vector3.new(-s, y, -s),
			bottom + Vector3.new(s, y, s),
			0.25,
			C.harbor,
			Enum.Material.Metal
		)
		Pieces.beam(
			parent,
			bottom + Vector3.new(-s, y, s),
			bottom + Vector3.new(s, y, -s),
			0.25,
			C.harbor,
			Enum.Material.Metal
		)
	end
	Pieces.box(
		parent,
		CFrame.new(top + Vector3.new(0, 0.3, 0)),
		Vector3.new(2, 0.6, 2),
		C.ink,
		Enum.Material.Metal,
		false
	)
	local into = -Pieces.WIND
	local hub = top + Vector3.new(0, 1.6, 0) + into * 1.4
	local face = CFrame.lookAt(hub, hub + into)
	Kit.pipe(
		parent,
		hub - into * 1.6,
		hub + into * 0.4,
		1,
		{ Color = C.ink, Material = Enum.Material.Metal, CanCollide = false }
	)
	for i = 0, 7 do
		local a = i * math.pi / 4
		local blade = face
			* CFrame.Angles(0, 0, a)
			* CFrame.new(0, 2.9, 0)
			* CFrame.Angles(0, math.rad(20), 0)
		Pieces.box(
			parent,
			blade,
			Vector3.new(1.1, 3.8, 0.12),
			if i % 2 == 0 then C.sailcloth else C.beacon,
			Enum.Material.Metal,
			false
		)
	end
	-- tail vane
	local tailEnd = hub - into * 6
	Pieces.beam(parent, hub - into * 1, tailEnd, 0.25, C.ink, Enum.Material.Metal)
	Pieces.box(
		parent,
		CFrame.lookAt(tailEnd, tailEnd - into),
		Vector3.new(0.12, 2.2, 3),
		C.beacon,
		Enum.Material.Metal,
		false
	)
	-- water tank at the foot
	Pieces.cyl(parent, bottom + Vector3.new(4.6, 0, 1.5), 2.4, 4.6, C.harbor, Enum.Material.Metal)
end

-- Flat-roofed adobe weather hut with poking roof beams.
local function adobe(parent: Instance, cframe: CFrame, w: number, d: number, h: number)
	Pieces.box(
		parent,
		cframe * CFrame.new(0, h / 2, 0),
		Vector3.new(w, h, d),
		ADOBE,
		Enum.Material.Plaster
	)
	Pieces.box(
		parent,
		cframe * CFrame.new(0, h + 0.3, 0),
		Vector3.new(w + 0.4, 0.6, d + 0.4),
		ADOBE:Lerp(C.sailcloth, 0.25),
		Enum.Material.Plaster
	)
	for i = -1, 1 do
		Kit.pipe(
			parent,
			(cframe * CFrame.new(i * w * 0.3, h - 0.8, -d / 2 + 0.5)).Position,
			(cframe * CFrame.new(i * w * 0.3, h - 0.8, -d / 2 - 1.1)).Position,
			0.6,
			{
				Color = C.piling,
				Material = Enum.Material.Wood,
				CanCollide = false,
			}
		)
	end
	Pieces.box(
		parent,
		cframe * CFrame.new(-w * 0.18, 1.7, -d / 2 - 0.1),
		Vector3.new(1.8, 3.4, 0.3),
		C.seafoam,
		Enum.Material.Wood
	)
	Pieces.glow(
		Pieces.box(
			parent,
			cframe * CFrame.new(w * 0.25, 2.4, -d / 2 - 0.08),
			Vector3.new(1.4, 1.2, 0.2),
			Palette.window
		),
		Palette.window
	)
	-- rain gauge on the roof
	Pieces.cyl(
		parent,
		(cframe * CFrame.new(w * 0.3, h + 0.6, d * 0.2)).Position,
		1.4,
		0.6,
		C.sailcloth,
		Enum.Material.Metal,
		false
	)
end

-- Wooden water tower on four splayed legs: a western silhouette.
local function waterTower(parent: Instance, bottom: Vector3)
	local h = 11
	local top = bottom + Vector3.new(0, h, 0)
	for _, c in { { 1, 1 }, { 1, -1 }, { -1, -1 }, { -1, 1 } } do
		Pieces.beam(
			parent,
			bottom + Vector3.new(c[1] * 3.4, 0, c[2] * 3.4),
			top + Vector3.new(c[1] * 2.2, 0, c[2] * 2.2),
			0.6,
			C.piling,
			Enum.Material.Wood
		)
	end
	for _, y in { 4, 8 } do
		local s = 3.4 - y / h * 1.2
		Pieces.beam(
			parent,
			bottom + Vector3.new(-s, y, s),
			bottom + Vector3.new(s, y, -s),
			0.35,
			C.piling,
			Enum.Material.Wood
		)
	end
	Pieces.cyl(parent, top, 0.6, 7.4, C.piling, Enum.Material.WoodPlanks)
	Pieces.cyl(
		parent,
		top + Vector3.new(0, 0.6, 0),
		5.4,
		6.4,
		C.driftwood,
		Enum.Material.WoodPlanks
	)
	for _, y in { 1.6, 4.4 } do
		Pieces.cyl(parent, top + Vector3.new(0, y, 0), 0.35, 6.6, C.ink, Enum.Material.Metal, false)
	end
	Pieces.cyl(
		parent,
		top + Vector3.new(0, 6, 0),
		0.8,
		7,
		C.beacon,
		Enum.Material.WoodPlanks,
		false
	)
	Pieces.ball(
		parent,
		top + Vector3.new(0, 6.4, 0),
		2.4,
		C.beacon,
		Enum.Material.WoodPlanks,
		false
	)
	Pieces.rod(
		parent,
		top + Vector3.new(3.3, 3, 0),
		top + Vector3.new(4.6, -1.5, 0),
		0.5,
		C.harbor,
		Enum.Material.Metal
	)
	for _, z in { -0.5, 0.5 } do
		Pieces.rod(
			parent,
			bottom + Vector3.new(-3.6, 0, z),
			top + Vector3.new(-3.3, 0.6, z),
			0.18,
			C.harbor,
			Enum.Material.Metal
		)
	end
end

local function dress(ctx: Context, zone: ZoneContext)
	local rng = ctx.rng
	local folder = zone.folder
	local hw, hd = zone.slot.width / 2, zone.slot.depth / 2
	local spots: Geo.Spots = {}
	Geo.claim(spots, 0, -hd - 8, 9)
	Geo.claim(spots, 0, hd + 15, 10)
	Geo.claim(spots, 0, hd + 6, 7)
	Geo.claim(spots, hw + MARGINS.side + 4, hd * 0.6, 17) -- the cove

	observatory(ctx, zone)

	-- windmill on one side, huts on the other and at a back corner
	local wx, wz = hw + 8, hd * 0.25
	Geo.claim(spots, wx, wz, 6)
	windmill(folder, Geo.at(zone, wx, wz))
	local huts = {
		{ -hw - 8, -hd * 0.25, 7, 6, 4.6 },
		{ -hw - 8, hd * 0.45, 6, 5, 4 },
		{ hw + 7, hd + 13, 7, 6, 5 },
	}
	for _, h in huts do
		if not Geo.room(ctx, zone, 30) then
			break
		end
		Geo.claim(spots, h[1], h[2], 5.5)
		local cf = Geo.faceField(zone, h[1], h[2])
		adobe(folder, cf, h[3], h[4], h[5])
		Pieces.crate(folder, cf * CFrame.new(h[3] / 2 + 1.4, 0, -1), 1.8)
		Pieces.barrel(folder, (cf * CFrame.new(-h[3] / 2 - 1.2, 0, -1.5)).Position, C.beacon)
	end
	local tx, tz = -hw * 0.62, hd + 13
	Geo.claim(spots, tx, tz, 6)
	if Geo.room(ctx, zone, 30) then
		waterTower(folder, Geo.at(zone, tx, tz))
	end

	local lampX, lampZ = -hw - 6, hd * 0.1
	Pieces.lampPost(folder, Geo.at(zone, lampX, lampZ), 6, zone.slot.frame.RightVector)

	-- dust devil detector: tripod with an anemometer
	local dx, dz = hw + 7, -hd * 0.5
	Geo.claim(spots, dx, dz, 3)
	local foot = Geo.at(zone, dx, dz)
	for i = 0, 2 do
		local a = math.rad(i * 120)
		Pieces.beam(
			folder,
			foot + Vector3.new(math.cos(a) * 1.8, 0, math.sin(a) * 1.8),
			foot + Vector3.new(0, 5, 0),
			0.25,
			C.harbor,
			Enum.Material.Metal
		)
	end
	Pieces.anemometer(folder, foot + Vector3.new(0, 5, 0))

	-- cacti, tumbleweeds, desert flowers and rocks around the rim
	for _ = 1, Geo.count(ctx, 14) do
		if not Geo.room(ctx, zone, 6) then
			break
		end
		local x, z = Geo.findSpot(ctx, zone, spots, 4, 14, 1.8, true)
		if x and z then
			Pieces.cactus(folder, Geo.at(zone, x, z, -0.3), rng:NextNumber(4, 7.5), rng)
		end
	end
	for _ = 1, Geo.count(ctx, 5) do
		if not Geo.room(ctx, zone, 6) then
			break
		end
		local x, z = Geo.findSpot(ctx, zone, spots, 4, 14, 1.2, false)
		if x and z then
			local weed = Pieces.ball(
				folder,
				Geo.at(zone, x, z, 1),
				rng:NextNumber(1.6, 2.4),
				Palette.plankDark,
				Enum.Material.Fabric,
				false
			)
			weed.Transparency = 0.15
		end
	end
	for _ = 1, Geo.count(ctx, 8) do
		if not Geo.room(ctx, zone, 6) then
			break
		end
		local x, z = Geo.findSpot(ctx, zone, spots, 3, 12, 1.2, false)
		if x and z then
			Pieces.flowers(folder, Geo.at(zone, x, z), rng)
		end
	end
	for _ = 1, Geo.count(ctx, 7) do
		if not Geo.room(ctx, zone, 6) then
			break
		end
		local x, z = Geo.findSpot(ctx, zone, spots, 4, 15, 2.5, false)
		if x and z then
			Pieces.rocks(
				folder,
				Geo.at(zone, x, z),
				rng:NextNumber(2, 3.6),
				rng,
				ADOBE:Lerp(C.harbor, 0.35)
			)
		end
	end
	-- warning sign at the gate side
	Pieces.signBoard(
		folder,
		Geo.cf(zone, 13, -hd - 4, 3),
		5.6,
		2.4,
		"STRIKE ZONE",
		"Stand in the circle!",
		Palette.HAZARD_SIGN,
		zone.slot.floor
	)
end

local theme: Theme = {
	margins = MARGINS,
	island = ISLAND,
	field = {
		base = G.sandstone,
		accent = G.limestone,
		trim = G.brick,
		pattern = "checker",
		cell = 20,
	},
	border = {
		postColor = C.sailcloth,
		postMaterial = Enum.Material.Wood,
		postDiameter = 0.8,
		postHeight = 3.2,
		stones = true,
	},
	ground = ground,
	dress = dress,
}
Canyon.theme = theme

return Canyon
