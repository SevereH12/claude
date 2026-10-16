--!strict
-- Makes sure Workspace.Map exists. If you've saved a map into the place
-- (see Lib/MapBuilder.luau), it's left alone.

local ServerScriptService = game:GetService("ServerScriptService")

local MapBuilder = require(ServerScriptService.Server.Lib.MapBuilder)

local Map = {}

-- Runs in the init phase so the map exists before any system's start().
function Map.init()
	if not workspace:FindFirstChild("Map") then
		MapBuilder.build()
	end
end

local function child(path: { string }): Instance?
	local current: Instance? = workspace:FindFirstChild("Map")
	for _, name in path do
		current = current and current:FindFirstChild(name)
	end
	return current
end

function Map.sellPad(): BasePart?
	local pad = child({ "PowerPlant", "SellPad" })
	return if pad and pad:IsA("BasePart") then pad else nil
end

return Map
