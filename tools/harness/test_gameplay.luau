--!nocheck
-- Gameplay contract tests against the real map + real modules.
--   lune run tools/harness/test_gameplay.luau [style]
-- Checks the things the game silently depends on: every zone has a volume,
-- strikes have ground to land on inside it, the sell station is reachable
-- and detected by Selling, spawn is outside zones, zone volumes don't
-- overlap each other or the sell station.

local process = require("@lune/process")
local roblox = require("@lune/roblox")

local World = require("./World")

local Vector3 = roblox.Vector3
local styleName = process.args[1] -- nil = Config.WORLD_STYLE
local world = World.new("src")
world:require("ServerScriptService.Server.Lib.MapBuilder").build(styleName)
world:normalizeParts()

local Config = world:require("ReplicatedStorage.Shared.Config")
local Zones = world:require("ReplicatedStorage.Shared.Util.Zones")
local Selling = world:require("ServerScriptService.Server.Systems.Selling")

local failures = 0
local passes = 0
local function check(condition, message)
	if condition then
		passes += 1
	else
		failures += 1
		print("FAIL: " .. message)
	end
end

local map = world.workspace:FindFirstChild("Map")
check(map ~= nil, "Workspace.Map exists")

-- a character standing on a surface has its root ~3 studs above it
local ROOT = 3

-- zones -------------------------------------------------------------------
local zoneParts = {}
for id, def in Config.ZONES do
	local part = Zones.part(id)
	check(part ~= nil, "zone part exists for " .. id)
	if part then
		zoneParts[id] = part
		local floorCenter = part.CFrame.Position - Vector3.new(0, part.Size.Y / 2, 0)
		local inside = floorCenter + Vector3.new(0, 1 + ROOT, 0)
		local found = Zones.at(inside)
		check(
			found ~= nil and found.id == id,
			"a player standing on " .. id .. "'s floor is in " .. id
		)
		check(
			part.Size.X >= 2 * (Config.STRIKE_RADIUS + 2) + 10,
			id .. " is wide enough for strike circles"
		)
		check(
			part.Size.Z >= 2 * (Config.STRIKE_RADIUS + 2) + 10,
			id .. " is deep enough for strike circles"
		)
		check(
			part.Transparency >= 1 and not part.CanCollide and not part.CanQuery,
			id .. " volume is invisible and non-blocking"
		)
		check(def.color ~= nil and def.tagline ~= nil, id .. " has a colour and tagline")
	end
end
for a, pa in zoneParts do
	for b, pb in zoneParts do
		if a < b then
			local d = pa.CFrame.Position - pb.CFrame.Position
			local overlapX = math.abs(d.X) < (pa.Size.X + pb.Size.X) / 2
			local overlapY = math.abs(d.Y) < (pa.Size.Y + pb.Size.Y) / 2
			local overlapZ = math.abs(d.Z) < (pa.Size.Z + pb.Size.Z) / 2
			check(
				not (overlapX and overlapY and overlapZ),
				a .. " and " .. b .. " zone volumes do not overlap"
			)
		end
	end
end

-- spawn -------------------------------------------------------------------
local spawn
for _, inst in world.workspace:GetDescendants() do
	if inst.ClassName == "SpawnLocation" then
		spawn = inst
	end
end
check(spawn ~= nil, "a SpawnLocation exists")
if spawn then
	local standing = spawn.CFrame.Position + Vector3.new(0, spawn.Size.Y / 2 + ROOT, 0)
	check(Zones.at(standing) == nil, "spawn is outside every zone")
	check(not Selling.isAtStation(standing), "spawn is not a sell station")
end

-- selling -----------------------------------------------------------------
local stations = {}
for _, inst in world.workspace:GetDescendants() do
	if inst:IsA("BasePart") and inst:HasTag("SellArea") then
		table.insert(stations, inst)
	end
end
local pad = map and map:FindFirstChild("PowerPlant") and map.PowerPlant:FindFirstChild("SellPad")
check(#stations > 0 or pad ~= nil, "there is a sell station (SellArea tag or legacy SellPad)")
for _, area in stations do
	check(
		area.Transparency >= 1 and not area.CanCollide,
		area:GetFullName() .. " SellArea is invisible and non-blocking"
	)
	-- find the floor under the middle of the area: the visible pad/floor part below it
	local bottom = area.CFrame.Position - Vector3.new(0, area.Size.Y / 2, 0)
	local standing = bottom + Vector3.new(0, 1 + ROOT, 0)
	check(
		Selling.isAtStation(standing),
		"standing in the middle of " .. area:GetFullName() .. " sells"
	)
	check(Zones.at(standing) == nil, area:GetFullName() .. " is not inside a zone")
	local far = area.CFrame.Position + Vector3.new(area.Size.X, 0, area.Size.Z)
	check(not Selling.isAtStation(far), "a point beside " .. area:GetFullName() .. " does not sell")
end
if #stations == 0 and pad then
	local standing = pad.CFrame.Position + Vector3.new(0, pad.Size.Y / 2 + ROOT, 0)
	check(Selling.isAtStation(standing), "standing on the legacy SellPad sells")
end

-- catch floors must stay clear -------------------------------------------
-- Strike circles can appear anywhere inside a zone except its outer 2-stud
-- band, so nothing visible may stand above the floor there.
local BORDER_BAND = 2
for id, part in zoneParts do
	local floorY = part.CFrame.Position.Y - part.Size.Y / 2 + 1
	local hw, hd = part.Size.X / 2 - BORDER_BAND, part.Size.Z / 2 - BORDER_BAND
	local blockers = {}
	for _, inst in world.workspace:GetDescendants() do
		if
			inst:IsA("BasePart")
			and inst ~= part
			and inst.Transparency < 0.98
			and inst.ClassName ~= "Terrain"
		then
			local half = inst.Size / 2
			-- sample the part's corners and centre against the catch rectangle
			local intrudes = false
			for _, sx in { -1, 0, 1 } do
				for _, sy in { -1, 0, 1 } do
					for _, sz in { -1, 0, 1 } do
						local p = inst.CFrame:PointToWorldSpace(
							Vector3.new(sx * half.X, sy * half.Y, sz * half.Z)
						)
						local l = part.CFrame:PointToObjectSpace(p)
						if
							math.abs(l.X) <= hw
							and math.abs(l.Z) <= hd
							and p.Y > floorY + 0.3
							and p.Y < floorY + 30
						then
							intrudes = true
						end
					end
				end
			end
			if intrudes then
				table.insert(blockers, inst:GetFullName())
			end
		end
	end
	check(
		#blockers == 0,
		id
			.. " catch floor is clear (found: "
			.. table.concat(blockers, ", ", 1, math.min(#blockers, 5))
			.. ")"
	)
end

-- teaser and budget ----------------------------------------------------------
local zoneArt = map and map:FindFirstChild("ZoneArt")
local teaser = zoneArt and zoneArt:FindFirstChild("ComingSoon")
if map and map:GetAttribute("Style") ~= "Legacy" then -- the old map predates teasers
	check(teaser ~= nil and #teaser:GetDescendants() > 0, "a Coming Soon teaser was built")
end
local partCount = 0
for _, inst in world.workspace:GetDescendants() do
	if inst:IsA("BasePart") and inst.ClassName ~= "Terrain" then
		partCount += 1
	end
end
check(partCount <= 2500, string.format("part budget: %d / 2500", partCount))
print(string.format("parts: %d", partCount))

print(string.format("%d passed, %d failed", passes, failures))
for _, w in world.warnings do
	print("WARN: " .. w)
end
process.exit(if failures == 0 then 0 else 1)
