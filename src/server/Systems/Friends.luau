--!strict
-- The friends boost: +5% Volts on every sale for each Roblox friend in your
-- server, up to 3 (+15%) (Config.FRIENDS; the maths is Util/Social and
-- Util/Passes, applied by Systems/Passes.payout).
--
-- Checked on the server only, with Player:IsFriendsWith (in a pcall): when
-- someone joins, they're checked against everyone already here, once per
-- pair, and the answer is kept until one of them leaves. Each player's
-- count is Sync.friends[player] (sent in the snapshot for the HUD chip and
-- counted by every sale and the AFK Lounge).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SocialRules = require(ReplicatedStorage.Shared.Util.Social)
local Sync = require(script.Parent.Sync)

local Friends = {}

-- friendsOf[a][b] = true when a and b are friends (both directions are kept)
local friendsOf: { [Player]: { [Player]: boolean } } = {}

-- Works out the player's count again and sends it if it changed.
local function recount(player: Player)
	local set = friendsOf[player]
	if not set or not player.Parent then
		return
	end
	local present = 0
	for other in set do
		if other.Parent then
			present += 1
		end
	end
	local counted = SocialRules.countedFriends(present)
	if Sync.friends[player] ~= counted then
		Sync.friends[player] = counted
		Sync.markDirty(player)
	end
end

-- Asks Roblox once whether these two are friends; nil if it couldn't tell.
local function areFriends(a: Player, b: Player): boolean?
	local ok, result = pcall(function()
		return a:IsFriendsWith(b.UserId)
	end)
	if ok then
		return result == true
	end
	warn(`[Friends] couldn't check {a.Name} and {b.Name}: {result}`)
	return nil
end

local function check(a: Player, b: Player)
	if areFriends(a, b) and friendsOf[a] and friendsOf[b] then
		friendsOf[a][b] = true
		friendsOf[b][a] = true
		recount(a)
		recount(b)
	end
end

local function onPlayerAdded(player: Player)
	if friendsOf[player] then
		return
	end
	friendsOf[player] = {}
	Sync.friends[player] = 0
	for _, other in Players:GetPlayers() do
		if other ~= player and friendsOf[other] then
			task.spawn(check, player, other)
		end
	end
end

local function onPlayerRemoving(player: Player)
	local set = friendsOf[player]
	friendsOf[player] = nil
	Sync.friends[player] = nil
	if not set then
		return
	end
	for other in set do
		local theirs = friendsOf[other]
		if theirs then
			theirs[player] = nil
			recount(other)
		end
	end
end

-- How many friends count for this player now (0 to Config.FRIENDS.max).
function Friends.count(player: Player): number
	return Sync.friends[player] or 0
end

function Friends.init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

function Friends.start()
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return Friends
