--!nocheck
-- Gameplay contract tests against the real map + real modules.
--   lune run tools/harness/test_gameplay.luau [style]
-- Checks the things the game silently depends on: every zone has a volume,
-- strikes have ground to land on inside it, the sell station is reachable
-- and detected by Selling, spawn is outside zones, zone volumes don't
-- overlap each other or the sell station, portals lead where they say.
-- style "Game" (or none) = every world; a style name = the first world's
-- zones in that style.

local process = require("@lune/process")
local roblox = require("@lune/roblox")

local World = require("./World")

local Vector3 = roblox.Vector3
local styleName = process.args[1] -- nil or "Game" = every world
if styleName == "Game" then
	styleName = nil
end
local world = World.new("src")
world:require("ServerScriptService.Server.Lib.MapBuilder").build(styleName)
world:normalizeParts()

local Config = world:require("ReplicatedStorage.Shared.Config")
local Zones = world:require("ReplicatedStorage.Shared.Util.Zones")
local ResearchSites = world:require("ReplicatedStorage.Shared.Util.ResearchSites")
local Selling = world:require("ServerScriptService.Server.Systems.Selling")
local Formulas = world:require("ReplicatedStorage.Shared.Util.Formulas")
local Portals = world:require("ReplicatedStorage.Shared.Util.Portals")

-- the zones this build has: every world's, or the first world's in a preview
local worlds = if styleName then { Config.WORLDS[1] } else Config.WORLDS
local builtZones = {}
for _, w in worlds do
	for _, def in Formulas.worldZones(w.id) do
		builtZones[def.id] = def
	end
end

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
for id, def in builtZones do
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
-- one per world (where portals drop you); only the first world's spawns
local spawnsByWorld = {}
for _, inst in world.workspace:GetDescendants() do
	if inst.ClassName == "SpawnLocation" then
		local id = inst:GetAttribute("World")
		spawnsByWorld[id] = inst
		local standing = inst.CFrame.Position + Vector3.new(0, inst.Size.Y / 2 + ROOT, 0)
		check(Zones.at(standing) == nil, inst:GetFullName() .. " is outside every zone")
		check(not Selling.isAtStation(standing), inst:GetFullName() .. " is not a sell station")
		check(Portals.at(standing) == nil, inst:GetFullName() .. " is not in a portal")
		check(
			inst.Enabled == (id == Config.WORLDS[1].id),
			inst:GetFullName() .. " spawns players only if it's in the first world"
		)
	end
end
for _, w in worlds do
	check(spawnsByWorld[w.id] ~= nil, "a SpawnLocation exists for world " .. w.id)
end

-- portals -----------------------------------------------------------------------
local portalCount = 0
for _, inst in world.workspace:GetDescendants() do
	if inst:IsA("BasePart") and inst:HasTag(Portals.TAG) then
		portalCount += 1
		local to = inst:GetAttribute("ToWorld")
		local name = inst:GetFullName()
		local standing = inst.CFrame.Position - Vector3.new(0, inst.Size.Y / 2 - ROOT, 0)
		local found = Portals.at(standing)
		check(found ~= nil and found.id == to, "walking into " .. name .. " leads to " .. tostring(to))
		check(spawnsByWorld[to] ~= nil, name .. " leads to a world with a spawn")
		check(
			inst.Transparency >= 1 and not inst.CanCollide and not inst.CanQuery,
			name .. " is invisible and non-blocking"
		)
		check(Zones.at(standing) == nil, name .. " is outside every zone")
		check(not Selling.isAtStation(standing), name .. " is not a sell station")
		-- it stands in the hub of the world before or after the one it leads to
		local nearest, best = nil, math.huge
		for _, w in worlds do
			local d = (Vector3.new(w.offset.X, 0, w.offset.Z) - Vector3.new(inst.CFrame.X, 0, inst.CFrame.Z)).Magnitude
			if d < best then
				nearest, best = w, d
			end
		end
		check(
			nearest ~= nil and math.abs(Formulas.worldIndex(nearest.id) - Formulas.worldIndex(to)) == 1,
			name .. " is in the hub of a neighbouring world"
		)
	end
end
check(portalCount == 2 * (#worlds - 1), string.format("%d portals for %d worlds", portalCount, #worlds))

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

-- research camps and office ------------------------------------------------------
local campsModel = map and map:FindFirstChild("ResearchCamps")
check(campsModel ~= nil, "Map.ResearchCamps exists")
for id in builtZones do
	local box = campsModel and campsModel:FindFirstChild(id)
	check(box ~= nil and box:IsA("BasePart"), "a research camp box exists for " .. id)
	if box then
		check(box:GetAttribute("ZoneId") == id, id .. " camp box has its ZoneId attribute")
		check(
			box.Transparency >= 1 and not box.CanCollide and not box.CanQuery and not box.CanTouch,
			id .. " camp box is invisible and non-blocking"
		)
		local deck = box.CFrame.Position - Vector3.new(0, box.Size.Y / 2 - 1, 0)
		local standing = deck + Vector3.new(0, 1 + ROOT, 0)
		check(ResearchSites.campAt(standing) == id, "standing on " .. id .. "'s camp deck is in its camp")
		check(ResearchSites.camp(id) == box, "ResearchSites.camp finds " .. id)
		check(Zones.at(standing) == nil, id .. " camp is outside every zone")
		check(not Selling.isAtStation(standing), id .. " camp is not a sell station")
		for zid, zpart in zoneParts do
			-- the whole box, not just the middle: sample its corners and centre
			local inside = false
			for _, sx in { -1, 0, 1 } do
				for _, sz in { -1, 0, 1 } do
					local p = box.CFrame:PointToWorldSpace(
						Vector3.new(sx * box.Size.X / 2, 0, sz * box.Size.Z / 2)
					)
					if Zones.contains(zpart, p) then
						inside = true
					end
				end
			end
			check(not inside, id .. " camp box is outside zone " .. zid)
		end
	end
end
local offices = ResearchSites.offices()
if map and map:GetAttribute("Style") == "WeatherLab" then
	check(#offices > 0, "WeatherLab has a ResearchOffice")
end
for _, office in offices do
	local standing = office.CFrame.Position - Vector3.new(0, office.Size.Y / 2 - 1, 0)
		+ Vector3.new(0, 1 + ROOT, 0)
	check(ResearchSites.inOffice(standing), "standing on " .. office:GetFullName() .. " is in the office")
	check(Zones.at(standing) == nil, office:GetFullName() .. " is outside every zone")
	check(not Selling.isAtStation(standing), office:GetFullName() .. " is not a sell station")
	check(
		office.Transparency >= 1 and not office.CanCollide,
		office:GetFullName() .. " is invisible and non-blocking"
	)
end

-- the AFK Lounge -----------------------------------------------------------
local lounges = {}
for _, inst in world.workspace:GetDescendants() do
	if inst:IsA("BasePart") and inst:HasTag("AfkZone") then
		table.insert(lounges, inst)
	end
end
if map and map:GetAttribute("Style") == "WeatherLab" then
	check(#lounges > 0, "WeatherLab has an AFK Lounge (AfkZone)")
end
for _, box in lounges do
	check(box.Transparency >= 1 and not box.CanCollide, box:GetFullName() .. " is invisible and non-blocking")
	-- the whole box, not just the middle
	for _, sx in { -1, 0, 1 } do
		for _, sz in { -1, 0, 1 } do
			local p = box.CFrame:PointToWorldSpace(
				Vector3.new(sx * box.Size.X / 2, -box.Size.Y / 2 + 1 + ROOT, sz * box.Size.Z / 2)
			)
			check(Zones.at(p) == nil, box:GetFullName() .. " is outside every zone")
			check(not Selling.isAtStation(p), box:GetFullName() .. " is not a sell station")
		end
	end
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

-- block-built ground -----------------------------------------------------------
-- Styles with ground = "Blocks" fill no terrain, and every catch floor is
-- covered by collidable Map.Ground parts whose top is exactly at floor height.

-- Highest point of `part` on the vertical line through (x, z), or nil.
-- Blocks and upright cylinders only (catch floors are built from those).
local function topAt(part, x, z)
	local cf = part.CFrame
	local a = cf:PointToObjectSpace(Vector3.new(x, 0, z))
	local b = cf:VectorToObjectSpace(Vector3.new(0, 1, 0))
	local half = part.Size / 2
	local axes = { "X", "Y", "Z" }
	if part.ClassName == "Part" and part.Shape.Name == "Cylinder" then
		if math.abs(b.X) < 0.999 then
			return nil
		end
		local radius = math.min(half.Y, half.Z)
		if a.Y * a.Y + a.Z * a.Z > radius * radius then
			return nil
		end
		axes = { "X" }
	elseif part.ClassName ~= "Part" or part.Shape.Name ~= "Block" then
		return nil
	end
	local lo, hi = -math.huge, math.huge
	for _, axis in axes do
		local p, d, h = a[axis], b[axis], half[axis]
		if math.abs(d) < 1e-9 then
			if math.abs(p) > h then
				return nil
			end
		else
			local t1, t2 = (-h - p) / d, (h - p) / d
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			lo, hi = math.max(lo, t1), math.min(hi, t2)
			if lo > hi then
				return nil
			end
		end
	end
	return hi
end

if map and map:GetAttribute("Ground") == "Blocks" then
	local fills = 0
	for _, op in world.terrainOps do
		if op.kind ~= "Clear" then
			fills += 1
		end
	end
	check(fills == 0, string.format("block-built ground fills no terrain (found %d fills)", fills))

	local groundFolder = map:FindFirstChild("Ground")
	local groundParts = {}
	if groundFolder then
		for _, inst in groundFolder:GetDescendants() do
			if inst:IsA("BasePart") and inst.CanCollide and inst.Transparency < 0.98 then
				table.insert(groundParts, {
					part = inst,
					center = inst.CFrame.Position,
					reach = inst.Size.Magnitude / 2,
				})
			end
		end
	end
	check(#groundParts > 0, "Map.Ground has collidable ground parts")

	local STEP = 4
	for id, part in zoneParts do
		local floorY = part.CFrame.Position.Y - part.Size.Y / 2 + 1
		local hw, hd = part.Size.X / 2 - BORDER_BAND, part.Size.Z / 2 - BORDER_BAND
		local samples, bad = 0, {}
		local nu, nv = math.ceil(2 * hw / STEP), math.ceil(2 * hd / STEP)
		for i = 0, nu do
			for k = 0, nv do
				local p = part.CFrame:PointToWorldSpace(
					Vector3.new(-hw + 2 * hw * i / nu, 0, -hd + 2 * hd * k / nv)
				)
				local best = nil
				for _, g in groundParts do
					local dx, dz = g.center.X - p.X, g.center.Z - p.Z
					if dx * dx + dz * dz <= g.reach * g.reach then
						local top = topAt(g.part, p.X, p.Z)
						if top and (best == nil or top > best) then
							best = top
						end
					end
				end
				samples += 1
				if best == nil or math.abs(best - floorY) > 0.05 then
					table.insert(
						bad,
						string.format(
							"(%.0f, %.0f) %s",
							p.X,
							p.Z,
							if best then string.format("top %.2f", best) else "no ground"
						)
					)
				end
			end
		end
		check(
			#bad == 0,
			string.format(
				"%s catch floor is covered by Map.Ground at y=%.1f (%d of %d samples off: %s)",
				id,
				floorY,
				#bad,
				samples,
				table.concat(bad, ", ", 1, math.min(#bad, 5))
			)
		)
	end
end

-- teaser and part count ----------------------------------------------------------
local zoneArt = map and map:FindFirstChild("ZoneArt")
local teaser = zoneArt and zoneArt:FindFirstChild("ComingSoon")
if map then
	check(teaser ~= nil and #teaser:GetDescendants() > 0, "a Coming Soon teaser was built")
end
local partCount = 0
for _, inst in world.workspace:GetDescendants() do
	if inst:IsA("BasePart") and inst.ClassName ~= "Terrain" then
		partCount += 1
	end
end
-- no part limit (the user's call); the count is reported for reference
print(string.format("parts: %d", partCount))

print(string.format("%d passed, %d failed", passes, failures))
for _, w in world.warnings do
	print("WARN: " .. w)
end
process.exit(if failures == 0 then 0 else 1)
