--!strict
-- Walk speed: normal inside storm zones (catching should take skill), fast
-- everywhere else so walking to the Power Plant isn't a chore.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Zones = require(ReplicatedStorage.Shared.Util.Zones)

local CHECK_INTERVAL = 0.2

local Movement = {}

local function update(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return
	end
	local speed = if Zones.at(root.Position)
		then Config.WALK_SPEED_IN_ZONE
		else Config.WALK_SPEED_OUTSIDE
	if humanoid.WalkSpeed ~= speed then
		humanoid.WalkSpeed = speed
	end
end

function Movement.start()
	while true do
		for _, player in Players:GetPlayers() do
			update(player)
		end
		task.wait(CHECK_INTERVAL)
	end
end

return Movement
