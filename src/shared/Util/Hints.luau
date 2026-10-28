--!strict
-- Gameplay tips: the rules, as pure maths (the list and the timings are in
-- Config.HINTS; Systems/Hints saves which were seen; Controllers/Hints shows
-- them; tools/harness/test_hints.luau tests this).
--
-- After the new-player tutorial, each part of the game gets one short tip
-- the first time it matters (new boots affordable, a zone opens, a first
-- researcher, ...). Hints.pick decides which tip (if any) shows now:
--   * nothing while the tutorial runs, while tips are off in SETTINGS, or
--     while the player is busy (a panel open, catching, AFK)
--   * nothing for Config.HINTS.firstDelay seconds after joining or after
--     the tutorial, and Config.HINTS.gapSeconds after the last tip
--   * otherwise the first tip in the list that wasn't seen and whose
--     trigger (`when`, and `minutes` into the visit) is true
-- Each tip shows once ever: its id goes in profile.hintsSeen.

local Config = require(script.Parent.Parent.Config)
local Stats = require(script.Parent.Stats)
local Types = require(script.Parent.Parent.Types)

local Hints = {}

-- What the triggers look at. Most of it comes from the snapshot
-- (Hints.facts); the rest the client notices during the visit.
export type Facts = {
	minutes: number, -- minutes into this visit
	tutorialDone: boolean,
	bottleTier: number,
	bootTier: number,
	volts: number,
	researchers: number, -- hired
	unposted: boolean, -- a hired researcher is still at the Office
	topLevel: number, -- the highest researcher level
	glints: number, -- all tiers added up
	logFound: number, -- Storm Log entries found
	dailyStreak: number,
	full: boolean, -- the bottle is full
	remoteSell: boolean, -- owns Remote Sell
	canAscend: boolean,
	friends: number,
	groupMember: boolean,
	sold: boolean, -- sold at least once this visit
	sawRareBolt: boolean, -- a Golden, Rainbow or ball lightning bolt this visit
	sawSupercell: boolean, -- a Supercell this visit
	eventOn: boolean, -- a scheduled event (Double Volts Weekend) is on
}

-- What the client notices itself (everything Facts has that a snapshot doesn't).
export type Session = {
	minutes: number,
	canAscend: boolean,
	groupMember: boolean,
	sold: boolean,
	sawRareBolt: boolean,
	sawSupercell: boolean,
	eventOn: boolean,
}

-- The timing side of the choice (all in seconds, the same clock).
export type Timing = {
	now: number,
	lastShown: number, -- when the last tip showed (-math.huge = never)
	quietUntil: number, -- joined or finished the tutorial: none before this
	busy: boolean, -- a panel or the menu is open, catching, or AFK
	enabled: boolean, -- the "Gameplay tips" setting
}

-- The snapshot fields the facts come from (a Types.Snapshot fits).
export type SnapshotLike = {
	tutorialStep: number,
	bottleTier: number,
	bootTier: number,
	volts: number,
	researchers: { [string]: Types.ResearcherSave },
	glints: { number },
	log: Types.LogView,
	daily: { streak: number, lastDay: number, dayOffset: number },
	chargeCount: number,
	capacity: number,
	passes: { [string]: boolean },
	friends: number,
}

-- How many zones (Premium ones left out) a bottle tier opens.
function Hints.zonesOpen(bottleTier: number): number
	local count = 0
	for _, zone in Config.ZONES do
		if not zone.premium and zone.requiresBottle <= bottleTier then
			count += 1
		end
	end
	return count
end

-- How many worlds a bottle tier opens.
function Hints.worldsOpen(bottleTier: number): number
	local count = 0
	for _, world in Config.WORLDS do
		if world.requiresBottle <= bottleTier then
			count += 1
		end
	end
	return count
end

-- The triggers, by name (Config.HINTS list's `when`).
Hints.CONDITIONS = {
	always = function(_f: Facts): boolean
		return true
	end,
	remoteSellFull = function(f: Facts): boolean
		return f.remoteSell and f.full
	end,
	canAscend = function(f: Facts): boolean
		return f.canAscend
	end,
	worldOpen = function(f: Facts): boolean
		return Hints.worldsOpen(f.bottleTier) >= 2
	end,
	zoneOpen = function(f: Facts): boolean
		return Hints.zonesOpen(f.bottleTier) >= 2
	end,
	sawRareBolt = function(f: Facts): boolean
		return f.sawRareBolt
	end,
	sawSupercell = function(f: Facts): boolean
		return f.sawSupercell
	end,
	eventOn = function(f: Facts): boolean
		return f.eventOn
	end,
	-- still in the starter boots, and the next pair is affordable
	bootsAffordable = function(f: Facts): boolean
		local next = Config.BOOTS[2]
		return f.bootTier <= 1 and next ~= nil and f.volts >= next.price
	end,
	-- nobody hired, and the cheapest researcher is affordable
	canHire = function(f: Facts): boolean
		local cheapest = math.huge
		for _, def in Config.RESEARCHERS do
			cheapest = math.min(cheapest, def.price)
		end
		return f.researchers == 0 and f.volts >= cheapest
	end,
	unposted = function(f: Facts): boolean
		return f.unposted
	end,
	hasGlints = function(f: Facts): boolean
		return f.researchers > 0 and f.glints > 0
	end,
	researcherLevel5 = function(f: Facts): boolean
		return f.topLevel >= 5
	end,
	logStarted = function(f: Facts): boolean
		return f.logFound >= 3
	end,
	claimedDaily = function(f: Facts): boolean
		return f.dailyStreak >= 1
	end,
	hasSold = function(f: Facts): boolean
		return f.sold
	end,
	hasFriends = function(f: Facts): boolean
		return f.friends > 0
	end,
	notGroupMember = function(f: Facts): boolean
		return not f.groupMember
	end,
} :: { [string]: (Facts) -> boolean }

-- Every tip, in order (Config.HINTS.list).
function Hints.list(): { Types.HintDef }
	return Config.HINTS.list
end

local byId: { [string]: Types.HintDef } = {}
for _, def in Config.HINTS.list do
	byId[def.id] = def
end

-- The tip with this id, or nil (also the server's check of what a client sends).
function Hints.def(id: unknown): Types.HintDef?
	if typeof(id) ~= "string" then
		return nil
	end
	return byId[id]
end

-- A tip's text with its numbers filled in.
function Hints.text(def: Types.HintDef): string
	local perFriend = math.floor(Config.FRIENDS.perFriend * 100 + 0.5)
	local text = def.text
	text = string.gsub(text, "{groupBonus}", tostring(math.floor(Config.GROUP_BONUS * 100 + 0.5)))
	text = string.gsub(text, "{friendBonus}", tostring(perFriend))
	text = string.gsub(text, "{friendMax}", `+{perFriend * Config.FRIENDS.max}%%`)
	return text
end

-- The facts from a snapshot and what the client noticed this visit.
function Hints.facts(snapshot: SnapshotLike, session: Session): Facts
	local researchers, unposted, topLevel = 0, false, 0
	for _, save in snapshot.researchers do
		researchers += 1
		if save.post == "Office" then
			unposted = true
		end
		topLevel = math.max(topLevel, save.level)
	end
	local glints = 0
	for _, count in snapshot.glints do
		glints += count
	end
	return {
		minutes = session.minutes,
		tutorialDone = snapshot.tutorialStep == 0,
		bottleTier = snapshot.bottleTier,
		bootTier = snapshot.bootTier,
		volts = snapshot.volts,
		researchers = researchers,
		unposted = unposted,
		topLevel = topLevel,
		glints = glints,
		logFound = #snapshot.log.found,
		dailyStreak = snapshot.daily.streak,
		full = snapshot.capacity > 0 and snapshot.chargeCount >= snapshot.capacity,
		remoteSell = snapshot.passes.RemoteSell == true,
		canAscend = session.canAscend,
		friends = snapshot.friends,
		groupMember = session.groupMember,
		sold = session.sold,
		sawRareBolt = session.sawRareBolt,
		sawSupercell = session.sawSupercell,
		eventOn = session.eventOn,
	}
end

-- Is this tip's trigger true? (An unknown `when` is never true.)
function Hints.triggered(def: Types.HintDef, facts: Facts): boolean
	local condition = Hints.CONDITIONS[def.when]
	if not condition then
		return false
	end
	if def.minutes and facts.minutes < def.minutes then
		return false
	end
	return condition(facts)
end

-- May any tip show now (the timing and the busy rules)?
function Hints.canShow(facts: Facts, timing: Timing): boolean
	if not timing.enabled or not facts.tutorialDone or timing.busy then
		return false
	end
	if timing.now < timing.quietUntil then
		return false
	end
	return timing.now - timing.lastShown >= Config.HINTS.gapSeconds
end

-- The tip to show now, or nil. `seen`: the ids already shown.
function Hints.pick(
	seen: { [string]: boolean },
	facts: Facts,
	timing: Timing,
	list: { Types.HintDef }?
): Types.HintDef?
	if not Hints.canShow(facts, timing) then
		return nil
	end
	for _, def in list or Hints.list() do
		if not seen[def.id] and Hints.triggered(def, facts) then
			return def
		end
	end
	return nil
end

-- A saved set of seen ids, cleaned: only known ids, only `true`.
function Hints.sanitize(raw: unknown): { [string]: boolean }
	local clean: { [string]: boolean } = {}
	if typeof(raw) == "table" then
		for id, value in raw :: any do
			if value == true and byId[id] then
				clean[id] = true
			end
		end
	end
	return clean
end

-- For profiles saved before tips existed: the tips for things the player
-- has clearly done already count as seen (they don't need telling).
-- `data` is a saved profile (any shape: every field is checked).
function Hints.alreadyUsed(data: any): { [string]: boolean }
	local seen: { [string]: boolean } = {}
	local function num(value: any): number
		return if typeof(value) == "number" then value else 0
	end
	local stats = if typeof(data.stats) == "table" then data.stats else {}
	local lifetime = if typeof(stats.lifetime) == "table" then stats.lifetime else {}
	local function stat(key: string): number
		return num(lifetime[key])
	end
	local ascended = num(data.ascension) > 0
	if ascended then
		seen.ascend = true
	end
	if num(data.bootTier) >= 2 or ascended then
		seen.boots = true
	end
	-- been in two or more (non-Premium) zones
	local zonesVisited = 0
	for _, zone in Config.ZONES do
		if not zone.premium and stat(Stats.visitZoneKey(zone.id)) > 0 then
			zonesVisited += 1
		end
	end
	if zonesVisited >= 2 then
		seen.newZone = true
	end
	for index, world in Config.WORLDS do
		if index > 1 and stat(Stats.visitWorldKey(world.id)) > 0 then
			seen.portal = true
			seen.teleport = true
		end
	end
	-- researchers: hired, posted, promoted
	if typeof(data.researchers) == "table" and next(data.researchers) ~= nil then
		seen.hireResearcher = true
		for _, save in data.researchers do
			if typeof(save) == "table" then
				if typeof(save.post) == "string" and save.post ~= "Office" then
					seen.postResearcher = true
				end
				if num(save.rank) > 0 then
					seen.promote = true
					seen.glints = true
				end
			end
		end
	end
	if stat(Stats.PROMOTIONS) > 0 then
		seen.promote = true
		seen.glints = true
	end
	if typeof(data.logClaimed) == "table" and next(data.logClaimed) ~= nil then
		seen.stormLog = true
	end
	-- rewards
	if num(data.dailyStreak) > 0 then
		seen.dailyStreak = true
	end
	local playtime = data.playtime
	if typeof(playtime) == "table" and typeof(playtime.claimed) == "table" then
		for _, claimed in playtime.claimed do
			if claimed == true then
				seen.playtimeGifts = true
			end
		end
	end
	local quests = data.quests
	if typeof(quests) == "table" then
		if num(quests.rerollDay) > 0 then
			seen.quests = true
		end
		for _, period in { quests.daily, quests.weekly } do
			if typeof(period) == "table" then
				for _, quest in period do
					if typeof(quest) == "table" and quest.claimed == true then
						seen.quests = true
					end
				end
			end
		end
	end
	-- the store: bought something, or tried the free 2x Volts
	if data.trialUsed == true or (typeof(data.purchases) == "table" and #data.purchases > 0) then
		seen.boosts = true
	end
	-- the weather: already caught a rare bolt, been in a Supercell or an event
	for _, def in Config.BOLT_TYPES do
		if stat(Stats.typeKey(def.key)) > 0 then
			seen.rareBolt = true
		end
	end
	if stat(Stats.SUPERCELLS_SEEN) > 0 then
		seen.supercell = true
	end
	for _, event in Config.EVENTS do
		if stat(Stats.eventKey(event.name)) > 0 then
			seen.event = true
		end
	end
	return seen
end

return Hints
