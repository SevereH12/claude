--!strict
-- Timed boosts (Config.BOOSTS; the maths is Util/Boosts): rewards that switch
-- a Game Pass's effect on for a while. Each profile keeps seconds left per
-- boost (profile.boosts), and they only count down while the player is in
-- the game, so leaving never wastes one. Systems/Passes applies them
-- wherever it applies pass effects (selling, Remote Sell, capacity, luck);
-- the snapshot says when each runs out (Sync).
--
-- Also the Server Storm (Config.SERVER_STORM, bought through
-- Systems/Receipts): 2x Volts for everyone in this server, people who join
-- during it included. Each purchase adds 15 minutes, up to 60. It isn't
-- saved: it belongs to this server. Everyone can read it from workspace
-- attributes (Util/Boosts.STORM_ENDS and STORM_BY), and the Announcement
-- remote tells everyone when someone starts or adds to one.
--
-- The Server Surge is the same kind of timer with no buyer: filling the
-- server goal (Systems/ServerGoal) starts one, Config.SERVER_GOAL
-- .surgeMinutes of 2x Volts for everyone, stacking with a Server Storm.
-- Its end time is the workspace attribute Util/Boosts.SURGE_ENDS.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoostRules = require(ReplicatedStorage.Shared.Util.Boosts)
local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Types = require(ReplicatedStorage.Shared.Types)
local PlayerData = require(script.Parent.PlayerData)
local Sync = require(script.Parent.Sync)

local TICK = 1 -- seconds between countdown steps

local Boosts = {}

local announcement: RemoteEvent
local stormEnds: number? = nil -- os.clock() when the Server Storm ends
local surgeEnds: number? = nil -- os.clock() when the Server Surge ends

-- Fires when one of a player's boosts runs out.
Boosts.Ended = Signal.new() :: Signal.Signal<Player, string>

local NONE: BoostRules.Left = table.freeze({})

-- Seconds left per running boost (don't change it).
function Boosts.left(player: Player): BoostRules.Left
	local profile = PlayerData.get(player)
	return if profile then profile.boosts else NONE
end

-- Adds `seconds` to a boost (reward time stacks up to Config.BOOST_CAP;
-- `paid` time adds in full).
function Boosts.grant(player: Player, key: string, seconds: number, paid: boolean?)
	local profile = PlayerData.get(player)
	if not profile or not BoostRules.def(key) then
		return
	end
	BoostRules.grant(profile.boosts, key, seconds, paid)
	Sync.markDirty(player)
end

-- A boost bought for yourself (FOR ME): its time adds in full.
function Boosts.grantProduct(player: Player, product: Types.BoostProductDef)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	BoostRules.grantProduct(profile.boosts, product)
	Sync.markDirty(player)
end

-- Is a Server Storm on in this server?
function Boosts.stormOn(): boolean
	return stormEnds ~= nil and os.clock() < stormEnds
end

-- Starts a Server Storm for `buyer`, or adds to the one on (up to its
-- cap), and tells everyone. Returns its seconds left.
function Boosts.startStorm(buyer: Player): number
	local now = os.clock()
	local started = not Boosts.stormOn()
	local left = BoostRules.stormAdd(if stormEnds and not started then stormEnds - now else 0)
	stormEnds = now + left
	workspace:SetAttribute(BoostRules.STORM_ENDS, workspace:GetServerTimeNow() + left)
	workspace:SetAttribute(BoostRules.STORM_BY, buyer.DisplayName)
	announcement:FireAllClients("storm", buyer.DisplayName, left, started)
	print(
		`[Boosts] {buyer.Name} {if started then "started" else "added to"} a Server Storm: {math.round(
			left / 60
		)} min left`
	)
	return left
end

-- Ends the Server Storm now (when its timer runs out).
function Boosts.endStorm()
	stormEnds = nil
	workspace:SetAttribute(BoostRules.STORM_ENDS, nil)
	workspace:SetAttribute(BoostRules.STORM_BY, nil)
end

-- Is a Server Surge on in this server?
function Boosts.surgeOn(): boolean
	return surgeEnds ~= nil and os.clock() < surgeEnds
end

-- Starts a Server Surge (the server goal was filled), or adds
-- SERVER_GOAL.surgeMinutes to the one on, and tells everyone (`top`: the
-- round's biggest contributor, or ""). Returns its seconds left.
function Boosts.startSurge(top: string): number
	local now = os.clock()
	local left = (if surgeEnds and Boosts.surgeOn() then surgeEnds - now else 0)
		+ Config.SERVER_GOAL.surgeMinutes * 60
	surgeEnds = now + left
	workspace:SetAttribute(BoostRules.SURGE_ENDS, workspace:GetServerTimeNow() + left)
	announcement:FireAllClients("surge", top, left)
	print(`[Boosts] the server goal was reached: a Server Surge, {math.round(left / 60)} min left`)
	return left
end

-- Ends the Server Surge now (when its timer runs out).
function Boosts.endSurge()
	surgeEnds = nil
	workspace:SetAttribute(BoostRules.SURGE_ENDS, nil)
end

function Boosts.init()
	announcement = Net.get("Announcement")
end

function Boosts.start()
	local last = os.clock()
	while true do
		task.wait(TICK)
		local now = os.clock()
		local dt = now - last
		last = now
		if stormEnds and now >= stormEnds then
			Boosts.endStorm()
		end
		if surgeEnds and now >= surgeEnds then
			Boosts.endSurge()
		end
		for _, player in Players:GetPlayers() do
			local profile = PlayerData.get(player)
			if profile and next(profile.boosts) then
				local ended = BoostRules.tick(profile.boosts, dt)
				if #ended > 0 then
					Sync.markDirty(player)
					for _, key in ended do
						Boosts.Ended:Fire(player, key)
					end
				end
			end
		end
	end
end

return Boosts
