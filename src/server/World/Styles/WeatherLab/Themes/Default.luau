--!strict
-- Default theme ("Meadow Station"): a green island with mowed stripes, a
-- rough meadow plateau over earth-and-rock cliffs, a grassy hill, a rocky
-- point, a greenhouse, an instrument shelter, hay bales, round trees and
-- flowers. Hero: a lattice radar mast with a big white radome and a red
-- beacon. Used for any zone theme WeatherLab doesn't have.

local ServerScriptService = game:GetService("ServerScriptService")

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

local MARGINS = { front = 12, side = 16, back = 24 }
local ISLAND: WLTypes.IslandLook = {
	cap = G.meadow,
	strata = { G.earth, G.rock },
	layer = 4,
	inset = 1.5,
	beach = G.beach,
	beachTop = 1.5,
	beachSide = 10,
	beachBack = 12,
	beachFront = -4,
	chamfer = 12,
	ramp = -1,
}

local Default = {}

local function ground(ctx: Context, zone: ZoneContext)
	local rng = ctx.rng
	local key = Geo.key(zone)
	local floor = zone.slot.floor
	local hw, hd = zone.slot.width / 2, zone.slot.depth / 2
	local m = MARGINS
	-- a grassy hill on one back corner, over an earth bank
	local hx, hz = -(hw + m.side + 2), hd + m.back - 4
	if Geo.clearOf(ctx, zone, Geo.at(zone, hx, hz), 14, 10) then
		Land.island(ctx, key, Geo.cf(zone, hx, hz, 3, 10), {
			cap = G.grass,
			strata = { G.earth, G.rock },
			apothem = 12,
			sides = 8,
			layer = 40,
			inset = 1,
		})
	end
	-- a rocky point off the other side, its top half way down a cliff band
	local px, pz = hw + m.side + 6, -hd * 0.3
	if floor >= 6 and Geo.clearOf(ctx, zone, Geo.at(zone, px, pz), 14, 10) then
		local top = Land.ledge(zone, ISLAND, 0.5)
		Land.mesa(
			ctx,
			key,
			{ G.rock, G.slate },
			Geo.cf(zone, px, pz, top - floor, 25),
			Vector2.new(16, 13),
			5,
			1.6,
			math.min(ISLAND.beachTop, floor - Land.CAP)
		)
	end
	-- mossy boulders on the side rims
	for _, side in { -1, 1 } do
		Pieces.rocks(zone.folder, Geo.at(zone, side * (hw + 12), -hd * 0.55), 4.5, rng)
	end
end

-- Lattice radar mast with a radome on top.
local function radar(ctx: Context, zone: ZoneContext)
	local folder = zone.folder
	local hd = zone.slot.depth / 2
	local base = Geo.at(zone, 0, hd + 13)
	local h = 24
	local top = base + Vector3.new(0, h, 0)
	Pieces.box(
		folder,
		CFrame.new(base + Vector3.new(0, 0.5, 0)),
		Vector3.new(9, 1, 9),
		Palette.stone,
		Enum.Material.Concrete
	)
	for _, c in { { 1, 1 }, { 1, -1 }, { -1, -1 }, { -1, 1 } } do
		Pieces.beam(
			folder,
			base + Vector3.new(c[1] * 3.6, 1, c[2] * 3.6),
			top + Vector3.new(c[1] * 1.6, 0, c[2] * 1.6),
			0.6,
			C.beacon,
			Enum.Material.Metal
		)
	end
	for _, y in { 8, 16 } do
		local s = 3.6 - 2 * y / h
		for _, edge in { { -1, -1, 1, -1 }, { 1, -1, 1, 1 }, { 1, 1, -1, 1 }, { -1, 1, -1, -1 } } do
			Pieces.beam(
				folder,
				base + Vector3.new(edge[1] * s, y, edge[2] * s),
				base + Vector3.new(edge[3] * s, y, edge[4] * s),
				0.35,
				C.sailcloth,
				Enum.Material.Metal
			)
		end
	end
	Pieces.box(
		folder,
		CFrame.new(top + Vector3.new(0, 0.3, 0)),
		Vector3.new(6, 0.6, 6),
		C.ink,
		Enum.Material.DiamondPlate
	)
	local domeCenter = top + Vector3.new(0, 5.4, 0)
	Pieces.ball(folder, domeCenter, 11, C.sailcloth, Enum.Material.SmoothPlastic)
	Pieces.cyl(
		folder,
		domeCenter - Vector3.new(0, 1.2, 0),
		1.2,
		11.3,
		C.seafoam,
		Enum.Material.SmoothPlastic,
		false
	)
	local beacon =
		Pieces.glow(Pieces.ball(folder, domeCenter + Vector3.new(0, 6, 0), 1.2, C.beacon), C.beacon)
	Kit.light(beacon, C.beacon, 24, 1.6)
	-- a small dish on the platform edge
	local dishAt = top + zone.slot.frame.RightVector * 2.6 + Vector3.new(0, 1.6, 0)
	Kit.decor({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 3.2, 3.2),
		CFrame = CFrame.lookAt(
			dishAt,
			dishAt + Vector3.new(0, 0.7, 0) + zone.slot.frame.LookVector
		) * CFrame.Angles(0, math.rad(90), 0),
		Color = C.sailcloth,
		Material = Enum.Material.Metal,
		CanCollide = false,
		Parent = folder,
	})
	-- ladder up one leg
	Pieces.plank(
		folder,
		base + Vector3.new(0, 0, -4.6),
		top + Vector3.new(0, 0, -2.4),
		1.2,
		0.3,
		C.ink,
		Enum.Material.Metal
	)
	Kit.cable(
		ctx,
		top + Vector3.new(2, 0.6, 2),
		base + Vector3.new(9, 0.4, 9),
		{ Color = C.ink, Width = 0.12, CurveSize = 1 }
	)
end

local function greenhouse(parent: Instance, cframe: CFrame, rng: Random)
	local w, d, h = 9, 6, 4
	Pieces.box(
		parent,
		cframe * CFrame.new(0, 0.3, 0),
		Vector3.new(w + 0.6, 0.6, d + 0.6),
		Palette.stone,
		Enum.Material.Cobblestone
	)
	local glass = Pieces.box(
		parent,
		cframe * CFrame.new(0, 0.6 + h / 2, 0),
		Vector3.new(w, h, d),
		C.seafoam:Lerp(C.sailcloth, 0.6),
		Enum.Material.Glass
	)
	glass.Transparency = 0.45
	for _, s in { 1, -1 } do
		local roof = Pieces.wedge(
			parent,
			cframe
				* CFrame.new(0, 0.6 + h + 1, s * d / 4)
				* CFrame.Angles(0, if s > 0 then math.pi else 0, 0),
			Vector3.new(w, 2, d / 2),
			C.seafoam:Lerp(C.sailcloth, 0.6),
			Enum.Material.Glass,
			false
		)
		roof.Transparency = 0.45
	end
	for _, x in { -w / 2, 0, w / 2 } do
		Pieces.box(
			parent,
			cframe * CFrame.new(x, 0.6 + h / 2 + 1, 0),
			Vector3.new(0.3, h + 2, d + 0.2),
			C.sailcloth,
			Enum.Material.Wood,
			false
		)
	end
	for i = -1, 1 do
		Pieces.bush(parent, (cframe * CFrame.new(i * 2.6, 0.8, 0)).Position, 1.8, rng)
	end
end

local function shelter(parent: Instance, cframe: CFrame)
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			Pieces.box(
				parent,
				cframe * CFrame.new(x * 1.1, 1.6, z * 0.8),
				Vector3.new(0.3, 3.2, 0.3),
				C.sailcloth,
				Enum.Material.Wood,
				false
			)
		end
	end
	Pieces.box(
		parent,
		cframe * CFrame.new(0, 4, 0),
		Vector3.new(3, 2, 2.2),
		C.sailcloth,
		Enum.Material.WoodPlanks
	)
	Pieces.box(
		parent,
		cframe * CFrame.new(0, 5.2, 0),
		Vector3.new(3.4, 0.4, 2.6),
		C.sailcloth,
		Enum.Material.Wood,
		false
	)
	Pieces.box(
		parent,
		cframe * CFrame.new(0, 4, -1.12),
		Vector3.new(2.6, 1.6, 0.05),
		C.ink,
		Enum.Material.SmoothPlastic,
		false
	)
end

local function dress(ctx: Context, zone: ZoneContext)
	local rng = ctx.rng
	local folder = zone.folder
	local hw, hd = zone.slot.width / 2, zone.slot.depth / 2
	local spots: Geo.Spots = {}
	Geo.claim(spots, 0, -hd - 8, 9)
	Geo.claim(spots, 0, hd + 13, 8)

	radar(ctx, zone)

	local gx, gz = hw + 9, hd * 0.3
	Geo.claim(spots, gx, gz, 7)
	if Geo.room(ctx, zone, 30) then
		greenhouse(folder, Geo.faceField(zone, gx, gz), rng)
	end
	local sx, sz = -hw - 7, -hd * 0.2
	Geo.claim(spots, sx, sz, 3)
	if Geo.room(ctx, zone, 15) then
		shelter(folder, Geo.faceField(zone, sx, sz))
	end
	local lx, lz = -hw - 9, hd * 0.45
	Geo.claim(spots, lx, lz, 6)
	if Geo.room(ctx, zone, 30) then
		Pieces.cottage(folder, Geo.faceField(zone, lx, lz), {
			width = 8,
			depth = 6,
			height = 4.8,
			roof = "clay",
			trim = C.seafoam,
			name = "FIELD LAB",
			chimney = false,
			instrument = "vane",
		}, rng)
	end

	-- hay bales
	for i = 1, Geo.count(ctx, 4) do
		if not Geo.room(ctx, zone, 6) then
			break
		end
		local x, z = Geo.findSpot(ctx, zone, spots, 4, 12, 2, true)
		if x and z then
			local cf = Geo.cf(zone, x, z, 1.3, rng:NextNumber(0, 180))
			Kit.decor({
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(2.4, 2.6, 2.6),
				CFrame = cf,
				Color = C.slicker:Lerp(C.driftwood, 0.45 + i * 0.05),
				Material = Enum.Material.Grass,
				Parent = folder,
			})
		end
	end
	for _ = 1, Geo.count(ctx, 7) do
		if not Geo.room(ctx, zone, 6) then
			break
		end
		local x, z = Geo.findSpot(ctx, zone, spots, 6, 16, 3, true)
		if x and z then
			Pieces.tree(folder, Geo.at(zone, x, z, -0.3), rng:NextNumber(0.9, 1.3), rng)
		end
	end
	for _ = 1, Geo.count(ctx, 6) do
		if not Geo.room(ctx, zone, 6) then
			break
		end
		local x, z = Geo.findSpot(ctx, zone, spots, 3, 12, 1.6, false)
		if x and z then
			Pieces.bush(folder, Geo.at(zone, x, z), rng:NextNumber(1.8, 2.6), rng)
		end
	end
	for _ = 1, Geo.count(ctx, 10) do
		if not Geo.room(ctx, zone, 6) then
			break
		end
		local x, z = Geo.findSpot(ctx, zone, spots, 3, 10, 1.2, false)
		if x and z then
			Pieces.flowers(folder, Geo.at(zone, x, z), rng)
		end
	end
	for _ = 1, Geo.count(ctx, 5) do
		if not Geo.room(ctx, zone, 6) then
			break
		end
		local x, z = Geo.findSpot(ctx, zone, spots, 5, 16, 2, false)
		if x and z then
			Pieces.rocks(folder, Geo.at(zone, x, z), rng:NextNumber(2, 3.2), rng)
		end
	end
end

-- Field looks rotated by spiral slot, so a 3rd, 4th or 5th fallback zone
-- each gets its own bold two-tone pattern and trim.
local FIELDS: { WLTypes.FieldLook } = {
	{ base = G.grass, accent = G.limestone, trim = G.brick, pattern = "along", cell = 12 },
	{ base = G.grass, accent = G.salt, trim = G.planks, pattern = "checker", cell = 20 },
	{ base = G.grass, accent = G.earth, trim = G.limestone, pattern = "across", cell = 12 },
	{ base = G.sand, accent = G.grass, trim = G.slate, pattern = "checker", cell = 20 },
}

local theme: Theme = {
	margins = MARGINS,
	fieldFor = function(zone: ZoneContext): WLTypes.FieldLook
		return FIELDS[(zone.slot.index - 1) % #FIELDS + 1]
	end,
	island = ISLAND,
	field = FIELDS[1],
	border = {
		postColor = C.sailcloth,
		postMaterial = Enum.Material.Wood,
		postDiameter = 0.8,
		postHeight = 3.2,
		stones = false,
	},
	ground = ground,
	dress = dress,
}
Default.theme = theme
-- for themes built on Default's island (Premium)
Default.ground = ground
Default.dress = dress

return Default
