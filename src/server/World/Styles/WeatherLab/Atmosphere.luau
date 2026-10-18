--!strict
-- Lighting for Barometer Bay. Calm: a warm late afternoon by the sea with
-- soft haze, cream clouds and gentle bloom so lanterns and cyan accents
-- glow. Storm (Lighting attributes the client tweens to): slate-indigo
-- ambient, blue-grey air and charcoal-navy clouds.

local Lighting = game:GetService("Lighting")

local WLTypes = require(script.Parent.WLTypes)

type Context = WLTypes.Context

local Atmosphere = {}

-- Removes earlier lighting objects of these classes so styles never stack.
local function fresh(parent: Instance, className: string, name: string): Instance
	for _, child in parent:GetChildren() do
		if child.ClassName == className then
			child:Destroy()
		end
	end
	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = parent
	return instance
end

function Atmosphere.build(ctx: Context)
	Lighting.ClockTime = 15.6
	Lighting.GeographicLatitude = 32
	Lighting.Brightness = 2.6
	Lighting.Ambient = Color3.fromRGB(96, 98, 118)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 146, 150)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 228, 196)
	Lighting.ColorShift_Bottom = Color3.fromRGB(110, 140, 170)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.5
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.35
	Lighting.ExposureCompensation = 0.1

	-- how storms look in this style (the client tweens to these and back)
	Lighting:SetAttribute("StormBrightness", 0.9)
	Lighting:SetAttribute("StormAmbient", Color3.fromRGB(62, 76, 108))
	Lighting:SetAttribute("StormAtmosphereColor", Color3.fromRGB(88, 104, 136))
	Lighting:SetAttribute("StormCloudColor", Color3.fromRGB(50, 58, 82))

	local atmosphere = fresh(Lighting, "Atmosphere", "SeaHaze") :: Atmosphere
	atmosphere.Density = 0.27
	atmosphere.Offset = 0.2
	atmosphere.Color = Color3.fromRGB(212, 224, 232)
	atmosphere.Decay = Color3.fromRGB(122, 146, 172)
	atmosphere.Glare = 0.35
	atmosphere.Haze = 1.3

	local clouds = fresh(ctx.terrain, "Clouds", "Cumulus") :: Clouds
	clouds.Cover = 0.56
	clouds.Density = 0.55
	clouds.Color = Color3.fromRGB(255, 246, 236)

	local bloom = fresh(Lighting, "BloomEffect", "LanternBloom") :: BloomEffect
	bloom.Intensity = 0.6
	bloom.Size = 28
	bloom.Threshold = 1.3

	local rays = fresh(Lighting, "SunRaysEffect", "SeaSun") :: SunRaysEffect
	rays.Intensity = 0.07
	rays.Spread = 0.6

	local grade = fresh(Lighting, "ColorCorrectionEffect", "StormGrade") :: ColorCorrectionEffect
	grade.Brightness = 0.02
	grade.Contrast = 0.08
	grade.Saturation = 0.15
	grade.TintColor = Color3.fromRGB(255, 247, 236)
end

return Atmosphere
