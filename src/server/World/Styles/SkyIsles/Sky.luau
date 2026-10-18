--!strict
-- SkyIsles lighting and the world below the islands: a warm, cozy late
-- afternoon in calm weather, deep indigo storms, and an endless sea of
-- clouds far beneath the archipelago with a few stray rocks drifting in it.

local Lighting = game:GetService("Lighting")
local ServerScriptService = game:GetService("ServerScriptService")

local World = ServerScriptService.Server.World
local Kit = require(World.Kit)
local Layout = require(World.Layout)
local WorldTypes = require(World.Types)
local Palette = require(script.Parent.Palette)
local Pieces = require(script.Parent.Pieces)

type Context = WorldTypes.Context

local C = Palette.C
local UP = Vector3.yAxis

local CLOUD_SEA_Y = -150

local Sky = {}

local function ensure<T>(parent: Instance, className: string, name: string): T
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing :: any
	end
	local created = Instance.new(className :: any)
	created.Name = name
	created.Parent = parent
	return created :: any
end

function Sky.atmosphere(_ctx: Context)
	Lighting.ClockTime = 15.6
	Lighting.Brightness = 2.5
	Lighting.Ambient = Color3.fromRGB(84, 74, 108)
	Lighting.OutdoorAmbient = Color3.fromRGB(156, 146, 182)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 232, 206)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 0.7
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.35

	-- storm look (the client tweens to these during storms)
	Lighting:SetAttribute("StormBrightness", 0.55)
	Lighting:SetAttribute("StormAmbient", Color3.fromRGB(70, 74, 120))
	Lighting:SetAttribute("StormAtmosphereColor", Color3.fromRGB(46, 40, 84))
	Lighting:SetAttribute("StormCloudColor", Color3.fromRGB(44, 40, 72))

	local atmosphere: Atmosphere = ensure(Lighting, "Atmosphere", "Atmosphere")
	atmosphere.Density = 0.3
	atmosphere.Offset = 0.18
	atmosphere.Color = Color3.fromRGB(236, 216, 232)
	atmosphere.Decay = Color3.fromRGB(150, 126, 196)
	atmosphere.Glare = 0.35
	atmosphere.Haze = 1.4

	local sky = Lighting:FindFirstChildOfClass("Sky") or ensure(Lighting, "Sky", "SkyIslesSky")
	sky.SunAngularSize = 16
	sky.MoonAngularSize = 10
	sky.StarCount = 3000
	sky.CelestialBodiesShown = true

	local bloom: BloomEffect = ensure(Lighting, "BloomEffect", "Bloom")
	bloom.Intensity = 0.65
	bloom.Size = 26
	bloom.Threshold = 0.95

	local grade: ColorCorrectionEffect = ensure(Lighting, "ColorCorrectionEffect", "StormGrade")
	grade.Brightness = 0.02
	grade.Contrast = 0.1
	grade.Saturation = 0.18
	grade.TintColor = Color3.fromRGB(255, 246, 238)

	local sunRays: SunRaysEffect = ensure(Lighting, "SunRaysEffect", "SunRays")
	sunRays.Intensity = 0.06
	sunRays.Spread = 0.7

	local terrain = workspace.Terrain
	local clouds: Clouds = ensure(terrain, "Clouds", "Clouds")
	clouds.Cover = 0.5
	clouds.Density = 0.42
	clouds.Color = Color3.fromRGB(252, 242, 246)

	terrain.WaterColor = Palette.WATER
	terrain.WaterTransparency = 0.55
	terrain.WaterWaveSize = 0.08
	terrain.WaterWaveSpeed = 6
	terrain.WaterReflectance = 0.3
	for material, color in Palette.TERRAIN do
		terrain:SetMaterialColor(material, color)
	end
end

-- A drifting islet: a small floating island with a tapered underside, a
-- little dressing on top and a crystal hanging from its tip.
local function drifter(ctx: Context, center: Vector3, radius: number, kind: number)
	local folder = ctx.folders.base
	local rng = ctx.rng
	local high = center.Y > 0
	local depth = radius * 2.4
	Kit.floatingIsland(
		ctx,
		center,
		radius,
		center.Y,
		depth,
		if high then Enum.Material.Grass else Enum.Material.Rock,
		Enum.Material.Rock
	)
	if high then
		if kind % 3 == 0 then
			Pieces.blossomTree(folder, rng, center, radius * 1.1, { C.coral, C.coralLight })
		elseif kind % 3 == 1 then
			local main = Pieces.cluster(folder, rng, center, radius * 0.75, C.cyan, 4)
			if kind == 1 then
				Pieces.light(main, C.cyan, 20, 1)
			end
		else
			Pieces.bush(
				folder,
				rng,
				center + Vector3.new(radius * 0.3, 0, 0),
				radius * 0.45,
				C.meadow
			)
			Pieces.rocks(folder, rng, center - Vector3.new(radius * 0.3, 0, 0), radius * 0.35)
		end
	end
	Pieces.cluster(folder, rng, center - UP * depth * 0.8, radius * 0.55, C.cyan, 3, true)
end

function Sky.base(ctx: Context)
	local base = ctx.folders.base

	-- the cloud sea: a pale backstop sheet far below, a lumpy layer of big
	-- soft cloud balls on top of it (cream near the isles, plum-tinted in
	-- the distance) and slow drifting puffs
	Pieces.block(
		base,
		CFrame.new(0, CLOUD_SEA_Y - 20, 0),
		Vector3.new(2048, 2, 2048),
		C.cloud,
		Enum.Material.SmoothPlastic,
		{ Name = "CloudSea", CastShadow = false, CanQuery = false, CanTouch = false }
	)
	for _, corner in
		{
			Vector3.new(1, 0, 1),
			Vector3.new(-1, 0, 0.4),
			Vector3.new(0.2, 0, -1),
		}
	do
		local holder = Pieces.block(
			base,
			CFrame.new(corner * 260 + UP * (CLOUD_SEA_Y + 34)),
			Vector3.new(520, 2, 520),
			C.cloud,
			Enum.Material.SmoothPlastic,
			{
				Name = "CloudPuffs",
				Transparency = 1,
				CastShadow = false,
				CanQuery = false,
				CanTouch = false,
			}
		)
		local puffs = Pieces.emitter(holder, {
			Name = "CloudSea",
			Texture = Kit.TEXTURES.smoke,
			Color = ColorSequence.new(C.cream, C.cloud),
			LightInfluence = 1,
			LightEmission = 0.15,
			Rate = 3,
			Lifetime = NumberRange.new(30, 40),
			Speed = NumberRange.new(0.4, 1.2),
			SpreadAngle = Vector2.new(20, 20),
			EmissionDirection = Enum.NormalId.Top,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-2, 2),
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 40),
				NumberSequenceKeypoint.new(0.5, 80),
				NumberSequenceKeypoint.new(1, 95),
			}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.25, 0.35),
				NumberSequenceKeypoint.new(0.75, 0.4),
				NumberSequenceKeypoint.new(1, 1),
			}),
		})
		if puffs then
			puffs:AddTag(Pieces.STORM_CLOUD)
		end
	end

	-- stray rocks drifting below and between the islands, kept off every
	-- current and future slot so new zones never land on one
	local future = {}
	local layout = ctx.layout
	for k = #ctx.zones + 2, #ctx.zones + 8 do
		table.insert(future, Layout.slot(layout, k, 150, 150, 0))
	end
	local function clear(p: Vector3, r: number): boolean
		if not Pieces.clearOf(ctx, p, r, nil, 14) then
			return false
		end
		for _, slot in future do
			local l = slot.frame:PointToObjectSpace(Vector3.new(p.X, 0, p.Z))
			if math.abs(l.X) < slot.width / 2 + r and math.abs(l.Z) < slot.depth / 2 + r then
				return false
			end
			local exit = slot.hubExit.Position
			local gate = slot.gate.Position
			if Pieces.segmentDistance(p, exit, gate) < r + 10 then
				return false
			end
		end
		for _, zone in ctx.zones do
			if Pieces.footprintDistance(zone, p) < r + 24 then
				return false
			end
		end
		return true
	end
	-- distant cloud banks: big soft balls ringing the archipelago below
	-- the horizon line, kept out from under every current and future isle
	local rngClouds = ctx.rng
	local banks = 0
	for k = 1, 60 do
		if banks >= 18 then
			break
		end
		local angle = k * 2.39996 + rngClouds:NextNumber(-0.3, 0.3)
		local distance = rngClouds:NextNumber(330, 470)
		local size = rngClouds:NextNumber(120, 240)
		local center = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		if clear(center, size * 0.45) then
			banks += 1
			local far = math.clamp((distance - 330) / 140, 0, 1)
			local color = C.cloud
				:Lerp(C.creamWarm, rngClouds:NextNumber(0, 0.4))
				:Lerp(C.twilightLight, 0.25 + far * 0.35)
			Pieces.block(
				base,
				CFrame.new(center + UP * (rngClouds:NextNumber(-170, -135) - size * 0.2)),
				Vector3.new(size, size * rngClouds:NextNumber(0.45, 0.6), size),
				color,
				Enum.Material.SmoothPlastic,
				{
					Name = "CloudBank",
					Shape = Enum.PartType.Ball,
					Transparency = rngClouds:NextNumber(0.15, 0.35),
					CastShadow = false,
					CanQuery = false,
					CanTouch = false,
				}
			)
		end
	end
	local placed = 0
	local rng = ctx.rng
	for _ = 1, 80 do
		if placed >= 8 then
			break
		end
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(layout.hubRadius + 40, 250)
		local radius = rng:NextNumber(6, 11)
		local high = placed % 4 ~= 3
		local y = if high then 16 + 4 * rng:NextInteger(0, 6) else rng:NextNumber(-40, -26)
		local center = Vector3.new(math.cos(angle) * distance, y, math.sin(angle) * distance)
		if clear(center, radius) then
			placed += 1
			drifter(ctx, center, radius, placed)
		end
	end
end

return Sky
