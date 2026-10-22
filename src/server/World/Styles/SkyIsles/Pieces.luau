--!strict
-- SkyIsles building pieces: the style's own kit, built on the framework Kit
-- with colours from Palette. Everything takes world positions and works at
-- any slot position or rotation, so zone themes stack automatically.

local ServerScriptService = game:GetService("ServerScriptService")

local World = ServerScriptService.Server.World
local Kit = require(World.Kit)
local Layout = require(World.Layout)
local WorldTypes = require(World.Types)
local Blocks = require(World.Blocks)
local Ground = require(script.Parent.Ground)
local Palette = require(script.Parent.Palette)
local SkyTypes = require(script.Parent.SkyTypes)

type Context = WorldTypes.Context
type ZoneContext = WorldTypes.ZoneContext
type FieldPattern = SkyTypes.FieldPattern

export type Accept = (position: Vector3, radius: number) -> boolean

export type BeamProps = {
	color: Color3,
	color1: Color3?,
	width: number,
	width1: number?,
	glow: number?, -- LightEmission 0..1
	transparency: number?,
	transparency1: number?,
	texture: string?,
	textureSpeed: number?,
	textureLength: number?,
	curve0: number?,
	curve1: number?,
	axis0: Vector3?, -- direction the curve leaves the first end (default down)
	axis1: Vector3?,
	segments: number?,
}

export type BridgeOptions = {
	glow: Color3,
	width: number?,
	startFlat: number?, -- flat stretch at the hub end
	endFlat: number?, -- flat landing at the far end
	stopAt: number?, -- 0..1: only build this much (a broken bridge)
	spacing: number?, -- distance between rail posts
	lights: boolean?,
}

local C = Palette.C
local UP = Vector3.yAxis

local Pieces = {}

-- Dressing helpers (plants, rocks, crystals, posts) ask this before
-- adding optional pieces. There's no part limit, so it's never over; the
-- calls stay so a per-zone cap could come back here.
function Pieces.overBudget(_parent: Instance): boolean
	return false
end

local function merge(base: { [string]: any }, extra: { [string]: any }?): { [string]: any }
	if extra then
		for key, value in extra do
			base[key] = value
		end
	end
	return base
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Basic shapes -----------------------------------------------------------------

-- Visual-only block: no collisions, no raycasts.
function Pieces.block(
	parent: Instance,
	cframe: CFrame,
	size: Vector3,
	color: Color3,
	material: Enum.Material?,
	extra: { [string]: any }?
): BasePart
	return Kit.decor(merge({
		CFrame = cframe,
		Size = size,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = parent,
	}, extra))
end

-- Collidable block people bump into (pillars, walls, trunks).
function Pieces.solid(
	parent: Instance,
	cframe: CFrame,
	size: Vector3,
	color: Color3,
	material: Enum.Material?,
	extra: { [string]: any }?
): BasePart
	return Kit.decor(merge({
		CFrame = cframe,
		Size = size,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		CanCollide = true,
		Parent = parent,
	}, extra))
end

function Pieces.wedge(
	parent: Instance,
	cframe: CFrame,
	size: Vector3,
	color: Color3,
	material: Enum.Material?,
	extra: { [string]: any }?
): BasePart
	return Kit.decor(merge({
		ClassName = "WedgePart",
		CFrame = cframe,
		Size = size,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = parent,
	}, extra))
end

-- Upright cylinder standing on `bottom`.
function Pieces.cylinder(
	parent: Instance,
	bottom: Vector3,
	height: number,
	diameter: number,
	color: Color3,
	material: Enum.Material?,
	extra: { [string]: any }?
): BasePart
	return Kit.cylinder(
		parent,
		bottom,
		height,
		diameter,
		merge({
			Color = color,
			Material = material or Enum.Material.SmoothPlastic,
			CanCollide = false,
		}, extra)
	)
end

function Pieces.ball(
	parent: Instance,
	center: Vector3,
	diameter: number,
	color: Color3,
	material: Enum.Material?,
	extra: { [string]: any }?
): BasePart
	return Kit.ball(
		parent,
		center,
		diameter,
		merge({
			Color = color,
			Material = material or Enum.Material.SmoothPlastic,
			CanCollide = false,
		}, extra)
	)
end

-- Round pipe from a to b.
function Pieces.pipe(
	parent: Instance,
	a: Vector3,
	b: Vector3,
	diameter: number,
	color: Color3,
	material: Enum.Material?,
	extra: { [string]: any }?
): BasePart
	return Kit.pipe(
		parent,
		a,
		b,
		diameter,
		merge({
			Color = color,
			Material = material or Enum.Material.SmoothPlastic,
			CanCollide = false,
		}, extra)
	)
end

-- A flat plank/leaf from a to b.
function Pieces.plank(
	parent: Instance,
	a: Vector3,
	b: Vector3,
	width: number,
	thickness: number,
	color: Color3,
	material: Enum.Material?
): BasePart
	return Pieces.block(
		parent,
		CFrame.lookAt((a + b) / 2, b),
		Vector3.new(width, thickness, (b - a).Magnitude),
		color,
		material
	)
end

-- Eight-point star prism (two squares, one turned 45 degrees) whose top
-- face is at `top`. The style's compass motif.
function Pieces.star(
	parent: Instance,
	top: Vector3,
	size: number,
	height: number,
	color: Color3,
	material: Enum.Material?,
	collide: boolean?,
	yaw: number?
): { BasePart }
	local base = CFrame.new(top - UP * (height / 2)) * CFrame.Angles(0, math.rad(yaw or 0), 0)
	local extra = { CanCollide = collide == true }
	return {
		Pieces.block(parent, base, Vector3.new(size, height, size), color, material, extra),
		Pieces.block(
			parent,
			base * CFrame.Angles(0, math.rad(45), 0),
			Vector3.new(size, height, size),
			color,
			material,
			extra
		),
	}
end

-- A cube balanced on its corner: gems, finials, crystal caps.
function Pieces.diamond(
	parent: Instance,
	center: Vector3,
	size: number,
	color: Color3,
	material: Enum.Material?
): BasePart
	return Pieces.block(
		parent,
		CFrame.new(center) * CFrame.Angles(math.rad(45), math.rad(20), math.rad(35.26)),
		Vector3.new(size, size, size),
		color,
		material or Enum.Material.Glass
	)
end

-- Lights and particles ------------------------------------------------

function Pieces.light(
	part: BasePart,
	color: Color3,
	range: number,
	brightness: number?,
	shadows: boolean?
): PointLight
	local light = Kit.light(part, color, range, brightness or 1, shadows)
	-- crystals and rune glows swell during storms
	light:AddTag(Pieces.STORM_GLOW)
	return light
end

function Pieces.spot(
	part: BasePart,
	color: Color3,
	range: number,
	brightness: number,
	angle: number,
	face: Enum.NormalId
): SpotLight
	return Kit.spotLight(part, color, range, brightness, angle, face)
end

function Pieces.emitter(part: BasePart, props: { [string]: any }): ParticleEmitter
	return Kit.emitter(part, props)
end

-- Soft sparkles drifting off a crystal.
function Pieces.sparkles(part: BasePart, color: Color3, rate: number?, size: number?)
	Pieces.emitter(part, {
		Name = "Sparkles",
		Texture = Kit.TEXTURES.sparkle,
		Color = ColorSequence.new(color),
		LightEmission = 1,
		LightInfluence = 0,
		Rate = rate or 4,
		Lifetime = NumberRange.new(1.5, 2.5),
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.3, size or 0.8),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Transparency = NumberSequence.new(0.2),
	})
end

-- Beams ------------------------------------------------------------------------

local function aim(a: Attachment, axis: Vector3?)
	local direction = axis or Vector3.new(0, -1, 0)
	a.Axis = direction
	a.SecondaryAxis = if math.abs(direction.Y) > 0.9 then Vector3.xAxis else UP
end

-- A beam between two world points with full control over its look. Built
-- with Kit.cable, then given the style's extras (gradients, textures,
-- curve directions).
function Pieces.beam(ctx: Context, a: Vector3, b: Vector3, props: BeamProps): Beam
	local glow = props.glow or 0
	local t0 = props.transparency or 0
	local beam = Kit.cable(ctx, a, b, {
		Color = props.color,
		Width = props.width,
		Segments = props.segments or 10,
		LightEmission = glow,
		Transparency = t0,
	})
	beam.Name = "Beam"
	beam.Color = ColorSequence.new(props.color, props.color1 or props.color)
	beam.Width1 = props.width1 or props.width
	beam.Transparency = NumberSequence.new(t0, props.transparency1 or t0)
	if props.texture then
		beam.Texture = props.texture
		beam.TextureSpeed = props.textureSpeed or 0
		beam.TextureLength = props.textureLength or 4
		beam.TextureMode = Enum.TextureMode.Wrap
	end
	local a0, a1 = beam.Attachment0, beam.Attachment1
	if a0 and a1 then
		aim(a0, props.axis0)
		aim(a1, props.axis1)
	end
	beam.CurveSize0 = props.curve0 or 0
	beam.CurveSize1 = props.curve1 or 0
	return beam
end

-- Ring of four curved beams (Bezier quarter circles) around `center` in
-- the plane of axisA/axisB.
function Pieces.ring(
	ctx: Context,
	center: Vector3,
	radius: number,
	axisA: Vector3,
	axisB: Vector3,
	_segments: number?,
	props: BeamProps
): { Beam }
	local beams = {}
	local k = radius * 0.5523
	for i = 0, 3 do
		local t0 = i * math.pi / 2
		local t1 = t0 + math.pi / 2
		local p0 = center + (axisA * math.cos(t0) + axisB * math.sin(t0)) * radius
		local p1 = center + (axisA * math.cos(t1) + axisB * math.sin(t1)) * radius
		local tan0 = -axisA * math.sin(t0) + axisB * math.cos(t0)
		local tan1 = -axisA * math.sin(t1) + axisB * math.cos(t1)
		local quarter = table.clone(props)
		quarter.axis0 = tan0
		quarter.axis1 = tan1
		quarter.curve0 = k
		quarter.curve1 = k
		quarter.segments = 12
		local beam = Pieces.beam(ctx, p0, p1, quarter)
		if beam then
			table.insert(beams, beam)
		end
	end
	return beams
end

-- Tags the client's storm controller can look for: StormGlow lights get
-- brighter during storms, StormArc beams flicker, StormCloud emitters
-- darken and speed up (see docs/styles/SkyIsles.md).
Pieces.STORM_GLOW = "StormGlow"
Pieces.STORM_ARC = "StormArc"
Pieces.STORM_CLOUD = "StormCloud"

-- Jagged lightning arc from a to b (tagged StormArc).
function Pieces.arc(
	ctx: Context,
	a: Vector3,
	b: Vector3,
	steps: number,
	jitter: number,
	props: BeamProps
)
	local previous = a
	for i = 1, steps do
		local t = i / steps
		local point = a:Lerp(b, t)
		if i < steps then
			point += Vector3.new(
				ctx.rng:NextNumber(-jitter, jitter),
				ctx.rng:NextNumber(-jitter, jitter),
				ctx.rng:NextNumber(-jitter, jitter)
			)
		end
		local beam = Pieces.beam(ctx, previous, point, props)
		if beam then
			beam:AddTag(Pieces.STORM_ARC)
		end
		previous = point
	end
end

-- Rune ring tagged as storm-reactive.
function Pieces.stormRing(
	ctx: Context,
	center: Vector3,
	radius: number,
	axisA: Vector3,
	axisB: Vector3,
	props: BeamProps
)
	for _, beam in Pieces.ring(ctx, center, radius, axisA, axisB, nil, props) do
		beam:AddTag(Pieces.STORM_ARC)
	end
end

-- A heavy iron tether with a sag. Every chain is recorded so the style can
-- check, after the build, that none of them runs through land.
type ChainRecord = { a: Vector3, b: Vector3, sag: number }

-- Kept on the ctx (one per build, shared by every module copy).
local function chainsOf(ctx: Context): { ChainRecord }
	local store = ctx :: any
	if not store.skyChains then
		store.skyChains = {}
	end
	return store.skyChains
end

function Pieces.chain(ctx: Context, a: Vector3, b: Vector3, sag: number)
	table.insert(chainsOf(ctx), { a = a, b = b, sag = sag })
	Pieces.beam(ctx, a, b, {
		color = C.iron,
		width = 1.1,
		curve0 = sag,
		curve1 = -sag,
		segments = 20,
	})
end

-- Forget recorded chains (start of a build).
function Pieces.resetChecks(ctx: Context)
	(ctx :: any).skyChains = {}
end

-- Sample every recorded chain against the ground the style laid; warns and
-- notes the count on the Map folder (attribute SkyBuriedChains) if any is
-- inside land, so a bad layout shows up in the build output.
function Pieces.checkChains(ctx: Context)
	local buried = 0
	for _, chain in chainsOf(ctx) do
		local down = UP * chain.sag
		local n = Ground.buried(ctx, chain.a, chain.a - down, chain.b - down, chain.b, 24)
		if n > 0 then
			buried += 1
			warn(
				string.format(
					"[SkyIsles] tether %s -> %s runs through land (%d samples)",
					tostring(chain.a),
					tostring(chain.b),
					n
				)
			)
		end
	end
	local map = ctx.folders.hub.Parent
	if map then
		map:SetAttribute("SkyBuriedChains", buried)
	end
end

-- Glowing rune cable (border fences, bridge rails).
function Pieces.runeCable(
	ctx: Context,
	a: Vector3,
	b: Vector3,
	color: Color3,
	sag: number?,
	width: number?
)
	Pieces.beam(ctx, a, b, {
		color = color,
		width = width or 0.28,
		glow = 1,
		curve0 = sag or 0.6,
		curve1 = -(sag or 0.6),
		segments = 8,
	})
end

-- A waterfall pouring off a lip into the clouds. The lip is pushed out
-- along `outward` until no ground is underneath it (past every coast lobe
-- and headland), and a water channel joins it back to the source, so the
-- water spills off the rim instead of out of the cliff. `lip` sits 0.6
-- below the surface the water runs on. Waterfalls are queued and built at
-- the end of the build (Pieces.flushWaterfalls), once every island is down.
function Pieces.waterfall(ctx: Context, lip: Vector3, outward: Vector3, drop: number, width: number)
	local store = ctx :: any
	store.skyFalls = store.skyFalls or {}
	table.insert(store.skyFalls, { lip = lip, outward = outward, drop = drop, width = width })
end

function Pieces.flushWaterfalls(ctx: Context)
	local store = ctx :: any
	for _, fall in store.skyFalls or {} do
		Pieces.buildWaterfall(ctx, fall.lip, fall.outward, fall.drop, fall.width)
	end
	store.skyFalls = {}
end

-- Returns false (and builds nothing) when no clear lip is found.
function Pieces.buildWaterfall(
	ctx: Context,
	lip: Vector3,
	outward: Vector3,
	drop: number,
	width: number
): boolean
	local out = flat(outward).Unit
	local mouth: Vector3? = nil
	for s = 0, 40, 2 do
		local p = lip + out * s
		if Ground.clearBelow(ctx, p - UP * 0.5, 30, 1.5) then
			mouth = p + out * 1
			break
		end
	end
	if not mouth then
		return false
	end
	local start = mouth :: Vector3
	-- the spill channel: a water strip over the land from source to mouth
	local length = (start - lip).Magnitude
	if length > 0.5 then
		local surface = (lip + start) / 2 + UP * 0.66
		Ground.water(
			ctx.folders.decor,
			Palette.WATER,
			CFrame.lookAt(surface, surface + out),
			Vector2.new(width * 0.8, length),
			"Spill"
		)
	end
	local bottom = start + out * 6 - UP * drop
	Pieces.beam(ctx, start, bottom, {
		color = C.seafoam,
		color1 = C.cloud,
		width = width,
		width1 = width * 1.8,
		glow = 0.25,
		transparency = 0.1,
		transparency1 = 1,
		texture = Kit.TEXTURES.smoke,
		textureSpeed = 0.6,
		textureLength = 10,
		curve0 = 5,
		axis0 = out,
		segments = 16,
	})
	Pieces.beam(ctx, start + UP * 0.2, bottom, {
		color = C.cream,
		width = width * 0.45,
		width1 = width,
		glow = 0.4,
		transparency = 0.2,
		transparency1 = 1,
		texture = Kit.TEXTURES.smoke,
		textureSpeed = 1.1,
		textureLength = 6,
		curve0 = 5,
		axis0 = out,
		segments = 16,
	})
	return true
end

-- Crystals -----------------------------------------------------------------------

-- A crystal shard rising from `bottom`: a square prism with a slanted tip,
-- turned `yaw` and leaning `tilt` degrees (tilt near 180 hangs it downward).
function Pieces.shard(
	parent: Instance,
	bottom: Vector3,
	height: number,
	width: number,
	color: Color3,
	yaw: number,
	tilt: number,
	material: Enum.Material?
): BasePart
	local base = CFrame.new(bottom)
		* CFrame.Angles(0, math.rad(yaw), 0)
		* CFrame.Angles(math.rad(tilt), 0, 0)
	local bodyHeight = height * 0.74
	local tipHeight = height - bodyHeight
	local mat = material or Enum.Material.Glass
	local body = Pieces.block(
		parent,
		base * CFrame.new(0, bodyHeight / 2, 0) * CFrame.Angles(0, math.rad(45), 0),
		Vector3.new(width, bodyHeight, width),
		color,
		mat,
		{ CastShadow = false }
	)
	Pieces.wedge(
		parent,
		base
			* CFrame.new(0, bodyHeight + tipHeight / 2 - 0.01, 0)
			* CFrame.Angles(0, math.rad(45), 0),
		Vector3.new(width, tipHeight, width),
		color,
		mat,
		{ CastShadow = false }
	)
	return body
end

-- A big crystal: glass shell with a glowing core.
function Pieces.bigShard(
	parent: Instance,
	bottom: Vector3,
	height: number,
	width: number,
	shell: Color3,
	core: Color3,
	yaw: number,
	tilt: number
): BasePart
	local body = Pieces.shard(parent, bottom, height, width, shell, yaw, tilt, Enum.Material.Glass)
	body.Transparency = 0.3
	body.Reflectance = 0.15
	local coreBase = CFrame.new(bottom)
		* CFrame.Angles(0, math.rad(yaw), 0)
		* CFrame.Angles(math.rad(tilt), 0, 0)
	Pieces.block(
		parent,
		coreBase * CFrame.new(0, height * 0.4, 0) * CFrame.Angles(0, math.rad(45), 0),
		Vector3.new(width * 0.45, height * 0.7, width * 0.45),
		core,
		Enum.Material.Neon,
		{ CastShadow = false }
	)
	return body
end

-- A cluster of 3-5 shards leaning out from `bottom`; returns the tallest.
function Pieces.cluster(
	parent: Instance,
	rng: Random,
	bottom: Vector3,
	size: number,
	color: Color3,
	count: number?,
	hanging: boolean?
): BasePart
	local n = if Pieces.overBudget(parent) then 1 else count or rng:NextInteger(3, 5)
	local main: BasePart? = nil
	for i = 1, n do
		local height = size * (if i == 1 then 1 else rng:NextNumber(0.4, 0.72))
		local width = height * rng:NextNumber(0.2, 0.28)
		local yaw = rng:NextNumber(0, 360)
		local lean = if i == 1 then rng:NextNumber(-6, 6) else rng:NextNumber(20, 40)
		local direction = CFrame.Angles(0, math.rad(yaw), 0):VectorToWorldSpace(Vector3.zAxis)
		local foot = bottom + (if i == 1 then Vector3.zero else direction * size * 0.12)
		local tilt = if hanging then 180 - lean else lean
		local shard = Pieces.shard(
			parent,
			foot,
			height,
			width,
			color,
			yaw,
			tilt,
			if i == 1 then Enum.Material.Neon else Enum.Material.Glass
		)
		if i == 1 then
			main = shard
		end
	end
	return main :: BasePart
end

-- Posts, lanterns, signs -----------------------------------------------------------

-- Stone rune post with a glowing crystal cap; returns the cable point.
function Pieces.runePost(
	parent: Instance,
	bottom: Vector3,
	height: number,
	color: Color3,
	facing: Vector3?,
	plinth: boolean?
): (Vector3, BasePart)
	local yaw = if facing then CFrame.lookAt(bottom, bottom + flat(facing)) else CFrame.new(bottom)
	local base = 0
	if plinth then
		Pieces.solid(
			parent,
			yaw * CFrame.new(0, 0.6, 0),
			Vector3.new(2, 1.2, 2),
			C.plum,
			Enum.Material.Slate
		)
		base = 1.2
	end
	local shaftHeight = height - 1 - base
	local shaft = Pieces.solid(
		parent,
		yaw * CFrame.new(0, base + shaftHeight / 2, 0),
		Vector3.new(if plinth then 1.3 else 1.5, shaftHeight, if plinth then 1.3 else 1.5),
		if plinth then C.skystone else C.skystoneDark,
		Enum.Material.Cobblestone
	)
	if not plinth then
		-- plain posts end in a rune-coloured slate top (no extra part)
		shaft.Color = C.skystoneDark:Lerp(color, 0.25)
		return bottom + UP * (height - 1.2), shaft
	end
	local cap =
		Pieces.diamond(parent, bottom + UP * (height - 0.4), 1.15, color, Enum.Material.Glass)
	return bottom + UP * (height - 0.9), cap
end

-- Hanging lantern: plum cap and base around a glowing core.
function Pieces.lantern(parent: Instance, center: Vector3, color: Color3, range: number?): BasePart
	Pieces.block(
		parent,
		CFrame.new(center + UP * 1),
		Vector3.new(1.5, 0.35, 1.5),
		C.plum,
		Enum.Material.Metal
	)
	local core = Pieces.block(
		parent,
		CFrame.new(center),
		Vector3.new(0.95, 1.6, 0.95),
		color,
		Enum.Material.Neon,
		{ CastShadow = false }
	)
	Pieces.block(
		parent,
		CFrame.new(center - UP * 0.95),
		Vector3.new(1.25, 0.3, 1.25),
		C.plum,
		Enum.Material.Metal
	)
	if range then
		Pieces.light(core, color, range, 1.3)
	end
	return core
end

-- Lamp post with an arm holding a lantern toward `facing`.
function Pieces.lampPost(
	parent: Instance,
	bottom: Vector3,
	height: number,
	color: Color3,
	facing: Vector3,
	range: number?
)
	local out = flat(facing).Unit
	Pieces.solid(
		parent,
		CFrame.new(bottom + UP * 0.4),
		Vector3.new(1.8, 0.8, 1.8),
		C.plum,
		Enum.Material.Slate
	)
	Pieces.cylinder(
		parent,
		bottom,
		height,
		0.8,
		C.plumDeep,
		Enum.Material.Metal,
		{ CanCollide = true }
	)
	local top = bottom + UP * height
	Pieces.plank(
		parent,
		top - UP * 0.3,
		top + out * 2.4 - UP * 0.3,
		0.4,
		0.4,
		C.plumDeep,
		Enum.Material.Metal
	)
	Pieces.diamond(parent, top + UP * 0.4, 0.8, C.gold, Enum.Material.Neon)
	Pieces.lantern(parent, top + out * 2.4 - UP * 1.6, color, range)
end

-- A framed board. The frame is thinner than the board, so text on either
-- face shows; backTitle puts different text on the back.
function Pieces.board(
	parent: Instance,
	cframe: CFrame,
	width: number,
	height: number,
	title: string,
	subtitle: string?,
	style: Kit.SignStyle,
	backTitle: string?,
	backSubtitle: string?
): BasePart
	Pieces.block(
		parent,
		cframe,
		Vector3.new(width + 0.9, height + 0.9, 0.4),
		C.gold,
		Enum.Material.Metal,
		{ Name = "SignFrame" }
	)
	local board = Kit.sign(parent, cframe, width, height, title, subtitle, style)
	if backTitle then
		Kit.faceText(board, Enum.NormalId.Back, backTitle, backSubtitle, style)
	end
	return board
end

-- A finger-post arrow board at `center` pointing along `direction`,
-- readable from both sides.
function Pieces.arrow(
	parent: Instance,
	center: Vector3,
	direction: Vector3,
	width: number,
	height: number,
	title: string,
	style: Kit.SignStyle
)
	local dir = flat(direction).Unit
	local frame = CFrame.fromMatrix(center, dir, UP)
	local board = Pieces.block(
		parent,
		frame,
		Vector3.new(width, height, 0.5),
		style.boardColor,
		style.boardMaterial,
		{ Name = "ArrowSign" }
	)
	Kit.faceText(board, Enum.NormalId.Front, title, nil, style)
	Kit.faceText(board, Enum.NormalId.Back, title, nil, style)
	local headLength = height * 0.9
	local headHeight = height + 1.2
	local tip = frame * CFrame.new(width / 2 + headLength / 2, 0, 0)
	Pieces.wedge(
		parent,
		tip * CFrame.new(0, headHeight / 4, 0) * CFrame.Angles(0, math.rad(-90), 0),
		Vector3.new(0.5, headHeight / 2, headLength),
		C.gold,
		Enum.Material.Metal
	)
	Pieces.wedge(
		parent,
		tip
			* CFrame.new(0, -headHeight / 4, 0)
			* CFrame.Angles(math.pi, 0, 0)
			* CFrame.Angles(0, math.rad(-90), 0),
		Vector3.new(0.5, headHeight / 2, headLength),
		C.gold,
		Enum.Material.Metal
	)
end

-- Rune gateway: two pillars with crystal tops, a stepped lintel and a
-- framed name board. `base` is on the ground at the middle, LookVector
-- toward the people who should read the front.
function Pieces.gateway(
	parent: Instance,
	base: CFrame,
	halfSpan: number,
	height: number,
	glow: Color3,
	title: string,
	subtitle: string?,
	backTitle: string?,
	backSubtitle: string?,
	lights: boolean?
)
	for side = -1, 1, 2 do
		local foot = base * CFrame.new(side * halfSpan, 0, 0)
		Pieces.solid(
			parent,
			foot * CFrame.new(0, 0.8, 0) * CFrame.Angles(0, math.rad(45), 0),
			Vector3.new(3.4, 1.6, 3.4),
			C.plum,
			Enum.Material.Slate
		)
		local shaft = height - 3
		Pieces.solid(
			parent,
			foot * CFrame.new(0, 1.6 + shaft / 2, 0),
			Vector3.new(2.4, shaft, 2.4),
			C.skystone,
			Enum.Material.Cobblestone
		)
		Pieces.solid(
			parent,
			foot * CFrame.new(0, height - 0.7, 0) * CFrame.Angles(0, math.rad(45), 0),
			Vector3.new(3.2, 1.4, 3.2),
			C.cream,
			Enum.Material.Marble
		)
		local lamp = Pieces.lantern(
			parent,
			(foot * CFrame.new(0, height * 0.62, -2.1)).Position,
			glow,
			if lights then 16 else nil
		)
		lamp.Name = "GateLantern"
	end
	Pieces.solid(
		parent,
		base * CFrame.new(0, height + 0.9, 0),
		Vector3.new(halfSpan * 2 + 4.4, 1.8, 2.8),
		C.plum,
		Enum.Material.Slate
	)
	-- a pointed gable over the lintel: two leaning slabs meeting at the top
	for side = -1, 1, 2 do
		local half = halfSpan + 1.2
		Pieces.block(
			parent,
			base
				* CFrame.new(side * half / 2, height + 2.6, 0)
				* CFrame.Angles(0, 0, -side * math.rad(20)),
			Vector3.new(half / math.cos(math.rad(20)) + 0.6, 1.2, 2.2),
			C.skystone,
			Enum.Material.Cobblestone
		)
	end
	Pieces.block(
		parent,
		base
			* CFrame.new(0, height + 3.4 + (halfSpan + 1.2) * math.tan(math.rad(20)) / 2, 0)
			* CFrame.Angles(0, 0, math.rad(45)),
		Vector3.new(2.4, 2.4, 2.6),
		glow,
		Enum.Material.Neon,
		{ CastShadow = false }
	)
	Pieces.board(
		parent,
		base * CFrame.new(0, height - 3.4, -0.2),
		halfSpan * 2 - 2.8,
		4.4,
		title,
		subtitle,
		Palette.signFor(glow),
		backTitle,
		backSubtitle
	)
end

-- Rune bridge from `from` to `to` (both on the walking surface): stone
-- deck with curbs, a glowing centre inlay, rail posts on the curbs joined
-- by a solid stone handrail (the border that keeps players on the bridge)
-- with a glowing rune cable along it, and a keel underneath. Flat at both
-- ends, ramp between.
function Pieces.bridge(
	ctx: Context,
	parent: Instance,
	from: Vector3,
	to: Vector3,
	opts: BridgeOptions
)
	local span = flat(to - from)
	local run = span.Magnitude
	local dir = span.Unit
	local right = dir:Cross(UP)
	local width = opts.width or 12
	local startFlat = math.min(opts.startFlat or 4, run * 0.25)
	local endFlat = math.min(opts.endFlat or 12, run * 0.35)
	local stop = run * (opts.stopAt or 1)

	local function pointAt(s: number): Vector3
		local y
		if s <= startFlat then
			y = from.Y
		elseif s >= run - endFlat then
			y = to.Y
		else
			y = from.Y + (to.Y - from.Y) * (s - startFlat) / (run - endFlat - startFlat)
		end
		local p = from + dir * s
		return Vector3.new(p.X, y, p.Z)
	end

	local breaks = { 0, startFlat, run - endFlat, run }
	for i = 1, 3 do
		local s0, s1 = breaks[i], math.min(breaks[i + 1], stop)
		if s1 - s0 > 0.05 then
			local p, q = pointAt(s0), pointAt(s1)
			Kit.walkway(parent, p, q, width, 1.4, {
				Name = "BridgeDeck",
				Color = C.skystone,
				Material = Enum.Material.Cobblestone,
			})
			for side = -1, 1, 2 do
				local offset = right * side * (width / 2 - 0.5)
				Kit.walkway(parent, p + offset + UP * 0.9, q + offset + UP * 0.9, 1, 1.8, {
					Name = "BridgeCurb",
					Color = C.plum,
					Material = Enum.Material.Slate,
				})
			end
			Kit.walkway(parent, p + UP * 0.12, q + UP * 0.12, 0.8, 0.3, {
				Name = "BridgeRune",
				Color = opts.glow,
				Material = Enum.Material.Neon,
				CanCollide = false,
				CanQuery = false,
				CastShadow = false,
			})
			Pieces.block(
				parent,
				CFrame.lookAt((p + q) / 2, q)
					* CFrame.new(0, -2.7, 0)
					* CFrame.Angles(0, 0, math.rad(45)),
				Vector3.new(3.2, 3.2, (q - p).Magnitude),
				C.skystoneDark,
				Enum.Material.Slate
			)
		end
	end

	-- a lantern hanging under the middle of the span, and rune stones
	-- drifting beside it
	if stop >= run * 0.6 and run > 30 then
		local middle = pointAt(run / 2)
		local lamp = Pieces.lantern(
			parent,
			middle - UP * 6.5,
			opts.glow,
			if opts.lights == false then nil else 20
		)
		lamp.Name = "BridgeLantern"
		Pieces.beam(ctx, middle - UP * 1.4, middle - UP * 5.4, { color = C.iron, width = 0.2 })
		for side = -1, 1, 2 do
			local s = run * (0.5 + side * 0.18)
			local stoneAt = pointAt(s) + right * side * (width / 2 + 5) - UP * 3
			local stone = Pieces.block(
				parent,
				CFrame.lookAt(stoneAt, stoneAt + dir) * CFrame.Angles(0.2 * side, 0.3, 0.15),
				Vector3.new(2.6, 3.6, 1.2),
				C.skystone,
				Enum.Material.Cobblestone
			)
			Pieces.block(
				parent,
				stone.CFrame * CFrame.new(0, 0, -0.62),
				Vector3.new(0.8, 2, 0.1),
				opts.glow,
				Enum.Material.Neon
			)
		end
	end

	-- rail posts on the curbs every `spacing` studs and at both bends of
	-- the ramp, so the handrail between them follows the deck exactly
	local spacing = opts.spacing or 16
	local last = math.min(run, stop) - 0.5
	local marks: { number } = { startFlat, run - endFlat, last }
	local s = 1
	while s < last do
		table.insert(marks, s)
		s += spacing
	end
	table.sort(marks)
	local posts: { number } = {}
	for _, mark in marks do
		if mark >= 1 and mark <= last and (#posts == 0 or mark - posts[#posts] >= 3) then
			table.insert(posts, mark)
		end
	end
	local previous: { [number]: Vector3 } = {}
	for k, at in posts do
		local deck = pointAt(at)
		for side = -1, 1, 2 do
			local foot = deck + right * side * (width / 2 - 0.5) + UP * 0.9
			local shaft = Pieces.solid(
				parent,
				CFrame.lookAt(foot + UP * 1.5, foot + UP * 1.5 + dir),
				Vector3.new(1, 3, 1),
				C.skystoneLight,
				Enum.Material.Cobblestone
			)
			shaft.Name = "RailPost"
			if opts.lights ~= false and k % 3 == 1 and side == 1 then
				Pieces.light(shaft, opts.glow, 14, 1)
			end
			local top = foot + UP * 2.6
			local before = previous[side]
			if before then
				local rail = Pieces.solid(
					parent,
					CFrame.lookAt((before + top) / 2, top),
					Vector3.new(0.7, 0.6, (top - before).Magnitude + 0.7),
					C.skystoneLight,
					Enum.Material.Cobblestone
				)
				rail.Name = "BridgeRail"
				Pieces.runeCable(ctx, before + UP * 0.42, top + UP * 0.42, opts.glow, 0.05, 0.22)
			end
			previous[side] = top
		end
	end
end

-- Plants and props ------------------------------------------------------------------

-- Palm tree; `away` makes the trunk lean that way (off a field).
function Pieces.palm(parent: Instance, rng: Random, bottom: Vector3, height: number, away: Vector3?)
	if Pieces.overBudget(parent) then
		return
	end
	local lean = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
	if away then
		lean = flat(away).Unit + lean * 0.35
	end
	lean = if lean.Magnitude > 0.01 then lean.Unit else Vector3.xAxis
	local point = bottom
	local segments = 2
	for i = 1, segments do
		local nextPoint = point + (UP + lean * (0.3 * i)).Unit * (height / segments)
		Pieces.pipe(
			parent,
			point,
			nextPoint + (nextPoint - point).Unit * 0.3,
			1.6 - i * 0.25,
			if i % 2 == 0 then C.wood else C.woodLight,
			Enum.Material.Wood,
			{ CanCollide = true }
		)
		point = nextPoint
	end
	Pieces.ball(parent, point, 1.9, C.wood, Enum.Material.Wood)
	local fronds = 4
	for k = 1, fronds do
		local angle = k / fronds * math.pi * 2 + rng:NextNumber(-0.25, 0.25)
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local length = height * rng:NextNumber(0.36, 0.46)
		local tip = point + out * length - UP * length * rng:NextNumber(0.3, 0.5)
		Pieces.plank(
			parent,
			point + UP * 0.3,
			tip,
			3,
			0.25,
			if k % 2 == 0 then C.meadow else C.meadowDark,
			Enum.Material.Grass
		)
	end
	local angle = rng:NextNumber(0, math.pi * 2)
	Pieces.ball(
		parent,
		point + Vector3.new(math.cos(angle) * 0.9, -0.9, math.sin(angle) * 0.9),
		1.2,
		C.wood,
		Enum.Material.Wood
	)
end

-- Round-canopied tree (storm blossom): trunk and three canopy balls.
function Pieces.blossomTree(
	parent: Instance,
	rng: Random,
	bottom: Vector3,
	height: number,
	colors: { Color3 }
)
	if Pieces.overBudget(parent) then
		return
	end
	local top = bottom + UP * height * 0.62
	Pieces.pipe(parent, bottom, top, 1.4, C.wood, Enum.Material.Wood, { CanCollide = true })
	for k = 1, 3 do
		local angle = k / 3 * math.pi * 2 + rng:NextNumber(0, 1)
		local center = top
			+ Vector3.new(math.cos(angle), 0, math.sin(angle)) * height * 0.16
			+ UP * height * rng:NextNumber(0.08, 0.26)
		Pieces.ball(
			parent,
			center,
			height * rng:NextNumber(0.42, 0.55),
			colors[(k - 1) % #colors + 1],
			Enum.Material.Grass
		)
	end
end

function Pieces.bush(parent: Instance, rng: Random, bottom: Vector3, size: number, color: Color3)
	if Pieces.overBudget(parent) then
		return
	end
	for k = 1, 2 do
		local offset = Vector3.new(rng:NextNumber(-0.4, 0.4), 0, rng:NextNumber(-0.4, 0.4)) * size
		Pieces.ball(
			parent,
			bottom + offset + UP * size * 0.3,
			size * rng:NextNumber(0.7, 1),
			if k == 1 then color else color:Lerp(Color3.new(0, 0, 0), 0.15),
			Enum.Material.Grass
		)
	end
end

-- A few tiny flowers in the given colours.
function Pieces.flowers(
	parent: Instance,
	rng: Random,
	bottom: Vector3,
	colors: { Color3 },
	count: number?
)
	if Pieces.overBudget(parent) then
		return
	end
	for k = 1, count or 3 do
		local offset = Vector3.new(rng:NextNumber(-1.5, 1.5), 0, rng:NextNumber(-1.5, 1.5))
		Pieces.ball(
			parent,
			bottom + offset + UP * 0.45,
			rng:NextNumber(0.7, 1.1),
			colors[(k - 1) % #colors + 1],
			Enum.Material.SmoothPlastic
		)
	end
end

function Pieces.rocks(parent: Instance, rng: Random, bottom: Vector3, size: number, color: Color3?)
	if Pieces.overBudget(parent) then
		return
	end
	Blocks.rock(
		parent,
		color or C.skystone,
		bottom - UP * size * 0.1,
		size * (0.9 + rng:NextNumber() * 0.2)
	)
end

-- Ground landforms (block-built, in Map.Ground) -----------------------------------

-- A headland: a round lobe of land whose cap sits at `floor` (cap over
-- soil over a short tapering underside) pushing an island's coast out
-- where a landmark or prop needs room. Same tones as the island it joins,
-- so the caps merge into one surface.
function Pieces.headland(
	ctx: Context,
	center: Vector3,
	radius: number,
	floor: number,
	tones: Ground.Tones
)
	local yaw = ctx.rng:NextNumber(0, math.pi)
	Ground.isle(
		ctx,
		tones,
		CFrame.new(center.X, floor, center.Z) * CFrame.Angles(0, yaw, 0),
		radius,
		radius + 8,
		{ sides = 12, soil = 7, tiers = 1 }
	)
end

-- A tilted rock slab: a turned block standing on the ground at `center`
-- (only X/Z used), from `bottom` up to about `top`, turned `yaw` degrees
-- off `outward` and leaning `tilt` degrees away along `outward`.
function Pieces.slabRock(
	ctx: Context,
	center: Vector3,
	outward: Vector3,
	halfWidth: number,
	halfDepth: number,
	top: number,
	bottom: number,
	tilt: number,
	yaw: number,
	color: Color3
)
	local out = flat(outward).Unit
	local height = top - bottom
	local middle = Vector3.new(center.X, (top + bottom) / 2, center.Z)
	local frame = CFrame.lookAt(middle, middle + out)
		* CFrame.Angles(0, math.rad(yaw), 0)
		* CFrame.Angles(-math.rad(tilt), 0, 0)
	Ground.box(ctx, color, frame, Vector3.new(halfWidth * 2, height, halfDepth * 2), "Slab")
end

-- A rock spire: stacked blocks shrinking upward, each turned 45 degrees
-- from the last and drifting along `lean`, rooted below `foot`.
function Pieces.spire(
	ctx: Context,
	foot: Vector3,
	height: number,
	radius: number,
	lean: Vector3,
	colors: { Color3 }
)
	local count = 4
	local drift = flat(lean)
	local root = 6
	local y = -root
	for i = 1, count do
		local t = (i - 1) / count
		local h = (if i == 1 then height / count + root else height / count)
		local w = radius * 2 * (1 - 0.2 * (i - 1))
		local center = foot + drift * (t * t * 4) + UP * (y + h / 2)
		Ground.box(
			ctx,
			colors[(i - 1) % #colors + 1],
			CFrame.new(center) * CFrame.Angles(0, (i - 1) * math.pi / 4, 0),
			Vector3.new(w, h, w),
			"Spire"
		)
		y += h
	end
end

-- A stepped mound standing on the ground at `center`: a wide star of
-- `color` from below the soil up to `top`, with an optional `crown` block
-- on top. Dunes, hills and knolls.
function Pieces.mound(
	ctx: Context,
	center: Vector3,
	radius: number,
	floor: number,
	top: number,
	color: Color3,
	crown: Color3?
)
	local yaw = CFrame.Angles(0, ctx.rng:NextNumber(0, math.pi / 2), 0)
	local base = top - (if crown then 1.4 else 0)
	local bottom = floor - 8
	Ground.star(
		ctx,
		color,
		CFrame.new(center.X, base, center.Z) * yaw,
		radius * 1.5,
		base - bottom,
		"Mound"
	)
	if crown then
		Ground.box(
			ctx,
			crown,
			-- 0.05 up so a neighbour built to the same `top` can't share its plane
			CFrame.new(center.X, top - 0.75, center.Z)
				* yaw
				* CFrame.Angles(0, math.pi / 8, 0),
			Vector3.new(radius * 0.95, 1.6, radius * 0.95),
			"Crown"
		)
	end
end

-- A natural arch from a to b (ground points) whose span tops out `rise`
-- studs above `floor`: two legs, a banded lintel and haunches under it.
function Pieces.arch(
	ctx: Context,
	a: Vector3,
	b: Vector3,
	floor: number,
	rise: number,
	color: Color3,
	band: Color3
)
	local p = Vector3.new(a.X, floor, a.Z)
	local q = Vector3.new(b.X, floor, b.Z)
	local length = (q - p).Magnitude
	local frame = CFrame.lookAt(p, q)
	local leg = 5
	for _, s in { 0, length } do
		Ground.box(
			ctx,
			color,
			frame * CFrame.new(0, (rise - 2) / 2, -s),
			Vector3.new(leg, rise + 2, leg),
			"Arch"
		)
	end
	Ground.box(
		ctx,
		band,
		frame * CFrame.new(0, rise, -length / 2),
		Vector3.new(leg - 0.6, 4, length + leg),
		"Arch"
	)
	-- haunches: upside-down wedges, tall end against each leg
	local span = length - leg
	local reach = math.min(5, span / 2 - 1)
	if reach > 1 then
		Ground.wedge(
			ctx,
			color,
			frame * CFrame.new(0, rise - 4, -leg / 2 - reach / 2) * CFrame.Angles(0, 0, math.pi),
			Vector3.new(leg - 1, 4, reach),
			"Arch"
		)
		Ground.wedge(
			ctx,
			color,
			frame
				* CFrame.new(0, rise - 4, -length + leg / 2 + reach / 2)
				* CFrame.Angles(0, math.pi, math.pi),
			Vector3.new(leg - 1, 4, reach),
			"Arch"
		)
	end
end

-- A flush turf tile (a flat square patch of grass, ochre or sand) on the
-- ground at `center`: decoration, not collidable.
function Pieces.turf(parent: Instance, center: Vector3, radius: number, color: Color3, yaw: number)
	Pieces.block(
		parent,
		CFrame.new(center + UP * 0.05) * CFrame.Angles(0, math.rad(yaw), 0),
		Vector3.new(radius * 1.5, 0.5, radius * 1.5),
		color,
		Enum.Material.SmoothPlastic,
		{ CastShadow = false, Name = "Turf" }
	)
end

-- Placement guards ----------------------------------------------------------------

local function allZones(ctx: Context): { ZoneContext }
	local all = table.clone(ctx.zones)
	table.insert(all, ctx.teaser)
	return all
end
Pieces.allZones = allZones

-- Where a zone's hero landmark goes: the first clear spot of back centre,
-- back corners and side headlands (`back` studs off the footprint), first
-- at full size and then at 3/4 size. Returns the spot and the scale, or nil
-- after a warning (and the Map attribute SkyMissingHeroes) when nothing fits.
function Pieces.heroSpot(
	ctx: Context,
	zone: ZoneContext,
	radius: number,
	back: number
): (Vector3?, number)
	local slot = zone.slot
	local hw, hd = slot.width / 2, slot.depth / 2
	local diagonal = back * 0.75
	local candidates = {
		Vector3.new(0, 0, hd + back),
		Vector3.new(hw + diagonal, 0, hd + diagonal),
		Vector3.new(-(hw + diagonal), 0, hd + diagonal),
		Vector3.new(hw + back, 0, hd * 0.2),
		Vector3.new(-(hw + back), 0, hd * 0.2),
	}
	for _, scale in { 1, 0.75 } do
		for _, l in candidates do
			local p = slot.frame:PointToWorldSpace(l)
			if Pieces.clearOf(ctx, p, radius * scale, zone) then
				return p, scale
			end
		end
	end
	warn(string.format("[SkyIsles] no room for the hero landmark of zone %s", zone.folder.Name))
	local map = ctx.folders.hub.Parent
	if map then
		local missing = map:GetAttribute("SkyMissingHeroes")
		map:SetAttribute("SkyMissingHeroes", (if type(missing) == "number" then missing else 0) + 1)
	end
	return nil, 0
end

-- Horizontal distance from p to the segment a-b.
function Pieces.segmentDistance(p: Vector3, a: Vector3, b: Vector3): number
	local ap = Vector2.new(p.X - a.X, p.Z - a.Z)
	local ab = Vector2.new(b.X - a.X, b.Z - a.Z)
	local t = math.clamp(ap:Dot(ab) / math.max(ab:Dot(ab), 1e-6), 0, 1)
	return (ap - ab * t).Magnitude
end

-- Horizontal distance from p to a zone's footprint rectangle (0 inside).
local function slotDistance(slot: WorldTypes.Slot, p: Vector3): number
	local l = slot.frame:PointToObjectSpace(Vector3.new(p.X, slot.floor, p.Z))
	local dx = math.max(math.abs(l.X) - slot.width / 2, 0)
	local dz = math.max(math.abs(l.Z) - slot.depth / 2, 0)
	return math.sqrt(dx * dx + dz * dz)
end

function Pieces.footprintDistance(zone: ZoneContext, p: Vector3): number
	return slotDistance(zone.slot, p)
end

-- Is a disc (centre p, radius r) clear of every other zone's footprint,
-- of every Research Camp pad (its sign and its way in), of every connector
-- corridor and (with hubPad) of the hub plaza?
function Pieces.clearOf(
	ctx: Context,
	p: Vector3,
	r: number,
	own: ZoneContext?,
	hubPad: number?
): boolean
	for _, zone in allZones(ctx) do
		if zone ~= own and Pieces.footprintDistance(zone, p) < r + 3 then
			return false
		end
		local slot = zone.slot
		if slotDistance(Layout.campFootprint(slot), p) < r + 1.5 then
			return false
		end
		if Pieces.segmentDistance(p, slot.hubExit.Position, slot.gate.Position) < r + 7 then
			return false
		end
	end
	if hubPad and Vector2.new(p.X, p.Z).Magnitude - r < ctx.layout.hubRadius + hubPad then
		return false
	end
	return true
end

-- Ground directions of the first `count` spiral slots (current and future lanes).
function Pieces.laneDirections(ctx: Context, count: number): { Vector3 }
	local layout = ctx.layout
	local directions = {}
	for k = 1, count do
		table.insert(
			directions,
			Layout.direction(math.rad(layout.firstAngle + (k - 1) * layout.angleStep))
		)
	end
	return directions
end

-- Is a disc clear of every lane ray leaving the hub (current and future)?
function Pieces.offLanes(ctx: Context, p: Vector3, r: number, halfWidth: number): boolean
	local point = flat(p)
	for _, direction in Pieces.laneDirections(ctx, 12) do
		local along = point:Dot(direction)
		if along > 0 then
			local lateral = (point - direction * along).Magnitude
			if lateral < halfWidth + r then
				return false
			end
		end
	end
	return true
end

-- Catch floor carpet ---------------------------------------------------------------

-- Patterns a zone's floor with flush bands or tiles. Their tops sit 0.18
-- above the ground floor: under the warning circles and inside the
-- catch-floor rule (nothing above floor + 0.3). Not collidable.
function Pieces.field(parent: Instance, zone: ZoneContext, pattern: FieldPattern)
	local slot = zone.slot
	local frame = slot.frame
	local W, D = slot.width, slot.depth
	local thickness = 0.36
	local y = 0.18 - thickness / 2
	local colors, materials = pattern.colors, pattern.materials
	local function tile(cframe: CFrame, size: Vector3, index: number)
		Pieces.block(
			parent,
			cframe,
			size,
			colors[(index - 1) % #colors + 1],
			materials[(index - 1) % #materials + 1],
			{ CastShadow = false, Name = "FieldTile" }
		)
	end
	-- chunky stepped frame: a 4-stud rim of alternating zone-colour tiles,
	-- with clipped corners; the pattern fills the inside
	local F = 4
	local IW, ID = W - 2 * F, D - 2 * F
	if pattern.kind == "bands" then
		local acrossX = pattern.axis == "x"
		local length = if acrossX then IW else ID
		local span = if acrossX then ID else IW
		local widths = pattern.widths or { 1 }
		local n = math.max(2, math.round(length / pattern.size))
		local total = 0
		for i = 1, n do
			total += widths[(i - 1) % #widths + 1]
		end
		local position = -length / 2
		for i = 1, n do
			local w = widths[(i - 1) % #widths + 1] / total * length
			local middle = position + w / 2
			if acrossX then
				tile(frame * CFrame.new(middle, y, 0), Vector3.new(w, thickness, span), i)
			else
				tile(frame * CFrame.new(0, y, middle), Vector3.new(span, thickness, w), i)
			end
			position += w
		end
	elseif pattern.kind == "rings" then
		-- concentric rectangular bands, ripple-like, readable from afar
		local hw, hd = IW / 2, ID / 2
		local s = pattern.size
		local index = 1
		while hw > s * 1.5 and hd > s * 1.5 do
			tile(frame * CFrame.new(0, y, -hd + s / 2), Vector3.new(hw * 2, thickness, s), index)
			tile(frame * CFrame.new(0, y, hd - s / 2), Vector3.new(hw * 2, thickness, s), index)
			tile(
				frame * CFrame.new(-hw + s / 2, y, 0),
				Vector3.new(s, thickness, hd * 2 - 2 * s),
				index
			)
			tile(
				frame * CFrame.new(hw - s / 2, y, 0),
				Vector3.new(s, thickness, hd * 2 - 2 * s),
				index
			)
			hw -= s
			hd -= s
			index += 1
		end
		tile(frame * CFrame.new(0, y, 0), Vector3.new(hw * 2, thickness, hd * 2), index)
	else
		local nx = math.max(2, math.round(IW / pattern.size))
		local nz = math.max(2, math.round(ID / pattern.size))
		local sx, sz = IW / nx, ID / nz
		for i = 0, nx - 1 do
			for j = 0, nz - 1 do
				tile(
					frame * CFrame.new(-IW / 2 + (i + 0.5) * sx, y, -ID / 2 + (j + 0.5) * sz),
					Vector3.new(sx, thickness, sz),
					(i + j) % 2 + 1
				)
			end
		end
	end
	-- the frame: stepped tiles in two zone tones along each edge
	local dark = zone.color:Lerp(Color3.new(0, 0, 0), 0.35)
	local frameY = 0.2 - thickness / 2
	local CORNER = 8
	local function frameRun(along: number, fixed: number, alongX: boolean)
		local length = along - 2 * CORNER
		local n = math.max(1, math.round(length / 8))
		local seg = length / n
		for k = 0, n - 1 do
			local m = -length / 2 + (k + 0.5) * seg
			local cf = if alongX then CFrame.new(m, frameY, fixed) else CFrame.new(fixed, frameY, m)
			local size = if alongX
				then Vector3.new(seg, thickness, F)
				else Vector3.new(F, thickness, seg)
			Pieces.block(
				parent,
				frame * cf,
				size,
				if k % 2 == 0 then zone.color else dark,
				Enum.Material.SmoothPlastic,
				{ CastShadow = false, Name = "FieldFrame" }
			)
		end
	end
	frameRun(W, -D / 2 + F / 2, true)
	frameRun(W, D / 2 - F / 2, true)
	frameRun(D, -W / 2 + F / 2, false)
	frameRun(D, W / 2 - F / 2, false)
	-- clipped corners: a dark square block with a zone-colour triangle cut
	for _, sign in
		{
			Vector3.new(1, 0, 1),
			Vector3.new(-1, 0, 1),
			Vector3.new(1, 0, -1),
			Vector3.new(-1, 0, -1),
		}
	do
		local c = Vector3.new(sign.X * (W / 2 - CORNER / 2), frameY, sign.Z * (D / 2 - CORNER / 2))
		Pieces.block(
			parent,
			frame * CFrame.new(c),
			Vector3.new(CORNER, thickness, CORNER),
			C.plumDeep,
			Enum.Material.SmoothPlastic,
			{ CastShadow = false, Name = "FieldCorner" }
		)
		-- a flat wedge (triangle in plan view) pointing into the field
		local yaw = math.atan2(-sign.X, -sign.Z)
		Pieces.wedge(
			parent,
			frame
				* CFrame.new(c + Vector3.new(0, 0.03, 0))
				* CFrame.Angles(0, yaw + math.pi / 4, 0)
				* CFrame.Angles(0, 0, math.pi / 2),
			Vector3.new(thickness, CORNER * 0.7, CORNER * 0.7),
			zone.color,
			Enum.Material.Neon,
			{ CastShadow = false, Name = "FieldCornerGlow" }
		)
	end
	-- glowing line on the frame's inner edge
	local line = 0.6
	local lineY = 0.24 - 0.2
	local edges: { { cframe: CFrame, size: Vector3 } } = {
		{ cframe = CFrame.new(0, lineY, -ID / 2), size = Vector3.new(IW, 0.4, line) },
		{ cframe = CFrame.new(0, lineY, ID / 2), size = Vector3.new(IW, 0.4, line) },
		{ cframe = CFrame.new(-IW / 2, lineY, 0), size = Vector3.new(line, 0.4, ID) },
		{ cframe = CFrame.new(IW / 2, lineY, 0), size = Vector3.new(line, 0.4, ID) },
	}
	for _, edge in edges do
		Pieces.block(
			parent,
			frame * edge.cframe,
			edge.size,
			C.cream,
			Enum.Material.Neon,
			{ CastShadow = false, Name = "FieldEdge" }
		)
	end
end

return Pieces
