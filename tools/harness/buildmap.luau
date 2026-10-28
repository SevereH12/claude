--!nocheck
-- Builds the map with the real MapBuilder in a stand-in world and writes
-- every part + terrain fill to a JSON file for checks and rendering.
--   lune run tools/harness/buildmap.luau [outfile] [style]
-- style "Game" (or none) builds every world in Config.WORLDS; a style name
-- builds only the first world's zones in that style (a preview). Each world
-- gets its own file, since worlds sit thousands of studs apart: the first
-- world's is `outfile`, world N's is `outfile` with _<WorldId> before .json.
-- Exits non-zero if the build errors or required map pieces are missing.

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local World = require("./World")

local outPath = process.args[1] or "map.json"
local styleName = process.args[2] -- nil or "Game" = every world
if styleName == "Game" then
	styleName = nil
end
local world = World.new("src")

local MapBuilder = world:require("ServerScriptService.Server.Lib.MapBuilder")
local ok, err = pcall(MapBuilder.build, styleName)
if not ok then
	print("BUILD FAILED: " .. tostring(err))
	process.exit(1)
end

world:normalizeParts()
local workspace = world.workspace
local map = workspace:FindFirstChild("Map")
local problems = {}
local function need(condition, message)
	if not condition then
		table.insert(problems, message)
	end
end

need(map ~= nil, "Workspace.Map missing")

local function vec(v)
	return { v.X, v.Y, v.Z }
end

local function cf(c)
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = c:GetComponents()
	return { x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 }
end

local parts = {}
local counts = {}
for _, inst in workspace:GetDescendants() do
	counts[inst.ClassName] = (counts[inst.ClassName] or 0) + 1
	if inst:IsA("BasePart") and inst.ClassName ~= "Terrain" then
		local shape = "Block"
		if inst.ClassName == "Part" then
			shape = inst.Shape.Name
		elseif inst.ClassName == "WedgePart" then
			shape = "Wedge"
		elseif inst.ClassName == "CornerWedgePart" then
			shape = "CornerWedge"
		elseif inst.ClassName == "SpawnLocation" then
			shape = "Block"
		end
		-- sign text (SurfaceGuis), for tools/render_view.py
		local texts = nil
		for _, gui in inst:GetChildren() do
			if gui.ClassName == "SurfaceGui" then
				local lines = {}
				for _, label in gui:GetChildren() do
					if label.ClassName == "TextLabel" then
						table.insert(lines, label.Text)
					end
				end
				texts = texts or {}
				table.insert(texts, { face = gui.Face.Name, lines = lines })
			end
		end
		table.insert(parts, {
			path = inst:GetFullName(),
			name = inst.Name,
			class = inst.ClassName,
			shape = shape,
			size = vec(inst.Size),
			cframe = cf(inst.CFrame),
			color = { inst.Color.R, inst.Color.G, inst.Color.B },
			transparency = inst.Transparency,
			material = inst.Material.Name,
			canCollide = inst.CanCollide,
			canTouch = inst.CanTouch,
			canQuery = inst.CanQuery,
			anchored = inst.Anchored,
			texts = texts,
		})
	end
end

-- cables (Beams) between attachments, as world-space segments
local beams = {}
for _, inst in workspace:GetDescendants() do
	if inst.ClassName == "Beam" then
		local a0, a1 = inst.Attachment0, inst.Attachment1
		if a0 and a1 and a0.Parent and a1.Parent then
			local p0 = a0.Parent.CFrame:PointToWorldSpace(a0.Position)
			local p1 = a1.Parent.CFrame:PointToWorldSpace(a1.Position)
			local color = inst.Color.Keypoints[1].Value
			table.insert(beams, {
				a = vec(p0),
				b = vec(p1),
				width = inst.Width0,
				color = { color.R, color.G, color.B },
				glow = inst.LightEmission,
			})
		end
	end
end

-- lights, for the render's glow pass
local lights = {}
for _, inst in workspace:GetDescendants() do
	if inst.ClassName == "PointLight" or inst.ClassName == "SpotLight" then
		local holder = inst.Parent
		local position = nil
		if holder and holder:IsA("BasePart") then
			position = holder.CFrame.Position
		elseif
			holder
			and holder.ClassName == "Attachment"
			and holder.Parent
			and holder.Parent:IsA("BasePart")
		then
			position = holder.Parent.CFrame:PointToWorldSpace(holder.Position)
		end
		if position then
			table.insert(lights, {
				p = vec(position),
				range = inst.Range,
				color = { inst.Color.R, inst.Color.G, inst.Color.B },
			})
		end
	end
end

local terrain = {}
for _, op in world.terrainOps do
	local entry = { kind = op.kind }
	local a = op.args
	if op.kind == "FillBlock" or op.kind == "FillWedge" then
		entry.cframe, entry.size, entry.material = cf(a[1]), vec(a[2]), a[3].Name
	elseif op.kind == "FillBall" then
		entry.center, entry.radius, entry.material = vec(a[1]), a[2], a[3].Name
	elseif op.kind == "FillCylinder" then
		entry.cframe, entry.height, entry.radius, entry.material = cf(a[1]), a[2], a[3], a[4].Name
	end
	table.insert(terrain, entry)
end

-- contract checks the gameplay code relies on
local zones = map and map:FindFirstChild("Zones")
need(zones ~= nil, "Map.Zones missing")
local Config = world:require("ReplicatedStorage.Shared.Config")
local Formulas = world:require("ReplicatedStorage.Shared.Util.Formulas")
local worlds = if styleName then { Config.WORLDS[1] } else Config.WORLDS
for _, w in worlds do
	for _, def in Formulas.worldZones(w.id) do
		local zonePart = zones and zones:FindFirstChild(def.id)
		need(zonePart ~= nil and zonePart:IsA("BasePart"), "zone part missing for " .. def.id)
	end
end
-- every world's hub has a portal to the next world and back to the last
local portalsTo = {}
for _, inst in workspace:GetDescendants() do
	if inst:IsA("BasePart") and inst:HasTag("Portal") then
		local to = inst:GetAttribute("ToWorld")
		portalsTo[to] = (portalsTo[to] or 0) + 1
	end
end
for index, w in worlds do
	-- one from the world before (onward) and one from the world after (back)
	local links = (if worlds[index - 1] then 1 else 0) + (if worlds[index + 1] then 1 else 0)
	need((portalsTo[w.id] or 0) == links, string.format("%d portals lead to %s", links, w.id))
end
local sellAreas = 0
for _, inst in workspace:GetDescendants() do
	if inst:IsA("BasePart") and inst:HasTag("SellArea") then
		sellAreas += 1
	end
end
local legacyPad = map
	and map:FindFirstChild("PowerPlant")
	and map.PowerPlant:FindFirstChild("SellPad")
need(sellAreas > 0 or legacyPad ~= nil, "no sell area (tagged SellArea) or PowerPlant.SellPad")
local spawns = 0
for _, inst in workspace:GetDescendants() do
	if inst.ClassName == "SpawnLocation" then
		spawns += 1
	end
end
need(spawns > 0, "no SpawnLocation")

-- one file per world: everything goes to the world whose hub is nearest
local function nearest(p)
	local best, bestDistance = 1, math.huge
	for index, w in worlds do
		local dx, dz = p[1] - w.offset.X, p[3] - w.offset.Z
		local distance = dx * dx + dz * dz
		if distance < bestDistance then
			best, bestDistance = index, distance
		end
	end
	return best
end
for index, w in worlds do
	local mine = function(list, key)
		local out = {}
		for _, item in list do
			if nearest(item[key]) == index then
				table.insert(out, item)
			end
		end
		return out
	end
	local path = if index == 1
		then outPath
		else string.gsub(outPath, "%.json$", "") .. "_" .. w.id .. ".json"
	local worldParts = mine(parts, "cframe")
	fs.writeFile(
		path,
		serde.encode("json", {
			parts = worldParts,
			terrain = terrain,
			beams = mine(beams, "a"),
			lights = mine(lights, "p"),
			style = if styleName then styleName else w.style,
			world = w.id,
			counts = counts,
			warnings = world.warnings,
			problems = problems,
		})
	)
	print(
		string.format(
			"built %s: %d parts, %d terrain ops, %d warnings -> %s",
			w.id,
			#worldParts,
			#terrain,
			#world.warnings,
			path
		)
	)
end
for _, w in world.warnings do
	print("WARN: " .. w)
end
if #problems > 0 then
	for _, p in problems do
		print("PROBLEM: " .. p)
	end
	process.exit(2)
end
