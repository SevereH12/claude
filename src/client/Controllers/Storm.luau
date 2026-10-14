--!strict
-- Tracks the storm phase from the server and darkens the sky during storms
-- (lighting changes here are local to this player only).

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Types = require(ReplicatedStorage.Shared.Types)

local SKY_TWEEN = TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

local LOOKS = {
	Storm = {
		lighting = { Brightness = 0.7, OutdoorAmbient = Color3.fromRGB(70, 75, 100) },
		atmosphere = { Density = 0.45, Color = Color3.fromRGB(100, 110, 140) },
	},
	Calm = {
		lighting = { Brightness = 2, OutdoorAmbient = Color3.fromRGB(110, 115, 135) },
		atmosphere = { Density = 0.3, Color = Color3.fromRGB(170, 180, 200) },
	},
}

local Storm = {}

Storm.current = nil :: Types.StormState?
Storm.Changed = Signal.new() :: Signal.Signal<Types.StormState>

-- Seconds left in the current phase, synced to the server clock.
function Storm.secondsLeft(): number
	local state = Storm.current
	if not state then
		return 0
	end
	return math.max(0, state.endsAt - workspace:GetServerTimeNow())
end

local function applyLook(phase: Types.StormPhase)
	local look = LOOKS[phase]
	TweenService:Create(Lighting, SKY_TWEEN, look.lighting):Play()
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		TweenService:Create(atmosphere, SKY_TWEEN, look.atmosphere):Play()
	end
end

function Storm.init()
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
