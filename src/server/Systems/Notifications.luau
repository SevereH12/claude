--!strict
-- Phone notifications: Roblox experience notifications (the rules are
-- Util/Notifications; the settings are Config.NOTIFICATIONS).
--   * Asking: after a daily reward claim, a player who's never been asked
--     gets "Remind me when my daily reward is ready?" (the NotifyOptIn
--     remote; Controllers/RewardsUI shows it, and YES opens Roblox's own
--     ExperienceNotificationService:PromptOptIn). Asked once, ever. YES
--     comes back on the same remote and is saved (profile.notifyYes).
--   * Only players who tapped YES get reminders queued (Roblox would drop
--     the rest anyway, but each costs a MemoryStore write and a call).
--   * Queueing: when a player who said YES leaves, "daily reward ready"
--     and "streak ends soon" are put in a MemoryStore sorted map, keyed by
--     when they're due. When they come back, those are taken out again.
--   * Sending: every server looks for due items each minute and claims each
--     one atomically (UpdateAsync) before sending it, so it's sent once.
--     It's sent with Open Cloud's CreateUserNotification
--     (POST https://apis.roblox.com/cloud/v2/users/<id>/notifications),
--     which game servers may call through HttpService with an API key from
--     HttpService:GetSecret. Roblox only delivers to players who opted in
--     (13+), at most one a day per game.
-- Setup (see README.md): the API key as secret Config.NOTIFICATIONS.
-- secretName, and the two notification strings' ids in Config. Until
-- they're set, nothing is sent: the log says what's missing, once.
-- Every step is logged ("[Notifications] ..."), since Studio can't send.

local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local NotifyRules = require(ReplicatedStorage.Shared.Util.Notifications)
local Types = require(ReplicatedStorage.Shared.Types)
local PlayerData = require(script.Parent.PlayerData)
local Rewards = require(script.Parent.Rewards)
local Sync = require(script.Parent.Sync)
local RateLimit = require(ServerScriptService.Server.Lib.RateLimit)

local SETTINGS = Config.NOTIFICATIONS
local URL = "https://apis.roblox.com/cloud/v2/users/%d/notifications"
local DAY = 86400
local TEST_EVERY = 60 -- seconds between an admin's TEST NOTIFY presses
local SERVER_ID = if game.JobId ~= ""
	then game.JobId
	else `studio-{HttpService:GenerateGUID(false)}`

local Notifications = {}

local optInRemote: RemoteEvent
local map: MemoryStoreSortedMap? = nil
local warned: { [string]: boolean } = {}
local queueing = 0 -- reminders still being queued (a closing server waits for them)

-- Logs a problem once per server (setup that's simply missing is printed,
-- not warned: it isn't an error until the user sets it up).
local function logOnce(key: string, message: string, quiet: boolean?)
	if not warned[key] then
		warned[key] = true
		if quiet then
			print(`[Notifications] {message}`)
		else
			warn(`[Notifications] {message}`)
		end
	end
end

local function getMap(): MemoryStoreSortedMap?
	if map then
		return map
	end
	local ok, result = pcall(function()
		return MemoryStoreService:GetSortedMap(SETTINGS.mapName)
	end)
	if not ok then
		logOnce("map", `can't open the MemoryStore queue: {result}`)
		return nil
	end
	map = result
	return result
end

-- The API key, or nil and why not.
local function apiKey(): (Secret?, string?)
	local ok, secret = pcall(function()
		return HttpService:GetSecret(SETTINGS.secretName)
	end)
	if not ok then
		return nil,
			`the secret "{SETTINGS.secretName}" isn't set ({secret}). Add it on the Creator Dashboard (Secrets), or in Studio under File > Experience Settings > Security > Local Secrets`
	end
	return secret, nil
end

-- What's missing for sending a kind, or nil if it's all set up.
local function setupProblem(kind: string): (Secret?, string?)
	if NotifyRules.messageId(kind) == "" then
		return nil,
			`no notification string id for "{kind}" in Config.NOTIFICATIONS (create it on the Creator Dashboard: Engagement > Notifications)`
	end
	return apiKey()
end

-- What came of one send:
--   "sent"   Roblox took it
--   "drop"   it can never work (setup missing, Studio, a 4xx): don't keep it
--   "retry"  Roblox is busy (429 or 5xx) or the call failed: try again later
type Outcome = "sent" | "drop" | "retry"

-- Sends one reminder, and says what came of it (and why, for the admin
-- panel's TEST NOTIFY). The key is only ever passed to RequestAsync as the
-- Secret it is: never printed, logged or turned into a string.
local function send(userId: number, kind: string): (Outcome, string)
	if RunService:IsStudio() then
		-- secrets from the Creator Dashboard only reach live servers
		print(
			`[Notifications] Studio: would send "{kind}" to user {userId} (only live servers send)`
		)
		return "drop", "Studio can't send notifications: test it in a live server"
	end
	local secret, problem = setupProblem(kind)
	if not secret then
		logOnce(
			`setup:{kind}`,
			`not sending "{kind}" reminders: {problem}. See README.md, "Leaderboards and notifications"`,
			true
		)
		return "drop", `not set up: {problem}`
	end
	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = string.format(URL, userId),
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/json",
				["x-api-key"] = secret,
			} :: any,
			Body = HttpService:JSONEncode(NotifyRules.body(game.GameId, kind)),
		})
	end)
	if not ok then
		logOnce(
			"http",
			`sending failed: {response}. Is "Allow HTTP Requests" on (Game Settings > Security)?`
		)
		return "retry", `the request failed: {response}`
	end
	if response.Success then
		print(`[Notifications] sent "{kind}" to user {userId}`)
		return "sent", `sent "{kind}" to user {userId}`
	end
	local code = response.StatusCode
	local answer = `Roblox answered {code} {response.StatusMessage}: {response.Body}`
	logOnce(`status:{code}`, answer)
	if code == 429 or code >= 500 then
		return "retry", answer
	end
	-- other 4xx: the key, the ids or the player (not opted in, one a day
	-- already); trying again won't help
	return "drop", answer
end

-- Claims, sends and removes every due item (a batch at a time).
local function sendDue()
	local queue = getMap()
	if not queue then
		return
	end
	local now = os.time()
	local ok, items = pcall(function()
		return queue:GetRangeAsync(
			Enum.SortDirection.Ascending,
			SETTINGS.batch,
			nil,
			NotifyRules.upperBound(now)
		)
	end)
	if not ok then
		logOnce("range", `reading the queue failed: {items}`)
		return
	end
	for _, item in items do
		local key = item.key
		local won = false
		local claimed = pcall(function()
			local result = queue:UpdateAsync(key, function(old: any): any
				return NotifyRules.claim(old, SERVER_ID, now, SETTINGS.claimSeconds)
			end, SETTINGS.claimSeconds * 2)
			won = NotifyRules.won(result, SERVER_ID, now)
		end)
		if not claimed or not won then
			continue -- another server has it
		end
		local value = item.value
		local outcome = send(value.userId, value.kind)
		if outcome ~= "retry" then
			pcall(function()
				queue:RemoveAsync(key)
			end)
		else
			-- Roblox is busy: the claim runs out and the rest wait for the
			-- next pass (or another server)
			break
		end
	end
end

-- Puts one reminder in the queue.
local function queueItem(item: NotifyRules.Item)
	local queue = getMap()
	if not queue then
		return
	end
	local stored: NotifyRules.Stored = { userId = item.userId, kind = item.kind, due = item.due }
	-- kept until a day after it's due (MemoryStore keeps items 45 days at most)
	local expiry = math.clamp(item.due - os.time() + DAY, 60, 45 * DAY)
	local ok, err = pcall(function()
		queue:SetAsync(item.key, stored, expiry)
	end)
	if ok then
		print(
			`[Notifications] queued "{item.kind}" for user {item.userId}, due in {item.due - os.time()} s`
		)
	else
		logOnce("queue", `queueing failed: {err}`)
	end
end

-- The player left: queue their reminders (only if they said YES).
local function onLeaving(player: Player, profile: Types.Profile)
	if not profile.notifyYes then
		return
	end
	local items = NotifyRules.plan(player.UserId, profile.lastDailyDay, profile.loginRun, os.time())
	for _, item in items do
		queueing += 1
		task.spawn(function()
			queueItem(item)
			queueing -= 1
		end)
	end
end

-- The player is back: their reminders aren't needed.
local function onLoaded(player: Player, profile: Types.Profile)
	if not profile.notifyYes then
		return
	end
	local queue = getMap()
	if not queue then
		return
	end
	for _, key in NotifyRules.keysFor(player.UserId, profile.lastDailyDay, profile.loginRun) do
		task.spawn(function()
			pcall(function()
				queue:RemoveAsync(key)
			end)
		end)
	end
end

-- After a daily claim: ask about reminders, once ever.
local function onDailyClaimed(player: Player, profile: Types.Profile)
	if profile.notifyAsked then
		return
	end
	profile.notifyAsked = true
	Sync.markDirty(player)
	optInRemote:FireClient(player)
	print(`[Notifications] asked {player.Name} about daily reminders`)
end

-- The client says YES was tapped on the question (rate-limited; only
-- after the server asked).
local function onYes(player: Player)
	if not RateLimit.allow(player, "NotifyOptIn", 0.2, 2) then
		return
	end
	local profile = PlayerData.get(player)
	if not profile or not profile.notifyAsked or profile.notifyYes then
		return
	end
	profile.notifyYes = true
	Sync.markDirty(player)
	print(`[Notifications] {player.Name} said yes to daily reminders`)
end

-- The admin panel's TEST NOTIFY (Systems/Admin checks it's an admin):
-- sends a "daily reward ready" to that admin straight away, once a minute
-- at most. Roblox only delivers it if they've allowed this game's
-- notifications, and at most one a day.
local lastTest: { [number]: number } = {}
function Notifications.sendTest(player: Player): (boolean, string)
	local now = os.clock()
	local last = lastTest[player.UserId]
	if last and now - last < TEST_EVERY then
		return false, `wait {math.ceil(TEST_EVERY - (now - last))} s before another test`
	end
	lastTest[player.UserId] = now
	local outcome, note = send(player.UserId, "daily")
	return outcome == "sent", note
end

function Notifications.init()
	optInRemote = Net.get("NotifyOptIn")
	optInRemote.OnServerEvent:Connect(onYes)
	Rewards.DailyClaimed:Connect(onDailyClaimed)
	PlayerData.Loaded:Connect(onLoaded)
	PlayerData.Leaving:Connect(onLeaving)
	game:BindToClose(function()
		local deadline = os.clock() + 10
		while queueing > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
	local _, problem = setupProblem("daily")
	if problem then
		logOnce(
			"setup:daily",
			`not sending "daily" reminders: {problem}. See README.md, "Leaderboards and notifications"`,
			true
		)
	end
end

function Notifications.start()
	while true do
		task.wait(SETTINGS.sendEverySeconds)
		sendDue()
	end
end

return Notifications
