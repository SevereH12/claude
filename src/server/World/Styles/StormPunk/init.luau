--!strict
-- StormPunk: "Voltcliff Works", a lightning-harvesting factory island.
-- Copper and brass with teal patina, white ceramic insulators, Tesla pylons,
-- cables strung between towers, riveted catwalks and cyan electricity.
-- Style guide: docs/styles/StormPunk.md.
--
-- Modules:
--   Palette     colours, materials, sign styles (the style guide in code)
--   Geo         bearings, placement checks, per-zone seeded randomness
--   Land        terrain landmasses: organic outlines, strata cliffs, stacks
--   Pieces      shared building pieces (insulators, pylons, lamps, signs...)
--   Atmosphere  calm and storm lighting
--   Hub         ocean, hub island, islets, Grand Coil, Volt Exchange, wayfinding
--   Zone        connector, border, gate and floor patterns for any slot
--   Themes/*    one module per zone theme: Beach, Canyon, Default
--   Teaser      the "Coming Soon" slot
--
-- A new zone needs only a Config.ZONES entry. If its theme has no module
-- here it gets Themes/Default; to give it its own look, add
-- Themes/<Theme>.luau with ground/dress/bridge and list it in THEMES below.

local ServerScriptService = game:GetService("ServerScriptService")

local WorldTypes = require(ServerScriptService.Server.World.Types)
local Atmosphere = require(script.Atmosphere)
local Geo = require(script.Geo)
local Hub = require(script.Hub)
local Palette = require(script.Palette)
local Teaser = require(script.Teaser)
local Zone = require(script.Zone)

type Context = WorldTypes.Context
type ZoneContext = WorldTypes.ZoneContext

type Theme = {
	ground: (ctx: Context, zone: ZoneContext) -> (),
	dress: (ctx: Context, zone: ZoneContext) -> (),
	bridge: Zone.BridgeStyle,
}

local THEMES: { [string]: Theme } = {
	Beach = require(script.Themes.Beach) :: Theme,
	Canyon = require(script.Themes.Canyon) :: Theme,
	Default = require(script.Themes.Default) :: Theme,
}

local function themeFor(zone: ZoneContext): Theme
	local def = zone.def
	return (def and THEMES[def.theme]) or THEMES.Default
end

local Style = {}

Style.name = "StormPunk"
Style.description =
	"Voltcliff Works: copper, brass and patina factory islands strung with glowing cables."
Style.palette = Palette.colors
Style.layout = {
	hubFloor = 12,
	hubRadius = 52,
	firstRadius = 148,
	radiusStep = 54,
	firstAngle = 100,
	angleStep = 135,
	teaserWidth = 96,
	teaserDepth = 88,
	teaserFloorStep = 16,
}

function Style.atmosphere(ctx: Context)
	Geo.init(ctx)
	Atmosphere.apply(ctx)
end

function Style.buildBase(ctx: Context)
	Hub.buildBase(ctx)
end

function Style.buildHub(ctx: Context)
	Hub.buildHub(ctx)
end

function Style.buildZoneGround(ctx: Context, zone: ZoneContext)
	themeFor(zone).ground(ctx, zone)
end

function Style.buildConnector(ctx: Context, zone: ZoneContext)
	if zone.slot.index == 1 then
		-- every zone landmass is down now: re-lay the hub's upper terrain on top
		Hub.restoreIsland(ctx)
	end
	Zone.buildConnector(ctx, zone, themeFor(zone).bridge)
end

function Style.buildBorder(ctx: Context, zone: ZoneContext)
	Zone.buildBorder(ctx, zone)
end

function Style.buildGate(ctx: Context, zone: ZoneContext)
	Zone.buildGate(ctx, zone)
end

Style.themes = {} :: { [string]: (ctx: Context, zone: ZoneContext) -> () }
for themeName, theme in THEMES do
	Style.themes[themeName] = theme.dress
end

function Style.buildTeaser(ctx: Context, zone: ZoneContext)
	Teaser.build(ctx, zone)
end

return Style
