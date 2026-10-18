--!strict
-- Default theme: the Rune Garden. Used for any zone theme SkyIsles has no
-- module for, so it reads well in any zone colour: the field is a
-- checkerboard in the complementary hue of the zone colour (warning circles
-- always stand out), the rim is a grassy garden with crystal trees and
-- lanterns, and the hero is a tall Rune Obelisk with a floating crystal.

local ServerScriptService = game:GetService("ServerScriptService")

local World = ServerScriptService.Server.World
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

local Default = {}

function Default.spec(zone: ZoneContext): ThemeSpec
	local light, dark = Palette.complement(zone.color)
	return {
		rim = G.grass,
		soil = G.soil,
		cliffs = { G.rock, G.slate, G.basalt },
		field = {
			kind = "checker",
			colors = { light, dark },
			materials = { Enum.Material.SmoothPlastic, Enum.Material.SmoothPlastic },
			size = 22,
		},
		accent = zone.color,
		depth = 54,
		ridge = G.grassDeep,
		ridgeHeight = 8,
		ridgeShape = "dunes",
		ridgeCap = G.grass,
		spires = G.rock,
	}
end

-- Tall obelisk with glowing rune slits and a floating crystal on top.
function Default.obelisk(
	ctx: Context,
	parent: Instance,
	foot: Vector3,
	color: Color3,
	facing: Vector3
)
	local frame = CFrame.lookAt(foot, foot + facing * Vector3.new(1, 0, 1))
	Pieces.star(parent, foot + UP * 1.6, 10, 2.2, C.plum, Enum.Material.Slate, true)
	local y = 1.6
	for _, tier in { { 5, 11 }, { 4, 9 }, { 3, 7 } } do
		local width, height = tier[1], tier[2]
		Pieces.solid(
			parent,
			frame * CFrame.new(0, y + height / 2, 0),
			Vector3.new(width, height, width),
			C.skystone,
			Enum.Material.Cobblestone
		)
		Pieces.block(
			parent,
			frame * CFrame.new(0, y + height / 2, -width / 2 - 0.05),
			Vector3.new(0.7, height * 0.7, 0.3),
			color,
			Enum.Material.Neon
		)
		Pieces.solid(
			parent,
			frame * CFrame.new(0, y + height + 0.35, 0),
			Vector3.new(width + 0.8, 0.7, width + 0.8),
			C.plum,
			Enum.Material.Slate
		)
		y += height + 0.7
	end
	Pieces.wedge(
		parent,
		frame * CFrame.new(0, y + 1.5, 0.75),
		Vector3.new(3, 3, 1.5),
		C.gold,
		Enum.Material.Metal
	)
	Pieces.wedge(
		parent,
		frame * CFrame.new(0, y + 1.5, -0.75) * CFrame.Angles(0, math.pi, 0),
		Vector3.new(3, 3, 1.5),
		C.gold,
		Enum.Material.Metal
	)
	local crystalAt = foot + UP * (y + 9)
	local crystal = Pieces.bigShard(parent, crystalAt, 7, 3.4, color, C.cream, 30, 0)
	Pieces.bigShard(parent, crystalAt, 5, 3.4, color, C.cream, 30, 180)
	Pieces.light(crystal, color, 34, 1.6)
	Pieces.stormRing(ctx, crystalAt + UP * 1.5, 5.5, Vector3.new(1, 0.2, 0).Unit, Vector3.zAxis, {
		color = color,
		width = 0.35,
		glow = 1,
	})
	Pieces.stormRing(ctx, crystalAt + UP * 1, 7.5, Vector3.xAxis, Vector3.new(0, 0.5, 1).Unit, {
		color = C.cream,
		width = 0.25,
		glow = 1,
	})
end

-- A tree whose canopy is a crystal cluster.
function Default.crystalTree(
	parent: Instance,
	rng: Random,
	foot: Vector3,
	height: number,
	color: Color3
)
	if Pieces.overBudget(parent) then
		return
	end
	local top = foot + UP * height * 0.55
	Pieces.pipe(parent, foot, top, 1.2, C.wood, Enum.Material.Wood, { CanCollide = true })
	Pieces.ball(parent, top, height * 0.4, C.meadowDark, Enum.Material.Grass)
	Pieces.cluster(parent, rng, top + UP * height * 0.1, height * 0.42, color, 3)
end

function Default.dress(ctx: Context, zone: ZoneContext, spec: ThemeSpec, land: Land)
	local slot = zone.slot
	local folder = zone.folder
	local rng = ctx.rng
	local floor = slot.floor
	local hw, hd = slot.width / 2, slot.depth / 2
	local toHub = slot.frame.LookVector

	-- hero: obelisk on a grassy knoll behind the field
	local tones = Zone.tones(spec)
	local knollSpot, scale = Pieces.heroSpot(ctx, zone, 13, 14)
	if knollSpot then
		local knoll = knollSpot
		Pieces.headland(ctx, knoll, 13 * scale, floor, tones)
		-- a stepped grassy knoll: two one-stud steps up to the obelisk
		local mound = knoll - toHub * 2
		local yaw = CFrame.Angles(0, math.atan2(toHub.X, toHub.Z), 0)
		Ground.poly(
			ctx,
			spec.rim,
			CFrame.new(mound.X, floor + 1, mound.Z) * yaw,
			9,
			1.5,
			8,
			"Knoll"
		)
		Ground.poly(
			ctx,
			spec.rim,
			CFrame.new(mound.X, floor + 2, mound.Z) * yaw * CFrame.Angles(0, math.pi / 8, 0),
			6.5,
			1.5,
			8,
			"Knoll"
		)
		Default.obelisk(
			ctx,
			folder,
			Vector3.new(knoll.X, floor + 2, knoll.Z) - toHub * 2,
			zone.color,
			toHub
		)
	end

	local function at(x: number, z: number): Vector3
		return slot.frame:PointToWorldSpace(Vector3.new(x, 0, z))
	end

	-- a standing-stone rune circle on a headland to the left
	local circle = at(-(land.halfW + 8), -hd * 0.35)
	if Pieces.clearOf(ctx, circle, 17, zone) then
		Pieces.headland(ctx, circle, 13, floor, tones)
		local center = Vector3.new(circle.X, floor, circle.Z)
		for k = 1, 6 do
			local angle = k / 6 * math.pi * 2
			local foot = center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * 7.5
			local height = rng:NextNumber(4.5, 6.5)
			local stone = Pieces.solid(
				folder,
				CFrame.lookAt(foot + UP * (height / 2 - 0.3), center + UP * (height / 2 - 0.3))
					* CFrame.Angles(rng:NextNumber(-0.08, 0.08), 0, rng:NextNumber(-0.08, 0.08)),
				Vector3.new(2.4, height, 1.5),
				C.skystone,
				Enum.Material.Cobblestone
			)
			Pieces.block(
				folder,
				stone.CFrame * CFrame.new(0, 0.4, -0.77),
				Vector3.new(0.6, height * 0.5, 0.1),
				zone.color,
				Enum.Material.Neon
			)
		end
		local heart = Pieces.cluster(folder, rng, center, 5, zone.color, 4)
		Pieces.light(heart, zone.color, 20, 1.2)
		Pieces.sparkles(heart, zone.color, 3, 0.8)
	end

	-- a pond spilling a waterfall off a headland to the right
	local pond = at(land.halfW + 6, -hd * 0.35)
	if Pieces.clearOf(ctx, pond, 15, zone) then
		Pieces.headland(ctx, pond, 12, floor, tones)
		local outward = slot.frame.RightVector
		Ground.water(
			folder,
			Palette.WATER,
			CFrame.lookAt(
				Vector3.new(pond.X, floor + 0.06, pond.Z),
				Vector3.new(pond.X, floor + 0.06, pond.Z) + outward
			) * CFrame.Angles(0, math.pi / 4, 0),
			Vector2.new(8.4, 8.4),
			"Pond"
		)
		local lip = Vector3.new(pond.X, floor - 0.6, pond.Z) + outward * 11
		local channel = Vector3.new(pond.X, floor + 0.06, pond.Z):Lerp(lip + UP * 0.66, 0.5)
		Ground.water(
			folder,
			Palette.WATER,
			CFrame.lookAt(channel, channel + outward),
			Vector2.new(2.6, 11),
			"Spill"
		)
		Pieces.waterfall(ctx, lip, outward, 80, 3)
		for k = 1, 5 do
			local angle = k / 5 * math.pi * 2 + 0.4
			local reed = Vector3.new(pond.X, floor, pond.Z)
				+ Vector3.new(math.cos(angle), 0, math.sin(angle)) * 6.4
			Pieces.block(
				folder,
				CFrame.new(reed + UP * 1.2) * CFrame.Angles(rng:NextNumber(-0.2, 0.2), angle, 0),
				Vector3.new(0.3, 2.4, 0.3),
				C.meadowDark,
				Enum.Material.Grass
			)
		end
		Pieces.rocks(folder, rng, Vector3.new(pond.X, floor, pond.Z) - outward * 6, 2.4)
	end

	-- crystal trees, lanterns, flowers and rocks on the rim
	for i, p in Zone.rimPoints(ctx, zone, land, 7, 3, 4) do
		if i <= 5 then
			Default.crystalTree(folder, rng, p, rng:NextNumber(9, 12), zone.color)
		else
			Pieces.lampPost(folder, p, 8, zone.color, toHub, if i == 6 then 18 else nil)
		end
	end
	for _, p in Zone.rimPoints(ctx, zone, land, 4, 5, 6) do
		Pieces.turf(folder, p, rng:NextNumber(3.5, 5), G.grassDeep, rng:NextNumber(0, 90))
		Pieces.flowers(folder, rng, p, { C.coral, C.cream, C.gold }, 4)
	end
	for _, p in Zone.rimPoints(ctx, zone, land, 6, 2, 2) do
		if rng:NextNumber() < 0.5 then
			Pieces.flowers(folder, rng, p, { C.coral, C.cream, zone.color }, 3)
		else
			Pieces.rocks(folder, rng, p, rng:NextNumber(1.6, 3))
		end
	end
	for i, terrace in land.terraces do
		if not Zone.unblocked(land, terrace.center, 2) then
			continue
		elseif i % 2 == 0 then
			Pieces.cluster(folder, rng, terrace.center, rng:NextNumber(4, 6), zone.color, 3)
		else
			Pieces.bush(folder, rng, terrace.center, 3, C.meadow)
		end
	end
	-- lanterns at the back corners of the rim
	for _, side in { -1, 1 } do
		Pieces.lampPost(folder, at(side * (hw + 5), hd + 5), 9, zone.color, -toHub)
	end
end

return Default
