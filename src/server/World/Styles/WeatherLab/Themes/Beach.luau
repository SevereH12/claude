--!strict
-- Beach theme ("Tidewatch Beach"): a sandy island with beach-towel striped
-- sand, dunes with beach grass, striped huts, umbrellas, palms, a tide
-- watch tower and buoys. Hero: a giant red-and-white weather balloon
-- tethered above a launch deck behind the field.

local ServerScriptService = game:GetService("ServerScriptService")

local Kit = require(ServerScriptService.Server.World.Kit)
local Geo = require(script.Parent.Parent.Geo)
local Palette = require(script.Parent.Parent.Palette)
local Pieces = require(script.Parent.Parent.Pieces)
local WLTypes = require(script.Parent.Parent.WLTypes)

type Context = WLTypes.Context
type ZoneContext = WLTypes.ZoneContext
type Theme = WLTypes.Theme

local C = Palette.colors

local MARGINS = { front = 9, side = 17, back = 28 }

local Beach = {}

local function ground(ctx: Context, zone: ZoneContext)
	local rng = ctx.rng
	local floor = zone.slot.floor
	local hw, hd = zone.slot.width / 2, zone.slot.depth / 2
	local m = MARGINS
	-- a round cove bitten into the long side (cut from every land layer)
	Geo.bite(ctx, Geo.key(zone), Geo.at(zone, -hw - m.side + 2, hd * 0.2, 0), 13)
	-- shallows, a low wet-sand step and the beach: big wobbly lobes so the
	-- island has headlands and spits rather than following the field
	Geo.terrace(ctx, zone, m, 24, -4, -18, Enum.Material.Sand, 16, 1, 1)
	Geo.terrace(ctx, zone, m, 16, -1.5, -16, Enum.Material.Sand, 15, 1, 1)
	Geo.terrace(ctx, zone, m, 10, math.min(1, floor - 2), -16, Enum.Material.Sand, 13, 1, 1)
	Geo.cliffs(ctx, zone, m, 1, floor, { Enum.Material.Sandstone, Enum.Material.Rock }, 10, 4, 7)
	Geo.terrace(ctx, zone, m, 0, floor, -16, Enum.Material.Sand, 9, 0)
	-- a long sand spit off one side and a rocky bluff ridge along the back
	-- (higher than the field, so the side view shows layers)
	for k = 0, 3 do
		Geo.lobe(
			ctx,
			zone,
			hw + m.side + 6 + k * 9,
			-hd * 0.55 - k * 5,
			6 - k,
			11 - k,
			math.min(1, floor - 2) - k * 0.6,
			Enum.Material.Sand,
			0.5
		)
	end
	for k, fx in { -0.76, -0.44 } do
		local bx, bz = fx * hw, hd + m.back - 4 + k * 3
		Geo.lobe(ctx, zone, bx, bz, 6, 10, floor + 3 + k * 2, Enum.Material.Sandstone, 1.5)
		Geo.lobe(ctx, zone, bx, bz + 1, 4, 7, floor + 4.5 + k * 2, Enum.Material.LeafyGrass, 1)
	end
	-- a big grassy rock headland on one back corner
	local hx, hz = hw + m.side + 8, hd + m.back - 4
	Geo.lobe(ctx, zone, hx + 6, hz + 6, 12, 20, 1, Enum.Material.Sand, 1)
	Geo.lobe(ctx, zone, hx, hz, 13, 21, floor + 2, Enum.Material.Rock, 2)
	Geo.lobe(ctx, zone, hx + 2, hz + 1, 8, 14, floor + 6, Enum.Material.Slate, 2)
	Geo.lobe(ctx, zone, hx + 2, hz + 1, 5, 10, floor + 6.5, Enum.Material.LeafyGrass, 1)
	-- a long curving sand spit off the other back corner
	for k = 0, 4 do
		Geo.lobe(
			ctx,
			zone,
			-hw - m.side - 4 - k * 9,
			hd * 0.75 + k * 9 - k * k,
			7 - k,
			13 - k * 1.5,
			1.5 - k * 0.4,
			Enum.Material.Sand,
			0.5
		)
	end

	-- dunes along the back and back corners, capped with beach grass
	local dunes = {
		{ -hw * 0.8, hd + 17 },
		{ -hw * 0.35, hd + 22 },
		{ hw * 0.45, hd + 21 },
		{ hw * 0.9, hd + 16 },
		{ -hw - 15, hd * 0.55 },
		{ hw + 15, hd * 0.6 },
		{ -hw - 14, -hd * 0.2 },
	}
	for _, d in dunes do
		local r = rng:NextNumber(9, 11)
		local p = Geo.at(zone, d[1], d[2], -4)
		ctx.terrain:FillBall(p, r, Enum.Material.Sand)
		ctx.terrain:FillBall(
			p + Vector3.new(rng:NextNumber(-2, 2), r - 2.5, rng:NextNumber(-2, 2)),
			4.5,
			Enum.Material.LeafyGrass
		)
	end
	-- a little lagoon cut into the back corner of the beach
	local lagoon = Geo.at(zone, -hw - m.side + 2, hd + m.back - 2, 0)
	Geo.pond(ctx, lagoon, 6, 11, floor - 0.6, 5)
	-- dune grass fringing the upper beach
	Geo.rim(ctx, zone, floor, Enum.Material.LeafyGrass, 2.6, 0.35)
	-- beach-grass meadows on the side and back rims
	for _ = 1, 6 do
		local x, z = Geo.rimPoint(ctx, zone, 9, 17, true)
		local p = Geo.at(zone, x, z, 0)
		ctx.terrain:FillCylinder(
			CFrame.new(p.X, floor - 1, p.Z),
			2.4,
			rng:NextNumber(4, 6.5),
			Enum.Material.LeafyGrass
		)
	end
	-- rock outcrops at the front corners and a few sea rocks
	for _, side in { -1, 1 } do
		local p = Geo.at(zone, side * (hw + 13), -hd - 6, -3)
		ctx.terrain:FillBall(p, 6.5, Enum.Material.Slate)
		ctx.terrain:FillBall(p + Vector3.new(3, 1.5, -2), 4, Enum.Material.Rock)
		local sea = Geo.at(zone, side * (hw + m.side + 20), hd * rng:NextNumber(-0.4, 0.4), 0)
		ctx.terrain:FillBall(Vector3.new(sea.X, -1, sea.Z), 5, Enum.Material.Slate)
	end
	-- tide pools on the side rims
	for _, side in { -1, 1 } do
		local p = Geo.at(zone, side * (hw + 10), hd * rng:NextNumber(-0.5, 0.1), 0)
		ctx.terrain:FillCylinder(CFrame.new(p.X, floor - 1.4, p.Z), 2, 3.5, Enum.Material.Water)
	end
end

-- Striped beach hut on short stilts. cframe at the ground, facing out the door.
local function hut(parent: Instance, cframe: CFrame, color: Color3)
	Pieces.box(
		parent,
		cframe * CFrame.new(0, 0.9, -0.8),
		Vector3.new(6.4, 0.5, 7.6),
		C.driftwood,
		Enum.Material.WoodPlanks
	)
	for _, x in { -2.8, 2.8 } do
		for _, z in { -3.8, 2.6 } do
			Pieces.box(
				parent,
				cframe * CFrame.new(x, 0.4, z),
				Vector3.new(0.5, 1, 0.5),
				C.piling,
				Enum.Material.Wood,
				false
			)
		end
	end
	Pieces.box(
		parent,
		cframe * CFrame.new(0, 3.65, 0.4),
		Vector3.new(5.4, 5, 4.6),
		color,
		Enum.Material.WoodPlanks
	)
	for _, x in { -1.8, 0, 1.8 } do
		Pieces.box(
			parent,
			cframe * CFrame.new(x, 3.65, -1.95),
			Vector3.new(0.7, 5, 0.12),
			C.sailcloth,
			Enum.Material.WoodPlanks,
			false
		)
	end
	Pieces.box(
		parent,
		cframe * CFrame.new(0, 2.9, -1.98),
		Vector3.new(1.6, 3.2, 0.12),
		C.ink,
		Enum.Material.Wood,
		false
	)
	Pieces.wedge(
		parent,
		cframe * CFrame.new(0, 7.1, -0.8),
		Vector3.new(6.2, 1.9, 3.6),
		C.beacon,
		Enum.Material.Wood
	)
	Pieces.wedge(
		parent,
		cframe * CFrame.new(0, 7.1, 1.6) * CFrame.Angles(0, math.pi, 0),
		Vector3.new(6.2, 1.9, 2.4),
		C.beacon,
		Enum.Material.Wood
	)
end

-- Lifeguard-style tide watch tower with a lantern and a red flag.
local function tideTower(ctx: Context, parent: Instance, cframe: CFrame)
	local legH = 7
	for _, x in { -2.2, 2.2 } do
		for _, z in { -2.2, 2.2 } do
			local foot = (cframe * CFrame.new(x * 1.25, 0, z * 1.25)).Position
			local top = (cframe * CFrame.new(x, legH, z)).Position
			Pieces.beam(parent, foot, top, 0.6, C.sailcloth, Enum.Material.Wood)
		end
	end
	Pieces.box(
		parent,
		cframe * CFrame.new(0, legH + 0.3, 0),
		Vector3.new(6, 0.6, 6),
		C.driftwood,
		Enum.Material.WoodPlanks
	)
	Pieces.box(
		parent,
		cframe * CFrame.new(0, legH + 2.3, 0.6),
		Vector3.new(4.6, 3.4, 3.6),
		C.sailcloth,
		Enum.Material.Plaster
	)
	Pieces.glow(
		Pieces.box(
			parent,
			cframe * CFrame.new(0, legH + 2.8, -1.25),
			Vector3.new(3.4, 1.4, 0.2),
			Palette.window
		),
		Palette.window
	)
	Pieces.box(
		parent,
		cframe * CFrame.new(0, legH + 4.25, 0.2),
		Vector3.new(6.2, 0.5, 5.6),
		C.beacon,
		Enum.Material.Wood
	)
	Pieces.plank(
		parent,
		(cframe * CFrame.new(0, 0, -6)).Position,
		(cframe * CFrame.new(0, legH, -3)).Position,
		2,
		0.4,
		C.driftwood
	)
	local mast = (cframe * CFrame.new(2.4, legH + 4.5, 2.2)).Position
	Pieces.cyl(parent, mast, 5, 0.25, C.ink, Enum.Material.Metal, false)
	Pieces.windsock(parent, mast + Vector3.new(0, 4.6, 0), C.beacon, 3)
	local sign = Kit.sign(
		parent,
		cframe * CFrame.new(0, legH - 0.6, -3.05) * CFrame.Angles(0, math.pi, 0),
		5.6,
		1.4,
		"TIDE WATCH",
		nil,
		Palette.SIGN
	)
	sign.CanCollide = false
	Pieces.lantern(parent, (cframe * CFrame.new(-2.6, legH + 3.6, -2.6)).Position, nil, 18)
	-- a rope from the tower to a mooring post at the waterline
	Kit.cable(
		ctx,
		(cframe * CFrame.new(2.6, legH + 1, -2.6)).Position,
		(cframe * CFrame.new(5, 1, -10)).Position,
		{ Color = Palette.sand, Width = 0.15, CurveSize = 1.5 }
	)
end

-- A plank pier on stilts from the back beach out to open water, with a
-- T-head, a lamp, a striped tide gauge and a rowboat tied alongside.
local function pier(ctx: Context, zone: ZoneContext, spots: Geo.Spots)
	local folder = zone.folder
	local floor = zone.slot.floor
	local hw, hd = zone.slot.width / 2, zone.slot.depth / 2
	local x = hw * 0.55
	local z0 = hd + 10
	local z1 = z0 + 6
	while z1 < z0 + 70 and (Geo.heightAt(ctx, Geo.key(zone), Geo.at(zone, x, z1, 0)) or -99) > -3 do
		z1 += 4
	end
	z1 += 12
	for z = z0, z1, 6 do
		Geo.claim(spots, x, z, 5)
	end
	local deckY = floor + 0.6
	local width = 5
	local tones = { C.driftwood, Palette.plankLight, Palette.plankDark }
	local n = math.max(2, math.floor((z1 - z0) / 12))
	for i = 0, n - 1 do
		local za, zb = z0 + (z1 - z0) * i / n, z0 + (z1 - z0) * (i + 1) / n
		Kit.walkway(
			folder,
			Geo.at(zone, x, za - 0.3, 0.6),
			Geo.at(zone, x, zb + 0.3, 0.6),
			width,
			0.6,
			{
				Name = "Pier",
				Color = tones[i % #tones + 1],
				Material = Enum.Material.WoodPlanks,
			}
		)
	end
	-- T-head at the end
	Kit.walkway(
		folder,
		Geo.at(zone, x - 7, z1 + 2.5, 0.6),
		Geo.at(zone, x + 7, z1 + 2.5, 0.6),
		6,
		0.6,
		{ Name = "PierHead", Color = Palette.plankLight, Material = Enum.Material.WoodPlanks }
	)
	-- stilts where the pier stands over water, rope rails on short posts
	local last: { [number]: Vector3 } = {}
	local z = z0 + 3
	while z <= z1 do
		local overWater = (Geo.heightAt(ctx, Geo.key(zone), Geo.at(zone, x, z, 0)) or -99)
			< floor - 1
		for _, side in { -1, 1 } do
			local px = x + side * (width / 2 - 0.3)
			if overWater then
				local foot = Geo.at(zone, px, z, 0)
				Pieces.cyl(
					folder,
					Vector3.new(foot.X, -8, foot.Z),
					deckY + 7.6,
					0.9,
					C.piling,
					Enum.Material.Wood,
					false
				)
			end
			local postBottom = Geo.at(zone, px, z, 0.6)
			Pieces.box(
				folder,
				CFrame.new(postBottom + Vector3.new(0, 1.3, 0)),
				Vector3.new(0.45, 2.6, 0.45),
				C.piling,
				Enum.Material.Wood,
				false
			)
			local top = postBottom + Vector3.new(0, 2.3, 0)
			local previous = last[side]
			if previous then
				Kit.cable(
					ctx,
					previous,
					top,
					{ Color = Palette.sand, Width = 0.15, CurveSize = 0.5 }
				)
			end
			last[side] = top
		end
		z += 9
	end
	for _, dx in { -6.4, 6.4 } do
		local foot = Geo.at(zone, x + dx, z1 + 2.5, 0)
		Pieces.cyl(
			folder,
			Vector3.new(foot.X, -8, foot.Z),
			deckY + 7.6,
			1,
			C.piling,
			Enum.Material.Wood,
			false
		)
	end
	local outward = zone.slot.frame:VectorToWorldSpace(Vector3.new(0, 0, 1))
	Pieces.lampPost(folder, Geo.at(zone, x + 5.6, z1 + 4.6, 0.6), 6.5, -outward)
	-- striped tide gauge standing in the water beside the head
	local gauge = Geo.at(zone, x - 8.5, z1 + 3.5, 0)
	Pieces.stripedPole(
		folder,
		Vector3.new(gauge.X, -2, gauge.Z),
		deckY + 7,
		0.8,
		{ C.slicker, C.ink },
		8
	)
	Pieces.glow(
		Pieces.ball(folder, Vector3.new(gauge.X, deckY + 5.4, gauge.Z), 1, zone.color),
		zone.color
	)
	-- sea spray where the waves hit the pier head
	local spray = Kit.part({
		Name = "Spray",
		Size = Vector3.new(14, 1, 3),
		CFrame = Geo.cf(zone, x, z1 + 5.5, 1 - floor),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Parent = folder,
	})
	Kit.emitter(spray, {
		Texture = Kit.TEXTURES.smoke,
		Rate = 4,
		Lifetime = NumberRange.new(1.2, 2),
		Speed = NumberRange.new(3, 6),
		SpreadAngle = Vector2.new(25, 25),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.5),
			NumberSequenceKeypoint.new(1, 4),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Color = ColorSequence.new(C.sailcloth),
		Acceleration = Vector3.new(0, -8, 0),
		EmissionDirection = Enum.NormalId.Top,
	})
	Pieces.barrel(folder, Geo.at(zone, x - 4.5, z1 + 3.8, 0.6), C.seafoam)
	Pieces.crate(folder, Geo.cf(zone, x - 2.6, z1 + 4.3, 0.6, 20), 1.6)
	-- rowboat tied alongside
	local boat = Geo.at(zone, x + width / 2 + 3.4, z1 - 6, 0.3 - floor)
	Pieces.boat(folder, CFrame.lookAt(boat, boat + outward), C.beacon, 8, false)
	Kit.cable(
		ctx,
		Geo.at(zone, x + width / 2 - 0.3, z1 - 3, 2.9),
		boat + outward * 2.6 + Vector3.new(0, 1.4, 0),
		{ Color = Palette.sand, Width = 0.12, CurveSize = 1.2 }
	)
end

-- Weather balloon launch station: deck, winch, control hut, tethered balloon.
local function balloonStation(ctx: Context, zone: ZoneContext, spots: Geo.Spots)
	local folder = zone.folder
	local hd = zone.slot.depth / 2
	local z = hd + 17
	Geo.claim(spots, 0, z, 11)
	local center = Geo.at(zone, 0, z, 0)
	Pieces.cyl(folder, center - Vector3.new(0, 0.4, 0), 1, 16.6, C.piling, Enum.Material.Wood)
	Pieces.cyl(folder, center, 1.2, 15, C.driftwood, Enum.Material.WoodPlanks)
	-- yellow launch ring painted on the deck
	Pieces.cyl(
		folder,
		center + Vector3.new(0, 1.2, 0),
		0.08,
		9,
		C.slicker,
		Enum.Material.SmoothPlastic,
		false
	)
	Pieces.cyl(
		folder,
		center + Vector3.new(0, 1.22, 0),
		0.08,
		7.6,
		C.driftwood,
		Enum.Material.WoodPlanks,
		false
	)
	local anchors = {}
	for i = 0, 2 do
		local a = math.rad(i * 120 + 30)
		local p = center + Vector3.new(math.cos(a) * 6.4, 1.2, math.sin(a) * 6.4)
		Pieces.cyl(folder, p, 1.6, 0.9, C.harbor, Enum.Material.Metal)
		table.insert(anchors, p + Vector3.new(0, 1.5, 0))
	end
	-- winch beside the deck
	local winch = Geo.cf(zone, 9.5, z + 2, 0, 90)
	Pieces.box(
		folder,
		winch * CFrame.new(0, 1.2, 0),
		Vector3.new(3, 2.4, 3.6),
		C.harbor,
		Enum.Material.Metal
	)
	Kit.pipe(
		folder,
		(winch * CFrame.new(0, 2.8, -1.4)).Position,
		(winch * CFrame.new(0, 2.8, 1.4)).Position,
		1.8,
		{
			Color = C.slicker,
			Material = Enum.Material.Metal,
			CanCollide = false,
		}
	)
	-- the balloon, drifting a little downwind
	local balloonCenter = center + Vector3.new(0, 48, 0) + Pieces.WIND * 6
	Pieces.balloon(ctx, folder, balloonCenter, 20, C.beacon, C.sailcloth, anchors, true)
	-- control hut
	local hx, hz = -15, z + 3
	Geo.claim(spots, hx, hz, 6)
	Pieces.cottage(folder, Geo.faceField(zone, hx, hz), {
		width = 7,
		depth = 6,
		height = 4.6,
		roof = "slate",
		trim = C.seafoam,
		name = "LAUNCH",
		instrument = "anemometer",
	}, ctx.rng)
	Pieces.signBoard(
		folder,
		Geo.cf(zone, 0, z - 9.2, 2.6),
		9,
		1.8,
		"BALLOON LAUNCH",
		nil,
		Palette.SIGN,
		zone.slot.floor
	)
end

local STRIPE = Color3.fromRGB(64, 200, 196) -- saturated sea-glass teal

local function dress(ctx: Context, zone: ZoneContext)
	local rng = ctx.rng
	local folder = zone.folder
	local floor = zone.slot.floor
	local hw, hd = zone.slot.width / 2, zone.slot.depth / 2
	-- ground height (relative to the floor) at a zone-local spot
	local function groundAt(x: number, z: number): number
		return Geo.groundAt(ctx, zone, x, z) - floor
	end
	local spots: Geo.Spots = {}
	-- keep the gate landing and the lagoon free
	Geo.claim(spots, 0, -hd - 8, 9)
	Geo.claim(spots, -hw - MARGINS.side + 2, hd + MARGINS.back - 2, 11)
	-- beach-towel stripes: flush sea-glass inlays with cream piping, the
	-- top only 0.05 above the sand so the floor stays flat and clear
	local frame = zone.slot.frame
	local stripeW, gap = 7, 7
	local iw, id = hw - 3, hd - 3
	local n = math.floor((2 * id + gap) / (stripeW + gap))
	local span = n * stripeW + (n - 1) * gap
	for i = 0, n - 1 do
		local z = -span / 2 + stripeW / 2 + i * (stripeW + gap)
		local c = frame * CFrame.new(0, 0, z)
		local at = CFrame.new(c.Position.X, floor - 0.15, c.Position.Z) * frame.Rotation
		Pieces.box(
			folder,
			at,
			Vector3.new(2 * iw, 0.4, stripeW),
			STRIPE,
			Enum.Material.SmoothPlastic,
			false
		)
		for _, side in { -1, 1 } do
			Pieces.box(
				folder,
				at * CFrame.new(0, 0.01, side * (stripeW / 2 + 0.5)),
				Vector3.new(2 * iw, 0.4, 1),
				C.sailcloth,
				Enum.Material.SmoothPlastic,
				false
			)
		end
	end
	Geo.claim(spots, -hw - MARGINS.side + 2, hd * 0.2, 14) -- the cove

	balloonStation(ctx, zone, spots)
	if Geo.room(ctx, zone, 60) then
		pier(ctx, zone, spots)
	end

	-- Props are grouped into vignettes with open sand between them:
	-- a cabana row on one side, the tide tower with its umbrellas and
	-- deck chairs on the other, two palm groves at the back corners and
	-- the pier (above) behind the field.

	-- cabana row: three striped huts shoulder to shoulder
	local hutColors = { C.seafoam, C.slicker, C.beacon }
	local cabanaX, cabanaZ = hw + 10, -hd * 0.12
	for i, dz in { -8.5, 0, 8.5 } do
		if i > 1 and not Geo.room(ctx, zone, 30) then
			break
		end
		local hx, hz = cabanaX + (i % 2) * 1.5, cabanaZ + dz
		Geo.claim(spots, hx, hz, 5)
		local cf = Geo.facing(Geo.at(zone, hx, hz), Geo.at(zone, 0, hz))
		hut(folder, cf, hutColors[i])
		if i == 2 then
			-- surfboards leaning on the middle hut
			for k, off in { -1.1, 1.1 } do
				Pieces.box(
					folder,
					cf * CFrame.new(off + 4.2, 3, -1.5) * CFrame.Angles(0.25, 0, 0.12),
					Vector3.new(1.7, 6.4, 0.35),
					hutColors[k + 1],
					Enum.Material.SmoothPlastic,
					false
				)
			end
		end
	end

	-- tide watch tower at a front corner, looking out to sea, with the
	-- umbrella cluster at its feet
	local tx, tz = -hw - 9, -hd * 0.45
	Geo.claim(spots, tx, tz, 6)
	if Geo.room(ctx, zone, 30) then
		tideTower(ctx, folder, Geo.facing(Geo.at(zone, tx, tz), Geo.at(zone, tx - 20, tz - 12)))
	end
	local umbrellaColors = { C.beacon, C.slicker, C.seafoam, C.sailcloth }
	for i = 1, Geo.count(ctx, 5) do
		if not Geo.room(ctx, zone, 8) then
			break
		end
		local x, z = Geo.nearSpot(ctx, zone, spots, -hw - 10, -hd * 0.1, 12, 3.4, 3)
		if x and z then
			local base = Geo.at(zone, x, z)
			Pieces.umbrella(folder, base, umbrellaColors[i % #umbrellaColors + 1])
			local towel = Geo.faceField(zone, x, z) * CFrame.new(2.2, 0.06, 0.5)
			Pieces.box(
				folder,
				towel,
				Vector3.new(2.4, 0.12, 4.6),
				umbrellaColors[(i + 1) % #umbrellaColors + 1],
				Enum.Material.Fabric,
				false
			)
			if i % 2 == 0 then
				local chair = Geo.faceField(zone, x, z) * CFrame.new(-2.2, 0, 0.6)
				Pieces.box(
					folder,
					chair * CFrame.new(0, 0.8, 0),
					Vector3.new(1.8, 0.3, 2.6),
					C.sailcloth,
					Enum.Material.Fabric,
					false
				)
				Pieces.box(
					folder,
					chair * CFrame.new(0, 1.6, 1.4) * CFrame.Angles(math.rad(-30), 0, 0),
					Vector3.new(1.8, 2, 0.3),
					umbrellaColors[i % #umbrellaColors + 1],
					Enum.Material.Fabric,
					false
				)
			end
		end
	end

	-- two palm groves at the back corners
	local groves = { { hw + 11, hd * 0.6 }, { -hw - 11, hd * 0.55 } }
	for i = 1, Geo.count(ctx, 7) do
		if not Geo.room(ctx, zone, 6) then
			break
		end
		local g = groves[i % #groves + 1]
		local x, z = Geo.nearSpot(ctx, zone, spots, g[1], g[2], 11, 3, 6)
		if x and z then
			Pieces.palm(folder, Geo.at(zone, x, z, -0.5), rng:NextNumber(11, 15), rng)
		end
	end

	-- rowboat pulled up on the front beach
	local bx, bz = hw + 12, -hd - 19
	local boatY = groundAt(bx, bz) + 0.4
	Pieces.boat(
		folder,
		Geo.facing(Geo.at(zone, bx, bz, boatY), Geo.at(zone, bx + 5, bz + 6, boatY)),
		C.seafoam,
		9,
		false
	)

	-- buoys bobbing offshore (not across the boardwalk)
	local hwSea, hdFront, hdBack =
		hw + MARGINS.side + 24, hd + MARGINS.front + 22, hd + MARGINS.back + 24
	local buoyCount = Geo.count(ctx, 10)
	for i = 1, buoyCount do
		if not Geo.room(ctx, zone, 6) then
			break
		end
		local t = (i - 0.5) / buoyCount
		local x, z
		if t < 0.3 then
			x, z = hwSea, -hdFront + (hdFront + hdBack) * (t / 0.3)
		elseif t < 0.4 then
			x, z = hwSea - 2 * hwSea * ((t - 0.3) / 0.1), hdBack
		elseif t < 0.7 then
			x, z = -hwSea, hdBack - (hdFront + hdBack) * ((t - 0.4) / 0.3)
		else
			x, z = -hwSea + (2 * hwSea) * ((t - 0.7) / 0.3), -hdFront
		end
		if not (z < 0 and math.abs(x) < 16) then
			x, z = Geo.seaward(ctx, zone, x + rng:NextNumber(-3, 3), z + rng:NextNumber(-3, 3), 3)
			local p = Geo.at(zone, x, z)
			Pieces.buoy(
				folder,
				Vector3.new(p.X, 0.2, p.Z),
				if i % 2 == 0 then C.beacon else C.slicker
			)
		end
	end

	-- driftwood, shells, beach grass and rocks
	for _ = 1, Geo.count(ctx, 4) do
		if not Geo.room(ctx, zone, 6) then
			break
		end
		local x, z = Geo.findSpot(ctx, zone, spots, 14, 26, 2, false, true)
		if x and z then
			local a = Geo.at(zone, x, z, groundAt(x, z) + 0.4)
			local b = a + Vector3.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3))
			Pieces.rod(
				folder,
				a,
				b + Vector3.new(0, 0.2, 0),
				rng:NextNumber(0.7, 1.1),
				Palette.plankLight,
				Enum.Material.Wood
			)
		end
	end
	for _ = 1, Geo.count(ctx, 12) do
		if not Geo.room(ctx, zone, 6) then
			break
		end
		local x, z = Geo.rimPoint(ctx, zone, 3, 14, false)
		local p = Geo.at(zone, x, z, 0.15)
		Pieces.ball(
			folder,
			p,
			rng:NextNumber(0.4, 0.7),
			if rng:NextNumber() < 0.5 then C.sailcloth else C.beacon:Lerp(C.sailcloth, 0.5),
			Enum.Material.SmoothPlastic,
			false
		)
	end
	for _ = 1, Geo.count(ctx, 16) do
		if not Geo.room(ctx, zone, 6) then
			break
		end
		local x, z = Geo.findSpot(ctx, zone, spots, 3, 16, 1, true)
		if x and z then
			Pieces.tuft(folder, Geo.at(zone, x, z, 0), rng)
		end
	end
	for _ = 1, Geo.count(ctx, 6) do
		if not Geo.room(ctx, zone, 6) then
			break
		end
		local x, z = Geo.findSpot(ctx, zone, spots, 5, 20, 2, false)
		if x and z then
			Pieces.rocks(folder, Geo.at(zone, x, z), rng:NextNumber(2, 3.5), rng)
		end
	end
end

local theme: Theme = {
	margins = MARGINS,
	field = {
		base = Enum.Material.Sand,
		accent = Enum.Material.Sand, -- stripes are flush part inlays (see dress)
		trim = Enum.Material.WoodPlanks,
		pattern = "across",
		cell = 12,
	},
	border = {
		postColor = C.driftwood,
		postMaterial = Enum.Material.Wood,
		postDiameter = 0.9,
		postHeight = 3.4,
		stones = false,
	},
	ground = ground,
	dress = dress,
}
Beach.theme = theme

return Beach
