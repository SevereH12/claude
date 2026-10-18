--!strict
-- Barometer Bay building pieces: lamps, cottages, domes, balloons, boats,
-- plants, rocks, signs. Every piece is built from Kit parts in the
-- WeatherLab palette. Positions are world space; "bottom" is the point a
-- piece stands on. Pieces never decide where they go: the hub, zone and
-- theme modules do.

local ServerScriptService = game:GetService("ServerScriptService")

local Kit = require(ServerScriptService.Server.World.Kit)
local Palette = require(script.Parent.Palette)
local WLTypes = require(script.Parent.WLTypes)

type Context = WLTypes.Context

local C = Palette.colors

local Pieces = {}

-- The bay's prevailing wind (windsocks, flags, balloons and smoke lean this way).
Pieces.WIND = Vector3.new(0.86, 0, 0.5).Unit

-- Basic shapes -------------------------------------------------------------------

-- Visual box. Collidable unless solid == false.
function Pieces.box(
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
		Material = material or Enum.Material.SmoothPlastic,
		CanCollide = solid ~= false,
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
		Material = material or Enum.Material.SmoothPlastic,
		CanCollide = solid ~= false,
		Parent = parent,
	})
end

-- Upright cylinder standing on `bottom`.
function Pieces.cyl(
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
		Material = material or Enum.Material.SmoothPlastic,
		CanCollide = solid ~= false,
	})
end

function Pieces.ball(
	parent: Instance,
	center: Vector3,
	diameter: number,
	color: Color3,
	material: Enum.Material?,
	solid: boolean?
): BasePart
	return Kit.ball(parent, center, diameter, {
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		CanCollide = solid ~= false,
	})
end

-- Round rod between two points (non-collidable).
function Pieces.rod(
	parent: Instance,
	a: Vector3,
	b: Vector3,
	diameter: number,
	color: Color3,
	material: Enum.Material?
): BasePart
	return Kit.pipe(parent, a, b, diameter, {
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		CanCollide = false,
	})
end

-- Square beam between two points (non-collidable).
function Pieces.beam(
	parent: Instance,
	a: Vector3,
	b: Vector3,
	thickness: number,
	color: Color3,
	material: Enum.Material?
): BasePart
	return Kit.strut(parent, a, b, thickness, {
		Color = color,
		Material = material or Enum.Material.Wood,
		CanCollide = false,
	})
end

-- A glowing part (Neon, non-collidable, no shadow).
function Pieces.glow(part: BasePart, color: Color3): BasePart
	part.Material = Enum.Material.Neon
	part.Color = color
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	return part
end

-- Horizontal unit vector (falls back to +X for vertical input).
local function flatUnit(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 1e-4 then
		return Vector3.new(1, 0, 0)
	end
	return f.Unit
end
Pieces.flatUnit = flatUnit

-- Flat board from a to b (width across, thin vertically). Non-collidable.
function Pieces.plank(
	parent: Instance,
	a: Vector3,
	b: Vector3,
	width: number,
	thick: number,
	color: Color3,
	material: Enum.Material?
): BasePart
	return Pieces.box(
		parent,
		CFrame.lookAt((a + b) / 2, b),
		Vector3.new(width, thick, (b - a).Magnitude),
		color,
		material or Enum.Material.WoodPlanks,
		false
	)
end

-- Light helpers --------------------------------------------------------------------

-- A small lantern hanging at `position`: navy cage, warm glowing core, light.
function Pieces.lantern(
	parent: Instance,
	position: Vector3,
	color: Color3?,
	range: number?,
	withLight: boolean?
): BasePart
	local glowColor = color or Palette.window
	Pieces.box(
		parent,
		CFrame.new(position + Vector3.new(0, 0.85, 0)),
		Vector3.new(1.3, 0.3, 1.3),
		C.ink,
		Enum.Material.Metal,
		false
	)
	local core = Pieces.glow(
		Pieces.box(parent, CFrame.new(position), Vector3.new(0.9, 1.3, 0.9), glowColor),
		glowColor
	)
	if withLight == true then
		Kit.light(core, color or Palette.lamp, range or 18, 1.4)
	end
	return core
end

-- Harbour lamp post: slate-blue post, curled arm, hanging lantern.
function Pieces.lampPost(
	parent: Instance,
	bottom: Vector3,
	height: number,
	armDir: Vector3,
	withLight: boolean?
): BasePart
	Pieces.cyl(parent, bottom, 0.8, 1.6, Palette.stoneDark, Enum.Material.Metal)
	local post = Pieces.cyl(parent, bottom, height, 0.6, C.harbor, Enum.Material.Metal)
	local top = bottom + Vector3.new(0, height, 0)
	local arm = flatUnit(armDir) * 1.8
	Pieces.rod(parent, top - Vector3.new(0, 0.3, 0), top + arm, 0.3, C.harbor, Enum.Material.Metal)
	Pieces.ball(parent, top + Vector3.new(0, 0.2, 0), 0.7, C.slicker, Enum.Material.Metal, false)
	Pieces.lantern(parent, top + arm - Vector3.new(0, 1.2, 0), nil, 22, withLight)
	return post
end

-- Pole of alternating coloured bands (survey pole / mini lighthouse).
function Pieces.stripedPole(
	parent: Instance,
	bottom: Vector3,
	height: number,
	diameter: number,
	colors: { Color3 },
	segments: number
): Vector3
	local h = height / segments
	for i = 0, segments - 1 do
		Pieces.cyl(
			parent,
			bottom + Vector3.new(0, i * h, 0),
			h,
			diameter,
			colors[i % #colors + 1],
			Enum.Material.SmoothPlastic
		)
	end
	return bottom + Vector3.new(0, height, 0)
end

-- Windsock on a pole top, blowing downwind.
function Pieces.windsock(parent: Instance, mount: Vector3, color: Color3, length: number?)
	local len = length or 4
	local wind = Pieces.WIND
	local droop = Vector3.new(0, -0.35, 0)
	local seg = len / 3
	for i = 0, 2 do
		local a = mount + (wind + droop) * (seg * i)
		local b = mount + (wind + droop) * (seg * (i + 1))
		local d = 1.4 - i * 0.3
		Kit.pipe(parent, a, b, d, {
			Color = if i % 2 == 0 then color else C.sailcloth,
			Material = Enum.Material.Fabric,
			CanCollide = false,
		})
	end
end

-- Spinning-cup anemometer on top of a mast.
function Pieces.anemometer(parent: Instance, top: Vector3)
	Pieces.cyl(parent, top, 1.2, 0.3, C.harbor, Enum.Material.Metal, false)
	local hub = top + Vector3.new(0, 1.2, 0)
	for i = 0, 2 do
		local a = math.rad(i * 120 + 15)
		local tip = hub + Vector3.new(math.cos(a), 0, math.sin(a)) * 1.3
		Pieces.rod(parent, hub, tip, 0.15, C.harbor, Enum.Material.Metal)
		Pieces.ball(parent, tip, 0.6, C.sailcloth, Enum.Material.Metal, false)
	end
end

-- Weather vane: rod with an arrow pointing into the wind.
function Pieces.weatherVane(parent: Instance, top: Vector3, scale: number?)
	local s = scale or 1
	Pieces.cyl(parent, top, 2.2 * s, 0.25 * s, C.ink, Enum.Material.Metal, false)
	local mid = top + Vector3.new(0, 1.8 * s, 0)
	local wind = Pieces.WIND
	local cf = CFrame.lookAt(mid, mid - wind)
	Pieces.box(
		parent,
		cf,
		Vector3.new(0.15 * s, 0.25 * s, 3 * s),
		C.ink,
		Enum.Material.Metal,
		false
	)
	Pieces.wedge(
		parent,
		cf * CFrame.new(0, 0, -1.9 * s) * CFrame.Angles(math.rad(90), 0, 0),
		Vector3.new(0.15 * s, 0.8 * s, 0.8 * s),
		C.beacon,
		Enum.Material.Metal,
		false
	)
	Pieces.box(
		parent,
		cf * CFrame.new(0, 0, 1.5 * s),
		Vector3.new(0.12 * s, 0.9 * s, 0.7 * s),
		C.beacon,
		Enum.Material.Metal,
		false
	)
end

-- Buildings ---------------------------------------------------------------------------

export type CottageOptions = {
	width: number,
	depth: number,
	height: number,
	roof: string, -- "clay" (red tiles) or "slate"
	wall: Color3?,
	trim: Color3?,
	name: string?,
	chimney: boolean?,
	instrument: string?, -- "anemometer", "vane" or nil
}

-- Gabled cottage. `cframe` is the ground point at the middle of the house,
-- LookVector out of the front door.
function Pieces.cottage(parent: Instance, cframe: CFrame, o: CottageOptions, rng: Random)
	local w, d, h = o.width, o.depth, o.height
	local wall = o.wall or C.sailcloth
	local trim = o.trim or C.seafoam
	local roofColor = if o.roof == "slate" then C.harbor else C.beacon
	local roofMat = if o.roof == "slate" then Enum.Material.Slate else Enum.Material.Brick
	-- stone footing and plaster walls
	Pieces.box(
		parent,
		cframe * CFrame.new(0, 0.4, 0),
		Vector3.new(w + 0.8, 1.2, d + 0.8),
		Palette.stone,
		Enum.Material.Cobblestone
	)
	Pieces.box(
		parent,
		cframe * CFrame.new(0, 0.8 + h / 2, 0),
		Vector3.new(w, h, d),
		wall,
		Enum.Material.Plaster
	)
	-- gable roof: two wedges meeting at the ridge, overhanging the walls
	local rh = math.min(w, d) * 0.42
	local roofY = 0.8 + h + rh / 2
	local overhang = 0.7
	local half = d / 2 + overhang
	Pieces.wedge(
		parent,
		cframe * CFrame.new(0, roofY, -half / 2),
		Vector3.new(w + overhang * 2, rh, half),
		roofColor,
		roofMat
	)
	Pieces.wedge(
		parent,
		cframe * CFrame.new(0, roofY, half / 2) * CFrame.Angles(0, math.pi, 0),
		Vector3.new(w + overhang * 2, rh, half),
		roofColor,
		roofMat
	)
	Pieces.box(
		parent,
		cframe * CFrame.new(0, 0.8 + h + rh + 0.1, 0),
		Vector3.new(w + overhang * 2 + 0.2, 0.4, 0.6),
		C.piling,
		Enum.Material.Wood,
		false
	)
	-- door with frame, step and a small awning
	local front = -d / 2
	Pieces.box(
		parent,
		cframe * CFrame.new(0, 0.8 + 2.1, front - 0.1),
		Vector3.new(2.6, 4.4, 0.3),
		C.piling,
		Enum.Material.Wood
	)
	Pieces.box(
		parent,
		cframe * CFrame.new(0, 0.8 + 2, front - 0.2),
		Vector3.new(2, 4, 0.3),
		trim,
		Enum.Material.Wood
	)
	Pieces.wedge(
		parent,
		cframe * CFrame.new(0, 0.8 + 4.9, front - 0.8) * CFrame.Angles(0, math.pi, 0),
		Vector3.new(3.4, 0.8, 1.4),
		trim,
		Enum.Material.Fabric,
		false
	)
	-- lit windows with shutters on the front, one on each side
	for _, side in { -1, 1 } do
		local x = side * (w / 2 - 1.8)
		local wy = 0.8 + h * 0.55
		Pieces.glow(
			Pieces.box(
				parent,
				cframe * CFrame.new(x, wy, front - 0.08),
				Vector3.new(1.6, 1.8, 0.2),
				Palette.window
			),
			Palette.window
		)
		for _, s in { -1, 1 } do
			Pieces.box(
				parent,
				cframe * CFrame.new(x + s * 1.25, wy, front - 0.15),
				Vector3.new(0.7, 2, 0.2),
				trim,
				Enum.Material.Wood,
				false
			)
		end
		Pieces.glow(
			Pieces.box(
				parent,
				cframe * CFrame.new(side * (w / 2 + 0.06), wy, 0),
				Vector3.new(0.2, 1.6, 1.6),
				Palette.window
			),
			Palette.window
		)
	end
	-- door lamp
	Pieces.lantern(parent, (cframe * CFrame.new(1.9, 0.8 + 4.2, front - 0.6)).Position, nil, 14)
	-- chimney with a wisp of smoke
	if o.chimney then
		local cx = (if rng:NextNumber() < 0.5 then -1 else 1) * (w / 2 - 1.4)
		local chimney = Pieces.box(
			parent,
			cframe * CFrame.new(cx, 0.8 + h + rh * 0.6, d * 0.18),
			Vector3.new(1.6, rh * 1.2 + 1.5, 1.6),
			Palette.stoneDark,
			Enum.Material.Brick
		)
		Kit.emitter(chimney, {
			Texture = Kit.TEXTURES.smoke,
			Rate = 2,
			Lifetime = NumberRange.new(4, 6),
			Speed = NumberRange.new(2, 3),
			SpreadAngle = Vector2.new(8, 8),
			Acceleration = Pieces.WIND * 1.5,
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(1, 4),
			}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.55),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Color = ColorSequence.new(C.sailcloth),
			EmissionDirection = Enum.NormalId.Top,
		})
	end
	-- name board over the door
	if o.name then
		Kit.sign(
			parent,
			cframe * CFrame.new(0, 0.8 + h - 0.9, front - 0.45) * CFrame.Angles(0, math.pi, 0),
			math.min(w - 1.5, 9),
			1.4,
			o.name,
			nil,
			Palette.SIGN
		)
	end
	-- roof instrument
	local ridge = (cframe * CFrame.new(-w * 0.25, 0.8 + h + rh + 0.3, 0)).Position
	if o.instrument == "anemometer" then
		Pieces.cyl(parent, ridge, 2.5, 0.3, C.harbor, Enum.Material.Metal, false)
		Pieces.anemometer(parent, ridge + Vector3.new(0, 2.5, 0))
	elseif o.instrument == "vane" then
		Pieces.weatherVane(parent, ridge, 0.9)
	end
end

-- Research dome: plaster hemisphere with teal ribs, door, optional
-- observatory slit and a mast. `cframe` faces out of the door.
function Pieces.dome(parent: Instance, cframe: CFrame, diameter: number, slit: boolean?)
	local base = cframe.Position
	local r = diameter / 2
	Pieces.cyl(
		parent,
		base - Vector3.new(0, 0.2, 0),
		1.4,
		diameter + 1.2,
		Palette.stone,
		Enum.Material.Cobblestone
	)
	local center = base + Vector3.new(0, 1.2, 0)
	Pieces.ball(parent, center, diameter, C.sailcloth, Enum.Material.SmoothPlastic)
	-- two crossing ribs and a ring band
	for i, yaw in { 45, -45 } do
		local rib = Kit.decor({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(
				if slit and i == 1 then 1.8 else 0.6,
				diameter * 1.03,
				diameter * 1.03
			),
			CFrame = CFrame.new(center) * cframe.Rotation * CFrame.Angles(0, math.rad(yaw + 90), 0),
			Color = if slit and i == 1 then C.ink else C.seafoam,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			Parent = parent,
		})
		rib.CastShadow = false
	end
	local ringY = r * 0.32
	local ringD = 2 * math.sqrt(r * r - ringY * ringY) * 1.03
	Pieces.cyl(
		parent,
		center + Vector3.new(0, ringY - 0.3, 0),
		0.6,
		ringD,
		C.seafoam,
		Enum.Material.SmoothPlastic,
		false
	)
	-- door porch
	local front = cframe * CFrame.new(0, 0, -r + 0.6)
	Pieces.box(
		parent,
		front * CFrame.new(0, 2.6, -0.6),
		Vector3.new(3.4, 4.4, 2.2),
		C.sailcloth,
		Enum.Material.Plaster
	)
	Pieces.box(
		parent,
		front * CFrame.new(0, 2.4, -1.75),
		Vector3.new(2, 3.8, 0.2),
		C.seafoam,
		Enum.Material.Wood
	)
	Pieces.lantern(parent, (front * CFrame.new(1.6, 4.4, -2)).Position, nil, 14)
	-- top mast with a red beacon
	local top = center + Vector3.new(0, r - 0.4, 0)
	Pieces.cyl(parent, top, 3, 0.3, C.harbor, Enum.Material.Metal, false)
	Pieces.glow(Pieces.ball(parent, top + Vector3.new(0, 3.2, 0), 0.7, C.beacon), C.beacon)
end

-- Weather balloon. Striped envelope with the sensor rod on top, a payload
-- box hanging under it, tethered to `anchors` with ropes (Beams).
function Pieces.balloon(
	ctx: Context,
	parent: Instance,
	center: Vector3,
	diameter: number,
	main: Color3,
	band: Color3,
	anchors: { Vector3 },
	sensor: boolean?
): BasePart
	local r = diameter / 2
	local envelope = Pieces.ball(parent, center, diameter, main, Enum.Material.SmoothPlastic, false)
	Pieces.cyl(
		parent,
		center - Vector3.new(0, 1.4, 0),
		2.8,
		diameter * 1.03,
		band,
		Enum.Material.SmoothPlastic,
		false
	)
	for _, y in { r * 0.62, -r * 0.62 } do
		local d = 2 * math.sqrt(r * r - y * y) * 1.04
		Pieces.cyl(
			parent,
			center + Vector3.new(0, y - 1, 0),
			2,
			d,
			band,
			Enum.Material.SmoothPlastic,
			false
		)
	end
	-- neck and payload
	local neck = center - Vector3.new(0, r + 1.2, 0)
	Pieces.cyl(parent, neck, 1.8, r * 0.45, band, Enum.Material.Fabric, false)
	local payload = neck - Vector3.new(0, 5, 0)
	Pieces.box(
		parent,
		CFrame.new(payload),
		Vector3.new(2.6, 2.2, 2.6),
		C.sailcloth,
		Enum.Material.SmoothPlastic,
		false
	)
	Pieces.box(
		parent,
		CFrame.new(payload + Vector3.new(0, 0.2, 0)),
		Vector3.new(2.7, 0.5, 2.7),
		C.seafoam,
		Enum.Material.SmoothPlastic,
		false
	)
	Kit.cable(ctx, payload + Vector3.new(0, 1.1, 0), neck, { Color = C.ink, Width = 0.12 })
	if sensor ~= false then
		local top = center + Vector3.new(0, r - 0.3, 0)
		Pieces.cyl(parent, top, 4, 0.35, C.ink, Enum.Material.Metal, false)
		local tip =
			Pieces.glow(Pieces.ball(parent, top + Vector3.new(0, 4.2, 0), 1, C.spark), C.spark)
		Kit.light(tip, C.spark, 26, 1.6)
	end
	for _, anchor in anchors do
		Kit.cable(ctx, anchor, neck + Vector3.new(0, 0.6, 0), {
			Color = C.sailcloth,
			Width = 0.18,
			CurveSize = 2,
		})
	end
	return envelope
end

-- Nature -------------------------------------------------------------------------------

-- Round seaside tree: trunk and a cluster of leafy balls.
function Pieces.tree(parent: Instance, bottom: Vector3, scale: number, rng: Random)
	local h = 5 * scale
	Pieces.cyl(parent, bottom, h + 1, 1.1 * scale, C.piling, Enum.Material.Wood)
	local top = bottom + Vector3.new(0, h + 1.5 * scale, 0)
	local leaf = if rng:NextNumber() < 0.5 then C.kelp else Palette.leafDark
	Pieces.ball(parent, top, 6 * scale, leaf, Enum.Material.Grass, false)
	for i = 1, 2 do
		local a = rng:NextNumber(0, math.pi * 2)
		local off = Vector3.new(math.cos(a), rng:NextNumber(-0.3, 0.6), math.sin(a)) * 2.4 * scale
		Pieces.ball(
			parent,
			top + off,
			rng:NextNumber(3.4, 4.6) * scale,
			if i == 1 then Palette.leafLight else leaf,
			Enum.Material.Grass,
			false
		)
	end
end

-- Leaning palm: curved trunk of short segments and a crown of fronds.
function Pieces.palm(parent: Instance, bottom: Vector3, height: number, rng: Random)
	local lean = Pieces.WIND * rng:NextNumber(0.15, 0.3)
		+ Vector3.new(rng:NextNumber(-0.1, 0.1), 0, rng:NextNumber(-0.1, 0.1))
	local p = bottom
	local segments = 4
	for i = 1, segments do
		local t = i / segments
		local nextP = bottom + Vector3.new(0, height * t, 0) + lean * height * t * t
		Pieces.rod(
			parent,
			p,
			nextP,
			1.3 - i * 0.12,
			if i % 2 == 0 then C.piling else C.driftwood,
			Enum.Material.Wood
		)
		p = nextP
	end
	local fronds = 6
	local phase = rng:NextNumber(0, math.pi * 2)
	for i = 1, fronds do
		local a = phase + i / fronds * math.pi * 2
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local tip = p + out * 5.5 - Vector3.new(0, 2.2, 0)
		local mid = p + out * 2.8 + Vector3.new(0, 0.4, 0)
		Pieces.plank(parent, p, mid, 1.8, 0.3, C.kelp, Enum.Material.Grass)
		Pieces.plank(parent, mid, tip, 1.4, 0.3, Palette.leafDark, Enum.Material.Grass)
	end
	for i = 1, 2 do
		Pieces.ball(
			parent,
			p + Vector3.new(i - 1.5, -0.7, 0.4),
			0.9,
			C.piling,
			Enum.Material.Wood,
			false
		)
	end
end

-- Saguaro-style cactus with one or two arms.
function Pieces.cactus(parent: Instance, bottom: Vector3, height: number, rng: Random)
	local green = C.kelp:Lerp(C.ink, 0.12)
	Pieces.cyl(parent, bottom, height, 1.7, green, Enum.Material.Grass)
	Pieces.ball(parent, bottom + Vector3.new(0, height, 0), 1.7, green, Enum.Material.Grass, false)
	local arms = rng:NextInteger(1, 2)
	local a0 = rng:NextNumber(0, math.pi * 2)
	for i = 1, arms do
		local a = a0 + (i - 1) * math.pi
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local y = height * rng:NextNumber(0.35, 0.6)
		local elbow = bottom + Vector3.new(0, y, 0) + out * 1.8
		Pieces.rod(parent, bottom + Vector3.new(0, y, 0), elbow, 1.1, green, Enum.Material.Grass)
		local up = height * rng:NextNumber(0.2, 0.35)
		Pieces.cyl(
			parent,
			elbow - Vector3.new(0, 0.5, 0),
			up + 0.5,
			1.1,
			green,
			Enum.Material.Grass,
			false
		)
		Pieces.ball(parent, elbow + Vector3.new(0, up, 0), 1.1, green, Enum.Material.Grass, false)
	end
	if rng:NextNumber() < 0.5 then
		Pieces.ball(
			parent,
			bottom + Vector3.new(0, height + 0.8, 0),
			0.6,
			C.beacon,
			Enum.Material.SmoothPlastic,
			false
		)
	end
end

-- Low leafy bush.
function Pieces.bush(parent: Instance, bottom: Vector3, size: number, rng: Random)
	for i = 1, 2 do
		local off = Vector3.new(rng:NextNumber(-0.4, 0.4), 0, rng:NextNumber(-0.4, 0.4)) * size
		Pieces.ball(
			parent,
			bottom + off + Vector3.new(0, size * 0.25, 0),
			size * (if i == 1 then 1 else 0.75),
			if i == 1 then C.kelp else Palette.leafLight,
			Enum.Material.Grass,
			false
		)
	end
end

-- A posy of little flowers (one stem part plus heads).
function Pieces.flowers(parent: Instance, bottom: Vector3, rng: Random)
	local colors = { C.beacon, C.slicker, C.sailcloth, C.seafoam }
	for _ = 1, 3 do
		local p = bottom
			+ Vector3.new(
				rng:NextNumber(-1.2, 1.2),
				rng:NextNumber(0.5, 0.9),
				rng:NextNumber(-1.2, 1.2)
			)
		Pieces.ball(
			parent,
			p,
			rng:NextNumber(0.5, 0.8),
			colors[rng:NextInteger(1, #colors)],
			Enum.Material.SmoothPlastic,
			false
		)
	end
end

-- Tuft of beach grass: three blades fanning out.
function Pieces.tuft(parent: Instance, bottom: Vector3, rng: Random, color: Color3?)
	local green = color or C.kelp
	for i = 1, 3 do
		local a = rng:NextNumber(0, math.pi * 2)
		local tip = bottom
			+ Vector3.new(math.cos(a) * 0.9, rng:NextNumber(1.4, 2.4), math.sin(a) * 0.9)
		Pieces.plank(
			parent,
			bottom,
			tip,
			0.5,
			0.15,
			if i == 2 then Palette.leafLight else green,
			Enum.Material.Grass
		)
	end
end

-- Cluster of slate-blue rocks.
function Pieces.rocks(parent: Instance, bottom: Vector3, size: number, rng: Random, color: Color3?)
	Kit.rock(parent, bottom - Vector3.new(0, size * 0.25, 0), size, rng, {
		Color = (color or Palette.stone):Lerp(C.ink, rng:NextNumber(0, 0.18)),
		Material = Enum.Material.Slate,
	})
end

-- Props ---------------------------------------------------------------------------------

function Pieces.crate(parent: Instance, cframe: CFrame, size: number)
	Pieces.box(
		parent,
		cframe * CFrame.new(0, size / 2, 0),
		Vector3.new(size, size, size),
		C.driftwood,
		Enum.Material.WoodPlanks
	)
	Pieces.box(
		parent,
		cframe * CFrame.new(0, size / 2, 0),
		Vector3.new(size + 0.1, size * 0.2, size + 0.1),
		C.piling,
		Enum.Material.Wood,
		false
	)
end

function Pieces.barrel(parent: Instance, bottom: Vector3, color: Color3?)
	Pieces.cyl(parent, bottom, 2.6, 2, color or C.seafoam, Enum.Material.Wood)
	Pieces.cyl(parent, bottom + Vector3.new(0, 0.5, 0), 0.3, 2.1, C.ink, Enum.Material.Metal, false)
	Pieces.cyl(parent, bottom + Vector3.new(0, 1.8, 0), 0.3, 2.1, C.ink, Enum.Material.Metal, false)
end

-- Park bench; cframe on the ground, LookVector = where you look when seated.
function Pieces.bench(parent: Instance, cframe: CFrame)
	Pieces.box(
		parent,
		cframe * CFrame.new(0, 1.4, 0),
		Vector3.new(5, 0.4, 1.6),
		C.driftwood,
		Enum.Material.WoodPlanks
	)
	Pieces.box(
		parent,
		cframe * CFrame.new(0, 2.6, 0.75),
		Vector3.new(5, 1.4, 0.3),
		C.driftwood,
		Enum.Material.WoodPlanks,
		false
	)
	for _, x in { -2, 2 } do
		Pieces.box(
			parent,
			cframe * CFrame.new(x, 0.9, 0.2),
			Vector3.new(0.4, 1.8, 1.8),
			C.ink,
			Enum.Material.Metal,
			false
		)
	end
end

-- Market stall with a striped awning, selling bottled-lightning souvenirs.
-- cframe on the ground, LookVector toward the customers.
function Pieces.stall(parent: Instance, cframe: CFrame, color: Color3, rng: Random)
	Pieces.box(
		parent,
		cframe * CFrame.new(0, 1.2, 0),
		Vector3.new(5.4, 2.4, 2.2),
		C.driftwood,
		Enum.Material.WoodPlanks
	)
	Pieces.box(
		parent,
		cframe * CFrame.new(0, 2.5, 0),
		Vector3.new(5.8, 0.25, 2.6),
		C.piling,
		Enum.Material.Wood,
		false
	)
	for _, x in { -2.6, 2.6 } do
		for _, z in { -1.2, 1.2 } do
			Pieces.box(
				parent,
				cframe * CFrame.new(x, 2.6, z),
				Vector3.new(0.35, 5.2, 0.35),
				C.piling,
				Enum.Material.Wood,
				false
			)
		end
	end
	for i = 0, 3 do
		Pieces.box(
			parent,
			cframe * CFrame.new(-2.25 + i * 1.5, 5.3, -0.3) * CFrame.Angles(math.rad(18), 0, 0),
			Vector3.new(1.5, 0.25, 4),
			if i % 2 == 0 then color else C.sailcloth,
			Enum.Material.Fabric,
			false
		)
	end
	for i = -1, 1 do
		local bottle = (cframe * CFrame.new(i * 1.5, 2.65, 0.1)).Position
		local glass = Pieces.cyl(parent, bottle, 1.1, 0.8, C.sailcloth, Enum.Material.Glass, false)
		glass.Transparency = 0.4
		Pieces.glow(
			Pieces.cyl(parent, bottle + Vector3.new(0, 0.15, 0), 0.7, 0.4, C.spark),
			C.spark
		)
	end
	Pieces.crate(
		parent,
		cframe * CFrame.new(3.8, 0, 0.6) * CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0),
		1.6
	)
end

-- Flower planter box.
function Pieces.planter(parent: Instance, cframe: CFrame, length: number, rng: Random)
	Pieces.box(
		parent,
		cframe * CFrame.new(0, 0.8, 0),
		Vector3.new(length, 1.6, 2.2),
		C.driftwood,
		Enum.Material.WoodPlanks
	)
	Pieces.box(
		parent,
		cframe * CFrame.new(0, 1.65, 0),
		Vector3.new(length - 0.4, 0.3, 1.8),
		C.piling,
		Enum.Material.Ground,
		false
	)
	local n = math.max(2, math.floor(length / 2.2))
	local colors = { C.beacon, C.slicker, C.sailcloth }
	for i = 1, n do
		local x = -length / 2 + (i - 0.5) * length / n
		Pieces.ball(
			parent,
			(cframe * CFrame.new(x, 2.2, rng:NextNumber(-0.3, 0.3))).Position,
			1.1,
			if i % 2 == 0 then C.kelp else colors[rng:NextInteger(1, #colors)],
			Enum.Material.Grass,
			false
		)
	end
end

-- Beach umbrella with a striped canopy.
function Pieces.umbrella(parent: Instance, bottom: Vector3, color: Color3)
	local tilt = Pieces.WIND * 0.6
	local top = bottom + Vector3.new(0, 6, 0) + tilt
	Pieces.rod(parent, bottom, top, 0.3, C.sailcloth, Enum.Material.Metal)
	local canopy = CFrame.lookAt(top, top + (Vector3.new(0, 1, 0) + tilt * 0.08).Unit)
		* CFrame.Angles(math.rad(-90), 0, 0)
	Kit.decor({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, 7.5, 7.5),
		CFrame = canopy * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = Enum.Material.Fabric,
		CanCollide = false,
		Parent = parent,
	})
	Kit.decor({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.7, 3.6, 3.6),
		CFrame = canopy * CFrame.new(0, 0.4, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = C.sailcloth,
		Material = Enum.Material.Fabric,
		CanCollide = false,
		Parent = parent,
	})
end

-- Floating marker buoy (bottom = waterline).
function Pieces.buoy(parent: Instance, waterline: Vector3, color: Color3)
	Pieces.ball(parent, waterline, 2.6, color, Enum.Material.SmoothPlastic, false)
	Pieces.cyl(
		parent,
		waterline + Vector3.new(0, 0.2, 0),
		0.6,
		2.4,
		C.sailcloth,
		Enum.Material.SmoothPlastic,
		false
	)
	Pieces.cyl(
		parent,
		waterline + Vector3.new(0, 1, 0),
		1.8,
		0.3,
		C.ink,
		Enum.Material.Metal,
		false
	)
	Pieces.glow(Pieces.ball(parent, waterline + Vector3.new(0, 3, 0), 0.6, C.slicker), C.slicker)
end

-- Little boat floating with its waterline at cframe (LookVector = bow).
function Pieces.boat(
	parent: Instance,
	cframe: CFrame,
	hull: Color3,
	length: number,
	withCabin: boolean
)
	local w = length * 0.42
	Pieces.box(
		parent,
		cframe * CFrame.new(0, 0.3, 0.6),
		Vector3.new(w, 1.8, length * 0.7),
		hull,
		Enum.Material.Wood,
		false
	)
	Pieces.wedge(
		parent,
		cframe * CFrame.new(0, 0.3, -length * 0.35),
		Vector3.new(w, 1.8, length * 0.3),
		hull,
		Enum.Material.Wood,
		false
	)
	Pieces.box(
		parent,
		cframe * CFrame.new(0, 1.3, 0.6),
		Vector3.new(w + 0.2, 0.3, length * 0.7 + 0.1),
		C.sailcloth,
		Enum.Material.Wood,
		false
	)
	if withCabin then
		Pieces.box(
			parent,
			cframe * CFrame.new(0, 2.4, 1.6),
			Vector3.new(w * 0.7, 2.2, length * 0.3),
			C.sailcloth,
			Enum.Material.Plaster,
			false
		)
		Pieces.box(
			parent,
			cframe * CFrame.new(0, 3.6, 1.6),
			Vector3.new(w * 0.8, 0.3, length * 0.34),
			C.beacon,
			Enum.Material.Wood,
			false
		)
		Pieces.cyl(
			parent,
			(cframe * CFrame.new(0, 3.7, 1.2)).Position,
			4.5,
			0.3,
			C.piling,
			Enum.Material.Wood,
			false
		)
	else
		Pieces.box(
			parent,
			cframe * CFrame.new(0, 1.2, 0.8),
			Vector3.new(w - 0.3, 0.3, 1),
			C.driftwood,
			Enum.Material.Wood,
			false
		)
	end
end

-- Framed sign, optionally on two posts down to groundY. `cframe` is the
-- board centre, LookVector = reading side. With `back`, the back face gets
-- its own text (and the frame is a rim instead of a backing plate).
function Pieces.signBoard(
	parent: Instance,
	cframe: CFrame,
	width: number,
	height: number,
	title: string,
	subtitle: string?,
	style: Kit.SignStyle,
	groundY: number?,
	back: { title: string, subtitle: string? }?
): BasePart
	local board = Kit.sign(parent, cframe, width, height, title, subtitle, style)
	local thick = style.thickness or 0.6
	if back then
		Kit.faceText(board, Enum.NormalId.Back, back.title, back.subtitle, style)
		for _, s in { -1, 1 } do
			Pieces.box(
				parent,
				cframe * CFrame.new(0, s * (height / 2 + 0.2), 0),
				Vector3.new(width + 0.6, 0.4, thick + 0.3),
				C.piling,
				Enum.Material.Wood,
				false
			)
		end
	else
		Pieces.box(
			parent,
			cframe * CFrame.new(0, 0, thick / 2 + 0.15),
			Vector3.new(width + 0.6, height + 0.6, 0.3),
			C.piling,
			Enum.Material.Wood,
			false
		)
	end
	if groundY then
		for _, s in { -1, 1 } do
			local p = (cframe * CFrame.new(s * (width / 2 - 0.6), 0, thick / 2 + 0.45)).Position
			Pieces.box(
				parent,
				CFrame.new(Vector3.new(p.X, (groundY + p.Y) / 2, p.Z)) * cframe.Rotation,
				Vector3.new(0.6, p.Y - groundY, 0.6),
				C.piling,
				Enum.Material.Wood
			)
		end
	end
	return board
end

-- Fingerpost arm: a board with a pointed tip, pointing along `dir` from `root`.
function Pieces.arm(
	parent: Instance,
	root: Vector3,
	dir: Vector3,
	length: number,
	color: Color3,
	text: string
)
	local d = Pieces.flatUnit(dir)
	local center = root + d * (length / 2 + 0.4)
	local cf = CFrame.lookAt(center, center + d)
	local board = Pieces.box(
		parent,
		cf,
		Vector3.new(0.35, 1.3, length),
		color,
		Enum.Material.SmoothPlastic,
		false
	)
	for _, s in { 1, -1 } do
		Pieces.wedge(
			parent,
			cf
				* CFrame.new(0, s * 0.325, -length / 2 - 0.4)
				* CFrame.Angles(0, 0, if s > 0 then 0 else math.pi),
			Vector3.new(0.35, 0.65, 0.8),
			color,
			Enum.Material.SmoothPlastic,
			false
		)
	end
	local style: Kit.SignStyle = {
		boardColor = color,
		titleColor = C.sailcloth,
		strokeColor = C.ink,
		titleFont = Enum.Font.LuckiestGuy,
	}
	Kit.faceText(board, Enum.NormalId.Right, text, nil, style)
	Kit.faceText(board, Enum.NormalId.Left, text, nil, style)
end

return Pieces
