--!strict
-- The next empty slot: a tall basalt island under construction (crane,
-- scaffolding, floodlight), reached by a catwalk that stops halfway at an
-- amber barricade with a big COMING SOON sign. Bare piles carry on toward
-- the island with a girder hanging off them.

local ServerScriptService = game:GetService("ServerScriptService")

local World = ServerScriptService.Server.World
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
local TERRAIN = Enum.Material
local SEA_FLOOR = -20
local UP = Vector3.new(0, 1, 0)

local Teaser = {}

local function crane(ctx: Context, parent: Instance, base: Vector3, toward: Vector3)
	local facing = Geo.facing(base, toward)
	local yaw = math.deg(math.atan2(-facing.LookVector.X, -facing.LookVector.Z))
	local height = 40
	local _, _, tip = Pieces.pylon(parent, base, height, yaw, 2.6)
	local top = tip - UP * 3.5
	local jibEnd = top + facing.LookVector * 26
	local tailEnd = top - facing.LookVector * 9
	Pieces.strut(parent, top, jibEnd, 1.2, C.hazard)
	Pieces.strut(parent, top + UP * 2.4, jibEnd - UP * 0.2, 0.5, C.iron)
	Pieces.strut(parent, top, tailEnd, 1.2, C.hazard)
	Pieces.block(
		parent,
		CFrame.new(tailEnd - UP * 1.5) * facing.Rotation,
		Vector3.new(3.4, 3, 3),
		C.iron,
		M.concrete
	)
	Pieces.block(
		parent,
		CFrame.new(top - UP * 1.6 + facing.LookVector * 1.5) * facing.Rotation,
		Vector3.new(3, 2.8, 3),
		C.hazard,
		M.metal
	)
	-- hook on a cable
	local hook = jibEnd - UP * 16
	Pieces.wire(ctx, jibEnd, hook + UP * 0.8, 0, 0.2)
	Pieces.block(parent, CFrame.new(hook), Vector3.new(1.6, 1.6, 1.6), C.hazard, M.metal)
	-- a girder hanging from the hook
	Pieces.strut(
		parent,
		hook - UP * 2 - facing.RightVector * 6,
		hook - UP * 2.6 + facing.RightVector * 6,
		1.2,
		T.copperDark
	)
	Pieces.wire(ctx, hook, hook - UP * 2 - facing.RightVector * 5.5, 0, 0.15)
	Pieces.wire(ctx, hook, hook - UP * 2.6 + facing.RightVector * 5.5, 0, 0.15)
	-- banner facing the hub, readable from the plaza
	Pieces.framedSign(
		parent,
		CFrame.lookAt(top - UP * 9 + facing.LookVector * 1.8, top - UP * 9 + facing.LookVector * 10),
		16,
		5,
		"COMING SOON",
		nil,
		Palette.sign(C.hazard, true)
	)
	local beacon = Pieces.ball(parent, tip + UP * 0.2, 1.8, C.hazard, M.neon)
	Pieces.glow(beacon, C.hazard, 24, 2)
end

local function scaffold(
	parent: Instance,
	frame: CFrame,
	width: number,
	depth: number,
	height: number
)
	local nx, nz = 3, 2
	for ix = 0, nx - 1 do
		for iz = 0, nz - 1 do
			local p = (frame * CFrame.new(
				-width / 2 + ix * width / (nx - 1),
				0,
				-depth / 2 + iz * depth / (nz - 1)
			)).Position
			Pieces.strut(parent, p, p + UP * height, 0.4, C.iron)
		end
	end
	for _, y in { height * 0.5, height } do
		for _, z in { -depth / 2, depth / 2 } do
			Pieces.strut(
				parent,
				(frame * CFrame.new(-width / 2, y, z)).Position,
				(frame * CFrame.new(width / 2, y, z)).Position,
				0.35,
				C.hazard
			)
		end
		Pieces.block(
			parent,
			frame * CFrame.new(0, y - 0.2, 0),
			Vector3.new(width, 0.3, depth),
			C.timber,
			M.planks
		)
	end
	-- a half-built pylon stump inside, with welding sparks
	local stump = Pieces.column(parent, frame.Position, height * 0.7, 2.4, C.copper, M.metal, true)
	Pieces.sparks(stump, C.hazard, 10)
	Pieces.insulator(parent, (frame * CFrame.new(0, height * 0.7, 0)).Position, 0.9, 2)
end

function Teaser.build(ctx: Context, zone: ZoneContext)
	local slot = zone.slot
	local F = slot.floor
	local w, d = slot.width, slot.depth
	local parent = zone.folder
	local rng = Geo.rng(ctx, "teaser")

	-- the uncharted island: a basalt crag with slate strata, sea stacks
	-- around it and a ragged grass cap where the crane stands
	local center = slot.frame.Position
	Land.fill(
		ctx,
		Land.rectOutline(slot.frame, w + 6, d + 6, rng, 16, 12, 4),
		SEA_FLOOR,
		-3,
		TERRAIN.Sand
	)
	Land.fill(
		ctx,
		Land.rectOutline(slot.frame, w - 10, d - 10, rng, 13, 9, 3),
		SEA_FLOOR,
		2,
		TERRAIN.Sand
	)
	Land.cliff(
		ctx,
		Land.clip(
			Land.rectOutline(slot.frame, w * 0.6, d * 0.6, rng, 11, 8, 3),
			Geo.landSafe(ctx, F - 16, zone)
		),
		SEA_FLOOR,
		F - 16,
		TERRAIN.Basalt,
		{ TERRAIN.Slate, TERRAIN.Rock },
		TERRAIN.Rock
	)
	Land.cliff(
		ctx,
		Land.clip(
			Land.roundOutline(Vector3.new(center.X, 0, center.Z), math.min(w, d) * 0.3, rng, 8, 3),
			Geo.landSafe(ctx, F, zone)
		),
		SEA_FLOOR,
		F,
		TERRAIN.Basalt,
		{ TERRAIN.Slate, TERRAIN.Rock },
		TERRAIN.LeafyGrass
	)
	for i = 1, 4 do
		local a = math.rad(i * 90 + rng:NextNumber(-30, 30))
		local p = center
			+ slot.frame.RightVector * math.cos(a) * w * 0.36
			+ slot.frame.LookVector * math.sin(a) * d * 0.36
		Land.pinnacle(
			ctx,
			Vector3.new(p.X, SEA_FLOOR, p.Z),
			F - SEA_FLOOR + rng:NextNumber(-14, 6),
			rng:NextNumber(4, 6.5),
			rng,
			{ TERRAIN.Basalt, TERRAIN.Slate, TERRAIN.Basalt },
			3,
			TERRAIN.LeafyGrass
		)
	end

	-- the unfinished catwalk and its barricade
	local from = slot.hubExit.Position
	local to = slot.gate.Position
	local deckEnd = Zone.catwalk(
		ctx,
		ctx.folders.connectors,
		from,
		to,
		zone.color,
		Zone.defaultBridge,
		0.42,
		Geo.detail(zone)
	)
	local dir = Vector3.new(to.X - from.X, 0, to.Z - from.Z).Unit
	local barFrame = CFrame.lookAt(deckEnd - dir * 1.2, deckEnd - dir * 3)
	Pieces.barricade(parent, barFrame, 9.6)
	for _, s in { -1, 1 } do
		Pieces.column(
			parent,
			(barFrame * CFrame.new(s * 6.2, 0, 0.8)).Position,
			12,
			0.7,
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
		Palette.sign(C.hazard, true)
	)
	-- a girder dangling off the first bare pile cap
	local hang = deckEnd + dir * 7 - UP * 1.4
	Pieces.strut(parent, hang, hang + dir * 9 - UP * 6, 1, T.copperDark)

	-- construction on the island top
	center = Vector3.new(center.X, F, center.Z)
	crane(ctx, parent, center + slot.frame.RightVector * 7, Vector3.new(0, F, 0))
	scaffold(
		parent,
		Geo.facing(
			center - slot.frame.RightVector * 9 + slot.frame.LookVector * 4,
			Vector3.new(0, F, 0)
		),
		8,
		6,
		12
	)
	local light = Pieces.lamp(parent, center + slot.frame.LookVector * 12, 9, C.hazard, 26)
	local _ = light
	for _ = 1, 8 do
		local p = center
			+ slot.frame.RightVector * rng:NextNumber(-14, 14)
			+ slot.frame.LookVector * rng:NextNumber(-12, 12)
		local roll = rng:NextNumber()
		if roll < 0.4 then
			Pieces.crate(parent, p, rng:NextNumber(1.6, 2.4), rng:NextNumber(0, 90), C.hazard)
		elseif roll < 0.7 then
			Pieces.barrel(parent, p, C.copper)
		else
			Pieces.rocks(parent, p, rng:NextNumber(1.5, 3), rng, T.rockDark)
		end
	end
end

return Teaser
