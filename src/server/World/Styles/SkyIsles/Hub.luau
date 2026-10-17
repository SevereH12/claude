--!strict
-- The Stormspire: the hub island at the heart of the archipelago.
--   * a compass-rose island: paved plaza, grassy lobes and lower terraces
--     between eight lanes (one per current or future zone slot), tapering
--     into an inverted mountain with glowing crystal stalactites
--   * the Charge Altar (sell station) under the Stormspire: a gold star
--     dais and SELL pad beneath a pillared canopy, a tower above it and a
--     giant floating storm crystal ringed with runes on top
--   * a light trail, chevrons and a rune gateway on every active lane,
--     a compass signpost at spawn, tethers from the spire to every island

local ServerScriptService = game:GetService("ServerScriptService")

local World = ServerScriptService.Server.World
local Kit = require(World.Kit)
local WorldTypes = require(World.Types)
local Palette = require(script.Parent.Palette)
local Pieces = require(script.Parent.Pieces)
local Zone = require(script.Parent.Zone)

type Context = WorldTypes.Context
type ZoneContext = WorldTypes.ZoneContext

local C = Palette.C
local UP = Vector3.yAxis

local LANE_HALF = 4.5 -- half width of a lane runner
local PILLAR_RADIUS = 19
local SPAWN_RADIUS = 36
local TEASER_GLOW = Color3.fromRGB(176, 160, 226)

local Hub = {}

local function direction(angle: number): Vector3
	return Vector3.new(math.sin(angle), 0, -math.cos(angle))
end

-- Lane angles (radians) of the first eight slots, and the sector angles
-- halfway between neighbouring lanes.
local function lanesAndSectors(ctx: Context): ({ number }, { number })
	local layout = ctx.layout
	local lanes: { number } = {}
	local seen: { [number]: boolean } = {}
	for k = 1, 8 do
		local degrees = (layout.firstAngle + (k - 1) * layout.angleStep) % 360
		local key = math.round(degrees * 10)
		if not seen[key] then
			seen[key] = true
			table.insert(lanes, math.rad(degrees))
		end
	end
	local sorted = table.clone(lanes)
	table.sort(sorted)
	local sectors: { number } = {}
	for i, angle in sorted do
		local nextAngle = sorted[i % #sorted + 1]
		if nextAngle <= angle then
			nextAngle += math.pi * 2
		end
		table.insert(sectors, (angle + nextAngle) / 2)
	end
	return lanes, sectors
end

-- Land ------------------------------------------------------------------------------

local function buildLand(ctx: Context, sectors: { number }): { Vector3 }
	local layout = ctx.layout
	local floor = layout.hubFloor
	local R = layout.hubRadius
	local rng = ctx.rng
	local hub = ctx.folders.hub

	-- inverted mountain, darker toward the tip
	local materials = {
		Enum.Material.Rock,
		Enum.Material.Rock,
		Enum.Material.Slate,
		Enum.Material.Slate,
		Enum.Material.Basalt,
	}
	local depth = 96
	local layers = 8
	local step = depth / layers
	for i = layers, 1, -1 do
		local f = (i - 0.5) / layers
		local radius = math.max(6, (R + 10) * (1 - f ^ 1.3))
		local jitter = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) * R * 0.05
		local material = materials[math.clamp(math.ceil(f * #materials), 1, #materials)]
		Kit.blob(ctx, jitter, radius, floor - 6 - (i - 1) * step, step + 6, material, 7)
	end
	-- the tip: a long spike with a glowing crystal cluster hanging off it
	local tipY = floor - 6 - depth
	local spikeRadius = 6
	local y = tipY + step
	for _ = 1, 4 do
		ctx.terrain:FillCylinder(CFrame.new(0, y - 4, 0), 9, spikeRadius, Enum.Material.Basalt)
		y -= 7
		spikeRadius *= 0.7
	end
	local tipCrystal = Pieces.cluster(hub, rng, Vector3.new(0, y + 3, 0), 14, C.cyan, 5, true)
	Pieces.light(tipCrystal, C.cyan, 40, 2)

	-- glowing crystals bursting from the cliffs, between lanes
	for i = 1, #sectors, 3 do
		local dir = direction(sectors[i])
		local spot = dir * (R - 4) + UP * (floor - 30)
		Pieces.cluster(hub, rng, spot, 12, C.cyan, 4)
	end

	-- lower terraces and grassy lobes between the lanes
	local lawnSpots: { Vector3 } = {}
	for _, angle in sectors do
		local dir = direction(angle)
		local lowRadius = rng:NextNumber(11, 14)
		local low = dir * (R + 13)
		if Pieces.offLanes(ctx, low, lowRadius, 7) and Pieces.clearOf(ctx, low, lowRadius) then
			Kit.blob(ctx, low, lowRadius, floor - 8, 10, Enum.Material.LeafyGrass, 5)
		end
		local midRadius = rng:NextNumber(12, 15)
		local mid = dir * (R + 5) + Vector3.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3))
		if Pieces.offLanes(ctx, mid, midRadius, 7) and Pieces.clearOf(ctx, mid, midRadius) then
			Kit.blob(ctx, mid, midRadius, floor - 4, 10, Enum.Material.Grass, 5)
		end
	end

	-- the plaza and its lawns
	ctx.terrain:FillCylinder(CFrame.new(0, floor - 6, 0), 12, R + 2, Enum.Material.Pavement)
	for _, angle in sectors do
		local dir = direction(angle)
		local radius = rng:NextNumber(12, 14)
		local spot = dir * (R - 1)
		if
			Pieces.offLanes(ctx, spot, radius, LANE_HALF + 1) and Pieces.clearOf(ctx, spot, radius)
		then
			ctx.terrain:FillCylinder(
				CFrame.new(spot.X, floor - 5, spot.Z),
				10,
				radius,
				Enum.Material.Grass
			)
			table.insert(lawnSpots, Vector3.new(spot.X, floor, spot.Z) + dir * (radius - 4))
		end
	end
	-- an inner ring of cobbles around the altar
	ctx.terrain:FillCylinder(CFrame.new(0, floor - 2, 0), 4, 30, Enum.Material.Cobblestone)
	ctx.terrain:FillCylinder(CFrame.new(0, floor - 2, 0), 4, 22, Enum.Material.Pavement)
	return lawnSpots
end

-- Altar and spire ---------------------------------------------------------------------

local function buildAltar(ctx: Context, sectors: { number }, facing: Vector3)
	local hub = ctx.folders.hub
	local rng = ctx.rng
	local floor = ctx.layout.hubFloor
	local center = Vector3.new(0, floor, 0)

	-- star dais: gold skirt, plum tier, marble tier, frame, SELL pad
	Pieces.star(hub, center + UP * 0.3, 42, 0.6, C.gold, Enum.Material.Metal)
	Pieces.star(hub, center + UP * 1, 40, 1.8, C.plum, Enum.Material.Slate, true)
	Pieces.star(hub, center + UP * 2, 28, 1.2, C.cream, Enum.Material.Marble, true)
	Pieces.solid(
		hub,
		CFrame.new(center + UP * 2.1),
		Vector3.new(23, 0.4, 23),
		C.plumDeep,
		Enum.Material.Slate
	)
	local padPosition = center + UP * 2.2
	local pad = Kit.part({
		Name = "SellPad",
		Size = Vector3.new(20, 0.6, 20),
		CFrame = CFrame.lookAt(padPosition, padPosition + facing),
		Color = C.gold,
		Material = Enum.Material.Neon,
		Parent = hub,
	})
	pad.CanTouch = false
	-- SELL lettered along all four edges of the pad, each band reading
	-- for someone walking in from that side
	local padTop = padPosition + UP * 0.3
	for k = 0, 3 do
		local d = (CFrame.Angles(0, math.rad(k * 90), 0) * pad.CFrame).LookVector
		local bandAt = padTop + d * 6.6 + UP * 0.06
		local band = Pieces.block(
			hub,
			CFrame.lookAt(bandAt, bandAt - d),
			Vector3.new(7.8, 0.1, 5.2),
			C.goldDeep,
			Enum.Material.SmoothPlastic,
			{ CastShadow = false, Name = "SellLettering" }
		)
		Kit.faceText(band, Enum.NormalId.Top, "SELL", nil, {
			boardColor = C.goldDeep,
			titleColor = C.plumDeep,
			strokeColor = C.cream,
			titleFont = Enum.Font.LuckiestGuy,
		})
	end
	Kit.sellArea(hub, pad, 12)
	Pieces.light(pad, C.gold, 32, 1.6)

	-- eight pillars between the lanes
	local pillarTop = floor + 1 + 23.4
	local tops: { Vector3 } = {}
	for _, angle in sectors do
		local dir = direction(angle)
		local foot = center + dir * PILLAR_RADIUS + UP * 1
		local frame = CFrame.lookAt(foot, foot - dir)
		Pieces.solid(
			hub,
			frame * CFrame.new(0, 0.8, 0),
			Vector3.new(3.8, 1.6, 3.8),
			C.plumDeep,
			Enum.Material.Slate
		)
		Pieces.solid(
			hub,
			frame * CFrame.new(0, 1.6 + 10.2, 0),
			Vector3.new(2.6, 20.4, 2.6),
			C.skystone,
			Enum.Material.Cobblestone
		)
		Pieces.block(
			hub,
			frame * CFrame.new(0, 13, 0),
			Vector3.new(2.9, 0.6, 2.9),
			C.cyan,
			Enum.Material.Neon
		)
		Pieces.solid(
			hub,
			frame * CFrame.new(0, 22.7, 0),
			Vector3.new(3.8, 1.4, 3.8),
			C.cream,
			Enum.Material.Marble
		)
		table.insert(tops, Vector3.new(foot.X, pillarTop, foot.Z))
	end
	-- lintels and the star roof
	for i, a in tops do
		local b = tops[i % #tops + 1]
		Pieces.solid(
			hub,
			CFrame.lookAt((a + b) / 2 + UP * 0.9, b + UP * 0.9),
			Vector3.new(2.4, 1.8, (b - a).Magnitude + 2),
			C.plum,
			Enum.Material.Slate
		)
	end
	-- fabric banners between the pillars and lanterns under the roof edge
	for i, a in tops do
		local b = tops[i % #tops + 1]
		local middle = (a + b) / 2
		local out = Vector3.new(middle.X, 0, middle.Z).Unit
		local banner = CFrame.lookAt(middle + out * 1.3 - UP * 1.9, middle + out * 3 - UP * 1.9)
		local color = if i % 2 == 0 then C.coral else C.cyanDeep
		Pieces.block(hub, banner, Vector3.new(6, 3.6, 0.15), color, Enum.Material.Fabric)
		Pieces.wedge(
			hub,
			banner * CFrame.new(0, -2.6, 0) * CFrame.Angles(math.pi, 0, 0),
			Vector3.new(6, 1.6, 0.15),
			color,
			Enum.Material.Fabric
		)
		if i % 2 == 1 then
			local lamp = Pieces.lantern(hub, middle - out * 1.8 - UP * 2.6, C.gold, nil)
			lamp.Name = "CanopyLantern"
		end
	end

	local roofTop = pillarTop + 3.2
	Pieces.star(hub, center + UP * (pillarTop + 1.2 - floor), 40, 0.6, C.gold, Enum.Material.Metal)
	Pieces.star(hub, Vector3.new(0, roofTop, 0), 38, 2.4, C.plum, Enum.Material.Slate)

	-- giant SELL boards hanging under the canopy on four sides
	local boardY = floor + 19
	for k = 0, 3 do
		local dir = direction(math.rad(k * 90))
		local position = Vector3.new(0, boardY, 0) + dir * 10.6
		local frame = CFrame.lookAt(position, position + dir)
		Pieces.board(hub, frame, 18, 5.4, "SELL", "Bring your charge here", Palette.SELL_SIGN)
		for side = -1, 1, 2 do
			local hook = frame * CFrame.new(side * 7, 3.1, 0)
			Pieces.beam(ctx, hook.Position, hook.Position + UP * (pillarTop - boardY - 2.6), {
				color = C.iron,
				width = 0.3,
			})
		end
	end
	-- the charge conduit: a crystal under the roof pouring light into the pad
	local conduit = Pieces.cluster(hub, rng, Vector3.new(0, pillarTop + 0.5, 0), 6, C.gold, 4, true)
	Pieces.sparkles(conduit, C.gold, 6, 1)
	Pieces.beam(ctx, Vector3.new(0, pillarTop - 4, 0), padPosition + UP * 0.4, {
		color = C.gold,
		color1 = C.cream,
		width = 3,
		width1 = 6,
		glow = 1,
		transparency = 0.35,
		transparency1 = 0.75,
		texture = Kit.TEXTURES.sparkle,
		textureSpeed = -1,
		textureLength = 3,
	})

	-- the tower: stacked star tiers, cornices and glowing window slits
	local function tier(
		height: number,
		size: number,
		top: number,
		color: Color3,
		material: Enum.Material
	)
		Pieces.star(hub, Vector3.new(0, top, 0), size, height, color, material, true)
	end
	local y = roofTop
	tier(15, 22, y + 15, C.skystone, Enum.Material.Cobblestone)
	Pieces.star(hub, Vector3.new(0, y + 9, 0), 22.6, 0.7, C.cyan, Enum.Material.Neon)
	tier(1.4, 25, y + 16.4, C.plum, Enum.Material.Slate)
	tier(13, 16, y + 29.4, C.skystoneLight, Enum.Material.Cobblestone)
	tier(1.2, 19, y + 30.6, C.gold, Enum.Material.Metal)
	tier(11, 11, y + 41.6, C.skystone, Enum.Material.Cobblestone)
	tier(1, 13.4, y + 42.6, C.plum, Enum.Material.Slate)
	tier(5, 7, y + 47.6, C.skystoneLight, Enum.Material.Cobblestone)
	tier(4, 4, y + 51.6, C.gold, Enum.Material.Metal)
	for i, angle in sectors do
		if i % 2 == 0 then
			local dir = direction(angle)
			Pieces.block(
				hub,
				CFrame.lookAt(dir * 11.6 + UP * (y + 7), dir * 20 + UP * (y + 7)),
				Vector3.new(0.9, 8, 0.9),
				C.cyan,
				Enum.Material.Neon
			)
			Pieces.block(
				hub,
				CFrame.lookAt(dir * 8.4 + UP * (y + 23), dir * 20 + UP * (y + 23)),
				Vector3.new(0.8, 6, 0.8),
				C.cyan,
				Enum.Material.Neon
			)
		end
	end

	-- rune stones drifting around the tower
	for k = 1, 6 do
		local angle = k / 6 * math.pi * 2 + 0.3
		local stoneAt = direction(angle) * rng:NextNumber(17, 21)
			+ UP * (y + rng:NextNumber(10, 34))
		local stone = Pieces.block(
			hub,
			CFrame.new(stoneAt)
				* CFrame.Angles(rng:NextNumber(-0.4, 0.4), angle, rng:NextNumber(-0.3, 0.3)),
			Vector3.new(3.2, 4.4, 1.4),
			C.skystone,
			Enum.Material.Cobblestone
		)
		Pieces.block(
			hub,
			stone.CFrame * CFrame.new(0, 0, -0.72),
			Vector3.new(1, 2.4, 0.1),
			if k % 2 == 0 then C.gold else C.cyan,
			Enum.Material.Neon
		)
	end

	-- crown prongs holding the storm crystal
	local crystalCenter = Vector3.new(0, y + 70, 0)
	local prongTips: { Vector3 } = {}
	for k = 0, 3 do
		local dir = direction(math.rad(45 + k * 90))
		local a = dir * 2.5 + UP * (y + 50)
		local b = dir * 7.5 + UP * (y + 64)
		Pieces.plank(hub, a, b, 1.4, 1.4, C.plum, Enum.Material.Slate)
		Pieces.diamond(hub, b, 1.6, C.cyan)
		table.insert(prongTips, b)
	end
	local crystal = Pieces.bigShard(hub, crystalCenter, 16, 7.5, C.cyan, C.cream, 0, 0)
	Pieces.bigShard(hub, crystalCenter + UP * 0.05, 11, 7.5, C.cyan, C.cream, 0, 180)
	Pieces.light(crystal, C.cyan, 60, 2.2)
	Pieces.sparkles(crystal, C.cyan, 8, 1.6)
	Pieces.ring(ctx, crystalCenter + UP * 3, 10, Vector3.new(1, 0.25, 0).Unit, Vector3.zAxis, 14, {
		color = C.cyan,
		width = 0.55,
		glow = 1,
	})
	Pieces.ring(ctx, crystalCenter + UP * 2, 12.5, Vector3.xAxis, Vector3.new(0, 0.4, 1).Unit, 14, {
		color = C.gold,
		width = 0.45,
		glow = 1,
	})
	Pieces.ring(
		ctx,
		crystalCenter + UP * 1,
		15,
		Vector3.new(1, -0.3, 0.3).Unit,
		Vector3.new(0, 0.5, 1).Unit,
		16,
		{
			color = C.cyan,
			width = 0.35,
			glow = 1,
			transparency = 0.2,
		}
	)
	for _, tip in prongTips do
		Pieces.arc(ctx, crystalCenter + (tip - crystalCenter).Unit * 3, tip, 3, 1.4, {
			color = C.cyan,
			color1 = C.cream,
			width = 0.3,
			glow = 1,
		})
	end
end

-- Lanes --------------------------------------------------------------------------------

local function laneOwner(ctx: Context, index: number): ZoneContext?
	if index <= #ctx.zones then
		return ctx.zones[index]
	elseif index == #ctx.zones + 1 then
		return ctx.teaser
	end
	return nil
end

local function buildLanes(ctx: Context, lanes: { number })
	local hub = ctx.folders.hub
	local floor = ctx.layout.hubFloor
	local R = ctx.layout.hubRadius
	for index, angle in lanes do
		local dir = direction(angle)
		local from = dir * 26
		local to = dir * (R + 1.5)
		local length = (to - from).Magnitude
		local middle = (from + to) / 2
		-- paved runner on every lane, ready for future zones
		Pieces.block(
			hub,
			CFrame.lookAt(middle, to) + UP * (floor - 0.06),
			Vector3.new(LANE_HALF * 2, 0.4, length),
			C.skystoneLight,
			Enum.Material.Cobblestone,
			{ CastShadow = false, Name = "LaneRunner" }
		)
		local zone = laneOwner(ctx, index)
		if zone then
			local glow = if zone.isTeaser then TEASER_GLOW else zone.color
			-- light trail: centre line plus chevrons pointing out to the zone
			if zone.isTeaser then
				for s = 30, R - 2, 6 do
					local p = dir * s + UP * (floor + 0.14)
					Pieces.block(
						hub,
						CFrame.lookAt(p, p + dir),
						Vector3.new(0.8, 0.2, 3),
						glow,
						Enum.Material.Neon,
						{ CastShadow = false }
					)
				end
			else
				local a = dir * 27 + UP * (floor + 0.14)
				local b = dir * (R + 1) + UP * (floor + 0.14)
				Pieces.block(
					hub,
					CFrame.lookAt((a + b) / 2, b),
					Vector3.new(0.8, 0.2, (b - a).Magnitude),
					glow,
					Enum.Material.Neon,
					{ CastShadow = false, Name = "LightTrail" }
				)
				for s = 32, R - 6, 8 do
					local tip = dir * (s + 1.5) + UP * (floor + 0.16)
					for side = -1, 1, 2 do
						local lateral = dir:Cross(UP) * side
						local tail = tip - dir * 2.6 + lateral * 2.6
						Pieces.block(
							hub,
							CFrame.lookAt((tip + tail) / 2, tip),
							Vector3.new(0.9, 0.2, (tip - tail).Magnitude + 0.6),
							glow,
							Enum.Material.Neon,
							{ CastShadow = false, Name = "Chevron" }
						)
					end
				end
			end
			-- rune gateway at the rim, sign facing the plaza
			local gatePoint = dir * (R - 7) + UP * floor
			local def = zone.def
			local title = if def then string.upper(def.displayName) else "COMING SOON"
			local subtitle = if def then def.tagline else "A new isle is being charted"
			Pieces.gateway(
				hub,
				CFrame.lookAt(gatePoint, gatePoint - dir),
				7,
				13,
				glow,
				title,
				subtitle,
				"STORMSPIRE",
				"SELL at the altar",
				not zone.isTeaser
			)
		else
			-- dormant lane: a pair of unlit markers at the rim
			for side = -1, 1, 2 do
				local p = dir * (R - 2) + dir:Cross(UP) * side * (LANE_HALF + 1.5) + UP * floor
				Pieces.solid(
					hub,
					CFrame.new(p + UP * 1.4),
					Vector3.new(1.4, 2.8, 1.4),
					C.skystone,
					Enum.Material.Cobblestone
				)
				Pieces.diamond(hub, p + UP * 3.3, 0.9, C.skystoneDark, Enum.Material.Glass)
			end
		end
	end
end

-- Spawn -----------------------------------------------------------------------------------

local function buildSpawn(ctx: Context, spawnAngle: number): Vector3
	local hub = ctx.folders.hub
	local floor = ctx.layout.hubFloor
	local rng = ctx.rng
	local dir = direction(spawnAngle)
	local position = dir * SPAWN_RADIUS + UP * floor
	local forward = -dir
	local right = forward:Cross(UP)

	Pieces.cylinder(
		hub,
		position - UP * 0.1,
		0.3,
		14.5,
		C.cyan,
		Enum.Material.Neon,
		{ CastShadow = false }
	)
	Pieces.cylinder(
		hub,
		position - UP * 0.1,
		0.42,
		12.8,
		C.plum,
		Enum.Material.Slate,
		{ CastShadow = false }
	)
	Kit.spawn(hub, CFrame.lookAt(position, position + forward), Vector3.new(9, 1, 9), {
		Color = C.skystoneDark,
		Material = Enum.Material.Slate,
	})
	for k = 0, 3 do
		local corner = position + direction(spawnAngle + math.rad(45 + k * 90)) * 8.6
		local main = Pieces.cluster(hub, rng, corner, 3.4, C.cyan, 2)
		if k == 0 then
			Pieces.light(main, C.cyan, 18, 1)
		end
	end

	-- welcome board behind the spawn, facing the plaza
	local boardFoot = position + dir * 10
	local boardFrame = CFrame.lookAt(boardFoot + UP * 7.5, boardFoot + UP * 7.5 - dir)
	for side = -1, 1, 2 do
		local post = (boardFrame * CFrame.new(side * 7.4, 0, 0)).Position
		Pieces.cylinder(
			hub,
			Vector3.new(post.X, floor, post.Z),
			10.4,
			0.9,
			C.wood,
			Enum.Material.Wood,
			{
				CanCollide = true,
			}
		)
		Pieces.diamond(hub, Vector3.new(post.X, floor + 10.9, post.Z), 1, C.gold)
	end
	Pieces.board(
		hub,
		boardFrame,
		14,
		5.4,
		"STORMSPIRE",
		"Catch lightning on the isles, sell it at the altar",
		Palette.SIGN
	)

	-- compass signpost beside the spawn pointing at the altar and every lane
	local post = position + right * 6.5 + forward * 1
	local arrows = #ctx.zones + 2
	local postHeight = math.max(12, 4 + arrows * 2.2)
	Pieces.cylinder(hub, post, postHeight, 1, C.wood, Enum.Material.Wood, { CanCollide = true })
	Pieces.diamond(hub, post + UP * (postHeight + 0.6), 1.4, C.gold)
	local height = postHeight - 1
	local function pointAt(target: Vector3, title: string, style: Kit.SignStyle)
		local toward = (target - post) * Vector3.new(1, 0, 1)
		if toward.Magnitude < 1 then
			return
		end
		local d = toward.Unit
		Pieces.arrow(hub, post + UP * height + d * 5.2, d, 8.4, 1.7, title, style)
		height -= 2.2
	end
	pointAt(Vector3.zero, "SELL", Palette.SELL_SIGN)
	for _, zone in ctx.zones do
		local def = zone.def :: any
		pointAt(
			zone.slot.hubExit.Position,
			string.upper(def.displayName),
			Palette.signFor(zone.color, true)
		)
	end
	pointAt(ctx.teaser.slot.hubExit.Position, "COMING SOON", Palette.signFor(TEASER_GLOW, true))
	return position
end

-- Sectors: gardens, lamps, banners ---------------------------------------------------------

local function buildSectors(
	ctx: Context,
	sectors: { number },
	spawnAngle: number,
	lawnSpots: { Vector3 }
)
	local hub = ctx.folders.hub
	local floor = ctx.layout.hubFloor
	local rng = ctx.rng
	local blossoms = { C.coral, C.coralLight, C.coral }
	local kind = 0
	for _, angle in sectors do
		local gap = math.abs(((angle - spawnAngle + math.pi) % (math.pi * 2)) - math.pi)
		if gap > 0.05 then
			kind += 1
			local dir = direction(angle)
			local right = dir:Cross(UP)
			local spot = dir * 44 + UP * floor
			if kind % 3 == 1 then
				-- blossom grove on a star planter
				Pieces.star(hub, spot + UP * 1.2, 9, 1.2, C.plum, Enum.Material.Slate, true)
				Pieces.star(hub, spot + UP * 1.35, 7.6, 0.3, C.meadowDark, Enum.Material.Grass)
				Pieces.blossomTree(hub, rng, spot + UP * 1.2, 13, blossoms)
				Pieces.bush(hub, rng, spot + right * 9, 3, C.meadow)
				Pieces.flowers(hub, rng, spot - right * 8, { C.coral, C.cream, C.gold }, 4)
			elseif kind % 3 == 2 then
				-- crystal planter with a lamp and a bench
				Pieces.star(hub, spot + UP * 1, 7, 1, C.plum, Enum.Material.Slate, true)
				local main = Pieces.cluster(hub, rng, spot + UP * 1, 7, C.cyan, 4)
				Pieces.light(main, C.cyan, 16, 1)
				Pieces.lampPost(hub, spot + right * 9 + UP * 0, 9, C.gold, -dir, 20)
				local bench = spot - right * 8
				Pieces.solid(
					hub,
					CFrame.lookAt(bench + UP * 1.3, bench + UP * 1.3 - dir),
					Vector3.new(5, 0.5, 1.6),
					C.woodLight,
					Enum.Material.Wood
				)
				for side = -1, 1, 2 do
					Pieces.solid(
						hub,
						CFrame.lookAt(bench + UP * 0.55, bench + UP * 0.55 - dir)
							* CFrame.new(side * 2, 0, 0),
						Vector3.new(0.6, 1.1, 1.4),
						C.plum,
						Enum.Material.Slate
					)
				end
			else
				-- banner poles in the style's warm and cool accents
				for side = -1, 1, 2 do
					local foot = spot + right * side * 5
					Pieces.cylinder(
						hub,
						foot,
						12,
						0.6,
						C.plumDeep,
						Enum.Material.Metal,
						{ CanCollide = true }
					)
					Pieces.diamond(hub, foot + UP * 12.4, 0.9, C.gold)
					local banner = CFrame.lookAt(
						foot + UP * 8.2 + right * side * 1.5,
						foot + UP * 8.2 + right * side * 1.5 - dir
					)
					Pieces.block(
						hub,
						banner,
						Vector3.new(2.6, 6.5, 0.15),
						if side == 1 then C.coral else C.cyanDeep,
						Enum.Material.Fabric
					)
					Pieces.wedge(
						hub,
						banner * CFrame.new(0, -4.1, 0) * CFrame.Angles(math.pi, 0, 0),
						Vector3.new(2.6, 1.7, 0.15),
						if side == 1 then C.coral else C.cyanDeep,
						Enum.Material.Fabric
					)
				end
				Pieces.bush(hub, rng, spot, 3.4, C.meadow)
			end
		end
	end
	-- lawn dressing: flowers, rocks, bushes on the outer lawns
	for _, spot in lawnSpots do
		Pieces.flowers(hub, rng, spot, { C.coral, C.gold, C.cream }, 3)
		Pieces.rocks(
			hub,
			rng,
			spot + Vector3.new(rng:NextNumber(-4, 4), 0, rng:NextNumber(-4, 4)),
			2.2
		)
	end
	-- two waterfalls pouring off lawn edges into the clouds
	local poured = 0
	for _, spot in lawnSpots do
		if poured < 2 and Pieces.offLanes(ctx, spot, 5, LANE_HALF) then
			local out = spot * Vector3.new(1, 0, 1)
			local outward = out.Unit
			local pool = spot - outward * 1
			ctx.terrain:FillCylinder(
				CFrame.new(pool.X, floor - 2, pool.Z),
				4,
				3.6,
				Enum.Material.Water
			)
			Pieces.waterfall(ctx, pool + outward * 4.5 - UP * 0.6, outward, 110, 3.4)
			poured += 1
		end
	end
end

-- Tethers -----------------------------------------------------------------------------------

local function buildTethers(ctx: Context)
	local hub = ctx.folders.hub
	local floor = ctx.layout.hubFloor
	-- the chains leave the spire's third tier, high above the canopy and
	-- the lawns, and fall gently to the bollards on each island's rim
	local towerY = floor + 63
	local function bracket(start: Vector3, dir: Vector3)
		Pieces.block(
			hub,
			CFrame.lookAt(start - dir * 1, start + dir),
			Vector3.new(2.4, 2.4, 3),
			C.iron,
			Enum.Material.Metal
		)
	end
	for _, zone in ctx.zones do
		local dir = zone.slot.hubExit.LookVector
		local right = dir:Cross(UP)
		for _, point in Zone.tetherPoints(ctx, zone) do
			local side = if (point - Vector3.zero):Dot(right) > 0 then 1 else -1
			local start = dir * 8.5 + right * side * 2 + UP * towerY
			bracket(start, dir)
			Pieces.chain(ctx, start, point, (point - start).Magnitude * 0.035)
		end
	end
	-- the teaser's tether hangs snapped
	local dir = ctx.teaser.slot.hubExit.LookVector
	local start = dir * 8.5 + UP * towerY
	bracket(start, dir)
	Pieces.chain(ctx, start, start + dir * 10 - UP * 24, 5)
end

function Hub.build(ctx: Context)
	local lanes, sectors = lanesAndSectors(ctx)
	-- spawn sits in the sector just clockwise of the first zone's lane
	local first = math.rad(ctx.layout.firstAngle % 360)
	local spawnAngle = sectors[1]
	local best = math.huge
	for _, angle in sectors do
		local delta = (angle - first) % (math.pi * 2)
		if delta < best then
			best = delta
			spawnAngle = angle
		end
	end
	-- the SELL pad lines up with the star; its text reads for someone
	-- walking in along the lane nearest the spawn's view
	local view = math.round((spawnAngle + math.pi) / (math.pi / 4)) * (math.pi / 4)
	local lawnSpots = buildLand(ctx, sectors)
	buildAltar(ctx, sectors, direction(view))
	buildLanes(ctx, lanes)
	buildSpawn(ctx, spawnAngle)
	buildSectors(ctx, sectors, spawnAngle, lawnSpots)
	buildTethers(ctx)
end

return Hub
