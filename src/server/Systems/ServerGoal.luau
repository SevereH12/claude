--!strict
-- The server goal: one meter for the whole server (Config.SERVER_GOAL, the
-- maths in Util/Weather; tools/harness/test_weather.luau tests it).
--
-- Every Volt sold here fills it: Selling.payOut calls ServerGoal.add, so
-- sales at a station and Remote Sell count; the AFK Lounge doesn't (it
-- never goes through payOut).
--
-- Its size is every present player's grinding rate (Util/Afk, with their
-- own passes, boosts, group bonus and any event, but not a Server Storm or
-- Surge, which come and go) added up, times SERVER_GOAL.minutes. It's
-- worked out again when someone joins (once their data loads) or leaves,
-- and never drops below what's filled plus 10%, so it can't get stuck.
--
-- Filling it starts a Server Surge (Systems/Boosts.startSurge): 2x Volts
-- for everyone for 10 minutes. Then the meter empties, the round's
-- contributions are cleared, and the next goal is 1.5x bigger. Every hour
-- (counted from the server's start) the size goes back to normal.
--
-- Everyone reads it from workspace attributes (Util/Weather.GOAL_FILLED,
-- GOAL_SIZE and GOAL_TOP: the round's top 3 contributors), and the HUD
-- draws the meter. Nothing here is saved: it belongs to this server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local AfkRules = require(ReplicatedStorage.Shared.Util.Afk)
local PassRules = require(ReplicatedStorage.Shared.Util.Passes)
local Weather = require(ReplicatedStorage.Shared.Util.Weather)
local Boosts = require(script.Parent.Boosts)
local Passes = require(script.Parent.Passes)
local PlayerData = require(script.Parent.PlayerData)

local GOAL = Config.SERVER_GOAL
local CHECK_INTERVAL = 30 -- seconds between checks of the hourly reset

local ServerGoal = {}

local filled = 0 -- Volts in the meter this round
local size = GOAL.minGoal
local round = 0 -- goals reached this hour
local hourStart = os.clock()
local contributed: { [string]: number } = {} -- Volts this round, by display name

-- A player's grinding rate (Volts a second in their best zone), without
-- the server-wide timers.
local function rateOf(player: Player): number?
	local profile = PlayerData.get(player)
	if not profile then
		return nil
	end
	local effects = table.clone(Passes.saleEffects(player))
	effects[PassRules.SERVER_STORM] = nil
	effects[PassRules.SERVER_SURGE] = nil
	local _, breakdown = AfkRules.rate(
		{ bottleTier = profile.bottleTier, bootTier = profile.bootTier },
		effects,
		false
	)
	return breakdown.grindPerSecond
end

-- Tells everyone where the meter is.
local function publish()
	workspace:SetAttribute(Weather.GOAL_FILLED, math.floor(filled))
	workspace:SetAttribute(Weather.GOAL_SIZE, size)
	workspace:SetAttribute(
		Weather.GOAL_TOP,
		Weather.encodeTop(Weather.topContributors(contributed, GOAL.topCount))
	)
end

-- Works the goal's size out again from who's here now.
function ServerGoal.recompute(leaving: Player?)
	local rates: { number } = {}
	for _, player in Players:GetPlayers() do
		if player ~= leaving then
			local rate = rateOf(player)
			if rate then
				table.insert(rates, rate)
			end
		end
	end
	round, hourStart = Weather.goalRound(round, hourStart, os.clock())
	size = Weather.goalSize(rates, round, filled)
	publish()
end

-- The meter is full: a Surge, and the next (bigger) goal.
local function complete()
	local top = Weather.topContributors(contributed, 1)[1]
	Boosts.startSurge(if top then top.name else "")
	round, hourStart = Weather.goalRound(round, hourStart, os.clock())
	round += 1
	filled = 0
	table.clear(contributed)
	ServerGoal.recompute()
end

-- `volts` were just sold by `player` (Selling.payOut).
function ServerGoal.add(player: Player, volts: number)
	if volts ~= volts or volts <= 0 then
		return
	end
	filled += volts
	contributed[player.DisplayName] = (contributed[player.DisplayName] or 0) + volts
	if filled >= size then
		complete()
	else
		publish()
	end
end

-- Studio TEST tool: adds a share of the goal as if `player` sold it.
function ServerGoal.testFill(player: Player, share: number)
	ServerGoal.add(player, math.max(math.ceil(size * share), 1))
end

function ServerGoal.init()
	PlayerData.Loaded:Connect(function()
		ServerGoal.recompute()
	end)
	Players.PlayerRemoving:Connect(function(player)
		ServerGoal.recompute(player)
	end)
end

function ServerGoal.start()
	ServerGoal.recompute()
	while true do
		task.wait(CHECK_INTERVAL)
		local newRound = Weather.goalRound(round, hourStart, os.clock())
		if newRound ~= round then
			ServerGoal.recompute()
		end
	end
end

return ServerGoal
