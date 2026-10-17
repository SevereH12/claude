--!strict
-- StormPunk building pieces: insulators, pylons, lamps, coils, signs,
-- props. Every piece uses the palette and composes Kit primitives, so all
-- the world's modules share one look. Positions are world space; "bottom"
-- is the point a piece stands on.

local ServerScriptService = game:GetService("ServerScriptService")

local World = ServerScriptService.Server.World
local Kit = require(World.Kit)
local WorldTypes = require(World.Types)
local Palette = require(script.Parent.Palette)

type Context = WorldTypes.Context

local C = Palette.colors
local T = Palette.tints
local M = Palette.materials

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
	material: Enum.Material?
): BasePart
	return Kit.strut(parent, a, b, thickness, {
		Color = color,
		Material = material or M.metal,
		CanCollide = false,
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

-- Flat disc lying on a surface (top at bottom.Y + thickness): floor inlays.
function Pieces.disc(
	parent: Instance,
	bottom: Vector3,
	diameter: number,
	thickness: number,
	color: Color3,
	material: Enum.Material?
): BasePart
	local disc = Kit.cylinder(parent, bottom, thickness, diameter, {
		Color = color,
		Material = material or M.ceramic,
		CanCollide = false,
		CastShadow = false,
	})
	return disc
end

-- Energy ------------------------------------------------------------------------

function Pieces.glow(part: BasePart, color: Color3, range: number, brightness: number?): PointLight
	return Kit.light(part, color, range, brightness or 1.6, false)
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
		Kit.emitter(orb, {
			Texture = Kit.TEXTURES.sparkle,
			Color = ColorSequence.new(color or C.volt),
			LightEmission = 1,
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, diameter * 0.18),
				NumberSequenceKeypoint.new(1, 0),
			}),
			Lifetime = NumberRange.new(0.3, 0.7),
			Rate = 14,
			Speed = NumberRange.new(4, 9),
			SpreadAngle = Vector2.new(180, 180),
			Transparency = NumberSequence.new(0.1),
		})
	end
	return orb
end

-- Electric sparks crackling off a part's surface.
function Pieces.sparks(part: BasePart, color: Color3?, rate: number?): ParticleEmitter
	return Kit.emitter(part, {
		Texture = Kit.TEXTURES.sparkle,
		Color = ColorSequence.new(color or C.volt),
		LightEmission = 1,
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Lifetime = NumberRange.new(0.2, 0.5),
		Rate = rate or 6,
		Speed = NumberRange.new(2, 6),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -12, 0),
	})
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
	Pieces.strut(parent, l0, leftTop, 0.35, C.copper)
	Pieces.strut(parent, r0, rightTop, 0.35, C.copper)
	for i, t in { 0.3, 0.6, 0.9 } do
		Pieces.liveCable(
			ctx,
			l0:Lerp(leftTop, t),
			r0:Lerp(rightTop, t),
			C.volt,
			0.25 + i * 0.05,
			-0.8 - i * 0.4
		)
	end
end

-- Structures ------------------------------------------------------------------------

-- Border post: copper pile, two insulator discs and a lamp cap in `color`.
-- Returns the cable attach point.
function Pieces.insulatorPost(
	parent: Instance,
	bottom: Vector3,
	height: number,
	color: Color3
): Vector3
	Pieces.column(parent, bottom - Vector3.new(0, 1, 0), height + 1, 1.1, C.copper, M.metal, true)
	local top = bottom + Vector3.new(0, height, 0)
	Pieces.column(parent, top - Vector3.new(0, 1.9, 0), 0.45, 2.2, C.ceramic, M.ceramic)
	Pieces.column(parent, top - Vector3.new(0, 1.1, 0), 0.45, 1.8, C.ceramic, M.ceramic)
	Pieces.ball(parent, top + Vector3.new(0, 0.25, 0), 1.1, color, M.neon)
	return top - Vector3.new(0, 1.5, 0)
end

-- Lamp post: iron post, brass hood, glowing lantern. Returns the lantern.
function Pieces.lamp(
	parent: Instance,
	bottom: Vector3,
	height: number,
	glowColor: Color3?,
	lightRange: number?
): BasePart
	Pieces.column(parent, bottom, height, 0.55, C.iron, M.metal, true)
	Pieces.column(parent, bottom, 0.8, 1.3, C.iron, M.metal)
	local lanternCenter = bottom + Vector3.new(0, height + 0.7, 0)
	local lantern = Pieces.ball(parent, lanternCenter, 1.3, glowColor or C.volt, M.neon)
	Pieces.column(parent, lanternCenter + Vector3.new(0, 0.55, 0), 0.4, 1.9, C.brass)
	if lightRange then
		Pieces.glow(lantern, glowColor or C.volt, lightRange, 1.4)
	end
	return lantern
end

-- Lattice Tesla pylon with a crossarm. Returns the two crossarm ends and the tip.
function Pieces.pylon(
	parent: Instance,
	bottom: Vector3,
	height: number,
	yawDeg: number,
	baseHalf: number?
): (Vector3, Vector3, Vector3)
	local cf = CFrame.new(bottom) * CFrame.Angles(0, math.rad(yawDeg), 0)
	local b = baseHalf or height * 0.12
	local t = math.max(b * 0.3, 0.8)
	local corners = { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }
	local mids: { Vector3 } = {}
	for _, c in corners do
		local foot = cf:PointToWorldSpace(Vector3.new(c[1] * b, 0, c[2] * b))
		local head = cf:PointToWorldSpace(Vector3.new(c[1] * t, height, c[2] * t))
		Pieces.strut(parent, foot, head, 0.45, C.iron)
		table.insert(mids, foot:Lerp(head, 0.45))
	end
	for i = 1, 4 do
		Pieces.strut(parent, mids[i], mids[i % 4 + 1], 0.3, C.copper)
	end
	-- crossarm
	local armY = height * 0.86
	local armHalf = math.max(b * 1.1, 3)
	local armA = cf:PointToWorldSpace(Vector3.new(-armHalf, armY, 0))
	local armB = cf:PointToWorldSpace(Vector3.new(armHalf, armY, 0))
	Pieces.strut(parent, armA, armB, 0.5, C.iron)
	local hangA = Pieces.insulator(parent, armA - Vector3.new(0, 1.6, 0), 0.6, 2)
	local hangB = Pieces.insulator(parent, armB - Vector3.new(0, 1.6, 0), 0.6, 2)
	local tip = cf:PointToWorldSpace(Vector3.new(0, height, 0))
	Pieces.column(parent, tip, 2.5, 0.35, C.copper)
	Pieces.ball(parent, tip + Vector3.new(0, 2.8, 0), 0.9, C.volt, M.neon)
	return hangA - Vector3.new(0, 1.4, 0),
		hangB - Vector3.new(0, 1.4, 0),
		tip + Vector3.new(0, 2.8, 0)
end

-- Banded chimney / smokestack. Returns its top centre.
function Pieces.smokestack(
	parent: Instance,
	bottom: Vector3,
	height: number,
	diameter: number,
	smoke: boolean?
): Vector3
	Pieces.column(parent, bottom, height, diameter, C.copper, M.metal, true)
	local bands = math.max(2, math.floor(height / 9))
	for i = 1, bands do
		local y = height * (i / (bands + 1))
		Pieces.column(
			parent,
			bottom + Vector3.new(0, y, 0),
			1.1,
			diameter + 0.5,
			if i % 2 == 0 then C.patina else C.brass
		)
	end
	local top = bottom + Vector3.new(0, height, 0)
	Pieces.column(parent, top - Vector3.new(0, 1.2, 0), 1.6, diameter + 1.2, C.iron)
	if smoke then
		local vent = Pieces.block(
			parent,
			CFrame.new(top + Vector3.new(0, 0.2, 0)),
			Vector3.new(diameter * 0.7, 0.2, diameter * 0.7),
			C.soot
		)
		vent.Transparency = 1
		Kit.emitter(vent, {
			Texture = Kit.TEXTURES.smoke,
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

-- Big riveted storage tank (gasometer / capacitor) with a patina dome.
function Pieces.tank(
	parent: Instance,
	bottom: Vector3,
	height: number,
	diameter: number,
	glowing: boolean?
)
	Pieces.column(parent, bottom, height, diameter, C.copper, M.metal, true)
	Pieces.column(parent, bottom, 1.2, diameter + 1, C.iron, M.metal, true)
	for i, y in { 0.33, 0.66 } do
		Pieces.column(
			parent,
			bottom + Vector3.new(0, height * y, 0),
			0.8,
			diameter + 0.4,
			if i == 1 then C.brass else C.patina
		)
	end
	Pieces.column(parent, bottom + Vector3.new(0, height, 0), 1, diameter + 0.6, C.patina)
	Pieces.ball(
		parent,
		bottom + Vector3.new(0, height + 0.2, 0),
		diameter * 0.82,
		C.patina,
		M.metal
	)
	if glowing then
		Pieces.orb(parent, bottom + Vector3.new(0, height + diameter * 0.42, 0), 2, C.volt, 18)
	end
end

-- Props ----------------------------------------------------------------------------

function Pieces.crate(
	parent: Instance,
	bottom: Vector3,
	size: number,
	yawDeg: number,
	color: Color3?
): BasePart
	local cf = CFrame.new(bottom + Vector3.new(0, size / 2, 0))
		* CFrame.Angles(0, math.rad(yawDeg), 0)
	local box =
		Pieces.block(parent, cf, Vector3.new(size, size, size), color or C.timber, M.wood, true)
	Pieces.block(
		parent,
		cf * CFrame.new(0, 0, 0),
		Vector3.new(size + 0.1, size * 0.18, size + 0.1),
		T.brassDark,
		M.metal
	)
	return box
end

function Pieces.barrel(parent: Instance, bottom: Vector3, color: Color3?)
	Pieces.column(parent, bottom, 3, 2.2, color or C.patina, M.metal, true)
	Pieces.column(parent, bottom + Vector3.new(0, 1.3, 0), 0.4, 2.4, C.iron)
end

-- Small rock cluster from Kit.rock in palette stone tones.
function Pieces.rocks(parent: Instance, bottom: Vector3, size: number, rng: Random, color: Color3?)
	Kit.rock(parent, bottom - Vector3.new(0, size * 0.2, 0), size, rng, {
		Color = color or T.rock,
		Material = Enum.Material.Slate,
		CanCollide = size > 3,
	})
end

-- Tuft of dune grass / scrub: two crossed blades.
function Pieces.tuft(parent: Instance, bottom: Vector3, rng: Random, color: Color3?)
	local h = rng:NextNumber(1.2, 2.4)
	local yaw = rng:NextNumber(0, 180)
	for i = 0, 1 do
		local cf = CFrame.new(bottom + Vector3.new(0, h / 2 - 0.1, 0))
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
	local s = rng:NextNumber(1.6, 3)
	Pieces.ball(
		parent,
		bottom + Vector3.new(0, s * 0.3, 0),
		s,
		color or C.sage,
		Enum.Material.Grass
	)
	if rng:NextNumber() < 0.5 then
		Pieces.ball(
			parent,
			bottom + Vector3.new(s * 0.45, s * 0.2, rng:NextNumber(-0.5, 0.5)),
			s * 0.7,
			T.sageDark,
			Enum.Material.Grass
		)
	end
end

-- Railing from a to b (points on the walking surface).
function Pieces.railing(
	parent: Instance,
	a: Vector3,
	b: Vector3,
	height: number,
	spacing: number,
	color: Color3?
)
	-- collidable, so nobody walks off a bridge
	local length = (b - a).Magnitude
	local posts = math.max(1, math.floor(length / spacing + 0.5))
	local h = Vector3.new(0, height, 0)
	for k = 0, posts do
		local p = a:Lerp(b, k / posts)
		Pieces.strut(parent, p, p + h, 0.3, C.iron).CanCollide = true
	end
	Pieces.strut(parent, a + h, b + h, 0.3, color or C.brass).CanCollide = true
	Pieces.strut(parent, a + h * 0.5, b + h * 0.5, 0.2, C.iron).CanCollide = true
end

-- Amber/black striped barricade centred at `bottom`, facing `cframe`.
function Pieces.barricade(parent: Instance, cframe: CFrame, width: number)
	local stripes = math.max(3, math.floor(width / 2))
	local w = width / stripes
	for i = 0, stripes - 1 do
		local x = -width / 2 + (i + 0.5) * w
		Pieces.block(
			parent,
			cframe * CFrame.new(x, 2.4, 0) * CFrame.Angles(0, 0, math.rad(0)),
			Vector3.new(w, 1.4, 0.5),
			if i % 2 == 0 then C.hazard else C.soot,
			Enum.Material.SmoothPlastic,
			true
		)
	end
	for _, side in { -1, 1 } do
		Pieces.block(
			parent,
			cframe * CFrame.new(side * (width / 2 - 0.4), 1.4, 0),
			Vector3.new(0.5, 2.8, 1.6),
			C.iron,
			M.metal,
			true
		)
	end
	local lampL = Pieces.ball(
		parent,
		(cframe * CFrame.new(-width / 2 + 0.4, 3.4, 0)).Position,
		0.8,
		C.hazard,
		M.neon
	)
	Pieces.ball(
		parent,
		(cframe * CFrame.new(width / 2 - 0.4, 3.4, 0)).Position,
		0.8,
		C.hazard,
		M.neon
	)
	return lampL
end

-- Sign board with a brass frame. Text faces cframe.LookVector.
function Pieces.framedSign(
	parent: Instance,
	cframe: CFrame,
	width: number,
	height: number,
	title: string,
	subtitle: string?,
	style: Kit.SignStyle
): BasePart
	local board = Kit.sign(parent, cframe, width, height, title, subtitle, style)
	local t = 0.5
	local hw, hh = width / 2 + t / 2, height / 2 + t / 2
	local d = (style.thickness or 0.6) + 0.2
	for _, e in { { 0, hh, width + 2 * t, t }, { 0, -hh, width + 2 * t, t } } do
		Pieces.block(
			parent,
			cframe * CFrame.new(e[1], e[2], 0),
			Vector3.new(e[3], e[4], d),
			C.brass
		)
	end
	for _, side in { -1, 1 } do
		Pieces.block(
			parent,
			cframe * CFrame.new(side * hw, 0, 0),
			Vector3.new(t, height, d),
			C.brass
		)
	end
	return board
end

-- Arrow-shaped sign pointing along `direction` (horizontal), text on both
-- sides. `center` is the middle of the board.
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
	local style = Palette.sign(color, true)
	Kit.sign(parent, cf, length, height, title, nil, style)
	-- arrow head: two wedges forming a triangle in the board's plane
	local headLength = height * 0.9
	local half = height * 0.85
	local base = center + d * (length / 2)
	for _, s in { 1, -1 } do
		local up = UP * s
		local mid = base + up * (half / 2) + d * (headLength / 2)
		local wedgeX = if s == 1 then x else -x
		local cframe = CFrame.fromMatrix(mid, wedgeX, up)
		Pieces.wedge(parent, cframe, Vector3.new(0.8, half, headLength), color, M.neon)
	end
	-- tail notch: a brass cap
	Pieces.block(
		parent,
		cf * CFrame.new(-length / 2 - 0.3, 0, 0),
		Vector3.new(0.6, height + 0.4, 1),
		C.brass
	)
end

-- Timber pier on piles from a to b (sea-level points) with its deck at
-- deckY, a lamp and a bollard at the far end and an optional name board.
function Pieces.pier(parent: Instance, from: Vector3, to: Vector3, deckY: number, label: string?)
	local a = Vector3.new(from.X, deckY, from.Z)
	local b = Vector3.new(to.X, deckY, to.Z)
	local dir = Vector3.new(b.X - a.X, 0, b.Z - a.Z).Unit
	local side = dir:Cross(UP)
	Pieces.block(
		parent,
		CFrame.lookAt((a + b) / 2, b),
		Vector3.new(5, 0.5, (b - a).Magnitude),
		C.timber,
		M.planks,
		true
	)
	local n = math.max(1, math.floor((b - a).Magnitude / 7))
	for i = 0, n do
		local p = a:Lerp(b, i / n)
		for _, s in { -1, 1 } do
			local foot = p + side * s * 2.2
			Pieces.column(
				parent,
				Vector3.new(foot.X, -6, foot.Z),
				foot.Y + 6.8,
				0.8,
				T.timberDark,
				M.wood
			)
		end
	end
	Pieces.lamp(parent, b - dir * 1.5 + side * 2, 6, C.volt, 22)
	Pieces.column(parent, b - dir * 1.5 - side * 1.8, 1.2, 1.2, C.brass)
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
-- pointed timber hull with a copper stripe, a cabin and a lightning-rod mast.
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
		M.planks
	)
	Pieces.wedge(
		parent,
		frame * CFrame.new(0, 4, 2.4) * CFrame.Angles(0, math.rad(90), 0),
		Vector3.new(3.4, 1, 3.4),
		C.patina
	)
	Pieces.column(parent, base + UP * 1.4 - fwd * 0.6, 8, 0.35, C.copper)
	Pieces.insulator(parent, base + UP * 9.4 - fwd * 0.6, 0.5, 2)
	Pieces.ball(parent, base + UP * 10.6 - fwd * 0.6, 0.6, C.volt, M.neon)
	Pieces.column(parent, (frame * CFrame.new(1, 3.5, 3.4)).Position, 1.6, 0.7, C.iron)
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
		Pieces.trail(parent, a, b, size * 0.18, color, M.neon, 0.14)
	end
end

return Pieces
