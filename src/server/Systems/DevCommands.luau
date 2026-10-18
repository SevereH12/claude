--!strict
-- Test commands for the game's owner, typed in chat. Roblox never shows a
-- chat command's message to anyone, and this one is hidden from the "/"
-- autocomplete list. The repo is public, so the name isn't the lock: the
-- command only works in Studio play tests or, in a live server, for the
-- user who owns the place.
--
--   /v2eon6gx4y        set your Volts to 1 trillion (as good as infinite)
--   /v2eon6gx4y <n>    set your Volts to n (/v2eon6gx4y 0 resets them)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local PlayerData = require(script.Parent.PlayerData)
local Sync = require(script.Parent.Sync)

local VOLTS_COMMAND = "/v2eon6gx4y"
local INFINITE_VOLTS = 1e12

local DevCommands = {}

local function isOwner(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	-- a group-owned place has a group id here, so only Studio works there
	return game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId
end

local function setVolts(source: TextSource, text: string)
	local player = Players:GetPlayerByUserId(source.UserId)
	if not player or not isOwner(player) then
		return
	end
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	local amount = INFINITE_VOLTS
	local arg = string.match(text, "^%S+%s+(%S+)")
	if arg then
		local n = tonumber(arg)
		if not n or n ~= n or n < 0 or n > INFINITE_VOLTS then
			return
		end
		amount = math.floor(n)
	end
	profile.volts = amount
	Sync.markDirty(player)
	print(`[DevCommands] {player.Name} set Volts to {amount}`)
end

function DevCommands.init()
	if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
		warn("[DevCommands] chat commands need TextChatService (Chat > ChatVersion)")
		return
	end
	local command = Instance.new("TextChatCommand")
	command.Name = "DevVolts"
	command.PrimaryAlias = VOLTS_COMMAND
	command.AutocompleteVisible = false
	command.Triggered:Connect(setVolts)
	command.Parent = TextChatService
end

return DevCommands
