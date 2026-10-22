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

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Portals = require(ReplicatedStorage.Shared.Util.Portals)
local ResearchSites = require(ReplicatedStorage.Shared.Util.ResearchSites)
local Blocks = require(script.Parent.Blocks)
local WorldTypes = require(script.Parent.Types)

type Context = WorldTypes.Context
type ZoneContext = WorldTypes.ZoneContext

local Kit = {}

Kit.SELL_TAG = "SellArea"
Kit.OFFICE_TAG = "ResearchOffice"
Kit.PORTAL_TAG = Portals.TAG
-- Ground a hub keeps clear for each portal (Kit.portal): a circle this wide.
Kit.PORTAL_SPACE = 14

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

-- Invisible box over a pad that Util/ResearchSites treats as a Research
-- Office. Same idea as sellArea: the pad is art, this box is what counts.
function Kit.researchOffice(parent: Instance, pad: BasePart, height: number?): BasePart
	local h = height or 12
	local area = Kit.part({
		Name = "ResearchOffice",
		Size = Vector3.new(pad.Size.X + 4, h, pad.Size.Z + 4),
		CFrame = pad.CFrame * CFrame.new(0, pad.Size.Y / 2 + h / 2 - 1, 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Parent = parent,
	})
	area:AddTag(Kit.OFFICE_TAG)
	return area
end

local GATE_WIDTH = 16 -- wider than any connector deck
local GATE_HEIGHT = 12 -- higher than a jump
local LOCK_SIGN_Y = 5.4 -- the lock sign's middle, above the deck: about eye height
local GATE_SIGN: SignStyle = {
	boardColor = Color3.fromRGB(28, 30, 40),
	titleColor = Color3.fromRGB(255, 255, 255),
	subtitleColor = Color3.fromRGB(255, 214, 60),
	thickness = 0.5,
}

-- A locked zone's gate: a shimmering barrier across the end of the
-- connector, 1 stud outside the zone at slot.gate, between two posts, with
-- a sign saying what the zone needs hung on the barrier at eye height,
-- facing the connector (below every style's gate art, which stands above
-- the deck: arches, name boards, ornaments). Model <ZoneId> with a
-- "Barrier" part.
-- Nothing in it collides or is hit by raycasts here; Controllers/ZoneGates
-- makes the barrier solid on the client of each player who can't enter.
function Kit.zoneGate(parent: Instance, zone: ZoneContext, requirement: string): Model
	local def = zone.def :: any
	local model = Instance.new("Model")
	model.Name = def.id
	model:SetAttribute("ZoneId", def.id)
	local gate = zone.slot.gate * CFrame.new(0, 0, -1) -- looks toward the hub
	local barrier = Kit.decor({
		Name = "Barrier",
		Size = Vector3.new(GATE_WIDTH, GATE_HEIGHT, 0.6),
		CFrame = gate * CFrame.new(0, GATE_HEIGHT / 2, 0),
		Color = zone.color,
		Material = Enum.Material.ForceField,
		Transparency = 0.2,
		CastShadow = false,
		Parent = model,
	})
	barrier:SetAttribute("ZoneId", def.id)
	for _, side in { -1, 1 } do
		Kit.decor({
			Name = "Post",
			Size = Vector3.new(0.8, GATE_HEIGHT + 1, 0.8),
			CFrame = gate * CFrame.new(side * (GATE_WIDTH / 2 + 0.4), (GATE_HEIGHT + 1) / 2, 0),
			Color = Color3.fromRGB(40, 44, 58),
			Material = Enum.Material.Metal,
			Parent = model,
		})
	end
	Kit.sign(
		model,
		gate * CFrame.new(0, LOCK_SIGN_Y, -(0.3 + (GATE_SIGN.thickness or 0.6) / 2 + 0.05)),
		GATE_WIDTH - 4,
		3,
		`🔒 {string.upper(def.displayName)}`,
		requirement,
		GATE_SIGN
	)
	model.Parent = parent
	return model
end

local CAMP_WOOD = Color3.fromRGB(122, 92, 62)
local CAMP_DARK = Color3.fromRGB(74, 62, 52)
local CAMP_CANVAS = Color3.fromRGB(226, 216, 192)
local CAMP_METAL = Color3.fromRGB(150, 156, 164)
local CAMP_PILE_FALLBACK = 14
-- above the 0.2 boardwalk decks sit at, so they never share a plane
local CAMP_DECK_LIFT = ResearchSites.CAMP_DECK_LIFT

-- How far below `from` the nearest ground or base part is.
local function dropBelow(ctx: Context, from: Vector3): number
	-- pcall: the offline test harness has no raycasting, so piles fall back
	-- to a fixed length there
	local ok, hit = pcall(function()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { ctx.folders.ground, ctx.folders.base, ctx.terrain }
		return workspace:Raycast(from, Vector3.new(0, -60, 0), params)
	end)
	if ok and hit then
		return math.max(from.Y - hit.Position.Y + 1, 2)
	end
	return CAMP_PILE_FALLBACK
end

-- Default Research Camp: a pile-built deck at zone.slot.camp (joined to the
-- gate landing), a canvas tent, an instrument mast with an anemometer and a
-- "<ZONE> FIELD CAMP" sign in the zone colour. Neutral colours, 30 parts.
function Kit.researchCamp(ctx: Context, zone: ZoneContext)
	local def = zone.def
	if not def then
		return
	end
	-- The deck sits CAMP_DECK_LIFT above the camp height so it rests on top
	-- of whatever ground reaches under it (a zone plateau's edge is at the
	-- same height): two surfaces on one plane flicker.
	local camp = zone.slot.camp * CFrame.new(0, CAMP_DECK_LIFT, 0)
	local W, D = 28, 14
	local parent = Instance.new("Folder")
	parent.Name = def.id .. "Camp"
	parent.Parent = ctx.folders.decor
	local function at(x: number, y: number, z: number): CFrame
		return camp * CFrame.new(x, y, z)
	end

	-- deck (top at camp height) and the piles under it
	Blocks.box(ctx.folders.ground, CAMP_WOOD, at(0, -0.5, 0), Vector3.new(W, 1, D))
	for _, x in { -W / 2 + 1, 0, W / 2 - 1 } do
		for _, z in { -D / 2 + 1, D / 2 - 1 } do
			local drop = dropBelow(ctx, at(x, -1, z).Position)
			Blocks.box(
				ctx.folders.ground,
				CAMP_DARK,
				at(x, -1 - drop / 2, z),
				Vector3.new(1, drop, 1)
			)
		end
	end

	-- canvas tent: two sloped canvas sheets over a ridge pole
	local tentX, tentZ, tentW, tentL, tentH = 7, -1, 7, 8, 4.5
	local tilt = math.atan2(tentH, tentW / 2)
	local sheet = math.sqrt((tentW / 2) ^ 2 + tentH ^ 2)
	for _, side in { -1, 1 } do
		Kit.decor({
			Name = "Canvas",
			Size = Vector3.new(sheet, 0.3, tentL),
			CFrame = at(tentX + side * tentW / 4, 0.5 + tentH / 2, tentZ)
				* CFrame.Angles(0, 0, -side * tilt),
			Color = CAMP_CANVAS,
			Material = Enum.Material.Fabric,
			Parent = parent,
		})
	end
	Kit.decor({
		Name = "Groundsheet",
		Size = Vector3.new(tentW, 0.2, tentL),
		CFrame = at(tentX, 0.1, tentZ),
		Color = CAMP_DARK,
		Material = Enum.Material.Fabric,
		Parent = parent,
	})
	Kit.strut(
		parent,
		at(tentX, 0.5 + tentH, tentZ - tentL / 2 - 0.5).Position,
		at(tentX, 0.5 + tentH, tentZ + tentL / 2 + 0.5).Position,
		0.4,
		{ Color = CAMP_WOOD, Material = Enum.Material.Wood, CanCollide = false }
	)
	for _, z in { -tentL / 2 - 0.5, tentL / 2 + 0.5 } do
		Kit.cylinder(parent, at(tentX, 0, tentZ + z).Position, 0.5 + tentH, 0.4, {
			Color = CAMP_WOOD,
			Material = Enum.Material.Wood,
			CanCollide = false,
		})
	end

	-- instrument mast with an anemometer (three cups on a crossed arm)
	local mastX, mastZ, mastH = -8, -3, 9
	Kit.cylinder(parent, at(mastX, 0, mastZ).Position, mastH, 0.5, {
		Color = CAMP_METAL,
		Material = Enum.Material.Metal,
	})
	local top = at(mastX, mastH, mastZ).Position
	Kit.cylinder(parent, top, 0.6, 0.3, { Color = CAMP_DARK, CanCollide = false })
	for i = 1, 3 do
		local a = math.rad(i * 120)
		local tip = top + Vector3.new(math.cos(a) * 1.5, 0.4, math.sin(a) * 1.5)
		Kit.strut(parent, top + Vector3.new(0, 0.4, 0), tip, 0.15, {
			Color = CAMP_METAL,
			Material = Enum.Material.Metal,
			CanCollide = false,
		})
		Kit.ball(parent, tip, 0.8, { Color = CAMP_CANVAS, CanCollide = false })
	end

	-- instrument crates by the mast
	Kit.decor({
		Name = "Crate",
		Size = Vector3.new(2.2, 1.6, 1.6),
		CFrame = at(-4.5, 0.8, -3.5) * CFrame.Angles(0, math.rad(15), 0),
		Color = CAMP_WOOD,
		Material = Enum.Material.Wood,
		Parent = parent,
	})
	Kit.decor({
		Name = "Crate",
		Size = Vector3.new(1.4, 1.2, 1.4),
		CFrame = at(-4.3, 2.2, -3.4) * CFrame.Angles(0, math.rad(-20), 0),
		Color = CAMP_DARK,
		Material = Enum.Material.Wood,
		Parent = parent,
	})

	-- sign on two posts at the back of the deck, facing the hub
	local signZ = D / 2 - 1.5
	for _, x in { -5, 5 } do
		Kit.cylinder(parent, at(x, 0, signZ).Position, 6.2, 0.5, {
			Color = CAMP_WOOD,
			Material = Enum.Material.Wood,
		})
	end
	Kit.sign(
		parent,
		at(0, 5.4, signZ - 0.5),
		12,
		2.6,
		`{string.upper(def.displayName)} FIELD CAMP`,
		nil,
		{
			boardColor = zone.color,
			boardMaterial = Enum.Material.SmoothPlastic,
			titleColor = Color3.new(1, 1, 1),
			strokeColor = Color3.fromRGB(30, 30, 36),
			thickness = 0.5,
			twoSided = true,
		}
	)
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

-- Portals --------------------------------------------------------------------------

export type PortalLook = {
	ring: Color3,
	ringMaterial: Enum.Material?,
	step: Color3, -- the round step it stands on
	stepMaterial: Enum.Material?,
	sign: SignStyle,
}

local PORTAL_RADIUS = 6.5 -- of the ring's centre line
local PORTAL_LIFT = 1.4 -- the ring's lowest point above the step
local PORTAL_STEP = 0.45 -- step height: walk straight up onto it
local PORTAL_SEGMENTS = 20

-- A portal to another world standing on the ground at `frame`, facing
-- along frame.LookVector (the side players walk up from): a round step,
-- a ring round a glowing disc in the destination world's colour, a sign
-- with where it goes and what it needs, and the invisible box tagged
-- Portal (attribute ToWorld) that Systems/Worlds watches. Walking into the
-- disc takes you there. Fits in a Kit.PORTAL_SPACE circle.
function Kit.portal(
	parent: Instance,
	frame: CFrame,
	portal: WorldTypes.Portal,
	look: PortalLook
): BasePart
	local to = portal.to
	local model = Instance.new("Model")
	model.Name = `Portal{to.id}`
	local bottom = frame.Position
	Kit.cylinder(model, bottom - Vector3.new(0, 0.3, 0), PORTAL_STEP + 0.3, Kit.PORTAL_SPACE - 1, {
		Name = "Step",
		Color = look.step,
		Material = look.stepMaterial or Enum.Material.SmoothPlastic,
	})
	local floor = PORTAL_STEP
	local center = frame * CFrame.new(0, floor + PORTAL_LIFT + PORTAL_RADIUS, 0)
	local segment = 2 * PORTAL_RADIUS * math.tan(math.pi / PORTAL_SEGMENTS) + 0.25
	for i = 0, PORTAL_SEGMENTS - 1 do
		local angle = (i + 0.5) * 2 * math.pi / PORTAL_SEGMENTS
		Kit.decor({
			Name = "Ring",
			Size = Vector3.new(segment, 1.3, 1.4),
			CFrame = center
				* CFrame.new(math.cos(angle) * PORTAL_RADIUS, math.sin(angle) * PORTAL_RADIUS, 0)
				* CFrame.Angles(0, 0, angle + math.pi / 2),
			Color = look.ring,
			Material = look.ringMaterial or Enum.Material.Metal,
			CanCollide = false,
			Parent = model,
		})
	end
	-- feet: two blocks the ring stands on
	for _, side in { -1, 1 } do
		Kit.decor({
			Name = "Foot",
			Size = Vector3.new(1.6, PORTAL_LIFT + 1.2, 2),
			CFrame = frame * CFrame.new(side * 3.4, floor + (PORTAL_LIFT + 1.2) / 2, 0),
			Color = look.ring,
			Material = look.ringMaterial or Enum.Material.Metal,
			Parent = model,
		})
	end
	local disc = Kit.decor({
		Name = "Disc",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 2 * PORTAL_RADIUS - 0.8, 2 * PORTAL_RADIUS - 0.8),
		CFrame = center * CFrame.Angles(0, math.pi / 2, 0),
		Color = to.color,
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		CanCollide = false,
		CastShadow = false,
		Parent = model,
	})
	Kit.light(disc, to.color, 18, 2)
	Kit.emitter(disc, {
		Texture = Kit.TEXTURES.sparkle,
		Color = ColorSequence.new(to.color, Color3.new(1, 1, 1)),
		LightEmission = 1,
		Lifetime = NumberRange.new(0.8, 1.6),
		Rate = 14,
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new(0.5, 0),
	})
	local title = if portal.back
		then `BACK TO {string.upper(to.displayName)}`
		else string.upper(to.displayName)
	Kit.sign(
		model,
		frame * CFrame.new(0, floor + PORTAL_LIFT + 2 * PORTAL_RADIUS + 2.6, 0),
		15,
		3.4,
		title,
		if portal.requirement then `🔒 {portal.requirement}` else to.tagline,
		look.sign
	)
	local box = Kit.part({
		Name = "Portal",
		Size = Vector3.new(2 * PORTAL_RADIUS - 1, 2 * PORTAL_RADIUS, 6),
		CFrame = center,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Parent = model,
	})
	box:AddTag(Kit.PORTAL_TAG)
	box:SetAttribute("ToWorld", to.id)
	model.Parent = parent
	return box
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
