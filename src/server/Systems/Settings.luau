--!strict
-- The SETTINGS panel's sound volumes, saved in the profile. The client sends
-- the whole set; every value is checked and clamped here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Net = require(ReplicatedStorage.Shared.Net)
local PlayerData = require(script.Parent.PlayerData)
local Sync = require(script.Parent.Sync)
local RateLimit = require(ServerScriptService.Server.Lib.RateLimit)

local Settings = {}

-- A volume from the client: a real number, clamped to 0..1 (nil if not one).
local function volume(value: unknown): number?
	if typeof(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return math.clamp(value, 0, 1)
end

local function onSave(player: Player, sent: unknown)
	-- sliders send while dragging: a few a second is plenty
	if not RateLimit.allow(player, "SaveSettings", 4, 8) then
		return
	end
	if typeof(sent) ~= "table" then
		return
	end
	local values = sent :: { [any]: any }
	local music, sfx, ambience =
		volume(values.musicVolume), volume(values.sfxVolume), volume(values.ambienceVolume)
	if music == nil or sfx == nil or ambience == nil or typeof(values.muted) ~= "boolean" then
		return
	end
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	profile.settings = {
		musicVolume = music,
		sfxVolume = sfx,
		ambienceVolume = ambience,
		muted = values.muted,
	}
	Sync.markDirty(player)
end

function Settings.init()
	Net.get("SaveSettings").OnServerEvent:Connect(onSave)
end

return Settings
