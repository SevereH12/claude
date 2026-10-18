--!strict
-- SkyIsles: the Stormspire Isles. Floating islands chained to a central
-- storm temple above an endless sea of clouds, linked by glowing rune
-- bridges. Style guide: docs/styles/SkyIsles.md.
--
-- Modules:
--   Palette   colours, ground colours, sign looks
--   Ground    block-built ground (Map.Ground): polygons, islands, tapers,
--             hanging points, plus "how high is the ground here?" queries
--   Pieces    the style's building kit (shapes, crystals, bridges, landforms)
--   Sky       lighting, storm look, cloud sea, drifting rocks
--   Hub       the Stormspire: altar/sell station, spire, lanes, spawn
--   Zone      island, field, border, gate and bridge shared by all themes
--   Teaser    the "coming soon" island and blocked bridge
--   Themes/*  per-theme spec (materials, field pattern) and edge dressing
--
-- A new zone needs only a Config.ZONES entry; a new look needs one more
-- module in Themes/ (spec + dress), registered in THEMES below.

local ServerScriptService = game:GetService("ServerScriptService")

local WorldTypes = require(ServerScriptService.Server.World.Types)
local Ground = require(script.Ground)
local Hub = require(script.Hub)
local Palette = require(script.Palette)
local Pieces = require(script.Pieces)
local Sky = require(script.Sky)
local SkyTypes = require(script.SkyTypes)
local Teaser = require(script.Teaser)
local Zone = require(script.Zone)

type Context = WorldTypes.Context
type ZoneContext = WorldTypes.ZoneContext
type Theme = SkyTypes.Theme

local THEMES: { [string]: Theme } = {
	Beach = require(script.Themes.Beach),
	Canyon = require(script.Themes.Canyon),
	Default = require(script.Themes.Default),
}

local function themeOf(zone: ZoneContext): Theme
	local def = zone.def
	return (def and THEMES[def.theme]) or THEMES.Default
end

local Style = {}

Style.name = "SkyIsles"
Style.description =
	"Sky archipelago: floating islands chained to the Stormspire above a sea of clouds, linked by rune bridges."
Style.palette = (Palette.C :: any) :: { [string]: Color3 }
-- every walkable surface is part-built in Map.Ground; no terrain is filled
Style.ground = "Blocks"
-- Slots land on the eight compass directions (135 degree steps), each a
-- little further out than the last; seven zones plus the teaser fit.
Style.layout = {
	hubFloor = 0,
	hubRadius = 56,
	firstRadius = 168,
	radiusStep = 28,
	firstAngle = 90,
	angleStep = 135,
	teaserWidth = 84,
	teaserDepth = 84,
	teaserFloorStep = 12,
}

function Style.atmosphere(ctx: Context)
	-- log every ground part so pieces can test "is this inside land?"
	Ground.install(ctx)
	Pieces.resetChecks(ctx)
	Sky.atmosphere(ctx)
end

function Style.buildBase(ctx: Context)
	Sky.base(ctx)
end

function Style.buildHub(ctx: Context)
	Hub.build(ctx)
end

-- What each zone's ground built, handed on to its theme. Lives here (the
-- one module the Builder holds) so every step of a build sees the same land.
local lands: { [ZoneContext]: SkyTypes.Land } = {}

function Style.buildZoneGround(ctx: Context, zone: ZoneContext)
	lands[zone] = Zone.ground(ctx, zone, themeOf(zone).spec(zone))
end

function Style.buildConnector(ctx: Context, zone: ZoneContext)
	Zone.connector(ctx, zone)
end

function Style.buildBorder(ctx: Context, zone: ZoneContext)
	Zone.border(ctx, zone)
end

function Style.buildGate(ctx: Context, zone: ZoneContext)
	Zone.gate(ctx, zone)
end

local themes: { [string]: (ctx: Context, zone: ZoneContext) -> () } = {}
for name, theme in THEMES do
	themes[name] = function(ctx: Context, zone: ZoneContext)
		local land = lands[zone] or Zone.newLand(ctx, zone)
		lands[zone] = nil
		theme.dress(ctx, zone, theme.spec(zone), land)
	end
end
Style.themes = themes

function Style.buildTeaser(ctx: Context, zone: ZoneContext)
	Teaser.build(ctx, zone)
	Pieces.flushWaterfalls(ctx)
	Pieces.checkChains(ctx)
end

return Style
