--!strict
-- StormPunk building pieces: insulators, pylons, lamps, coils, signs,
-- buildings and props. Every piece uses the palette and composes Kit
-- primitives, so all the world's modules share one look. Positions are
-- world space; "bottom" is the point a piece stands on.
--
-- Part budget: pieces are designed chunky and cheap (a border post is 2-3
-- parts, a lamp 2, a palm 9, a framed sign 2) so 7 zones fit in 2,500.

local ServerScriptService = game:GetService("ServerScriptService")

local World = ServerScriptService.Server.World
local Blocks = require(World.Blocks)
local Kit = require(World.Kit)
local WorldTypes = require(World.Types)
local Palette = require(script.Parent.Palette)

type Context = WorldTypes.Context

local C = Palette.colors
local T = Palette.tints
local M = Palette.materials
local L = Palette.light

local UP = Vector3.new(0, 1, 0)

local Pieces = {}

-- Basic shapes -----------------------------------------------------------------

-- Visual block. solid = collidable (structures people shouldn't walk through).
function Pieces.block(
	parent: Instance,
	cframe: CFrame,
	size: Vector3,
	color: Color3,
	material: Enum.Material?,
	solid: boolean?
): BasePart
	return Kit.decor({
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = material or M.metal,
		CanCollide = solid == true,
		CastShadow = size.Magnitude > 3,
		Parent = parent,
	})
end

function Pieces.wedge(
	parent: Instance,
	cframe: CFrame,
	size: Vector3,
	color: Color3,
	material: Enum.Material?,
	solid: boolean?
): BasePart
	return Kit.decor({
		ClassName = "WedgePart",
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = material or M.metal,
		CanCollide = solid == true,
		Parent = parent,
	})
end

function Pieces.column(
	parent: Instance,
	bottom: Vector3,
	height: number,
	diameter: number,
	color: Color3,
	material: Enum.Material?,
	solid: boolean?
): BasePart
	return Kit.cylinder(parent, bottom, height, diameter, {
		Color = color,
		Material = material or M.metal,
		CanCollide = solid == true,
	})
end

function Pieces.ball(
	parent: Instance,
	center: Vector3,
	diameter: number,
	color: Color3,
	material: Enum.Material?
): BasePart
	return Kit.ball(parent, center, diameter, {
		Color = color,
		Material = material or M.metal,
		CanCollide = false,
	})
end

function Pieces.strut(
	parent: Instance,
	a: Vector3,
	b: Vector3,
	thickness: number,
	color: Color3,
	material: Enum.Material?,
	solid: boolean?
): BasePart
	return Kit.strut(parent, a, b, thickness, {
		Color = color,
		Material = material or M.metal,
		CanCollide = solid == true,
	})
end

function Pieces.pipe(
	parent: Instance,
	a: Vector3,
	b: Vector3,
	diameter: number,
	color: Color3,
	material: Enum.Material?
): BasePart
	return Kit.pipe(parent, a, b, diameter, {
		Color = color,
		Material = material or M.metal,
		CanCollide = false,
	})
end

-- Energy ------------------------------------------------------------------------

function Pieces.glow(part: BasePart, color: Color3, range: number, brightness: number?): PointLight
	return Kit.light(part, color, range, brightness or 1.6, false)
end

local function sparkEmitter(part: BasePart, color: Color3, size: number, rate: number)
	Kit.emitter(part, {
		Texture = Kit.TEXTURES.sparkle,
		Color = ColorSequence.new(color),
		LightEmission = 1,
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, size),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Lifetime = NumberRange.new(0.25, 0.6),
		Rate = rate,
		Speed = NumberRange.new(3, 8),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -10, 0),
		Transparency = NumberSequence.new(0.1),
	})
end

-- Neon orb, optionally lit and sparking.
function Pieces.orb(
	parent: Instance,
	center: Vector3,
	diameter: number,
	color: Color3?,
	lightRange: number?,
	sparks: boolean?
): BasePart
	local orb = Pieces.ball(parent, center, diameter, color or C.volt, M.neon)
	if lightRange then
		Pieces.glow(orb, color or C.volt, lightRange, 2)
	end
	if sparks then
		sparkEmitter(orb, color or C.volt, diameter * 0.18, 14)
	end
	return orb
end

-- Electric sparks crackling off a part's surface.
function Pieces.sparks(part: BasePart, color: Color3?, rate: number?)
	sparkEmitter(part, color or C.volt, 0.5, rate or 6)
end

-- Glowing cable (Beam) in any colour.
function Pieces.liveCable(
	ctx: Context,
	a: Vector3,
	b: Vector3,
	color: Color3?,
	width: number?,
	sag: number?
): Beam
	return Kit.cable(ctx, a, b, {
		Color = color or C.volt,
		Width = width or 0.35,
		CurveSize = sag or 0,
		LightEmission = 1,
		Brightness = 2,
	})
end

-- Plain dark power line.
function Pieces.wire(ctx: Context, a: Vector3, b: Vector3, sag: number?, width: number?): Beam
	return Kit.cable(ctx, a, b, {
		Color = C.soot,
		Width = width or 0.25,
		CurveSize = sag or 2,
	})
end

-- Ceramic insulator stack around a vertical axis. Returns the top point.
function Pieces.insulator(parent: Instance, bottom: Vector3, scale: number, count: number): Vector3
	local step = 0.75 * scale
	for i = 0, count - 1 do
		Pieces.column(
			parent,
			bottom + Vector3.new(0, i * step, 0),
			0.42 * scale,
			if i % 2 == 0 then 2.3 * scale else 1.8 * scale,
			C.ceramic,
			M.ceramic
		)
	end
	return bottom + Vector3.new(0, count * step, 0)
end

-- Ring of balls: a copper torus (coil crowns, lighthouse rings).
function Pieces.torus(
	parent: Instance,
	center: Vector3,
	radius: number,
	ballSize: number,
	count: number,
	color: Color3,
	material: Enum.Material?
)
	for i = 1, count do
		local a = (i / count) * math.pi * 2
		Pieces.ball(
			parent,
			center + Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius),
			ballSize,
			color,
			material
		)
	end
end

-- Jacob's ladder: two diverging copper rods with cyan arcs between them.
function Pieces.jacobsLadder(
	ctx: Context,
	parent: Instance,
	base: Vector3,
	right: Vector3,
	height: number
)
	local spread = height * 0.35
	local leftTop = base - right * spread + Vector3.new(0, height, 0)
	local rightTop = base + right * spread + Vector3.new(0, height, 0)
	local l0 = base - right * 0.6
	local r0 = base + right * 0.6
	Pieces.strut(parent, l0, leftTop, 0.45, C.copper)
	Pieces.strut(parent, r0, rightTop, 0.45, C.copper)
	for i, t in { 0.45, 0.9 } do
		Pieces.liveCable(
			ctx,
			l0:Lerp(leftTop, t),
			r0:Lerp(rightTop, t),
			C.volt,
			0.3 + i * 0.08,
			-0.8 - i * 0.5
		)
	end
end

-- Structures ------------------------------------------------------------------------

-- Border post: a chunky copper pile with a ceramic insulator collar and
-- (when `cap`) a lamp cap in the zone colour. Returns the cable point.
function Pieces.insulatorPost(
	parent: Instance,
	bottom: Vector3,
	height: number,
	color: Color3,
	cap: boolean
): Vector3
	Pieces.column(parent, bottom - UP, height + 1, 1.5, C.copper, M.metal, true)
	local top = bottom + UP * height
	Pieces.column(parent, top - UP * 1.9, 1.1, 2.7, C.ceramic, M.ceramic)
	if cap then
		Pieces.ball(parent, top + UP * 0.5, 1.9, color, M.neon)
	end
	return top - UP * 1.35
end

-- Lamp post: iron post and a glowing lantern (optionally a brass hood).
-- Returns the lantern.
function Pieces.lamp(
	parent: Instance,
	bottom: Vector3,
	height: number,
	glowColor: Color3?,
	lightRange: number?,
	hood: boolean?
): BasePart
	Pieces.column(parent, bottom, height, 0.6, C.iron, M.metal, true)
	local lanternCenter = bottom + UP * (height + 0.7)
	local lantern = Pieces.ball(parent, lanternCenter, 1.5, glowColor or C.volt, M.neon)
	if hood then
		Pieces.column(parent, lanternCenter + UP * 0.6, 0.4, 2, C.brass)
	end
	if lightRange then
		Pieces.glow(lantern, glowColor or C.volt, lightRange, 1.4)
	end
	return lantern
end

-- Lattice Tesla pylon with a crossarm (8 parts). Returns the two crossarm
-- cable points and the tip.
function Pieces.pylon(
	parent: Instance,
	bottom: Vector3,
	height: number,
	yawDeg: number,
	baseHalf: number?,
	thickness: number?
): (Vector3, Vector3, Vector3)
	local cf = CFrame.new(bottom) * CFrame.Angles(0, math.rad(yawDeg), 0)
	local b = baseHalf or height * 0.12
	local t = math.max(b * 0.3, 0.8)
	local leg = thickness or 0.7
	for _, c in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
		local foot = cf:PointToWorldSpace(Vector3.new(c[1] * b, 0, c[2] * b))
		local head = cf:PointToWorldSpace(Vector3.new(c[1] * t, height, c[2] * t))
		Pieces.strut(parent, foot, head, leg, C.iron)
	end
	-- crossarm with an insulator at each end
	local armY = height * 0.86
	local armHalf = math.max(b * 1.1, 3)
	local armA = cf:PointToWorldSpace(Vector3.new(-armHalf, armY, 0))
	local armB = cf:PointToWorldSpace(Vector3.new(armHalf, armY, 0))
	Pieces.strut(parent, armA, armB, leg * 0.9, C.copper)
	Pieces.column(parent, armA - UP * 1.6, 1.6, 1.3, C.ceramic, M.ceramic)
	Pieces.column(parent, armB - UP * 1.6, 1.6, 1.3, C.ceramic, M.ceramic)
	local tip = cf:PointToWorldSpace(Vector3.new(0, height, 0))
	Pieces.ball(parent, tip + UP * 0.6, 1.4, C.volt, M.neon)
	return armA - UP * 1.7, armB - UP * 1.7, tip + UP * 0.6
end

-- Banded chimney / smokestack (4 parts). Returns its top centre.
function Pieces.smokestack(
	parent: Instance,
	bottom: Vector3,
	height: number,
	diameter: number,
	smoke: boolean?
): Vector3
	Pieces.column(parent, bottom, height, diameter, C.copper, M.metal, true)
	Pieces.column(parent, bottom + UP * height * 0.3, 1.2, diameter + 0.5, C.brass)
	Pieces.column(parent, bottom + UP * height * 0.62, 1.2, diameter + 0.5, C.patina)
	local top = bottom + UP * height
	local rim = Pieces.column(parent, top - UP * 1.2, 1.6, diameter + 1.2, C.iron)
	if smoke then
		Kit.emitter(rim, {
			Texture = Kit.TEXTURES.smoke,
			-- upright Kit cylinders run along local X: emit out of the top
			EmissionDirection = Enum.NormalId.Right,
			Color = ColorSequence.new(Color3.fromRGB(205, 200, 196), Color3.fromRGB(120, 120, 128)),
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, diameter * 0.5),
				NumberSequenceKeypoint.new(1, diameter * 2.2),
			}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.35),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Lifetime = NumberRange.new(4, 7),
			Rate = 4,
			Speed = NumberRange.new(4, 7),
			SpreadAngle = Vector2.new(12, 12),
			Acceleration = Vector3.new(2, 1, 0),
			RotSpeed = NumberRange.new(-20, 20),
		})
	end
	return top
end

-- Big riveted storage tank (gasometer) with a patina dome.
function Pieces.tank(
	parent: Instance,
	bottom: Vector3,
	height: number,
	diameter: number,
	glowing: boolean?
)
	Pieces.column(parent, bottom, height, diameter, C.copper, M.metal, true)
	Pieces.column(parent, bottom, 1.4, diameter + 1.2, C.iron, M.metal, true)
	Pieces.column(parent, bottom + UP * height * 0.45, 1, diameter + 0.5, C.brass)
	Pieces.column(parent, bottom + UP * height, 1.2, diameter + 0.8, C.patina)
	Pieces.ball(parent, bottom + UP * (height + 0.4), diameter * 0.84, C.patina, M.metal)
	if glowing then
		Pieces.orb(parent, bottom + UP * (height + diameter * 0.44), 2.4, C.volt, 18)
	end
end

-- Buildings ---------------------------------------------------------------------------

-- A trimmed building body: stepped iron plinth, the walls, copper corner
-- pilasters and a brass cornice band proud of the roof line (7 parts).
-- `frame` is on the ground at the centre (LookVector = the front).
-- Returns the CFrame at the centre of the roof line.
function Pieces.building(
	parent: Instance,
	frame: CFrame,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	trim: Color3?
): CFrame
	local plinth = 0.9
	Pieces.block(
		parent,
		frame * CFrame.new(0, plinth / 2, 0),
		Vector3.new(size.X + 1.4, plinth, size.Z + 1.4),
		C.iron,
		M.concrete,
		true
	)
	Pieces.block(parent, frame * CFrame.new(0, plinth + size.Y / 2, 0), size, color, material, true)
	for _, c in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
		Pieces.block(
			parent,
			frame * CFrame.new(c[1] * size.X / 2, plinth + size.Y / 2, c[2] * size.Z / 2),
			Vector3.new(0.9, size.Y, 0.9),
			trim or C.copper,
			M.metal
		)
	end
	local roofY = plinth + size.Y
	Pieces.block(
		parent,
		frame * CFrame.new(0, roofY + 0.3, 0),
		Vector3.new(size.X + 1, 0.6, size.Z + 1),
		C.brass,
		M.metal
	)
	return frame * CFrame.new(0, roofY + 0.6, 0)
end

-- A window on a wall: `cframe` on the wall surface, LookVector outward.
-- Glowing pane set into the wall, recessed behind a proud brass lintel
-- and sill (3 parts).
function Pieces.window(
	parent: Instance,
	cframe: CFrame,
	width: number,
	height: number,
	glow: Color3?
)
	Pieces.block(parent, cframe, Vector3.new(width, height, 0.2), glow or L.warm, M.neon)
	Pieces.block(
		parent,
		cframe * CFrame.new(0, height / 2 + 0.22, -0.25),
		Vector3.new(width + 0.9, 0.45, 0.6),
		C.brass,
		M.metal
	)
	Pieces.block(
		parent,
		cframe * CFrame.new(0, -height / 2 - 0.18, -0.3),
		Vector3.new(width + 0.9, 0.36, 0.7),
		C.brass,
		M.metal
	)
end

-- Gable roof over a building: two wedges meeting at the ridge, with a
-- one-stud overhang all round. `top` = roof line centre (LookVector = front).
function Pieces.gable(
	parent: Instance,
	top: CFrame,
	width: number,
	depth: number,
	rise: number,
	color: Color3,
	material: Enum.Material?
)
	-- a WedgePart is tall at its back (+Z) and slopes down to its front
	local w, d = width + 2, depth + 2
	Pieces.wedge(
		parent,
		top * CFrame.new(0, rise / 2, -d / 4),
		Vector3.new(w, rise, d / 2),
		color,
		material
	)
	Pieces.wedge(
		parent,
		top * CFrame.new(0, rise / 2, d / 4) * CFrame.Angles(0, math.pi, 0),
		Vector3.new(w, rise, d / 2),
		color,
		material
	)
end

-- Props ----------------------------------------------------------------------------

function Pieces.crate(
	parent: Instance,
	bottom: Vector3,
	size: number,
	yawDeg: number,
	color: Color3?,
	banded: boolean?
): BasePart
	local cf = CFrame.new(bottom + UP * (size / 2)) * CFrame.Angles(0, math.rad(yawDeg), 0)
	local box =
		Pieces.block(parent, cf, Vector3.new(size, size, size), color or C.timber, M.wood, true)
	if banded then
		Pieces.block(
			parent,
			cf,
			Vector3.new(size + 0.1, size * 0.18, size + 0.1),
			T.brassDark,
			M.metal
		)
	end
	return box
end

function Pieces.barrel(parent: Instance, bottom: Vector3, color: Color3?)
	Pieces.column(parent, bottom, 3, 2.2, color or C.patina, M.metal, true)
end

-- Small rock cluster (Kit.rock, 2-4 parts) in palette stone tones.
-- A chunky block rock (World/Blocks: SmoothPlastic, shape from its spot).
function Pieces.rocks(parent: Instance, bottom: Vector3, size: number, color: Color3?)
	Blocks.rock(parent, color or T.rock, bottom - UP * (size * 0.2), size, {
		Name = "Rock",
		CanCollide = size > 3,
	})
end

-- Tuft of dune grass / scrub: two crossed blades.
function Pieces.tuft(parent: Instance, bottom: Vector3, rng: Random, color: Color3?)
	local h = rng:NextNumber(1.4, 2.6)
	local yaw = rng:NextNumber(0, 180)
	for i = 0, 1 do
		local cf = CFrame.new(bottom + UP * (h / 2 - 0.1))
			* CFrame.Angles(0, math.rad(yaw + i * 90), 0)
			* CFrame.Angles(rng:NextNumber(-0.25, 0.25), 0, 0)
		Pieces.wedge(
			parent,
			cf,
			Vector3.new(0.25, h, h * 0.6),
			color or C.sage,
			Enum.Material.Grass
		)
	end
end

-- Scrub bush: one or two squat balls.
function Pieces.shrub(parent: Instance, bottom: Vector3, rng: Random, color: Color3?)
	local s = rng:NextNumber(1.8, 3.2)
	Pieces.ball(parent, bottom + UP * (s * 0.3), s, color or C.sage, Enum.Material.Grass)
	if rng:NextNumber() < 0.4 then
		Pieces.ball(
			parent,
			bottom + Vector3.new(s * 0.45, s * 0.2, rng:NextNumber(-0.5, 0.5)),
			s * 0.7,
			T.sageDark,
			Enum.Material.Grass
		)
	end
end

-- Palm (9 parts): a curved, ringed trunk, five flat fronds and a cluster
-- of copper "coconuts".
function Pieces.palm(parent: Instance, base: Vector3, lean: Vector3, rng: Random)
	local height = rng:NextNumber(11, 15)
	local bend = rng:NextNumber(2.5, 4.5)
	local prev = base
	for i = 1, 3 do
		local t = i / 3
		local p = base + UP * height * t + lean * bend * t * t
		Pieces.pipe(
			parent,
			prev - (p - prev).Unit * 0.2,
			p,
			1.35 - t * 0.4,
			if i % 2 == 0 then T.timberPale else C.timber,
			M.wood
		)
		prev = p
	end
	local crown = prev
	local spin = rng:NextNumber(0, 360)
	for i = 0, 4 do
		local a = math.rad(spin + i * 72 + rng:NextNumber(-10, 10))
		local d = Vector3.new(math.sin(a), 0, -math.cos(a))
		local length = rng:NextNumber(6, 8)
		local tip = crown + d * length - UP * rng:NextNumber(2.2, 3.6)
		local mid = crown:Lerp(tip, 0.5) + UP * 0.6
		local cf = CFrame.lookAt(mid, tip) * CFrame.Angles(0, 0, math.rad(90))
		Pieces.wedge(
			parent,
			cf,
			Vector3.new(0.3, 2.6, (tip - crown).Magnitude),
			if i % 2 == 0 then C.sage else T.sageDark,
			Enum.Material.Grass
		)
	end
	Pieces.ball(parent, crown - UP * 0.6, 1.5, C.copper)
end

-- Railing from a to b (points on the walking surface): posts and one rail,
-- all collidable so nobody walks off a bridge.
function Pieces.railing(
	parent: Instance,
	a: Vector3,
	b: Vector3,
	height: number,
	spacing: number,
	color: Color3?
)
	local length = (b - a).Magnitude
	local posts = math.max(1, math.floor(length / spacing + 0.5))
	local h = UP * height
	for k = 0, posts do
		local p = a:Lerp(b, k / posts)
		Pieces.strut(parent, p, p + h, 0.35, C.iron, M.metal, true)
	end
	Pieces.strut(parent, a + h, b + h, 0.4, color or C.brass, M.metal, true)
end

-- Sign board (Kit.sign) that never blocks anyone: boards are decoration.
function Pieces.sign(
	parent: Instance,
	cframe: CFrame,
	width: number,
	height: number,
	title: string,
	subtitle: string?,
	style: Kit.SignStyle
): BasePart
	local board = Kit.sign(parent, cframe, width, height, title, subtitle, style)
	board.CanCollide = false
	board.CanQuery = false
	return board
end

-- Sign board on a brass backing plate that frames it (2 parts). Text
-- faces cframe.LookVector (and the back too when the style is two-sided).
function Pieces.framedSign(
	parent: Instance,
	cframe: CFrame,
	width: number,
	height: number,
	title: string,
	subtitle: string?,
	style: Kit.SignStyle
): BasePart
	local board = Pieces.sign(parent, cframe, width, height, title, subtitle, style)
	local d = (style.thickness or 0.6) + 0.3
	Pieces.block(parent, cframe, Vector3.new(width + 1, height + 1, d - 0.1), C.brass)
	board.Size = Vector3.new(width, height, d)
	return board
end

-- Arrow-shaped sign pointing along `direction` (horizontal), text on both
-- sides (3 parts). `center` is the middle of the board.
function Pieces.arrowSign(
	parent: Instance,
	center: Vector3,
	direction: Vector3,
	length: number,
	height: number,
	title: string,
	color: Color3
)
	local d = Vector3.new(direction.X, 0, direction.Z).Unit
	local x = d:Cross(UP)
	local cf = CFrame.fromMatrix(center, d, UP)
	Pieces.sign(parent, cf, length, height, title, nil, Palette.sign(color, true))
	-- arrow head: two wedges forming a triangle in the board's plane
	local headLength = height * 0.9
	local half = height * 0.85
	local base = center + d * (length / 2)
	for _, s in { 1, -1 } do
		local up = UP * s
		local mid = base + up * (half / 2) + d * (headLength / 2)
		local wedgeX = if s == 1 then x else -x
		Pieces.wedge(
			parent,
			CFrame.fromMatrix(mid, wedgeX, up),
			Vector3.new(0.8, half, headLength),
			color,
			M.neon
		)
	end
end

-- Amber/black striped barricade across `cframe` (LookVector = the side the
-- stripes face), collidable.
function Pieces.barricade(parent: Instance, cframe: CFrame, width: number)
	local stripes = 4
	local w = (width - 1) / stripes
	for i = 0, stripes - 1 do
		local x = -width / 2 + 0.5 + (i + 0.5) * w
		Pieces.block(
			parent,
			cframe * CFrame.new(x, 2.4, 0),
			Vector3.new(w, 1.4, 0.5),
			if i % 2 == 0 then C.hazard else C.soot,
			Enum.Material.SmoothPlastic,
			true
		)
	end
	for _, side in { -1, 1 } do
		Pieces.block(
			parent,
			cframe * CFrame.new(side * (width / 2 - 0.4), 1.6, 0),
			Vector3.new(0.6, 3.2, 1.8),
			C.iron,
			M.metal,
			true
		)
	end
end

-- Timber pier on piles from a to b (sea-level points) with its deck at
-- deckY, a lamp at the far end and an optional name board.
function Pieces.pier(
	parent: Instance,
	from: Vector3,
	to: Vector3,
	deckY: number,
	label: string?,
	seaFloor: number
)
	local a = Vector3.new(from.X, deckY, from.Z)
	local b = Vector3.new(to.X, deckY, to.Z)
	local dir = Vector3.new(b.X - a.X, 0, b.Z - a.Z).Unit
	local side = dir:Cross(UP)
	Pieces.block(
		parent,
		CFrame.lookAt((a + b) / 2, b) * CFrame.new(0, -0.25, 0),
		Vector3.new(5, 0.5, (b - a).Magnitude),
		C.timber,
		M.planks,
		true
	)
	local n = math.max(1, math.floor((b - a).Magnitude / 9))
	for i = 1, n do
		local p = a:Lerp(b, i / n)
		for _, s in { -1, 1 } do
			local foot = p + side * s * 2.2
			Pieces.column(
				parent,
				Vector3.new(foot.X, seaFloor, foot.Z),
				deckY + 0.6 - seaFloor,
				0.9,
				T.timberDark,
				M.wood
			)
		end
	end
	Pieces.lamp(parent, b - dir * 1.5 + side * 2, 6, C.volt, nil, true)
	if label then
		local at = a + UP * 3.2 + side * 2.6 + dir * 2
		Pieces.framedSign(
			parent,
			CFrame.lookAt(at, at - dir),
			4.4,
			1.4,
			label,
			nil,
			Palette.sign(C.volt, true)
		)
	end
end

-- Little storm skiff floating at `frame` (on the water, LookVector = bow):
-- pointed timber hull with a copper stripe, a cabin and a lightning-rod
-- mast (8 parts).
function Pieces.skiff(parent: Instance, frame: CFrame)
	local fwd = frame.LookVector
	local side = frame.RightVector
	local base = frame.Position
	Pieces.block(
		parent,
		frame * CFrame.new(0, 0.5, 1.5),
		Vector3.new(5, 1.8, 7),
		C.timber,
		M.planks
	)
	Pieces.block(
		parent,
		frame * CFrame.new(0, 0.9, 1.5),
		Vector3.new(5.1, 0.4, 7.05),
		C.copper,
		M.metal
	)
	local bowBase = base + UP * 0.5 + fwd * 2
	for _, s in { 1, -1 } do
		local y = side * s
		local center = bowBase + y * 1.25 + fwd * 1.75
		local x = y:Cross(-fwd)
		Pieces.wedge(
			parent,
			CFrame.fromMatrix(center, x, y),
			Vector3.new(1.8, 2.5, 3.5),
			C.timber,
			M.planks
		)
	end
	Pieces.block(
		parent,
		frame * CFrame.new(0, 2.4, 2.4),
		Vector3.new(3, 2.2, 3),
		C.ceramic,
		M.ceramic
	)
	Pieces.block(
		parent,
		frame * CFrame.new(0, 3.65, 2.4),
		Vector3.new(3.6, 0.35, 3.6),
		C.patina,
		M.metal
	)
	Pieces.column(parent, base + UP * 1.4 - fwd * 0.6, 8, 0.35, C.copper)
	Pieces.ball(parent, base + UP * 9.6 - fwd * 0.6, 0.8, C.volt, M.neon)
end

-- A flush strip on a walking surface from a to b (both on the surface).
function Pieces.trail(
	parent: Instance,
	a: Vector3,
	b: Vector3,
	width: number,
	color: Color3,
	material: Enum.Material?,
	lift: number?
): BasePart
	local h = lift or 0.12
	local length = (b - a).Magnitude
	return Kit.decor({
		Size = Vector3.new(width, 0.2, length),
		CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.new(0, h - 0.1, 0),
		Color = color,
		Material = material or M.neon,
		CanCollide = false,
		CastShadow = false,
		Parent = parent,
	})
end

-- Chevron (">") on a walking surface at `at`, pointing along `direction`.
function Pieces.chevron(
	parent: Instance,
	at: Vector3,
	direction: Vector3,
	size: number,
	color: Color3
)
	local d = Vector3.new(direction.X, 0, direction.Z).Unit
	local side = d:Cross(UP)
	for _, s in { -1, 1 } do
		local a = at + side * s * size * 0.5 - d * size * 0.35
		local b = at + d * size * 0.35
		Pieces.trail(parent, a, b, size * 0.2, color, M.neon, 0.14)
	end
end

return Pieces
