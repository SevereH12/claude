--!strict
-- Where Researchers work. Each zone has a Research Camp, an invisible box at
-- Workspace.Map.ResearchCamps.<ZoneId>; the hub has one or more Research
-- Offices, invisible boxes tagged "ResearchOffice". Same box test as
-- zones and sell areas (Util/Volumes). This is the only code that finds them.

local CollectionService = game:GetService("CollectionService")

local Volumes = require(script.Parent.Volumes)

local OFFICE_TAG = "ResearchOffice"

local ResearchSites = {}

function ResearchSites.camp(zoneId: string): BasePart?
	local map = workspace:FindFirstChild("Map")
	local container = map and map:FindFirstChild("ResearchCamps")
	local part = container and container:FindFirstChild(zoneId)
	return if part and part:IsA("BasePart") then part else nil
end

function ResearchSites.offices(): { BasePart }
	local offices: { BasePart } = {}
	for _, instance in CollectionService:GetTagged(OFFICE_TAG) do
		if instance:IsA("BasePart") and instance:IsDescendantOf(workspace) then
			table.insert(offices, instance)
		end
	end
	return offices
end

function ResearchSites.inOffice(position: Vector3): boolean
	for _, office in ResearchSites.offices() do
		if Volumes.contains(office, position) then
			return true
		end
	end
	return false
end

-- The zone id whose camp contains a position, or nil.
function ResearchSites.campAt(position: Vector3): string?
	local map = workspace:FindFirstChild("Map")
	local container = map and map:FindFirstChild("ResearchCamps")
	if not container then
		return nil
	end
	for _, part in container:GetChildren() do
		if part:IsA("BasePart") and Volumes.contains(part, position) then
			return part.Name
		end
	end
	return nil
end

return ResearchSites
