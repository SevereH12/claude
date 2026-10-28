--!strict
-- Gameplay tips: which ones a player has seen (the list and its rules:
-- Config.HINTS and Util/Hints; showing them: Controllers/Hints).
-- The client picks a tip and shows it, then says so on the HintSeen remote
-- with the tip's id; this saves the id in profile.hintsSeen, so it never
-- shows again (on any server or device). That's all the client can do:
-- mark a known tip as seen, rate-limited.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local HintRules = require(ReplicatedStorage.Shared.Util.Hints)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local PlayerData = require(script.Parent.PlayerData)
local Sync = require(script.Parent.Sync)

local Hints = {}

-- Lib/RateLimit, required in init (the harness can't load it: it hooks
-- PlayerRemoving when it loads)
local allow: (Player, string, number, number) -> boolean

-- marks one tip as seen (the remote's handler)
local function onSeen(player: Player, id: unknown)
	-- tips are at least a minute apart, so a few a minute is plenty
	if not allow(player, "HintSeen", 0.2, 3) then
		return
	end
	local def = HintRules.def(id)
	local profile = PlayerData.get(player)
	if not def or not profile or profile.hintsSeen[def.id] then
		return
	end
	profile.hintsSeen[def.id] = true
	Sync.markDirty(player)
end

function Hints.init()
	allow = require(ServerScriptService.Server.Lib.RateLimit).allow
	Net.get("HintSeen").OnServerEvent:Connect(onSeen)
	-- only known ids are kept (a tip taken out of the list is dropped)
	PlayerData.Loaded:Connect(function(_player: Player, profile: Types.Profile)
		profile.hintsSeen = HintRules.sanitize(profile.hintsSeen)
	end)
end

return Hints
