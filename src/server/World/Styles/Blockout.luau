--!strict
-- Blockout: the reference style pack. Plain grey shapes, no art. It exists
-- to show every function a style must provide and to test the framework.
-- Copy it to start a new style (a style can also be a folder with
-- init.luau plus extra modules, e.g. Styles/StormPunk/init.luau).

local ServerScriptService = game:GetService("ServerScriptService")
local Lighting = game:GetService("Lighting")

local World = ServerScriptService.Server.World
local Kit = require(World.Kit)
local WorldTypes = require(World.Types)

type Context = WorldTypes.Context
type ZoneContext = WorldTypes.ZoneContext

local PALETTE = {
	ground = Color3.fromRGB(150, 150, 150),
	trim = Color3.fromRGB(90, 90, 95),
	accent = Color3.fromRGB(255, 210, 60),
	text = Color3.fromRGB(255, 255, 255),
}

local SIGN: Kit.SignStyle = {
	boardColor = PALETTE.trim,
	titleColor = PALETTE.accent,
	twoSided = true,
}

local Style = {}

Style.name = "Blockout"
Style.description = "Reference style: grey blockout shapes for testing the world framework."
Style.palette = PALETTE
Style.layout = {
	hubFloor = 8,
	hubRadius = 44,
	firstRadius = 150,
	radiusStep = 70,
	firstAngle = 90,
	angleStep = 135,
	teaserWidth = 90,
	teaserDepth = 90,
	teaserFloorStep = 12,
}

function Style.atmosphere(_ctx: Context)
	Lighting.ClockTime = 14
	Lighting.Brightness = 2
end

function Style.buildBase(ctx: Context)
	-- sea floor and ocean (surface at y = 0)
	Kit.fillBox(ctx, CFrame.new(0, -24, 0), Vector3.new(1600, 8, 1600), Enum.Material.Sand)
	Kit.fillBox(ctx, CFrame.new(0, -10, 0), Vector3.new(1600, 20, 1600), Enum.Material.Water)
	-- hub island, reaching past the connector start points
	local layout = ctx.layout
	Kit.blob(
		ctx,
		Vector3.zero,
		layout.hubRadius / 0.8 + 6,
		layout.hubFloor,
		layout.hubFloor + 20,
		Enum.Material.Concrete,
		8
	)
end

function Style.buildHub(ctx: Context)
	local floor = ctx.layout.hubFloor
	local hub = ctx.folders.hub
	Kit.spawn(hub, CFrame.new(0, floor + 0.5, 18), Vector3.new(10, 1, 10), { Color = PALETTE.trim })

	local pad = Kit.part({
		Name = "SellPad",
		Size = Vector3.new(16, 1, 16),
		CFrame = CFrame.new(0, floor + 0.5, -14),
		Color = PALETTE.accent,
		Material = Enum.Material.Neon,
		Parent = hub,
	})
	Kit.faceText(
		pad,
		Enum.NormalId.Top,
		"SELL",
		nil,
		{ boardColor = PALETTE.accent, titleColor = PALETTE.text }
	)
	Kit.sellArea(hub, pad)

	-- a signpost toward every zone (and the teaser)
	local all = table.clone(ctx.zones)
	table.insert(all, ctx.teaser)
	for _, zone in all do
		local exit = zone.slot.hubExit
		local name = if zone.def then zone.def.displayName else "Coming Soon"
		local post = exit.Position - exit.LookVector * 6 + exit.RightVector * 8
		Kit.decor({
			Size = Vector3.new(0.6, 6, 0.6),
			CFrame = CFrame.new(post + Vector3.new(0, 3, 0)),
			Color = PALETTE.trim,
			Parent = hub,
		})
		Kit.sign(
			hub,
			CFrame.lookAt(
				post + Vector3.new(0, 6.5, 0),
				post + Vector3.new(0, 6.5, 0) - exit.LookVector
			),
			8,
			2,
			name,
			nil,
			SIGN
		)
	end
end

function Style.buildZoneGround(ctx: Context, zone: ZoneContext)
	local slot = zone.slot
	Kit.slab(
		ctx,
		slot.frame,
		slot.width + 16,
		slot.depth + 16,
		slot.floor,
		slot.floor + 20,
		Enum.Material.Slate,
		8
	)
end

function Style.buildConnector(ctx: Context, zone: ZoneContext)
	local slot = zone.slot
	Kit.walkway(ctx.folders.connectors, slot.hubExit.Position, slot.gate.Position, 12, 1, {
		Name = "Bridge",
		Color = PALETTE.trim,
		Material = Enum.Material.Concrete,
	})
end

function Style.buildBorder(_ctx: Context, zone: ZoneContext)
	for _, cframe in Kit.perimeter(zone, 16) do
		Kit.cylinder(
			zone.folder,
			cframe.Position,
			4,
			0.8,
			{ Color = zone.color, Material = Enum.Material.Neon }
		)
	end
end

function Style.buildGate(_ctx: Context, zone: ZoneContext)
	local def = zone.def :: any
	local gate = zone.slot.gate
	local signCFrame = gate * CFrame.new(0, 12, 0) * CFrame.Angles(0, 0, 0)
	Kit.sign(zone.folder, signCFrame, 20, 5, string.upper(def.displayName), def.tagline, SIGN)
end

Style.themes = {
	Default = function(_ctx: Context, _zone: ZoneContext) end,
}

function Style.buildTeaser(ctx: Context, zone: ZoneContext)
	local slot = zone.slot
	Kit.slab(
		ctx,
		slot.frame,
		slot.width,
		slot.depth,
		slot.floor,
		slot.floor + 20,
		Enum.Material.Slate,
		8
	)
	-- half a bridge, then a barrier
	local from = slot.hubExit.Position
	local halfway = from:Lerp(slot.gate.Position, 0.45)
	Kit.walkway(
		ctx.folders.connectors,
		from,
		halfway,
		12,
		1,
		{ Name = "BrokenBridge", Color = PALETTE.trim }
	)
	Kit.sign(
		zone.folder,
		CFrame.lookAt(halfway + Vector3.new(0, 4, 0), from + Vector3.new(0, 4, 0)),
		12,
		5,
		"COMING SOON",
		nil,
		SIGN
	)
end

return Style
