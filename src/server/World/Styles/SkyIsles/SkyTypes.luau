--!strict
-- Types shared by the SkyIsles modules.

local ServerScriptService = game:GetService("ServerScriptService")

local WorldTypes = require(ServerScriptService.Server.World.Types)

type Context = WorldTypes.Context
type ZoneContext = WorldTypes.ZoneContext

-- The carpet of flush bands/tiles that patterns a catch floor.
export type FieldPattern = {
	kind: "bands" | "checker" | "rings",
	colors: { Color3 }, -- alternated
	materials: { Enum.Material }, -- alternated with colors
	size: number, -- target band or tile size in studs
	axis: "x" | "z"?, -- bands: stripes change along this local axis (default z)
	widths: { number }?, -- bands: relative widths, cycled (strata look)
}

-- How a theme's island is built (colours, field, shape).
export type ThemeSpec = {
	rim: Color3, -- cap of the plateau round the field, its lobes and headlands
	soil: Color3, -- band under the cap
	cliffs: { Color3 }, -- underside strata (alternated), the last one for hanging points
	field: FieldPattern,
	accent: Color3, -- crystals hanging under the island
	depth: number, -- how far the underside reaches below the floor
	shore: number?, -- extra rim on the sides and back (a broad beach)
	ridge: Color3, -- backdrop ridge behind the field (rocks, walls, hills)
	ridgeHeight: number,
	ridgeShape: ("slabs" | "dunes")?, -- tilted rock slabs (default) or stepped mounds
	ridgeCap: Color3?, -- dunes: crown on each mound
	spires: Color3?, -- a couple of stacked rock spires on the ridge line
}

export type Theme = {
	spec: (zone: ZoneContext) -> ThemeSpec,
	dress: (ctx: Context, zone: ZoneContext, spec: ThemeSpec, land: Land) -> (),
}

-- Where an island has guaranteed flat land (zone-local, at the floor):
-- x in [-halfW, halfW], z in [front, back] with chamfered corners; plus
-- the coast lobes and headlands (all with their top at the floor).
export type Land = {
	halfW: number,
	front: number, -- negative: the hub-facing edge of the land
	back: number,
	terraces: { { center: Vector3, radius: number, top: number } },
	blocked: { { center: Vector3, radius: number } }, -- ridge lumps: keep props off
}

return nil
