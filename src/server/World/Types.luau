--!strict
-- Types for the world builder. A world = a hub + one zone per Config.ZONES
-- entry + a "coming soon" teaser in the next free slot. The framework
-- (Builder, Layout) decides WHERE things go and guarantees the gameplay
-- contracts; a style pack (Styles/<Name>) decides what everything LOOKS like.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SharedTypes = require(ReplicatedStorage.Shared.Types)

-- Spiral placement. Zone i sits at angle firstAngle + (i-1)*angleStep
-- (degrees clockwise from north, -Z) and distance firstRadius +
-- (i-1)*radiusStep from the hub centre, facing the hub. Keep radiusStep
-- large enough that a full turn of the spiral clears the previous ring.
export type LayoutParams = {
	hubFloor: number, -- height of the hub's walkable ground
	hubRadius: number, -- distance from hub centre to where connectors start
	firstRadius: number, -- distance from hub centre to the first zone's centre
	radiusStep: number,
	firstAngle: number,
	angleStep: number,
	teaserWidth: number, -- footprint used for the "coming soon" slot
	teaserDepth: number,
	teaserFloorStep: number, -- teaser floor = last zone floor + this
}

export type Slot = {
	index: number, -- 1-based position along the spiral
	angle: number, -- radians clockwise from north
	width: number,
	depth: number,
	floor: number,
	-- CFrame at the centre of the catch floor surface. LookVector points at
	-- the hub, so local -Z is "toward the hub" and the gate is on that edge.
	frame: CFrame,
	-- On the floor at the middle of the hub-facing edge, LookVector toward the hub.
	gate: CFrame,
	-- On the hub's rim (hubRadius) in this slot's direction, LookVector
	-- pointing out toward the zone. Connectors run hubExit -> gate.
	hubExit: CFrame,
}

-- Per-zone build context handed to style functions.
export type ZoneContext = {
	def: SharedTypes.ZoneDef?, -- nil for the teaser slot
	slot: Slot,
	folder: Folder, -- put everything for this zone in here
	isTeaser: boolean,
	-- Inner rectangle (centred on slot.frame) where strikes land. Keep it
	-- flat and clear: nothing above floor + 0.3 may be built inside it.
	catchWidth: number,
	catchDepth: number,
	color: Color3, -- the zone's signature colour (grey for the teaser)
}

export type Context = {
	map: Folder,
	folders: {
		base: Folder,
		hub: Folder,
		zones: Folder,
		connectors: Folder,
		decor: Folder,
	},
	terrain: Terrain,
	rng: Random, -- seeded: the same style always builds the same world
	layout: LayoutParams,
	zones: { ZoneContext }, -- in spiral order
	teaser: ZoneContext,
	-- Anchor part for Beam attachments (Kit.cable). Lives at the world origin.
	cableAnchor: BasePart,
}

export type StylePack = {
	name: string,
	description: string,
	palette: { [string]: Color3 },
	layout: LayoutParams,

	-- Lighting, Atmosphere, Clouds, post effects, water colour. Called first.
	-- Name the ColorCorrectionEffect "StormGrade" so storms can tint it.
	-- Set Lighting attributes StormBrightness (number), StormAmbient (Color3),
	-- StormAtmosphereColor (Color3), StormCloudColor (Color3) to tune how
	-- storms look in this style; the client falls back to sensible defaults.
	atmosphere: (ctx: Context) -> (),
	-- Ocean / sky / the landmass under the hub.
	buildBase: (ctx: Context) -> (),
	-- Hub landmass details, hero landmark, wayfinding signs toward every
	-- zone and the teaser. MUST create one SpawnLocation (outside every zone)
	-- and at least one sell station: an invisible box part tagged
	-- "SellArea" (use Kit.sellArea) over a clearly marked pad.
	buildHub: (ctx: Context) -> (),
	-- The zone's landmass: terrain under and around the footprint, with the
	-- catch floor flat at slot.floor across catchWidth x catchDepth.
	buildZoneGround: (ctx: Context, zone: ZoneContext) -> (),
	-- Walkable path/bridge from slot.hubExit to slot.gate (heights differ).
	buildConnector: (ctx: Context, zone: ZoneContext) -> (),
	-- Visible, themed border along the footprint edge (width x depth).
	buildBorder: (ctx: Context, zone: ZoneContext) -> (),
	-- Entrance at slot.gate with the zone's name and tagline.
	buildGate: (ctx: Context, zone: ZoneContext) -> (),
	-- Biome dressing keyed by ZoneDef.theme, e.g. themes.Beach. Decorate the
	-- ring between the catch rectangle and the footprint edge, and outside it.
	-- themes.Default is used for any theme the style doesn't have.
	themes: { [string]: (ctx: Context, zone: ZoneContext) -> () },
	-- The next empty slot: a blocked bridge/path and a "COMING SOON" sign.
	buildTeaser: (ctx: Context, zone: ZoneContext) -> (),
}

return nil
