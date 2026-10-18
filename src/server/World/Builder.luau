--!strict
-- Builds the whole world in one style:
--   1. clear the old map and terrain
--   2. plan zone slots on the spiral (Layout) from Config.ZONES
--   3. create every zone's volume part (the gameplay contract; styles never do this)
--   4. call the style pack: atmosphere -> base -> hub -> per zone (ground,
--      connector, border, gate, theme) -> teaser
--   5. build each zone's Research Camp (box + style.buildCamp or Kit.researchCamp)
--   6. check the result has a SpawnLocation and a SellArea (warn if no ResearchOffice)
--
-- Adding a zone = adding a Config.ZONES entry. It lands in the next slot,
-- the teaser moves one slot further out, and nothing else moves.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Util.Formulas)
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

function Builder.build(styleName: string?): Folder
	local name = styleName or Config.WORLD_STYLE
	local style: StylePack = (require :: any)(styleModule(name))

	local old = workspace:FindFirstChild("Map")
	if old then
		old:Destroy()
	end
	clearTemplate()
	workspace.Terrain:Clear()

	local map = folder("Map", workspace)
	map:SetAttribute("AutoBuilt", true)
	map:SetAttribute("Style", name)
	map:SetAttribute("Ground", style.ground or "Terrain")

	-- zone volumes stay loaded on every client even with streaming on
	local zonesModel = Instance.new("Model")
	zonesModel.Name = "Zones"
	zonesModel.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	zonesModel.Parent = map

	-- ground = what players walk on (Blocks); the strike raycast hits it
	local folders = {
		ground = folder("Ground", map),
		base = folder("Base", map),
		hub = folder("Hub", map),
		zones = folder("ZoneArt", map),
		connectors = folder("Connectors", map),
		decor = folder("Decor", map),
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
		Parent = map,
	})

	-- plan
	local defs = Formulas.sortedZones()
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
		map = map,
		folders = folders,
		terrain = workspace.Terrain,
		rng = Random.new(seedFor(name)),
		layout = style.layout,
		zones = zones,
		teaser = teaser,
		cableAnchor = cableAnchor,
	}

	-- build
	style.atmosphere(ctx)
	style.buildBase(ctx)
	style.buildHub(ctx)
	for _, zone in zones do
		local def = zone.def :: any
		zoneVolume(zonesModel, def.id, zone)
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
	local camps = Instance.new("Model")
	camps.Name = "ResearchCamps"
	camps.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	camps.Parent = map
	for _, zone in zones do
		local def = zone.def :: any
		local box = campBox(camps, def.id, zone)
		box:SetAttribute("ZoneId", def.id)
		if style.buildCamp then
			style.buildCamp(ctx, zone)
		else
			Kit.researchCamp(ctx, zone)
		end
	end

	-- contracts the game relies on
	local spawnCount, sellCount = 0, 0
	for _, descendant in map:GetDescendants() do
		if descendant:IsA("SpawnLocation") then
			spawnCount += 1
		end
	end
	for _, tagged in CollectionService:GetTagged(Kit.SELL_TAG) do
		if tagged:IsDescendantOf(map) then
			sellCount += 1
		end
	end
	if spawnCount == 0 then
		error(`[World] style "{name}" built no SpawnLocation`, 0)
	end
	if sellCount == 0 then
		error(`[World] style "{name}" built no SellArea (use Kit.sellArea)`, 0)
	end

	local hasOffice = false
	for _, tagged in CollectionService:GetTagged(Kit.OFFICE_TAG) do
		if tagged:IsDescendantOf(map) then
			hasOffice = true
		end
	end
	if not hasOffice then
		warn(`[World] style "{name}" built no ResearchOffice (use Kit.researchOffice)`)
	end

	print(`[World] built "{name}": {#zones} zones, {countParts(map)} parts`)
	return map
end

return Builder
