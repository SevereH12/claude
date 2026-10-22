--!strict
-- Chat tags before the name on every message: a gold [VIP] for VIP pass
-- owners, then a [Member] in the group colour for members of the game's
-- group. Added on each client (TextChatService.OnIncomingMessage) from the
-- sender's Pass_VIP and GroupMember attributes (Systems/Passes,
-- Systems/Group). This is the only code that sets OnIncomingMessage: a
-- client can only have one.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Config = require(ReplicatedStorage.Shared.Config)
local PassRules = require(ReplicatedStorage.Shared.Util.Passes)

local VIP_TAG = `<font color="#{Config.VIP_GOLD:ToHex()}">[VIP]</font> `
local MEMBER_TAG = `<font color="#{Config.GROUP_COLOR:ToHex()}">[Member]</font> `

local VipChat = {}

function VipChat.init()
	TextChatService.OnIncomingMessage = function(message: TextChatMessage)
		local properties = Instance.new("TextChatMessageProperties")
		local source = message.TextSource
		local sender = if source then Players:GetPlayerByUserId(source.UserId) else nil
		if not sender then
			return properties
		end
		local tags = ""
		if sender:GetAttribute(PassRules.ATTRIBUTE .. "VIP") == true then
			tags ..= VIP_TAG
		end
		if sender:GetAttribute(PassRules.GROUP) == true then
			tags ..= MEMBER_TAG
		end
		if tags ~= "" then
			properties.PrefixText = tags .. message.PrefixText
		end
		return properties
	end
end

return VipChat
