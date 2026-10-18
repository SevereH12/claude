--!strict
-- WeatherLab: Barometer Bay, a cozy seaside town of storm scientists (see
-- docs/styles/WeatherLab.md). A lighthouse harbour village is the hub;
-- each zone is a field station on its own island in a different biome,
-- reached by a winding plank boardwalk. Modules:
--   Palette     colours, ground block colours, sign styles
--   Geo         zone-local coordinates, prop spots, part budget, ground registry
--   Land        part-built ground: sea, islands, field plateaus, beaches
--   Pieces      building pieces (lamps, cottages, domes, balloons, plants...)
--   Atmosphere  calm and storm lighting
--   Hub         sea, hub island, lighthouse, sell station, spawn, village
--   Zone        generic zone plateau, boardwalk, border and gate
--   Themes/     Beach, Canyon, Default biome dressing
--   Teaser      the Coming Soon slot
--
-- Borrowed looks: a zone whose theme is "<Style>:<Theme>" (e.g.
-- "StormPunk:Default") gets that style pack's own island, border, gate and
-- theme dressing. WeatherLab still builds its boardwalk to the gate, and
-- the other pack's atmosphere, hub and teaser never run.

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
type Build = (ctx: Context, zone: ZoneContext) -> ()

-- Borrowed looks ---------------------------------------------------------------------

-- Per-zone palette tweaks, written into the borrowed pack's own Palette
-- tables while that zone builds and put back after. WeatherLab's ambient
-- is cooler and hazier than StormPunk's, so its cool greys go flat
-- blue-grey: warm them a touch. Beaches and grass caps take WeatherLab's
-- own colours, so the shores read as one bay.
local TWEAKS: { [string]: { [string]: { [string]: Color3 } } } = {
	Works = {
		ground = {
			sand = Palette.ground.beach,
			grass = Palette.ground.grass,
			concrete = Color3.fromRGB(168, 164, 154),
			slate = Color3.fromRGB(118, 118, 126),
		},
	},
}

-- The borrowed pack gets its own seeded Random (so it never shifts
-- WeatherLab's ctx.rng draws) on a view of the build context, kept on the
-- context; the pack's per-build state (seeds, land registries) is keyed
-- by that view.
local BORROW_SEED = 4417

type Borrowed = {
	pack: any, -- the other style pack (its StylePack table)
	palette: any, -- its Palette module
	theme: string, -- the theme name inside that pack
	front: number?, -- how far its island top reaches past the footprint
}

local borrowedByTheme: { [string]: Borrowed } = {}

local function borrowed(zone: ZoneContext): Borrowed?
	local def = zone.def
	if not def then
		return nil
	end
	local cached = borrowedByTheme[def.theme]
	if cached then
		return cached
	end
	local styleName, themeName = string.match(def.theme, "^(%w+):(%w+)$")
	if not styleName or not themeName then
		return nil
	end
	local module = script.Parent:FindFirstChild(styleName)
	assert(
		module and module:IsA("ModuleScript"),
		`[WeatherLab] zone {def.id} borrows style {styleName}, which doesn't exist`
	)
	local paletteModule = module:FindFirstChild("Palette")
	local zoneModule = module:FindFirstChild("Zone")
	local b: Borrowed = {
		pack = (require :: any)(module),
		palette = if paletteModule then (require :: any)(paletteModule) else {},
		theme = themeName,
		front = if zoneModule then (require :: any)(zoneModule).MARGIN else nil,
	}
	borrowedByTheme[def.theme] = b
	return b
end

local function viewOf(ctx: Context): Context
	local holder = ctx :: any
	if not holder.borrowView then
		holder.borrowView = setmetatable({ rng = Random.new(BORROW_SEED) }, { __index = ctx })
	end
	return holder.borrowView :: Context
end

-- Runs one of the borrowed pack's functions for `zone`, on the context
-- view, with the zone's palette tweaks applied and its def showing the
-- bare theme name (the pack looks its theme up by def.theme). The zone
-- itself is passed as is: packs compare zones by identity.
local function run(ctx: Context, zone: ZoneContext, b: Borrowed, build: Build)
	local def = zone.def :: any
	local saved: { { any } } = {}
	for group, colors in TWEAKS[def.id] or {} do
		local target = b.palette[group]
		if target then
			for name, color in colors do
				table.insert(saved, { target, name, target[name] })
				target[name] = color
			end
		end
	end
	local view = table.clone(def)
	view.theme = b.theme
	zone.def = view
	local ok, err = xpcall(build, debug.traceback, viewOf(ctx), zone)
	zone.def = def
	for i = #saved, 1, -1 do
		local entry = saved[i]
		entry[1][entry[2]] = entry[3]
	end
	if not ok then
		error(err, 0)
	end
end

local function buildZoneGround(ctx: Context, zone: ZoneContext)
	local b = borrowed(zone)
	if b then
		run(ctx, zone, b, b.pack.buildZoneGround)
	else
		Zone.ground(ctx, zone)
	end
end

local function buildConnector(ctx: Context, zone: ZoneContext)
	local b = borrowed(zone)
	Zone.connector(ctx, zone, if b then b.front else nil)
end

local function buildBorder(ctx: Context, zone: ZoneContext)
	local b = borrowed(zone)
	if b then
		run(ctx, zone, b, b.pack.buildBorder)
	else
		Zone.border(ctx, zone)
	end
end

local function buildGate(ctx: Context, zone: ZoneContext)
	local b = borrowed(zone)
	if b then
		run(ctx, zone, b, function(view: Context, z: ZoneContext)
			b.pack.buildGate(view, z) -- StormPunk's returns its cable points
		end)
	else
		Zone.gate(ctx, zone)
	end
end

local function dressBorrowed(ctx: Context, zone: ZoneContext)
	local b = borrowed(zone) :: Borrowed
	run(ctx, zone, b, b.pack.themes[b.theme] or b.pack.themes.Default)
end

-- Builder looks dressing up by the full theme name: any "<Style>:<Theme>"
-- name finds the borrowed pack's dressing.
local themes: { [string]: Build } = setmetatable({}, {
	__index = function(_, name: string): Build?
		return if string.find(name, ":", 1, true) then dressBorrowed else nil
	end,
}) :: any
for name, theme in Themes.list do
	themes[name] = theme.dress
end

local Style: WorldTypes.StylePack = {
	name = "WeatherLab",
	description = "Barometer Bay: a cozy seaside town of storm scientists. A lighthouse harbour hub "
		.. "and island field stations in different biomes, linked by winding boardwalks.",
	palette = Palette.colors,
	-- all ground is SmoothPlastic blocks in Map.Ground (World/Blocks)
	ground = "Blocks",
	-- A 135-degree spiral uses 8 directions before it repeats, and each
	-- full turn moves 3 slots (114 studs) further out, so later zones
	-- clear earlier ones and no boardwalk ever crosses an island.
	layout = {
		hubFloor = 8,
		hubRadius = 60,
		firstRadius = 178,
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
	buildZoneGround = buildZoneGround,
	buildConnector = buildConnector,
	buildBorder = buildBorder,
	buildGate = buildGate,
	themes = themes,
	buildTeaser = Teaser.build,
}

return Style
