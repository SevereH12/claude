--!strict
-- Types shared by the WeatherLab modules.

local ServerScriptService = game:GetService("ServerScriptService")

local WorldTypes = require(ServerScriptService.Server.World.Types)

export type Context = WorldTypes.Context
export type ZoneContext = WorldTypes.ZoneContext

-- How far a zone's island top reaches past its footprint on each side.
export type Margins = { front: number, back: number, side: number }

-- Border posts around a zone's footprint.
export type BorderLook = {
	postColor: Color3,
	postMaterial: Enum.Material,
	postDiameter: number,
	postHeight: number,
	stones: boolean, -- a little cairn stone at the foot of each post
}

-- Bold two-tone pattern painted into a zone's flat catch floor.
export type FieldLook = {
	base: Enum.Material,
	accent: Enum.Material,
	trim: Enum.Material,
	pattern: string, -- "across" stripes, "along" stripes or "checker"
	cell: number, -- stripe / square size in studs
}

export type Theme = {
	margins: Margins,
	field: FieldLook,
	border: BorderLook,
	-- terrain under and around the footprint (the field is painted after)
	ground: (ctx: Context, zone: ZoneContext) -> (),
	-- hero landmark, mid-size props and small details around the field
	dress: (ctx: Context, zone: ZoneContext) -> (),
}

return nil
