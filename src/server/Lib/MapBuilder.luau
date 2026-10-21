--!strict
-- Entry point for building the map. The Studio updater plugin and the Map
-- system both call MapBuilder.build(). It builds every world in
-- Config.WORLDS, each in its own style; see src/server/World. Passing a
-- style name builds only the first world's zones in that style, to review
-- a style (the tools in tools/ do this).
--
-- The plugin requires a CLONE of this module (parented to ServerStorage),
-- so everything here must be reached by absolute paths, never script.Parent.

local ServerScriptService = game:GetService("ServerScriptService")

local MapBuilder = {}

function MapBuilder.build(previewStyle: string?): Folder
	local Builder = require(ServerScriptService.Server.World.Builder)
	return Builder.build(previewStyle)
end

return MapBuilder
