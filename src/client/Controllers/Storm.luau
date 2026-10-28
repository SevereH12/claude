--!strict
-- Tracks the storm phase from the server and sets the mood: during a storm
-- the sky darkens, clouds roll in and it rains. All of this is local to
-- this player's screen. The rain follows SETTINGS > Graphics > Rain and
-- particles, and the colour grade Bloom and colour. Changes take 4 seconds
-- (slow enough for Reduce flashing). A Supercell (Systems/StormCycle) is a
-- darker, purple version of the storm look.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Shared.Net)
local SettingsStore = require(script.Parent.Parent.Lib.SettingsStore)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Types = require(ReplicatedStorage.Shared.Types)

local SKY_TWEEN = TweenInfo.new(4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local RAIN_HEIGHT = 45

type Look = {
	lighting: { [string]: any },
	atmosphere: { [string]: any },
	clouds: { [string]: any },
	grade: { [string]: any },
	rainRate: number,
}

local RAIN_RATE = 450

-- Calm = however the world style set up the lighting (captured at start).
-- Storm = the style's storm values from Lighting attributes
-- (StormBrightness, StormAmbient, StormAtmosphereColor, StormCloudColor),
-- falling back to a darker, bluer version of the calm look.
local LOOKS: { [string]: Look } = {}

local function attribute<T>(name: string, fallback: T): T
	local value = Lighting:GetAttribute(name)
	if value == nil then
		return fallback
	end
	return value :: any
end

local function darker(color: Color3, amount: number): Color3
	return color:Lerp(Color3.fromRGB(40, 48, 72), amount)
end

local function captureLooks()
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
	local grade = Lighting:FindFirstChild("StormGrade")

	local calm: Look = {
		lighting = {
			Brightness = Lighting.Brightness,
			OutdoorAmbient = Lighting.OutdoorAmbient,
			ClockTime = Lighting.ClockTime,
		},
		atmosphere = {},
		clouds = {},
		grade = {},
		rainRate = 0,
	}
	local storm: Look = {
		lighting = {
			Brightness = attribute("StormBrightness", Lighting.Brightness * 0.4),
			OutdoorAmbient = attribute("StormAmbient", darker(Lighting.OutdoorAmbient, 0.45)),
			ClockTime = Lighting.ClockTime + 0.9,
		},
		atmosphere = {},
		clouds = {},
		grade = {},
		rainRate = RAIN_RATE,
	}
	if atmosphere then
		calm.atmosphere =
			{ Density = atmosphere.Density, Color = atmosphere.Color, Haze = atmosphere.Haze }
		storm.atmosphere = {
			Density = math.min(atmosphere.Density + 0.13, 0.7),
			Color = attribute("StormAtmosphereColor", darker(atmosphere.Color, 0.45)),
			Haze = atmosphere.Haze + 0.9,
		}
	end
	if clouds then
		calm.clouds = { Cover = clouds.Cover, Density = clouds.Density, Color = clouds.Color }
		storm.clouds = {
			Cover = math.max(clouds.Cover, 0.92),
			Density = math.max(clouds.Density, 0.85),
			Color = attribute("StormCloudColor", darker(clouds.Color, 0.6)),
		}
	end
	if grade and grade:IsA("ColorCorrectionEffect") then
		calm.grade = {
			Saturation = grade.Saturation,
			Contrast = grade.Contrast,
			TintColor = grade.TintColor,
		}
		storm.grade = {
			Saturation = grade.Saturation - 0.25,
			Contrast = grade.Contrast + 0.08,
			TintColor = grade.TintColor:Lerp(Color3.fromRGB(200, 215, 255), 0.6),
		}
	end
	LOOKS.Calm = calm
	LOOKS.Storm = storm

	-- Supercell: the storm look, darker and purple
	local purple = Color3.fromRGB(70, 30, 110)
	local supercell: Look = {
		lighting = {
			Brightness = storm.lighting.Brightness * 0.6,
			OutdoorAmbient = (storm.lighting.OutdoorAmbient :: Color3):Lerp(purple, 0.5),
			ClockTime = storm.lighting.ClockTime,
		},
		atmosphere = table.clone(storm.atmosphere),
		clouds = table.clone(storm.clouds),
		grade = table.clone(storm.grade),
		rainRate = RAIN_RATE * 1.5,
	}
	if typeof(storm.atmosphere.Color) == "Color3" then
		supercell.atmosphere.Color = storm.atmosphere.Color:Lerp(purple, 0.55)
		supercell.atmosphere.Density = math.min(storm.atmosphere.Density + 0.08, 0.75)
	end
	if typeof(storm.clouds.Color) == "Color3" then
		supercell.clouds.Color = storm.clouds.Color:Lerp(purple, 0.5)
		supercell.clouds.Cover = 1
	end
	if typeof(storm.grade.TintColor) == "Color3" then
		supercell.grade.TintColor = storm.grade.TintColor:Lerp(Color3.fromRGB(200, 160, 255), 0.6)
	end
	LOOKS.Supercell = supercell
end

-- Which look a state wants: "Calm", "Storm" or "Supercell".
local function lookOf(state: Types.StormState): string
	return if state.phase == "Storm" and state.supercell then "Supercell" else state.phase
end

local Storm = {}

Storm.current = nil :: Types.StormState?
Storm.Changed = Signal.new() :: Signal.Signal<Types.StormState>

local rainEmitter: ParticleEmitter

-- Seconds left in the current phase, synced to the server clock.
function Storm.secondsLeft(): number
	local state = Storm.current
	if not state then
		return 0
	end
	return math.max(0, state.endsAt - workspace:GetServerTimeNow())
end

local function tweenIfExists(target: Instance?, goals: { [string]: any })
	if target then
		TweenService:Create(target, SKY_TWEEN, goals):Play()
	end
end

-- The colour grade with no effect, for scaling it down.
local NEUTRAL_GRADE: { [string]: any } =
	{ Saturation = 0, Contrast = 0, TintColor = Color3.new(1, 1, 1) }

-- The look's colour grade at `amount` of its strength.
local function scaledGrade(grade: { [string]: any }, amount: number): { [string]: any }
	local out = {}
	for key, value in grade do
		local neutral = NEUTRAL_GRADE[key]
		if typeof(value) == "number" and typeof(neutral) == "number" then
			out[key] = neutral + (value - neutral) * amount
		elseif typeof(value) == "Color3" and typeof(neutral) == "Color3" then
			out[key] = neutral:Lerp(value, amount)
		else
			out[key] = value
		end
	end
	return out
end

local function applyLook(name: string)
	local look = LOOKS[name]
	tweenIfExists(Lighting, look.lighting)
	tweenIfExists(Lighting:FindFirstChildOfClass("Atmosphere"), look.atmosphere)
	tweenIfExists(workspace.Terrain:FindFirstChildOfClass("Clouds"), look.clouds)
	tweenIfExists(
		Lighting:FindFirstChild("StormGrade"),
		scaledGrade(look.grade, SettingsStore.get("bloomAmount"))
	)
	rainEmitter.Rate = look.rainRate * SettingsStore.get("particleAmount")
end

-- A big invisible slab that follows the camera and rains streaks downward.
local function makeRain(): ParticleEmitter
	local slab = Instance.new("Part")
	slab.Name = "RainCloud"
	slab.Anchored = true
	slab.CanCollide = false
	slab.CanQuery = false
	slab.CanTouch = false
	slab.Transparency = 1
	slab.Size = Vector3.new(140, 1, 140)
	slab.Parent = workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Rain"
	emitter.Rate = 0
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.Speed = NumberRange.new(90, 110)
	emitter.Lifetime = NumberRange.new(0.6, 0.8)
	emitter.Size = NumberSequence.new(0.12)
	emitter.Squash = NumberSequence.new(3) -- stretch into streaks
	emitter.Orientation = Enum.ParticleOrientation.FacingCameraWorldUp
	emitter.Color = ColorSequence.new(Color3.fromRGB(190, 210, 240))
	emitter.Transparency = NumberSequence.new(0.45)
	emitter.LightEmission = 0.2
	-- the streaks move with the slab, so running fast (boots) never leaves
	-- the ground ahead of you dry while new rain catches up
	emitter.LockedToPart = true
	emitter.Parent = slab

	RunService.RenderStepped:Connect(function()
		local camera = workspace.CurrentCamera
		if camera then
			slab.Position = camera.CFrame.Position + Vector3.new(0, RAIN_HEIGHT, 0)
		end
	end)
	return emitter
end

function Storm.init()
	captureLooks()
	rainEmitter = makeRain()
	Net.get("StormState").OnClientEvent:Connect(function(state: Types.StormState)
		local previous = Storm.current
		local changedLook = previous == nil or lookOf(previous) ~= lookOf(state)
		Storm.current = state
		if changedLook then
			applyLook(lookOf(state))
		end
		Storm.Changed:Fire(state)
	end)
	-- the settings change the current look straight away
	SettingsStore.Changed:Connect(function(key: string)
		local state = Storm.current
		if state and (key == "particleAmount" or key == "bloomAmount") then
			applyLook(lookOf(state))
		end
	end)
end

return Storm
