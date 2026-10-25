--!strict
-- Walk speed: normal inside storm zones (catching should take skill, and
-- boots add a little), fast everywhere else so walking to the Power Plant
-- isn't a chore. Also the server's zone lock: anyone standing in a zone
-- they haven't unlocked is put back just outside its gate. It also marks
-- the zones and worlds a player has been in (the Storm Log).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Formulas = require(ReplicatedStorage.Shared.Util.Formulas)
local Portals = require(ReplicatedStorage.Shared.Util.Portals)
local Progression = require(ReplicatedStorage.Shared.Util.Progression)
local StatRules = require(ReplicatedStorage.Shared.Util.Stats)
local Zones = require(ReplicatedStorage.Shared.Util.Zones)
local Analytics = require(script.Parent.Analytics)
local Passes = require(script.Parent.Passes)
local PlayerData = require(script.Parent.PlayerData)
local Stats = require(script.Parent.Stats)

local CHECK_INTERVAL = 0.2
local GATE_STEP_OUT = 6 -- studs outside a locked zone's gate to put players

local Movement = {}

local function update(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return
	end
	local profile = PlayerData.get(player)
	local zone = Zones.at(root.Position)
	if
		zone
		and profile
		and not Progression.canEnter(profile, zone, Progression.playerIsPremium(player))
	then
		local part = Zones.part(zone.id)
		if part then
			-- the zone part faces the hub (-Z); its gate is the middle of that
			-- edge at floor height (1 above the part's base)
			local outside = part.CFrame
				* CFrame.new(0, 1 - part.Size.Y / 2, -part.Size.Z / 2 - GATE_STEP_OUT)
			local position = outside.Position + Vector3.new(0, 3.5, 0)
			local body = character :: Model
			body:PivotTo(CFrame.lookAt(position, position + part.CFrame.LookVector))
		end
		zone = nil
	end
	Analytics.inZone(player, zone)
	-- the Storm Log's Places page: zones and worlds visited
	if zone then
		Stats.visited(player, StatRules.visitZoneKey(zone.id))
	end
	local worldId = player:GetAttribute(Portals.WORLD_ATTRIBUTE)
	if typeof(worldId) == "string" then
		Stats.visited(player, StatRules.visitWorldKey(worldId))
	end
	local speed = Formulas.walkSpeed(
		zone ~= nil,
		if profile then profile.bootTier else 1,
		Passes.owned(player) -- Jet Boots: faster between zones
	)
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
