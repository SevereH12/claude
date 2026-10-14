--!strict
-- Runs the storm/calm loop and tells every client the current phase and
-- when it ends.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)

local StormCycle = {}

local state: Types.StormState = { phase = "Calm", endsAt = 0 }

function StormCycle.isStorming(): boolean
	return state.phase == "Storm"
end

local function setPhase(remote: RemoteEvent, phase: Types.StormPhase, duration: number)
	state = { phase = phase, endsAt = workspace:GetServerTimeNow() + duration }
	remote:FireAllClients(state)
	print(`[StormCycle] {phase} for {duration}s`)
end

function StormCycle.init()
	local remote = Net.get("StormState")
	-- players joining mid-cycle get the current phase straight away
	Players.PlayerAdded:Connect(function(player)
		remote:FireClient(player, state)
	end)
end

function StormCycle.start()
	local remote = Net.get("StormState")
	setPhase(remote, "Calm", Config.FIRST_STORM_DELAY)
	task.wait(Config.FIRST_STORM_DELAY)
	while true do
		setPhase(remote, "Storm", Config.STORM_DURATION)
		task.wait(Config.STORM_DURATION)
		setPhase(remote, "Calm", Config.CALM_DURATION)
		task.wait(Config.CALM_DURATION)
	end
end

return StormCycle
