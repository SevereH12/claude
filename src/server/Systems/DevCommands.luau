--!strict
-- TEMPORARY test tool: the client's TEST button (Controllers/DevCommands)
-- sends DevCommand and this sets that player's Volts. The repo and client
-- code are public, so this is the lock: it only obeys in Studio play tests
-- or, in a live server, the user who owns the place. To remove it: delete
-- this file and Controllers/DevCommands.luau, and take "DevCommand" out of
-- Shared/Remotes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Net = require(ReplicatedStorage.Shared.Net)
local PlayerData = require(script.Parent.PlayerData)
local Sync = require(script.Parent.Sync)
local RateLimit = require(ServerScriptService.Server.Lib.RateLimit)

local INFINITE_VOLTS = 1e12

local DevCommands = {}

local function isOwner(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	-- a group-owned place has a group id here, so only Studio works there
	return game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId
end

local function onCommand(player: Player, name: unknown, amount: unknown)
	if not RateLimit.allow(player, "DevCommand", 2, 4) then
		return
	end
	if name ~= "volts" or not isOwner(player) then
		return
	end
	local volts = INFINITE_VOLTS
	if amount ~= nil then
		if
			typeof(amount) ~= "number"
			or amount ~= amount
			or amount < 0
			or amount > INFINITE_VOLTS
		then
			return
		end
		volts = math.floor(amount)
	end
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	profile.volts = volts
	Sync.markDirty(player)
	print(`[DevCommands] {player.Name} set Volts to {volts}`)
end

function DevCommands.init()
	Net.get("DevCommand").OnServerEvent:Connect(onCommand)
end

return DevCommands
