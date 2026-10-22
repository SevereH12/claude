--!strict
-- VIP chat tag: a gold [VIP] before the name on every chat message a VIP
-- pass owner sends. Added on each client (TextChatService.OnIncomingMessage)
-- from the sender's Pass_VIP attribute (Systems/Passes). This is the only
-- code that sets OnIncomingMessage: a client can only have one.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Config = require(ReplicatedStorage.Shared.Config)
local PassRules = require(ReplicatedStorage.Shared.Util.Passes)

local TAG = `<font color="#{Config.VIP_GOLD:ToHex()}">[VIP]</font> `

local VipChat = {}

function VipChat.init()
	TextChatService.OnIncomingMessage = function(message: TextChatMessage)
		local properties = Instance.new("TextChatMessageProperties")
		local source = message.TextSource
		local sender = if source then Players:GetPlayerByUserId(source.UserId) else nil
		if sender and sender:GetAttribute(PassRules.ATTRIBUTE .. "VIP") == true then
			properties.PrefixText = TAG .. message.PrefixText
		end
		return properties
	end
end

return VipChat
