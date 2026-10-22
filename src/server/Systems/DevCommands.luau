--!strict
-- TEMPORARY test tool: the client's TEST buttons (Controllers/DevCommands)
-- send DevCommand: "volts" sets that player's Volts, "premium" turns
-- Pretend Premium on or off, "pass" pretends to own a Game Pass. The repo
-- and client code are public, so this is the lock: it only obeys in Studio
-- play tests or, in a live server, the user who owns the place; Pretend
-- Premium and the pass toggles are Studio only. To remove it:
-- delete this file and Controllers/DevCommands.luau, and take "DevCommand"
-- out of Shared/Remotes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Util.Progression)
local Passes = require(script.Parent.Passes)
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

local function setVolts(player: Player, amount: unknown)
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

-- Lets a tester without Premium try the Premium zone. Progression also
-- ignores the attribute outside Studio.
local function setPretendPremium(player: Player, on: unknown)
	if not RunService:IsStudio() or typeof(on) ~= "boolean" then
		return
	end
	player:SetAttribute(Progression.PRETEND_PREMIUM, on)
	Sync.markDirty(player)
	print(`[DevCommands] {player.Name} Pretend Premium {if on then "on" else "off"}`)
end

-- "Pretend owns <pass>": Passes.setPretend ignores it outside Studio.
local function setPretendPass(player: Player, key: unknown, on: unknown)
	if not RunService:IsStudio() or typeof(key) ~= "string" or typeof(on) ~= "boolean" then
		return
	end
	Passes.setPretend(player, key, on)
	print(`[DevCommands] {player.Name} Pretend owns {key} {if on then "on" else "off"}`)
end

local function onCommand(player: Player, name: unknown, value: unknown, extra: unknown)
	if not RateLimit.allow(player, "DevCommand", 2, 4) or not isOwner(player) then
		return
	end
	if name == "volts" then
		setVolts(player, value)
	elseif name == "premium" then
		setPretendPremium(player, value)
	elseif name == "pass" then
		setPretendPass(player, value, extra)
	end
end

function DevCommands.init()
	Net.get("DevCommand").OnServerEvent:Connect(onCommand)
end

return DevCommands
