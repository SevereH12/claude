--!strict
-- Part-built ground: islands, plateaus, beaches, ramps and rocks made of
-- chunky anchored SmoothPlastic blocks instead of Terrain, so the map reads
-- like a clean hand-built diorama. Every style pack builds its ground with
-- these and puts walkable ground in ctx.folders.ground (Workspace.Map.Ground,
-- which the strike raycast hits).
--
-- Conventions:
--   * Every function takes a parent and a colour and returns what it built.
--   * Ground parts are collidable and queryable but never fire touches.
--   * No unions, meshes, decals or textured materials: colour carries the
--     look. Each part's colour is jittered by about +/-4% brightness, keyed
--     off its position, so builds are identical every time and large flat
--     surfaces show their facets. The pieces of one disc/ring share a shade,
--     since they overlap on the same plane and mixed shades would flicker.
--   * A `top` CFrame is the centre of the shape's top face; its rotation
--     sets the shape's yaw. Keep it level.

local Blocks = {}

Blocks.JITTER = 0.04
-- Roblox clamps every part axis to this size.
Blocks.MAX_SIZE = 2048

-- Deterministic 0..1 from a position.
local function hash(v: Vector3): number
	local h = math.sin(v.X * 12.9898 + v.Y * 78.233 + v.Z * 37.719) * 43758.5453
	return h - math.floor(h)
end

-- `color` brightened or darkened by up to `amount` (default Blocks.JITTER),
-- picked by `key` so the same spot always gets the same shade.
function Blocks.jitter(color: Color3, key: Vector3, amount: number?): Color3
	local scale = 1 + (hash(key) * 2 - 1) * (amount or Blocks.JITTER)
	return Color3.new(
		math.clamp(color.R * scale, 0, 1),
		math.clamp(color.G * scale, 0, 1),
		math.clamp(color.B * scale, 0, 1)
	)
end

-- Any ground part. props may set ClassName ("Part", "WedgePart",
-- "CornerWedgePart"), Shape, Name, CanCollide, Transparency, etc.
function Blocks.part(
	parent: Instance,
	color: Color3,
	cframe: CFrame,
	size: Vector3,
	props: { [string]: any }?
): BasePart
	local options: { [string]: any } = props or {}
	local part = Instance.new(options.ClassName or "Part") :: BasePart
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	part.CanTouch = false
	part.Name = "Ground"
	if options.Shape and part:IsA("Part") then
		part.Shape = options.Shape
	end
	part.Size = Vector3.new(
		math.min(size.X, Blocks.MAX_SIZE),
		math.min(size.Y, Blocks.MAX_SIZE),
		math.min(size.Z, Blocks.MAX_SIZE)
	)
	part.CFrame = cframe
	part.Color = Blocks.jitter(color, cframe.Position)
	for key, value in options do
		if key ~= "ClassName" and key ~= "Shape" and key ~= "Parent" then
			(part :: any)[key] = value
		end
	end
	part.Parent = parent
	return part
end

function Blocks.box(
	parent: Instance,
	color: Color3,
	cframe: CFrame,
	size: Vector3,
	props: { [string]: any }?
): BasePart
	return Blocks.part(parent, color, cframe, size, props)
end

-- A WedgePart: tall end at its local +Z, slope falling toward -Z.
function Blocks.wedge(
	parent: Instance,
	color: Color3,
	cframe: CFrame,
	size: Vector3,
	props: { [string]: any }?
): BasePart
	local options = table.clone(props or {})
	options.ClassName = "WedgePart"
	return Blocks.part(parent, color, cframe, size, options)
end

-- A walkable ramp whose slope runs from `low` up to `high` (both points on
-- the slope's centre line), `width` studs wide. Solid underneath down to
-- low.Y. Keep the slope at 28 degrees or less.
function Blocks.ramp(
	parent: Instance,
	color: Color3,
	low: Vector3,
	high: Vector3,
	width: number,
	props: { [string]: any }?
): BasePart
	if high.Y < low.Y then
		low, high = high, low
	end
	local flat = Vector3.new(high.X - low.X, 0, high.Z - low.Z)
	local run = math.max(flat.Magnitude, 0.05)
	local rise = math.max(high.Y - low.Y, 0.05)
	local direction = if flat.Magnitude > 0.001 then flat.Unit else Vector3.new(0, 0, 1)
	local center = Vector3.new((low.X + high.X) / 2, (low.Y + high.Y) / 2, (low.Z + high.Z) / 2)
	-- local +Z (the tall end) must point from low to high
	local cframe = CFrame.lookAt(center, center - direction)
	return Blocks.wedge(parent, color, cframe, Vector3.new(width, rise, run), props)
end

-- Radial thickness of a polygon's rim blocks: thick enough that the round
-- core can reach every inner corner without poking out of the polygon.
local function rimThickness(radius: number, sides: number): number
	return math.min(radius, math.max(2, radius * (1 - math.cos(math.pi / sides)) + 1.5))
end

-- Rim blocks of a regular `sides`-gon whose flat faces sit `radius` studs
-- (the apothem) from the centre, each `thickness` studs deep.
local function rim(
	parent: Instance,
	color: Color3,
	top: CFrame,
	radius: number,
	thickness: number,
	height: number,
	sides: number,
	props: { [string]: any }?
): { BasePart }
	local parts = {}
	local length = 2 * radius * math.tan(math.pi / sides) + 0.05
	-- one shade for the whole shape: the blocks overlap on the same plane,
	-- and different shades there would flicker
	local options = table.clone(props or {})
	if options.Color == nil then
		options.Color = Blocks.jitter(color, top.Position)
	end
	for i = 0, sides - 1 do
		local angle = i * 2 * math.pi / sides
		local cframe = top
			* CFrame.Angles(0, angle, 0)
			* CFrame.new(0, -height / 2, -(radius - thickness / 2))
		table.insert(
			parts,
			Blocks.part(parent, color, cframe, Vector3.new(length, height, thickness), options)
		)
	end
	return parts
end

-- A solid regular polygon (an island cap, a plateau layer, a pad):
-- `sides` rim blocks plus one hidden round core, `sides + 1` parts.
-- `radius` is the apothem (centre to the middle of a flat side).
function Blocks.disc(
	parent: Instance,
	color: Color3,
	top: CFrame,
	radius: number,
	height: number,
	sides: number,
	props: { [string]: any }?
): { BasePart }
	sides = math.max(sides, 5)
	local thickness = rimThickness(radius, sides)
	local parts = rim(parent, color, top, radius, thickness, height, sides, props)
	if thickness < radius then
		local coreRadius = math.min((radius - thickness) / math.cos(math.pi / sides) + 0.25, radius)
		local options = table.clone(props or {})
		options.Shape = Enum.PartType.Cylinder
		if options.Color == nil then
			options.Color = Blocks.jitter(color, top.Position)
		end
		table.insert(
			parts,
			Blocks.part(
				parent,
				color,
				top * CFrame.new(0, -height / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
				Vector3.new(height, coreRadius * 2, coreRadius * 2),
				options
			)
		)
	end
	return parts
end

-- A polygon ring (a beach band, a grass lip): `sides` blocks covering the
-- band from apothem `radius - width` out to `radius`.
function Blocks.ring(
	parent: Instance,
	color: Color3,
	top: CFrame,
	radius: number,
	width: number,
	height: number,
	sides: number,
	props: { [string]: any }?
): { BasePart }
	sides = math.max(sides, 5)
	return rim(parent, color, top, radius, math.min(width, radius), height, sides, props)
end

-- Stacked layers under `top`, alternating colors[1], colors[2], ... from
-- the top down. Each layer below is `inset` studs wider than the one above,
-- so the sides step out like rock strata. heights[1] is the top layer.
-- The top layer's flat top is exactly at top.Position.Y.
function Blocks.strata(
	parent: Instance,
	colors: { Color3 },
	top: CFrame,
	radius: number,
	heights: { number },
	inset: number,
	sides: number,
	props: { [string]: any }?
): { BasePart }
	local parts = {}
	local depth = 0
	for i, height in heights do
		local layerTop = top * CFrame.new(0, -depth, 0)
		local color = colors[(i - 1) % #colors + 1]
		for _, part in
			Blocks.disc(parent, color, layerTop, radius + (i - 1) * inset, height, sides, props)
		do
			table.insert(parts, part)
		end
		depth += height
	end
	return parts
end

-- Rectangular strata (a mesa under a rectangular catch floor): `size` is
-- the top layer's X/Z footprint; each layer below grows by `inset` on
-- every side. One block per layer.
function Blocks.strataBox(
	parent: Instance,
	colors: { Color3 },
	top: CFrame,
	size: Vector2,
	heights: { number },
	inset: number,
	props: { [string]: any }?
): { BasePart }
	local parts = {}
	local depth = 0
	for i, height in heights do
		local grow = (i - 1) * inset * 2
		local color = colors[(i - 1) % #colors + 1]
		table.insert(
			parts,
			Blocks.box(
				parent,
				color,
				top * CFrame.new(0, -depth - height / 2, 0),
				Vector3.new(size.X + grow, height, size.Y + grow),
				props
			)
		)
		depth += height
	end
	return parts
end

-- A chunky rock: 2 or 3 tilted blocks sitting on `bottom`, about `size`
-- studs across. Shape and tilt come from the position, so a rock at the
-- same spot always looks the same.
function Blocks.rock(
	parent: Instance,
	color: Color3,
	bottom: Vector3,
	size: number,
	props: { [string]: any }?
): { BasePart }
	local parts = {}
	local count = if hash(bottom * 1.7) < 0.5 then 2 else 3
	for i = 1, count do
		local key = bottom + Vector3.new(i * 3.1, i * 1.3, i * 2.7)
		local r1, r2, r3 = hash(key), hash(key * 1.31), hash(key * 2.17)
		local s = size * (0.55 + 0.45 * r1) * (if i == 1 then 1 else 0.75)
		local blockSize =
			Vector3.new(s * (0.9 + 0.4 * r2), s * (0.6 + 0.3 * r3), s * (0.9 + 0.4 * r3))
		local offset =
			Vector3.new((r2 - 0.5) * size * 0.6, blockSize.Y * 0.3, (r3 - 0.5) * size * 0.6)
		local cframe = CFrame.new(bottom + offset)
			* CFrame.Angles((r1 - 0.5) * 0.5, r2 * math.pi * 2, (r3 - 0.5) * 0.5)
		local options = table.clone(props or {})
		options.Name = options.Name or "Rock"
		table.insert(parts, Blocks.box(parent, color, cframe, blockSize, options))
	end
	return parts
end

-- See-through sea surface, `top` studs high: not collidable, not hit by
-- raycasts, no shadow. Put it outside the Ground folder and lay a solid
-- seabed a few studs below so anyone who falls in can wade back out.
function Blocks.water(
	parent: Instance,
	color: Color3,
	center: Vector3,
	size: Vector2,
	top: number,
	props: { [string]: any }?
): BasePart
	local options = table.clone(props or {})
	options.Name = options.Name or "Sea"
	options.CanCollide = false
	options.CanQuery = false
	options.CastShadow = false
	if options.Transparency == nil then
		options.Transparency = 0.3
	end
	local part = Blocks.box(
		parent,
		color,
		CFrame.new(center.X, top - 1, center.Z),
		Vector3.new(size.X, 2, size.Y),
		options
	)
	part.Color = color
	return part
end

return Blocks
