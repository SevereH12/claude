--!strict
-- WeatherLab: Barometer Bay, a cozy seaside town of storm scientists (see
-- docs/styles/WeatherLab.md). A lighthouse harbour village is the hub;
-- each zone is a field station on its own island in a different biome,
-- reached by a winding plank boardwalk. Modules:
--   Palette     colours, terrain tints, sign styles
--   Geo         zone-local coordinates, contour-terrace islands, ground queries
--   Pieces      building pieces (lamps, cottages, domes, balloons, plants...)
--   Atmosphere  calm and storm lighting
--   Hub         sea, hub island, lighthouse, sell station, spawn, village
--   Zone        generic island ground, boardwalk, border and gate
--   Themes/     Beach, Canyon, Default biome dressing
--   Teaser      the Coming Soon slot

local ServerScriptService = game:GetService("ServerScriptService")

local WorldTypes = require(ServerScriptService.Server.World.Types)
local Atmosphere = require(script.Atmosphere)
local Hub = require(script.Hub)
local Palette = require(script.Palette)
local Teaser = require(script.Teaser)
local Themes = require(script.Themes)
local Zone = require(script.Zone)

type Context = WorldTypes.Context
type ZoneContext = WorldTypes.ZoneContext

local themes: { [string]: (Context, ZoneContext) -> () } = {}
for name, theme in Themes.list do
	themes[name] = theme.dress
end

local Style: WorldTypes.StylePack = {
	name = "WeatherLab",
	description = "Barometer Bay: a cozy seaside town of storm scientists. A lighthouse harbour hub "
		.. "and island field stations in different biomes, linked by winding boardwalks.",
	palette = Palette.colors,
	-- A 135-degree spiral uses 8 directions before it repeats, and each
	-- full turn moves 3 slots (114 studs) further out, so later zones
	-- clear earlier ones and no boardwalk ever crosses an island.
	layout = {
		hubFloor = 8,
		hubRadius = 60,
		firstRadius = 166,
		radiusStep = 38,
		firstAngle = 90,
		angleStep = 135,
		teaserWidth = 88,
		teaserDepth = 88,
		teaserFloorStep = 12,
	},
	atmosphere = Atmosphere.build,
	buildBase = Hub.buildBase,
	buildHub = Hub.buildHub,
	buildZoneGround = Zone.ground,
	buildConnector = Zone.connector,
	buildBorder = Zone.border,
	buildGate = Zone.gate,
	themes = themes,
	buildTeaser = Teaser.build,
}

return Style
