--!strict
-- Box-volume math shared by zones and sell areas: "is this point inside
-- this (possibly rotated) part's box?"

local Volumes = {}

function Volumes.contains(part: BasePart, position: Vector3): boolean
	local localPos = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	return math.abs(localPos.X) <= half.X
		and math.abs(localPos.Y) <= half.Y
		and math.abs(localPos.Z) <= half.Z
end

-- The column of space above a pad: within the pad's footprint (plus a
-- margin) and from just below its top surface up to `height` studs above.
function Volumes.aboveTop(pad: BasePart, position: Vector3, height: number, margin: number): boolean
	local localPos = pad.CFrame:PointToObjectSpace(position)
	local half = pad.Size / 2
	return math.abs(localPos.X) <= half.X + margin
		and math.abs(localPos.Z) <= half.Z + margin
		and localPos.Y >= half.Y - 1
		and localPos.Y <= half.Y + height
end

return Volumes
