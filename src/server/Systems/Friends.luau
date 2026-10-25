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
--
-- Studio testing: the TEST panel's "Pretend friends" (Friends.cyclePretend)
-- adds 0 to 3 pretend friends, in Studio only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local SocialRules = require(ReplicatedStorage.Shared.Util.Social)
local Sync = require(script.Parent.Sync)

local Friends = {}

-- friendsOf[a][b] = true when a and b are friends (both directions are kept)
local friendsOf: { [Player]: { [Player]: boolean } } = {}
local pretend: { [Player]: number } = {}

-- Works out the player's count again and sends it if it changed.
local function recount(player: Player)
	local set = friendsOf[player]
	if not set or not player.Parent then
		return
	end
	local present = pretend[player] or 0
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
	pretend[player] = nil
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

-- Studio TEST button: 0, 1, 2, 3 pretend friends, then back to 0.
function Friends.cyclePretend(player: Player): number
	if not RunService:IsStudio() then
		return 0
	end
	local n = ((pretend[player] or 0) + 1) % (Config.FRIENDS.max + 1)
	pretend[player] = n
	recount(player)
	return n
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
