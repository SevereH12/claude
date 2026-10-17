--!strict
-- Terrain log: wraps ctx.terrain so every fill the style (and the Kit pieces
-- it calls) makes is recorded. The style can then ask "is this point inside
-- land?" without reading voxels back, which places waterfall lips past the
-- outermost lobe, moors tethers on the rim and checks chains are not buried.

local Terra = {}

type Op = {
	kind: string,
	cframe: CFrame,
	size: Vector3,
	radius: number,
	solid: boolean,
}

local ops: { Op } = {}

local function isSolid(material: Enum.Material): boolean
	return material ~= Enum.Material.Air and material ~= Enum.Material.Water
end

-- Replace ctx.terrain with a recording proxy. Call once at the start of a build.
function Terra.install(ctx: any)
	table.clear(ops)
	local real = ctx.terrain
	if type(real) == "table" and rawget(real, "__skyTerra") then
		real = rawget(real, "__skyTerra")
	end
	local proxy: { [string]: any } = {
		__skyTerra = real,
		FillBlock = function(_, cframe: CFrame, size: Vector3, material: Enum.Material)
			table.insert(ops, {
				kind = "Block",
				cframe = cframe,
				size = size,
				radius = 0,
				solid = isSolid(material),
			})
			real:FillBlock(cframe, size, material)
		end,
		FillWedge = function(_, cframe: CFrame, size: Vector3, material: Enum.Material)
			table.insert(ops, {
				kind = "Wedge",
				cframe = cframe,
				size = size,
				radius = 0,
				solid = isSolid(material),
			})
			real:FillWedge(cframe, size, material)
		end,
		FillCylinder = function(_, cframe: CFrame, height: number, radius: number, material: Enum.Material)
			table.insert(ops, {
				kind = "Cylinder",
				cframe = cframe,
				size = Vector3.new(radius * 2, height, radius * 2),
				radius = radius,
				solid = isSolid(material),
			})
			real:FillCylinder(cframe, height, radius, material)
		end,
		FillBall = function(_, center: Vector3, radius: number, material: Enum.Material)
			table.insert(ops, {
				kind = "Ball",
				cframe = CFrame.new(center),
				size = Vector3.one * radius * 2,
				radius = radius,
				solid = isSolid(material),
			})
			real:FillBall(center, radius, material)
		end,
		Clear = function(_)
			table.clear(ops)
			real:Clear()
		end,
	}
	setmetatable(proxy, {
		__index = function(_, key: string): any
			local value = real[key]
			if type(value) == "function" then
				return function(_, ...)
					return value(real, ...)
				end
			end
			return value
		end,
		__newindex = function(_, key: string, value: any)
			real[key] = value
		end,
	})
	ctx.terrain = proxy
end

local function inside(op: Op, p: Vector3, pad: number): boolean
	local l = op.cframe:PointToObjectSpace(p)
	local h = op.size / 2 + Vector3.one * pad
	if op.kind == "Ball" then
		return l.Magnitude <= op.radius + pad
	elseif op.kind == "Cylinder" then
		return math.abs(l.Y) <= h.Y and Vector2.new(l.X, l.Z).Magnitude <= op.radius + pad
	end
	if math.abs(l.X) > h.X or math.abs(l.Y) > h.Y or math.abs(l.Z) > h.Z then
		return false
	end
	if op.kind == "Wedge" then
		-- solid below the slope rising from the front-bottom to the back-top
		return (l.Y + h.Y) / (2 * h.Y) <= (l.Z + h.Z) / (2 * h.Z) + 0.05
	end
	return true
end

-- Is p inside land (later fills win)? `pad` grows every fill a little
-- (voxels round outward), default 2 studs.
function Terra.solidAt(p: Vector3, pad: number?): boolean
	local grow = pad or 2
	for i = #ops, 1, -1 do
		local op = ops[i]
		if inside(op, p, grow) then
			return op.solid
		end
	end
	return false
end

-- Is the whole column under p (to `depth` studs down) free of land?
function Terra.clearBelow(p: Vector3, depth: number, pad: number?): boolean
	local d = 0
	while d <= depth do
		if Terra.solidAt(p - Vector3.yAxis * d, pad) then
			return false
		end
		d += 3
	end
	return true
end

-- Point on a cubic Bezier.
function Terra.bezier(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local u = 1 - t
	return p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t)
end

-- How many of `samples` points along the curve are inside land.
function Terra.buried(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, samples: number): number
	local n = 0
	for i = 1, samples - 1 do
		if Terra.solidAt(Terra.bezier(p0, p1, p2, p3, i / samples), 0.5) then
			n += 1
		end
	end
	return n
end

return Terra
