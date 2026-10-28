--!strict
-- Storm Bottler Simulator server entry point. Two-phase bootstrap: init() every
-- system, then start() every system.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

-- Remotes must exist before any system or client looks for them.
Net.createAll()

local Systems = script:FindFirstChild("Systems")

-- Every system is loaded, then init()ed, then start()ed, in name order (so
-- it's the same every time). Loading and init() are wrapped in pcall: one
-- broken system is reported with its name (as an error in its own thread,
-- so Systems/Errors still sees it) and the rest still run. Each start()
-- already runs in its own thread, so an error there stops only that system.
local function report(message: string)
	task.defer(error, message, 0) -- after every init(), so Systems/Errors is listening
end

local names: { string } = {}
local loaded: { [string]: any } = {}
if Systems then
	for _, child in Systems:GetChildren() do
		if child:IsA("ModuleScript") then
			local ok, result = pcall(require :: any, child)
			if ok then
				loaded[child.Name] = result
				table.insert(names, child.Name)
			else
				report(`[StormBottler] system {child.Name} failed to load: {result}`)
			end
		end
	end
end
table.sort(names)

for _, name in names do
	local system = loaded[name]
	if typeof(system) == "table" and typeof(system.init) == "function" then
		local ok, err = pcall(system.init)
		if not ok then
			report(`[StormBottler] system {name} failed to init: {err}`)
		end
	end
end

for _, name in names do
	local system = loaded[name]
	if typeof(system) == "table" and typeof(system.start) == "function" then
		task.spawn(system.start)
	end
end

print("[StormBottler] server started")
