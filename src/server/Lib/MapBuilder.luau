--!strict
-- Entry point for building the map. The Studio updater plugin and the Map
-- system both call MapBuilder.build(). It builds every world in
-- Config.WORLDS, each in its own style; see src/server/World. Passing a
-- style name builds only the first world's zones in that style, to review
-- a style (the tools in tools/ do this).
--
-- The plugin requires a CLONE of this module (parented to ServerStorage),
-- so everything here must be reached by absolute paths, never script.Parent.
--
-- It also turns on streaming (Workspace.StreamingEnabled, Config.STREAMING):
-- phones only load the map near the player, which saves a lot of memory.
-- What gameplay needs everywhere is in Persistent models (World/Builder).
-- Only Studio's edit mode may change it (the updater plugin can), so a map
-- built while the game runs (Systems/Map) leaves it as the place has it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local MapBuilder = {}

local function turnOnStreaming()
	if RunService:IsRunning() then
		return
	end
	local Config = require(ReplicatedStorage.Shared.Config)
	local settings = Config.STREAMING
	local ok, err = pcall(function()
		Workspace.StreamingEnabled = true
		Workspace.StreamingMinRadius = settings.minRadius
		Workspace.StreamingTargetRadius = settings.targetRadius
		-- drop far parts when memory is low, and wait (rather than fall)
		-- if the ground near you hasn't loaded yet
		Workspace.StreamOutBehavior = Enum.StreamOutBehavior.Opportunistic
		Workspace.StreamingIntegrityMode = Enum.StreamingIntegrityMode.MinimumRadiusPause
	end)
	if not ok then
		warn(
			`[MapBuilder] couldn't turn on streaming ({err}). In Studio: click Workspace in the Explorer, then tick StreamingEnabled in Properties.`
		)
	end
end

function MapBuilder.build(previewStyle: string?): Folder
	local Builder = require(ServerScriptService.Server.World.Builder)
	local map = Builder.build(previewStyle)
	turnOnStreaming()
	return map
end

return MapBuilder
