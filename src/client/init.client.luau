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

-- one controller failing to set up must not stop the others (the shop
-- once stayed blank that way), so each init is caught and reported
for name, controller in loaded do
	if typeof(controller.init) == "function" then
		local ok, err = pcall(controller.init)
		if not ok then
			warn(`[StormBottler] {name}.init failed: {err}`)
			-- tell the server too (Controllers/ErrorReport), if it's set up
			local reporter = loaded.ErrorReport
			if reporter and typeof(reporter.report) == "function" then
				pcall(reporter.report, name, `{name}.init failed: {err}`)
			end
		end
	end
end

for _, controller in loaded do
	if typeof(controller.start) == "function" then
		task.spawn(controller.start)
	end
end

print("[StormBottler] client started")
