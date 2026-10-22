--!strict
-- Premium theme ("Aurora Reef", for Roblox Premium zones): Default's island,
-- landforms and dressing, then the premium touches: gold-trimmed posts and
-- boardwalk, violet border ropes (the zone colour), a PREMIUM arch in front
-- of the gate, lanterns round the plateau and an aurora ribbon in the sky.
-- The catch floor stays low contrast so the bolt rings read clearly.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Kit = require(ServerScriptService.Server.World.Kit)
local Progression = require(ReplicatedStorage.Shared.Util.Progression)
local Default = require(script.Parent.Default)
local Geo = require(script.Parent.Parent.Geo)
local Palette = require(script.Parent.Parent.Palette)
local Pieces = require(script.Parent.Parent.Pieces)
local WLTypes = require(script.Parent.Parent.WLTypes)

type Context = WLTypes.Context
type ZoneContext = WLTypes.ZoneContext
type Theme = WLTypes.Theme

local C = Palette.colors

local GOLD = Color3.fromRGB(232, 186, 76)
local VIOLET = Color3.fromRGB(92, 58, 150)
local LANTERN = Color3.fromRGB(255, 214, 140)
local AURORA = ColorSequence.new(Color3.fromRGB(90, 255, 170), Color3.fromRGB(190, 120, 255))
local AURORA_FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.25, 0.35),
	NumberSequenceKeypoint.new(0.75, 0.35),
	NumberSequenceKeypoint.new(1, 1),
})

-- The arch stands between the lighthouse gate (1.8 in front of the field)
-- and the research camp pad (5 in front). It frames the gate: its posts
-- stand outside the gate's lamp posts and the value plaque, and its
-- PREMIUM board sits above the gate's lamps, so the zone sign behind it
-- reads in full from the boardwalk.
local ARCH_Z = 3.9
local ARCH_X = 13.4
local ARCH_H = 17.5 -- above the gate's lamps (about 15.4 over the floor)
local ARCH_BOARD = Vector2.new(16, 3)
local ZONE_CEILING = 46 -- the zone volume's height; the aurora flies above it

local SIGN: Kit.SignStyle = {
	boardColor = VIOLET,
	titleColor = GOLD,
	subtitleColor = C.sailcloth,
	strokeColor = C.ink,
}

local Premium = {}

-- Zone-local spot on the ground (y relative to the catch floor).
local function onGround(ctx: Context, zone: ZoneContext, x: number, z: number): Vector3
	return Geo.at(zone, x, z, Geo.groundAt(ctx, zone, x, z) - zone.slot.floor)
end

local function arch(ctx: Context, zone: ZoneContext)
	local folder = zone.folder
	local z = -zone.slot.depth / 2 - ARCH_Z
	local up = Vector3.new(0, 1, 0)
	local top = onGround(ctx, zone, 0, z).Y - zone.slot.floor + ARCH_H
	for _, side in { -1, 1 } do
		local bottom = onGround(ctx, zone, side * ARCH_X, z)
		-- each post reaches the crossbar, whatever the ground does under it
		local height = top - (bottom.Y - zone.slot.floor)
		Pieces.box(
			folder,
			CFrame.new(bottom + up * 0.3),
			Vector3.new(2, 0.6, 2),
			GOLD,
			Enum.Material.Metal
		)
		Pieces.box(
			folder,
			CFrame.new(bottom + up * (height / 2)),
			Vector3.new(1.2, height, 1.2),
			VIOLET,
			Enum.Material.SmoothPlastic
		)
		for _, y in { 2.2, height / 2, height - 1.2 } do
			Pieces.box(
				folder,
				CFrame.new(bottom + up * y),
				Vector3.new(1.4, 0.3, 1.4),
				GOLD,
				Enum.Material.Metal,
				false
			)
		end
		-- a lantern hanging inside each post
		local hook = Geo.at(zone, side * (ARCH_X - 1.6), z, top)
		Pieces.lantern(folder, hook - up * 2, LANTERN, 16)
		Kit.cable(ctx, hook, hook - up * 1, { Color = C.ink, Width = 0.1 })
	end
	Pieces.box(
		folder,
		Geo.cf(zone, 0, z, top + 0.35),
		Vector3.new(ARCH_X * 2 + 1.6, 0.7, 1.4),
		GOLD,
		Enum.Material.Metal,
		false
	)
	Pieces.signBoard(
		folder,
		-- its bottom rail (0.4 under the board) rests on the crossbar
		Geo.cf(zone, 0, z, top + 0.7 + 0.4 + ARCH_BOARD.Y / 2),
		ARCH_BOARD.X,
		ARCH_BOARD.Y,
		`{Progression.PREMIUM_ICON} PREMIUM`,
		"members only",
		SIGN,
		nil,
		{ title = `{Progression.PREMIUM_ICON} PREMIUM`, subtitle = "thanks for being a member" }
	)
end

-- A violet lamp post with gold fittings and a warm lantern on top.
local function lanternPost(ctx: Context, zone: ZoneContext, x: number, z: number)
	local folder = zone.folder
	local bottom = onGround(ctx, zone, x, z)
	local h = 4.4
	Pieces.cyl(folder, bottom, 0.5, 1.2, GOLD, Enum.Material.Metal)
	Pieces.cyl(folder, bottom, h, 0.5, VIOLET, Enum.Material.SmoothPlastic)
	Pieces.cyl(folder, bottom + Vector3.new(0, h, 0), 0.3, 0.9, GOLD, Enum.Material.Metal)
	Pieces.lantern(folder, bottom + Vector3.new(0, h + 0.3 + 0.65, 0), LANTERN, 16)
end

-- Three wavy glowing ribbons across the sky above the zone. Beams cost
-- no parts and sit above the zone volume, so the catch floor stays clear.
local function aurora(ctx: Context, zone: ZoneContext)
	local hw, hd = zone.slot.width / 2, zone.slot.depth / 2
	for _, band in
		{
			{ z = -0.3, rise = 12, width = 14 },
			{ z = 0.15, rise = 17, width = 18 },
			{ z = 0.6, rise = 22, width = 12 },
		}
	do
		local y = ZONE_CEILING + band.rise
		local ribbon = Kit.cable(
			ctx,
			Geo.at(zone, -hw - 14, hd * band.z - 10, y),
			Geo.at(zone, hw + 14, hd * band.z + 10, y + 4),
			{ Width = band.width, LightEmission = 1, Brightness = 2, Segments = 30, CurveSize = 14 }
		)
		ribbon.Name = "Aurora"
		ribbon.CurveSize1 = 14 -- both ends bend the same way: an S-wave, not a sag
		ribbon.Width1 = band.width * 0.6
		ribbon.Color = AURORA
		ribbon.Transparency = AURORA_FADE
	end
end

local function dress(ctx: Context, zone: ZoneContext)
	Default.dress(ctx, zone)
	arch(ctx, zone)
	local hw, hd = zone.slot.width / 2, zone.slot.depth / 2
	for _, spot in { { -1, -1 }, { 1, -1 }, { -1, 0 }, { 1, 0 }, { -1, 1 }, { 1, 1 } } do
		lanternPost(ctx, zone, spot[1] * (hw + 5), spot[2] * (hd + 4))
	end
	aurora(ctx, zone)
end

local theme: Theme = {
	margins = Default.theme.margins,
	island = Default.theme.island,
	-- two close sea-greens: a calm floor the violet bolt rings stand out on
	field = {
		base = Color3.fromRGB(104, 158, 124),
		accent = Color3.fromRGB(114, 167, 133),
		trim = GOLD,
		pattern = "along",
		cell = 14,
	},
	border = {
		postColor = GOLD,
		postMaterial = Enum.Material.Metal,
		postDiameter = 0.8,
		postHeight = 3.2,
		stones = false,
	},
	boardwalkTrim = GOLD,
	ground = Default.ground,
	dress = dress,
}
Premium.theme = theme

return Premium
