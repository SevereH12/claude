--!strict
-- Gives every player the Bottle tool. Catching only works while it's
-- equipped (an equipped Tool is parented to the character).

local Players = game:GetService("Players")

local Bottles = {}

local TOOL_NAME = "Bottle"

local function makeTool(): Tool
	local tool = Instance.new("Tool")
	tool.Name = TOOL_NAME
	tool.ToolTip = "Hold me in a storm!"
	tool.CanBeDropped = false
	tool.RequiresHandle = true

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1, 1.6, 1)
	handle.Material = Enum.Material.Glass
	handle.Transparency = 0.3
	handle.Color = Color3.fromRGB(170, 220, 255)
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool

	local cork = Instance.new("Part")
	cork.Name = "Cork"
	cork.Size = Vector3.new(0.6, 0.3, 0.6)
	cork.Material = Enum.Material.Wood
	cork.Color = Color3.fromRGB(150, 110, 70)
	cork.CanCollide = false
	cork.Massless = true
	cork.CFrame = handle.CFrame * CFrame.new(0, 0.95, 0)
	cork.Parent = tool

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = cork
	weld.Parent = handle

	-- glows brighter as the bottle fills (set by the client's FX controller)
	local light = Instance.new("PointLight")
	light.Name = "Glow"
	light.Color = Color3.fromRGB(150, 200, 255)
	light.Range = 6
	light.Brightness = 0
	light.Parent = handle

	return tool
end

local function hasBottle(container: Instance?): boolean
	return container ~= nil and container:FindFirstChild(TOOL_NAME) ~= nil
end

local function give(player: Player)
	-- StarterGear is copied into the Backpack on every respawn
	local starterGear = player:WaitForChild("StarterGear", 10)
	if starterGear and not hasBottle(starterGear) then
		makeTool().Parent = starterGear
	end
	-- and the current life, in case they already spawned
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack and not hasBottle(backpack) and not hasBottle(player.Character) then
		makeTool().Parent = backpack
	end
end

function Bottles.start()
	Players.PlayerAdded:Connect(give)
	for _, player in Players:GetPlayers() do
		task.spawn(give, player)
	end
end

return Bottles
