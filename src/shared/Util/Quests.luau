--!strict
-- The rules for daily and weekly quests (Systems/Quests applies them, the
-- QUESTS tab in the REWARDS panel shows them; tools/harness/test_quests.luau
-- tests them). Pure: no Roblox services.
--
-- How it works, in plain words:
--   * Each UTC day a player gets Config.QUESTS.daily quests, and each week
--     (Monday 00:00 UTC) Config.QUESTS.weekly, picked from
--     Config.QUESTS.templates. The pick is seeded by their userId and the
--     day (or week) number, so they get the same quests all day, on any
--     server.
--   * A quest watches one stat counter (Util/Stats): today's counters for a
--     daily quest, this week's for a weekly one. It remembers the counter's
--     value when it was picked (`base`), so only what happens after counts.
--   * Amounts grow with the player's bottle tier; "earn Volts" is minutes
--     of their grinding rate in their best zone (Util/Afk).
--   * One free reroll a day swaps any unfinished quest for another.

local Config = require(script.Parent.Parent.Config)
local Types = require(script.Parent.Parent.Types)
local Afk = require(script.Parent.Afk)
local Format = require(script.Parent.Format)
local Progression = require(script.Parent.Progression)
local Stats = require(script.Parent.Stats)

export type Period = "daily" | "weekly"

local Quests = {}

-- A small seeded number generator (the "minimal standard" one), so a pick
-- is the same everywhere: on every server and in the test harness.
local MOD = 2147483647

local function generator(seed: number): () -> number
	local state = seed % (MOD - 1) + 1
	local function nextNumber(): number
		state = (state * 48271) % MOD
		return state
	end
	-- a few steps to spread out seeds that are close together
	for _ = 1, 4 do
		nextNumber()
	end
	return nextNumber
end

-- A whole number from 1 to `n`.
local function roll(rng: () -> number, n: number): number
	return rng() % n + 1
end

local function seedFor(userId: number, period: Period, number: number, salt: number): number
	local tag = if period == "weekly" then 2 else 1
	return userId % MOD + number * 7919 + salt * 104729 + tag * 15485863
end

-- The template with this key.
function Quests.template(key: string): Types.QuestTemplate?
	for _, template in Config.QUESTS.templates do
		if template.key == key then
			return template
		end
	end
	return nil
end

-- A fresh quests save: day 0 is long ago, so quests are picked on load.
function Quests.new(): Types.QuestsSave
	return { day = 0, week = 0, daily = {}, weekly = {}, rerollDay = 0 }
end

-- The counter set a period's quests read.
function Quests.setFor(stats: Types.StatsSave, period: Period): { [string]: number }
	return if period == "weekly" then stats.thisWeek else stats.today
end

-- The stat counter a quest watches.
function Quests.statKey(quest: { key: string, zone: string? }): string
	local key = quest.key
	if key == "CatchZone" then
		return Stats.zoneKey(quest.zone or "")
	elseif key == "Sell" then
		return Stats.FULL_BOTTLES_SOLD
	elseif key == "Golden" then
		return Stats.typeKey("Golden")
	elseif key == "Volts" then
		return Stats.VOLTS_EARNED
	elseif key == "Play" then
		return Stats.PLAYTIME_MINUTES
	elseif key == "Promote" then
		return Stats.PROMOTIONS
	end
	return Stats.BOLTS
end

-- How far along a quest is (0 to its target).
function Quests.progressOf(quest: Types.QuestSave, set: { [string]: number }): number
	return math.clamp(Stats.get(set, Quests.statKey(quest)) - quest.base, 0, quest.target)
end

function Quests.isComplete(quest: Types.QuestSave, set: { [string]: number }): boolean
	return Quests.progressOf(quest, set) >= quest.target
end

-- Volts a minute of grinding in their best zone pays (no passes or boosts,
-- so a quest doesn't change size with a boost running).
function Quests.voltsPerMinute(progress: Progression.Progress): number
	local _, breakdown = Afk.rate(progress, {}, false)
	return breakdown.grindPerSecond * 60
end

-- Two significant figures (12,345 -> 12,000), at least 1.
local function tidy(n: number): number
	if n < 100 then
		return math.max(1, math.round(n))
	end
	local step = 10 ^ (math.floor(math.log10(n)) - 1)
	return math.round(n / step) * step
end

-- How much a template asks for this player in this period.
function Quests.amount(
	template: Types.QuestTemplate,
	period: Period,
	progress: Progression.Progress
): number
	local base = (if period == "weekly" then template.weekly else template.daily) or 0
	if template.key == "Volts" then
		return tidy(Quests.voltsPerMinute(progress) * base)
	end
	local grow = 1 + (template.perTier or 0) * (progress.bottleTier - 1)
	return math.max(1, math.round(base * grow))
end

-- The zones a "catch in a zone" quest can name: their best few non-Premium
-- zones they can enter (best paying first).
function Quests.zoneChoices(progress: Progression.Progress): { Types.ZoneDef }
	local zones: { Types.ZoneDef } = {}
	for _, zone in Config.ZONES do
		if not zone.premium and Progression.canEnter(progress, zone, false) then
			table.insert(zones, zone)
		end
	end
	table.sort(zones, function(a, b)
		if a.chargeValue ~= b.chargeValue then
			return a.chargeValue > b.chargeValue
		end
		return a.id < b.id
	end)
	local choices: { Types.ZoneDef } = {}
	for index = 1, math.min(#zones, Config.QUESTS.zoneChoices) do
		choices[index] = zones[index]
	end
	return choices
end

-- The templates a period can pick from, shuffled by `rng`.
local function shuffled(
	rng: () -> number,
	period: Period,
	hasResearcher: boolean
): { Types.QuestTemplate }
	local list: { Types.QuestTemplate } = {}
	for _, template in Config.QUESTS.templates do
		local amount = if period == "weekly" then template.weekly else template.daily
		if amount and (template.key ~= "Promote" or hasResearcher) then
			table.insert(list, template)
		end
	end
	for index = #list, 2, -1 do
		local other = roll(rng, index)
		list[index], list[other] = list[other], list[index]
	end
	return list
end

local function build(
	template: Types.QuestTemplate,
	period: Period,
	rng: () -> number,
	progress: Progression.Progress,
	set: { [string]: number }
): Types.QuestSave
	local key: string = template.key
	local zone: string? = nil
	if key == "CatchZone" then
		local choices = Quests.zoneChoices(progress)
		if #choices > 0 then
			zone = choices[roll(rng, #choices)].id
		else
			key = "Catch"
		end
	end
	local quest: Types.QuestSave = {
		key = key,
		zone = zone,
		target = Quests.amount(template, period, progress),
		base = 0,
		claimed = false,
	}
	quest.base = Stats.get(set, Quests.statKey(quest))
	return quest
end

-- A period's quests for this player: always the same for the same userId,
-- period number (day or week) and progress. `set` is that period's
-- counters, so progress counts from now.
function Quests.pick(
	userId: number,
	period: Period,
	number: number,
	progress: Progression.Progress,
	hasResearcher: boolean,
	set: { [string]: number }
): { Types.QuestSave }
	local rng = generator(seedFor(userId, period, number, 0))
	local count = if period == "weekly" then Config.QUESTS.weekly else Config.QUESTS.daily
	local quests: { Types.QuestSave } = {}
	for index, template in shuffled(rng, period, hasResearcher) do
		if index > count then
			break
		end
		table.insert(quests, build(template, period, rng, progress, set))
	end
	return quests
end

-- Picks new quests when the day (or week) has changed. Rolls the stat
-- counters over first, so both start the new day together. Returns true
-- if anything changed.
function Quests.refresh(
	save: Types.QuestsSave,
	stats: Types.StatsSave,
	userId: number,
	day: number,
	progress: Progression.Progress,
	hasResearcher: boolean
): boolean
	local changed = Stats.roll(stats, day)
	if save.day ~= day then
		save.day = day
		save.daily = Quests.pick(userId, "daily", day, progress, hasResearcher, stats.today)
		changed = true
	end
	local week = Stats.weekOf(day)
	if save.week ~= week then
		save.week = week
		save.weekly = Quests.pick(userId, "weekly", week, progress, hasResearcher, stats.thisWeek)
		changed = true
	end
	return changed
end

local function list(save: Types.QuestsSave, period: Period): { Types.QuestSave }
	return if period == "weekly" then save.weekly else save.daily
end

-- May the free reroll swap this quest today? Only an unfinished quest,
-- and only once a day.
function Quests.canReroll(
	save: Types.QuestsSave,
	stats: Types.StatsSave,
	period: Period,
	index: number,
	day: number
): boolean
	local quest = list(save, period)[index]
	return save.rerollDay ~= day
		and quest ~= nil
		and not quest.claimed
		and not Quests.isComplete(quest, Quests.setFor(stats, period))
end

-- Swaps a quest for a different template (today's free reroll). Returns
-- true if it did.
function Quests.reroll(
	save: Types.QuestsSave,
	stats: Types.StatsSave,
	period: Period,
	index: number,
	userId: number,
	day: number,
	progress: Progression.Progress,
	hasResearcher: boolean
): boolean
	if not Quests.canReroll(save, stats, period, index, day) then
		return false
	end
	local quests = list(save, period)
	local taken: { [string]: boolean } = {}
	for _, quest in quests do
		taken[quest.key] = true
	end
	local number = if period == "weekly" then save.week else save.day
	local rng = generator(seedFor(userId, period, number, 1 + day))
	for _, template in shuffled(rng, period, hasResearcher) do
		if not taken[template.key] then
			quests[index] = build(template, period, rng, progress, Quests.setFor(stats, period))
			save.rerollDay = day
			return true
		end
	end
	return false
end

-- Marks a finished quest claimed and returns it (nil if it can't be).
function Quests.claim(
	save: Types.QuestsSave,
	stats: Types.StatsSave,
	period: Period,
	index: number
): Types.QuestSave?
	local quest = list(save, period)[index]
	if not quest or quest.claimed or not Quests.isComplete(quest, Quests.setFor(stats, period)) then
		return nil
	end
	quest.claimed = true
	return quest
end

-- What a quest pays: its template's reward (daily), or the weekly reward.
function Quests.reward(key: string, period: Period): Types.Reward
	if period == "weekly" then
		return Config.QUESTS.weeklyReward
	end
	local template = Quests.template(key)
	return if template then template.reward else {}
end

-- What the client is sent: each quest with its progress.
function Quests.view(save: Types.QuestsSave, stats: Types.StatsSave, day: number): Types.QuestsView
	local function viewList(period: Period): { Types.QuestView }
		local set = Quests.setFor(stats, period)
		local views: { Types.QuestView } = {}
		for _, quest in list(save, period) do
			table.insert(views, {
				key = quest.key,
				zone = quest.zone,
				target = quest.target,
				progress = Quests.progressOf(quest, set),
				claimed = quest.claimed,
			})
		end
		return views
	end
	return {
		daily = viewList("daily"),
		weekly = viewList("weekly"),
		rerollReady = save.rerollDay ~= day,
	}
end

-- A quest in words: "Catch 120 bolts in Mesa".
function Quests.describe(quest: { key: string, zone: string?, target: number }): string
	local n = quest.target
	local count = Format.abbreviate(n)
	local key = quest.key
	if key == "CatchZone" then
		local zone = if quest.zone then Config.ZONES[quest.zone] else nil
		return `Catch {count} bolts in {if zone then zone.displayName else "a zone"}`
	elseif key == "Sell" then
		return if n == 1 then "Sell a full bottle" else `Sell {count} full bottles`
	elseif key == "Golden" then
		return if n == 1 then "Catch a golden bolt" else `Catch {count} golden bolts`
	elseif key == "Volts" then
		return `Earn {count} Volts`
	elseif key == "Play" then
		return `Play for {count} minutes`
	elseif key == "Promote" then
		return if n == 1 then "Promote a researcher" else `Promote {count} researchers`
	end
	return `Catch {count} bolts`
end

return Quests
