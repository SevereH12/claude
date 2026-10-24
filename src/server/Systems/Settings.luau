--!strict
-- The SETTINGS panel's values, saved in the profile so they follow the
-- player to every device. The client sends the whole table (SaveSettings);
-- only Util/Settings.sanitize's clean copy is stored. The saved table goes
-- to the client once when they join (the Settings remote), not in every
-- snapshot.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Net = require(ReplicatedStorage.Shared.Net)
local SettingsRules = require(ReplicatedStorage.Shared.Util.Settings)
local PlayerData = require(script.Parent.PlayerData)
local RateLimit = require(ServerScriptService.Server.Lib.RateLimit)

local MAX_KEYS = 200 -- a settings table with more entries than this is refused
local MAX_STRING = 32 -- and any string longer than this

local Settings = {}

local settingsRemote: RemoteEvent

-- Small enough to bother sanitizing: a table of at most MAX_KEYS short
-- string keys with plain values.
local function reasonable(sent: unknown): boolean
	if typeof(sent) ~= "table" then
		return false
	end
	local count = 0
	for key, value in sent :: { [any]: any } do
		count += 1
		if count > MAX_KEYS or typeof(key) ~= "string" or #key > MAX_STRING then
			return false
		end
		local kind = typeof(value)
		if kind == "string" then
			if #value > MAX_STRING then
				return false
			end
		elseif kind ~= "number" and kind ~= "boolean" then
			return false
		end
	end
	return true
end

local function onSave(player: Player, sent: unknown)
	-- the client waits a second after the last change, so this is plenty
	if not RateLimit.allow(player, "SaveSettings", 1, 4) then
		return
	end
	if not reasonable(sent) then
		return
	end
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	profile.settings = SettingsRules.sanitize(sent)
end

function Settings.init()
	settingsRemote = Net.get("Settings")
	Net.get("SaveSettings").OnServerEvent:Connect(onSave)
	PlayerData.Loaded:Connect(function(player, profile)
		profile.settings = SettingsRules.sanitize(profile.settings)
		settingsRemote:FireClient(player, profile.settings)
	end)
end

return Settings
