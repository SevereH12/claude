--!strict
-- Walk speed: normal inside storm zones (catching should take skill, and
-- boots add a little), fast everywhere else so walking to the Power Plant
-- isn't a chore.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Formulas = require(ReplicatedStorage.Shared.Util.Formulas)
local Zones = require(ReplicatedStorage.Shared.Util.Zones)
local PlayerData = require(script.Parent.PlayerData)

local CHECK_INTERVAL = 0.2

local Movement = {}

local function update(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return
	end
	local profile = PlayerData.get(player)
	local speed =
		Formulas.walkSpeed(Zones.at(root.Position) ~= nil, if profile then profile.bootTier else 1)
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
