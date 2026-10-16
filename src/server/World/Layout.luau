--!strict
-- Where zones go. Zones sit on a spiral around the hub: each new zone is
-- further round and further out than the last, so adding a zone never
-- moves an existing one (Bee Swarm style: later fields are further away and
-- usually higher up). Pure math, no instances.

local WorldTypes = require(script.Parent.Types)

type LayoutParams = WorldTypes.LayoutParams
type Slot = WorldTypes.Slot

local MAX_CONNECTOR_SLOPE = math.rad(28) -- steeper than this is unpleasant to walk
local MIN_CONNECTOR_LENGTH = 8

local Layout = {}

-- Unit vector on the ground for an angle measured clockwise from north (-Z).
function Layout.direction(angle: number): Vector3
	return Vector3.new(math.sin(angle), 0, -math.cos(angle))
end

function Layout.slot(
	params: LayoutParams,
	index: number,
	width: number,
	depth: number,
	floor: number
): Slot
	local angle = math.rad(params.firstAngle + (index - 1) * params.angleStep)
	local radius = params.firstRadius + (index - 1) * params.radiusStep
	local direction = Layout.direction(angle)
	local center = direction * radius + Vector3.new(0, floor, 0)
	local frame = CFrame.lookAt(center, Vector3.new(0, floor, 0))
	local exitPoint = direction * params.hubRadius + Vector3.new(0, params.hubFloor, 0)
	return {
		index = index,
		angle = angle,
		width = width,
		depth = depth,
		floor = floor,
		frame = frame,
		gate = frame * CFrame.new(0, 0, -depth / 2),
		hubExit = CFrame.lookAt(exitPoint, exitPoint + direction),
	}
end

-- Corners of a slot's footprint on the ground plane (x, z), grown by margin.
local function corners(slot: Slot, margin: number): { Vector2 }
	local hw, hd = slot.width / 2 + margin, slot.depth / 2 + margin
	local out = {}
	for _, offset in { { -hw, -hd }, { hw, -hd }, { hw, hd }, { -hw, hd } } do
		local p = slot.frame:PointToWorldSpace(Vector3.new(offset[1], 0, offset[2]))
		table.insert(out, Vector2.new(p.X, p.Z))
	end
	return out
end

local function project(points: { Vector2 }, axis: Vector2): (number, number)
	local lo, hi = math.huge, -math.huge
	for _, p in points do
		local d = p:Dot(axis)
		lo = math.min(lo, d)
		hi = math.max(hi, d)
	end
	return lo, hi
end

-- Do two footprints (plus margin) overlap on the ground? Separating-axis test.
function Layout.overlaps(a: Slot, b: Slot, margin: number): boolean
	local ca, cb = corners(a, margin / 2), corners(b, margin / 2)
	for _, rect in { ca, cb } do
		for i = 1, 2 do
			local edge = rect[i + 1] - rect[i]
			local axis = Vector2.new(-edge.Y, edge.X).Unit
			local aLo, aHi = project(ca, axis)
			local bLo, bHi = project(cb, axis)
			if aHi < bLo or bHi < aLo then
				return false
			end
		end
	end
	return true
end

-- Length and slope of the connector from the hub rim to a slot's gate.
function Layout.connector(slot: Slot): (number, number)
	local from = slot.hubExit.Position
	local to = slot.gate.Position
	local run = Vector2.new(to.X - from.X, to.Z - from.Z).Magnitude
	local rise = math.abs(to.Y - from.Y)
	return run, math.atan2(rise, math.max(run, 0.001))
end

-- Ground distance from the hub centre to the nearest point of a footprint.
function Layout.distanceFromHub(slot: Slot): number
	local hub = slot.frame:PointToObjectSpace(Vector3.new(0, slot.floor, 0))
	local dx = math.max(math.abs(hub.X) - slot.width / 2, 0)
	local dz = math.max(math.abs(hub.Z) - slot.depth / 2, 0)
	return math.sqrt(dx * dx + dz * dz)
end

-- All slots for the given zone footprints plus one teaser slot after them.
-- Errors with a clear message if the layout parameters make anything
-- overlap the hub or each other, or make a connector unwalkable.
function Layout.plan(
	params: LayoutParams,
	footprints: { { width: number, depth: number, floor: number } }
): ({ Slot }, Slot)
	local slots: { Slot } = {}
	local lastFloor = params.hubFloor
	for index, footprint in footprints do
		table.insert(
			slots,
			Layout.slot(params, index, footprint.width, footprint.depth, footprint.floor)
		)
		lastFloor = footprint.floor
	end
	local teaser = Layout.slot(
		params,
		#footprints + 1,
		params.teaserWidth,
		params.teaserDepth,
		lastFloor + params.teaserFloorStep
	)

	local all = table.clone(slots)
	table.insert(all, teaser)
	for i, slot in all do
		local run, slope = Layout.connector(slot)
		local label = if slot == teaser then "teaser slot" else `zone slot {i}`
		if Layout.distanceFromHub(slot) < params.hubRadius + 4 then
			error(`[Layout] {label} cuts into the hub; raise firstRadius or shrink the zone`, 0)
		end
		if run < MIN_CONNECTOR_LENGTH then
			error(
				`[Layout] {label} is too close to the hub (connector {math.floor(run)} studs); raise firstRadius`,
				0
			)
		end
		if slope > MAX_CONNECTOR_SLOPE then
			error(
				`[Layout] {label}: connector climbs {math.floor(math.deg(slope))} degrees; raise radiusStep/firstRadius or lower the floor step`,
				0
			)
		end
		for j = i + 1, #all do
			if Layout.overlaps(slot, all[j], 12) then
				error(`[Layout] slots {i} and {j} overlap; increase angleStep or radiusStep`, 0)
			end
		end
	end
	return slots, teaser
end

return Layout
