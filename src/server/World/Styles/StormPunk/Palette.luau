--!strict
-- StormPunk style guide in code: the 10-colour palette, materials and
-- sign styles every piece uses (see docs/styles/StormPunk.md).

local ServerScriptService = game:GetService("ServerScriptService")

local Kit = require(ServerScriptService.Server.World.Kit)

local Palette = {}

Palette.colors = {
	copper = Color3.fromRGB(186, 104, 58), -- main metal: pylons, coils, pipes
	patina = Color3.fromRGB(78, 168, 150), -- verdigris: roofs, domes, tide bands
	brass = Color3.fromRGB(222, 176, 78), -- trim: rails, frames, lamp housings
	ceramic = Color3.fromRGB(240, 236, 224), -- insulators, boards, lighthouse bands
	volt = Color3.fromRGB(90, 238, 255), -- electricity (Neon only)
	iron = Color3.fromRGB(60, 66, 78), -- girders, decks, lattice legs
	soot = Color3.fromRGB(34, 36, 44), -- darkest: sign boards, strokes
	hazard = Color3.fromRGB(255, 190, 40), -- amber: SELL, hazard stripes, teaser
	timber = Color3.fromRGB(156, 104, 64), -- boardwalks, crates, piers
	sage = Color3.fromRGB(132, 158, 112), -- scrub, dune grass, Mesa tiles
}

-- Tints derived from the palette (lighter/darker versions only).
Palette.tints = {
	copperDark = Color3.fromRGB(128, 70, 42),
	patinaDark = Color3.fromRGB(52, 120, 110),
	patinaPale = Color3.fromRGB(120, 196, 178),
	brassDark = Color3.fromRGB(170, 128, 52),
	ceramicShade = Color3.fromRGB(206, 200, 186),
	ironLight = Color3.fromRGB(96, 104, 118),
	timberDark = Color3.fromRGB(112, 74, 46),
	timberPale = Color3.fromRGB(196, 150, 100),
	sageDark = Color3.fromRGB(96, 122, 82),
	sand = Color3.fromRGB(226, 198, 140),
	cream = Color3.fromRGB(236, 220, 186),
	glass = Color3.fromRGB(170, 230, 240),
	warmLight = Color3.fromRGB(255, 196, 120),
	rock = Color3.fromRGB(120, 112, 104),
	rockDark = Color3.fromRGB(84, 80, 78),
}

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
}

-- Chunky, Bee Swarm-style signage: dark board, bright title, white subtitle.
function Palette.sign(titleColor: Color3?, twoSided: boolean?): Kit.SignStyle
	return {
		boardColor = Palette.colors.soot,
		boardMaterial = Enum.Material.SmoothPlastic,
		titleColor = titleColor or Palette.colors.brass,
		subtitleColor = Palette.colors.ceramic,
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
		boardColor = Palette.colors.ceramic,
		boardMaterial = Enum.Material.SmoothPlastic,
		titleColor = Palette.colors.hazard,
		subtitleColor = Palette.colors.soot,
		strokeColor = Palette.colors.soot,
		titleFont = Enum.Font.LuckiestGuy,
		subtitleFont = Enum.Font.FredokaOne,
		thickness = 1,
		twoSided = true,
	}
end

return Palette
