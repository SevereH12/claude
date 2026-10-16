--!strict
-- Entry point for building the map. The Studio updater plugin and the Map
-- system both call MapBuilder.build(). It builds the world in the style set
-- by Config.WORLD_STYLE (or the style passed in); see src/server/World.
--
-- The plugin requires a CLONE of this module (parented to ServerStorage),
-- so everything here must be reached by absolute paths, never script.Parent.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MapBuilder = {}

function MapBuilder.build(styleName: string?): Folder
	local Config = require(ReplicatedStorage.Shared.Config)
	local name = styleName or Config.WORLD_STYLE
	if name == "Legacy" then
		return require(ServerScriptService.Server.Lib.LegacyMapBuilder).build()
	end
	local Builder = require(ServerScriptService.Server.World.Builder)
	return Builder.build(name)
end

return MapBuilder
