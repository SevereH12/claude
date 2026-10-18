--!strict
-- The next empty slot: a tall basalt island under construction (crane,
-- scaffolding, work lamp), reached by a catwalk that stops partway at a
-- barricade with a big COMING SOON sign. Bare piles carry on toward the
-- island with a girder hanging off them. Amber here is construction only:
-- the barricade stripes, the trail chevrons and the crane cab.

local ServerScriptService = game:GetService("ServerScriptService")

local World = ServerScriptService.Server.World
local Kit = require(World.Kit)
local WorldTypes = require(World.Types)
local Geo = require(script.Parent.Geo)
local Land = require(script.Parent.Land)
local Palette = require(script.Parent.Palette)
local Pieces = require(script.Parent.Pieces)
local Zone = require(script.Parent.Zone)

type Context = WorldTypes.Context
type ZoneContext = WorldTypes.ZoneContext

local C = Palette.colors
local T = Palette.tints
local M = Palette.materials
local L = Palette.light
local TERRAIN = Enum.Material
local SEA_FLOOR = Geo.SEA_FLOOR
local UP = Vector3.new(0, 1, 0)

local Teaser = {}

-- A chunky construction crane: lattice mast, solid amber cab, jib and
-- counter-jib, a big counterweight, a hook carrying a girder, and a COMING
-- SOON banner facing the hub.
local function crane(ctx: Context, parent: Instance, base: Vector3, toward: Vector3)
	local facing = Geo.facing(base, toward)
	local yaw = math.deg(math.atan2(-facing.LookVector.X, -facing.LookVector.Z))
	local height = 42
	local _, _, tip = Pieces.pylon(parent, base, height, yaw, 3, 1.1)
	local top = tip - UP * 4
	local jibEnd = top + facing.LookVector * 28
	local tailEnd = top - facing.LookVector * 10
	Pieces.strut(parent, top, jibEnd, 1.6, C.copper)
	Pieces.strut(parent, top + UP * 4.5, jibEnd - UP * 0.2, 0.6, C.iron)
	Pieces.strut(parent, top, tailEnd, 1.6, C.copper)
	Pieces.block(
		parent,
		CFrame.new(tailEnd - UP * 2) * facing.Rotation,
		Vector3.new(5, 4, 4),
		C.iron,
		M.concrete
	)
	Pieces.block(
		parent,
		CFrame.new(top - UP * 2 + facing.LookVector * 2.2) * facing.Rotation,
		Vector3.new(3.6, 3.4, 3.6),
		C.hazard,
		M.metal
	)
	-- hook on a cable, carrying a girder
	local hook = jibEnd - UP * 16
	Pieces.wire(ctx, jibEnd, hook + UP * 0.8, 0, 0.25)
	Pieces.block(parent, CFrame.new(hook), Vector3.new(1.8, 1.8, 1.8), C.iron, M.metal)
	Pieces.strut(
		parent,
		hook - UP * 2 - facing.RightVector * 6,
		hook - UP * 2.6 + facing.RightVector * 6,
		1.4,
		T.copperDark
	)
	Pieces.wire(ctx, hook, hook - UP * 2 - facing.RightVector * 5.5, 0, 0.18)
	Pieces.wire(ctx, hook, hook - UP * 2.6 + facing.RightVector * 5.5, 0, 0.18)
	-- banner facing the hub, readable from the plaza
	local bannerAt = top - UP * 10 + facing.LookVector * 2.4
	Pieces.framedSign(
		parent,
		CFrame.lookAt(bannerAt, bannerAt + facing.LookVector),
		17,
		5.5,
		"COMING SOON",
		nil,
		Palette.sign(C.ceramic, true)
	)
	local beacon = Pieces.ball(parent, tip + UP * 0.6, 2, C.volt, M.neon)
	Pieces.glow(beacon, C.volt, 24, 2)
end

local function scaffold(
	parent: Instance,
	frame: CFrame,
	width: number,
	depth: number,
	height: number
)
	for _, c in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
		local p = (frame * CFrame.new(c[1] * width / 2, 0, c[2] * depth / 2)).Position
		Pieces.strut(parent, p, p + UP * height, 0.5, C.iron)
	end
	for _, z in { -depth / 2, depth / 2 } do
		Pieces.strut(
			parent,
			(frame * CFrame.new(-width / 2, height, z)).Position,
			(frame * CFrame.new(width / 2, height, z)).Position,
			0.45,
			C.copper
		)
	end
	Pieces.block(
		parent,
		frame * CFrame.new(0, height * 0.55, 0),
		Vector3.new(width, 0.35, depth),
		C.timber,
		M.planks
	)
	-- a half-built pylon stump inside, with welding sparks
	local stump = Pieces.column(parent, frame.Position, height * 0.7, 2.6, C.copper, M.metal, true)
	Pieces.sparks(stump, L.warm, 10)
	Pieces.column(
		parent,
		(frame * CFrame.new(0, height * 0.7, 0)).Position,
		1.4,
		3,
		C.ceramic,
		M.ceramic
	)
end

function Teaser.build(ctx: Context, zone: ZoneContext)
	local slot = zone.slot
	local F = slot.floor
	local w, d = slot.width, slot.depth
	local parent = zone.folder
	local rng = Geo.rng(ctx, "teaser")
	local guard = Geo.guard(ctx, zone, true)

	-- the uncharted island: a basalt crag with slate strata, sea stacks
	-- around it and a ragged grass cap where the crane stands
	local center = slot.frame.Position
	Land.fill(
		ctx,
		Land.organic(slot.frame, w + 6, d + 6, rng, { edge = 16, jitter = 12, bays = 2 }),
		SEA_FLOOR,
		-3,
		TERRAIN.Sand,
		0,
		guard
	)
	Land.fill(
		ctx,
		Land.organic(
			slot.frame,
			w - 10,
			d - 10,
			rng,
			{ edge = 13, jitter = 9, bays = 2, spits = 1 }
		),
		SEA_FLOOR,
		2,
		TERRAIN.Sand,
		0,
		guard
	)
	local lower = Land.cliff(
		ctx,
		Land.organic(slot.frame, w * 0.6, d * 0.6, rng, { edge = 11, jitter = 8, bays = 1 }),
		SEA_FLOOR,
		F - 16,
		TERRAIN.Basalt,
		{ TERRAIN.Slate, TERRAIN.Rock },
		TERRAIN.Rock,
		rng,
		{ guard = guard, lean = 8, foot = 0 }
	)
	Land.talus(ctx, lower, 2, rng, 8, TERRAIN.Basalt, guard)
	Land.cliff(
		ctx,
		Land.blob(Vector3.new(center.X, 0, center.Z), math.min(w, d) * 0.3, rng, 8, 3),
		SEA_FLOOR,
		F,
		TERRAIN.Basalt,
		{ TERRAIN.Slate, TERRAIN.Rock },
		TERRAIN.LeafyGrass,
		rng,
		{ guard = guard, lean = 6, foot = F - 24 }
	)
	Zone.saddle(ctx, zone, TERRAIN.Basalt, { TERRAIN.Slate, TERRAIN.Rock }, TERRAIN.LeafyGrass)
	for i = 1, 4 do
		local a = math.rad(i * 90 + rng:NextNumber(-30, 30))
		local p = center
			+ slot.frame.RightVector * math.cos(a) * w * 0.38
			+ slot.frame.LookVector * math.sin(a) * d * 0.38
		Land.pinnacle(
			ctx,
			Vector3.new(p.X, SEA_FLOOR, p.Z),
			F - SEA_FLOOR + rng:NextNumber(-14, 6),
			rng:NextNumber(4, 6.5),
			rng,
			{ TERRAIN.Basalt, TERRAIN.Slate, TERRAIN.Basalt },
			3,
			TERRAIN.LeafyGrass,
			guard
		)
	end

	-- the unfinished catwalk (soot trail: not open yet) and its barricade
	local from = slot.hubExit.Position
	local to = slot.gate.Position
	local deckEnd = Zone.catwalk(
		ctx,
		ctx.folders.connectors,
		from,
		to,
		zone.color,
		Zone.defaultBridge,
		{ stopAt = 0.42, trail = C.soot }
	)
	local dir = Vector3.new(to.X - from.X, 0, to.Z - from.Z).Unit
	local barFrame = CFrame.lookAt(deckEnd - dir * 1.2, deckEnd - dir * 3)
	Pieces.barricade(parent, barFrame, 9.6)
	-- nobody hops the barricade onto the unfinished deck
	Kit.part({
		Name = "Blocker",
		Size = Vector3.new(10.4, 14, 1),
		CFrame = barFrame * CFrame.new(0, 7, 0.4),
		Transparency = 1,
		CanCollide = true,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Parent = parent,
	})
	for _, s in { -1, 1 } do
		Pieces.column(
			parent,
			(barFrame * CFrame.new(s * 6.2, 0, 0.8)).Position,
			12,
			0.8,
			C.iron,
			M.metal,
			true
		)
	end
	Pieces.framedSign(
		parent,
		barFrame * CFrame.new(0, 9.5, 0.8),
		13,
		4.4,
		"COMING SOON",
		"a new storm zone is on the way",
		Palette.sign(C.ceramic, true)
	)
	-- a girder dangling off the first bare pile cap
	local hang = deckEnd + dir * 7 - UP * 1.4
	Pieces.strut(parent, hang, hang + dir * 9 - UP * 6, 1.2, T.copperDark)

	-- construction on the island top
	local top = Vector3.new(center.X, F, center.Z)
	crane(ctx, parent, top + slot.frame.RightVector * 7, Vector3.new(0, F, 0))
	scaffold(
		parent,
		Geo.facing(
			top - slot.frame.RightVector * 9 + slot.frame.LookVector * 4,
			Vector3.new(0, F, 0)
		),
		8,
		6,
		12
	)
	Pieces.lamp(parent, top + slot.frame.LookVector * 12, 9, L.warm, 26, true)
	for k = 0, 3 do
		local p = top
			+ slot.frame.RightVector * (-4 + k * 3.2)
			+ slot.frame.LookVector * (8 + (k % 2) * 2.4)
		if k % 2 == 0 then
			Pieces.crate(parent, p, rng:NextNumber(1.8, 2.4), rng:NextNumber(0, 90), nil, true)
		else
			Pieces.barrel(parent, p, C.copper)
		end
	end
end

return Teaser
