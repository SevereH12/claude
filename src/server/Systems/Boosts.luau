--!strict
-- Timed boosts (Config.BOOSTS; the maths is Util/Boosts): rewards that switch
-- a Game Pass's effect on for a while. Each profile keeps seconds left per
-- boost (profile.boosts), and they only count down while the player is in
-- the game, so leaving never wastes one. Systems/Passes applies them
-- wherever it applies pass effects (selling, Remote Sell, capacity, luck);
-- the snapshot says when each runs out (Sync).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoostRules = require(ReplicatedStorage.Shared.Util.Boosts)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local PlayerData = require(script.Parent.PlayerData)
local Sync = require(script.Parent.Sync)

local TICK = 1 -- seconds between countdown steps

local Boosts = {}

-- Fires when one of a player's boosts runs out.
Boosts.Ended = Signal.new() :: Signal.Signal<Player, string>

local NONE: BoostRules.Left = table.freeze({})

-- Seconds left per running boost (don't change it).
function Boosts.left(player: Player): BoostRules.Left
	local profile = PlayerData.get(player)
	return if profile then profile.boosts else NONE
end

-- Adds `seconds` to a boost (time stacks, up to Config.BOOST_CAP).
function Boosts.grant(player: Player, key: string, seconds: number)
	local profile = PlayerData.get(player)
	if not profile or not BoostRules.def(key) then
		return
	end
	BoostRules.grant(profile.boosts, key, seconds)
	Sync.markDirty(player)
end

-- Studio TEST tool: ends every boost now.
function Boosts.clear(player: Player)
	local profile = PlayerData.get(player)
	if profile then
		table.clear(profile.boosts)
		Sync.markDirty(player)
	end
end

function Boosts.start()
	local last = os.clock()
	while true do
		task.wait(TICK)
		local now = os.clock()
		local dt = now - last
		last = now
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
