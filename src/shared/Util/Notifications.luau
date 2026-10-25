--!strict
-- The phone notification rules (Systems/Notifications uses them;
-- tools/harness/test_social.luau tests them). Pure: no Roblox services.
--
-- When a player leaves, two reminders may be queued, each keyed by when
-- it's due (so a sorted map keeps them in time order):
--   "daily": the next daily reward is ready (the start of the next UTC day
--     after their last claim). Only if they claimed today: if today's is
--     still waiting, it's ready already.
--   "streak": the login streak breaks at the end of the day after their
--     last claim; this goes Config.NOTIFICATIONS.streakWarnHours before
--     that. Only for a streak of 2 days or more.
-- Anything already due when they leave isn't queued. When they come back,
-- the same keys are worked out again and removed.
--
-- Sending: every server looks at the due items each minute. A server
-- "claims" an item before sending it (Notifications.claim, inside the
-- sorted map's atomic UpdateAsync), so only one server ever sends it.

local Config = require(script.Parent.Parent.Config)

local Notifications = {}

local DAY = 24 * 60 * 60

export type Kind = "daily" | "streak"

-- A queued reminder: the sorted map's key and value.
export type Item = {
	key: string,
	userId: number,
	kind: Kind,
	due: number, -- os.time() when it should be sent
}

-- What the sorted map stores under an item's key. claimedBy/claimedAt are
-- set by the server sending it.
export type Stored = {
	userId: number,
	kind: string,
	due: number,
	claimedBy: string?,
	claimedAt: number?,
}

-- "000001761436800|123456|daily": the due time first, padded, so the map
-- sorts by it.
function Notifications.key(due: number, userId: number, kind: Kind): string
	return string.format("%015d|%d|%s", due, userId, kind)
end

-- The sorted map's exclusive upper bound for "due at or before `now`".
function Notifications.upperBound(now: number): string
	return string.format("%015d", now + 1)
end

-- When each reminder would be due for this claim history (0 = never).
local function dueTimes(lastClaimDay: number, run: number): (number, number)
	local ready = (lastClaimDay + 1) * DAY
	local streak = (lastClaimDay + 2) * DAY - Config.NOTIFICATIONS.streakWarnHours * 3600
	return ready, if run >= 2 then streak else 0
end

-- The reminders to queue when a player leaves at `now` (os.time()), from
-- their last daily claim (UTC day number, 0 = never) and login run.
function Notifications.plan(
	userId: number,
	lastClaimDay: number,
	run: number,
	now: number
): { Item }
	local items: { Item } = {}
	if lastClaimDay <= 0 then
		return items
	end
	local ready, streak = dueTimes(lastClaimDay, run)
	local today = now // DAY
	if lastClaimDay == today and ready > now then
		local item: Item = {
			key = Notifications.key(ready, userId, "daily"),
			userId = userId,
			kind = "daily",
			due = ready,
		}
		table.insert(items, item)
	end
	if streak > now then
		local item: Item = {
			key = Notifications.key(streak, userId, "streak"),
			userId = userId,
			kind = "streak",
			due = streak,
		}
		table.insert(items, item)
	end
	return items
end

-- Every key `plan` could have queued for this claim history (to take
-- them out of the map when the player comes back).
function Notifications.keysFor(userId: number, lastClaimDay: number, run: number): { string }
	if lastClaimDay <= 0 then
		return {}
	end
	local ready, streak = dueTimes(lastClaimDay, run)
	local keys = { Notifications.key(ready, userId, "daily") }
	if streak > 0 then
		table.insert(keys, Notifications.key(streak, userId, "streak"))
	end
	return keys
end

-- Is this stored item due at `now`?
function Notifications.isDue(stored: any, now: number): boolean
	return typeof(stored) == "table" and typeof(stored.due) == "number" and stored.due <= now
end

-- The claim, run inside UpdateAsync: returns the item claimed by
-- `serverId` at `now`, or nil to leave it alone (it's gone, not due yet,
-- or a server claimed it less than `claimSeconds` ago). A claim older
-- than that belongs to a server that stopped; it can be taken over.
function Notifications.claim(old: any, serverId: string, now: number, claimSeconds: number): Stored?
	if not Notifications.isDue(old, now) or typeof(old.userId) ~= "number" then
		return nil
	end
	if
		typeof(old.claimedBy) == "string"
		and typeof(old.claimedAt) == "number"
		and now - old.claimedAt < claimSeconds
	then
		return nil -- a server (maybe this one) is sending it
	end
	return {
		userId = old.userId,
		kind = old.kind,
		due = old.due,
		claimedBy = serverId,
		claimedAt = now,
	}
end

-- Did this server win the claim? (`result` is what UpdateAsync returned.)
function Notifications.won(result: any, serverId: string, now: number): boolean
	return typeof(result) == "table" and result.claimedBy == serverId and result.claimedAt == now
end

-- The notification string's asset id for a kind ("" = not set up).
function Notifications.messageId(kind: string): string
	if kind == "daily" then
		return Config.NOTIFICATIONS.dailyReadyMessageId
	elseif kind == "streak" then
		return Config.NOTIFICATIONS.streakEndingMessageId
	end
	return ""
end

-- The Open Cloud request body (CreateUserNotification) for one reminder.
function Notifications.body(universeId: number, kind: string): { [string]: any }
	return {
		source = { universe = `universes/{universeId}` },
		payload = { message_id = Notifications.messageId(kind), type = "MOMENT" },
		join_experience = { launch_data = `notify:{kind}` },
		analytics_data = { category = if kind == "daily" then "DailyReady" else "StreakEnding" },
	}
end

return Notifications
