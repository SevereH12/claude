--!strict
-- Beach theme (Shoreline): Cloudshore, a sandy isle drifting on the cloud
-- sea. The field is seaglass and teal bands (cool tones so yellow warning
-- circles pop), the rim is golden beach with palms, parasols, shells and
-- tide pools spilling waterfalls into the clouds, a sky-skiff is moored at
-- a little pier, and the hero is a striped Sky Lighthouse on a rock point.

local ServerScriptService = game:GetService("ServerScriptService")

local World = ServerScriptService.Server.World
local Blocks = require(World.Blocks)
local Kit = require(World.Kit)
local WorldTypes = require(World.Types)
local Ground = require(script.Parent.Parent.Ground)
local Palette = require(script.Parent.Parent.Palette)
local Pieces = require(script.Parent.Parent.Pieces)
local SkyTypes = require(script.Parent.Parent.SkyTypes)
local Zone = require(script.Parent.Parent.Zone)

type Context = WorldTypes.Context
type ZoneContext = WorldTypes.ZoneContext
type ThemeSpec = SkyTypes.ThemeSpec
type Land = SkyTypes.Land

local C = Palette.C
local G = Palette.GROUND
local UP = Vector3.yAxis

local Beach = {}

function Beach.spec(zone: ZoneContext): ThemeSpec
	return {
		rim = G.sand,
		soil = G.sandWet,
		cliffs = { G.rockLight, G.rock, G.slate },
		field = {
			kind = "rings",
			colors = Palette.fieldTones(zone.color, C.fieldMint, C.fieldTeal),
			materials = { Enum.Material.SmoothPlastic, Enum.Material.SmoothPlastic },
			size = 10,
		},
		accent = C.cyan,
		depth = 58,
		-- a broad beach: the sand reaches further on the sides and back
		shore = 6,
		ridge = G.dune,
		ridgeHeight = 6,
		ridgeShape = "dunes",
		ridgeCap = G.grassDeep,
		spires = G.rock,
	}
end

-- Striped lighthouse standing on `foot` with its door toward `facing`;
-- its lamp throws a light beam along each of `beams`.
function Beach.lighthouse(
	ctx: Context,
	parent: Instance,
	foot: Vector3,
	facing: Vector3,
	beams: { Vector3 }
)
	Pieces.cylinder(
		parent,
		foot - UP * 1,
		4,
		15,
		C.plum,
		Enum.Material.Slate,
		{ CanCollide = true }
	)
	Pieces.cylinder(parent, foot + UP * 3, 1, 13, C.gold, Enum.Material.Metal)
	-- tapering striped tower
	local y = 3
	local bands: { { diameter: number, height: number, color: Color3 } } = {
		{ diameter = 11.5, height = 8, color = C.cream },
		{ diameter = 10.6, height = 7, color = C.coral },
		{ diameter = 9.8, height = 7, color = C.cream },
		{ diameter = 9, height = 7, color = C.coral },
		{ diameter = 8.4, height = 6, color = C.cream },
	}
	for _, band in bands do
		local diameter, height, color = band.diameter, band.height, band.color
		Pieces.cylinder(
			parent,
			foot + UP * y,
			height,
			diameter,
			color,
			Enum.Material.SmoothPlastic,
			{
				CanCollide = true,
			}
		)
		y += height
	end
	local dir = (facing * Vector3.new(1, 0, 1)).Unit
	-- door and windows facing the hub
	Pieces.block(
		parent,
		CFrame.lookAt(foot + UP * 6.5 + dir * 5.6, foot + UP * 6.5 + dir * 10),
		Vector3.new(3, 5, 0.6),
		C.plum,
		Enum.Material.Wood
	)
	for _, h in { 15, 24 } do
		Pieces.block(
			parent,
			CFrame.lookAt(foot + UP * h + dir * 4.9, foot + UP * h + dir * 10),
			Vector3.new(1.4, 2.4, 0.4),
			C.cyan,
			Enum.Material.Neon
		)
	end
	-- gallery and rail
	Pieces.cylinder(parent, foot + UP * y, 1.2, 13.5, C.plum, Enum.Material.Slate)
	local gallery = foot + UP * (y + 1.2)
	local railPoints: { Vector3 } = {}
	for k = 0, 7 do
		local angle = k / 8 * math.pi * 2
		local p = gallery + Vector3.new(math.cos(angle), 0, math.sin(angle)) * 6.2
		Pieces.block(
			parent,
			CFrame.new(p + UP * 1),
			Vector3.new(0.35, 2, 0.35),
			C.plumDeep,
			Enum.Material.Metal
		)
		table.insert(railPoints, p + UP * 2)
	end
	for k = 1, #railPoints do
		Pieces.beam(
			ctx,
			railPoints[k],
			railPoints[k % #railPoints + 1],
			{ color = C.plumDeep, width = 0.25 }
		)
	end
	-- lamp room: glass drum with a storm-crystal lamp
	local lampRoom =
		Pieces.cylinder(parent, gallery, 6, 7, C.cyan, Enum.Material.Glass, { Transparency = 0.45 })
	lampRoom.Reflectance = 0.2
	local lamp = Pieces.diamond(parent, gallery + UP * 3, 3.2, C.cyan)
	Pieces.light(lamp, C.cyan, 48, 2.2)
	Pieces.sparkles(lamp, C.cyan, 5, 1.2)
	for _, out in beams do
		Pieces.beam(ctx, gallery + UP * 3, gallery + UP * 1 + out * 34, {
			color = C.cream,
			color1 = C.cyan,
			width = 2,
			width1 = 16,
			glow = 1,
			transparency = 0.55,
			transparency1 = 1,
		})
	end
	-- coral roof cone, finial and lightning rod
	local roof = gallery + UP * 6
	local cone: { { diameter: number, color: Color3 } } = {
		{ diameter = 8.6, color = C.coral },
		{ diameter = 6.6, color = C.coral },
		{ diameter = 4.6, color = C.coralLight },
		{ diameter = 2.6, color = C.coral },
	}
	for i, ring in cone do
		Pieces.cylinder(
			parent,
			roof + UP * ((i - 1) * 1.3),
			1.3,
			ring.diameter,
			ring.color,
			Enum.Material.ClayRoofTiles
		)
	end
	Pieces.ball(parent, roof + UP * 5.8, 1.6, C.gold, Enum.Material.Metal)
	Pieces.cylinder(parent, roof + UP * 6.4, 4, 0.3, C.plumDeep, Enum.Material.Metal)
	Pieces.diamond(parent, roof + UP * 10.6, 0.8, C.cyan)
end

-- Parasol with two deck chairs.
local function parasol(parent: Instance, rng: Random, foot: Vector3, color: Color3)
	if Pieces.overBudget(parent) then
		return
	end
	Pieces.cylinder(parent, foot, 6.5, 0.35, C.cream, Enum.Material.Metal)
	Pieces.cylinder(parent, foot + UP * 6.2, 0.5, 8, color, Enum.Material.Fabric)
	Pieces.cylinder(parent, foot + UP * 6.7, 0.5, 5, C.cream, Enum.Material.Fabric)
	Pieces.ball(parent, foot + UP * 7.4, 0.7, color, Enum.Material.Fabric)
	local yaw = rng:NextNumber(0, math.pi * 2)
	for side = -1, 1, 2 do
		local seat = foot
			+ Vector3.new(math.cos(yaw + side * 0.6), 0, math.sin(yaw + side * 0.6)) * 3.2
		local frame =
			CFrame.lookAt(seat + UP * 0.6, seat + UP * 0.6 + (seat - foot) * Vector3.new(1, 0, 1))
		Pieces.block(parent, frame, Vector3.new(1.8, 0.3, 3.6), C.woodLight, Enum.Material.Wood)
		Pieces.block(
			parent,
			frame * CFrame.new(0, 0.7, -1.6) * CFrame.Angles(math.rad(-55), 0, 0),
			Vector3.new(1.8, 0.3, 2),
			if side == 1 then color else C.cream,
			Enum.Material.Fabric
		)
	end
end

-- A sky-skiff: little boat hull under a balloon, moored off the rim.
local function skiff(ctx: Context, parent: Instance, center: Vector3, along: Vector3)
	local frame = CFrame.lookAt(center, center + along)
	Pieces.block(parent, frame, Vector3.new(4.4, 2, 9), C.wood, Enum.Material.Wood)
	Pieces.wedge(
		parent,
		frame * CFrame.new(0, 0, -6.5) * CFrame.Angles(0, math.pi, 0),
		Vector3.new(4.4, 2, 4),
		C.wood,
		Enum.Material.Wood
	)
	Pieces.wedge(
		parent,
		frame * CFrame.new(0, 0, 6),
		Vector3.new(4.4, 2, 3),
		C.wood,
		Enum.Material.Wood
	)
	Pieces.block(
		parent,
		frame * CFrame.new(0, 1.1, 0),
		Vector3.new(4.6, 0.3, 9.2),
		C.woodLight,
		Enum.Material.Wood
	)
	Pieces.block(
		parent,
		frame * CFrame.new(0, -0.6, 0),
		Vector3.new(4.5, 0.5, 9.1),
		C.coral,
		Enum.Material.Wood
	)
	local balloon = (frame * CFrame.new(0, 11, 0)).Position
	Pieces.ball(parent, balloon, 10, C.coral, Enum.Material.Fabric)
	Pieces.cylinder(parent, balloon - UP * 0.6, 1.2, 10.4, C.cream, Enum.Material.Fabric)
	for _, corner in
		{
			Vector3.new(-2, 1, -4),
			Vector3.new(2, 1, -4),
			Vector3.new(-2, 1, 4),
			Vector3.new(2, 1, 4),
		}
	do
		local deck = frame:PointToWorldSpace(corner)
		Pieces.beam(ctx, deck, balloon + (deck - center) * Vector3.new(0.6, 0, 0.6) - UP * 3.5, {
			color = C.woodLight,
			width = 0.15,
		})
	end
	local lantern = Pieces.lantern(parent, (frame * CFrame.new(0, 2.6, 3.5)).Position, C.gold, nil)
	lantern.Name = "SkiffLantern"
end

-- A little beach cabana: four posts, a plank floor and a coral roof.
local function cabana(parent: Instance, foot: Vector3, facing: Vector3)
	local frame = CFrame.lookAt(foot, foot + facing * Vector3.new(1, 0, 1))
	Pieces.solid(
		parent,
		frame * CFrame.new(0, 0.3, 0),
		Vector3.new(7, 0.6, 6),
		C.woodLight,
		Enum.Material.WoodPlanks
	)
	for _, corner in
		{
			Vector3.new(-3, 0, -2.5),
			Vector3.new(3, 0, -2.5),
			Vector3.new(-3, 0, 2.5),
			Vector3.new(3, 0, 2.5),
		}
	do
		Pieces.solid(
			parent,
			frame * CFrame.new(corner + UP * 3.3),
			Vector3.new(0.6, 5.4, 0.6),
			C.wood,
			Enum.Material.Wood
		)
	end
	for side = -1, 1, 2 do
		Pieces.wedge(
			parent,
			frame
				* CFrame.new(0, 7.1, side * 1.9)
				* CFrame.Angles(0, if side == 1 then 0 else math.pi, 0),
			Vector3.new(8, 2.2, 3.8),
			C.coral,
			Enum.Material.ClayRoofTiles
		)
	end
	Pieces.block(
		parent,
		frame * CFrame.new(0, 5.6, -2.9),
		Vector3.new(7, 1.2, 0.2),
		C.cream,
		Enum.Material.Fabric
	)
	local lamp = Pieces.lantern(parent, (frame * CFrame.new(0, 4.6, -3.4)).Position, C.gold, 16)
	lamp.Name = "CabanaLantern"
end

function Beach.dress(ctx: Context, zone: ZoneContext, spec: ThemeSpec, land: Land)
	local slot = zone.slot
	local frame = slot.frame
	local folder = zone.folder
	local rng = ctx.rng
	local floor = slot.floor
	local hw, hd = slot.width / 2, slot.depth / 2
	local toHub = frame.LookVector
	local function at(x: number, z: number): Vector3
		return frame:PointToWorldSpace(Vector3.new(x, 0, z))
	end

	-- hero: lighthouse on a rocky point at the end of a sandy headland
	local tones = Zone.tones(spec)
	local headlandSpot, scale = Pieces.heroSpot(ctx, zone, 20, 15)
	if headlandSpot then
		local headland = headlandSpot
		local out = Zone.outward(zone, headland)
		local side = out:Cross(UP)
		Pieces.headland(ctx, headland, 17 * scale, floor, tones)
		-- the rock point: two stepped rock tiers rising out of the sand
		local point = headland + out * 5.6
		local yaw = CFrame.Angles(0, math.atan2(out.X, out.Z), 0)
		Ground.poly(ctx, G.rock, CFrame.new(point.X, floor + 4, point.Z) * yaw, 8, 12, 8, "Rock")
		Ground.poly(
			ctx,
			G.rockLight,
			CFrame.new(point.X, floor + 8, point.Z) * yaw * CFrame.Angles(0, math.pi / 8, 0),
			5.6,
			4.5,
			8,
			"Rock"
		)
		Beach.lighthouse(ctx, folder, Vector3.new(point.X, floor + 8, point.Z), toHub, {
			(frame.RightVector * 0.8 - frame.LookVector * 0.6).Unit,
			(frame.RightVector * 0.2 - frame.LookVector).Unit,
		})
		Pieces.rocks(folder, rng, headland + side * 7 + out * 2, 3.2, C.skystone)
		Pieces.palm(folder, rng, headland - side * 6 + out * 4, 12, out)
	end

	-- a second headland on the far side with a cabana, a pier and the skiff
	local dockZ = -hd * 0.5
	local dock = at(-(land.halfW + 6), dockZ)
	if Pieces.clearOf(ctx, dock, 18, zone) then
		Pieces.headland(ctx, dock, 13, floor, tones)
		local outward = -frame.RightVector
		cabana(folder, at(-(land.halfW + 3), dockZ + 7), outward)
		local pierStart = at(-(land.halfW + 12), dockZ - 4)
		local pierEnd = at(-(land.halfW + 24), dockZ - 4)
		Kit.walkway(folder, pierStart + UP * 0.6, pierEnd + UP * 0.6, 4, 0.6, {
			Name = "Pier",
			Color = C.woodLight,
			Material = Enum.Material.WoodPlanks,
		})
		for _, t in { 0.5, 1 } do
			local post = pierStart:Lerp(pierEnd, t)
			for s = -1, 1, 2 do
				local foot = post + (pierEnd - pierStart):Cross(UP).Unit * s * 2.1
				Pieces.cylinder(folder, foot - UP * 5, 7, 0.6, C.wood, Enum.Material.Wood)
			end
		end
		skiff(
			ctx,
			folder,
			pierEnd + outward * 4 + frame.LookVector * 5 + UP * 1.5,
			frame.LookVector
		)
		Pieces.palm(folder, rng, at(-(land.halfW + 8), dockZ - 10), 11, outward)
	end

	-- tide pools on the rim; two spill waterfalls off the edge
	local spills = 0
	for _, u in { -1, 1 } do
		local spots: { number } = if u == 1 then { -0.35, -0.02 } else { -0.02 }
		for _, v in spots do
			local l = Vector3.new(u * (hw + 6.5), 0, v * slot.depth)
			local p = frame:PointToWorldSpace(l)
			if Pieces.clearOf(ctx, p, 4, zone) and Zone.unblocked(land, p, 4) then
				Ground.water(
					folder,
					Palette.WATER,
					CFrame.new(p + UP * 0.06) * frame.Rotation * CFrame.Angles(0, math.pi / 4, 0),
					Vector2.new(5.6, 5.6),
					"TidePool"
				)
				Pieces.rocks(folder, rng, p + frame.RightVector * u * 3.5, 1.6, C.skystone)
				if spills < 2 and (u == 1 or v > -0.1) and v < 0 then
					spills += 1
					local outward = frame.RightVector * u
					local lip =
						frame:PointToWorldSpace(Vector3.new(u * (land.halfW + 1), -0.6, l.Z))
					local channel = Vector3.new(p.X, floor + 0.06, p.Z):Lerp(lip + UP * 0.66, 0.5)
					Ground.water(
						folder,
						Palette.WATER,
						CFrame.lookAt(channel, channel + outward),
						Vector2.new(2.6, (lip - p).Magnitude),
						"Spill"
					)
					Pieces.waterfall(ctx, lip, outward, 90, 3)
				end
			end
		end
	end

	-- dune grass patches and boulders along the shore
	for _, p in Zone.rimPoints(ctx, zone, land, 5, 5, 6) do
		Pieces.turf(folder, p, rng:NextNumber(3.5, 5.5), G.grassDeep, rng:NextNumber(0, 90))
	end
	for _ = 1, 6 do
		local side = rng:NextNumber()
		local edge = if side < 0.6
			then at(
				(if side < 0.3 then -1 else 1) * (land.halfW - 3),
				rng:NextNumber(-0.7, 0.2) * hd
			)
			else at(rng:NextNumber(-0.8, 0.8) * hw, land.back - 3)
		if
			Zone.onRim(zone, land, edge, 6, 1)
			and Zone.unblocked(land, edge, 2)
			and Pieces.clearOf(ctx, edge, 5, zone)
		then
			Blocks.rock(folder, G.rock, edge, rng:NextNumber(5, 7))
		end
	end

	-- palms and parasols along the beach
	local palms = Zone.rimPoints(ctx, zone, land, 7, 5, 4)
	for i, p in palms do
		if i <= 5 then
			Pieces.palm(folder, rng, p, rng:NextNumber(10, 13), Zone.outward(zone, p))
		else
			parasol(folder, rng, p, if i % 2 == 0 then C.coral else C.cyanDeep)
		end
	end

	-- shells, starfish, sea-grass tufts and rocks in the sand
	for _, p in Zone.rimPoints(ctx, zone, land, 9, 1.5, 1.5) do
		local roll = rng:NextNumber()
		if roll < 0.35 then
			Pieces.ball(
				folder,
				p + UP * 0.2,
				rng:NextNumber(0.7, 1.1),
				C.coralLight,
				Enum.Material.SmoothPlastic
			)
		elseif roll < 0.55 then
			local yaw = rng:NextNumber(0, 180)
			for k = 0, 1 do
				Pieces.block(
					folder,
					CFrame.new(p + UP * 0.1) * CFrame.Angles(0, math.rad(yaw + k * 72), 0),
					Vector3.new(0.4, 0.2, 2),
					C.coral
				)
			end
		elseif roll < 0.8 then
			for k = 1, 3 do
				Pieces.block(
					folder,
					CFrame.new(p + UP * 1)
						* CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
						* CFrame.Angles(math.rad(rng:NextNumber(-20, 20)), 0, 0),
					Vector3.new(0.3, rng:NextNumber(1.6, 2.6), 0.6),
					if k % 2 == 0 then C.meadow else C.seaglass,
					Enum.Material.Grass
				)
			end
		else
			Pieces.pipe(
				folder,
				p + UP * 0.3,
				p + UP * 0.5 + Vector3.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3)),
				0.7,
				C.woodLight,
				Enum.Material.Wood
			)
		end
	end

	-- crystals and palms on the coast lobes
	for i, terrace in land.terraces do
		if not Zone.unblocked(land, terrace.center, 2) then
			continue
		elseif terrace.top < floor then
			if i % 2 == 1 then
				local main =
					Pieces.cluster(folder, rng, terrace.center, rng:NextNumber(5, 7), C.cyan, 3)
				if i == 1 then
					Pieces.light(main, C.cyan, 14, 1)
				end
			else
				Pieces.palm(
					folder,
					rng,
					terrace.center,
					rng:NextNumber(9, 12),
					Zone.outward(zone, terrace.center)
				)
			end
		else
			Pieces.palm(
				folder,
				rng,
				terrace.center,
				rng:NextNumber(10, 13),
				Zone.outward(zone, terrace.center)
			)
			parasol(folder, rng, terrace.center + Zone.outward(zone, terrace.center) * 6, C.coral)
		end
	end
end

return Beach
