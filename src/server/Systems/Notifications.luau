--!strict
-- Phone notifications: Roblox experience notifications (the rules are
-- Util/Notifications; the settings are Config.NOTIFICATIONS).
--   * Asking: after a daily reward claim, a player who's never been asked
--     gets "Remind me when my daily reward is ready?" (the NotifyOptIn
--     remote; Controllers/RewardsUI shows it, and YES opens Roblox's own
--     ExperienceNotificationService:PromptOptIn). Asked once, ever.
--   * Queueing: when a player who was asked leaves, "daily reward ready"
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

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local NotifyRules = require(ReplicatedStorage.Shared.Util.Notifications)
local Types = require(ReplicatedStorage.Shared.Types)
local PlayerData = require(script.Parent.PlayerData)
local Rewards = require(script.Parent.Rewards)
local Sync = require(script.Parent.Sync)

local SETTINGS = Config.NOTIFICATIONS
local URL = "https://apis.roblox.com/cloud/v2/users/%d/notifications"
local DAY = 86400
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

-- Sends one reminder. True if Roblox took it (or it can never work, so
-- there's no point keeping it).
local function send(userId: number, kind: string): boolean
	local secret, problem = setupProblem(kind)
	if not secret then
		logOnce(
			`setup:{kind}`,
			`not sending "{kind}" reminders: {problem}. See README.md, "Leaderboards and notifications"`,
			true
		)
		if RunService:IsStudio() then
			print(`[Notifications] would send "{kind}" to user {userId} (skipped: setup missing)`)
		end
		return true
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
		return false
	end
	if response.Success then
		print(`[Notifications] sent "{kind}" to user {userId}`)
	else
		-- 4xx: the key, the ids or the player (not opted in, one a day
		-- already); trying again won't help
		logOnce(
			`status:{response.StatusCode}`,
			`Roblox answered {response.StatusCode} {response.StatusMessage}: {response.Body}`
		)
	end
	return true
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
		if send(value.userId, value.kind) then
			pcall(function()
				queue:RemoveAsync(key)
			end)
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

-- The player left: queue their reminders (only if they were asked).
local function onLeaving(player: Player, profile: Types.Profile)
	if not profile.notifyAsked then
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
	if not profile.notifyAsked then
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

-- Studio TEST: queues a "daily" reminder for this player, due now; the
-- next send (within a minute) claims it and sends it, or logs why not.
function Notifications.testQueue(player: Player)
	local now = os.time()
	local item: NotifyRules.Item = {
		key = NotifyRules.key(now, player.UserId, "daily"),
		userId = player.UserId,
		kind = "daily",
		due = now,
	}
	queueItem(item)
	task.spawn(sendDue)
end

function Notifications.init()
	optInRemote = Net.get("NotifyOptIn")
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
