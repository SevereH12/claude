--!strict
-- Players walk through each other: nobody can push another player off a
-- strike ring or out of a zone. Every part of every character goes in the
-- "Players" collision group, which doesn't collide with itself (it still
-- collides with the map).

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")

local GROUP = "Players"

local Collisions = {}

local function join(part: Instance)
	if part:IsA("BasePart") then
		part.CollisionGroup = GROUP
	end
end

local function onCharacter(character: Model)
	for _, part in character:GetDescendants() do
		join(part)
	end
	character.DescendantAdded:Connect(join)
end

local function onPlayer(player: Player)
	if player.Character then
		onCharacter(player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
end

function Collisions.init()
	PhysicsService:RegisterCollisionGroup(GROUP)
	PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, false)
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

return Collisions
