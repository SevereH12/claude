--!strict
-- Travel between worlds (Config.WORLDS). Every hub has portals (Kit.portal:
-- boxes tagged Portal, attribute ToWorld). Walking into one sends you to
-- that world's spawn if you own its bottle. Like selling, it's a position
-- check here on the server, never Touched; the client only explains a
-- locked portal (Controllers/Travel). The world you're in is the player
-- attribute World, and you respawn there. It isn't saved: every visit
-- starts in the first world.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Portals = require(ReplicatedStorage.Shared.Util.Portals)
local Progression = require(ReplicatedStorage.Shared.Util.Progression)
local PlayerData = require(script.Parent.PlayerData)

local CHECK_INTERVAL = 0.1 -- portal boxes are 6 deep: no one runs through between checks
local COOLDOWN = 2 -- seconds after a trip before a portal takes you again
local ROOT_ABOVE = 3 -- a standing character's root is this far above the ground

local lastTrip: { [Player]: number } = {}
local spawns: { [string]: SpawnLocation } = {}

local Travel = {}

-- A world's spawn (the Builder gives each one a World attribute).
local function spawnOf(worldId: string): SpawnLocation?
	local cached = spawns[worldId]
	if cached and cached:IsDescendantOf(workspace) then
		return cached
	end
	local map = workspace:FindFirstChild("Map")
	if map then
		for _, descendant in map:GetDescendants() do
			if descendant:IsA("SpawnLocation") and descendant:GetAttribute("World") == worldId then
				spawns[worldId] = descendant
				return descendant
			end
		end
	end
	return nil
end

-- Puts the player on that world's spawn, facing the way it faces.
local function sendTo(player: Player, worldId: string)
	local spawnLocation = spawnOf(worldId)
	if not spawnLocation then
		return
	end
	local arrival = spawnLocation.CFrame * CFrame.new(0, spawnLocation.Size.Y / 2 + ROOT_ABOVE, 0)
	lastTrip[player] = os.clock()
	player:SetAttribute(Portals.WORLD_ATTRIBUTE, worldId)
	-- with streaming on, load the far world before arriving (yields)
	pcall(player.RequestStreamAroundAsync, player, arrival.Position)
	local character = player.Character
	if character then
		character:PivotTo(arrival)
	end
end

local function check(player: Player)
	if os.clock() - (lastTrip[player] or -math.huge) < COOLDOWN then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local world = Portals.at(root.Position)
	local profile = PlayerData.get(player)
	if world and profile and Progression.canEnterWorld(profile, world) then
		lastTrip[player] = os.clock()
		task.spawn(sendTo, player, world.id)
	end
end

local function onPlayerAdded(player: Player)
	player:SetAttribute(Portals.WORLD_ATTRIBUTE, Config.WORLDS[1].id)
	-- respawn in the world you were in, not back at the first one
	player.CharacterAdded:Connect(function(character)
		local world = Portals.worldOf(player)
		if world.id ~= Config.WORLDS[1].id and character:WaitForChild("HumanoidRootPart", 10) then
			sendTo(player, world.id)
		end
	end)
end

function Travel.init()
	Players.PlayerRemoving:Connect(function(player)
		lastTrip[player] = nil
	end)
end

function Travel.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	while true do
		task.wait(CHECK_INTERVAL)
		for _, player in Players:GetPlayers() do
			check(player)
		end
	end
end

return Travel
