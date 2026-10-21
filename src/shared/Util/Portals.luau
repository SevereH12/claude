--!strict
-- Portals between worlds: invisible boxes tagged Portal with a ToWorld
-- attribute (World/Kit.portal builds them at each hub). Systems/Travel
-- sends you through; the client uses this to say why one won't.

local CollectionService = game:GetService("CollectionService")

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)
local Formulas = require(script.Parent.Formulas)
local Volumes = require(script.Parent.Volumes)

local Portals = {}

Portals.TAG = "Portal"
-- Player attribute with the id of the world you're in (the server sets it).
Portals.WORLD_ATTRIBUTE = "World"

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
