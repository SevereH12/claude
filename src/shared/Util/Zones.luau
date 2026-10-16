--!strict
-- Zone geometry shared by server and client. Each zone is an invisible box
-- at Workspace.Map.Zones.<ZoneId> covering the whole zone volume (the
-- bordered area, from its floor up into the sky).

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)

local Zones = {}

function Zones.part(zoneId: string): BasePart?
	local map = workspace:FindFirstChild("Map")
	local container = map and map:FindFirstChild("Zones")
	local part = container and container:FindFirstChild(zoneId)
	return if part and part:IsA("BasePart") then part else nil
end

function Zones.contains(part: BasePart, position: Vector3): boolean
	local localPos = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	return math.abs(localPos.X) <= half.X
		and math.abs(localPos.Y) <= half.Y
		and math.abs(localPos.Z) <= half.Z
end

-- The zone a position is in, or nil when it's outside every zone.
function Zones.at(position: Vector3): Types.ZoneDef?
	for id, def in Config.ZONES do
		local part = Zones.part(id)
		if part and Zones.contains(part, position) then
			return def
		end
	end
	return nil
end

return Zones
