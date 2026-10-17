--!strict
-- Canyon theme (Mesa): Ember Mesa, a sunset-red canyon isle. The field is
-- twilight-violet strata stripes (complementary to the orange warning
-- circles), the cliffs are banded ember and ochre, hoodoos, cacti and a
-- crystal mine line the rim, and the hero is the Crystal Butte: a tall
-- layered butte crowned with a giant amber crystal and a lightning rod.

local ServerScriptService = game:GetService("ServerScriptService")

local World = ServerScriptService.Server.World
local Kit = require(World.Kit)
local WorldTypes = require(World.Types)
local Palette = require(script.Parent.Parent.Palette)
local Pieces = require(script.Parent.Parent.Pieces)
local SkyTypes = require(script.Parent.Parent.SkyTypes)
local Zone = require(script.Parent.Parent.Zone)

type Context = WorldTypes.Context
type ZoneContext = WorldTypes.ZoneContext
type ThemeSpec = SkyTypes.ThemeSpec
type Land = SkyTypes.Land

local C = Palette.C
local UP = Vector3.yAxis

local Canyon = {}

function Canyon.spec(zone: ZoneContext): ThemeSpec
	return {
		rim = Enum.Material.Sandstone,
		terrace = Enum.Material.Ground,
		cliffs = {
			Enum.Material.Ground,
			Enum.Material.Sandstone,
			Enum.Material.Ground,
			Enum.Material.Slate,
			Enum.Material.Basalt,
		},
		fieldTerrain = Enum.Material.Ground,
		field = {
			kind = "bands",
			axis = "x",
			colors = Palette.fieldTones(zone.color, C.twilightDeep, C.twilightLight),
			materials = { Enum.Material.Sandstone, Enum.Material.Sandstone },
			size = 10,
			widths = { 1.3, 0.7 },
		},
		accent = C.gold,
		depth = 62,
		ridge = Enum.Material.Sandstone,
		ridgeHeight = 14,
		spires = Enum.Material.Sandstone,
	}
end

-- Stacked strata: cylinders shrinking upward, alternating ember and ochre.
local function strata(ctx: Context, center: Vector3, floor: number, radii: { number }, step: number)
	local materials = { Enum.Material.Sandstone, Enum.Material.Ground }
	-- root it into the island
	ctx.terrain:FillCylinder(
		CFrame.new(center.X, floor - 10, center.Z),
		24,
		radii[1],
		Enum.Material.Sandstone
	)
	for i, radius in radii do
		local top = floor + i * step
		ctx.terrain:FillCylinder(
			CFrame.new(center.X, top - step / 2 - 1, center.Z),
			step + 2,
			radius,
			materials[(i - 1) % 2 + 1]
		)
	end
end

-- A hoodoo: stacked rock lumps with a flat cap stone.
local function hoodoo(parent: Instance, rng: Random, foot: Vector3, height: number)
	local y = 0
	local pieces: { { width: number, share: number, color: Color3 } } = {
		{ width = 3, share = 0.34, color = C.ember },
		{ width = 2.4, share = 0.26, color = C.emberLight },
		{ width = 2, share = 0.24, color = C.ember },
	}
	for _, piece in pieces do
		local width, share, color = piece.width, piece.share, piece.color
		local h = height * share
		Pieces.solid(
			parent,
			CFrame.new(foot + UP * (y + h / 2)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
			Vector3.new(width, h, width),
			color,
			Enum.Material.Sandstone
		)
		y += h
	end
	Pieces.ball(parent, foot + UP * (y + 0.6), 2.6, C.emberLight, Enum.Material.Sandstone)
	Pieces.solid(
		parent,
		CFrame.new(foot + UP * (y + 1.8)) * CFrame.Angles(0.08, rng:NextNumber(0, math.pi), 0.05),
		Vector3.new(4.6, 1, 4),
		C.emberDark,
		Enum.Material.Sandstone
	)
end

local function cactus(parent: Instance, rng: Random, foot: Vector3, height: number)
	local green = C.seaglass:Lerp(C.meadowDark, 0.5)
	Pieces.cylinder(parent, foot, height, 1.4, green, Enum.Material.Grass, { CanCollide = true })
	Pieces.ball(parent, foot + UP * height, 1.4, green, Enum.Material.Grass)
	local yaw = rng:NextNumber(0, math.pi * 2)
	for side = -1, 1, 2 do
		local out = Vector3.new(math.cos(yaw), 0, math.sin(yaw)) * side
		local armY = height * (if side == 1 then 0.5 else 0.65)
		local elbow = foot + UP * armY + out * 2
		Pieces.pipe(parent, foot + UP * armY, elbow, 1, green, Enum.Material.Grass)
		Pieces.cylinder(parent, elbow - UP * 0.4, height * 0.3, 1, green, Enum.Material.Grass)
	end
	Pieces.ball(parent, foot + UP * (height + 0.7), 0.7, C.coral, Enum.Material.SmoothPlastic)
end

-- Mine cart full of crystals on a short track with a lantern post.
local function mineCart(
	parent: Instance,
	rng: Random,
	start: Vector3,
	finish: Vector3,
	color: Color3
)
	local dir = (finish - start) * Vector3.new(1, 0, 1)
	local frame = CFrame.lookAt(start, start + dir)
	local length = dir.Magnitude
	for side = -1, 1, 2 do
		Pieces.block(
			parent,
			frame * CFrame.new(side * 1.3, 0.25, -length / 2),
			Vector3.new(0.3, 0.3, length),
			C.iron,
			Enum.Material.Metal
		)
	end
	for s = 1, length - 1, 3 do
		Pieces.block(
			parent,
			frame * CFrame.new(0, 0.1, -s),
			Vector3.new(3.6, 0.25, 0.8),
			C.wood,
			Enum.Material.Wood
		)
	end
	local cart = frame * CFrame.new(0, 1.8, -length * 0.6)
	Pieces.solid(parent, cart, Vector3.new(3, 2.2, 4.4), C.iron, Enum.Material.Metal)
	Pieces.block(
		parent,
		cart * CFrame.new(0, 1.15, 0),
		Vector3.new(3.3, 0.3, 4.7),
		C.emberDark,
		Enum.Material.Wood
	)
	for _, corner in
		{
			Vector3.new(-1.6, -1.1, -1.4),
			Vector3.new(1.6, -1.1, -1.4),
			Vector3.new(-1.6, -1.1, 1.4),
			Vector3.new(1.6, -1.1, 1.4),
		}
	do
		local wheel = cart:PointToWorldSpace(corner)
		Pieces.pipe(
			parent,
			wheel - cart.RightVector * 0.2,
			wheel + cart.RightVector * 0.2,
			1.2,
			C.plumDeep,
			Enum.Material.Metal
		)
	end
	local load = cart:PointToWorldSpace(Vector3.new(0, 1, 0))
	local main = Pieces.cluster(parent, rng, load, 3.2, color, 3)
	Pieces.light(main, color, 14, 1)
end

-- Wooden post with a hanging lantern.
local function lanternPost(
	parent: Instance,
	foot: Vector3,
	facing: Vector3,
	color: Color3,
	range: number?
)
	local out = (facing * Vector3.new(1, 0, 1)).Unit
	Pieces.cylinder(parent, foot, 8, 0.8, C.wood, Enum.Material.Wood, { CanCollide = true })
	Pieces.plank(
		parent,
		foot + UP * 7.6,
		foot + UP * 7.6 + out * 2.4,
		0.5,
		0.5,
		C.wood,
		Enum.Material.Wood
	)
	Pieces.lantern(parent, foot + UP * 6.2 + out * 2.2, color, range)
end

function Canyon.dress(ctx: Context, zone: ZoneContext, _spec: ThemeSpec, land: Land)
	local slot = zone.slot
	local frame = slot.frame
	local folder = zone.folder
	local rng = ctx.rng
	local floor = slot.floor
	local hw, hd = slot.width / 2, slot.depth / 2
	local toHub = frame.LookVector

	-- hero: the Crystal Butte behind the field
	local butte = frame:PointToWorldSpace(Vector3.new(0, 0, hd + 19))
	if Pieces.clearOf(ctx, butte, 17, zone) then
		strata(ctx, butte, floor, { 16, 14.5, 13, 11.5, 10 }, 7)
		local summit = Vector3.new(butte.X, floor + 35, butte.Z)
		local crystal = Pieces.bigShard(folder, summit - UP * 1, 18, 7, C.gold, zone.color, 15, 4)
		Pieces.bigShard(folder, summit + toHub * 3.5 - UP * 1, 11, 4.5, C.gold, zone.color, 40, -24)
		Pieces.bigShard(
			folder,
			summit - toHub * 3 + frame.RightVector * 3 - UP * 1,
			9,
			4,
			C.gold,
			zone.color,
			70,
			26
		)
		Pieces.light(crystal, zone.color, 50, 2)
		Pieces.sparkles(crystal, C.gold, 6, 1.4)
		-- lightning rod beside the crystal
		local rodFoot = summit + frame.RightVector * -5 - UP * 0.5
		Pieces.cylinder(folder, rodFoot, 14, 0.5, C.plumDeep, Enum.Material.Metal)
		Pieces.ball(folder, rodFoot + UP * 14.2, 1.2, C.gold, Enum.Material.Metal)
		Pieces.ring(ctx, summit + UP * 8, 9, Vector3.new(1, 0.2, 0).Unit, Vector3.zAxis, 12, {
			color = zone.color,
			width = 0.4,
			glow = 1,
		})
		Pieces.arc(ctx, rodFoot + UP * 14.2, summit + UP * 12, 3, 1, {
			color = C.gold,
			color1 = C.cream,
			width = 0.3,
			glow = 1,
		})
	end

	-- smaller strata buttes at the back corners
	for _, u in { -1, 1 } do
		local p = frame:PointToWorldSpace(Vector3.new(u * (hw + 11), 0, hd * 0.55))
		if Pieces.clearOf(ctx, p, 10, zone) then
			strata(ctx, p, floor, { 9, 7.5, 6 }, 5)
			local cap =
				Pieces.cluster(folder, rng, Vector3.new(p.X, floor + 15, p.Z), 5, zone.color, 3)
			if u == 1 then
				Pieces.light(cap, zone.color, 20, 1.2)
			end
		end
	end

	-- hoodoos, cacti and lantern posts around the rim
	for i, p in Zone.rimPoints(ctx, zone, land, 9, 3, 4) do
		if i <= 4 then
			hoodoo(folder, rng, p, rng:NextNumber(8, 12))
		elseif i <= 7 then
			cactus(folder, rng, p, rng:NextNumber(5, 7))
		else
			lanternPost(folder, p, toHub, C.gold, if i == 8 then 18 else nil)
		end
	end

	-- a headland on the left side with the crystal mine cart track
	local function at(x: number, z: number): Vector3
		return frame:PointToWorldSpace(Vector3.new(x, 0, z))
	end
	local mine = at(-(land.halfW + 6), -hd * 0.15)
	if Pieces.clearOf(ctx, mine, 17, zone) then
		Pieces.headland(ctx, mine, 13, floor, Enum.Material.Sandstone, Enum.Material.Ground)
		local trackStart = at(-(land.halfW + 4), -hd * 0.15 - 10)
		local trackEnd = at(-(land.halfW + 4), -hd * 0.15 + 9)
		mineCart(folder, rng, trackStart, trackEnd, zone.color)
		lanternPost(folder, at(-(land.halfW + 9), -hd * 0.15 + 4), frame.RightVector, C.gold, 16)
		Pieces.cluster(folder, rng, at(-(land.halfW + 12), -hd * 0.15 - 4), 6, zone.color, 4)
	end

	-- a natural sandstone arch on the right-hand rim
	local archA = at(hw + 9, -hd * 0.45 - 10)
	local archB = at(hw + 9, -hd * 0.45 + 10)
	if Pieces.clearOf(ctx, archA, 6, zone) and Pieces.clearOf(ctx, archB, 6, zone) then
		for _, leg in { archA, archB } do
			ctx.terrain:FillCylinder(
				CFrame.new(leg.X, floor + 4, leg.Z),
				24,
				4.5,
				Enum.Material.Sandstone
			)
		end
		local middle = (archA + archB) / 2
		ctx.terrain:FillBlock(
			CFrame.lookAt(
				Vector3.new(middle.X, floor + 17, middle.Z),
				Vector3.new(archB.X, floor + 17, archB.Z)
			),
			Vector3.new(8, 6, 30),
			Enum.Material.Sandstone
		)
		ctx.terrain:FillBlock(
			CFrame.lookAt(
				Vector3.new(middle.X, floor + 21, middle.Z),
				Vector3.new(archB.X, floor + 21, archB.Z)
			),
			Vector3.new(6, 2, 22),
			Enum.Material.Ground
		)
	end

	-- ochre patches in the red sand
	for _, p in Zone.rimPoints(ctx, zone, land, 5, 5, 6) do
		Kit.blob(
			ctx,
			Vector3.new(p.X, 0, p.Z),
			rng:NextNumber(3.5, 5.5),
			floor,
			4,
			Enum.Material.Ground,
			4
		)
	end

	-- rocks, dry brush and crystal shards on the rim and terraces
	for _, p in Zone.rimPoints(ctx, zone, land, 12, 1.5, 1.5) do
		local roll = rng:NextNumber()
		if roll < 0.45 then
			Pieces.rocks(folder, rng, p, rng:NextNumber(1.6, 3.2), C.emberDark)
		elseif roll < 0.75 then
			Pieces.bush(
				folder,
				rng,
				p,
				rng:NextNumber(1.6, 2.4),
				C.goldDeep:Lerp(C.meadowDark, 0.45)
			)
		else
			Pieces.shard(
				folder,
				p,
				rng:NextNumber(2.5, 4),
				0.8,
				zone.color,
				rng:NextNumber(0, 360),
				rng:NextNumber(10, 30)
			)
		end
	end
	for i, terrace in land.terraces do
		if i % 2 == 0 then
			hoodoo(folder, rng, terrace.center, rng:NextNumber(7, 10))
		else
			Pieces.cluster(folder, rng, terrace.center, rng:NextNumber(4, 6), zone.color, 3)
		end
	end
end

return Canyon
