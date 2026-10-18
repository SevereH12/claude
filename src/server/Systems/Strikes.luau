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
local Zones = require(ReplicatedStorage.Shared.Util.Zones)
local Research = require(script.Parent.Research)
local ResearchMath = require(ReplicatedStorage.Shared.Util.Research)
local PlayerData = require(script.Parent.PlayerData)
local StormCycle = require(script.Parent.StormCycle)
local Sync = require(script.Parent.Sync)

-- HumanoidRootPart sits about this far above the ground the player stands on
local ROOT_HEIGHT = 3

local random = Random.new()
local nextStrikeId = 0

local warningRemote: RemoteEvent
local landedRemote: RemoteEvent
local forecastRemote: RemoteEvent

local Strikes = {}

-- Random point on the ground inside the zone, kept far enough from the
-- border that the whole circle fits inside it.
local function randomGroundPoint(zonePart: BasePart): Vector3?
	local inset = Config.STRIKE_RADIUS + 2
	local halfX = math.max(zonePart.Size.X / 2 - inset, 0)
	local halfZ = math.max(zonePart.Size.Z / 2 - inset, 0)
	local offset = Vector3.new(
		random:NextNumber(-halfX, halfX),
		zonePart.Size.Y / 2,
		random:NextNumber(-halfZ, halfZ)
	)
	local top = zonePart.CFrame:PointToWorldSpace(offset)

	-- the ground is Map.Ground parts or terrain; ignore everything else
	-- (posts, walls, trees, players)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local map = workspace:FindFirstChild("Map")
	local ground = map and map:FindFirstChild("Ground")
	params.FilterDescendantsInstances = if ground
		then { workspace.Terrain, ground }
		else { workspace.Terrain }
	local result = workspace:Raycast(top, Vector3.new(0, -zonePart.Size.Y - 10, 0), params)
	if not result or not Zones.contains(zonePart, result.Position + Vector3.new(0, 1, 0)) then
		return nil
	end
	return result.Position
end

-- The player's root part if they can catch right now (alive). The bottle
-- is always in their hand, so there's nothing to equip.
local function catchingRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Horizontal distance to the strike, or nil if the player isn't inside their
-- own catch radius (bigger with Rod Tech).
local function distanceInside(root: BasePart, position: Vector3, radius: number): number?
	local heightAboveGround = root.Position.Y - ROOT_HEIGHT - position.Y
	if heightAboveGround < -3 or heightAboveGround > Config.STRIKE_MAX_HEIGHT_ABOVE then
		return nil
	end
	local flat = Vector3.new(root.Position.X - position.X, 0, root.Position.Z - position.Z)
	local distance = flat.Magnitude
	return if distance <= radius then distance else nil
end

local function resolve(zone: Types.ZoneDef, id: number, position: Vector3)
	local catchers: { number } = {}
	local full: { number } = {}
	local assayed: { number } = {}

	-- everyone inside with room in their bottle, closest first
	local candidates: { { player: Player, profile: Types.Profile, distance: number } } = {}
	for _, player in Players:GetPlayers() do
		local root = catchingRoot(player)
		local profile = PlayerData.get(player)
		local radius = ResearchMath.catchRadius(Research.active(player, "RodTech"))
		local distance = if root then distanceInside(root, position, radius) else nil
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
		local value = zone.chargeValue
		local assayLevel = Research.active(candidate.player, "Analyst")
		if assayLevel and random:NextNumber() < ResearchMath.assayChance(assayLevel) then
			value *= 2
			table.insert(assayed, candidate.player.UserId)
		end
		candidate.profile.chargeValue += value
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
		assayed = assayed,
	}
	landedRemote:FireAllClients(landed)
	Research.onStrikeLanded(zone.id, catchers)
end

local function publicWarning(zone: Types.ZoneDef, id: number, position: Vector3)
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

-- The position is picked now. The public warning goes out FORECAST_MAX_LEAD
-- later, and each Forecaster owner hears about it `lead` seconds before that.
local function spawnStrike(zone: Types.ZoneDef, zonePart: BasePart)
	local position = randomGroundPoint(zonePart)
	if not position then
		return
	end
	nextStrikeId += 1
	local id = nextStrikeId

	local warnsAt = workspace:GetServerTimeNow() + Config.FORECAST_MAX_LEAD
	local forecast: Types.Forecast = {
		id = id,
		zoneId = zone.id,
		position = position,
		radius = Config.STRIKE_RADIUS,
		warnsAt = warnsAt,
	}
	for _, player in Players:GetPlayers() do
		local level = Research.active(player, "Forecaster")
		local profile = PlayerData.get(player)
		local save = if profile then profile.researchers.Forecaster else nil
		if level and save and save.post == zone.id then
			local lead = ResearchMath.forecastLead(level)
			task.delay(Config.FORECAST_MAX_LEAD - lead, function()
				if player.Parent then
					forecastRemote:FireClient(player, forecast)
				end
			end)
		end
	end
	task.delay(Config.FORECAST_MAX_LEAD, publicWarning, zone, id, position)
end

local function runZone(zone: Types.ZoneDef)
	local zonePart = Zones.part(zone.id)
	if not zonePart then
		warn(`[Strikes] no Workspace.Map.Zones.{zone.id} part; zone disabled`)
		return
	end
	while true do
		if StormCycle.isStorming() then
			spawnStrike(zone, zonePart)
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
	forecastRemote = Net.get("Forecast")
end

function Strikes.start()
	for _, zone in Formulas.sortedZones() do
		task.spawn(runZone, zone)
	end
end

return Strikes
