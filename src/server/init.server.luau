--!strict
-- ClickSimulator server entry point. Two-phase bootstrap: init() every
-- system, then start() every system.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

-- Remotes must exist before any system or client looks for them.
Net.createAll()

local Systems = script:FindFirstChild("Systems")

local loaded: { [string]: any } = {}
if Systems then
	for _, child in Systems:GetChildren() do
		if child:IsA("ModuleScript") then
			loaded[child.Name] = (require :: any)(child)
		end
	end
end

for _, system in loaded do
	if typeof(system.init) == "function" then
		system.init()
	end
end

for _, system in loaded do
	if typeof(system.start) == "function" then
		task.spawn(system.start)
	end
end

print("[ClickSimulator] server started")
