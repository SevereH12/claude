--!strict
-- Builds the whole game: every world in Config.WORLDS, each in its own style.
-- Each world is built round the origin and then moved to world.offset; its
-- zone volumes, camps, gates and ground join the shared Map.Zones,
-- Map.ResearchCamps, Map.ZoneGates and Map.Ground (Map.Ground.<WorldId>),
-- and the rest of its art sits in Map.<WorldId> (the first world's sits
-- straight in Map). Per world:
--   1. plan its zone slots on the spiral (Layout) from its Config.ZONES entries
--   2. create every zone's volume part (the gameplay contract; styles never do this)
--   3. call the style pack: atmosphere (first world only) -> base -> hub
--      (with its portals) -> per zone (ground, connector, border, gate,
--      theme) -> teaser
--   4. build each zone's Research Camp (box + style.buildCamp or Kit.researchCamp)
--   5. check it has a SpawnLocation, a SellArea and its portals (warn if
--      the first world has no ResearchOffice)
-- Only the first world's SpawnLocation is used for spawning; the others
-- are where portals drop you (attribute World on each).
--
-- Adding a zone = adding a Config.ZONES entry. It lands in the next slot of
-- its world, the teaser moves one slot further out, and nothing else moves.
-- Adding a world = adding a Config.WORLDS entry (and its zones).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local SharedTypes = require(ReplicatedStorage.Shared.Types)
local Formulas = require(ReplicatedStorage.Shared.Util.Formulas)
local Progression = require(ReplicatedStorage.Shared.Util.Progression)
local Kit = require(script.Parent.Kit)
local Layout = require(script.Parent.Layout)
local WorldTypes = require(script.Parent.Types)

type Context = WorldTypes.Context
type ZoneContext = WorldTypes.ZoneContext
type StylePack = WorldTypes.StylePack

-- How far a zone's volume reaches above its floor.
local ZONE_HEIGHT = 46
-- Strike circles stay this far inside the footprint edge (Strikes insets
-- strike centres by STRIKE_RADIUS + 2), so only this outer band is free
-- for border pieces.
local BORDER_BAND = 2
local CAMP_HEIGHT = 12
local TEASER_COLOR = Color3.fromRGB(150, 150, 160)

local Builder = {}

local function styleModule(name: string): ModuleScript
	local styles = script.Parent:FindFirstChild("Styles")
	local module = styles and styles:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		error(`[World] unknown style "{name}" (expected src/server/World/Styles/{name})`, 0)
	end
	return module
end

function Builder.styleNames(): { string }
	local names = {}
	local styles = script.Parent:FindFirstChild("Styles")
	if styles then
		for _, child in styles:GetChildren() do
			if child:IsA("ModuleScript") then
				table.insert(names, child.Name)
			end
		end
	end
	table.sort(names)
	return names
end

-- Same style -> same seed -> same world every build.
local function seedFor(name: string): number
	local seed = 7
	for i = 1, #name do
		seed = (seed * 31 + string.byte(name, i)) % 2147483647
	end
	return seed
end

local function folder(name: string, parent: Instance): Folder
	local newFolder = Instance.new("Folder")
	newFolder.Name = name
	newFolder.Parent = parent
	return newFolder
end

-- The default Baseplate template's parts would overlap the world.
local function clearTemplate()
	for _, name in { "Baseplate", "SpawnLocation" } do
		local existing = workspace:FindFirstChild(name)
		if existing and existing:IsA("BasePart") then
			existing:Destroy()
		end
	end
end

local function zoneVolume(parent: Instance, name: string, zone: ZoneContext): BasePart
	local slot = zone.slot
	return Kit.part({
		Name = name,
		Size = Vector3.new(slot.width, ZONE_HEIGHT, slot.depth),
		CFrame = slot.frame * CFrame.new(0, ZONE_HEIGHT / 2 - 1, 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Parent = parent,
	})
end

-- The camp's gameplay volume (Util/ResearchSites), set up like a SellArea.
local function campBox(parent: Instance, name: string, zone: ZoneContext): BasePart
	return Kit.part({
		Name = name,
		Size = Vector3.new(Layout.CAMP_WIDTH, CAMP_HEIGHT, Layout.CAMP_DEPTH),
		CFrame = zone.slot.camp * CFrame.new(0, CAMP_HEIGHT / 2 - 1, 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Parent = parent,
	})
end

local function countParts(root: Instance): number
	local count = 0
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			count += 1
		end
	end
	return count
end

type Containers = {
	zones: Instance,
	camps: Instance,
	gates: Instance,
}

type Plan = {
	world: SharedTypes.WorldDef,
	style: string,
	portals: { WorldTypes.Portal },
}

local function persistentModel(name: string, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = name
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model.Parent = parent
	return model
end

local function taggedIn(root: Instance, tag: string): { Instance }
	local list = {}
	for _, tagged in CollectionService:GetTagged(tag) do
		if tagged:IsDescendantOf(root) then
			table.insert(list, tagged)
		end
	end
	return list
end

-- Builds one world into `root` (art folders) and `containers`, round the
-- origin. Returns the number of zones built.
local function buildWorld(
	plan: Plan,
	root: Folder,
	ground: Folder,
	containers: Containers,
	isFirst: boolean
): number
	local world = plan.world
	local name = plan.style
	local style: StylePack = (require :: any)(styleModule(name))

	-- ground = what players walk on (Blocks); the strike raycast hits it
	local folders = {
		ground = ground,
		base = folder("Base", root),
		hub = folder("Hub", root),
		zones = folder("ZoneArt", root),
		connectors = folder("Connectors", root),
		decor = folder("Decor", root),
	}

	local cableAnchor = Kit.part({
		Name = "CableAnchor",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Parent = root,
	})

	-- plan
	local defs = Formulas.worldZones(world.id)
	local footprints = {}
	for _, def in defs do
		table.insert(footprints, { width = def.width, depth = def.depth, floor = def.floor })
	end
	local slots, teaserSlot = Layout.plan(style.layout, footprints)

	local zones: { ZoneContext } = {}
	for i, def in defs do
		local slot = slots[i]
		table.insert(zones, {
			def = def,
			slot = slot,
			folder = folder(def.id, folders.zones),
			isTeaser = false,
			catchWidth = slot.width - 2 * BORDER_BAND,
			catchDepth = slot.depth - 2 * BORDER_BAND,
			color = def.color,
		})
	end
	local teaser: ZoneContext = {
		def = nil,
		slot = teaserSlot,
		folder = folder("ComingSoon", folders.zones),
		isTeaser = true,
		catchWidth = teaserSlot.width - 2 * BORDER_BAND,
		catchDepth = teaserSlot.depth - 2 * BORDER_BAND,
		color = TEASER_COLOR,
	}

	local ctx: Context = {
		map = root,
		folders = folders,
		terrain = workspace.Terrain,
		rng = Random.new(seedFor(name)),
		layout = style.layout,
		world = world,
		portals = plan.portals,
		zones = zones,
		teaser = teaser,
		cableAnchor = cableAnchor,
	}

	-- build
	if isFirst then
		style.atmosphere(ctx)
	end
	style.buildBase(ctx)
	style.buildHub(ctx)
	for _, zone in zones do
		local def = zone.def :: any
		zoneVolume(containers.zones, def.id, zone)
		style.buildZoneGround(ctx, zone)
	end
	for _, zone in zones do
		local def = zone.def :: any
		style.buildConnector(ctx, zone)
		style.buildBorder(ctx, zone)
		style.buildGate(ctx, zone)
		local theme = style.themes[def.theme] or style.themes.Default
		if theme then
			theme(ctx, zone)
		end
	end
	style.buildTeaser(ctx, teaser)

	-- Research Camps: one invisible box per zone, then the art
	for _, zone in zones do
		local def = zone.def :: any
		local box = campBox(containers.camps, def.id, zone)
		box:SetAttribute("ZoneId", def.id)
		if style.buildCamp then
			style.buildCamp(ctx, zone)
		else
			Kit.researchCamp(ctx, zone)
		end
	end

	-- Zone gates: a barrier at the gate of every zone with an entry rule.
	-- It never collides on the server; each client makes its own copy solid
	-- while it can't enter (Controllers/ZoneGates). The real lock is on the
	-- server (Strikes, Movement, Research).
	for _, zone in zones do
		local def = zone.def :: any
		local requirement = Progression.requirement(def)
		if requirement then
			Kit.zoneGate(containers.gates, zone, requirement)
		end
	end

	-- contracts the game relies on
	local spawns = {}
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("SpawnLocation") then
			table.insert(spawns, descendant)
		end
	end
	if #spawns == 0 then
		error(`[World] style "{name}" built no SpawnLocation`, 0)
	end
	for _, spawnLocation in spawns do
		spawnLocation:SetAttribute("World", world.id)
		-- only the first world's spawn is used for spawning
		spawnLocation.Enabled = isFirst
	end
	if #taggedIn(root, Kit.SELL_TAG) == 0 then
		error(`[World] style "{name}" built no SellArea (use Kit.sellArea)`, 0)
	end
	local portals = taggedIn(root, Kit.PORTAL_TAG)
	for _, portal in plan.portals do
		local found = false
		for _, box in portals do
			if box:GetAttribute("ToWorld") == portal.to.id then
				found = true
			end
		end
		if not found then
			error(`[World] style "{name}" built no portal to {portal.to.id} (use Kit.portal)`, 0)
		end
	end
	if isFirst and #taggedIn(root, Kit.OFFICE_TAG) == 0 then
		warn(`[World] style "{name}" built no ResearchOffice (use Kit.researchOffice)`)
	end
	return #zones
end

-- Every world with the portals its hub needs: to the next world (locked
-- until you own its bottle) and back to the previous one.
local function gamePlans(): { Plan }
	local plans: { Plan } = {}
	for index, world in Config.WORLDS do
		local portals: { WorldTypes.Portal } = {}
		local nextWorld = Config.WORLDS[index + 1]
		if nextWorld then
			table.insert(portals, {
				to = nextWorld,
				back = false,
				requirement = Progression.worldRequirement(nextWorld),
			})
		end
		local previous = Config.WORLDS[index - 1]
		if previous then
			table.insert(portals, { to = previous, back = true, requirement = nil })
		end
		table.insert(plans, { world = world, style = world.style, portals = portals })
	end
	return plans
end

-- `previewStyle`: build only the first world's zones, in that style, with
-- no portals (to review a style; the tools use it). nil = the whole game.
function Builder.build(previewStyle: string?): Folder
	local plans = if previewStyle
		then { { world = Config.WORLDS[1], style = previewStyle, portals = {} } :: Plan }
		else gamePlans()

	local old = workspace:FindFirstChild("Map")
	if old then
		old:Destroy()
	end
	clearTemplate()
	workspace.Terrain:Clear()

	local firstStyle: StylePack = (require :: any)(styleModule(plans[1].style))
	local map = folder("Map", workspace)
	map:SetAttribute("AutoBuilt", true)
	map:SetAttribute("Style", plans[1].style)
	map:SetAttribute("Ground", firstStyle.ground or "Terrain")

	-- zone volumes, camps and gates stay loaded on every client even with
	-- streaming on
	local shared: Containers = {
		zones = persistentModel("Zones", map),
		camps = persistentModel("ResearchCamps", map),
		gates = persistentModel("ZoneGates", map),
	}
	local ground = folder("Ground", map)

	for index, plan in plans do
		local world = plan.world
		if index == 1 then
			local count = buildWorld(plan, map, ground, shared, true)
			print(
				`[World] built "{plan.style}" ({world.displayName}): {count} zones, {countParts(map)} parts`
			)
		else
			-- build round the origin in a staging folder, move it to the
			-- world's offset, then hand the shared pieces over
			local root = folder(world.id, map)
			local staging: Containers = {
				zones = folder("Zones", root),
				camps = folder("ResearchCamps", root),
				gates = folder("ZoneGates", root),
			}
			local worldGround = folder(world.id, root)
			local count = buildWorld(plan, root, worldGround, staging, false)
			local parts = countParts(root)
			for _, descendant in root:GetDescendants() do
				if descendant:IsA("BasePart") then
					descendant.CFrame += world.offset
				end
			end
			worldGround.Parent = ground
			for _, pair in
				{
					{ staging.zones, shared.zones },
					{ staging.camps, shared.camps },
					{ staging.gates, shared.gates },
				}
			do
				for _, child in pair[1]:GetChildren() do
					child.Parent = pair[2]
				end
				pair[1]:Destroy()
			end
			print(
				`[World] built "{plan.style}" ({world.displayName}): {count} zones, {parts} parts`
			)
		end
	end
	return map
end

return Builder
