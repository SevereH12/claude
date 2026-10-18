--!strict
-- Storm Society field scientists, built from plain parts (no meshes). Each is
-- a small, chunky figure (about two thirds of a player) in a cream field coat
-- with goggles, a badge and a hood in the role colour; the role's instrument
-- is the silhouette. Built standing at the origin, facing -Z, 14 parts or
-- fewer. Parts the animator moves are named: Instrument, Arm, Hood, and
-- TankFill (Chemist), Tape (Analyst), Balloon/Stripe/Stripe2/Tether/Peg
-- (Storm Chaser). Everything is anchored; nothing collides.

local ResearcherModels = {}

-- Unscaled units below; every size and position is multiplied by this.
ResearcherModels.SCALE = 0.85
local S = ResearcherModels.SCALE

local COAT = Color3.fromRGB(232, 224, 200)
local DARK = Color3.fromRGB(58, 62, 72)
local BRASS = Color3.fromRGB(196, 158, 78)
local COPPER = Color3.fromRGB(184, 108, 64)
local WOOD = Color3.fromRGB(140, 104, 70)
local PAPER = Color3.fromRGB(240, 238, 228)
local CYAN = Color3.fromRGB(90, 230, 255)

ResearcherModels.ACCENTS = {
	Forecaster = Color3.fromRGB(80, 150, 220),
	RodTech = Color3.fromRGB(214, 124, 58),
	Analyst = Color3.fromRGB(150, 110, 200),
	Chemist = Color3.fromRGB(64, 184, 148),
	StormChaser = Color3.fromRGB(214, 78, 68),
} :: { [string]: Color3 }

-- Cylinders run along X; this turns one upright.
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))
-- ...and this turns one to run along Z (facing the front).
local FACING = CFrame.Angles(0, math.rad(90), 0)

local function piece(model: Model, name: string, props: { [string]: any }): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	local position: Vector3 = props.Position or Vector3.zero
	local rotation: CFrame = props.Rotation or CFrame.identity
	props.Position = nil
	props.Rotation = nil
	for key, value in props do
		(part :: any)[key] = value
	end
	part.Size = part.Size * S
	part.CFrame = CFrame.new(position * S) * rotation
	part.Parent = model
	return part
end

-- A thin block from a to b (unscaled points).
local function strut(
	model: Model,
	name: string,
	a: Vector3,
	b: Vector3,
	thickness: number,
	color: Color3
): BasePart
	local mid = (a + b) / 2
	return piece(model, name, {
		Size = Vector3.new(thickness, thickness, (b - a).Magnitude),
		Position = mid,
		Rotation = CFrame.lookAt(Vector3.zero, b - a),
		Color = color,
	})
end

local function figure(model: Model, accent: Color3)
	piece(model, "Boots", {
		Size = Vector3.new(1.6, 0.9, 1.2),
		Position = Vector3.new(0, 0.45, 0),
		Color = DARK,
	})
	piece(model, "Body", {
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2, 2.2, 1.7),
		Position = Vector3.new(0, 1.9, 0),
		Color = COAT,
		Material = Enum.Material.Fabric,
	})
	piece(model, "Head", {
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.4, 1.4, 1.4),
		Position = Vector3.new(0, 3.5, 0),
		Color = Color3.fromRGB(236, 190, 150),
	})
	piece(model, "Goggles", {
		Size = Vector3.new(1.2, 0.4, 0.3),
		Position = Vector3.new(0, 3.55, -0.62),
		Color = DARK,
		Material = Enum.Material.Metal,
	})
	piece(model, "Hood", {
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.7, 1.2, 1.7),
		Position = Vector3.new(0, 3.95, 0.2),
		Color = accent,
		Material = Enum.Material.Fabric,
	})
	piece(model, "Badge", {
		Size = Vector3.new(0.45, 0.45, 0.1),
		Position = Vector3.new(0.55, 2.3, -0.74),
		Color = BRASS,
		Material = Enum.Material.Metal,
	})
	-- the arm hangs from the shoulder; the animator swings it about that point
	piece(model, "Arm", {
		Size = Vector3.new(0.5, 1.3, 0.5),
		Position = Vector3.new(1.2, 2.1, -0.1),
		Color = COAT,
		Material = Enum.Material.Fabric,
	})
end

local function forecaster(model: Model)
	local top = Vector3.new(-2.6, 3.0, -0.4)
	for i = 1, 3 do
		local a = math.rad(i * 120 + 30)
		strut(
			model,
			`Leg{i}`,
			top,
			top + Vector3.new(math.cos(a) * 1, -3, math.sin(a) * 1),
			0.18,
			WOOD
		)
	end
	piece(model, "Instrument", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 1.5, 1.5),
		Position = top + Vector3.new(0, 0.5, 0),
		Rotation = FACING,
		Color = BRASS,
		Material = Enum.Material.Metal,
	})
	piece(model, "Clipboard", {
		Size = Vector3.new(0.9, 1.2, 0.12),
		Position = top + Vector3.new(1.1, -0.5, -0.2),
		Rotation = CFrame.Angles(0.25, 0, 0.1),
		Color = WOOD,
		Material = Enum.Material.Wood,
	})
end

local function rodTech(model: Model)
	piece(model, "Base", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.25, 1.6, 1.6),
		Position = Vector3.new(-2.8, 0.12, -0.2),
		Rotation = UPRIGHT,
		Color = DARK,
		Material = Enum.Material.Metal,
	})
	piece(model, "Rod", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(6, 0.25, 0.25),
		Position = Vector3.new(-2.8, 3.2, -0.2),
		Rotation = UPRIGHT,
		Color = COPPER,
		Material = Enum.Material.Metal,
	})
	piece(model, "Instrument", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.9, 1.1, 1.1),
		Position = Vector3.new(-2.8, 2.4, -0.2),
		Rotation = UPRIGHT,
		Color = Color3.fromRGB(150, 84, 52),
		Material = Enum.Material.Metal,
	})
	piece(model, "Cable", {
		Size = Vector3.new(0.2, 0.2, 3),
		Position = Vector3.new(-3.2, 0.15, -1.9),
		Color = DARK,
	})
end

local function analyst(model: Model)
	piece(model, "DeskTop", {
		Size = Vector3.new(3.2, 0.25, 1.5),
		Position = Vector3.new(0, 1.7, -2.1),
		Color = WOOD,
		Material = Enum.Material.Wood,
	})
	for _, side in { -1, 1 } do
		piece(model, side < 0 and "DeskLegL" or "DeskLegR", {
			Size = Vector3.new(0.25, 1.6, 1.2),
			Position = Vector3.new(side * 1.4, 0.8, -2.1),
			Color = DARK,
			Material = Enum.Material.Metal,
		})
	end
	piece(model, "Instrument", {
		Size = Vector3.new(1.6, 1.1, 0.12),
		Position = Vector3.new(-0.5, 2.4, -2.55),
		Rotation = CFrame.Angles(-0.2, 0, 0),
		Color = Color3.fromRGB(60, 170, 190),
		Material = Enum.Material.Neon,
	})
	piece(model, "Printer", {
		Size = Vector3.new(1, 0.6, 0.8),
		Position = Vector3.new(1, 2.12, -2.1),
		Color = DARK,
		Material = Enum.Material.Metal,
	})
	-- the tape grows out of the printer toward the front (-Z)
	piece(model, "Tape", {
		Size = Vector3.new(0.4, 0.04, 0.15),
		Position = Vector3.new(1, 2.46, -2.55),
		Color = PAPER,
	})
end

local function chemist(model: Model)
	piece(model, "Instrument", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2.4, 1.6, 1.6),
		Position = Vector3.new(0, 2.3, 1.35),
		Rotation = UPRIGHT,
		Color = Color3.fromRGB(190, 230, 255),
		Material = Enum.Material.Glass,
		Transparency = 0.45,
	})
	piece(model, "TankFill", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, 1.3, 1.3),
		Position = Vector3.new(0, 2.3, 1.35),
		Rotation = UPRIGHT,
		Color = CYAN,
		Material = Enum.Material.Neon,
	})
	piece(model, "TankCap", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 0.9, 0.9),
		Position = Vector3.new(0, 3.6, 1.35),
		Rotation = UPRIGHT,
		Color = DARK,
		Material = Enum.Material.Metal,
	})
end

local function stormChaser(model: Model)
	local balloon = Vector3.new(2.6, 7, 0.2)
	piece(model, "Peg", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 0.3, 0.3),
		Position = Vector3.new(2.6, 0.5, 0.2),
		Rotation = UPRIGHT,
		Color = DARK,
		Material = Enum.Material.Metal,
	})
	piece(model, "Balloon", {
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(3.2, 3.2, 3.2),
		Position = balloon,
		Color = Color3.fromRGB(214, 78, 68),
		Material = Enum.Material.Fabric,
	})
	piece(model, "Stripe", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, 3.3, 3.3),
		Position = balloon,
		Rotation = UPRIGHT,
		Color = PAPER,
		Material = Enum.Material.Fabric,
	})
	piece(model, "Stripe2", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, 2.7, 2.7),
		Position = balloon + Vector3.new(0, 0.95, 0),
		Rotation = UPRIGHT,
		Color = PAPER,
		Material = Enum.Material.Fabric,
	})
	-- the animator re-aims the tether between the peg and the balloon
	strut(model, "Tether", Vector3.new(2.6, 1, 0.2), balloon - Vector3.new(0, 1.6, 0), 0.08, DARK)
end

local BUILDERS: { [string]: (Model) -> () } = {
	Forecaster = forecaster,
	RodTech = rodTech,
	Analyst = analyst,
	Chemist = chemist,
	StormChaser = stormChaser,
}

-- A researcher standing at the origin, facing -Z. The pivot is at their feet.
function ResearcherModels.build(roleId: string): Model
	local model = Instance.new("Model")
	model.Name = roleId
	figure(model, ResearcherModels.ACCENTS[roleId] or Color3.fromRGB(120, 140, 160))
	local builder = BUILDERS[roleId]
	if builder then
		builder(model)
	end
	model.WorldPivot = CFrame.identity
	return model
end

return ResearcherModels
