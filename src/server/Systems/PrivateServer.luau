--!strict
-- Private servers (turned on for the game page, see README.md "Private
-- servers"): the player who owns the private server gets the
-- PrivateServerOwner attribute, which shows a small [Owner] chat tag
-- (Controllers/VipChat). Nothing else changes in a private server.
--
-- game.PrivateServerOwnerId is 0 in public servers and in reserved
-- (AFK/teleport) servers, so the tag only shows in real private servers.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PassRules = require(ReplicatedStorage.Shared.Util.Passes)

local PrivateServer = {}

local function onPlayer(player: Player)
	local ownerId = game.PrivateServerOwnerId
	if ownerId ~= 0 and player.UserId == ownerId then
		player:SetAttribute(PassRules.SERVER_OWNER, true)
		print(`[PrivateServer] {player.Name} owns this private server`)
	end
end

function PrivateServer.init()
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

return PrivateServer
