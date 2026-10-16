--!strict
-- Style-agnostic building pieces. Style packs compose these with their own
-- palette; nothing in here has a look of its own.
--
-- Conventions:
--   * Every function takes a `parent` (or a props.Parent) and returns what it built.
--   * Positions are world space. "bottom" means the point the object stands on.
--   * Parts are Anchored with smooth surfaces. Use Kit.decor for anything
--     purely visual: it can't be touched and (when non-collidable) can't be
--     hit by raycasts, so it never interferes with strikes or selling.
--   * Terrain helpers fill the world's Terrain; later fills overwrite earlier ones.

local WorldTypes = require(script.Parent.Types)

type Context = WorldTypes.Context
type ZoneContext = WorldTypes.ZoneContext

local Kit = {}

Kit.SELL_TAG = "SellArea"

-- Built-in particle textures (no uploads needed).
Kit.TEXTURES = table.freeze({
	sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
	fire = "rbxasset://textures/particles/fire_main.dds",
})

-- Parts ---------------------------------------------------------------------

-- Generic anchored part. props may include ClassName ("Part", "WedgePart",
-- "CornerWedgePart", "TrussPart") and any BasePart property; Parent is set last.
function Kit.part(props: { [string]: any }): BasePart
	local className = props.ClassName or "Part"
	local part = Instance.new(className) :: BasePart
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	-- Shape first so a later Size isn't squashed by the shape change
	if props.Shape and part:IsA("Part") then
		part.Shape = props.Shape
	end
	for key, value in props do
		if key ~= "ClassName" and key ~= "Parent" and key ~= "Shape" then
			(part :: any)[key] = value
		end
	end
	part.Parent = props.Parent
	return part
end

-- Visual-only part: never fires touches; when CanCollide is false it is
-- also invisible to raycasts.
function Kit.decor(props: { [string]: any }): BasePart
	local part = Kit.part(props)
	part.CanTouch = false
	if not part.CanCollide then
		part.CanQuery = false
	end
	return part
end

-- CFrame standing a cylinder upright (cylinders run along X) at a point,
-- optionally turned by yaw degrees.
function Kit.upright(position: Vector3, yaw: number?): CFrame
	return CFrame.new(position)
		* CFrame.Angles(0, math.rad(yaw or 0), 0)
		* CFrame.Angles(0, 0, math.rad(90))
end

-- Upright cylinder standing on `bottom`.
function Kit.cylinder(
	parent: Instance,
	bottom: Vector3,
	height: number,
	diameter: number,
	props: { [string]: any }?
): BasePart
	local options = table.clone(props or {})
	options.Shape = Enum.PartType.Cylinder
	options.Size = Vector3.new(height, diameter, diameter)
	options.CFrame = Kit.upright(bottom + Vector3.new(0, height / 2, 0))
	options.Parent = parent
	return Kit.decor(options)
end

function Kit.ball(
	parent: Instance,
	center: Vector3,
	diameter: number,
	props: { [string]: any }?
): BasePart
	local options = table.clone(props or {})
	options.Shape = Enum.PartType.Ball
	options.Size = Vector3.new(diameter, diameter, diameter)
	options.CFrame = CFrame.new(center)
	options.Parent = parent
	return Kit.decor(options)
end

-- A beam/post/plank running from a to b with a square cross-section.
function Kit.strut(
	parent: Instance,
	a: Vector3,
	b: Vector3,
	thickness: number,
	props: { [string]: any }?
): BasePart
	local options = table.clone(props or {})
	options.Size = Vector3.new(thickness, thickness, (b - a).Magnitude)
	options.CFrame = CFrame.lookAt((a + b) / 2, b)
	options.Parent = parent
	return Kit.decor(options)
end

-- Round pipe from a to b (a cylinder lying along the segment).
function Kit.pipe(
	parent: Instance,
	a: Vector3,
	b: Vector3,
	diameter: number,
	props: { [string]: any }?
): BasePart
	local options = table.clone(props or {})
	options.Shape = Enum.PartType.Cylinder
	options.Size = Vector3.new((b - a).Magnitude, diameter, diameter)
	-- lookAt aims -Z along the segment; turn so the cylinder's X axis does
	options.CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0)
	options.Parent = parent
	return Kit.decor(options)
end

-- Walkable slab whose TOP surface runs from `from` to `to` (both points on
-- the walking surface). Collidable. Works for flat paths and ramps.
function Kit.walkway(
	parent: Instance,
	from: Vector3,
	to: Vector3,
	width: number,
	thickness: number,
	props: { [string]: any }?
): BasePart
	local options = table.clone(props or {})
	options.Size = Vector3.new(width, thickness, (to - from).Magnitude)
	options.CFrame = CFrame.lookAt((from + to) / 2, to) * CFrame.new(0, -thickness / 2, 0)
	options.Parent = parent
	local part = Kit.part(options)
	part.CanTouch = false
	return part
end

-- Lights ---------------------------------------------------------------------

function Kit.light(
	parent: Instance,
	color: Color3,
	range: number,
	brightness: number,
	shadows: boolean?
): PointLight
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = shadows == true
	light.Parent = parent
	return light
end

function Kit.spotLight(
	parent: Instance,
	color: Color3,
	range: number,
	brightness: number,
	angle: number,
	face: Enum.NormalId
): SpotLight
	local light = Instance.new("SpotLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Angle = angle
	light.Face = face
	light.Parent = parent
	return light
end

-- Cables (Beams) -------------------------------------------------------------

-- A cable between two world points. Beams cost no parts.
-- props: Color (Color3), Width, CurveSize (sag in studs), LightEmission
-- (0..1, glowing when > 0), Brightness, Transparency (number), Segments.
function Kit.cable(ctx: Context, a: Vector3, b: Vector3, props: { [string]: any }?): Beam
	local options: { [string]: any } = props or {}
	local anchor = ctx.cableAnchor
	local a0 = Instance.new("Attachment")
	a0.Name = "CableEnd"
	a0.Position = anchor.CFrame:PointToObjectSpace(a)
	a0.Parent = anchor
	local a1 = Instance.new("Attachment")
	a1.Name = "CableEnd"
	a1.Position = anchor.CFrame:PointToObjectSpace(b)
	a1.Parent = anchor

	local beam = Instance.new("Beam")
	beam.Name = "Cable"
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Color = ColorSequence.new(options.Color or Color3.fromRGB(25, 25, 30))
	local width = options.Width or 0.3
	beam.Width0 = width
	beam.Width1 = width
	beam.FaceCamera = true
	beam.Segments = options.Segments or 12
	local emission = options.LightEmission or 0
	beam.LightEmission = emission
	beam.LightInfluence = if emission > 0 then 0 else 1
	beam.Brightness = options.Brightness or 1
	beam.Transparency = NumberSequence.new(options.Transparency or 0)
	-- sag: aim both ends' curve handles downward
	local sag = options.CurveSize or 0
	a0.Axis = Vector3.new(0, -1, 0)
	a0.SecondaryAxis = Vector3.new(1, 0, 0)
	a1.Axis = Vector3.new(0, -1, 0)
	a1.SecondaryAxis = Vector3.new(1, 0, 0)
	beam.CurveSize0 = sag
	beam.CurveSize1 = -sag
	beam.Parent = anchor
	return beam
end

-- Text -----------------------------------------------------------------------

export type SignStyle = {
	boardColor: Color3,
	boardMaterial: Enum.Material?,
	titleColor: Color3,
	subtitleColor: Color3?,
	strokeColor: Color3?,
	titleFont: Enum.Font?,
	subtitleFont: Enum.Font?,
	thickness: number?,
	twoSided: boolean?,
	glow: boolean?, -- default true: text ignores lighting so it reads at night
}

local function addText(gui: SurfaceGui, title: string, subtitle: string?, style: SignStyle)
	local stroke = style.strokeColor or Color3.fromRGB(15, 15, 25)
	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.Position = UDim2.fromScale(0.05, 0.06)
	titleLabel.Size = UDim2.fromScale(0.9, if subtitle then 0.56 else 0.88)
	titleLabel.Font = style.titleFont or Enum.Font.LuckiestGuy
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = style.titleColor
	titleLabel.Text = title
	titleLabel.Parent = gui
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Thickness = 5
	titleStroke.Color = stroke
	titleStroke.Parent = titleLabel
	if subtitle then
		local subtitleLabel = Instance.new("TextLabel")
		subtitleLabel.BackgroundTransparency = 1
		subtitleLabel.Position = UDim2.fromScale(0.06, 0.64)
		subtitleLabel.Size = UDim2.fromScale(0.88, 0.3)
		subtitleLabel.Font = style.subtitleFont or Enum.Font.BuilderSansExtraBold
		subtitleLabel.TextScaled = true
		subtitleLabel.TextColor3 = style.subtitleColor or Color3.new(1, 1, 1)
		subtitleLabel.Text = subtitle
		subtitleLabel.Parent = gui
		local subStroke = Instance.new("UIStroke")
		subStroke.Thickness = 3
		subStroke.Color = stroke
		subStroke.Parent = subtitleLabel
	end
end

-- Puts text on one face of an existing part.
function Kit.faceText(
	part: BasePart,
	face: Enum.NormalId,
	title: string,
	subtitle: string?,
	style: SignStyle
): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = if style.glow == false then 1 else 0
	gui.MaxDistance = 600
	gui.Parent = part
	addText(gui, title, subtitle, style)
	return gui
end

-- A sign board centred at `cframe`; the text is on the face that points
-- along cframe.LookVector.
function Kit.sign(
	parent: Instance,
	cframe: CFrame,
	width: number,
	height: number,
	title: string,
	subtitle: string?,
	style: SignStyle
): BasePart
	local board = Kit.decor({
		Name = "Sign",
		Size = Vector3.new(width, height, style.thickness or 0.6),
		CFrame = cframe,
		Color = style.boardColor,
		Material = style.boardMaterial or Enum.Material.SmoothPlastic,
		Parent = parent,
	})
	Kit.faceText(board, Enum.NormalId.Front, title, subtitle, style)
	if style.twoSided then
		Kit.faceText(board, Enum.NormalId.Back, title, subtitle, style)
	end
	return board
end

-- Rocks and scatter ------------------------------------------------------------

-- Low-poly rock: 2-4 overlapping blocks/wedges at random angles. Collidable.
function Kit.rock(
	parent: Instance,
	bottom: Vector3,
	size: number,
	rng: Random,
	props: { [string]: any }?
): { BasePart }
	local pieces: { BasePart } = {}
	local count = rng:NextInteger(2, 4)
	for i = 1, count do
		local s = size * rng:NextNumber(0.55, 1)
		local options = table.clone(props or {})
		options.ClassName = if i > 1 and rng:NextNumber() < 0.5 then "WedgePart" else "Part"
		options.Size = Vector3.new(
			s * rng:NextNumber(0.8, 1.3),
			s * rng:NextNumber(0.6, 1),
			s * rng:NextNumber(0.8, 1.3)
		)
		local offset = Vector3.new(
			rng:NextNumber(-0.35, 0.35) * size,
			s * 0.3,
			rng:NextNumber(-0.35, 0.35) * size
		)
		options.CFrame = CFrame.new(bottom + offset)
			* CFrame.Angles(
				rng:NextNumber(-0.35, 0.35),
				rng:NextNumber(0, math.pi * 2),
				rng:NextNumber(-0.35, 0.35)
			)
		options.Name = options.Name or "Rock"
		options.Parent = parent
		local piece = Kit.part(options)
		piece.CanTouch = false
		table.insert(pieces, piece)
	end
	return pieces
end

-- Up to `count` points from `sample` that pass `accept`; gives up after
-- 20 tries per point so it can't loop forever.
function Kit.scatter(
	count: number,
	sample: () -> Vector3,
	accept: ((Vector3) -> boolean)?
): { Vector3 }
	local points: { Vector3 } = {}
	local tries = 0
	while #points < count and tries < count * 20 do
		tries += 1
		local p = sample()
		if not accept or accept(p) then
			table.insert(points, p)
		end
	end
	return points
end

-- Zone geometry ---------------------------------------------------------------

-- World point at normalised footprint coordinates. u runs across the zone
-- (-0.5 .. 0.5), v runs from the gate edge (-0.5, hub side) to the back
-- edge (0.5). y is added on top of the floor height.
function Kit.footprintPoint(zone: ZoneContext, u: number, v: number, y: number?): Vector3
	local slot = zone.slot
	return slot.frame:PointToWorldSpace(Vector3.new(u * slot.width, y or 0, v * slot.depth))
end

-- Is a world position (horizontally) inside the zone's catch rectangle,
-- grown by `margin`? Use it to keep decoration off the catch floor.
function Kit.inCatch(zone: ZoneContext, position: Vector3, margin: number?): boolean
	local localPos = zone.slot.frame:PointToObjectSpace(position)
	local m = margin or 0
	return math.abs(localPos.X) <= zone.catchWidth / 2 + m
		and math.abs(localPos.Z) <= zone.catchDepth / 2 + m
end

-- Is a world position (horizontally) inside the zone's footprint (+margin)?
function Kit.inFootprint(zone: ZoneContext, position: Vector3, margin: number?): boolean
	local localPos = zone.slot.frame:PointToObjectSpace(position)
	local m = margin or 0
	return math.abs(localPos.X) <= zone.slot.width / 2 + m
		and math.abs(localPos.Z) <= zone.slot.depth / 2 + m
end

-- CFrames along the footprint edge every ~`spacing` studs (corners
-- included) on the floor, LookVector pointing outward. `inset` moves them
-- toward the middle.
function Kit.perimeter(zone: ZoneContext, spacing: number, inset: number?): { CFrame }
	local slot = zone.slot
	local hw, hd = slot.width / 2 - (inset or 0), slot.depth / 2 - (inset or 0)
	local result: { CFrame } = {}
	local sides = {
		{ Vector3.new(-hw, 0, -hd), Vector3.new(hw, 0, -hd), Vector3.new(0, 0, -1) },
		{ Vector3.new(hw, 0, -hd), Vector3.new(hw, 0, hd), Vector3.new(1, 0, 0) },
		{ Vector3.new(hw, 0, hd), Vector3.new(-hw, 0, hd), Vector3.new(0, 0, 1) },
		{ Vector3.new(-hw, 0, hd), Vector3.new(-hw, 0, -hd), Vector3.new(-1, 0, 0) },
	}
	for _, side in sides do
		local a, b, outward = side[1], side[2], side[3]
		local steps = math.max(1, math.round((b - a).Magnitude / spacing))
		local worldOut = slot.frame:VectorToWorldSpace(outward)
		for i = 0, steps - 1 do
			local world = slot.frame:PointToWorldSpace(a:Lerp(b, i / steps))
			table.insert(result, CFrame.lookAt(world, world + worldOut))
		end
	end
	return result
end

-- Selling, spawn ----------------------------------------------------------------

-- Invisible box over a pad that the server's Selling system watches. The
-- pad itself is pure art; this box is what counts.
function Kit.sellArea(parent: Instance, pad: BasePart, height: number?): BasePart
	local h = height or 12
	local area = Kit.part({
		Name = "SellArea",
		Size = Vector3.new(pad.Size.X + 4, h, pad.Size.Z + 4),
		CFrame = pad.CFrame * CFrame.new(0, pad.Size.Y / 2 + h / 2 - 1, 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Parent = parent,
	})
	area:AddTag(Kit.SELL_TAG)
	return area
end

function Kit.spawn(
	parent: Instance,
	cframe: CFrame,
	size: Vector3,
	props: { [string]: any }?
): SpawnLocation
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "Spawn"
	spawnLocation.Anchored = true
	spawnLocation.Neutral = true
	spawnLocation.Duration = 0
	spawnLocation.Size = size
	spawnLocation.CFrame = cframe
	spawnLocation.TopSurface = Enum.SurfaceType.Smooth
	local options: { [string]: any } = props or {}
	for key, value in options do
		(spawnLocation :: any)[key] = value
	end
	spawnLocation.Parent = parent
	return spawnLocation
end

-- Particles ----------------------------------------------------------------------

function Kit.emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	for key, value in props do
		(emitter :: any)[key] = value
	end
	emitter.Parent = parent
	return emitter
end

-- Terrain -------------------------------------------------------------------------

function Kit.fillBox(ctx: Context, cframe: CFrame, size: Vector3, material: Enum.Material)
	ctx.terrain:FillBlock(cframe, size, material)
end

-- Flat-topped landmass with an irregular outline: a core cylinder plus
-- `lobes` overlapping cylinders around it. Top surface at topY, `depth`
-- studs thick. Good for islands, plateaus and terraces.
function Kit.blob(
	ctx: Context,
	center: Vector3,
	radius: number,
	topY: number,
	depth: number,
	material: Enum.Material,
	lobes: number?
)
	local terrain = ctx.terrain
	local rng = ctx.rng
	terrain:FillCylinder(
		CFrame.new(center.X, topY - depth / 2, center.Z),
		depth,
		radius * 0.8,
		material
	)
	local count = lobes or 7
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local r = radius * rng:NextNumber(0.35, 0.55)
		local reach = radius - r * rng:NextNumber(0.7, 1)
		local x = center.X + math.cos(angle) * reach
		local z = center.Z + math.sin(angle) * reach
		terrain:FillCylinder(CFrame.new(x, topY - depth / 2, z), depth, r, material)
	end
end

-- Rectangular landmass (any rotation) with softened, irregular edges: a
-- box plus jittered cylinders along its outline.
function Kit.slab(
	ctx: Context,
	frame: CFrame,
	width: number,
	depth: number,
	topY: number,
	thickness: number,
	material: Enum.Material,
	edgeRadius: number?
)
	local terrain = ctx.terrain
	local rng = ctx.rng
	local base = CFrame.new(frame.Position.X, topY - thickness / 2, frame.Position.Z)
		* frame.Rotation
	terrain:FillBlock(base, Vector3.new(width, thickness, depth), material)
	local r = edgeRadius or 8
	local hw, hd = width / 2, depth / 2
	local perimeter = 2 * (width + depth)
	local steps = math.max(4, math.floor(perimeter / (r * 1.4)))
	for i = 0, steps - 1 do
		local t = i / steps * perimeter
		local x, z
		if t < width then
			x, z = -hw + t, -hd
		elseif t < width + depth then
			x, z = hw, -hd + (t - width)
		elseif t < 2 * width + depth then
			x, z = hw - (t - width - depth), hd
		else
			x, z = -hw, hd - (t - 2 * width - depth)
		end
		local p = base:PointToWorldSpace(Vector3.new(x, 0, z))
		terrain:FillCylinder(
			CFrame.new(p),
			thickness * rng:NextNumber(0.7, 1),
			r * rng:NextNumber(0.6, 1.1),
			material
		)
	end
end

-- A floating island: flat top at topY with an irregular outline, tapering
-- down to a rocky point `depth` studs below.
function Kit.floatingIsland(
	ctx: Context,
	center: Vector3,
	radius: number,
	topY: number,
	depth: number,
	topMaterial: Enum.Material,
	rockMaterial: Enum.Material
)
	local layers = 6
	local layerHeight = depth / layers
	for i = 1, layers do
		local below = (i - 0.5) * layerHeight -- centre of this layer, below the top
		local layerRadius = radius * math.max(0.12, (1 - (i - 1) / layers) ^ 1.3)
		local wobble = Vector3.new(ctx.rng:NextNumber(-1, 1), 0, ctx.rng:NextNumber(-1, 1))
			* radius
			* 0.08
		local layerCenter = Vector3.new(center.X, topY - below, center.Z) + wobble
		ctx.terrain:FillCylinder(
			CFrame.new(layerCenter),
			layerHeight + 2,
			layerRadius,
			rockMaterial
		)
	end
	Kit.blob(ctx, center, radius, topY, 6, topMaterial, 6)
end

return Kit
