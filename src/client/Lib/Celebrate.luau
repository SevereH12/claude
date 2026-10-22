--!strict
-- A short celebration on your own character: gold sparks bursting off you
-- (a purchase, a claimed reward). Only you see it.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Celebrate = {}

function Celebrate.sparks()
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Parent = root
	local sparks = Instance.new("ParticleEmitter")
	sparks.Rate = 0
	sparks.Lifetime = NumberRange.new(0.6, 1.1)
	sparks.Speed = NumberRange.new(12, 20)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Acceleration = Vector3.new(0, -20, 0)
	sparks.Size = NumberSequence.new(0.45, 0)
	sparks.Color = ColorSequence.new(Config.VIP_GOLD, Color3.new(1, 1, 1))
	sparks.LightEmission = 1
	sparks.Parent = attachment
	sparks:Emit(60)
	Debris:AddItem(attachment, 2)
end

return Celebrate
