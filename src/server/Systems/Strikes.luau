--!strict
-- Spawns lightning strikes during storms and decides who catches them.
--
-- For each strike: pick a random spot in the zone, warn every client (they
-- draw the circle), wait WARNING_TIME, then check every player's position
-- on the server. Clients never say "I caught it"; nothing to fake.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Util.Formulas)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local Map = require(script.Parent.Map)
local PlayerData = require(script.Parent.PlayerData)
local StormCycle = require(script.Parent.StormCycle)
local Sync = require(script.Parent.Sync)

-- HumanoidRootPart sits about this far above the ground the player stands on
local ROOT_HEIGHT = 3

local random = Random.new()
local nextStrikeId = 0

local warningRemote: RemoteEvent
local landedRemote: RemoteEvent

local Strikes = {}

-- Random point on the ground inside the zone's box.
local function randomGroundPoint(area: BasePart): Vector3?
	local offset = Vector3.new(
		(random:NextNumber() - 0.5) * area.Size.X,
		0,
		(random:NextNumber() - 0.5) * area.Size.Z
	)
	local top = area.CFrame:PointToWorldSpace(offset) + Vector3.new(0, 60, 0)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace:FindFirstChild("Map") :: Instance }
	local result = workspace:Raycast(top, Vector3.new(0, -200, 0), params)
	return if result then result.Position else nil
end

-- The player's root part if they can catch right now: alive, holding the bottle.
local function catchingRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	-- an equipped Tool is parented to the character
	local bottle = character:FindFirstChild("Bottle")
	if not bottle or not bottle:IsA("Tool") then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Horizontal distance to the strike, or nil if the player isn't inside it.
local function distanceInside(root: BasePart, position: Vector3): number?
	local heightAboveGround = root.Position.Y - ROOT_HEIGHT - position.Y
	if heightAboveGround < -3 or heightAboveGround > Config.STRIKE_MAX_HEIGHT_ABOVE then
		return nil
	end
	local flat = Vector3.new(root.Position.X - position.X, 0, root.Position.Z - position.Z)
	local distance = flat.Magnitude
	return if distance <= Config.STRIKE_RADIUS then distance else nil
end

local function resolve(zone: Types.ZoneDef, id: number, position: Vector3)
	local catchers: { number } = {}
	local full: { number } = {}

	-- everyone inside with room in their bottle, closest first
	local candidates: { { player: Player, profile: Types.Profile, distance: number } } = {}
	for _, player in Players:GetPlayers() do
		local root = catchingRoot(player)
		local profile = PlayerData.get(player)
		local distance = if root then distanceInside(root, position) else nil
		if profile and distance then
			if Formulas.isFull(profile) then
				table.insert(full, player.UserId)
			else
				table.insert(
					candidates,
					{ player = player, profile = profile, distance = distance }
				)
			end
		end
	end
	table.sort(candidates, function(a, b)
		return a.distance < b.distance
	end)

	for index, candidate in candidates do
		if zone.mode == "Single" and index > 1 then
			break
		end
		candidate.profile.chargeCount += 1
		candidate.profile.chargeValue += zone.chargeValue
		table.insert(catchers, candidate.player.UserId)
		Sync.markDirty(candidate.player)
	end

	local landed: Types.StrikeLanded = {
		id = id,
		zoneId = zone.id,
		position = position,
		value = zone.chargeValue,
		catchers = catchers,
		full = full,
	}
	landedRemote:FireAllClients(landed)
end

local function spawnStrike(zone: Types.ZoneDef, area: BasePart)
	local position = randomGroundPoint(area)
	if not position then
		return
	end
	nextStrikeId += 1
	local id = nextStrikeId

	local warning: Types.StrikeWarning = {
		id = id,
		zoneId = zone.id,
		position = position,
		radius = Config.STRIKE_RADIUS,
		landsAt = workspace:GetServerTimeNow() + Config.WARNING_TIME,
	}
	warningRemote:FireAllClients(warning)
	task.delay(Config.WARNING_TIME, resolve, zone, id, position)
end

local function runZone(zone: Types.ZoneDef)
	local area = Map.zoneArea(zone.id)
	if not area then
		warn(`[Strikes] no Workspace.Map.Zones.{zone.id} part; zone disabled`)
		return
	end
	while true do
		if StormCycle.isStorming() then
			spawnStrike(zone, area)
			local jitter = 1 + (random:NextNumber() * 2 - 1) * Config.STRIKE_INTERVAL_JITTER
			task.wait(zone.strikeInterval * jitter)
		else
			task.wait(0.5)
		end
	end
end

function Strikes.init()
	warningRemote = Net.get("StrikeWarning")
	landedRemote = Net.get("StrikeLanded")
end

function Strikes.start()
	for _, zone in Formulas.sortedZones() do
		task.spawn(runZone, zone)
	end
end

return Strikes
