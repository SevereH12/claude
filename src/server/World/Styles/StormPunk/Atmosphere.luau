--!strict
-- Lighting for StormPunk. Calm: warm golden afternoon over teal water, soft
-- bloom so lamps and lanterns glow (cozy), light haze so the far heroes
-- keep their silhouettes. Storm (Lighting attributes the client tweens to):
-- dark slate and indigo so the cyan and zone-colour neon takes over.
-- Also paints every terrain material StormPunk uses (Palette.terrain).

local Lighting = game:GetService("Lighting")
local ServerScriptService = game:GetService("ServerScriptService")

local WorldTypes = require(ServerScriptService.Server.World.Types)
local Palette = require(script.Parent.Palette)

type Context = WorldTypes.Context

local Atmosphere = {}

local function ensure<T>(parent: Instance, className: string, name: string): T
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing :: any
	end
	if existing then
		existing:Destroy()
	end
	local created = Instance.new(className :: any)
	created.Name = name
	created.Parent = parent
	return created :: any
end

function Atmosphere.apply(ctx: Context)
	Lighting.ClockTime = 15.4
	Lighting.GeographicLatitude = 28
	Lighting.Brightness = 2.6
	Lighting.Ambient = Color3.fromRGB(70, 62, 66)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 136, 128)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.3

	-- storm look (read by the client's Storm controller)
	Lighting:SetAttribute("StormBrightness", 0.55)
	Lighting:SetAttribute("StormAmbient", Color3.fromRGB(58, 78, 108))
	Lighting:SetAttribute("StormAtmosphereColor", Color3.fromRGB(70, 84, 112))
	Lighting:SetAttribute("StormCloudColor", Color3.fromRGB(38, 40, 58))

	local atmosphere: Atmosphere = ensure(Lighting, "Atmosphere", "Atmosphere")
	atmosphere.Density = 0.26
	atmosphere.Offset = 0.1
	atmosphere.Color = Color3.fromRGB(232, 206, 182)
	atmosphere.Decay = Color3.fromRGB(110, 150, 160)
	atmosphere.Glare = 0.3
	atmosphere.Haze = 0.9

	-- neon (Brightness-boosted) blooms; sunlit ceramic does not
	local bloom: BloomEffect = ensure(Lighting, "BloomEffect", "Bloom")
	bloom.Intensity = 0.6
	bloom.Size = 26
	bloom.Threshold = 1.05

	local grade: ColorCorrectionEffect = ensure(Lighting, "ColorCorrectionEffect", "StormGrade")
	grade.Brightness = 0.02
	grade.Contrast = 0.1
	grade.Saturation = 0.18
	grade.TintColor = Color3.fromRGB(255, 244, 232)

	local rays: SunRaysEffect = ensure(Lighting, "SunRaysEffect", "SunRays")
	rays.Intensity = 0.07
	rays.Spread = 0.55

	local clouds: Clouds = ensure(ctx.terrain, "Clouds", "Clouds")
	clouds.Cover = 0.58
	clouds.Density = 0.45
	clouds.Color = Color3.fromRGB(255, 236, 220)

	local terrain = ctx.terrain
	terrain.WaterColor = Palette.water
	terrain.WaterTransparency = 0.55
	terrain.WaterWaveSize = 0.18
	terrain.WaterWaveSpeed = 10
	terrain.WaterReflectance = 0.35
	for material, color in Palette.terrain do
		terrain:SetMaterialColor(material, color)
	end
end

return Atmosphere
