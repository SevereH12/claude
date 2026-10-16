--!nocheck
-- Builds the map with the real MapBuilder in a stand-in world and writes
-- every part + terrain fill to a JSON file for checks and rendering.
--   lune run tools/harness/buildmap.luau [outfile]
-- Exits non-zero if the build errors or required map pieces are missing.

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local World = require("./World")

local outPath = process.args[1] or "map.json"
local world = World.new("src")

local MapBuilder = world:require("ServerScriptService.Server.Lib.MapBuilder")
local ok, err = pcall(MapBuilder.build)
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
		})
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
for id in Config.ZONES do
	local zonePart = zones and zones:FindFirstChild(id)
	need(zonePart ~= nil and zonePart:IsA("BasePart"), "zone part missing for " .. id)
end
local sellAreas = 0
for _, inst in workspace:GetDescendants() do
	if inst:IsA("BasePart") and inst:HasTag("SellArea") then
		sellAreas += 1
	end
end
local legacyPad = map and map:FindFirstChild("PowerPlant") and map.PowerPlant:FindFirstChild("SellPad")
need(sellAreas > 0 or legacyPad ~= nil, "no sell area (tagged SellArea) or PowerPlant.SellPad")
local spawns = 0
for _, inst in workspace:GetDescendants() do
	if inst.ClassName == "SpawnLocation" then
		spawns += 1
	end
end
need(spawns > 0, "no SpawnLocation")

fs.writeFile(
	outPath,
	serde.encode("json", {
		parts = parts,
		terrain = terrain,
		counts = counts,
		warnings = world.warnings,
		problems = problems,
	})
)
print(string.format("built: %d parts, %d terrain ops, %d warnings -> %s", #parts, #terrain, #world.warnings, outPath))
for _, w in world.warnings do
	print("WARN: " .. w)
end
if #problems > 0 then
	for _, p in problems do
		print("PROBLEM: " .. p)
	end
	process.exit(2)
end
