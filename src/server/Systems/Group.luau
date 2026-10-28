--!strict
-- Membership of the group that owns the game (Config.GROUP_ID): members get
-- Config.GROUP_BONUS more Volts on every sale (Util/Passes, applied by
-- Systems/Passes, so Remote Sell gets it too).
--
-- Checked on the server when a player joins (IsInGroupAsync, in a pcall).
-- When their client says they just joined from the REWARDS panel
-- (GroupJoined, handled by Systems/Rewards), it's checked again; Roblox
-- can keep answering from an old cache, so a "no" is tried again after 10s
-- and 30s, asking for the player's group list. Never the client's word alone.
--
-- Everyone can see it: the GroupMember player attribute (the [Member] chat
-- tag, the panel's group card).

local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PassRules = require(ReplicatedStorage.Shared.Util.Passes)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Sync = require(script.Parent.Sync)

local RETRIES = { 10, 30 } -- seconds before each re-check of a "no" after joining

local Group = {}

Group.ATTRIBUTE = PassRules.GROUP

-- Fires when a player becomes a member during their visit (they joined).
Group.Joined = Signal.new() :: Signal.Signal<Player>

local members: { [Player]: boolean } = {}
local checking: { [Player]: boolean } = {}

-- Does Roblox say they're in the group? nil if it couldn't tell.
local function inGroup(player: Player): boolean?
	local ok, result = pcall(function()
		return player:IsInGroupAsync(Config.GROUP_ID)
	end)
	if ok then
		return result == true
	end
	warn(`[Group] couldn't check {player.Name}: {result}`)
	return nil
end

-- The same question by the player's group list: a fresher answer after
-- they've just joined (IsInGroupAsync keeps its first one).
local function inGroupFresh(player: Player): boolean?
	local ok, groups = pcall(function()
		return GroupService:GetGroupsAsync(player.UserId)
	end)
	if not ok or typeof(groups) ~= "table" then
		return inGroup(player)
	end
	for _, info in groups do
		if typeof(info) == "table" and info.Id == Config.GROUP_ID then
			return true
		end
	end
	return false
end

-- Members get the attribute; the snapshot is
-- resent so sales and the panel catch up.
local function refresh(player: Player)
	if not player.Parent then
		return
	end
	local member = members[player] == true
	player:SetAttribute(Group.ATTRIBUTE, if member then true else nil)
	Sync.markDirty(player)
end

function Group.isMember(player: Player): boolean
	return members[player] == true
end

-- After the client says they joined: check again, and again after 10s and
-- 30s if Roblox still says no. Once at a time per player.
function Group.recheck(player: Player)
	if members[player] or checking[player] then
		return
	end
	checking[player] = true
	task.spawn(function()
		local waits = { 0 }
		table.move(RETRIES, 1, #RETRIES, 2, waits)
		for _, seconds in waits do
			if seconds > 0 then
				task.wait(seconds)
			end
			if not player.Parent then
				break
			end
			if inGroupFresh(player) then
				members[player] = true
				refresh(player)
				Group.Joined:Fire(player)
				print(`[Group] {player.Name} joined {Config.GROUP_NAME}: group bonus on`)
				break
			end
		end
		checking[player] = nil
	end)
end

local function onPlayerAdded(player: Player)
	if inGroup(player) then
		members[player] = true
		refresh(player)
	end
end

function Group.init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		members[player] = nil
		checking[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return Group
