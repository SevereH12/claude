--!strict
-- The next empty slot: a misty rock island under survey (tent, crates,
-- scaffold and a grey "?" balloon) and a boardwalk that stops half way at
-- a striped barrier with a COMING SOON board, bare stilts beyond it.

local ServerScriptService = game:GetService("ServerScriptService")

local Kit = require(ServerScriptService.Server.World.Kit)
local Geo = require(script.Parent.Geo)
local Palette = require(script.Parent.Palette)
local Pieces = require(script.Parent.Pieces)
local WLTypes = require(script.Parent.WLTypes)
local Zone = require(script.Parent.Zone)

type Context = WLTypes.Context
type ZoneContext = WLTypes.ZoneContext

local C = Palette.colors

local Teaser = {}

local STOP_AT = 0.55
local MARGINS = { front = -6, side = -10, back = -6 }

local function island(ctx: Context, zone: ZoneContext)
	local floor = zone.slot.floor
	local m = MARGINS
	Geo.terrace(ctx, zone, m, 26, -4, -18, Enum.Material.Sand, 10, 1, 0.9)
	Geo.terrace(ctx, zone, m, 20, 1.5, -16, Enum.Material.Sand, 8, 1, 1)
	Geo.cliffs(ctx, zone, m, 1.5, floor - 3, { Enum.Material.Rock, Enum.Material.Slate }, 16, 4, 8)
	Geo.terrace(ctx, zone, m, 2, floor - 2, -16, Enum.Material.Rock, 11, 2)
	Geo.terrace(ctx, zone, m, 0, floor, -16, Enum.Material.LeafyGrass, 11, 1.5)
	local hw, hd = zone.slot.width / 2, zone.slot.depth / 2
	Geo.lobe(ctx, zone, hw + 4, -hd * 0.3, 9, 16, floor - 10, Enum.Material.Slate, 2)
	Geo.lobe(ctx, zone, -hw - 2, hd * 0.4, 10, 18, 1, Enum.Material.Sand, 0.5)
	for _, s in { { -hw + 4, hd - 2, 14 }, { hw - 2, hd * 0.2, 9 } } do
		local p = Geo.at(zone, s[1], s[2], 0)
		Geo.stack(
			ctx,
			Vector3.new(p.X, floor - 4, p.Z),
			5,
			floor + s[3],
			{ Enum.Material.Slate, Enum.Material.Rock },
			Enum.Material.LeafyGrass
		)
	end
end

-- Striped sawhorse barrier across the deck.
local function barrier(parent: Instance, cframe: CFrame, width: number)
	for _, x in { -width / 2 + 0.6, width / 2 - 0.6 } do
		for _, z in { -0.6, 0.6 } do
			Pieces.beam(
				parent,
				(cframe * CFrame.new(x, 0, z * 1.4)).Position,
				(cframe * CFrame.new(x, 2.6, 0)).Position,
				0.3,
				C.ink,
				Enum.Material.Metal
			)
		end
	end
	local stripes = 5
	for i = 0, stripes - 1 do
		local seg = width / stripes
		Pieces.box(
			parent,
			cframe * CFrame.new(-width / 2 + seg * (i + 0.5), 2.7, 0),
			Vector3.new(seg, 0.9, 0.3),
			if i % 2 == 0 then C.slicker else C.ink,
			Enum.Material.SmoothPlastic
		)
	end
	for _, x in { -width / 2 + 0.6, width / 2 - 0.6 } do
		local lamp = Pieces.glow(
			Pieces.ball(parent, (cframe * CFrame.new(x, 3.5, 0)).Position, 0.7, C.beacon),
			C.beacon
		)
		lamp.Name = "BarrierLamp"
	end
end

local function cone(parent: Instance, bottom: Vector3)
	Pieces.box(
		parent,
		CFrame.new(bottom + Vector3.new(0, 0.1, 0)),
		Vector3.new(1.6, 0.2, 1.6),
		C.beacon,
		Enum.Material.SmoothPlastic,
		false
	)
	Pieces.cyl(parent, bottom, 1.2, 1.1, C.beacon, Enum.Material.SmoothPlastic, false)
	Pieces.cyl(
		parent,
		bottom + Vector3.new(0, 1.2, 0),
		0.5,
		0.8,
		C.sailcloth,
		Enum.Material.SmoothPlastic,
		false
	)
	Pieces.cyl(
		parent,
		bottom + Vector3.new(0, 1.7, 0),
		0.5,
		0.55,
		C.beacon,
		Enum.Material.SmoothPlastic,
		false
	)
end

local function walk(ctx: Context, zone: ZoneContext)
	local slot = zone.slot
	local parent = Instance.new("Folder")
	parent.Name = "ComingSoon"
	parent.Parent = ctx.folders.connectors
	Zone.trail(ctx, parent, slot.angle, zone.color)
	local p, list = Zone.boardwalk(ctx, parent, slot.hubExit.Position, slot.gate.Position, {
		color = zone.color,
		title = "COMING SOON",
		subtitle = "New station under survey",
		landing = 16,
		stopAt = STOP_AT,
	})
	local endS = list[#list]
	local endPoint = p.at(endS)
	local dir = p.tangent(endS)
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local face = CFrame.lookAt(endPoint, endPoint + dir)
	-- barrier, cones, sign and caution rope at the end of the deck
	barrier(parent, face * CFrame.new(0, 0, 1.2), Zone.DECK_WIDTH - 1)
	cone(parent, (face * CFrame.new(-3, 0, 3.4)).Position)
	cone(parent, (face * CFrame.new(3.2, 0, 2.8)).Position)
	local signCf = face * CFrame.new(0, 7.2, 0.2) * CFrame.Angles(0, math.pi, 0)
	Pieces.signBoard(
		parent,
		signCf,
		9,
		3.4,
		"COMING SOON",
		"A new station is on the way",
		Palette.HAZARD_SIGN,
		endPoint.Y
	)
	for _, side in { -1, 1 } do
		Kit.cable(
			ctx,
			(face * CFrame.new(side * (Zone.DECK_WIDTH / 2 - 0.3), 2.7, 0.2)).Position,
			(face * CFrame.new(-side * 1.5, 1.6, 0.2)).Position,
			{
				Color = C.slicker,
				Width = 0.25,
				CurveSize = 0.6,
			}
		)
	end
	-- loose planks left on the deck
	for i = 1, 2 do
		local a = (face * CFrame.new(-1 + i * 1.4, 0.15, 4 + i)).Position
		Pieces.plank(parent, a, a + right * 3.6 + dir * (i - 1.5), 1, 0.3, Palette.plankLight)
	end
	-- bare stilts beyond, getting lower as the build crew hasn't got there yet
	local s = endS + 6
	local stop = p.length * 0.85
	local k = 0
	while s < stop do
		k += 1
		local q = p.at(s)
		local d = p.tangent(s)
		local r = Vector3.new(-d.Z, 0, d.X)
		local top = q.Y - 1 - k * 1.8 - ctx.rng:NextNumber(0, 1.5)
		if top > 1.5 then
			for _, side in { -1, 1 } do
				local foot = q + r * side * (Zone.DECK_WIDTH / 2 - 0.8)
				Pieces.cyl(
					parent,
					Vector3.new(foot.X, -8, foot.Z),
					top + 8 - (if side > 0 then 1 else 0),
					1.1,
					C.piling,
					Enum.Material.Wood,
					false
				)
			end
		end
		s += 7
	end
end

local function camp(ctx: Context, zone: ZoneContext)
	local rng = ctx.rng
	local folder = zone.folder
	local floor = zone.slot.floor
	local hd = zone.slot.depth / 2
	-- grey "?" balloon over the island
	local anchors = {}
	for i = 0, 2 do
		local a = math.rad(i * 120 + 10)
		local p = Geo.at(zone, math.cos(a) * 6, math.sin(a) * 6 + 4, 0)
		Pieces.cyl(folder, p, 1.6, 0.8, C.piling, Enum.Material.Wood)
		table.insert(anchors, p + Vector3.new(0, 1.5, 0))
	end
	local center = Geo.at(zone, 0, 4, 30) + Pieces.WIND * 4
	Pieces.balloon(
		ctx,
		folder,
		center,
		14,
		zone.color:Lerp(C.sailcloth, 0.35),
		C.ink,
		anchors,
		false
	)
	local mark = Kit.sign(
		folder,
		CFrame.lookAt(
			center - Vector3.new(0, 13.5, 0),
			center - Vector3.new(0, 13.5, 0) + zone.slot.frame.LookVector
		),
		3.4,
		3.4,
		"?",
		nil,
		Palette.HAZARD_SIGN
	)
	mark.CanCollide = false
	-- survey tent, crates and a scaffold tower with a work light
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
	for i = 1, 3 do
		Pieces.crate(folder, Geo.cf(zone, -6 + i * 2.2, -12 + (i % 2) * 2, 0, i * 25), 1.8)
	end
	Pieces.barrel(folder, Geo.at(zone, 4, -14), C.slicker)
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
	Pieces.lantern(folder, Geo.at(zone, sx, sz - 2.4, h - 0.5), C.slicker, 30)
	Pieces.windsock(folder, Geo.at(zone, sx + 2, sz + 2, h), C.slicker, 3.5)
	-- big board at the island front
	Pieces.signBoard(
		folder,
		Geo.cf(zone, 0, -hd + 12, 5.2),
		14,
		4.6,
		"COMING SOON",
		"Next station under survey",
		Palette.HAZARD_SIGN,
		floor
	)
	-- sea mist drifting round the island
	local mist = Kit.part({
		Name = "Mist",
		Size = Vector3.new(zone.slot.width, 1, zone.slot.depth),
		CFrame = Geo.cf(zone, 0, 0, -floor + 2),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Parent = folder,
	})
	Kit.emitter(mist, {
		Texture = Kit.TEXTURES.smoke,
		Rate = 3,
		Lifetime = NumberRange.new(8, 12),
		Speed = NumberRange.new(0.5, 1),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 10),
			NumberSequenceKeypoint.new(1, 18),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.4, 0.75),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Color = ColorSequence.new(C.sailcloth),
		Acceleration = Pieces.WIND * 0.4,
		EmissionDirection = Enum.NormalId.Top,
	})
	for _ = 1, 5 do
		local x, z = rng:NextNumber(-20, 20), rng:NextNumber(-10, 20)
		Pieces.rocks(folder, Geo.at(zone, x, z), rng:NextNumber(2, 3), rng)
	end
end

-- The next field, staked out with survey pegs and caution tape and half
-- ploughed into stripes, so it reads as "a field is coming" from afar.
local function survey(ctx: Context, zone: ZoneContext)
	local folder = zone.folder
	local floor = zone.slot.floor
	local x0, x1, z0, z1 = -26, 26, -22, 30
	-- ploughed stripes, the last one only half done
	local columns = 7
	local w = (x1 - x0) / columns
	for i = 0, columns - 1, 2 do
		local done = if i >= columns - 1 then 0.45 else 1
		local za, zb = z0, z0 + (z1 - z0) * done
		local c = Geo.at(zone, x0 + (i + 0.5) * w, (za + zb) / 2, -2)
		ctx.terrain:FillBlock(
			CFrame.new(c) * zone.slot.frame.Rotation,
			Vector3.new(w, 4, zb - za),
			Enum.Material.Ground
		)
	end
	-- pegs with orange flags round the edge, joined by caution tape
	local corners = { { x0, z0 }, { x1, z0 }, { x1, z1 }, { x0, z1 } }
	local tops: { Vector3 } = {}
	for k = 1, 4 do
		local a, b = corners[k], corners[k % 4 + 1]
		local len = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
		local n = math.max(1, math.floor(len / 13 + 0.5))
		for j = 0, n - 1 do
			local t = j / n
			local x, z = a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t
			local bottom = Geo.at(zone, x, z, 0)
			Pieces.box(
				folder,
				CFrame.new(bottom + Vector3.new(0, 1.4, 0)),
				Vector3.new(0.35, 2.8, 0.35),
				C.driftwood,
				Enum.Material.Wood,
				false
			)
			Pieces.box(
				folder,
				Geo.cf(zone, x, z, 2.5, 90) * CFrame.new(0.6, 0, 0),
				Vector3.new(1.1, 0.7, 0.08),
				C.beacon:Lerp(C.slicker, 0.45),
				Enum.Material.Fabric,
				false
			)
			table.insert(tops, bottom + Vector3.new(0, 2.2, 0))
		end
	end
	for i, top in tops do
		Kit.cable(ctx, top, tops[i % #tops + 1], {
			Color = C.slicker,
			Width = 0.2,
			CurveSize = 0.4,
		})
	end
	-- a peg-and-string sign at the near edge
	Pieces.signBoard(
		folder,
		Geo.cf(zone, -16, z0 - 2, 2.2),
		7,
		2,
		"FIELD SITE",
		"keep off the pegs",
		Palette.SIGN,
		floor
	)
end

function Teaser.build(ctx: Context, zone: ZoneContext)
	island(ctx, zone)
	survey(ctx, zone)
	walk(ctx, zone)
	camp(ctx, zone)
end

return Teaser
