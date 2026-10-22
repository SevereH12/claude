--!strict
-- Every character wears boots, coloured by the boot tier they own (set here
-- on the server, so everyone sees everyone's boots). Above the starter pair
-- they leave a faint cyan spark trail while the player moves inside a storm
-- zone, the only place boots make you faster. Jet Boots pass owners get heel
-- flames and a jet trail while they run between zones, where the pass makes
-- them faster.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Zones = require(ReplicatedStorage.Shared.Util.Zones)
local Passes = require(script.Parent.Passes)
local PlayerData = require(script.Parent.PlayerData)

local BOOTS_NAME = "Boots"
local SOLE_COLOR = Color3.fromRGB(45, 40, 38)
local SPARK_COLOR = Color3.fromRGB(110, 230, 255)
local JET_CORE = Color3.fromRGB(255, 236, 170)
local JET_COLOR = Color3.fromRGB(255, 140, 50)
local JET_TAIL = Color3.fromRGB(255, 70, 40)

-- Boot colour per tier, in Config.BOOTS order; tiers past the end reuse the last.
local TIER_COLORS = {
	Color3.fromRGB(240, 196, 40), -- Rain Boots: classic yellow wellies
	Color3.fromRGB(70, 160, 230), -- Puddle Jumpers
	Color3.fromRGB(90, 200, 150), -- Squall Skippers
	Color3.fromRGB(170, 110, 230), -- Gale Striders
	Color3.fromRGB(40, 44, 60), -- Thunder Treads
}

local Boots = {}

local function bootPart(parent: Instance, name: string, size: Vector3, color: Color3): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	part.Parent = parent
	return part
end

local function weldTo(foot: BasePart, part: BasePart, offset: CFrame)
	local weld = Instance.new("Weld")
	weld.Part0 = foot
	weld.Part1 = part
	weld.C0 = offset
	weld.Parent = part
end

-- One boot: a body around the foot and ankle and a darker sole, 2 parts.
-- R15 feet are short parts; on R6 the foot is the bottom of the leg.
local function makeBoot(model: Model, foot: BasePart, isR15: boolean, color: Color3)
	local s = foot.Size
	local bottom = if isR15 then -s.Y / 2 else -1
	local body = bootPart(
		model,
		"Boot",
		Vector3.new(s.X + 0.16, if isR15 then s.Y + 0.6 else 0.8, s.Z + 0.16),
		color
	)
	weldTo(foot, body, CFrame.new(0, bottom + body.Size.Y / 2, 0))
	local sole = bootPart(model, "Sole", Vector3.new(s.X + 0.22, 0.14, s.Z + 0.3), SOLE_COLOR)
	weldTo(foot, sole, CFrame.new(0, bottom + 0.05, -0.06))

	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "Sparks"
	sparks.Enabled = false
	sparks.Rate = 10
	sparks.Lifetime = NumberRange.new(0.3, 0.6)
	sparks.Speed = NumberRange.new(0.5, 1.5)
	sparks.SpreadAngle = Vector2.new(60, 60)
	sparks.EmissionDirection = Enum.NormalId.Bottom
	sparks.Size = NumberSequence.new(0.18, 0)
	sparks.Transparency = NumberSequence.new(0.45, 1)
	sparks.Color = ColorSequence.new(SPARK_COLOR)
	sparks.LightEmission = 1
	sparks.Parent = sole

	-- Jet Boots: off until update() turns them on
	local flame = Instance.new("ParticleEmitter")
	flame.Name = "JetFlame"
	flame.Enabled = false
	flame.Rate = 45
	flame.Lifetime = NumberRange.new(0.12, 0.25)
	flame.Speed = NumberRange.new(5, 8)
	flame.SpreadAngle = Vector2.new(15, 15)
	flame.EmissionDirection = Enum.NormalId.Back
	flame.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	flame.Transparency = NumberSequence.new(0.15, 1)
	flame.Color = ColorSequence.new(JET_CORE, JET_COLOR)
	flame.LightEmission = 1
	flame.Parent = sole
	local top = Instance.new("Attachment")
	top.Name = "JetTrailTop"
	top.Position = Vector3.new(0, 0.5, 0.15)
	top.Parent = sole
	local base = Instance.new("Attachment")
	base.Name = "JetTrailBottom"
	base.Position = Vector3.new(0, 0, 0.15)
	base.Parent = sole
	local trail = Instance.new("Trail")
	trail.Name = "JetTrail"
	trail.Enabled = false
	trail.Attachment0 = top
	trail.Attachment1 = base
	trail.Lifetime = 0.35
	trail.MinLength = 0.05
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.Color = ColorSequence.new(JET_COLOR, JET_TAIL)
	trail.Transparency = NumberSequence.new(0.25, 1)
	trail.WidthScale = NumberSequence.new(1, 0.2)
	trail.Parent = sole
end

-- Replaces the character's boots with a pair for `tier`.
local function dress(character: Model, tier: number)
	local left = character:FindFirstChild("LeftFoot") or character:FindFirstChild("Left Leg")
	local right = character:FindFirstChild("RightFoot") or character:FindFirstChild("Right Leg")
	if not left or not right or not left:IsA("BasePart") or not right:IsA("BasePart") then
		return
	end
	local old = character:FindFirstChild(BOOTS_NAME)
	if old then
		old:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = BOOTS_NAME
	model:SetAttribute("Tier", tier)
	local color = TIER_COLORS[math.clamp(tier, 1, #TIER_COLORS)]
	local isR15 = left.Name == "LeftFoot"
	makeBoot(model, left, isR15, color)
	makeBoot(model, right, isR15, color)
	model.Parent = character
end

local function tierOf(player: Player): number
	local profile = PlayerData.get(player)
	return if profile then profile.bootTier else 1
end

local function attach(player: Player, character: Model)
	-- wait for the feet to load, then dress in whatever the player owns
	if not (character:WaitForChild("LeftFoot", 5) or character:FindFirstChild("Left Leg")) then
		return
	end
	dress(character, tierOf(player))
end

-- Keeps each pair matching the owned tier, the sparks on only while moving
-- inside a zone with better-than-starter boots, and the jets on only while
-- a Jet Boots owner moves between zones.
local function update(player: Player)
	local character = player.Character
	local model = character and character:FindFirstChild(BOOTS_NAME)
	if not character or not model then
		return
	end
	local tier = tierOf(player)
	if model:GetAttribute("Tier") ~= tier then
		dress(character, tier)
		model = character:FindFirstChild(BOOTS_NAME)
		if not model then
			return
		end
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	local moving = humanoid ~= nil
		and humanoid.Health > 0
		and humanoid.MoveDirection.Magnitude > 0.1
		and root ~= nil
		and root:IsA("BasePart")
	local inZone = moving and Zones.at((root :: BasePart).Position) ~= nil
	local sparking = tier > 1 and inZone
	local jetting = moving and not inZone and Passes.owns(player, "JetBoots")
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			local on = if descendant.Name == "JetFlame" then jetting else sparking
			if descendant.Enabled ~= on then
				descendant.Enabled = on
			end
		elseif descendant:IsA("Trail") and descendant.Enabled ~= jetting then
			descendant.Enabled = jetting
		end
	end
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		attach(player, character)
	end)
	if player.Character then
		task.spawn(attach, player, player.Character)
	end
end

function Boots.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	while true do
		for _, player in Players:GetPlayers() do
			update(player)
		end
		task.wait(0.25)
	end
end

return Boots
