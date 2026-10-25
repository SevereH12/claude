--!strict
-- The rules behind the admin panel and error reporting, kept free of Roblox
-- services so tools/harness/test_ops.luau can test them:
--   * isAdmin: who may use the admin panel (Config.ADMIN_RANK)
--   * fingerprint: a short name for an error, so the same bug seen many
--     times counts as one (script name + the first line of the message,
--     with numbers and player names taken out)
--   * cleanReason, banLabel, summary: small helpers for the panel
--   * newWindow / allow: "at most N per minute" counters

local Config = require(script.Parent.Parent.Config)

local Ops = {}

-- What the server knows about a player when it decides if they're an admin.
export type AdminFacts = {
	studio: boolean, -- a Studio play test: everyone is an admin
	userId: number,
	placeOwnerId: number?, -- the user who owns the place (a user-owned place)
	groupOwnerId: number?, -- the owner of Config.GROUP_ID
	rank: number?, -- their rank in Config.GROUP_ID (0 = not in it)
}

function Ops.isAdmin(facts: AdminFacts): boolean
	if facts.studio then
		return true
	end
	if facts.userId <= 0 then
		return false -- guests and test players
	end
	if facts.placeOwnerId ~= nil and facts.userId == facts.placeOwnerId then
		return true
	end
	if facts.groupOwnerId ~= nil and facts.userId == facts.groupOwnerId then
		return true
	end
	return (facts.rank or 0) >= Config.ADMIN_RANK
end

local FINGERPRINT_LENGTH = 100

-- "Controllers.Shop: attempt to index nil with 'Price'" from a script name
-- and a full error message. Two errors with the same fingerprint are the
-- same bug: line numbers, counts and ids are removed, and so are player
-- names in paths (a client script lives under Players.<name>).
function Ops.fingerprint(scriptName: string, message: string): string
	local line = string.match(message, "^[^\r\n]*") or ""
	-- Players.Henry.PlayerScripts... -> PlayerScripts...
	line = string.gsub(line, "Players%.[^%.%s]+%.", "")
	-- the script path and line number at the start ("A.B.C:12: ")
	line = string.gsub(line, "^[%w_%.%s]+:%d+:%s*", "")
	line = string.gsub(line, "%d+", "")
	line = string.gsub(line, "%s+", " ")
	line = string.match(line, "^%s*(.-)%s*$") or line
	local name = string.match(scriptName, "[^%.]+$") or scriptName
	if name == "" then
		name = "?"
	end
	local result = `{name}: {line}`
	if #result > FINGERPRINT_LENGTH then
		result = string.sub(result, 1, FINGERPRINT_LENGTH)
	end
	return result
end

-- A kick or ban reason: one line, trimmed, at most Config.ADMIN.reasonLength
-- characters. nil if it isn't text.
function Ops.cleanReason(reason: unknown): string?
	if typeof(reason) ~= "string" then
		return nil
	end
	local text = string.gsub(reason, "[%c]", " ")
	text = string.match(text, "^%s*(.-)%s*$") or ""
	if #text > Config.ADMIN.reasonLength then
		text = string.sub(text, 1, Config.ADMIN.reasonLength)
	end
	return text
end

-- A username (3-20 letters, digits or _) or a user id typed as digits.
-- Returns the cleaned name and the id (if digits were typed).
function Ops.parseTarget(text: unknown): (string?, number?)
	if typeof(text) ~= "string" then
		return nil, nil
	end
	local trimmed = string.match(text, "^%s*(.-)%s*$") or ""
	if string.match(trimmed, "^%d+$") and #trimmed <= 15 then
		local id = tonumber(trimmed)
		if id and id > 0 then
			return trimmed, id
		end
		return nil, nil
	end
	if string.match(trimmed, "^[%w_]+$") and #trimmed >= 3 and #trimmed <= 20 then
		return trimmed, nil
	end
	return nil, nil
end

-- "1 hour", "7 days", "forever" for a ban length in seconds.
function Ops.banLabel(seconds: number): string
	if seconds < 0 then
		return "forever"
	elseif seconds % 86400 == 0 then
		local days = seconds // 86400
		return if days == 1 then "1 day" else `{days} days`
	elseif seconds % 3600 == 0 then
		local hours = seconds // 3600
		return if hours == 1 then "1 hour" else `{hours} hours`
	end
	return `{seconds} s`
end

function Ops.isBanLength(seconds: unknown): boolean
	return typeof(seconds) == "number" and table.find(Config.ADMIN.banSeconds, seconds) ~= nil
end

-- A saved profile as "key: value" lines, sorted, for the read-only lookup:
-- numbers, text and true/false as they are, tables as their entry count.
function Ops.summary(profile: { [string]: any }, maxLines: number): { string }
	local keys = {}
	for key in profile do
		if typeof(key) == "string" then
			table.insert(keys, key)
		end
	end
	table.sort(keys)
	local lines = {}
	for _, key in keys do
		local value = profile[key]
		local shown
		if typeof(value) == "table" then
			local count = 0
			for _ in value do
				count += 1
			end
			shown = `{count} entries`
		elseif typeof(value) == "string" then
			shown = if #value > 40 then string.sub(value, 1, 40) .. "..." else value
		else
			shown = tostring(value)
		end
		table.insert(lines, `{key}: {shown}`)
		if #lines >= maxLines then
			break
		end
	end
	return lines
end

-- "At most `limit` in any `seconds`" (a fixed window that restarts).
export type Window = { start: number, count: number, limit: number, seconds: number }

function Ops.newWindow(limit: number, seconds: number): Window
	return { start = -math.huge, count = 0, limit = limit, seconds = seconds }
end

-- True (and counts it) if one more fits in the window at time `now`.
function Ops.allow(window: Window, now: number): boolean
	if now - window.start >= window.seconds then
		window.start = now
		window.count = 0
	end
	if window.count >= window.limit then
		return false
	end
	window.count += 1
	return true
end

return Ops
