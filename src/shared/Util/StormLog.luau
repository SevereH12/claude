--!strict
-- The Storm Log: a collection book, worked out from the lifetime stat
-- counters (Util/Stats) and the hired researchers, so the only thing it
-- saves is which rows' rewards were claimed (profile.logClaimed). Pure: no
-- Roblox services, so tools/harness/test_quests.luau can test it.
--
-- Four pages (Config.STORM_LOG.pages), each made of rows of entries:
--   * Bolts: a row per zone, an entry per bolt type caught there
--   * Places: a row per world, an entry for the world and each of its zones
--   * Team: a row per researcher, an entry per rank they've reached (rank 0
--     is "hired")
--   * Weather: one row, an entry for the Supercell and each scheduled event
-- A finished row pays its page's rowReward once (CLAIM in the LOG tab).
-- A finished page adds +2% Volts for good (Passes.logBonus, up to +8%).
-- Roblox Premium zones are bonuses: their Bolts row and their Places entry
-- are shown, but a page (and a world's Places row) can be finished
-- without them, so nobody needs Premium for the whole Log bonus.

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)
local Passes = require(script.Parent.Passes)
local Research = require(script.Parent.Research)
local Stats = require(script.Parent.Stats)

-- One thing to find. It's found when any counter in `stats` is above 0,
-- or (Team) when researcher `role` has reached rank `rank`.
export type Entry = {
	id: string,
	label: string, -- shown under the icon once it's found
	icon: string, -- an emoji
	hint: string, -- how to find it (shown on the "?" until then)
	stats: { string }?,
	role: string?,
	rank: number?,
	bonus: boolean?, -- a Premium zone's: not needed to finish its row
}

export type Row = {
	id: string, -- "<page id>:<what>", e.g. "Bolts:Mesa"
	page: string,
	label: string,
	entries: { Entry },
	bonus: boolean?, -- a Premium zone's row: not needed to finish its page
}

export type Page = {
	id: string,
	title: string,
	icon: string,
	reward: Types.Reward, -- what each of its rows pays
	rows: { Row },
}

-- Entry ids found: id -> true.
export type Found = { [string]: boolean }

local StormLog = {}

local BOLT_NAMES: { [string]: string } = {
	Normal = "Bolt",
	Golden = "Golden",
	Rainbow = "Rainbow",
	Ball = "Ball Lightning",
}
local BOLT_ICONS: { [string]: string } = {
	Normal = "⚡",
	Golden = "🌟",
	Rainbow = "🌈",
	Ball = "🔮",
}

local function worldIndex(worldId: string): number
	for index, world in Config.WORLDS do
		if world.id == worldId then
			return index
		end
	end
	return math.huge
end

-- Every zone in the order you reach them: world, then bottle, then order.
local function sortedZones(): { Types.ZoneDef }
	local list: { Types.ZoneDef } = {}
	for _, zone in Config.ZONES do
		table.insert(list, zone)
	end
	table.sort(list, function(a, b)
		local wa, wb = worldIndex(a.world), worldIndex(b.world)
		if wa ~= wb then
			return wa < wb
		end
		if a.requiresBottle ~= b.requiresBottle then
			return a.requiresBottle < b.requiresBottle
		end
		return a.order < b.order
	end)
	return list
end

-- "Needs the Storm Cell" or "a Roblox Premium zone".
local function zoneNeeds(zone: Types.ZoneDef): string
	if zone.premium then
		return " (a Roblox Premium zone)"
	end
	if zone.requiresBottle <= 1 then
		return ""
	end
	local bottle = Config.BOTTLES[zone.requiresBottle]
	return if bottle then ` (needs the {bottle.name})` else ""
end

-- "2%" or "0.4%".
local function percent(chance: number): string
	local value = math.round(chance * 1000) / 10
	return if value == math.floor(value) then `{math.floor(value)}%` else `{value}%`
end

local function boltRows(zones: { Types.ZoneDef }): { Row }
	local rows: { Row } = {}
	for _, zone in zones do
		local entries: { Entry } = {
			{
				id = `Bolts:Normal:{zone.id}`,
				label = "Bolt",
				icon = BOLT_ICONS.Normal,
				hint = `Catch any bolt in {zone.displayName}{zoneNeeds(zone)}`,
				stats = { Stats.typeZoneKey("Normal", zone.id) },
			},
		}
		for _, def in Config.BOLT_TYPES do
			local name = BOLT_NAMES[def.key] or def.label
			local how = if def.key == "Ball"
				then `Touch a drifting ball lightning orb in {zone.displayName}`
				else `Catch a {name} bolt in {zone.displayName}`
			table.insert(entries, {
				id = `Bolts:{def.key}:{zone.id}`,
				label = name,
				icon = BOLT_ICONS[def.key] or "⚡",
				hint = `{how} (about {percent(def.chance)} of strikes){zoneNeeds(zone)}`,
				stats = { Stats.typeZoneKey(def.key, zone.id) },
			})
		end
		table.insert(rows, {
			id = `Bolts:{zone.id}`,
			page = "Bolts",
			label = if zone.premium then `{zone.displayName} (Premium bonus)` else zone.displayName,
			entries = entries,
			bonus = zone.premium == true,
		})
	end
	return rows
end

-- A zone counts as visited once you've stood in it (or caught a bolt
-- there); a world once you've been in it (or in one of its zones).
local function placeRows(zones: { Types.ZoneDef }): { Row }
	local rows: { Row } = {}
	for index, world in Config.WORLDS do
		local worldStats = { Stats.visitWorldKey(world.id) }
		local zoneEntries: { Entry } = {}
		for _, zone in zones do
			if zone.world == world.id then
				local keys = { Stats.visitZoneKey(zone.id), Stats.zoneKey(zone.id) }
				table.insert(worldStats, keys[1])
				table.insert(worldStats, keys[2])
				table.insert(zoneEntries, {
					id = `Places:zone:{zone.id}`,
					label = zone.displayName,
					icon = "📍",
					hint = `Walk into {zone.displayName}{zoneNeeds(zone)}`
						.. (if zone.premium then ", a bonus: not needed for the row" else ""),
					stats = keys,
					bonus = zone.premium == true,
				})
			end
		end
		local bottle = Config.BOTTLES[world.requiresBottle]
		local entries: { Entry } = {
			{
				id = `Places:world:{world.id}`,
				label = world.displayName,
				icon = "🌍",
				hint = if index == 1 or not bottle
					then `Visit {world.displayName}`
					else `Take the portal to {world.displayName} (needs the {bottle.name})`,
				stats = worldStats,
			},
		}
		for _, entry in zoneEntries do
			table.insert(entries, entry)
		end
		table.insert(rows, {
			id = `Places:{world.id}`,
			page = "Places",
			label = world.displayName,
			entries = entries,
		})
	end
	return rows
end

local function teamRows(): { Row }
	local rows: { Row } = {}
	for _, def in Config.RESEARCHERS do
		local entries: { Entry } = {
			{
				id = `Team:{def.id}:0`,
				label = "Hired",
				icon = "🔬",
				hint = `Hire {def.name} at the Research Office`,
				role = def.id,
				rank = 0,
			},
		}
		for rank = 1, Research.maxRank() do
			table.insert(entries, {
				id = `Team:{def.id}:{rank}`,
				label = `Rank {rank}`,
				icon = string.rep("★", math.min(rank, 3)),
				hint = `Promote {def.name} to rank {rank}`,
				role = def.id,
				rank = rank,
			})
		end
		table.insert(rows, {
			id = `Team:{def.id}`,
			page = "Team",
			label = def.name,
			entries = entries,
		})
	end
	return rows
end

local function weatherRows(): { Row }
	local entries: { Entry } = {
		{
			id = "Weather:Supercell",
			label = "Supercell",
			icon = "🌀",
			hint = `Be in game during a Supercell (about every {Config.SUPERCELL.intervalMinutes} minutes)`,
			stats = { Stats.SUPERCELLS_SEEN },
		},
	}
	for _, event in Config.EVENTS do
		local when = if typeof(event.startUtc) == "string"
				and typeof(event.endUtc) == "string"
			then ` ({event.startUtc} to {event.endUtc} UTC)`
			else ""
		table.insert(entries, {
			id = `Weather:event:{event.name}`,
			label = event.name,
			icon = "🎉",
			hint = `Play during {event.name}{when}`,
			stats = { Stats.eventKey(event.name) },
		})
	end
	return { { id = "Weather:Storms", page = "Weather", label = "Storms", entries = entries } }
end

local cached: { Page }? = nil

-- Every page with its rows and entries (worked out from Config once).
function StormLog.pages(): { Page }
	if cached then
		return cached
	end
	local zones = sortedZones()
	local byPage: { [string]: { Row } } = {
		Bolts = boltRows(zones),
		Places = placeRows(zones),
		Team = teamRows(),
		Weather = weatherRows(),
	}
	local pages: { Page } = {}
	for _, def in Config.STORM_LOG.pages do
		table.insert(pages, {
			id = def.id,
			title = def.title,
			icon = def.icon,
			reward = def.rowReward,
			rows = byPage[def.id] or {},
		})
	end
	cached = pages
	return pages
end

-- The row with this id and its page, or nil.
function StormLog.row(rowId: string): (Row?, Page?)
	for _, page in StormLog.pages() do
		for _, row in page.rows do
			if row.id == rowId then
				return row, page
			end
		end
	end
	return nil, nil
end

-- Is this entry found, from the lifetime counters and the researchers?
local function isFound(
	entry: Entry,
	lifetime: { [string]: number },
	researchers: { [string]: Types.ResearcherSave }
): boolean
	if entry.role then
		local save = researchers[entry.role]
		return save ~= nil and (save.rank or 0) >= (entry.rank or 0)
	end
	for _, key in entry.stats or {} do
		if (lifetime[key] or 0) > 0 then
			return true
		end
	end
	return false
end

-- Every entry found so far.
function StormLog.found(
	lifetime: { [string]: number },
	researchers: { [string]: Types.ResearcherSave }
): Found
	local found: Found = {}
	for _, page in StormLog.pages() do
		for _, row in page.rows do
			for _, entry in row.entries do
				if isFound(entry, lifetime, researchers) then
					found[entry.id] = true
				end
			end
		end
	end
	return found
end

-- How many of the entries a row needs are found, and how many it needs
-- (a bonus entry isn't needed, except in a bonus row, which needs all).
function StormLog.rowProgress(row: Row, found: Found): (number, number)
	local count, total = 0, 0
	for _, entry in row.entries do
		if entry.bonus and not row.bonus then
			continue
		end
		total += 1
		if found[entry.id] then
			count += 1
		end
	end
	return count, total
end

function StormLog.rowDone(row: Row, found: Found): boolean
	local count, total = StormLog.rowProgress(row, found)
	return count == total
end

-- How many of the entries a page needs are found, and how many it needs
-- (bonus rows and entries aren't needed).
function StormLog.pageProgress(page: Page, found: Found): (number, number)
	local count, total = 0, 0
	for _, row in page.rows do
		if row.bonus then
			continue
		end
		local c, t = StormLog.rowProgress(row, found)
		count += c
		total += t
	end
	return count, total
end

function StormLog.pageDone(page: Page, found: Found): boolean
	local count, total = StormLog.pageProgress(page, found)
	return total > 0 and count == total
end

-- The ids of the finished pages.
function StormLog.pagesDone(found: Found): { string }
	local list: { string } = {}
	for _, page in StormLog.pages() do
		if StormLog.pageDone(page, found) then
			table.insert(list, page.id)
		end
	end
	return list
end

-- `owned` (an Util/Passes set) plus a mark for each finished page, so
-- Passes.sellMultiplier adds the Log bonus.
function StormLog.withPages(owned: Passes.Owned, found: Found): Passes.Owned
	local done = StormLog.pagesDone(found)
	if #done == 0 then
		return owned
	end
	local set = table.clone(owned)
	for _, id in done do
		set[Passes.LOG_PAGE .. id] = true
	end
	return set
end

-- The Volts bonus for this many finished pages (0.02 each, capped).
function StormLog.bonus(pagesDone: number): number
	local log = Config.STORM_LOG
	return math.min(pagesDone * log.pageBonus, log.maxBonus)
end

-- Can this row's reward be claimed now? (finished and not claimed yet)
function StormLog.canClaim(rowId: string, found: Found, claimed: { [string]: boolean }): boolean
	local row = StormLog.row(rowId)
	return row ~= nil and not claimed[rowId] and StormLog.rowDone(row, found)
end

-- Claims a finished row: marks it claimed and returns its reward, or nil
-- if it can't be claimed.
function StormLog.claim(claimed: { [string]: boolean }, rowId: string, found: Found): Types.Reward?
	if not StormLog.canClaim(rowId, found, claimed) then
		return nil
	end
	local _, page = StormLog.row(rowId)
	claimed[rowId] = true
	return if page then page.reward else nil
end

-- What the client is sent: found entry ids and claimed row ids.
function StormLog.view(found: Found, claimed: { [string]: boolean }): Types.LogView
	local view: Types.LogView = { found = {}, claimed = {} }
	for id in found do
		table.insert(view.found, id)
	end
	for id, yes in claimed do
		if yes then
			table.insert(view.claimed, id)
		end
	end
	table.sort(view.found)
	table.sort(view.claimed)
	return view
end

-- The view back as sets (the client's side).
function StormLog.fromView(view: Types.LogView?): (Found, { [string]: boolean })
	local found: Found = {}
	local claimed: { [string]: boolean } = {}
	if view then
		for _, id in view.found do
			found[id] = true
		end
		for _, id in view.claimed do
			claimed[id] = true
		end
	end
	return found, claimed
end

-- Studio TEST "+Log entry": the first entry not found yet that a counter
-- can find (Team entries need a real hire or promotion), and the counter
-- to add 1 to. nil when there's none left.
function StormLog.nextTestEntry(found: Found): (Entry?, string?)
	for _, page in StormLog.pages() do
		for _, row in page.rows do
			for _, entry in row.entries do
				local stats = entry.stats
				if not found[entry.id] and stats and stats[1] then
					return entry, stats[1]
				end
			end
		end
	end
	return nil, nil
end

return StormLog
