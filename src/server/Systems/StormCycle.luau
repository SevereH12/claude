--!strict
-- Runs the storm/calm loop and tells every client the current phase and
-- when it ends.
--
-- About every hour (Config.SUPERCELL, Util/Weather) a Supercell takes over:
-- 30 s before it, the state carries `supercellAt` (clients show a
-- countdown); then a storm with `supercell = true` runs for its 3 minutes
-- (Systems/Strikes doubles the strikes and the golden chance), then the
-- normal loop carries on with a calm.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local StatRules = require(ReplicatedStorage.Shared.Util.Stats)
local Types = require(ReplicatedStorage.Shared.Types)
local Weather = require(ReplicatedStorage.Shared.Util.Weather)
local Stats = require(script.Parent.Stats)

local SEEN_CHECK = 10 -- seconds between "who's here for the Supercell" checks

local StormCycle = {}

local state: Types.StormState = { phase = "Calm", endsAt = 0 }
local random = Random.new()
local supercellAt = math.huge -- server time the next Supercell starts
local remote: RemoteEvent

function StormCycle.isStorming(): boolean
	return state.phase == "Storm"
end

-- Is the storm on now a Supercell?
function StormCycle.isSupercell(): boolean
	return state.phase == "Storm" and state.supercell == true
end

local function now(): number
	return workspace:GetServerTimeNow()
end

-- `supercellAt` goes out only during the warning countdown.
local function warningAt(): number?
	return if Weather.supercellStage(now(), supercellAt) == "warning" then supercellAt else nil
end

local function setPhase(phase: Types.StormPhase, duration: number, supercell: boolean?)
	state = {
		phase = phase,
		endsAt = now() + duration,
		supercell = supercell,
		supercellAt = if supercell then nil else warningAt(),
	}
	remote:FireAllClients(state)
	print(`[StormCycle] {if supercell then "Supercell" else phase} for {duration}s`)
end

-- Waits out the phase. Returns true early if a Supercell is due; sends the
-- countdown once when its warning starts.
local function waitPhase(): boolean
	while now() < state.endsAt do
		local stage = Weather.supercellStage(now(), supercellAt)
		if stage == "on" or stage == "over" then
			return true
		end
		if stage == "warning" and state.supercellAt == nil then
			state = table.clone(state)
			state.supercellAt = supercellAt
			remote:FireAllClients(state)
		end
		task.wait(0.25)
	end
	return false
end

local function runSupercell()
	local duration = Config.SUPERCELL.minutes * 60
	setPhase("Storm", duration, true)
	-- everyone here (and anyone who joins) has seen it, for the Storm Log
	local endsAt = now() + duration
	repeat
		for _, player in Players:GetPlayers() do
			Stats.saw(player, StatRules.SUPERCELLS_SEEN)
		end
		task.wait(math.max(0, math.min(SEEN_CHECK, endsAt - now())))
	until now() >= endsAt
	supercellAt = Weather.nextSupercellAt(now(), random:NextNumber())
	setPhase("Calm", Config.CALM_DURATION)
	waitPhase()
end

-- TEST panel (Studio): the next Supercell starts in `seconds`.
function StormCycle.supercellIn(seconds: number)
	supercellAt = now() + seconds
end

function StormCycle.init()
	remote = Net.get("StormState")
	-- players joining mid-cycle get the current phase straight away
	Players.PlayerAdded:Connect(function(player)
		remote:FireClient(player, state)
	end)
end

function StormCycle.start()
	supercellAt = Weather.nextSupercellAt(now(), random:NextNumber())
	setPhase("Calm", Config.FIRST_STORM_DELAY)
	waitPhase()
	while true do
		if now() >= supercellAt then
			runSupercell()
			continue
		end
		setPhase("Storm", Config.STORM_DURATION)
		if waitPhase() then
			continue
		end
		setPhase("Calm", Config.CALM_DURATION)
		waitPhase()
	end
end

return StormCycle
