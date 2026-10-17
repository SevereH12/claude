--!strict
-- Types shared by the SkyIsles modules.

local ServerScriptService = game:GetService("ServerScriptService")

local WorldTypes = require(ServerScriptService.Server.World.Types)

type Context = WorldTypes.Context
type ZoneContext = WorldTypes.ZoneContext

-- The carpet of flush bands/tiles that patterns a catch floor.
export type FieldPattern = {
	kind: "bands" | "checker",
	colors: { Color3 }, -- alternated
	materials: { Enum.Material }, -- alternated with colors
	size: number, -- target band or tile size in studs
	axis: "x" | "z"?, -- bands: stripes change along this local axis (default z)
	widths: { number }?, -- bands: relative widths, cycled (strata look)
}

-- How a theme's island is built (materials, field, shape).
export type ThemeSpec = {
	rim: Enum.Material, -- plateau surface around the field
	terrace: Enum.Material, -- lower ledges hanging off the sides
	cliffs: { Enum.Material }, -- underside, top to bottom
	fieldTerrain: Enum.Material, -- flat terrain under the field carpet
	field: FieldPattern,
	accent: Color3, -- crystals hanging under the island
	depth: number, -- how far the underside reaches below the floor
	ridge: Enum.Material, -- backdrop ridge behind the field (rocks, walls, hills)
	ridgeHeight: number,
}

export type Theme = {
	spec: (zone: ZoneContext) -> ThemeSpec,
	dress: (ctx: Context, zone: ZoneContext, spec: ThemeSpec, land: Land) -> (),
}

-- Where an island has guaranteed flat land (zone-local, at the floor):
-- x in [-halfW, halfW], z in [front, back]; plus extra terraces.
export type Land = {
	halfW: number,
	front: number, -- negative: the hub-facing edge of the land
	back: number,
	terraces: { { center: Vector3, radius: number, top: number } },
	blocked: { { center: Vector3, radius: number } }, -- ridge lumps: keep props off
}

return nil
