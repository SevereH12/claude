--!strict
-- Tracks the storm phase from the server and sets the mood: during a storm
-- the sky darkens, clouds roll in and it rains. All of this is local to
-- this player's screen.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Shared.Net)
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

local LOOKS: { [Types.StormPhase]: Look } = {
	Storm = {
		lighting = {
			Brightness = 0.9,
			OutdoorAmbient = Color3.fromRGB(70, 78, 105),
			ClockTime = 17.4,
		},
		atmosphere = { Density = 0.45, Color = Color3.fromRGB(95, 105, 135), Haze = 2.5 },
		clouds = { Cover = 0.92, Density = 0.85, Color = Color3.fromRGB(75, 80, 98) },
		grade = { Saturation = -0.15, Contrast = 0.18, TintColor = Color3.fromRGB(205, 220, 255) },
		rainRate = 450,
	},
	Calm = {
		lighting = {
			Brightness = 2.2,
			OutdoorAmbient = Color3.fromRGB(125, 130, 150),
			ClockTime = 16.5,
		},
		atmosphere = { Density = 0.32, Color = Color3.fromRGB(195, 202, 218), Haze = 1.6 },
		clouds = { Cover = 0.62, Density = 0.55, Color = Color3.fromRGB(215, 218, 230) },
		grade = { Saturation = 0.1, Contrast = 0.1, TintColor = Color3.fromRGB(240, 244, 255) },
		rainRate = 0,
	},
}

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

local function applyLook(phase: Types.StormPhase)
	local look = LOOKS[phase]
	tweenIfExists(Lighting, look.lighting)
	tweenIfExists(Lighting:FindFirstChildOfClass("Atmosphere"), look.atmosphere)
	tweenIfExists(workspace.Terrain:FindFirstChildOfClass("Clouds"), look.clouds)
	tweenIfExists(Lighting:FindFirstChild("StormGrade"), look.grade)
	rainEmitter.Rate = look.rainRate
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
	rainEmitter = makeRain()
	Net.get("StormState").OnClientEvent:Connect(function(state: Types.StormState)
		local previous = Storm.current
		local changedPhase = previous == nil or previous.phase ~= state.phase
		Storm.current = state
		if changedPhase then
			applyLook(state.phase)
		end
		Storm.Changed:Fire(state)
	end)
end

return Storm
