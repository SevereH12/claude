--!strict
-- Types shared by the WeatherLab modules.

local ServerScriptService = game:GetService("ServerScriptService")

local WorldTypes = require(ServerScriptService.Server.World.Types)

export type Context = WorldTypes.Context
export type ZoneContext = WorldTypes.ZoneContext

-- How far a zone's plateau top reaches past its footprint on each side.
export type Margins = { front: number, back: number, side: number }

-- Border posts around a zone's footprint.
export type BorderLook = {
	postColor: Color3,
	postMaterial: Enum.Material,
	postDiameter: number,
	postHeight: number,
	stones: boolean, -- a little cairn stone at the foot of each post
}

-- Bold two-tone pattern the catch floor blocks are laid in.
export type FieldLook = {
	base: Color3,
	accent: Color3,
	trim: Color3,
	pattern: string, -- "across" stripes, "along" stripes or "checker"
	cell: number, -- stripe / square size in studs
	piping: Color3?, -- 1-stud bands either side of each accent stripe
}

-- The block island under a zone: a rectangular plateau (the field plus its
-- margins) on stepped strata, standing in an octagonal beach tier whose
-- wedge slopes run down to the sea bed.
export type IslandLook = {
	cap: Color3, -- plateau top round the field
	strata: { Color3 }, -- plateau cliff bands, top band first, alternating
	layer: number, -- target cliff band height
	inset: number, -- each lower band steps out this far
	beach: Color3,
	beachTop: number, -- beach tier height (world y, kept below the floor)
	beachSide: number, -- beach width past the plateau's sides
	beachBack: number, -- ... past its back
	beachFront: number, -- ... past its front (negative: starts behind it)
	chamfer: number, -- round off the beach tier's corners (arc radius)
	ramp: number?, -- 1 / -1: a ramp from the beach up the right / left cliff
}

export type Theme = {
	margins: Margins,
	island: IslandLook,
	field: FieldLook,
	-- optional per-zone field (e.g. Default rotates patterns by slot so
	-- several fallback zones never look identical)
	fieldFor: ((zone: ZoneContext) -> FieldLook)?,
	border: BorderLook,
	boardwalkTrim: Color3?, -- a band in this colour round each boardwalk rail post
	-- biome landforms round the plateau (headlands, spits, spires, stacks),
	-- built after the plateau and its beach
	ground: (ctx: Context, zone: ZoneContext) -> (),
	-- hero landmark, mid-size props and small details around the field
	dress: (ctx: Context, zone: ZoneContext) -> (),
}

return nil
