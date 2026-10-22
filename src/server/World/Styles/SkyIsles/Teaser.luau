--!strict
-- The "coming soon" slot: an uncharted, storm-veiled island with a dormant
-- crystal and scaffolding, reached by a half-built rune bridge that stops
-- at a glowing rune barrier with a COMING SOON board. Loose bridge stones
-- drift in the gap.

local ServerScriptService = game:GetService("ServerScriptService")

local World = ServerScriptService.Server.World
local Kit = require(World.Kit)
local WorldTypes = require(World.Types)
local Ground = require(script.Parent.Ground)
local Palette = require(script.Parent.Palette)
local Pieces = require(script.Parent.Pieces)

type Context = WorldTypes.Context
type ZoneContext = WorldTypes.ZoneContext

local C = Palette.C
local G = Palette.GROUND
local UP = Vector3.yAxis

local GLOW = Color3.fromRGB(176, 160, 226)
local SPIRE = Color3.fromRGB(150, 96, 230)
local SPIRE_CORE = Color3.fromRGB(196, 140, 255)
local BUILT = 0.42 -- share of the bridge that is built from the hub side

local Teaser = {}

function Teaser.build(ctx: Context, zone: ZoneContext)
	local slot = zone.slot
	local frame = slot.frame
	local folder = zone.folder
	local rng = ctx.rng
	local floor = slot.floor
	local hw, hd = slot.width / 2, slot.depth / 2
	local accept = function(p: Vector3, r: number): boolean
		return Pieces.clearOf(ctx, p, r, zone, 4)
	end

	-- rough island: no field yet, just raw storm rock, a lower terrace
	-- skirting one side, a tapering underside and hanging points
	local tones = {
		cap = G.stormRock,
		soil = G.basalt,
		rocks = { G.slate, G.basalt },
		tip = C.plumDeep,
	}
	local apothem = hd * 0.86
	Ground.isle(ctx, tones, frame * CFrame.new(0, 0, -hd + apothem), apothem, 44, {
		sides = 16,
		soil = 6,
		tiers = 3,
		points = 2,
	})
	local terrace = frame:PointToWorldSpace(Vector3.new(hw * 0.38, 0, hd * 0.38))
	if accept(terrace, hw * 0.55) then
		local terraceTop = CFrame.new(terrace.X, floor - 8, terrace.Z) * frame.Rotation
		Ground.poly(ctx, G.slate, terraceTop, hw * 0.55 + Ground.OVERHANG, Ground.CAP, 12, "Cap")
		Ground.poly(
			ctx,
			G.basalt,
			terraceTop * CFrame.new(0, -Ground.CAP, 0),
			hw * 0.55,
			6,
			12,
			"Soil"
		)
	end
	for k = 1, 5 do
		local angle = k / 5 * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local l = Vector3.new(math.cos(angle), 0, math.sin(angle)) * rng:NextNumber(18, 26)
		if l.Z > -20 then
			local crystal = Pieces.cluster(
				folder,
				rng,
				frame:PointToWorldSpace(l * 0.8) + UP * floor,
				rng:NextNumber(6, 9),
				GLOW,
				3
			)
			if k == 1 then
				Pieces.light(crystal, GLOW, 22, 1)
			end
		end
	end

	-- dormant crystal in a scaffold at the centre
	local center = Vector3.new(frame.Position.X, floor, frame.Position.Z)
	local crystal = Pieces.bigShard(folder, center, 28, 9, SPIRE, SPIRE_CORE, 20, 0)
	crystal.Transparency = 0.2
	Pieces.light(crystal, SPIRE_CORE, 30, 1.4)
	local corners: { Vector3 } = {}
	for _, corner in
		{
			Vector3.new(-1, 0, -1),
			Vector3.new(1, 0, -1),
			Vector3.new(1, 0, 1),
			Vector3.new(-1, 0, 1),
		}
	do
		local foot = center + frame:VectorToWorldSpace(corner * 7)
		Pieces.solid(
			folder,
			CFrame.new(foot + UP * 11),
			Vector3.new(0.8, 22, 0.8),
			C.woodLight,
			Enum.Material.Wood
		)
		table.insert(corners, foot)
	end
	for _, h in { 6, 13, 20 } do
		for k = 1, 4 do
			Pieces.plank(
				folder,
				corners[k] + UP * h,
				corners[k % 4 + 1] + UP * h,
				0.6,
				0.6,
				C.wood,
				Enum.Material.Wood
			)
		end
	end
	-- crates and a survey flag
	for k = 1, 3 do
		local p = center + frame:VectorToWorldSpace(Vector3.new(9 + k * 1.5, 0, -4 + k * 2.8))
		Pieces.solid(
			folder,
			CFrame.new(p + UP * 1.1) * CFrame.Angles(0, rng:NextNumber(0, 1), 0),
			Vector3.new(2.2, 2.2, 2.2),
			C.woodLight,
			Enum.Material.WoodPlanks
		)
	end
	local flag = center + frame:VectorToWorldSpace(Vector3.new(-10, 0, -8))
	Pieces.cylinder(folder, flag, 9, 0.4, C.plumDeep, Enum.Material.Metal)
	Pieces.block(
		folder,
		CFrame.new(flag + UP * 7.6 + frame.RightVector * 1.6) * frame.Rotation,
		Vector3.new(3, 2, 0.15),
		GLOW,
		Enum.Material.Fabric
	)

	-- storm veil: dark mist rolling over the island
	local veil = Pieces.block(
		folder,
		CFrame.new(center + UP * 6),
		Vector3.new(hw * 1.4, 2, hd * 1.4),
		C.plum,
		Enum.Material.SmoothPlastic,
		{ Transparency = 1, Name = "Veil" }
	)
	Pieces.emitter(veil, {
		Name = "StormVeil",
		Texture = Kit.TEXTURES.smoke,
		Color = ColorSequence.new(C.twilight, C.plumDeep),
		LightInfluence = 1,
		Rate = 5,
		Lifetime = NumberRange.new(10, 14),
		Speed = NumberRange.new(0.5, 1.5),
		SpreadAngle = Vector2.new(30, 30),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 10),
			NumberSequenceKeypoint.new(1, 26),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		}),
	})

	-- half-built bridge from the hub, ending at a rune barrier (decks lie
	-- a touch above the ground at both ends, like every bridge)
	local from = slot.hubExit.Position + UP * 0.2
	local to = slot.gate.Position + UP * 0.2
	Pieces.bridge(ctx, ctx.folders.connectors, from, to, {
		glow = GLOW,
		width = 12,
		startFlat = 4,
		endFlat = 12,
		stopAt = BUILT,
		lights = false,
	})
	local run = ((to - from) * Vector3.new(1, 0, 1)).Magnitude
	local dir = ((to - from) * Vector3.new(1, 0, 1)).Unit
	local right = dir:Cross(UP)
	local riseStart = 4
	local riseEnd = run - 12
	local stopS = run * BUILT
	local stopY = from.Y
		+ (to.Y - from.Y) * math.clamp((stopS - riseStart) / (riseEnd - riseStart), 0, 1)
	local stopPoint = Vector3.new(from.X, 0, from.Z) + dir * stopS + UP * stopY
	local barrierAt = stopPoint - dir * 1.5
	local barrierFrame = CFrame.lookAt(barrierAt, barrierAt - dir)
	Pieces.solid(
		ctx.folders.connectors,
		barrierFrame * CFrame.new(0, 5, 0),
		Vector3.new(9.4, 10, 0.6),
		GLOW,
		Enum.Material.ForceField,
		{ Name = "RuneBarrier", Transparency = 0.2 }
	)
	for side = -1, 1, 2 do
		local foot = barrierAt + right * side * 5.2
		Pieces.solid(
			ctx.folders.connectors,
			CFrame.new(foot + UP * 6),
			Vector3.new(1.6, 12, 1.6),
			C.plum,
			Enum.Material.Slate
		)
		-- a crystal on each top corner of the board, which rests on the posts
		Pieces.diamond(ctx.folders.connectors, foot + UP * 17.9, 1.4, GLOW)
	end
	Pieces.board(
		folder,
		barrierFrame * CFrame.new(0, 12 + 2.2, 0),
		13,
		4.4,
		"COMING SOON",
		"A new isle is being charted",
		Palette.signFor(GLOW)
	)

	-- loose stones drifting in the gap
	for k = 1, 5 do
		local s = stopS + (run - stopS) * (k / 6)
		local y = from.Y
			+ (to.Y - from.Y) * math.clamp((s - riseStart) / (riseEnd - riseStart), 0, 1)
		local p = Vector3.new(from.X, 0, from.Z)
			+ dir * s
			+ right * rng:NextNumber(-4, 4)
			+ UP * (y - rng:NextNumber(2, 10))
		Pieces.block(
			ctx.folders.connectors,
			CFrame.new(p)
				* CFrame.Angles(
					rng:NextNumber(-0.5, 0.5),
					rng:NextNumber(0, 3),
					rng:NextNumber(-0.5, 0.5)
				),
			Vector3.new(rng:NextNumber(4, 7), 1.4, rng:NextNumber(3, 5)),
			C.skystone,
			Enum.Material.Cobblestone
		)
	end

	-- a short stub reaching out from the island side
	Pieces.bridge(ctx, folder, to, from, {
		glow = GLOW,
		width = 12,
		startFlat = 6,
		endFlat = 4,
		stopAt = 0.14,
		lights = false,
	})
end

return Teaser
