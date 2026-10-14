--!strict
-- Storm Bottler Simulator client entry point. Same two-phase bootstrap as the server.

-- make sure ReplicatedStorage has fully arrived before any controller
-- requires shared modules
if not game:IsLoaded() then
	game.Loaded:Wait()
end

local Controllers = script:FindFirstChild("Controllers")

local loaded: { [string]: any } = {}
if Controllers then
	for _, child in Controllers:GetChildren() do
		if child:IsA("ModuleScript") then
			loaded[child.Name] = (require :: any)(child)
		end
	end
end

for _, controller in loaded do
	if typeof(controller.init) == "function" then
		controller.init()
	end
end

for _, controller in loaded do
	if typeof(controller.start) == "function" then
		task.spawn(controller.start)
	end
end

print("[StormBottler] client started")
