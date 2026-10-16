--!strict
-- Storm Bottler Updater: a Roblox Studio plugin with one button.
--
-- "Update Game" downloads the latest game code from GitHub and puts it into
-- the open place, exactly like Rojo would (same layout as default.project.json):
--   src/shared -> ReplicatedStorage.Shared
--   src/server -> ServerScriptService.Server   (init.server.luau = Script)
--   src/client -> StarterPlayerScripts.Client  (init.client.luau = LocalScript)
-- then rebuilds the map if it was built by MapBuilder (Map has AutoBuilt = true).
--
-- Everything happens in one undo step (Ctrl+Z undoes the whole update).

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local OWNER = "SevereH12"
local REPO = "claude"
local BRANCH = "claude/sweet-planck-ea1ob4"
local API = `https://api.github.com/repos/{OWNER}/{REPO}`
local RAW = `https://raw.githubusercontent.com/{OWNER}/{REPO}`
local PARALLEL_DOWNLOADS = 8

type Root = { prefix: string, parent: Instance, name: string }
type FileMap = { [string]: string } -- relative path -> source

-- UI ------------------------------------------------------------------------

local toolbar = plugin:CreateToolbar("Storm Bottler")
local button = toolbar:CreateButton(
	"StormBottlerUpdate",
	"Download the latest Storm Bottler game code from GitHub into this place",
	"",
	"Update Game"
)
button.ClickableWhenViewportHidden = true

local widgetInfo =
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, true, 360, 150, 300, 120)
local widgetOk, widgetResult = pcall(function()
	return plugin:CreateDockWidgetPluginGuiAsync("StormBottlerUpdater", widgetInfo)
end)
local widget: DockWidgetPluginGui = if widgetOk
	then widgetResult
	else (plugin :: any):CreateDockWidgetPluginGui("StormBottlerUpdater", widgetInfo)
widget.Title = "Storm Bottler Updater"

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.fromScale(1, 1)
statusLabel.BackgroundColor3 = Color3.fromRGB(30, 34, 54)
statusLabel.TextColor3 = Color3.new(1, 1, 1)
statusLabel.Font = Enum.Font.BuilderSansBold
statusLabel.TextSize = 18
statusLabel.TextWrapped = true
statusLabel.Text = "Click Update Game to download the latest version."
statusLabel.Parent = widget
local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 12)
padding.PaddingRight = UDim.new(0, 12)
padding.Parent = statusLabel

local function status(text: string, color: Color3?)
	statusLabel.Text = text
	statusLabel.TextColor3 = color or Color3.new(1, 1, 1)
	print(`[StormBottlerUpdater] {text}`)
end

-- Download ------------------------------------------------------------------

local function get(url: string): string
	local response = HttpService:RequestAsync({ Url = url, Method = "GET" })
	if not response.Success or not response.Body then
		error(`HTTP {response.StatusCode} {response.StatusMessage} ({url})`, 0)
	end
	return response.Body
end

local function latestCommit(): string
	local commit = HttpService:JSONDecode(get(`{API}/commits/{BRANCH}`))
	return commit.sha
end

local function listSourceFiles(sha: string): { string }
	local tree = HttpService:JSONDecode(get(`{API}/git/trees/{sha}?recursive=1`))
	local paths: { string } = {}
	for _, entry in tree.tree do
		if
			entry.type == "blob"
			and entry.path:sub(1, 4) == "src/"
			and entry.path:sub(-5) == ".luau"
		then
			table.insert(paths, entry.path)
		end
	end
	return paths
end

-- Downloads every file, a few at a time. Returns path -> source.
local function downloadAll(sha: string, paths: { string }): FileMap
	local sources: FileMap = {}
	local failure: string? = nil
	local nextIndex = 1
	local done = 0

	local function worker()
		while nextIndex <= #paths and not failure do
			local path = paths[nextIndex]
			nextIndex += 1
			local ok, result = pcall(get, `{RAW}/{sha}/{path}`)
			if ok then
				sources[path] = result
			else
				failure = tostring(result)
			end
			done += 1
			status(`Downloading scripts... {done}/{#paths}`)
		end
	end

	for _ = 1, math.min(PARALLEL_DOWNLOADS, #paths) do
		task.spawn(worker)
	end
	while done < #paths and not failure do
		task.wait(0.05)
	end
	if failure then
		error(failure, 0)
	end
	return sources
end

-- Build ---------------------------------------------------------------------

local function scriptClass(fileName: string): (string, string)
	if fileName:sub(-12) == ".server.luau" then
		return "Script", fileName:sub(1, -13)
	elseif fileName:sub(-12) == ".client.luau" then
		return "LocalScript", fileName:sub(1, -13)
	end
	return "ModuleScript", fileName:sub(1, -6)
end

-- Builds one folder of files into an instance, the way Rojo does: a folder
-- with init.server.luau becomes a Script, init.client.luau a LocalScript,
-- init.luau a ModuleScript; otherwise it's a Folder.
local function buildDirectory(name: string, files: FileMap): Instance
	local className, source = "Folder", nil
	if files["init.server.luau"] then
		className, source = "Script", files["init.server.luau"]
	elseif files["init.client.luau"] then
		className, source = "LocalScript", files["init.client.luau"]
	elseif files["init.luau"] then
		className, source = "ModuleScript", files["init.luau"]
	end
	local node = Instance.new(className :: any)
	node.Name = name
	if source then
		(node :: any).Source = source
	end

	local subdirectories: { [string]: FileMap } = {}
	for relative, fileSource in files do
		local slash = relative:find("/", 1, true)
		if slash then
			local directory = relative:sub(1, slash - 1)
			local inner = subdirectories[directory] or {}
			inner[relative:sub(slash + 1)] = fileSource
			subdirectories[directory] = inner
		elseif
			relative ~= "init.server.luau"
			and relative ~= "init.client.luau"
			and relative ~= "init.luau"
		then
			local childClass, childName = scriptClass(relative)
			local child = Instance.new(childClass :: any)
			child.Name = childName;
			(child :: any).Source = fileSource
			child.Parent = node
		end
	end
	for directory, inner in subdirectories do
		buildDirectory(directory, inner).Parent = node
	end
	return node
end

local function roots(): { Root }
	-- every place has this; it can't be created by scripts
	local playerScripts = StarterPlayer:WaitForChild("StarterPlayerScripts")
	return {
		{ prefix = "src/shared/", parent = ReplicatedStorage, name = "Shared" },
		{ prefix = "src/server/", parent = ServerScriptService, name = "Server" },
		{ prefix = "src/client/", parent = playerScripts, name = "Client" },
	}
end

local function install(sources: FileMap): number
	local count = 0
	for _, root in roots() do
		local files: FileMap = {}
		for path, source in sources do
			if path:sub(1, #root.prefix) == root.prefix then
				files[path:sub(#root.prefix + 1)] = source
				count += 1
			end
		end
		local built = buildDirectory(root.name, files)
		local old = root.parent:FindFirstChild(root.name)
		if old then
			old:Destroy()
		end
		built.Parent = root.parent
	end
	return count
end

-- Rebuild the map unless someone has hand-edited it (AutoBuilt removed).
local function rebuildMap(): string
	local map = workspace:FindFirstChild("Map")
	if map and map:GetAttribute("AutoBuilt") ~= true then
		return "Map kept (it's marked as hand-edited)."
	end
	local server = ServerScriptService:FindFirstChild("Server")
	local lib = server and server:FindFirstChild("Lib")
	local builder = lib and lib:FindFirstChild("MapBuilder")
	if not builder or not builder:IsA("ModuleScript") then
		return "No MapBuilder found; map not built."
	end
	-- require a fresh copy so we never get a cached old version
	local copy = builder:Clone()
	copy.Parent = ServerStorage
	local ok, err = pcall(function()
		(require :: any)(copy).build()
	end)
	copy:Destroy()
	if not ok then
		error(`Map build failed: {err}`, 0)
	end
	return "Map rebuilt."
end

-- Update --------------------------------------------------------------------

local busy = false

local function update()
	if busy then
		return
	end
	if RunService:IsRunning() then
		status("Stop the playtest first, then click Update Game.", Color3.fromRGB(255, 200, 80))
		return
	end
	busy = true
	widget.Enabled = true

	local recording =
		ChangeHistoryService:TryBeginRecording("StormBottlerUpdate", "Update Storm Bottler")
	local ok, err = pcall(function()
		status("Checking GitHub for the latest version...")
		local sha = latestCommit()
		local paths = listSourceFiles(sha)
		if #paths == 0 then
			error("No game files found on GitHub.", 0)
		end
		local sources = downloadAll(sha, paths)
		status("Installing scripts...")
		local count = install(sources)
		status("Building the map...")
		local mapNote = rebuildMap()
		plugin:SetSetting("lastVersion", sha)
		status(
			`Updated to version {sha:sub(1, 7)}: {count} scripts. {mapNote}\nPress Ctrl+S to save, then Play!`,
			Color3.fromRGB(120, 230, 140)
		)
	end)
	if recording then
		ChangeHistoryService:FinishRecording(
			recording,
			if ok
				then Enum.FinishRecordingOperation.Commit
				else Enum.FinishRecordingOperation.Cancel
		)
	end
	if not ok then
		local message = tostring(err)
		local hint = if message:lower():find("http") and message:find("404")
			then "\nIs the GitHub repo public?"
			elseif
				message:lower():find("permission")
				or message:lower():find("not enabled")
				or message:lower():find("denied")
			then "\nAllow the web access popup, then click Update Game again."
			else ""
		status(`Update failed: {message}{hint}`, Color3.fromRGB(255, 110, 110))
	end
	busy = false
end

button.Click:Connect(function()
	task.spawn(update)
end)
