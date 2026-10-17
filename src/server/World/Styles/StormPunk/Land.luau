--!strict
-- Terrain landmasses for StormPunk: organic outlines (never plain circles or
-- rectangles), layered cliffs with strata, beaches, sea stacks and arches.
-- An outline is computed once and can be filled many times at different
-- heights and materials, so strata bands follow the exact same coastline.

local ServerScriptService = game:GetService("ServerScriptService")

local WorldTypes = require(ServerScriptService.Server.World.Types)

type Context = WorldTypes.Context

export type Circle = { x: number, z: number, r: number }
export type Outline = {
	box: { frame: CFrame, width: number, depth: number }?,
	circles: { Circle },
}

local Land = {}

-- Rounded, wobbly rectangle around `frame` (only its position and yaw are
-- used). Edge circles of radius ~`edge` follow a slow wave plus a little
-- noise (bays and points rather than even bumps), pushed in and out by up to
-- `jitter`. `spurs` adds that many bigger lobes reaching further out.
function Land.rectOutline(
	frame: CFrame,
	width: number,
	depth: number,
	rng: Random,
	edge: number,
	jitter: number,
	spurs: number?
): Outline
	local circles: { Circle } = {}
	local hw, hd = width / 2, depth / 2
	local perimeter = 2 * (width + depth)
	local steps = math.max(8, math.floor(perimeter / (edge * 1.1)))
	local offset = rng:NextNumber(0, perimeter)
	local phase1, phase2 = rng:NextNumber(0, math.pi * 2), rng:NextNumber(0, math.pi * 2)
	local f1 = math.pi * 2 * rng:NextInteger(2, 3) / perimeter
	local f2 = math.pi * 2 * rng:NextInteger(5, 7) / perimeter
	local function edgeAt(t: number): (number, number, number, number)
		t %= perimeter
		if t < width then
			return -hw + t, -hd, 0, -1
		elseif t < width + depth then
			return hw, -hd + (t - width), 1, 0
		elseif t < 2 * width + depth then
			return hw - (t - width - depth), hd, 0, 1
		end
		return -hw, hd - (t - 2 * width - depth), -1, 0
	end
	for i = 0, steps - 1 do
		local t = offset + i / steps * perimeter
		local x, z, nx, nz = edgeAt(t)
		local wave = 0.6 * math.sin(t * f1 + phase1) + 0.4 * math.sin(t * f2 + phase2)
		local push = (wave * 0.75 + rng:NextNumber(-0.25, 0.25) + 0.25) * jitter
		local p = frame:PointToWorldSpace(Vector3.new(x + nx * push, 0, z + nz * push))
		local r = edge * (0.8 + 0.4 * (wave * 0.5 + 0.5)) * rng:NextNumber(0.9, 1.1)
		table.insert(circles, { x = p.X, z = p.Z, r = r })
	end
	for _ = 1, spurs or 0 do
		local x, z, nx, nz = edgeAt(rng:NextNumber(0, perimeter))
		local push = jitter + edge * rng:NextNumber(0.3, 0.8)
		local p = frame:PointToWorldSpace(Vector3.new(x + nx * push, 0, z + nz * push))
		table.insert(circles, { x = p.X, z = p.Z, r = edge * rng:NextNumber(1.1, 1.6) })
	end
	return {
		-- the core box sits inside the edge circles so corners come out round
		box = {
			frame = CFrame.new(frame.Position) * frame.Rotation,
			width = math.max(width - 1.2 * edge, width * 0.5),
			depth = math.max(depth - 1.2 * edge, depth * 0.5),
		},
		circles = circles,
	}
end

-- Wobbly round outline: a core disc plus lobes around its rim.
function Land.roundOutline(
	center: Vector3,
	radius: number,
	rng: Random,
	lobes: number,
	wobble: number
): Outline
	local circles: { Circle } = { { x = center.X, z = center.Z, r = radius * 0.78 } }
	local start = rng:NextNumber(0, math.pi * 2)
	for i = 1, lobes do
		local a = start + (i / lobes) * math.pi * 2 + rng:NextNumber(-0.25, 0.25)
		local r = radius * rng:NextNumber(0.32, 0.5)
		local reach = radius - r * rng:NextNumber(0.8, 1.05) + rng:NextNumber(-1, 1) * wobble
		table.insert(circles, {
			x = center.X + math.sin(a) * reach,
			z = center.Z - math.cos(a) * reach,
			r = r,
		})
	end
	return { box = nil, circles = circles }
end

-- Copy of an outline keeping only the circles `keep` accepts (the box stays).
function Land.clip(outline: Outline, keep: (Circle) -> boolean): Outline
	local circles: { Circle } = {}
	for _, c in outline.circles do
		if keep(c) then
			table.insert(circles, c)
		end
	end
	return { box = outline.box, circles = circles }
end

-- Fills the outline between two heights. `grow` widens it (strata lips).
function Land.fill(
	ctx: Context,
	outline: Outline,
	bottomY: number,
	topY: number,
	material: Enum.Material,
	grow: number?
)
	local g = grow or 0
	local h = topY - bottomY
	if h <= 0 then
		return
	end
	local midY = (topY + bottomY) / 2
	local box = outline.box
	if box then
		local p = box.frame.Position
		ctx.terrain:FillBlock(
			CFrame.new(p.X, midY, p.Z) * box.frame.Rotation,
			Vector3.new(box.width + 2 * g, h, box.depth + 2 * g),
			material
		)
	end
	for _, c in outline.circles do
		ctx.terrain:FillCylinder(CFrame.new(c.x, midY, c.z), h, c.r + g, material)
	end
end

-- Is a point (horizontally) inside the outline, shrunk by `shrink`?
function Land.contains(outline: Outline, position: Vector3, shrink: number?): boolean
	local m = shrink or 0
	local box = outline.box
	if box then
		local l =
			box.frame:PointToObjectSpace(Vector3.new(position.X, box.frame.Position.Y, position.Z))
		if math.abs(l.X) <= box.width / 2 - m and math.abs(l.Z) <= box.depth / 2 - m then
			return true
		end
	end
	for _, c in outline.circles do
		local dx, dz = position.X - c.x, position.Z - c.z
		if dx * dx + dz * dz <= (c.r - m) * (c.r - m) and c.r > m then
			return true
		end
	end
	return false
end

export type Layer = { outline: Outline, top: number }

-- Height of the highest layer containing the point (layers listed highest
-- first), or nil if none does. `shrink` keeps props off crumbly edges.
function Land.surfaceAt(layers: { Layer }, position: Vector3, shrink: number?): number?
	for _, layer in layers do
		if Land.contains(layer.outline, position, shrink) then
			return layer.top
		end
	end
	return nil
end

-- Exactly flat rectangle (any yaw) with its top at topY: catch floors.
function Land.flatRect(
	ctx: Context,
	frame: CFrame,
	width: number,
	depth: number,
	topY: number,
	thickness: number,
	material: Enum.Material
)
	local p = frame.Position
	ctx.terrain:FillBlock(
		CFrame.new(p.X, topY - thickness / 2, p.Z) * frame.Rotation,
		Vector3.new(width, thickness, depth),
		material
	)
end

-- Layered cliff: fills `outline` from bottomY to topY with `body`, then
-- 4-stud strata bands from `bands` (cycled, slightly proud of the face) and
-- finally a cap layer of `cap` on top. Returns nothing; pure terrain.
function Land.cliff(
	ctx: Context,
	outline: Outline,
	bottomY: number,
	topY: number,
	body: Enum.Material,
	bands: { Enum.Material },
	cap: Enum.Material
)
	Land.fill(ctx, outline, bottomY, topY - 4, body)
	if #bands > 0 then
		local y = math.floor((topY - 4) / 4) * 4 - 4
		local i = 0
		while y > bottomY + 2 do
			i += 1
			if i % 2 == 1 then
				local material = bands[((i - 1) // 2) % #bands + 1]
				Land.fill(ctx, outline, y - 4, y, material, 0.3 + (i % 3) * 0.45)
			end
			y -= 4
		end
	end
	Land.fill(ctx, outline, topY - 4, topY, cap)
end

-- Sea stack / hoodoo: a stack of shrinking, wobbling discs with strata.
function Land.pinnacle(
	ctx: Context,
	base: Vector3,
	height: number,
	radius: number,
	rng: Random,
	materials: { Enum.Material },
	capRadius: number?,
	cap: Enum.Material?
)
	local layers = math.max(3, math.floor(height / 6))
	local layerH = height / layers
	local x, z = base.X, base.Z
	for i = 1, layers do
		local t = (i - 1) / (layers - 1)
		local r = radius + ((capRadius or radius * 0.45) - radius) * t
		r *= rng:NextNumber(0.88, 1.12)
		x += rng:NextNumber(-1, 1) * radius * 0.08
		z += rng:NextNumber(-1, 1) * radius * 0.08
		local y0 = base.Y + (i - 1) * layerH
		ctx.terrain:FillCylinder(
			CFrame.new(x, y0 + layerH / 2 + 0.5, z),
			layerH + 1,
			math.max(r, 1.5),
			if i == layers and cap then cap else materials[(i - 1) % #materials + 1]
		)
	end
end

-- Natural rock arch from a to b (both on the ground), peak at `height`.
function Land.arch(
	ctx: Context,
	a: Vector3,
	b: Vector3,
	height: number,
	thickness: number,
	rng: Random,
	materials: { Enum.Material }
)
	Land.pinnacle(ctx, a, height, thickness * 0.9, rng, materials, thickness * 0.6)
	Land.pinnacle(ctx, b, height, thickness * 0.9, rng, materials, thickness * 0.6)
	local segments = 5
	for i = 0, segments - 1 do
		local t0, t1 = i / segments, (i + 1) / segments
		local function at(t: number): Vector3
			local p = a:Lerp(b, t)
			local lift = math.sin(t * math.pi) * 0.18 * height
			return p + Vector3.new(0, height - thickness * 0.4 + lift, 0)
		end
		local p0, p1 = at(t0), at(t1)
		ctx.terrain:FillBlock(
			CFrame.lookAt((p0 + p1) / 2, p1),
			Vector3.new(thickness, thickness * 0.8, (p1 - p0).Magnitude + thickness * 0.6),
			materials[(i % #materials) + 1]
		)
	end
end

return Land
