--!strict
-- Error reporting. Every script error, on the server (ScriptContext.Error)
-- and on players' devices (Controllers/ErrorReport sends them through the
-- ClientError remote), is grouped by its fingerprint (Util/Ops: the script
-- plus the first line of the message, numbers taken out).
--   * The first time a fingerprint is seen in this server it's sent to the
--     Creator Dashboard as the custom event "Error" (Systems/Analytics).
--   * The admin panel shows this server's most recent errors
--     (Config.ERRORS.recent), with how many times each happened.
-- Client errors are rate-limited: Config.ERRORS.perPlayer a minute per
-- player and perServer a minute for the whole server; the rest are dropped.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScriptContext = game:GetService("ScriptContext")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Ops = require(ReplicatedStorage.Shared.Util.Ops)
local Analytics = require(script.Parent.Analytics)
local RateLimit = require(ServerScriptService.Server.Lib.RateLimit)

local SETTINGS = Config.ERRORS

export type ErrorEntry = {
	fingerprint: string,
	source: string, -- "server" or "client"
	message: string, -- the first line, cut to Config.ERRORS.messageLength
	who: string, -- the player whose device it happened on ("" for the server)
	time: number, -- os.time() of the latest one
	count: number,
}

local Errors = {}

local recent: { ErrorEntry } = {} -- newest first
local reported: { [string]: boolean } = {} -- fingerprints sent to analytics
local serverWindow = Ops.newWindow(SETTINGS.perServer, 60)
local recording = false

local function firstLine(message: string): string
	local line = string.match(message, "^[^\r\n]*") or ""
	if #line > SETTINGS.messageLength then
		line = string.sub(line, 1, SETTINGS.messageLength)
	end
	return line
end

local function record(source: string, scriptName: string, message: string, player: Player?)
	if recording then
		return -- an error while recording an error: don't loop
	end
	recording = true
	local ok, err = pcall(function()
		local fingerprint = Ops.fingerprint(scriptName, message)
		local who = if player then player.Name else ""
		local entry: ErrorEntry? = nil
		for index, existing in recent do
			if existing.fingerprint == fingerprint and existing.source == source then
				entry = table.remove(recent, index)
				break
			end
		end
		if entry then
			entry.count += 1
			entry.time = os.time()
			entry.message = firstLine(message)
			entry.who = who
		else
			entry = {
				fingerprint = fingerprint,
				source = source,
				message = firstLine(message),
				who = who,
				time = os.time(),
				count = 1,
			}
		end
		table.insert(recent, 1, entry :: ErrorEntry)
		while #recent > SETTINGS.recent do
			table.remove(recent)
		end
		local key = `{source}|{fingerprint}`
		if not reported[key] then
			reported[key] = true
			Analytics.error(fingerprint, source, player)
		end
	end)
	recording = false
	if not ok then
		warn(`[Errors] couldn't record an error: {err}`)
	end
end

local function onServerError(message: string, _trace: string, origin: Instance?)
	record("server", if origin then origin:GetFullName() else "?", message, nil)
end

local function onClientError(player: Player, message: unknown, scriptName: unknown)
	if not RateLimit.allow(player, "ClientError", SETTINGS.perPlayer / 60, SETTINGS.perPlayer) then
		return
	end
	if typeof(message) ~= "string" or #message == 0 or #message > 4000 then
		return
	end
	local name = if typeof(scriptName) == "string" and #scriptName <= 200 then scriptName else "?"
	if not Ops.allow(serverWindow, os.clock()) then
		return
	end
	record("client", name, message, player)
end

-- This server's most recent errors, newest first (a copy).
function Errors.recent(): { ErrorEntry }
	local list = {}
	for _, entry in recent do
		table.insert(list, table.clone(entry))
	end
	return list
end

-- The admin panel's TEST ERROR button: a real error on the server.
function Errors.testServerError(by: Player)
	task.spawn(function()
		error(`[Admin] test error from the server (asked by {by.Name})`)
	end)
end

function Errors.init()
	ScriptContext.Error:Connect(onServerError)
	Net.get("ClientError").OnServerEvent:Connect(onClientError)
end

return Errors
