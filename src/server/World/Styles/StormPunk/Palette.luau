--!strict
-- StormPunk style guide in code: the 10-colour palette, the tints derived
-- from it, the terrain and light tokens, materials and sign styles every
-- piece uses (see docs/styles/StormPunk.md).

local ServerScriptService = game:GetService("ServerScriptService")

local Kit = require(ServerScriptService.Server.World.Kit)

local Palette = {}

Palette.colors = {
	copper = Color3.fromRGB(186, 104, 58), -- main metal: pylons, coils, pipes
	patina = Color3.fromRGB(78, 168, 150), -- verdigris: roofs, domes, tide bands
	brass = Color3.fromRGB(222, 176, 78), -- trim: rails, frames, cornices
	ceramic = Color3.fromRGB(240, 236, 224), -- insulators, boards, lighthouse bands
	volt = Color3.fromRGB(90, 238, 255), -- electricity (Neon only)
	iron = Color3.fromRGB(60, 66, 78), -- girders, decks, lattice legs
	soot = Color3.fromRGB(34, 36, 44), -- darkest: sign boards, strokes
	hazard = Color3.fromRGB(255, 190, 40), -- amber: reserved for SELL (+ teaser stripes)
	timber = Color3.fromRGB(156, 104, 64), -- boardwalks, crates, piers
	sage = Color3.fromRGB(132, 158, 112), -- scrub, dune grass, Mesa tiles
}

local C = Palette.colors

-- Tints: every one is a palette colour mixed toward soot (darker) or
-- ceramic (paler), so nothing off-palette sneaks in.
local function dark(color: Color3, t: number): Color3
	return color:Lerp(C.soot, t)
end
local function pale(color: Color3, t: number): Color3
	return color:Lerp(C.ceramic, t)
end

Palette.tints = {
	copperDark = dark(C.copper, 0.35),
	patinaDark = dark(C.patina, 0.35),
	patinaPale = pale(C.patina, 0.35),
	brassDark = dark(C.brass, 0.3),
	ceramicShade = dark(C.ceramic, 0.14),
	ironLight = pale(C.iron, 0.2),
	timberDark = dark(C.timber, 0.3),
	timberPale = pale(C.timber, 0.35),
	sageDark = dark(C.sage, 0.3),
	glass = pale(C.volt, 0.55), -- lantern and capacitor glass
	rock = dark(C.timber, 0.15):Lerp(C.iron, 0.35), -- part rocks match terrain Rock
	rockDark = dark(C.iron, 0.05):Lerp(C.timber, 0.2),
}

-- Light tokens (PointLight colours and warm windows: light, not paint).
Palette.light = {
	warm = Color3.fromRGB(255, 200, 130), -- lamps, windows, the cozy calm glow
	volt = C.volt, -- lanterns, orbs, coil
}

-- Terrain material colours (Terrain:SetMaterialColor), all palette-derived.
-- Every terrain material StormPunk uses is listed, so Roblox defaults
-- (drab khaki sand, near-black basalt, teal slate...) never show.
Palette.terrain = {
	[Enum.Material.Sand] = Color3.fromRGB(230, 200, 140), -- beaches, Shoreline field
	[Enum.Material.Limestone] = Color3.fromRGB(224, 204, 162), -- Mesa field base, strata
	[Enum.Material.Sandstone] = Color3.fromRGB(198, 128, 86), -- mesa cliffs (copper family)
	[Enum.Material.Basalt] = Color3.fromRGB(82, 88, 104), -- sea stacks, crags (iron family)
	[Enum.Material.Slate] = Color3.fromRGB(104, 110, 124), -- hub and yard cliffs
	[Enum.Material.Rock] = Color3.fromRGB(132, 120, 108), -- strata, talus
	[Enum.Material.Brick] = Color3.fromRGB(160, 92, 62), -- hub plaza
	[Enum.Material.Pavement] = Color3.fromRGB(184, 176, 160), -- hub paving, spokes
	[Enum.Material.LeafyGrass] = Color3.fromRGB(116, 160, 84), -- terraces, dunes, caps
	[Enum.Material.Grass] = Color3.fromRGB(126, 166, 92), -- planters
	[Enum.Material.Ground] = Color3.fromRGB(150, 98, 64), -- mesa strata (timber family)
	[Enum.Material.Concrete] = Color3.fromRGB(150, 154, 156), -- generator yard
	[Enum.Material.Salt] = Color3.fromRGB(226, 220, 204), -- salt flats on the shore
}

-- Water: teal, a patina cousin.
Palette.water = Color3.fromRGB(34, 132, 138)

Palette.materials = {
	metal = Enum.Material.Metal,
	rusty = Enum.Material.CorrodedMetal,
	plate = Enum.Material.DiamondPlate,
	ceramic = Enum.Material.SmoothPlastic,
	neon = Enum.Material.Neon,
	glass = Enum.Material.Glass,
	planks = Enum.Material.WoodPlanks,
	wood = Enum.Material.Wood,
	fabric = Enum.Material.Fabric,
	concrete = Enum.Material.Concrete,
	brick = Enum.Material.Brick,
}

-- Chunky, Bee Swarm-style signage: dark board, bright title, white subtitle.
function Palette.sign(titleColor: Color3?, twoSided: boolean?): Kit.SignStyle
	return {
		boardColor = C.soot,
		boardMaterial = Enum.Material.SmoothPlastic,
		titleColor = titleColor or C.brass,
		subtitleColor = C.ceramic,
		strokeColor = Color3.fromRGB(20, 20, 26),
		titleFont = Enum.Font.LuckiestGuy,
		subtitleFont = Enum.Font.FredokaOne,
		thickness = 0.8,
		twoSided = twoSided == true,
	}
end

-- Light board for the giant marquee signs.
function Palette.marquee(): Kit.SignStyle
	return {
		boardColor = C.ceramic,
		boardMaterial = Enum.Material.SmoothPlastic,
		titleColor = C.hazard,
		subtitleColor = C.soot,
		strokeColor = C.soot,
		titleFont = Enum.Font.LuckiestGuy,
		subtitleFont = Enum.Font.FredokaOne,
		thickness = 1,
		twoSided = true,
	}
end

return Palette
