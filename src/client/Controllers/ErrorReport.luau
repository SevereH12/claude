--!strict
-- Sends this device's script errors to the server (the ClientError remote,
-- Systems/Errors), which groups them and puts new ones on the Creator
-- Dashboard and in the admin panel. At most Config.ERRORS.perPlayer a
-- minute are sent (the server limits it again).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScriptContext = game:GetService("ScriptContext")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Ops = require(ReplicatedStorage.Shared.Util.Ops)

local ErrorReport = {}

local remote: RemoteEvent? = nil
local window = Ops.newWindow(Config.ERRORS.perPlayer, 60)

-- Report one error (also used by the client entry script for a controller
-- whose init failed, which a pcall hides from ScriptContext.Error).
function ErrorReport.report(scriptName: string, message: string)
	if not Ops.allow(window, os.clock()) then
		return
	end
	local events = remote or Net.get("ClientError")
	remote = events
	events:FireServer(string.sub(message, 1, 2000), string.sub(scriptName, 1, 200))
end

function ErrorReport.init()
	remote = Net.get("ClientError")
	ScriptContext.Error:Connect(function(message: string, _trace: string, origin: Instance?)
		ErrorReport.report(if origin then origin.Name else "?", message)
	end)
end

return ErrorReport
