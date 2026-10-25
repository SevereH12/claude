--!strict
-- Travel between worlds (Config.WORLDS). Every hub has portals (Kit.portal:
-- boxes tagged Portal, attribute ToWorld). Walking into one sends you to
-- that world's spawn if you own its bottle. Like selling, it's a position
-- check here on the server, never Touched; the client only explains a
-- locked portal (Controllers/Travel). The world you're in is the player
-- attribute World, and you respawn there. It isn't saved: every visit
-- starts in the first world. The menu's Teleport panel asks to go to
-- another world's hub (remote Teleport): the same unlock rule, while alive,
-- and at most once every Config.TELEPORT_COOLDOWN seconds (the rule:
-- Portals.teleportRefusal; the player attribute TeleportReadyAt tells the
-- panel when it can go again), checked here. The panel's AFK Lounge entry
-- (Portals.AFK_LOUNGE) goes to the lounge in the first world on the same
-- cooldown (Portals.loungeRefusal; Systems/Afk.sendToLounge).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Portals = require(ReplicatedStorage.Shared.Util.Portals)
local Progression = require(ReplicatedStorage.Shared.Util.Progression)
local Afk = require(script.Parent.Afk)
local PlayerData = require(script.Parent.PlayerData)
local RateLimit = require(ServerScriptService.Server.Lib.RateLimit)

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

-- Teleport panel: go to the hub (spawn) of another world you can enter.
local function onTeleport(player: Player, worldId: unknown)
	if not RateLimit.allow(player, "Teleport", 1, 3) then
		return
	end
	local profile = PlayerData.get(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not profile or not humanoid or humanoid.Health <= 0 then
		return
	end
	local now = workspace:GetServerTimeNow()
	local readyAt = player:GetAttribute(Portals.READY_ATTRIBUTE)
	if worldId == Portals.AFK_LOUNGE then
		local root = character:FindFirstChild("HumanoidRootPart")
		local inLounge = root ~= nil and root:IsA("BasePart") and Afk.isInLounge(root.Position)
		if
			Portals.loungeRefusal(inLounge, now, if typeof(readyAt) == "number" then readyAt else 0)
		then
			return
		end
		player:SetAttribute(Portals.READY_ATTRIBUTE, now + Config.TELEPORT_COOLDOWN)
		lastTrip[player] = os.clock()
		task.spawn(Afk.sendToLounge, player)
		return
	end
	local refusal, world = Portals.teleportRefusal(
		profile,
		worldId,
		Portals.worldOf(player).id,
		now,
		if typeof(readyAt) == "number" then readyAt else 0
	)
	if refusal or not world then
		return
	end
	player:SetAttribute(Portals.READY_ATTRIBUTE, now + Config.TELEPORT_COOLDOWN)
	lastTrip[player] = os.clock()
	task.spawn(sendTo, player, world.id)
end

-- Sends the player to the first world's spawn (Barometer Bay), the start
-- of the game: Systems/Ascension calls it after an Ascension. Yields while
-- the world streams in, so call it in its own thread.
function Travel.sendHome(player: Player)
	sendTo(player, Config.WORLDS[1].id)
end

function Travel.init()
	Players.PlayerRemoving:Connect(function(player)
		lastTrip[player] = nil
	end)
	Net.get("Teleport").OnServerEvent:Connect(onTeleport)
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
