--!strict
-- The Research Center: the island in the next free slot is the Storm
-- Society's research station, reached by a full boardwalk from the hub.
-- A big observatory dome with the hiring doorstep (the ResearchOffice box)
-- at its door, a RESEARCH CENTER arch over the path, a weather balloon, a
-- field tent, crates and an instrument scaffold. The island is a
-- grass-topped rock 11-gon on grey cliff bands with a sand skirt, two lower
-- rock horns round a bay at the back and sea stacks. Adding a zone moves
-- the whole station one slot out, like the old Coming Soon island.

local ServerScriptService = game:GetService("ServerScriptService")

local Blocks = require(ServerScriptService.Server.World.Blocks)
local Kit = require(ServerScriptService.Server.World.Kit)
local Geo = require(script.Parent.Geo)
local Land = require(script.Parent.Land)
local Palette = require(script.Parent.Palette)
local Pieces = require(script.Parent.Pieces)
local WLTypes = require(script.Parent.WLTypes)
local Zone = require(script.Parent.Zone)

type Context = WLTypes.Context
type ZoneContext = WLTypes.ZoneContext

local C = Palette.colors
local G = Palette.ground

local Teaser = {}

local BEACH_TOP = 1

local function island(ctx: Context, zone: ZoneContext)
	local key = Geo.key(zone)
	local folder = Land.folder(ctx, key)
	local floor = zone.slot.floor
	local hw, hd = zone.slot.width / 2, zone.slot.depth / 2
	-- the main rock, covering the survey site and the camp
	Land.island(ctx, key, Geo.cf(zone, 0, -hd * 0.14, 0, 8), {
		cap = G.meadow,
		strata = { G.rock, G.slate },
		apothem = math.min(hw, hd) * 0.92,
		sides = 11,
		layer = 15,
		inset = 2,
		beach = G.beach,
		beachTop = BEACH_TOP,
		beachWidth = 6,
	})
	-- two lower horns round a bay at the back: a rocky crescent
	-- x, z, top below the floor, yaw, width, depth, stack above the floor
	local horns = {
		{ -hw * 0.62, hd * 0.72, -7, 24, 20, 16, 9 },
		{ hw * 0.66, hd * 0.6, -13, -18, 15, 13, 4 },
	}
	for _, h in horns do
		local x, z, drop, yaw, rise = h[1], h[2], h[3], h[4], h[7]
		local size = Vector2.new(h[5], h[6])
		local top = math.max(floor + drop, BEACH_TOP + 3)
		Land.mesa(
			ctx,
			key,
			{ G.slate, G.rock },
			Geo.cf(zone, x, z, top - floor, yaw),
			size,
			10,
			2,
			BEACH_TOP
		)
		-- a rock stack on each horn
		local p = Geo.at(zone, x, z, top - floor)
		Land.stack(ctx, folder, { G.slate, G.rock }, p, 7, floor + rise, 5, G.meadow)
	end
	-- and one standing in the sea off the front corner
	local sea = Geo.at(zone, hw + 6, -hd * 0.35, 0)
	Land.stack(
		ctx,
		folder,
		{ G.rock, G.slate },
		Vector3.new(sea.X, Land.SEABED, sea.Z),
		8,
		floor - 6,
		9,
		G.meadow
	)
end

local function walk(ctx: Context, zone: ZoneContext)
	local slot = zone.slot
	local parent = Instance.new("Folder")
	parent.Name = "ResearchCenter"
	parent.Parent = ctx.folders.connectors
	Zone.trail(ctx, parent, slot.angle, zone.color, Geo.key(zone))
	Zone.boardwalk(ctx, parent, slot.hubExit.Position, slot.gate.Position, {
		color = zone.color,
		title = "RESEARCH CENTER",
		subtitle = "Hire researchers here",
		landing = 16,
	})
end

-- The observatory dome (local 0, DOME_Z) with the hiring doorstep at its
-- door, facing the boardwalk: a marked pad under the invisible
-- ResearchOffice box that Util/ResearchSites finds.
local DOME_Z = 6
local DOME_DIAMETER = 16

local function center(ctx: Context, zone: ZoneContext)
	local folder = zone.folder
	local floor = zone.slot.floor
	local cf = Geo.cf(zone, 0, DOME_Z, 0) -- looks toward the hub and the gate
	Pieces.dome(folder, cf, DOME_DIAMETER, true)
	local r = DOME_DIAMETER / 2
	local doorstep = (cf * CFrame.new(0, 0, -r - 3.9)).Position
	local pad = Blocks.box(
		ctx.folders.ground,
		Palette.stone,
		CFrame.new(doorstep.X, floor + 0.1, doorstep.Z) * cf.Rotation,
		Vector3.new(8, 0.6, 6),
		{ Name = "ResearchPad" }
	)
	Blocks.box(
		ctx.folders.ground,
		C.seafoam,
		CFrame.new(doorstep.X, floor + 0.36, doorstep.Z) * cf.Rotation,
		Vector3.new(6, 0.12, 4),
		{ Name = "ResearchMark" }
	)
	Kit.researchOffice(folder, pad, 12)
	Kit.sign(folder, cf * CFrame.new(0, 6.4, -r - 1.5), 8, 1.6, "RESEARCH", nil, Palette.SIGN)
end

local function camp(ctx: Context, zone: ZoneContext)
	local rng = ctx.rng
	local folder = zone.folder
	local floor = zone.slot.floor
	local hd = zone.slot.depth / 2
	-- weather balloon tethered beside the dome
	local anchors = {}
	for k = 0, 2 do
		local a = math.rad(k * 120 + 10)
		local p = Geo.at(zone, 24 + math.cos(a) * 5, 12 + math.sin(a) * 5, 0)
		Pieces.cyl(folder, p, 1.6, 0.8, C.piling, Enum.Material.Wood)
		table.insert(anchors, p + Vector3.new(0, 1.5, 0))
	end
	Pieces.balloon(
		ctx,
		folder,
		Geo.at(zone, 24, 12, 36) + Pieces.WIND * 4,
		12,
		C.sailcloth,
		C.seafoam,
		anchors,
		false
	)
	-- field tent, crates and an instrument scaffold with a work light
	local tent = Geo.cf(zone, -14, -2, 0, 30)
	for _, s in { 1, -1 } do
		Pieces.wedge(
			folder,
			tent * CFrame.new(s * 1.6, 1.6, 0) * CFrame.Angles(0, math.rad(90 * s), 0),
			Vector3.new(5, 3.2, 3.2),
			C.seafoam,
			Enum.Material.Fabric
		)
	end
	-- off to the side, clear of the path from the arch to the doorstep
	for i = 1, 3 do
		Pieces.crate(folder, Geo.cf(zone, 10 + i * 2.2, -14 + (i % 2) * 2, 0, i * 25), 1.8)
	end
	Pieces.barrel(folder, Geo.at(zone, 9, -16), C.slicker)
	local sx, sz = 14, -6
	local h = 12
	for _, c in { { -2, -2 }, { 2, -2 }, { 2, 2 }, { -2, 2 } } do
		Pieces.cyl(
			folder,
			Geo.at(zone, sx + c[1], sz + c[2]),
			h,
			0.5,
			C.harbor,
			Enum.Material.Metal
		)
	end
	for _, y in { 5, 11 } do
		Pieces.box(
			folder,
			Geo.cf(zone, sx, sz, y),
			Vector3.new(4.8, 0.4, 4.8),
			C.driftwood,
			Enum.Material.WoodPlanks
		)
	end
	Pieces.beam(
		folder,
		Geo.at(zone, sx - 2, sz - 2, 0.5),
		Geo.at(zone, sx + 2, sz - 2, 10.5),
		0.25,
		C.harbor,
		Enum.Material.Metal
	)
	Pieces.beam(
		folder,
		Geo.at(zone, sx + 2, sz + 2, 0.5),
		Geo.at(zone, sx - 2, sz + 2, 10.5),
		0.25,
		C.harbor,
		Enum.Material.Metal
	)
	Pieces.lantern(folder, Geo.at(zone, sx, sz - 2.4, h - 0.5), C.slicker, 30, true)
	Pieces.windsock(folder, Geo.at(zone, sx + 2, sz + 2, h), C.slicker, 3.5)
	-- arch over the path from the boardwalk to the dome
	Pieces.signBoard(
		folder,
		Geo.cf(zone, 0, -hd + 12, 8.5),
		16,
		4.6,
		"RESEARCH CENTER",
		"Storm Society: hire researchers at the dome",
		Palette.SIGN,
		floor
	)
	for _ = 1, 5 do
		local x, z = rng:NextNumber(-20, 20), rng:NextNumber(-10, 20)
		-- not on the dome, its doorstep or the path to it
		if math.abs(x) > 6 and math.sqrt(x * x + (z - DOME_Z) ^ 2) > DOME_DIAMETER / 2 + 3 then
			Pieces.rocks(folder, Geo.at(zone, x, z), rng:NextNumber(2, 3), rng)
		end
	end
end

function Teaser.build(ctx: Context, zone: ZoneContext)
	island(ctx, zone)
	center(ctx, zone)
	walk(ctx, zone)
	camp(ctx, zone)
end

return Teaser
