--!strict
-- Every character carries a bottle in their right hand, always. No tool to
-- equip. The bottle glows brighter as it fills (set here on the server, so
-- everyone can see how full everyone else's bottle is). VIP glass is gold;
-- the charge glows in the player's bolt colour (Bolt Colours pick, else VIP
-- gold, else the default blue that turns gold when full).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PassRules = require(ReplicatedStorage.Shared.Util.Passes)
local Passes = require(script.Parent.Passes)
local PlayerData = require(script.Parent.PlayerData)

local BOTTLE_NAME = "Bottle"
local EMPTY_COLOR = Color3.fromRGB(110, 185, 255)
local FULL_COLOR = Color3.fromRGB(255, 210, 70)
local GLASS_COLOR = Color3.fromRGB(190, 230, 255)
local VIP_GLASS_COLOR = Color3.fromRGB(255, 214, 110)

local Bottles = {}

local function bottlePart(name: string, props: { [string]: any }): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Cylinder
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	for key, value in props do
		(part :: any)[key] = value
	end
	return part
end

-- Built around the origin standing upright (cylinders run along X, so each
-- one is rotated onto its side... and then up).
local function makeBottle(): Model
	local upright = CFrame.Angles(0, 0, math.rad(90))
	local model = Instance.new("Model")
	model.Name = BOTTLE_NAME

	local body = bottlePart("Body", {
		Size = Vector3.new(1.5, 1, 1),
		CFrame = upright,
		Material = Enum.Material.Glass,
		Transparency = 0.35,
		Color = GLASS_COLOR,
	})
	body.Parent = model

	local charge = bottlePart("Charge", {
		Size = Vector3.new(1.3, 0.8, 0.8),
		CFrame = upright,
		Material = Enum.Material.Neon,
		Transparency = 1,
		Color = EMPTY_COLOR,
	})
	charge.Parent = model

	local neck = bottlePart("Neck", {
		Size = Vector3.new(0.5, 0.5, 0.5),
		CFrame = CFrame.new(0, 1, 0) * upright,
		Material = Enum.Material.Glass,
		Transparency = 0.35,
		Color = GLASS_COLOR,
	})
	neck.Parent = model

	local cork = bottlePart("Cork", {
		Size = Vector3.new(0.3, 0.55, 0.55),
		CFrame = CFrame.new(0, 1.35, 0) * upright,
		Material = Enum.Material.Wood,
		Color = Color3.fromRGB(150, 105, 65),
	})
	cork.Parent = model

	for _, piece in { charge, neck, cork } do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = body
		weld.Part1 = piece
		weld.Parent = piece
	end

	local glow = Instance.new("PointLight")
	glow.Name = "Glow"
	glow.Color = EMPTY_COLOR
	glow.Range = 8
	glow.Brightness = 0
	glow.Parent = charge

	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "FullSparkles"
	sparkles.Enabled = false
	sparkles.Rate = 8
	sparkles.Lifetime = NumberRange.new(0.4, 0.8)
	sparkles.Speed = NumberRange.new(1, 2)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Size = NumberSequence.new(0.25, 0)
	sparkles.Color = ColorSequence.new(FULL_COLOR)
	sparkles.LightEmission = 1
	sparkles.Parent = charge

	model.PrimaryPart = body
	return model
end

local function attach(character: Model)
	local hand = character:WaitForChild("RightHand", 5) or character:FindFirstChild("Right Arm")
	if not hand or not hand:IsA("BasePart") or character:FindFirstChild(BOTTLE_NAME) then
		return
	end
	local bottle = makeBottle()
	local body = bottle.PrimaryPart :: BasePart

	-- hold it by the neck: neck at the grip point, body hanging below the hand
	local grip = hand:FindFirstChild("RightGripAttachment")
	local gripPosition = if grip and grip:IsA("Attachment")
		then grip.Position
		else Vector3.new(0, -hand.Size.Y / 2, 0)
	local weld = Instance.new("Weld")
	weld.Part0 = hand
	weld.Part1 = body
	weld.C0 = CFrame.new(gripPosition - Vector3.new(0, 0.9, 0)) * CFrame.Angles(0, 0, math.rad(90))
	weld.Parent = body

	bottle.Parent = character
end

-- Glow to match how full the bottle is, in the player's colours.
local function updateFill(player: Player)
	local character = player.Character
	local profile = PlayerData.get(player)
	local bottle = character and character:FindFirstChild(BOTTLE_NAME)
	local charge = bottle and bottle:FindFirstChild("Charge")
	if not bottle or not profile or not charge or not charge:IsA("BasePart") then
		return
	end
	local owned = Passes.owned(player)
	local bolt = PassRules.boltColour(owned, profile.boltColour)
	local fraction = math.clamp(profile.chargeCount / Passes.capacity(player, profile), 0, 1)
	local full = fraction >= 1
	local transparency = if fraction > 0 then 0.75 - fraction * 0.6 else 1
	-- what the bottle should look like; skip the work when it already does
	local look = `{math.floor(transparency * 100 + 0.5)}|{full}|{bolt}|{owned.VIP == true}`
	if bottle:GetAttribute("Look") == look then
		return
	end
	bottle:SetAttribute("Look", look)

	-- full: the default blue turns gold; a bolt colour turns bright
	local color = if bolt
		then (if full then bolt:Lerp(Color3.new(1, 1, 1), 0.45) else bolt)
		elseif full then FULL_COLOR
		else EMPTY_COLOR
	charge.Transparency = transparency
	charge.Color = color
	local glow = charge:FindFirstChild("Glow")
	if glow and glow:IsA("PointLight") then
		glow.Brightness = fraction * 3
		glow.Color = color
	end
	local sparkles = charge:FindFirstChild("FullSparkles")
	if sparkles and sparkles:IsA("ParticleEmitter") then
		sparkles.Enabled = full
		sparkles.Color = ColorSequence.new(color)
	end
	-- VIP: golden glass
	local glass = if owned.VIP then VIP_GLASS_COLOR else GLASS_COLOR
	for _, name in { "Body", "Neck" } do
		local part = bottle:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			part.Color = glass
		end
	end
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(attach)
	if player.Character then
		task.spawn(attach, player.Character)
	end
end

function Bottles.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	while true do
		for _, player in Players:GetPlayers() do
			updateFill(player)
		end
		task.wait(0.25)
	end
end

return Bottles
