--!strict
-- Builds the placeholder map out of plain parts. Swap the art freely later:
-- the game only relies on these names:
--   Workspace.Map.Zones.<ZoneId>        invisible box where strikes land
--   Workspace.Map.PowerPlant.SellPad    touch to sell
--
-- To keep the map in your place file (so you can edit it in Studio), run
-- this once in Edit mode from the command bar:
--   require(game.ServerScriptService.Server.Lib.MapBuilder).build()
-- then save the place. The game only builds the map itself if it's missing.
--
-- Layout (top view, studs; -Z is north):
--
--              [ Power Plant ]   z = -95
--               [ SellPad ]      z = -72
--   [ MESA ]<ramp     spawn       [ SHORELINE ]
--   x = -120          (0, 40)     x = 115

local Lighting = game:GetService("Lighting")

local MapBuilder = {}

local COLORS = {
	ocean = Color3.fromRGB(38, 92, 140),
	grass = Color3.fromRGB(76, 120, 70),
	sand = Color3.fromRGB(214, 190, 130),
	mesa = Color3.fromRGB(150, 88, 62),
	rock = Color3.fromRGB(105, 105, 112),
	concrete = Color3.fromRGB(120, 124, 132),
	dark = Color3.fromRGB(45, 48, 56),
	volt = Color3.fromRGB(255, 214, 60),
	trunk = Color3.fromRGB(110, 78, 48),
	leaves = Color3.fromRGB(60, 140, 70),
}

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

local function folder(name: string, parent: Instance): Folder
	local newFolder = Instance.new("Folder")
	newFolder.Name = name
	newFolder.Parent = parent
	return newFolder
end

-- Floating text sign above a point.
local function sign(
	parent: Instance,
	name: string,
	position: Vector3,
	title: string,
	subtitle: string,
	color: Color3
)
	local anchor = part({
		Name = name,
		Size = Vector3.new(1, 1, 1),
		Position = position,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = parent,
	})
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(320, 110)
	billboard.MaxDistance = 400
	billboard.LightInfluence = 0
	billboard.Parent = anchor

	local function line(text: string, y: number, height: number, textColor: Color3)
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, height)
		label.Position = UDim2.fromScale(0, y)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = textColor
		label.TextStrokeTransparency = 0
		label.Text = text
		label.Parent = billboard
	end
	line(title, 0, 0.6, color)
	line(subtitle, 0.6, 0.4, Color3.new(1, 1, 1))
end

local function palm(parent: Instance, position: Vector3)
	part({
		Name = "PalmTrunk",
		ClassName = "Part",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(14, 1.6, 1.6),
		CFrame = CFrame.new(position + Vector3.new(0, 7, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = COLORS.trunk,
		Material = Enum.Material.Wood,
		Parent = parent,
	})
	part({
		Name = "PalmLeaves",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(7, 7, 7),
		Position = position + Vector3.new(0, 15, 0),
		Color = COLORS.leaves,
		Material = Enum.Material.Grass,
		Parent = parent,
	})
end

local function rock(parent: Instance, position: Vector3, size: Vector3, yaw: number)
	part({
		Name = "Rock",
		Size = size,
		CFrame = CFrame.new(position + Vector3.new(0, size.Y / 2, 0))
			* CFrame.Angles(0, math.rad(yaw), 0),
		Color = COLORS.rock,
		Material = Enum.Material.Slate,
		Parent = parent,
	})
end

-- Zone boxes are invisible and ignored by physics and raycasts; strikes pick
-- a random point inside them and raycast down to find the ground.
local function zoneArea(parent: Instance, name: string, position: Vector3, size: Vector3)
	part({
		Name = name,
		Size = size,
		Position = position,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = parent,
	})
end

local function setStormyLighting()
	Lighting.ClockTime = 15
	Lighting.Brightness = 2
	Lighting.OutdoorAmbient = Color3.fromRGB(110, 115, 135)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = 0.3
	atmosphere.Haze = 1.5
	atmosphere.Color = Color3.fromRGB(170, 180, 200)
	atmosphere.Decay = Color3.fromRGB(90, 100, 120)
	atmosphere.Parent = Lighting
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

function MapBuilder.build(): Folder
	local old = workspace:FindFirstChild("Map")
	if old then
		old:Destroy()
	end
	clearTemplate()

	local map = folder("Map", workspace)
	local ground = folder("Ground", map)
	local decor = folder("Decor", map)
	local zones = folder("Zones", map)
	local signs = folder("Signs", map)

	-- Ocean and island (island top surface is y = 0)
	part({
		Name = "Ocean",
		Size = Vector3.new(2048, 4, 2048),
		Position = Vector3.new(0, -4, 0),
		Color = COLORS.ocean,
		Material = Enum.Material.Glass,
		Transparency = 0.1,
		Parent = ground,
	})
	part({
		Name = "Island",
		Size = Vector3.new(360, 4, 300),
		Position = Vector3.new(0, -2, 0),
		Color = COLORS.grass,
		Material = Enum.Material.Grass,
		Parent = ground,
	})

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = Vector3.new(0, 0.5, 40)
	spawn.Color = COLORS.concrete
	spawn.Material = Enum.Material.Concrete
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = map

	-- Power Plant
	local plant = Instance.new("Model")
	plant.Name = "PowerPlant"
	plant.Parent = map
	part({
		Name = "Building",
		Size = Vector3.new(44, 24, 24),
		Position = Vector3.new(0, 12, -95),
		Color = COLORS.concrete,
		Material = Enum.Material.Concrete,
		Parent = plant,
	})
	part({
		Name = "Stripe",
		Size = Vector3.new(44.4, 2, 24.4),
		Position = Vector3.new(0, 20, -95),
		Color = COLORS.volt,
		Material = Enum.Material.Neon,
		Parent = plant,
	})
	for _, x in { -14, 14 } do
		part({
			Name = "Chimney",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(20, 6, 6),
			CFrame = CFrame.new(x, 34, -100) * CFrame.Angles(0, 0, math.rad(90)),
			Color = COLORS.dark,
			Material = Enum.Material.Metal,
			Parent = plant,
		})
	end
	part({
		Name = "SellPad",
		Size = Vector3.new(18, 1, 18),
		Position = Vector3.new(0, 0.5, -72),
		Color = COLORS.volt,
		Material = Enum.Material.Neon,
		Parent = plant,
	})
	plant.PrimaryPart = plant:FindFirstChild("Building") :: BasePart
	sign(
		signs,
		"PowerPlantSign",
		Vector3.new(0, 10, -72),
		"POWER PLANT",
		"Step on the pad to sell",
		COLORS.volt
	)

	-- Shoreline: open beach, everyone in the circle catches
	part({
		Name = "Sand",
		Size = Vector3.new(120, 0.4, 220),
		Position = Vector3.new(115, 0.2, 0),
		Color = COLORS.sand,
		Material = Enum.Material.Sand,
		Parent = ground,
	})
	zoneArea(zones, "Shoreline", Vector3.new(115, 2, 0), Vector3.new(104, 1, 200))
	sign(
		signs,
		"ShorelineSign",
		Vector3.new(70, 12, 0),
		"SHORELINE",
		"Everyone in the circle catches",
		Color3.fromRGB(255, 230, 120)
	)
	for _, z in { -90, -40, 30, 85 } do
		palm(decor, Vector3.new(172, 0, z))
	end

	-- Mesa: raised plateau, only the closest player catches (worth more)
	part({
		Name = "Mesa",
		Size = Vector3.new(100, 12, 120),
		Position = Vector3.new(-120, 6, 0),
		Color = COLORS.mesa,
		Material = Enum.Material.Sandstone,
		Parent = ground,
	})
	-- ramp up the east side: tall end against the mesa (x = -70), low end at x = -30
	part({
		Name = "MesaRamp",
		ClassName = "WedgePart",
		Size = Vector3.new(24, 12, 40),
		CFrame = CFrame.new(-50, 6, 0) * CFrame.Angles(0, math.rad(-90), 0),
		Color = COLORS.mesa,
		Material = Enum.Material.Sandstone,
		Parent = ground,
	})
	-- strike area is inset 10 studs from the edges so circles never hang off the cliff
	zoneArea(zones, "Mesa", Vector3.new(-120, 14, 0), Vector3.new(80, 1, 100))
	sign(
		signs,
		"MesaSign",
		Vector3.new(-50, 22, 0),
		"MESA",
		"One catcher per bolt - 4x Volts",
		Color3.fromRGB(255, 140, 90)
	)

	-- a few rocks for cover/landmarks
	rock(decor, Vector3.new(40, 0, -30), Vector3.new(8, 5, 6), 20)
	rock(decor, Vector3.new(-30, 0, 70), Vector3.new(10, 6, 7), 65)
	rock(decor, Vector3.new(-150, 12, -40), Vector3.new(7, 4, 6), 10)
	rock(decor, Vector3.new(-95, 12, 45), Vector3.new(6, 5, 8), 40)

	setStormyLighting()
	print("[MapBuilder] map built")
	return map
end

return MapBuilder
