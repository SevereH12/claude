--!strict
-- The Graphics settings that aren't one effect's own (SETTINGS > Graphics):
--   * the starting Quality, set once by device (Util/Settings.devicePreset)
--   * Shadows (Lighting.GlobalShadows, on this screen only)
--   * Bloom: the world's bloom and sun rays, scaled (Storm scales the
--     colour grade)
--   * Field of view
--   * Far decorations: decoration parts (each world's Decor and ZoneArt
--     folders) past 250 or 500 studs hide, by LocalTransparencyModifier. Only
--     parts nothing walks on: no collision, no signs, nothing tagged. Checked
--     in batches every 2 seconds from a list made once.
-- And Accessibility & HUD > Text size, which sets Layout's text level.
-- A game can't change the player's own Roblox graphics level, only read it.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = require(ReplicatedStorage.Shared.Util.Settings)
local Layout = require(script.Parent.Parent.Lib.Layout)
local LayoutMath = require(script.Parent.Parent.Lib.LayoutMath)
local SettingsStore = require(script.Parent.Parent.Lib.SettingsStore)

local DECOR_FOLDERS = { "Decor", "ZoneArt" }
local CHECK_EVERY = 2 -- seconds between decoration passes
local BATCH = 400 -- parts per frame in a pass

local Graphics = {}

type Effect = { effect: PostEffect, property: string, base: number }
local effects: { Effect } = {}
local decor: { BasePart } = {}
local inDecor: { [BasePart]: boolean } = {}

local function robloxLevel(): number
	local ok, level = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel.Value
	end)
	return if ok and typeof(level) == "number" then level else 0
end

-- First join (nothing saved yet): the Quality that suits this device.
local function startingPreset()
	if SettingsStore.get("graphicsSet") then
		return
	end
	local preset = Rules.devicePreset(Layout.class, robloxLevel())
	SettingsStore.set("graphicsPreset", preset)
	SettingsStore.set("graphicsSet", true)
end

-- Bloom and sun rays at their world style's strength times the setting.
local function captureEffects()
	for _, child in Lighting:GetChildren() do
		if child:IsA("BloomEffect") or child:IsA("SunRaysEffect") then
			local intensity = (child :: any).Intensity :: number
			table.insert(effects, { effect = child, property = "Intensity", base = intensity })
		end
	end
end

local function applyBloom(amount: number)
	for _, entry in effects do
		(entry.effect :: any)[entry.property] = entry.base * amount
		entry.effect.Enabled = amount > 0
	end
end

local function applyFov(fov: number)
	local camera = workspace.CurrentCamera
	if camera then
		camera.FieldOfView = fov
	end
end

-- A part that's only there to look at (safe to hide far away).
local function isDecoration(part: BasePart): boolean
	if part.CanCollide or part.Transparency >= 1 then
		return false
	end
	if #CollectionService:GetTags(part) > 0 then
		return false
	end
	return part:FindFirstChildWhichIsA("SurfaceGui", true) == nil
		and part:FindFirstChildWhichIsA("BillboardGui", true) == nil
end

local function addPart(part: Instance)
	if part:IsA("BasePart") and not inDecor[part] and isDecoration(part) then
		inDecor[part] = true
		table.insert(decor, part)
	end
end

-- Every world's decoration folders: Map.Decor (the first world) and
-- Map.<WorldId>.Decor, and the same for ZoneArt.
local function watchFolder(folder: Instance)
	for _, descendant in folder:GetDescendants() do
		addPart(descendant)
	end
	folder.DescendantAdded:Connect(addPart) -- streamed in later
end

local watched: { [Instance]: boolean } = {}
local function watchRoot(root: Instance)
	local function consider(child: Instance)
		if not watched[child] and table.find(DECOR_FOLDERS, child.Name) then
			watched[child] = true
			watchFolder(child)
		end
	end
	for _, child in root:GetChildren() do
		consider(child)
	end
	root.ChildAdded:Connect(consider) -- with streaming, folders can arrive late
end

local function findDecor(map: Instance)
	watchRoot(map)
	local function addWorld(child: Instance)
		if child:IsA("Folder") or child:IsA("Model") then
			watchRoot(child)
		end
	end
	for _, child in map:GetChildren() do
		addWorld(child)
	end
	map.ChildAdded:Connect(addWorld)
end

-- Streaming removes far parts (and brings back new copies later): forget
-- the removed ones so the list doesn't keep growing.
local function forgetRemoved()
	local index = 1
	while index <= #decor do
		local part = decor[index]
		if part.Parent == nil then
			inDecor[part] = nil
			decor[index] = decor[#decor]
			decor[#decor] = nil
		else
			index += 1
		end
	end
end

-- One pass: hide decorations past the range, show the rest.
local function decorPass()
	local range = Rules.decorRange(SettingsStore.get("decorDistance"))
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local eye = camera.CFrame.Position
	for index, part in decor do
		if part.Parent then
			local far = range < math.huge and (part.Position - eye).Magnitude > range
			part.LocalTransparencyModifier = if far then 1 else 0
		end
		if index % BATCH == 0 then
			task.wait()
		end
	end
end

function Graphics.start()
	captureEffects()
	SettingsStore.watch("shadows", function(on: boolean)
		Lighting.GlobalShadows = on
	end)
	SettingsStore.watch("bloomAmount", applyBloom)
	SettingsStore.watch("fieldOfView", applyFov)
	SettingsStore.watch("textSize", function(size: string)
		Layout.setTextLevel(LayoutMath.TEXT_LEVELS[size] or 0)
	end)
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		applyFov(SettingsStore.get("fieldOfView"))
	end)

	if SettingsStore.loaded then
		startingPreset()
	else
		SettingsStore.Loaded:Connect(startingPreset)
	end

	task.spawn(function()
		local map = workspace:WaitForChild("Map", 60)
		if not map then
			return
		end
		findDecor(map)
		while true do
			forgetRemoved()
			decorPass()
			task.wait(CHECK_EVERY)
		end
	end)
end

return Graphics
