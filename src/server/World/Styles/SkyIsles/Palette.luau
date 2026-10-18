--!strict
-- SkyIsles palette: the ten core colours, their working shades, terrain
-- material colours and sign looks. Every SkyIsles piece takes its colours
-- from here (docs/styles/SkyIsles.md explains what each one is for).

local ServerScriptService = game:GetService("ServerScriptService")

local Kit = require(ServerScriptService.Server.World.Kit)

local Palette = {}

local C = {
	-- the ten core colours
	skystone = Color3.fromRGB(150, 138, 176), -- main masonry
	plum = Color3.fromRGB(84, 68, 108), -- trim, boards, deep rock
	cream = Color3.fromRGB(246, 238, 224), -- marble caps, rails, clouds
	meadow = Color3.fromRGB(110, 186, 86), -- lawns, foliage
	cyan = Color3.fromRGB(90, 228, 255), -- energy, crystals, runes
	gold = Color3.fromRGB(255, 204, 72), -- selling, money, key signs
	coral = Color3.fromRGB(255, 122, 104), -- warm accent
	seaglass = Color3.fromRGB(70, 170, 140), -- Cloudshore field, water
	ember = Color3.fromRGB(208, 106, 66), -- canyon cliffs
	twilight = Color3.fromRGB(118, 98, 166), -- Mesa field, storm accents

	-- working shades of the core colours
	skystoneLight = Color3.fromRGB(190, 180, 210),
	skystoneDark = Color3.fromRGB(112, 100, 140),
	plumDeep = Color3.fromRGB(56, 44, 76),
	creamWarm = Color3.fromRGB(236, 220, 192),
	meadowDark = Color3.fromRGB(72, 146, 72),
	meadowLight = Color3.fromRGB(160, 214, 110),
	cyanDeep = Color3.fromRGB(46, 156, 214),
	goldDeep = Color3.fromRGB(222, 150, 40),
	coralLight = Color3.fromRGB(255, 176, 160),
	seaglassDeep = Color3.fromRGB(42, 128, 120),
	seafoam = Color3.fromRGB(150, 222, 196),
	emberLight = Color3.fromRGB(232, 150, 92),
	emberDark = Color3.fromRGB(158, 74, 52),
	twilightLight = Color3.fromRGB(154, 134, 196),
	twilightDeep = Color3.fromRGB(96, 78, 142),
	wood = Color3.fromRGB(150, 104, 72),
	woodLight = Color3.fromRGB(198, 160, 112),
	iron = Color3.fromRGB(50, 44, 62),
	cloud = Color3.fromRGB(238, 230, 242),
	ink = Color3.fromRGB(34, 24, 50),
	-- bold two-tone field pairs (30%+ luminance apart)
	fieldMint = Color3.fromRGB(164, 238, 206),
	fieldTeal = Color3.fromRGB(28, 104, 110),
	fieldLilac = Color3.fromRGB(214, 192, 246),
	fieldPlum = Color3.fromRGB(78, 52, 118),
}
Palette.C = C

-- Terrain material colours (Terrain:SetMaterialColor). Grass is only ever
-- used outside catch floors: its grass blades would hide warning circles.
Palette.TERRAIN = {
	[Enum.Material.Rock] = Color3.fromRGB(146, 132, 170),
	[Enum.Material.Slate] = Color3.fromRGB(100, 86, 126),
	[Enum.Material.Basalt] = Color3.fromRGB(66, 54, 88),
	[Enum.Material.Pavement] = Color3.fromRGB(208, 198, 222),
	[Enum.Material.Cobblestone] = Color3.fromRGB(170, 158, 192),
	[Enum.Material.Grass] = Color3.fromRGB(110, 184, 84),
	[Enum.Material.LeafyGrass] = Color3.fromRGB(78, 156, 76),
	[Enum.Material.Sand] = Color3.fromRGB(244, 214, 150),
	[Enum.Material.Sandstone] = Color3.fromRGB(210, 112, 72),
	[Enum.Material.Ground] = Color3.fromRGB(232, 162, 96),
	[Enum.Material.Limestone] = Color3.fromRGB(232, 218, 196),
	[Enum.Material.Mud] = Color3.fromRGB(120, 92, 120),
	[Enum.Material.Salt] = Color3.fromRGB(226, 220, 236),
}

Palette.WATER = Color3.fromRGB(70, 190, 196)

function Palette.lerp(a: Color3, b: Color3, t: number): Color3
	return a:Lerp(b, t)
end

-- Two field tones in the complementary hue of `color`, so warning circles
-- drawn in `color` always stand out against the floor.
function Palette.complement(color: Color3): (Color3, Color3)
	local h, s = color:ToHSV()
	local hue = (h + 0.5) % 1
	if s < 0.15 then
		-- grey zone colours: use a calm sky-blue field
		hue = 0.6
	end
	return Color3.fromHSV(hue, 0.3, 0.92), Color3.fromHSV(hue, 0.6, 0.45)
end

-- The two field tones to lay under warning circles drawn in `color`: the
-- theme's preferred pair, unless its hue is too close to the circles' hue
-- (a theme reused by a zone of a similar colour), then the complement.
function Palette.fieldTones(color: Color3, a: Color3, b: Color3): { Color3 }
	local hue, saturation = color:ToHSV()
	local preferred = a:ToHSV()
	local distance = math.abs(hue - preferred)
	distance = math.min(distance, 1 - distance)
	if saturation >= 0.15 and distance < 0.17 then
		local light, dark = Palette.complement(color)
		return { light, dark }
	end
	return { a, b }
end

-- Sign looks ---------------------------------------------------------------

Palette.SIGN = {
	boardColor = C.plum,
	boardMaterial = Enum.Material.Slate,
	titleColor = C.cream,
	subtitleColor = C.gold,
	strokeColor = C.ink,
	titleFont = Enum.Font.LuckiestGuy,
	subtitleFont = Enum.Font.FredokaOne,
} :: Kit.SignStyle

-- A board whose title glows in a zone's colour.
function Palette.signFor(color: Color3, twoSided: boolean?): Kit.SignStyle
	return {
		boardColor = C.plum,
		boardMaterial = Enum.Material.Slate,
		titleColor = color:Lerp(Color3.new(1, 1, 1), 0.15),
		subtitleColor = C.cream,
		strokeColor = C.ink,
		titleFont = Enum.Font.LuckiestGuy,
		subtitleFont = Enum.Font.FredokaOne,
		twoSided = twoSided,
	}
end

-- The gold SELL look.
Palette.SELL_SIGN = {
	boardColor = C.plumDeep,
	boardMaterial = Enum.Material.Slate,
	titleColor = C.gold,
	subtitleColor = C.cream,
	strokeColor = C.ink,
	titleFont = Enum.Font.LuckiestGuy,
	subtitleFont = Enum.Font.FredokaOne,
	twoSided = true,
} :: Kit.SignStyle

return Palette
