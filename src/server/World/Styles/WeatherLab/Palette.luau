--!strict
-- Barometer Bay palette, materials and sign styles. Every piece in the
-- WeatherLab style takes its colours from here (see docs/styles/WeatherLab.md).

local ServerScriptService = game:GetService("ServerScriptService")

local Kit = require(ServerScriptService.Server.World.Kit)

local Palette = {}

Palette.colors = {
	beacon = Color3.fromRGB(214, 69, 58), -- lighthouse red
	sailcloth = Color3.fromRGB(246, 239, 222), -- cream walls, bands, domes
	driftwood = Color3.fromRGB(196, 154, 108), -- decks, benches, crates
	piling = Color3.fromRGB(92, 68, 52), -- stilts, posts, beams
	harbor = Color3.fromRGB(72, 92, 122), -- slate roofs, instrument metal, stone
	seafoam = Color3.fromRGB(86, 190, 176), -- lab teal trims and shutters
	slicker = Color3.fromRGB(255, 204, 64), -- raincoat yellow: SELL, arrows, hazard
	spark = Color3.fromRGB(110, 232, 255), -- bottled lightning (Neon only)
	kelp = Color3.fromRGB(104, 164, 84), -- foliage
	ink = Color3.fromRGB(34, 44, 66), -- navy text strokes, fittings
} :: { [string]: Color3 }

local C = Palette.colors

-- Derived tones (always mixes of the palette, never new hues).
Palette.lamp = Color3.fromRGB(255, 178, 100) -- warm lantern light
Palette.window = Color3.fromRGB(255, 196, 120) -- lit window glass
Palette.plankDark = C.driftwood:Lerp(C.piling, 0.22)
Palette.plankLight = C.driftwood:Lerp(C.sailcloth, 0.18)
Palette.stone = C.harbor:Lerp(C.sailcloth, 0.35)
Palette.stoneDark = C.harbor:Lerp(C.ink, 0.3)
Palette.leafDark = C.kelp:Lerp(C.ink, 0.25)
Palette.leafLight = C.kelp:Lerp(C.slicker, 0.25)
Palette.sand = C.driftwood:Lerp(C.sailcloth, 0.45)
Palette.teaser = Color3.fromRGB(150, 150, 160)

-- Terrain material colours, tuned to the palette.
Palette.terrain = {
	{ material = Enum.Material.Sand, color = Color3.fromRGB(234, 210, 154) },
	{ material = Enum.Material.Salt, color = Color3.fromRGB(248, 244, 232) },
	{ material = Enum.Material.Sandstone, color = Color3.fromRGB(204, 118, 78) },
	{ material = Enum.Material.Limestone, color = Color3.fromRGB(238, 216, 172) },
	{ material = Enum.Material.Rock, color = Color3.fromRGB(118, 124, 136) },
	{ material = Enum.Material.Slate, color = Color3.fromRGB(86, 100, 122) },
	{ material = Enum.Material.Grass, color = Color3.fromRGB(112, 168, 82) },
	{ material = Enum.Material.LeafyGrass, color = Color3.fromRGB(74, 128, 60) },
	{ material = Enum.Material.Cobblestone, color = Color3.fromRGB(164, 154, 140) },
	{ material = Enum.Material.Brick, color = Color3.fromRGB(176, 90, 70) },
	{ material = Enum.Material.WoodPlanks, color = Color3.fromRGB(176, 130, 88) },
	{ material = Enum.Material.Ground, color = Color3.fromRGB(140, 106, 74) },
	{ material = Enum.Material.Basalt, color = Color3.fromRGB(60, 66, 80) },
}

Palette.water = Color3.fromRGB(46, 150, 162)

-- Sign styles ------------------------------------------------------------------

-- Wooden board, cream title, navy stroke: the default village sign.
local SIGN: Kit.SignStyle = {
	boardColor = C.driftwood,
	boardMaterial = Enum.Material.Wood,
	titleColor = C.sailcloth,
	subtitleColor = C.slicker,
	strokeColor = C.ink,
	titleFont = Enum.Font.LuckiestGuy,
	subtitleFont = Enum.Font.FredokaOne,
	thickness = 0.8,
}

-- A sign whose title is a zone's own colour.
function Palette.zoneSign(color: Color3): Kit.SignStyle
	return {
		boardColor = C.ink,
		boardMaterial = Enum.Material.SmoothPlastic,
		titleColor = color,
		subtitleColor = C.sailcloth,
		strokeColor = Color3.fromRGB(14, 18, 30),
		titleFont = Enum.Font.LuckiestGuy,
		subtitleFont = Enum.Font.FredokaOne,
		thickness = 0.8,
	}
end

-- The giant SELL board.
local SELL_SIGN: Kit.SignStyle = {
	boardColor = C.slicker,
	boardMaterial = Enum.Material.SmoothPlastic,
	titleColor = C.beacon,
	subtitleColor = C.ink,
	strokeColor = C.sailcloth,
	titleFont = Enum.Font.LuckiestGuy,
	subtitleFont = Enum.Font.FredokaOne,
	thickness = 1,
	twoSided = true,
}

-- Hazard sign for the Coming Soon barrier.
local HAZARD_SIGN: Kit.SignStyle = {
	boardColor = C.slicker,
	boardMaterial = Enum.Material.SmoothPlastic,
	titleColor = C.ink,
	subtitleColor = C.ink,
	strokeColor = C.slicker,
	titleFont = Enum.Font.LuckiestGuy,
	subtitleFont = Enum.Font.FredokaOne,
	thickness = 0.8,
	twoSided = true,
}

Palette.SIGN = SIGN
Palette.SELL_SIGN = SELL_SIGN
Palette.HAZARD_SIGN = HAZARD_SIGN

return Palette
