--!strict
-- Builds the island: terrain, zones with glowing borders, the Power Plant,
-- decorations and lighting. Swap the art freely later; the game only
-- relies on these names:
--   Workspace.Map.Zones.<ZoneId>        invisible box = the zone's volume
--   Workspace.Map.PowerPlant.SellPad    touch to sell
--
-- The Studio updater plugin runs build() in Edit mode so you can see and
-- edit the map. The game also builds it at runtime if Workspace.Map is
-- missing. Maps built here are tagged AutoBuilt = true; the updater only
-- rebuilds a map with that tag, so delete the attribute (Map > Properties >
-- Attributes) to protect a map you've edited by hand.
--
-- Layout (top view, studs; -Z is north). Terrain top is y = 0.
--
--                 [ POWER PLANT ]  z = -105
--                   [SellPad]      z = -72
--   [ MESA y=12 ]<ramp  + spawn (0,30)  [ SHORELINE ]
--   x -160..-70          path          x 60..160

local Lighting = game:GetService("Lighting")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local MapBuilder = {}

local ISLAND_RADIUS = 195

local COLORS = {
	concrete = Color3.fromRGB(150, 152, 160),
	concreteDark = Color3.fromRGB(95, 98, 108),
	metal = Color3.fromRGB(60, 64, 74),
	volt = Color3.fromRGB(255, 214, 60),
	electric = Color3.fromRGB(110, 190, 255),
	trunk = Color3.fromRGB(105, 74, 46),
	palm = Color3.fromRGB(70, 150, 70),
	tree = Color3.fromRGB(52, 112, 60),
	lamp = Color3.fromRGB(255, 200, 130),
}

-- Zone footprints: floor height and the bordered rectangle.
type ZoneLayout = {
	floor: number,
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
	gate: "West" | "East",
}

local ZONE_LAYOUT: { [string]: ZoneLayout } = {
	Shoreline = { floor = 0, minX = 60, maxX = 160, minZ = -80, maxZ = 80, gate = "West" },
	Mesa = { floor = 12, minX = -160, maxX = -70, minZ = -55, maxZ = 55, gate = "East" },
}

local ZONE_HEIGHT = 42 -- zone volume reaches this far above the floor

-- Helpers -------------------------------------------------------------------

local function part(props: { [string]: any }): BasePart
	local className = props.ClassName or "Part"
	local newPart = Instance.new(className) :: BasePart
	newPart.Anchored = true
	newPart.TopSurface = Enum.SurfaceType.Smooth
	newPart.BottomSurface = Enum.SurfaceType.Smooth
	newPart.Material = Enum.Material.SmoothPlastic
	local parent = props.Parent
	for key, value in props do
		if key ~= "ClassName" and key ~= "Parent" then
			(newPart :: any)[key] = value
		end
	end
	newPart.Parent = parent
	return newPart
end

-- Decorative part: no collisions with raycasts/touch so it never gets in
-- the way of strikes or selling.
local function decor(props: { [string]: any }): BasePart
	props.CanQuery = false
	props.CanTouch = false
	return part(props)
end

local function folder(name: string, parent: Instance): Folder
	local newFolder = Instance.new("Folder")
	newFolder.Name = name
	newFolder.Parent = parent
	return newFolder
end

local function vertical(position: Vector3): CFrame
	-- cylinders run along X; tip them upright
	return CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
end

-- Big readable text on one face of a part.
local function surfaceText(
	target: BasePart,
	face: Enum.NormalId,
	title: string,
	subtitle: string?,
	color: Color3
)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Brightness = 1.5
	gui.Parent = target

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = UDim2.fromScale(1, if subtitle then 0.62 else 1)
	titleLabel.Font = Enum.Font.LuckiestGuy
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = color
	titleLabel.Text = title
	titleLabel.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 6
	stroke.Color = Color3.fromRGB(15, 15, 25)
	stroke.Parent = titleLabel

	if subtitle then
		local subtitleLabel = Instance.new("TextLabel")
		subtitleLabel.BackgroundTransparency = 1
		subtitleLabel.Position = UDim2.fromScale(0.05, 0.62)
		subtitleLabel.Size = UDim2.fromScale(0.9, 0.34)
		subtitleLabel.Font = Enum.Font.BuilderSansBold
		subtitleLabel.TextScaled = true
		subtitleLabel.TextColor3 = Color3.new(1, 1, 1)
		subtitleLabel.Text = subtitle
		subtitleLabel.Parent = gui
		local subStroke = Instance.new("UIStroke")
		subStroke.Thickness = 4
		subStroke.Color = Color3.fromRGB(15, 15, 25)
		subStroke.Parent = subtitleLabel
	end
end

local function light(parent: Instance, color: Color3, range: number, brightness: number)
	local pointLight = Instance.new("PointLight")
	pointLight.Color = color
	pointLight.Range = range
	pointLight.Brightness = brightness
	pointLight.Shadows = false
	pointLight.Parent = parent
end

-- Terrain -------------------------------------------------------------------

local function buildTerrain()
	local terrain = workspace.Terrain
	terrain:Clear()

	-- ocean (surface at y = -2) over a sandy sea floor
	terrain:FillBlock(CFrame.new(0, -22, 0), Vector3.new(1400, 8, 1400), Enum.Material.Sand)
	terrain:FillBlock(CFrame.new(0, -10, 0), Vector3.new(1400, 16, 1400), Enum.Material.Water)

	-- island: sand beach ring, grass on top
	terrain:FillCylinder(CFrame.new(0, -8, 0), 14, ISLAND_RADIUS + 20, Enum.Material.Sand)
	terrain:FillCylinder(CFrame.new(0, -7, 0), 14, ISLAND_RADIUS, Enum.Material.Grass)

	-- Shoreline: wide sandy beach on the east side
	local shore = ZONE_LAYOUT.Shoreline
	terrain:FillBlock(
		CFrame.new((shore.minX + shore.maxX) / 2, -4, 0),
		Vector3.new(shore.maxX - shore.minX + 16, 8, shore.maxZ - shore.minZ + 16),
		Enum.Material.Sand
	)

	-- Mesa: sandstone plateau (top y = 12) with a ramp up its east side
	terrain:FillBlock(CFrame.new(-115, 0, 0), Vector3.new(100, 24, 120), Enum.Material.Sandstone)
	-- wedge: tall end against the mesa (x = -65), low end at x = -25
	terrain:FillWedge(
		CFrame.new(-45, 6, 0) * CFrame.Angles(0, math.rad(-90), 0),
		Vector3.new(16, 12, 40),
		Enum.Material.Sandstone
	)
	-- boulders around the mesa's base for a natural look
	for _, spot in
		{
			Vector3.new(-160, 2, -62),
			Vector3.new(-70, 2, -62),
			Vector3.new(-165, 2, 40),
			Vector3.new(-90, 2, 64),
		}
	do
		terrain:FillBall(spot, 9, Enum.Material.Rock)
	end

	-- cobblestone paths from the centre to each area
	local paths: { { center: Vector3, size: Vector3 } } = {
		{ center = Vector3.new(30, -1, 0), size = Vector3.new(60, 2, 10) }, -- east to Shoreline
		{ center = Vector3.new(-12.5, -1, 0), size = Vector3.new(25, 2, 10) }, -- west to the Mesa ramp
		{ center = Vector3.new(0, -1, -42), size = Vector3.new(10, 2, 84) }, -- north to the Power Plant
		{ center = Vector3.new(0, -1, 18), size = Vector3.new(10, 2, 36) }, -- south to spawn
	}
	for _, path in paths do
		terrain:FillBlock(CFrame.new(path.center), path.size, Enum.Material.Cobblestone)
	end

	-- scattered rocks on the grass
	for _, spot in
		{
			Vector3.new(40, 0, 60),
			Vector3.new(-40, 0, 80),
			Vector3.new(50, 0, -60),
			Vector3.new(-50, 0, -90),
		}
	do
		terrain:FillBall(spot, 4, Enum.Material.Rock)
	end
end

-- Zones ---------------------------------------------------------------------

local function buildZone(map: Instance, zonesModel: Model, zoneId: string, layout: ZoneLayout)
	local def = Config.ZONES[zoneId]
	local color = def.color
	local width = layout.maxX - layout.minX
	local depth = layout.maxZ - layout.minZ
	local centerX = (layout.minX + layout.maxX) / 2
	local centerZ = (layout.minZ + layout.maxZ) / 2
	local floor = layout.floor

	-- the zone volume (what the code checks against)
	part({
		Name = zoneId,
		Size = Vector3.new(width, ZONE_HEIGHT, depth),
		Position = Vector3.new(centerX, floor - 1 + ZONE_HEIGHT / 2, centerZ),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = zonesModel,
	})

	local border = folder(`{zoneId}Border`, map)

	-- glowing rail + shimmering force-field wall along each side
	local sides = {
		{ Vector3.new(centerX, 0, layout.minZ), Vector3.new(width, 0, 0) },
		{ Vector3.new(centerX, 0, layout.maxZ), Vector3.new(width, 0, 0) },
		{ Vector3.new(layout.minX, 0, centerZ), Vector3.new(0, 0, depth) },
		{ Vector3.new(layout.maxX, 0, centerZ), Vector3.new(0, 0, depth) },
	}
	for _, side in sides do
		local center, span = side[1], side[2]
		local sizeX = math.max(span.X, 0.6)
		local sizeZ = math.max(span.Z, 0.6)
		decor({
			Name = "Rail",
			Size = Vector3.new(sizeX, 0.4, sizeZ),
			Position = Vector3.new(center.X, floor + 0.3, center.Z),
			Color = color,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
			Parent = border,
		})
		decor({
			Name = "Wall",
			Size = Vector3.new(math.max(span.X, 0.2), 7, math.max(span.Z, 0.2)),
			Position = Vector3.new(center.X, floor + 3.5, center.Z),
			Color = color,
			Material = Enum.Material.ForceField,
			Transparency = 0.2,
			CanCollide = false,
			CastShadow = false,
			Parent = border,
		})
	end

	-- lightning-rod posts every ~20 studs around the edge
	local function post(x: number, z: number)
		decor({
			Name = "Post",
			Size = Vector3.new(1, 6, 1),
			Position = Vector3.new(x, floor + 3, z),
			Color = COLORS.metal,
			Material = Enum.Material.Metal,
			Parent = border,
		})
		local cap = decor({
			Name = "PostCap",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.6, 1.6, 1.6),
			Position = Vector3.new(x, floor + 6.5, z),
			Color = color,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = border,
		})
		light(cap, color, 10, 1)
	end
	local stepsX = math.max(1, math.round(width / 20))
	local stepsZ = math.max(1, math.round(depth / 20))
	for i = 0, stepsX do
		local x = layout.minX + width * i / stepsX
		post(x, layout.minZ)
		post(x, layout.maxZ)
	end
	for i = 1, stepsZ - 1 do
		local z = layout.minZ + depth * i / stepsZ
		post(layout.minX, z)
		post(layout.maxX, z)
	end

	-- entrance arch with the zone's name, facing the path
	local gateX = if layout.gate == "West" then layout.minX else layout.maxX
	local outward = if layout.gate == "West" then Enum.NormalId.Left else Enum.NormalId.Right
	local inward = if layout.gate == "West" then Enum.NormalId.Right else Enum.NormalId.Left
	for _, z in { centerZ - 11, centerZ + 11 } do
		decor({
			Name = "ArchPillar",
			Size = Vector3.new(2, 16, 2),
			Position = Vector3.new(gateX, floor + 8, z),
			Color = COLORS.metal,
			Material = Enum.Material.DiamondPlate,
			Parent = border,
		})
		decor({
			Name = "ArchGlow",
			Size = Vector3.new(2.2, 14, 0.4),
			Position = Vector3.new(gateX, floor + 8, z),
			Color = color,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = border,
		})
	end
	local beam = decor({
		Name = "ArchSign",
		Size = Vector3.new(1.5, 6, 26),
		Position = Vector3.new(gateX, floor + 18, centerZ),
		Color = COLORS.metal,
		Material = Enum.Material.Metal,
		Parent = border,
	})
	surfaceText(beam, outward, string.upper(def.displayName), def.tagline, color)
	surfaceText(beam, inward, string.upper(def.displayName), "Fast walking outside the zone", color)
	light(beam, color, 24, 1.5)
end

-- Power Plant ---------------------------------------------------------------

local function buildPowerPlant(map: Instance)
	local plant = Instance.new("Model")
	plant.Name = "PowerPlant"
	plant.Parent = map

	decor({
		Name = "Plaza",
		Size = Vector3.new(80, 0.4, 56),
		Position = Vector3.new(0, 0.2, -88),
		Color = COLORS.concreteDark,
		Material = Enum.Material.Concrete,
		Parent = plant,
	})
	local hall = part({
		Name = "Building",
		Size = Vector3.new(44, 22, 22),
		Position = Vector3.new(0, 11, -105),
		Color = COLORS.concrete,
		Material = Enum.Material.Concrete,
		Parent = plant,
	})
	decor({
		Name = "Roof",
		Size = Vector3.new(46, 1.2, 24),
		Position = Vector3.new(0, 22.6, -105),
		Color = COLORS.metal,
		Material = Enum.Material.Metal,
		Parent = plant,
	})
	-- glowing window bands on the front
	for _, y in { 7, 13 } do
		decor({
			Name = "Windows",
			Size = Vector3.new(38, 2, 0.4),
			Position = Vector3.new(0, y, -93.9),
			Color = COLORS.volt,
			Material = Enum.Material.Neon,
			Parent = plant,
		})
	end
	surfaceText(hall, Enum.NormalId.Back, "POWER PLANT", nil, COLORS.volt)
	local signGui = hall:FindFirstChildOfClass("SurfaceGui")
	if signGui then
		-- keep the title on the upper wall, above the windows
		local title = signGui:FindFirstChildOfClass("TextLabel")
		if title then
			title.Size = UDim2.fromScale(0.9, 0.22)
			title.Position = UDim2.fromScale(0.05, 0.02)
		end
	end

	-- cooling towers with steam
	for _, x in { -34, 34 } do
		local tower = decor({
			Name = "CoolingTower",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(32, 18, 18),
			CFrame = vertical(Vector3.new(x, 16, -112)),
			Color = Color3.fromRGB(200, 200, 205),
			Material = Enum.Material.Concrete,
			Parent = plant,
		})
		decor({
			Name = "TowerStripe",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(2, 18.3, 18.3),
			CFrame = vertical(Vector3.new(x, 26, -112)),
			Color = Color3.fromRGB(220, 70, 60),
			Material = Enum.Material.SmoothPlastic,
			Parent = plant,
		})
		local steam = Instance.new("ParticleEmitter")
		steam.Name = "Steam"
		steam.Texture = "rbxasset://textures/particles/smoke_main.dds"
		steam.Color = ColorSequence.new(Color3.fromRGB(230, 232, 240))
		steam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.4),
			NumberSequenceKeypoint.new(1, 1),
		})
		steam.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 6),
			NumberSequenceKeypoint.new(1, 18),
		})
		steam.Lifetime = NumberRange.new(5, 8)
		steam.Rate = 4
		steam.Speed = NumberRange.new(4, 7)
		steam.EmissionDirection = Enum.NormalId.Right -- tower's +X points up
		steam.SpreadAngle = Vector2.new(10, 10)
		-- emit from the top opening only, not the whole tower
		local top = Instance.new("Attachment")
		top.Name = "SteamOutlet"
		top.Position = Vector3.new(16, 0, 0)
		top.Parent = tower
		steam.Parent = top
	end

	-- tesla coil on the roof (the client makes it crackle)
	decor({
		Name = "CoilBase",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(6, 4, 4),
		CFrame = vertical(Vector3.new(0, 26, -105)),
		Color = COLORS.metal,
		Material = Enum.Material.Metal,
		Parent = plant,
	})
	for i = 0, 2 do
		decor({
			Name = "CoilRing",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.6, 5, 5),
			CFrame = vertical(Vector3.new(0, 24.5 + i * 1.6, -105)),
			Color = Color3.fromRGB(190, 120, 60),
			Material = Enum.Material.Metal,
			Parent = plant,
		})
	end
	local orb = decor({
		Name = "CoilOrb",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(5, 5, 5),
		Position = Vector3.new(0, 31, -105),
		Color = COLORS.electric,
		Material = Enum.Material.Neon,
		Parent = plant,
	})
	light(orb, COLORS.electric, 40, 2)

	-- the sell pad
	local pad = part({
		Name = "SellPad",
		Size = Vector3.new(20, 1, 20),
		Position = Vector3.new(0, 0.5, -72),
		Color = COLORS.volt,
		Material = Enum.Material.Neon,
		Parent = plant,
	})
	decor({
		Name = "SellPadRim",
		Size = Vector3.new(23, 0.8, 23),
		Position = Vector3.new(0, 0.4, -72),
		Color = COLORS.metal,
		Material = Enum.Material.DiamondPlate,
		Parent = plant,
	})
	surfaceText(
		pad,
		Enum.NormalId.Top,
		"SELL",
		"Step here to sell your charges",
		Color3.fromRGB(40, 30, 0)
	)
	light(pad, COLORS.volt, 30, 1.5)

	plant.PrimaryPart = hall
end

-- Decoration ----------------------------------------------------------------

local function palm(parent: Instance, position: Vector3, lean: number)
	local top = position + Vector3.new(lean, 15, 0)
	local trunkCenter = (position + top) / 2
	decor({
		Name = "PalmTrunk",
		Size = Vector3.new(1.4, (top - position).Magnitude, 1.4),
		CFrame = CFrame.lookAt(trunkCenter, top) * CFrame.Angles(math.rad(90), 0, 0),
		Color = COLORS.trunk,
		Material = Enum.Material.Wood,
		Parent = parent,
	})
	for i = 0, 4 do
		local angle = math.rad(i * 72)
		decor({
			Name = "PalmLeaf",
			Size = Vector3.new(1, 0.3, 8),
			CFrame = CFrame.new(top)
				* CFrame.Angles(0, angle, 0)
				* CFrame.Angles(math.rad(-25), 0, 0)
				* CFrame.new(0, 0, -3.5),
			Color = COLORS.palm,
			Material = Enum.Material.Grass,
			CanCollide = false,
			Parent = parent,
		})
	end
end

local function tree(parent: Instance, position: Vector3, scale: number)
	decor({
		Name = "TreeTrunk",
		Size = Vector3.new(1.6, 8, 1.6) * scale,
		Position = position + Vector3.new(0, 4 * scale, 0),
		Color = COLORS.trunk,
		Material = Enum.Material.Wood,
		Parent = parent,
	})
	decor({
		Name = "TreeLeaves",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(9, 9, 9) * scale,
		Position = position + Vector3.new(0, 10 * scale, 0),
		Color = COLORS.tree,
		Material = Enum.Material.Grass,
		Parent = parent,
	})
end

local function lamp(parent: Instance, position: Vector3)
	decor({
		Name = "LampPole",
		Size = Vector3.new(0.6, 10, 0.6),
		Position = position + Vector3.new(0, 5, 0),
		Color = COLORS.metal,
		Material = Enum.Material.Metal,
		Parent = parent,
	})
	local head = decor({
		Name = "LampHead",
		Size = Vector3.new(1.6, 1, 1.6),
		Position = position + Vector3.new(0, 10.4, 0),
		Color = COLORS.lamp,
		Material = Enum.Material.Neon,
		Parent = parent,
	})
	light(head, COLORS.lamp, 22, 1.2)
end

local function buildDecor(map: Instance)
	local decorFolder = folder("Decor", map)

	-- palms around the beach, skipping the zones
	for i = 0, 17 do
		local angle = math.rad(i * 20 + 7)
		local position = Vector3.new(math.cos(angle) * 188, 0, math.sin(angle) * 188)
		local inShoreline = position.X > 50 and math.abs(position.Z) < 95
		local inMesa = position.X < -55 and math.abs(position.Z) < 75
		if not inShoreline and not inMesa then
			palm(decorFolder, position, if i % 2 == 0 then 2 else -2)
		end
	end

	for _, spot in
		{
			Vector3.new(-30, 0, 55),
			Vector3.new(35, 0, 45),
			Vector3.new(-45, 0, -40),
			Vector3.new(45, 0, -35),
			Vector3.new(-20, 0, 110),
			Vector3.new(25, 0, 120),
		}
	do
		tree(decorFolder, spot, 0.9 + (math.abs(spot.X) % 3) * 0.15)
	end

	for _, spot in
		{
			Vector3.new(8, 0, 10),
			Vector3.new(-8, 0, -10),
			Vector3.new(8, 0, -40),
			Vector3.new(-8, 0, -60),
			Vector3.new(30, 0, 8),
			Vector3.new(-20, 0, 8),
		}
	do
		lamp(decorFolder, spot)
	end

	-- island name stone beside spawn, its front face turned toward the spawn pad
	local stone = decor({
		Name = "WelcomeStone",
		Size = Vector3.new(16, 6, 2),
		CFrame = CFrame.lookAt(Vector3.new(22, 3, 14), Vector3.new(0, 3, 34)),
		Color = COLORS.concreteDark,
		Material = Enum.Material.Slate,
		Parent = decorFolder,
	})
	surfaceText(
		stone,
		Enum.NormalId.Front,
		"STORM BOTTLER",
		"Catch lightning. Sell it. Get rich.",
		COLORS.volt
	)
end

-- Lighting ------------------------------------------------------------------

local function ensure<T>(parent: Instance, className: string, name: string): T
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing :: any
	end
	local created = Instance.new(className :: any)
	created.Name = name
	created.Parent = parent
	return created :: any
end

local function setLighting()
	Lighting.ClockTime = 16.5
	Lighting.Brightness = 2.2
	Lighting.Ambient = Color3.fromRGB(45, 48, 62)
	Lighting.OutdoorAmbient = Color3.fromRGB(125, 130, 150)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.25

	local atmosphere: Atmosphere = ensure(Lighting, "Atmosphere", "Atmosphere")
	atmosphere.Density = 0.32
	atmosphere.Offset = 0.15
	atmosphere.Color = Color3.fromRGB(195, 202, 218)
	atmosphere.Decay = Color3.fromRGB(100, 110, 135)
	atmosphere.Glare = 0.2
	atmosphere.Haze = 1.6

	local bloom: BloomEffect = ensure(Lighting, "BloomEffect", "Bloom")
	bloom.Intensity = 0.7
	bloom.Size = 30
	bloom.Threshold = 1.3

	local grade: ColorCorrectionEffect = ensure(Lighting, "ColorCorrectionEffect", "StormGrade")
	grade.Brightness = 0
	grade.Contrast = 0.1
	grade.Saturation = 0.1
	grade.TintColor = Color3.fromRGB(240, 244, 255)

	local sunRays: SunRaysEffect = ensure(Lighting, "SunRaysEffect", "SunRays")
	sunRays.Intensity = 0.05
	sunRays.Spread = 0.6

	local clouds: Clouds = ensure(workspace.Terrain, "Clouds", "Clouds")
	clouds.Cover = 0.62
	clouds.Density = 0.55
	clouds.Color = Color3.fromRGB(215, 218, 230)

	local terrain = workspace.Terrain
	terrain.WaterColor = Color3.fromRGB(30, 110, 150)
	terrain.WaterTransparency = 0.6
	terrain.WaterWaveSize = 0.2
	terrain.WaterWaveSpeed = 12
	terrain.WaterReflectance = 0.4
end

-- Removes the default Baseplate template parts, which would overlap the island.
local function clearTemplate()
	for _, name in { "Baseplate", "SpawnLocation" } do
		local existing = workspace:FindFirstChild(name)
		if existing and existing:IsA("BasePart") then
			existing:Destroy()
			print(`[MapBuilder] removed template part {name}`)
		end
	end
end

-- Build ---------------------------------------------------------------------

function MapBuilder.build(): Folder
	local old = workspace:FindFirstChild("Map")
	if old then
		old:Destroy()
	end
	clearTemplate()
	buildTerrain()

	local map = folder("Map", workspace)
	map:SetAttribute("AutoBuilt", true)

	-- zone boxes stay loaded on every client even with streaming on
	local zonesModel = Instance.new("Model")
	zonesModel.Name = "Zones"
	zonesModel.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	zonesModel.Parent = map
	for zoneId, layout in ZONE_LAYOUT do
		buildZone(map, zonesModel, zoneId, layout)
	end

	buildPowerPlant(map)
	buildDecor(map)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = Vector3.new(0, 0.5, 30)
	spawn.Color = COLORS.concreteDark
	spawn.Material = Enum.Material.DiamondPlate
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = map
	local spawnDecal = spawn:FindFirstChildOfClass("Decal")
	if spawnDecal then
		spawnDecal:Destroy()
	end

	setLighting()
	print("[MapBuilder] map built")
	return map
end

return MapBuilder
