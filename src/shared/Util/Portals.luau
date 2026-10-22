--!strict
-- Portals between worlds: invisible boxes tagged Portal with a ToWorld
-- attribute (World/Kit.portal builds them at each hub). Systems/Travel
-- sends you through; the client uses this to say why one won't. Also the
-- menu's Teleport panel's rule (Portals.teleportRefusal), which the server
-- checks and the panel shows (tools/harness/test_teleport.luau tests it).

local CollectionService = game:GetService("CollectionService")

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)
local Formulas = require(script.Parent.Formulas)
local Progression = require(script.Parent.Progression)
local Volumes = require(script.Parent.Volumes)

local Portals = {}

Portals.TAG = "Portal"
-- Player attribute with the id of the world you're in (the server sets it).
Portals.WORLD_ATTRIBUTE = "World"
-- Player attribute: workspace:GetServerTimeNow() when the Teleport panel can
-- take them again (the server sets it after each trip).
Portals.READY_ATTRIBUTE = "TeleportReadyAt"

-- The world with this id, or nil.
function Portals.world(id: unknown): Types.WorldDef?
	for _, world in Config.WORLDS do
		if world.id == id then
			return world
		end
	end
	return nil
end

-- Whole seconds until the Teleport panel can be used again (0 = now).
-- `readyAt` and `now` on one clock.
function Portals.cooldownLeft(now: number, readyAt: number): number
	return math.max(0, math.ceil(readyAt - now - 1e-6))
end

-- Why the Teleport panel can't take a player to `worldId` now (a message
-- for them), or nil and the world when it can: a real world, not the one
-- they're in (`here`), unlocked (the portals' rule, Progression), and off
-- the TELEPORT_COOLDOWN (`readyAt`, on the same clock as `now`).
function Portals.teleportRefusal(
	progress: Progression.Progress,
	worldId: unknown,
	here: string,
	now: number,
	readyAt: number
): (string?, Types.WorldDef?)
	local world = Portals.world(worldId)
	if not world then
		return "That world doesn't exist", nil
	end
	if world.id == here then
		return "You're already here", nil
	end
	local locked = Progression.worldLockReason(progress, world)
	if locked then
		return locked, nil
	end
	local wait = Portals.cooldownLeft(now, readyAt)
	if wait > 0 then
		return `Teleport ready in {wait}s`, nil
	end
	return nil, world
end

-- The world the portal at this position leads to, or nil.
function Portals.at(position: Vector3): Types.WorldDef?
	for _, instance in CollectionService:GetTagged(Portals.TAG) do
		if
			instance:IsA("BasePart")
			and instance:IsDescendantOf(workspace)
			and Volumes.contains(instance, position)
		then
			local to = instance:GetAttribute("ToWorld")
			for _, world in Config.WORLDS do
				if world.id == to then
					return world
				end
			end
		end
	end
	return nil
end

-- The world a player is in: the first one until the server says otherwise.
function Portals.worldOf(player: Player): Types.WorldDef
	local id = player:GetAttribute(Portals.WORLD_ATTRIBUTE)
	return Formulas.world(if typeof(id) == "string" then id else Config.WORLDS[1].id)
end

return Portals
