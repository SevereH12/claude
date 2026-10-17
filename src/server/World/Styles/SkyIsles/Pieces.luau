--!strict
-- SkyIsles building pieces: the style's own kit, built on the framework Kit
-- with colours from Palette. Everything takes world positions and works at
-- any slot position or rotation, so zone themes stack automatically.

local ServerScriptService = game:GetService("ServerScriptService")

local World = ServerScriptService.Server.World
local Kit = require(World.Kit)
local Layout = require(World.Layout)
local WorldTypes = require(World.Types)
local Palette = require(script.Parent.Palette)
local SkyTypes = require(script.Parent.SkyTypes)
local Terra = require(script.Parent.Terra)

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

-- Performance budgets for the whole world.
local MAX_LIGHTS = 86
local MAX_EMITTERS = 24

local Pieces = {}

-- Spends one unit of a per-world budget, counted on the Map folder so the
-- count is shared by every module and resets with each new map.
local function spend(part: Instance, key: string, limit: number): boolean
	local map = part:FindFirstAncestor("Map")
	if not map then
		return true
	end
	local used = map:GetAttribute(key)
	local count = if type(used) == "number" then used else 0
	if count >= limit then
		return false
	end
	map:SetAttribute(key, count + 1)
	return true
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
		material or Enum.Material.Neon
	)
end

-- Lights and particles (budgeted) ---------------------------------------------

function Pieces.light(
	part: BasePart,
	color: Color3,
	range: number,
	brightness: number?,
	shadows: boolean?
): PointLight?
	if not spend(part, "SkyLights", MAX_LIGHTS) then
		return nil
	end
	return Kit.light(part, color, range, brightness or 1, shadows)
end

function Pieces.spot(
	part: BasePart,
	color: Color3,
	range: number,
	brightness: number,
	angle: number,
	face: Enum.NormalId
): SpotLight?
	if not spend(part, "SkyLights", MAX_LIGHTS) then
		return nil
	end
	return Kit.spotLight(part, color, range, brightness, angle, face)
end

function Pieces.emitter(part: BasePart, props: { [string]: any }): ParticleEmitter?
	if not spend(part, "SkyEmitters", MAX_EMITTERS) then
		return nil
	end
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

local function attachment(anchor: BasePart, position: Vector3, axis: Vector3?): Attachment
	local a = Instance.new("Attachment")
	a.Name = "BeamEnd"
	a.Position = anchor.CFrame:PointToObjectSpace(position)
	local direction = axis or Vector3.new(0, -1, 0)
	a.Axis = direction
	a.SecondaryAxis = if math.abs(direction.Y) > 0.9 then Vector3.xAxis else UP
	a.Parent = anchor
	return a
end

-- A beam between two world points with full control over its look.
function Pieces.beam(ctx: Context, a: Vector3, b: Vector3, props: BeamProps): Beam
	local anchor = ctx.cableAnchor
	local beam = Instance.new("Beam")
	beam.Name = "Beam"
	beam.Attachment0 = attachment(anchor, a, props.axis0)
	beam.Attachment1 = attachment(anchor, b, props.axis1)
	beam.Color = ColorSequence.new(props.color, props.color1 or props.color)
	beam.Width0 = props.width
	beam.Width1 = props.width1 or props.width
	beam.FaceCamera = true
	beam.Segments = props.segments or 10
	local glow = props.glow or 0
	beam.LightEmission = glow
	beam.LightInfluence = if glow > 0 then 0 else 1
	local t0 = props.transparency or 0
	beam.Transparency = NumberSequence.new(t0, props.transparency1 or t0)
	if props.texture then
		beam.Texture = props.texture
		beam.TextureSpeed = props.textureSpeed or 0
		beam.TextureLength = props.textureLength or 4
		beam.TextureMode = Enum.TextureMode.Wrap
	end
	beam.CurveSize0 = props.curve0 or 0
	beam.CurveSize1 = props.curve1 or 0
	beam.Parent = anchor
	return beam
end

-- Ring of straight beam segments around `center` in the plane of axisA/axisB.
function Pieces.ring(
	ctx: Context,
	center: Vector3,
	radius: number,
	axisA: Vector3,
	axisB: Vector3,
	segments: number,
	props: BeamProps
)
	for i = 0, segments - 1 do
		local t0 = i / segments * math.pi * 2
		local t1 = (i + 1) / segments * math.pi * 2
		local p0 = center + (axisA * math.cos(t0) + axisB * math.sin(t0)) * radius
		local p1 = center + (axisA * math.cos(t1) + axisB * math.sin(t1)) * radius
		Pieces.beam(ctx, p0, p1, props)
	end
end

-- Jagged lightning arc from a to b.
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
		Pieces.beam(ctx, previous, point, props)
		previous = point
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

-- Sample every recorded chain against the terrain the style laid; warns and
-- notes the count on the Map folder (attribute SkyBuriedChains) if any is
-- inside land, so a bad layout shows up in the build output.
function Pieces.checkChains(ctx: Context)
	local buried = 0
	for _, chain in chainsOf(ctx) do
		local down = UP * chain.sag
		local n = Terra.buried(ctx, chain.a, chain.a - down, chain.b - down, chain.b, 24)
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
-- along `outward` until nothing the style filled is underneath it (past
-- every coast lobe and shelf), and a water channel joins it back to the
-- source, so the water spills off the rim instead of out of the cliff.
-- Returns false (and builds nothing) when no clear lip is found.
function Pieces.waterfall(
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
		if Terra.clearBelow(ctx, p - UP * 0.5, 30, 1.5) then
			mouth = p + out * 1
			break
		end
	end
	if not mouth then
		return false
	end
	local start = mouth :: Vector3
	-- the spill channel: water laid over the land between source and mouth
	local length = (start - lip).Magnitude
	local s = 0
	while s < length do
		local q = lip + out * s
		if Terra.solidAt(ctx, q - UP * 3, 0) then
			ctx.terrain:FillBlock(
				CFrame.lookAt(q - UP * 1, q - UP * 1 + out),
				Vector3.new(4, 2, 4.5),
				Enum.Material.Water
			)
		end
		s += 4
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
	local mat = material or Enum.Material.Neon
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
	local n = count or rng:NextInteger(3, 5)
	local main: BasePart? = nil
	for i = 1, n do
		local height = size * (if i == 1 then 1 else rng:NextNumber(0.4, 0.72))
		local width = height * rng:NextNumber(0.2, 0.28)
		local yaw = rng:NextNumber(0, 360)
		local lean = if i == 1 then rng:NextNumber(-6, 6) else rng:NextNumber(20, 40)
		local direction = CFrame.Angles(0, math.rad(yaw), 0):VectorToWorldSpace(Vector3.zAxis)
		local foot = bottom + (if i == 1 then Vector3.zero else direction * size * 0.12)
		local tilt = if hanging then 180 - lean else lean
		local shard = Pieces.shard(parent, foot, height, width, color, yaw, tilt)
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
	Pieces.solid(
		parent,
		yaw * CFrame.new(0, base + shaftHeight / 2, 0),
		Vector3.new(if plinth then 1.3 else 1.5, shaftHeight, if plinth then 1.3 else 1.5),
		if plinth then C.skystone else C.skystoneDark,
		Enum.Material.Cobblestone
	)
	local cap = Pieces.diamond(parent, bottom + UP * (height - 0.4), 1.15, color)
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
			foot * CFrame.new(0, 0.8, 0),
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
		Pieces.block(
			parent,
			foot * CFrame.new(0, height * 0.42, 0),
			Vector3.new(2.7, 0.5, 2.7),
			glow,
			Enum.Material.Neon,
			{ CastShadow = false }
		)
		Pieces.solid(
			parent,
			foot * CFrame.new(0, height - 0.7, 0),
			Vector3.new(3.4, 1.4, 3.4),
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
	Pieces.block(
		parent,
		base * CFrame.new(0, height + 2.4, 0),
		Vector3.new(halfSpan * 2 - 1, 1.2, 2.2),
		C.skystone,
		Enum.Material.Cobblestone
	)
	Pieces.block(
		parent,
		base * CFrame.new(0, height + 3.6, 0) * CFrame.Angles(0, 0, math.rad(45)),
		Vector3.new(2.4, 2.4, 2.6),
		glow,
		Enum.Material.Neon,
		{ CastShadow = false }
	)
	for side = -1, 1, 2 do
		Pieces.shard(
			parent,
			(base * CFrame.new(side * halfSpan, height + 1.8, 0)).Position,
			4,
			1.3,
			glow,
			side * 20,
			side * 12
		)
	end
	-- banners hanging off the lintel ends
	for side = -1, 1, 2 do
		local banner = base * CFrame.new(side * (halfSpan + 2.6), height - 2.2, 0)
		Pieces.block(parent, banner, Vector3.new(2, 4.6, 0.15), glow, Enum.Material.Fabric)
		Pieces.wedge(
			parent,
			banner * CFrame.new(0, -3, 0) * CFrame.Angles(math.pi, 0, 0),
			Vector3.new(2, 1.4, 0.15),
			glow,
			Enum.Material.Fabric
		)
	end
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
-- deck with curbs, a glowing centre inlay, rail posts with crystal caps,
-- glowing rail cables and a keel underneath. Flat at both ends, ramp between.
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
	local width = opts.width or 10
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

	-- rail posts with glowing cables between them
	local spacing = opts.spacing or 12
	local count = math.max(1, math.floor((math.min(run, stop) - 1) / spacing))
	local previous: { [number]: Vector3 } = {}
	for k = 0, count do
		local s = math.min(1 + k * spacing, stop - 0.5)
		local deck = pointAt(s)
		for side = -1, 1, 2 do
			local foot = deck + right * side * (width / 2 - 0.5) + UP * 1.8
			local shaft = Pieces.solid(
				parent,
				CFrame.lookAt(foot + UP * 1.5, foot + UP * 1.5 + dir),
				Vector3.new(1, 3, 1),
				C.skystoneLight,
				Enum.Material.Cobblestone
			)
			shaft.Name = "RailPost"
			local cap = Pieces.diamond(parent, foot + UP * 3.5, 0.95, opts.glow)
			if opts.lights ~= false and k % 2 == 0 and side == 1 then
				Pieces.light(cap, opts.glow, 14, 1)
			end
			local top = foot + UP * 2.8
			local last = previous[side]
			if last then
				Pieces.runeCable(ctx, last, top, opts.glow, 0.5, 0.22)
			end
			previous[side] = top
		end
	end
end

-- Plants and props ------------------------------------------------------------------

-- Palm tree; `away` makes the trunk lean that way (off a field).
function Pieces.palm(parent: Instance, rng: Random, bottom: Vector3, height: number, away: Vector3?)
	local lean = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
	if away then
		lean = flat(away).Unit + lean * 0.35
	end
	lean = if lean.Magnitude > 0.01 then lean.Unit else Vector3.xAxis
	local point = bottom
	local segments = 3
	for i = 1, segments do
		local nextPoint = point + (UP + lean * (0.22 * i)).Unit * (height / segments)
		Pieces.pipe(
			parent,
			point,
			nextPoint + (nextPoint - point).Unit * 0.3,
			1.6 - i * 0.18,
			if i % 2 == 0 then C.wood else C.woodLight,
			Enum.Material.Wood,
			{ CanCollide = true }
		)
		point = nextPoint
	end
	Pieces.ball(parent, point, 1.9, C.wood, Enum.Material.Wood)
	local fronds = 6
	for k = 1, fronds do
		local angle = k / fronds * math.pi * 2 + rng:NextNumber(-0.25, 0.25)
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local length = height * rng:NextNumber(0.36, 0.46)
		local tip = point + out * length - UP * length * rng:NextNumber(0.3, 0.5)
		Pieces.plank(
			parent,
			point + UP * 0.3,
			tip,
			2.4,
			0.25,
			if k % 2 == 0 then C.meadow else C.meadowDark,
			Enum.Material.Grass
		)
	end
	for k = 1, 2 do
		local angle = k * math.pi + rng:NextNumber(0, 1)
		Pieces.ball(
			parent,
			point + Vector3.new(math.cos(angle) * 0.9, -0.9, math.sin(angle) * 0.9),
			1,
			C.wood,
			Enum.Material.Wood
		)
	end
end

-- Round-canopied tree (storm blossom): trunk and three canopy balls.
function Pieces.blossomTree(
	parent: Instance,
	rng: Random,
	bottom: Vector3,
	height: number,
	colors: { Color3 }
)
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
	Kit.rock(parent, bottom - UP * size * 0.15, size, rng, {
		Color = color or C.skystone,
		Material = Enum.Material.Rock,
	})
end

-- Terrain: islands ---------------------------------------------------------------

-- Point on the outline of the local rectangle [-hw, hw] x [front, back]
-- at distance t along it, and the outward normal there. With `corner`,
-- points near a corner are pulled onto a rounded corner of that radius.
local function rectPoint(
	t: number,
	hw: number,
	front: number,
	back: number,
	corner: number
): (Vector3, Vector3)
	local w, d = hw * 2, back - front
	local point, normal
	if t < w then
		point, normal = Vector3.new(-hw + t, 0, front), Vector3.new(0, 0, -1)
	elseif t < w + d then
		point, normal = Vector3.new(hw, 0, front + (t - w)), Vector3.new(1, 0, 0)
	elseif t < 2 * w + d then
		point, normal = Vector3.new(hw - (t - w - d), 0, back), Vector3.new(0, 0, 1)
	else
		point, normal = Vector3.new(-hw, 0, back - (t - 2 * w - d)), Vector3.new(-1, 0, 0)
	end
	if corner > 0 then
		local cx = math.clamp(point.X, -hw + corner, hw - corner)
		local cz = math.clamp(point.Z, front + corner, back - corner)
		local offset = Vector3.new(point.X - cx, 0, point.Z - cz)
		if math.abs(point.X - cx) > 0.01 and math.abs(point.Z - cz) > 0.01 then
			local out = offset.Unit
			return Vector3.new(cx, 0, cz) + out * corner, out
		end
	end
	return point, normal
end

export type LandOptions = {
	corner: number?, -- round the rectangle's corners with this radius
	lobe: number, -- typical lobe radius along the coast
	reach: number?, -- how far lobes may push out, in lobe radii (default 0.4)
	accept: Accept?,
}

-- Flat-topped landmass on a local rectangle (in `frame`'s ground plane)
-- with a lumpy outline: a (rounded) box plus jittered lobes along its
-- edge. Lobes that `accept` rejects are skipped.
function Pieces.landmass(
	ctx: Context,
	frame: CFrame,
	hw: number,
	front: number,
	back: number,
	topY: number,
	thickness: number,
	material: Enum.Material,
	options: LandOptions
)
	local rng = ctx.rng
	local terrain = ctx.terrain
	local corner = math.min(options.corner or 0, hw, (back - front) / 2)
	local function fillBox(x: number, z: number, sx: number, sz: number)
		local at = frame:PointToWorldSpace(Vector3.new(x, 0, z))
		terrain:FillBlock(
			CFrame.new(at.X, topY - thickness / 2, at.Z) * frame.Rotation,
			Vector3.new(sx, thickness, sz),
			material
		)
	end
	local middle = (front + back) / 2
	if corner > 0.5 then
		fillBox(0, middle, hw * 2, back - front - corner * 2)
		fillBox(0, middle, hw * 2 - corner * 2, back - front)
		for _, c in
			{
				Vector3.new(-1, 0, front),
				Vector3.new(1, 0, front),
				Vector3.new(-1, 0, back),
				Vector3.new(1, 0, back),
			}
		do
			local z = if c.Z == front then front + corner else back - corner
			local at = frame:PointToWorldSpace(Vector3.new(c.X * (hw - corner), 0, z))
			terrain:FillCylinder(
				CFrame.new(at.X, topY - thickness / 2, at.Z),
				thickness,
				corner,
				material
			)
		end
	else
		fillBox(0, middle, hw * 2, back - front)
	end
	local lobe = options.lobe
	local reach = options.reach or 0.4
	local perimeter = 2 * (hw * 2 + (back - front))
	local steps = math.max(6, math.floor(perimeter / lobe))
	for i = 0, steps - 1 do
		local t = ((i + rng:NextNumber(-0.45, 0.45)) / steps * perimeter) % perimeter
		local localPoint, normal = rectPoint(t, hw, front, back, corner)
		-- mostly small lobes with the odd big bulge: a natural, uneven coast
		-- a few big bulges, many small nubs and some straight cliff facets
		local roll = rng:NextNumber()
		local big = roll < 0.1
		local radius = lobe
			* (if big then rng:NextNumber(1.6, 2) elseif roll < 0.55 then rng:NextNumber(0.3, 0.5) else rng:NextNumber(0.55, 0.9))
		local push = lobe * (if big then rng:NextNumber(0, reach) else rng:NextNumber(-0.5, reach))
		local world = frame:PointToWorldSpace(localPoint + normal * push)
		local facet = roll > 0.72
		if facet then
			-- a flat cliff face turned a little off the coast line
			local length = lobe * rng:NextNumber(1.2, 2.2)
			local deep = lobe * rng:NextNumber(0.5, 0.8)
			if not options.accept or options.accept(world, length * 0.6) then
				local h = thickness * rng:NextNumber(0.7, 1)
				local n = frame:VectorToWorldSpace(normal)
				local at = Vector3.new(world.X, topY - h / 2, world.Z)
				terrain:FillBlock(
					CFrame.lookAt(at, at + n) * CFrame.Angles(0, math.rad(rng:NextNumber(-22, 22)), 0),
					Vector3.new(length, h, deep),
					material
				)
			end
		elseif not options.accept or options.accept(world, radius) then
			local h = thickness * rng:NextNumber(0.6, 1)
			terrain:FillCylinder(CFrame.new(world.X, topY - h / 2, world.Z), h, radius, material)
		end
	end
end

-- A headland: a round lobe of land at `floor` (solid core plus a lumpy
-- edge) over a slightly wider rock shelf 4 studs lower. Use it to push an
-- island's coastline out where a landmark or prop needs room.
function Pieces.headland(
	ctx: Context,
	center: Vector3,
	radius: number,
	floor: number,
	top: Enum.Material,
	shelf: Enum.Material
)
	local ground = Vector3.new(center.X, 0, center.Z)
	Kit.blob(ctx, ground, radius * 1.15, floor - 4, 10, shelf, 6)
	ctx.terrain:FillCylinder(CFrame.new(center.X, floor - 5, center.Z), 10, radius * 0.8, top)
	Kit.blob(ctx, ground, radius, floor, 8, top, 6)
end

-- A tilted rock slab: a rotated terrain block standing on the ground at
-- `center` (only X/Z used), from `bottom` up to about `top`, turned `yaw`
-- degrees off `outward` and leaning `tilt` degrees away along `outward`
-- (so the top moves away from whatever `outward` points from). The slab's
-- horizontal reach from `center` stays within halfWidth/halfDepth.
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
	material: Enum.Material
)
	local out = flat(outward).Unit
	local height = top - bottom
	local middle = Vector3.new(center.X, (top + bottom) / 2, center.Z)
	local frame = CFrame.lookAt(middle, middle + out)
		* CFrame.Angles(0, math.rad(yaw), 0)
		* CFrame.Angles(-math.rad(tilt), 0, 0)
	ctx.terrain:FillBlock(frame, Vector3.new(halfWidth * 2, height, halfDepth * 2), material)
end

-- A sea-stack spire: a chain of terrain balls shrinking upward, rooted
-- below `foot`, with a slight lean.
function Pieces.spire(
	ctx: Context,
	foot: Vector3,
	height: number,
	radius: number,
	lean: Vector3,
	material: Enum.Material
)
	local r = radius
	local y = 0
	local drift = flat(lean)
	ctx.terrain:FillCylinder(CFrame.new(foot - UP * 6), 14, radius * 1.15, material)
	while y < height and r >= 3.5 do
		local t = y / height
		ctx.terrain:FillBall(foot + UP * y + drift * (t * t * 4), r, material)
		y += r * 0.9
		r = math.max(radius * (1 - t * 0.55), 3.5)
		if y + r > height then
			break
		end
	end
end

-- A natural arch: a chain of terrain balls along a half ellipse from a to
-- b (ground points) rising `rise` studs, with legs flaring at the base.
function Pieces.ballArch(
	ctx: Context,
	a: Vector3,
	b: Vector3,
	floor: number,
	rise: number,
	material: Enum.Material,
	band: Enum.Material?
)
	local count = 11
	for i = 0, count - 1 do
		local t = i / (count - 1)
		local angle = math.pi * t
		local p = a:Lerp(b, (1 - math.cos(angle)) / 2)
		local y = floor + math.sin(angle) * rise
		local edge = math.abs(t - 0.5) * 2
		local r = 3.5 + edge
		local mat = if band and i % 3 == 1 then band else material
		ctx.terrain:FillBall(Vector3.new(p.X, y, p.Z), r, mat)
	end
	for _, leg in { a, b } do
		ctx.terrain:FillBall(Vector3.new(leg.X, floor - 1, leg.Z), 6.5, material)
		ctx.terrain:FillBall(Vector3.new(leg.X, floor + 3, leg.Z), 5, material)
	end
end

-- Tapering rocky underside below a rectangle of half extents hw x hd
-- centred on `frame`, from topY down `depth` studs, plus hanging spikes.
-- Materials run from the top layer to the tip.
function Pieces.underside(
	ctx: Context,
	frame: CFrame,
	hw: number,
	hd: number,
	topY: number,
	depth: number,
	materials: { Enum.Material },
	accept: Accept?
)
	local rng = ctx.rng
	local layers = math.max(3, math.floor(depth / 11))
	local step = depth / layers
	local bottomCenters: { Vector3 } = {}
	for i = layers, 1, -1 do
		local f = (i - 0.5) / layers
		local scale = math.max(0.12, 1 - f ^ 1.35)
		local material = materials[math.clamp(math.ceil(f * #materials), 1, #materials)]
		local shift =
			Vector3.new(rng:NextNumber(-1, 1) * hw * 0.07, 0, rng:NextNumber(-1, 1) * hd * 0.07)
		local layerFrame = frame * CFrame.new(shift)
		local w = math.max(4, hw * scale)
		local d = math.max(4, hd * scale)
		Pieces.landmass(ctx, layerFrame, w, -d, d, topY - (i - 1) * step, step + 5, material, {
			corner = math.min(w, d) * 0.5,
			lobe = math.clamp(math.min(w, d) * 0.5, 5, 14),
			accept = accept,
		})
		if i == layers - 1 then
			for _ = 1, 4 do
				table.insert(
					bottomCenters,
					layerFrame:PointToWorldSpace(
						Vector3.new(rng:NextNumber(-0.7, 0.7) * w, 0, rng:NextNumber(-0.7, 0.7) * d)
					)
				)
			end
		end
	end
	-- two or three off-centre hanging cones: chains of terrain balls that
	-- shrink downward, finished with a sharp rock tip part
	local tipY = topY - depth
	local cones = math.min(#bottomCenters, if hw * hd > 2500 then 3 else 2)
	for k = 1, cones do
		local center = bottomCenters[k]
		local radius = rng:NextNumber(7, 10)
		local y = tipY + step * 1.2
		local drift = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
		local material = materials[#materials]
		local p = Vector3.new(center.X, y, center.Z)
		while radius >= 4 do
			ctx.terrain:FillBall(p, radius, material)
			p += drift * 0.8 - UP * radius * 0.95
			radius *= 0.8
		end
		local folder = ctx.folders.base
		local tipHeight = radius * 4
		Pieces.wedge(
			folder,
			CFrame.new(p + UP * (radius * 0.6 - tipHeight / 2))
				* CFrame.Angles(math.pi, rng:NextNumber(0, math.pi), 0),
			Vector3.new(radius * 2.2, tipHeight, radius * 2.2),
			Palette.TERRAIN[material] or C.skystoneDark,
			material
		)
	end
end

-- Placement guards ----------------------------------------------------------------

local function allZones(ctx: Context): { ZoneContext }
	local all = table.clone(ctx.zones)
	table.insert(all, ctx.teaser)
	return all
end
Pieces.allZones = allZones

-- Horizontal distance from p to the segment a-b.
function Pieces.segmentDistance(p: Vector3, a: Vector3, b: Vector3): number
	local ap = Vector2.new(p.X - a.X, p.Z - a.Z)
	local ab = Vector2.new(b.X - a.X, b.Z - a.Z)
	local t = math.clamp(ap:Dot(ab) / math.max(ab:Dot(ab), 1e-6), 0, 1)
	return (ap - ab * t).Magnitude
end

-- Horizontal distance from p to a zone's footprint rectangle (0 inside).
function Pieces.footprintDistance(zone: ZoneContext, p: Vector3): number
	local slot = zone.slot
	local l = slot.frame:PointToObjectSpace(Vector3.new(p.X, slot.floor, p.Z))
	local dx = math.max(math.abs(l.X) - slot.width / 2, 0)
	local dz = math.max(math.abs(l.Z) - slot.depth / 2, 0)
	return math.sqrt(dx * dx + dz * dz)
end

-- Is a disc (centre p, radius r) clear of every other zone's footprint,
-- of every connector corridor and (with hubPad) of the hub plaza?
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
-- above the terrain floor: under the warning circles and inside the
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
	if pattern.kind == "bands" then
		local acrossX = pattern.axis == "x"
		local length = if acrossX then W else D
		local span = if acrossX then D else W
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
	else
		local nx = math.max(2, math.round(W / pattern.size))
		local nz = math.max(2, math.round(D / pattern.size))
		local sx, sz = W / nx, D / nz
		for i = 0, nx - 1 do
			for j = 0, nz - 1 do
				tile(
					frame * CFrame.new(-W / 2 + (i + 0.5) * sx, y, -D / 2 + (j + 0.5) * sz),
					Vector3.new(sx, thickness, sz),
					(i + j) % 2 + 1
				)
			end
		end
	end
	-- glowing edge line in the zone colour, just inside the footprint edge
	local line = 0.7
	local lineY = 0.28 - 0.2
	local edges: { { cframe: CFrame, size: Vector3 } } = {
		{ cframe = CFrame.new(0, lineY, -D / 2 + 1), size = Vector3.new(W - 2, 0.4, line) },
		{ cframe = CFrame.new(0, lineY, D / 2 - 1), size = Vector3.new(W - 2, 0.4, line) },
		{ cframe = CFrame.new(-W / 2 + 1, lineY, 0), size = Vector3.new(line, 0.4, D - 2) },
		{ cframe = CFrame.new(W / 2 - 1, lineY, 0), size = Vector3.new(line, 0.4, D - 2) },
	}
	for _, edge in edges do
		Pieces.block(
			parent,
			frame * edge.cframe,
			edge.size,
			zone.color,
			Enum.Material.Neon,
			{ CastShadow = false, Name = "FieldEdge" }
		)
	end
end

return Pieces
