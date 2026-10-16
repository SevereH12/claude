--!nocheck
-- Test harness: a stand-in Roblox world for running game modules outside
-- Studio with Lune (https://lune-org.github.io). It loads src/ into a
-- DataModel with the same layout as default.project.json, gives each
-- module a working `script`, `require`, `game` and `workspace`, and stubs
-- the engine bits Lune doesn't have (terrain fills, tweens, task).
--
-- Usage from another harness script:
--   local World = require("./World")
--   local world = World.new("src")
--   local MapBuilder = world:require("ServerScriptService.Server.Lib.MapBuilder")

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Instance = roblox.Instance

local World = {}
World.__index = World

-- Records every terrain call so it can be checked and drawn later.
local terrainOps = {}
local function recordTerrain(kind)
	return function(_self, ...)
		table.insert(terrainOps, { kind = kind, args = { ... } })
	end
end
roblox.implementMethod("Terrain", "Clear", function()
	table.insert(terrainOps, { kind = "Clear", args = {} })
end)
roblox.implementMethod("Terrain", "FillBlock", recordTerrain("FillBlock"))
roblox.implementMethod("Terrain", "FillBall", recordTerrain("FillBall"))
roblox.implementMethod("Terrain", "FillCylinder", recordTerrain("FillCylinder"))
roblox.implementMethod("Terrain", "FillWedge", recordTerrain("FillWedge"))

local currentGame = nil
roblox.implementMethod("CollectionService", "GetTagged", function(_self, tag)
	local tagged = {}
	if currentGame then
		for _, inst in currentGame:GetDescendants() do
			if inst:HasTag(tag) then
				table.insert(tagged, inst)
			end
		end
	end
	return tagged
end)

local guidCounter = 0
roblox.implementMethod("HttpService", "GenerateGUID", function(_self, wrap)
	guidCounter += 1
	local guid = string.format("00000000-0000-4000-8000-%012d", guidCounter)
	return if wrap == false then guid else "{" .. guid .. "}"
end)

-- The harness plays the server in Studio.
roblox.implementMethod("RunService", "IsStudio", function()
	return true
end)
roblox.implementMethod("RunService", "IsServer", function()
	return true
end)
roblox.implementMethod("RunService", "IsClient", function()
	return false
end)
roblox.implementMethod("RunService", "IsRunning", function()
	return false
end)

local function scriptClass(fileName)
	if fileName:sub(-12) == ".server.luau" then
		return "Script", fileName:sub(1, -13)
	elseif fileName:sub(-12) == ".client.luau" then
		return "LocalScript", fileName:sub(1, -13)
	end
	return "ModuleScript", fileName:sub(1, -6)
end

-- Builds a directory the way Rojo does (init.server.luau => Script, etc.).
local function buildDirectory(path, name)
	local className, source = "Folder", nil
	for initName, initClass in
		{
			["init.server.luau"] = "Script",
			["init.client.luau"] = "LocalScript",
			["init.luau"] = "ModuleScript",
		}
	do
		if fs.isFile(path .. "/" .. initName) then
			className, source = initClass, fs.readFile(path .. "/" .. initName)
		end
	end
	local node = Instance.new(className)
	node.Name = name
	if source then
		node.Source = source
	end
	for _, entry in fs.readDir(path) do
		local full = path .. "/" .. entry
		if fs.isDir(full) then
			buildDirectory(full, entry).Parent = node
		elseif entry:sub(-5) == ".luau" and not entry:match("^init%.") then
			local childClass, childName = scriptClass(entry)
			local child = Instance.new(childClass)
			child.Name = childName
			child.Source = fs.readFile(full)
			child.Parent = node
		end
	end
	return node
end

function World.new(srcPath)
	local self = setmetatable({}, World)
	terrainOps = {}
	self.terrainOps = terrainOps
	self.warnings = {}

	local game = Instance.new("DataModel")
	self.game = game
	currentGame = game
	game.JobId = "" -- Studio has an empty JobId
	local workspace = game:GetService("Workspace")
	self.workspace = workspace
	local terrain = Instance.new("Terrain")
	terrain.Name = "Terrain"
	terrain.Parent = workspace
	local starterPlayer = game:GetService("StarterPlayer")
	local playerScripts = Instance.new("StarterPlayerScripts")
	playerScripts.Parent = starterPlayer
	game:GetService("Lighting")

	buildDirectory(srcPath .. "/shared", "Shared").Parent = game:GetService("ReplicatedStorage")
	buildDirectory(srcPath .. "/server", "Server").Parent = game:GetService("ServerScriptService")
	buildDirectory(srcPath .. "/client", "Client").Parent = playerScripts

	self.cache = {}
	return self
end

-- Lune's CFrame.lookAt mirrors the Z axis (looking south gives north).
-- Everything else in Lune's CFrame matches Roblox, so wrap it and replace
-- lookAt with Roblox's definition built from fromMatrix (verified correct).
local function lookAt(at, target, up)
	local upVector = up or roblox.Vector3.new(0, 1, 0)
	local look = (target - at).Unit
	local right = look:Cross(upVector)
	if right.Magnitude < 1e-6 then
		right = look:Cross(roblox.Vector3.new(0, 0, 1))
	end
	right = right.Unit
	return roblox.CFrame.fromMatrix(at, right, right:Cross(look), -look)
end
local CFrameShim = setmetatable({ lookAt = lookAt }, { __index = roblox.CFrame })

-- Roblox's Random (seeded, deterministic). Lune has no Random class.
local RandomClass = {}
RandomClass.__index = RandomClass
function RandomClass.new(seed)
	local self = setmetatable({}, RandomClass)
	self.state = math.floor(seed or 1) % 2147483647
	if self.state <= 0 then
		self.state += 2147483646
	end
	return self
end
function RandomClass:_next()
	-- Park-Miller minimal standard generator
	self.state = (self.state * 48271) % 2147483647
	return self.state / 2147483647
end
function RandomClass:NextNumber(min, max)
	local lo, hi = min or 0, max or 1
	return lo + (hi - lo) * self:_next()
end
function RandomClass:NextInteger(min, max)
	return min + math.floor(self:_next() * (max - min + 1))
end

-- Stand-ins for engine services Lune doesn't simulate.
local function fakeTween()
	return {
		Play = function() end,
		Cancel = function() end,
		Completed = { Connect = function() end, Once = function() end, Wait = function() end },
	}
end

function World:environment(scriptInstance)
	local world = self
	local base = getfenv(0)
	local env = {
		game = self.game,
		workspace = self.workspace,
		script = scriptInstance,
		task = task,
		Random = RandomClass,
		CFrame = CFrameShim,
		warn = function(...)
			table.insert(world.warnings, table.concat({ ... }, " "))
		end,
		require = function(target)
			if typeof(target) == "Instance" then
				return world:requireInstance(target)
			end
			error("harness require only supports ModuleScript instances, got " .. tostring(target))
		end,
	}
	-- Lune copies the environment table (a metatable fallback is ignored),
	-- so every Roblox type has to be placed in it directly
	for key, value in roblox do
		if env[key] == nil then
			env[key] = value
		end
	end
	for key, value in base do
		if env[key] == nil then
			env[key] = value
		end
	end
	return env
end

function World:requireInstance(module)
	if self.cache[module] ~= nil then
		return self.cache[module]
	end
	assert(module.ClassName == "ModuleScript", module:GetFullName() .. " is not a ModuleScript")
	local chunk = luau.load(module.Source, {
		debugName = module:GetFullName(),
		environment = self:environment(module),
	})
	local result = chunk()
	self.cache[module] = result
	return result
end

-- world:require("ServerScriptService.Server.Lib.MapBuilder")
function World:require(path)
	local node = self.game
	for part in path:gmatch("[^%.]+") do
		local nextNode = if node == self.game
			then self.game:GetService(part)
			else node:FindFirstChild(part)
		assert(nextNode, "harness: no " .. part .. " under " .. node:GetFullName())
		node = nextNode
	end
	return self:requireInstance(node)
end

-- In Roblox, Position is just a view of CFrame. Lune stores them as two
-- separate properties, so after code runs, fold any Position that was set
-- into the CFrame (keeping its rotation). Game code never sets both.
function World:normalizeParts()
	local zero = roblox.Vector3.new(0, 0, 0)
	for _, inst in self.game:GetDescendants() do
		if inst:IsA("BasePart") and inst.ClassName ~= "Terrain" then
			-- reading an unset Position errors in Lune; unset means "use CFrame"
			local ok, position = pcall(function()
				return inst.Position
			end)
			if ok and position ~= zero and inst.CFrame.Position == zero then
				inst.CFrame = roblox.CFrame.new(position) * inst.CFrame.Rotation
			end
		end
	end
end

World.fakeTween = fakeTween

return World
