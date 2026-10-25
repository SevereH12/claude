--!strict
-- Storm surprises as pure maths (tools/harness/test_weather.luau tests this):
-- which rare bolt a strike is (Config.BOLT_TYPES), when the next Supercell
-- comes (Config.SUPERCELL) and which scheduled events are on
-- (Config.EVENTS). Systems/Strikes, Systems/StormCycle and Systems/Passes
-- use it on the server; the HUD uses it to show the event chip.

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)
local Passes = require(script.Parent.Passes)

local DAY = 24 * 60 * 60
local WEEK = 7 * DAY
local WEEKDAYS: { [string]: number } =
	{ Mon = 0, Tue = 1, Wed = 2, Thu = 3, Fri = 4, Sat = 5, Sun = 6 }

local Weather = {}

-- Workspace attribute (Studio only, the TEST panel): pretend the first
-- event in Config.EVENTS is on.
Weather.PRETEND_EVENT = "PretendEvent"

export type SupercellStage = "waiting" | "warning" | "on" | "over"
export type ActiveEvent = { event: Types.EventDef, left: number }

-- Bolt types --------------------------------------------------------------

-- The rare bolt with this key, or nil (Normal has none).
function Weather.boltDef(key: Types.BoltType?): Types.BoltTypeDef?
	for _, def in Config.BOLT_TYPES do
		if def.key == key then
			return def
		end
	end
	return nil
end

-- What a bolt of this type multiplies its catch by (1 for Normal).
function Weather.boltMultiplier(key: Types.BoltType?): number
	local def = Weather.boltDef(key)
	return if def then def.multiplier else 1
end

-- The chance of each rare bolt right now: a Supercell makes Golden
-- SUPERCELL.goldenMultiplier times likelier.
function Weather.boltChance(def: Types.BoltTypeDef, supercell: boolean): number
	if supercell and def.key == "Golden" then
		return def.chance * Config.SUPERCELL.goldenMultiplier
	end
	return def.chance
end

-- Picks a strike's type from one random roll (0 to 1): each rare bolt
-- takes its chance's slice of the roll, the rest is Normal.
function Weather.pickBoltType(roll: number, supercell: boolean): Types.BoltType
	local edge = 0
	for _, def in Config.BOLT_TYPES do
		edge += Weather.boltChance(def, supercell)
		if roll < edge then
			return def.key
		end
	end
	return "Normal"
end

-- Supercells --------------------------------------------------------------

-- When the next Supercell starts, `from` (seconds) plus the interval and
-- some jitter: roll 0 = 15 minutes early, 0.5 = on time, 1 = 15 late.
function Weather.nextSupercellAt(from: number, roll: number): number
	local cell = Config.SUPERCELL
	local minutes = cell.intervalMinutes + (math.clamp(roll, 0, 1) * 2 - 1) * cell.jitterMinutes
	return from + minutes * 60
end

-- Where a Supercell that starts at `at` is at time `now`: still waiting,
-- in its warning countdown, on (it lasts SUPERCELL.minutes) or over.
function Weather.supercellStage(now: number, at: number): SupercellStage
	local cell = Config.SUPERCELL
	if now < at - cell.warningSeconds then
		return "waiting"
	elseif now < at then
		return "warning"
	elseif now < at + cell.minutes * 60 then
		return "on"
	end
	return "over"
end

-- Scheduled events --------------------------------------------------------

-- Seconds into the week (Monday 00:00 UTC = 0) of a Unix time. The Unix
-- clock started on a Thursday.
function Weather.weekSeconds(now: number): number
	local day = (now // DAY + WEEKDAYS.Thu) % 7
	return day * DAY + now % DAY
end

-- "Sat 00:00" -> seconds into the week, or nil if it isn't one.
function Weather.parseWeekly(text: string): number?
	local day, hour, minute = string.match(text, "^(%a%a%a) (%d%d?):(%d%d)$")
	local index = if day then WEEKDAYS[day] else nil
	local h, m = tonumber(hour), tonumber(minute)
	if index == nil or h == nil or m == nil or h > 23 or m > 59 then
		return nil
	end
	return index * DAY + h * 3600 + m * 60
end

-- Is the event on at Unix time `now`, and how many seconds are left (0 when
-- it's off)? A weekly event's end minute is included (Sun 23:59 runs to
-- Monday 00:00); a one-off event runs from startUtc up to endUtc.
function Weather.eventWindow(event: Types.EventDef, now: number): (boolean, number)
	local startAt, endAt = event.startUtc, event.endUtc
	if typeof(startAt) == "number" and typeof(endAt) == "number" then
		if now >= startAt and now < endAt then
			return true, endAt - now
		end
		return false, 0
	end
	local s = if typeof(startAt) == "string" then Weather.parseWeekly(startAt) else nil
	local e = if typeof(endAt) == "string" then Weather.parseWeekly(endAt) else nil
	if s == nil or e == nil then
		return false, 0
	end
	local length = (e + 60 - s) % WEEK
	if length == 0 then
		length = WEEK
	end
	local into = (Weather.weekSeconds(now) - s) % WEEK
	if into < length then
		return true, length - into
	end
	return false, 0
end

-- Every event on at `now` (Config.EVENTS unless a list is given), with
-- seconds left. `pretend` turns the first one on (the TEST panel).
function Weather.activeEvents(
	now: number,
	events: { Types.EventDef }?,
	pretend: boolean?
): { ActiveEvent }
	local list = events or Config.EVENTS
	local active: { ActiveEvent } = {}
	for index, event in list do
		local on, left = Weather.eventWindow(event, now)
		if not on and pretend and index == 1 then
			on, left = true, 3600
		end
		if on then
			table.insert(active, { event = event, left = left })
		end
	end
	return active
end

-- `owned` (an Util/Passes set) plus a mark for each event on at `now`, so
-- Passes.sellMultiplier multiplies by it.
function Weather.withEvents(owned: Passes.Owned, now: number, pretend: boolean?): Passes.Owned
	local active = Weather.activeEvents(now, nil, pretend)
	if #active == 0 then
		return owned
	end
	local set = table.clone(owned)
	for _, on in active do
		set[Passes.EVENT .. on.event.name] = true
	end
	return set
end

-- The events on right now, by the server clock (with the Studio pretend
-- switch). Not pure: it reads the workspace, so the harness never calls it.
function Weather.liveEvents(): { ActiveEvent }
	local pretend = game:GetService("RunService"):IsStudio()
		and workspace:GetAttribute(Weather.PRETEND_EVENT) == true
	return Weather.activeEvents(math.floor(workspace:GetServerTimeNow()), nil, pretend)
end

-- Time left as a short text: "1d 4h", "3h 12m", "12:05".
function Weather.formatLeft(seconds: number): string
	local left = math.max(0, math.ceil(seconds))
	if left >= DAY then
		return `{left // DAY}d {left // 3600 % 24}h`
	elseif left >= 3600 then
		return `{left // 3600}h {left // 60 % 60}m`
	end
	return string.format("%d:%02d", left // 60, left % 60)
end

return Weather
