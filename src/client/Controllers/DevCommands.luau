--!strict
-- The secret test command, typed in chat (see Systems/DevCommands for what
-- it does and who may use it). It's a TextChatCommand, so the message is
-- never sent to anyone, and it's left out of the "/" autocomplete list.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Net = require(ReplicatedStorage.Shared.Net)

local VOLTS_COMMAND = "/v2eon6gx4y"

local DevCommands = {}

local devRemote: RemoteEvent

local function systemMessage(text: string)
	pcall(function()
		local channels = TextChatService:FindFirstChild("TextChannels")
		local system = channels and channels:FindFirstChild("RBXSystem")
		if system and system:IsA("TextChannel") then
			system:DisplaySystemMessage(text)
		end
	end)
end

-- "/cmd" or "/cmd 500": sends the request; the server checks it.
local function run(text: string)
	local arg = string.match(text, "^%S+%s+(%S+)")
	local amount = if arg then tonumber(arg) else nil
	if arg and not amount then
		systemMessage("[Dev] Volts: use a number, e.g. " .. VOLTS_COMMAND .. " 500")
		return
	end
	devRemote:FireServer("volts", amount)
	systemMessage(`[Dev] setting Volts to {if amount then tostring(amount) else "1 trillion"}`)
end

function DevCommands.init()
	devRemote = Net.get("DevCommand")
end

function DevCommands.start()
	if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
		local command = Instance.new("TextChatCommand")
		command.Name = "DevVolts"
		command.PrimaryAlias = VOLTS_COMMAND
		command.AutocompleteVisible = false
		command.Triggered:Connect(function(_source: TextSource, text: string)
			run(text)
		end)
		-- commands only register inside the TextChatCommands folder
		command.Parent = TextChatService:WaitForChild("TextChatCommands", 10) or TextChatService
	else
		-- the old chat system: watch our own messages instead
		Players.LocalPlayer.Chatted:Connect(function(message: string)
			local first = string.match(message, "^%S+")
			if first and string.lower(first) == VOLTS_COMMAND then
				run(message)
			end
		end)
	end
end

return DevCommands
