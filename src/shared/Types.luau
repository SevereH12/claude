--!strict
-- Shared type definitions. Types that cross the client/server boundary
-- (remote payloads, profile schema) live here so both sides agree.

-- What gets saved to the DataStore for each player.
export type Profile = {
	version: number,
	volts: number,
	totalVolts: number, -- lifetime earnings (for stats/leaderboards later)
	bottleTier: number, -- index into Config.BOTTLES
	bootTier: number, -- index into Config.BOOTS
	chargeCount: number, -- bottle units filled (limited by capacity; a strike fills its zone's chargeSize)
	chargeValue: number, -- Volts those charges sell for
	researchers: { [string]: ResearcherSave }, -- hired researchers by role id
	tankCount: number, -- Chemist's overflow tank: bottle units held
	tankValue: number, -- Volts those charges sell for
	onboardStep: number, -- onboarding funnel steps already sent (Systems/Analytics)
	boltColour: number, -- Bolt Colours pick: index into Config.BOLT_COLOURS, 0 = default
	purchases: { string }, -- the newest Volts pack PurchaseIds already granted (Systems/Receipts)
	trialUsed: boolean, -- the free 2x Volts trial has been started (once ever)
	boosts: { [string]: number }, -- seconds left per boost key (Config.BOOSTS); count down only in game
	dailyStreak: number, -- day of the login streak last claimed (1-7), 0 = never
	lastDailyDay: number, -- UTC day (os.time() // 86400) of the last daily claim, 0 = never
	giftedPasses: { [string]: boolean }, -- passes others gifted this player (count as owned)
	receivedGiftIds: { string }, -- the newest gift ids already applied (Systems/Gifts)
	giftCredits: { [string]: { string } }, -- gifts paid for but not sent yet: product key -> purchase ids
	glints: { number }, -- Glints per zone tier: glints[tier + 1] (Util/Research)
	settings: { [string]: any }, -- the SETTINGS panel: Util/Settings values (Systems/Settings)
	stats: StatsSave, -- stat counters (Util/Stats, Systems/Stats)
	quests: QuestsSave, -- daily and weekly quests (Util/Quests, Systems/Quests)
	logClaimed: { [string]: boolean }, -- Storm Log rows whose reward was claimed, by row id (Util/StormLog)
}

-- A Storm Log page (Config.STORM_LOG.pages): its id, heading, icon, and
-- what finishing one of its rows pays (once per row).
export type StormLogPageDef = {
	id: string,
	title: string,
	icon: string,
	rowReward: Reward,
}

-- What the client sees of the Storm Log (Util/StormLog.view): the ids of
-- the entries found and of the rows already claimed.
export type LogView = {
	found: { string },
	claimed: { string },
}

-- Stat counters (Util/Stats): key -> count, three times over. `day` is the
-- UTC day `today` counts, `week` the Monday-to-Sunday week `thisWeek` counts.
export type StatsSave = {
	lifetime: { [string]: number },
	today: { [string]: number },
	thisWeek: { [string]: number },
	day: number,
	week: number,
}

-- A quest template (Config.QUESTS.templates). `daily` / `weekly`: the
-- amount at bottle tier 1 (nil = never picked for that period); `perTier`
-- adds that fraction of it for every bottle tier above 1. For "Volts" the
-- amounts are minutes of the player's grinding rate (Util/Afk).
export type QuestKind = "Catch" | "CatchZone" | "Sell" | "Golden" | "Volts" | "Play" | "Promote"
export type QuestTemplate = {
	key: QuestKind,
	daily: number?,
	weekly: number?,
	perTier: number?,
	reward: Reward, -- a daily quest's reward (a weekly one pays Config.QUESTS.weeklyReward)
}

-- A picked quest: its template, the zone (CatchZone), how much it takes,
-- the counter's value when it was picked (progress counts from there) and
-- whether its reward was claimed.
export type QuestSave = {
	key: string,
	zone: string?,
	target: number,
	base: number,
	claimed: boolean,
}

export type QuestsSave = {
	day: number, -- the UTC day `daily` was picked for
	week: number, -- the week `weekly` was picked for (Util/Stats.weekOf)
	daily: { QuestSave },
	weekly: { QuestSave },
	rerollDay: number, -- the UTC day the free reroll was last used
}

-- What the client sees of a quest (Util/Quests.view).
export type QuestView = {
	key: string,
	zone: string?,
	target: number,
	progress: number,
	claimed: boolean,
}

export type QuestsView = {
	daily: { QuestView },
	weekly: { QuestView },
	rerollReady: boolean, -- today's free reroll is still there
}

-- A hired researcher. post is "Office" or a zone id.
export type ResearcherSave = {
	level: number,
	data: number,
	post: string,
	rank: number, -- 0 to Research.maxRank(); works in zones of this tier or lower
}

-- Sent to the owning client whenever their state changes.
export type Snapshot = {
	volts: number,
	totalVolts: number,
	bottleTier: number,
	bootTier: number,
	chargeCount: number,
	chargeValue: number,
	researchers: { [string]: ResearcherSave },
	tankCount: number,
	tankValue: number,
	setupUntil: { [string]: number }, -- role id -> workspace:GetServerTimeNow() when set up
	premium: boolean, -- counts as Premium for zone entry (decided by the server)
	passes: { [string]: boolean }, -- Game Passes owned, by key (Config.PASSES)
	capacity: number, -- the bottle's real capacity (Big Bottles included)
	trialUsed: boolean, -- the free 2x Volts trial has been used
	store: StoreSession,
	boosts: { [string]: number }, -- active boost key -> workspace:GetServerTimeNow() when it runs out
	daily: { streak: number, lastDay: number, dayOffset: number }, -- the login streak (Util/Rewards.daily)
	gifts: { startedAt: number, claimed: { boolean } }, -- playtime gifts: session start (server time)
	gifted: { [string]: boolean }, -- passes owned because someone gifted them
	giftCredits: { [string]: number }, -- gift products paid for but not sent yet
	afk: AfkState?, -- in the AFK Lounge (Systems/Afk), nil when not
	glints: { number }, -- Glints per zone tier (glints[tier + 1])
	quests: QuestsView, -- today's and this week's quests with their progress
	log: LogView, -- the Storm Log: entries found and rows claimed
}

-- The player's AFK Lounge state, sent in the snapshot (Systems/Afk). The
-- numbers are Util/Afk.rate's breakdown, ready for the AFK screen.
export type AfkState = {
	active: boolean, -- earning (false while waiting to start)
	startsAt: number, -- workspace:GetServerTimeNow() when earning starts (or started)
	earned: number, -- Volts paid this AFK session
	perHour: number,
	fraction: number, -- of the grinding rate
	premium: boolean,
	zone: string, -- best zone's display name
	bottle: string,
	baseCapacity: number,
	capacity: number,
	chargeSize: number,
	strikes: number,
	fillSeconds: number,
	bag: number,
	multipliers: { { label: string, value: number } },
	luck: number,
	bigBottles: boolean,
}

-- This session's store numbers, sent in the snapshot (Systems/Passes).
export type StoreSession = {
	boostEarned: number, -- extra Volts 2x Volts boosts (the free trial too) have paid
	missedDouble: number, -- extra Volts 2x Volts would have paid this session
}

-- This session's playtime gifts and the Studio "Next day" offset
-- (Systems/Rewards).
export type RewardSession = {
	startedAt: number, -- workspace:GetServerTimeNow() when the session's playtime began
	claimed: { boolean }, -- per Config.PLAYTIME_GIFTS entry
	dayOffset: number, -- Studio only: days added to today
}

-- A timed boost (Config.BOOSTS): switches a Game Pass's effect on for a while.
export type BoostDef = {
	key: string,
	pass: string, -- the pass whose effect it gives (Config.PASSES key)
	name: string,
	icon: string,
}

-- A boost in the store's BOOSTS tab (Config.BOOST_PRODUCTS): a Developer
-- Product bought for yourself (FOR ME) or as a gift. `boosts` is what it
-- gives; a `serverStorm` product starts a Server Storm instead (FOR ME only).
export type BoostProductDef = {
	key: string,
	productId: number, -- Developer Product id (0 = not created yet)
	image: number, -- icon asset id (0 = use `icon`)
	name: string,
	icon: string, -- emoji fallback
	detail: string,
	price: number, -- Robux, a fallback until the real price loads
	boosts: { RewardBoost }?,
	serverStorm: boolean?,
}

-- A reward: `charges` pays that many bolts from the player's best zone
-- (Util/Store.volts); `boosts` adds timed boosts.
export type RewardBoost = { key: string, minutes: number }
export type Reward = { charges: number?, boosts: { RewardBoost }? }

-- A playtime gift: claimable `minutes` into a session.
export type PlaytimeGift = { minutes: number, reward: Reward }

-- A gift waiting in someone's inbox (Systems/Gifts). `id` is the giver's
-- PurchaseId (or a Studio test id); `kind` is "pass" (`key`: a pass key) or
-- "boost" (`key`: a Config.BOOST_PRODUCTS key).
export type GiftEntry = {
	id: string,
	kind: string,
	key: string,
	fromId: number,
	fromName: string,
	time: number,
}

-- Who a gift is for: remembered from PrepareGift until the receipt.
export type GiftIntent = {
	recipientId: number,
	recipientName: string,
	productKey: string,
	expires: number, -- os.clock()
}

-- A player found by username for the gift window (FindPlayer).
export type FoundPlayer = { userId: number, name: string, displayName: string }

-- What a claimed reward gave (the Rewarded remote): Volts, boosts, and the
-- boosts swapped for Volts because the player owns that pass.
export type Rewarded = { volts: number, boosts: { RewardBoost }, swapped: { string } }

export type StormPhase = "Storm" | "Calm"

-- endsAt is in workspace:GetServerTimeNow() time, so every client's timer agrees.
export type StormState = {
	phase: StormPhase,
	endsAt: number,
	supercell: boolean?, -- this storm is a Supercell (Config.SUPERCELL)
	supercellAt: number?, -- a Supercell starts at this time (sent in the last 30 s before it)
}

-- A rare bolt (Config.BOLT_TYPES); "Normal" is every other bolt.
export type BoltType = "Normal" | "Golden" | "Rainbow" | "Ball"

-- key: the BoltType; chance: the odds per strike (0.02 = 2%); multiplier:
-- what it multiplies the catch's value by; label: its popup ("GOLDEN");
-- boostMinutes: a random timed boost for every catcher (Rainbow).
export type BoltTypeDef = {
	key: BoltType,
	chance: number,
	multiplier: number,
	label: string,
	color: Color3,
	boostMinutes: number?,
}

-- A scheduled event (Config.EVENTS) multiplies every sale while it's on.
-- startUtc/endUtc: a Unix time (a one-off event) or "Sat 00:00" style
-- weekday and UTC time (it repeats every week). The end minute is included.
export type EventDef = {
	name: string,
	startUtc: number | string,
	endUtc: number | string,
	multiplier: number,
	banner: string,
}

-- "Shared": everyone inside the circle catches it.
-- "Single": only the closest player inside the circle catches it.
export type ZoneMode = "Shared" | "Single"

-- A world: its own map (hub, sell station, zones) far from the others,
-- reached through a portal. Volts, bottles and boots carry over.
export type WorldDef = {
	id: string,
	displayName: string,
	tagline: string, -- shown on its portal and the welcome banner
	style: string, -- the world style it's built in (src/server/World/Styles/<style>)
	requiresBottle: number, -- bottle tier needed to go through its portal
	color: Color3, -- its portal and banner colour
	offset: Vector3, -- where its hub centre is (the first world's is the origin)
}

export type ZoneDef = {
	id: string, -- must match the part name in Workspace.Map.Zones (unique across worlds)
	world: string, -- id of the world it's in (Config.WORLDS)
	displayName: string,
	tagline: string, -- shown on the zone sign and banner
	color: Color3, -- border, sign and warning circle colour
	mode: ZoneMode,
	chargeValue: number, -- Volts per caught strike
	chargeSize: number, -- bottle units one caught strike fills (see Config.ZONES)
	strikeInterval: number, -- average seconds between strikes during a storm
	order: number, -- position along its world's zone spiral (1 = closest to the hub)
	requiresBottle: number, -- bottle tier needed to catch here (Util/Progression)
	premium: boolean?, -- Roblox Premium members only; pays per player (Util/Progression)

	-- World layout (see src/server/World). Zones are placed automatically on
	-- a spiral around the hub in `order`; these only describe the zone itself.
	theme: string, -- biome theme each world style decorates it with, e.g. "Beach"
	width: number, -- catch floor size in studs (side to side, facing the hub)
	depth: number, -- catch floor size in studs (from the gate to the back)
	floor: number, -- height of the catch floor above sea level
}

-- values: the five per-level numbers of the perk (level 1 to 5).
export type ResearcherDef = {
	id: string,
	name: string,
	role: string,
	price: number,
	perk: string, -- {v} is replaced by the level's value
	values: { number },
}

-- A Game Pass in the Boosts store (Config.PASSES).
export type PassDef = {
	key: string,
	id: number, -- game pass asset id (0 = not created yet)
	image: number, -- icon asset id (0 = use `icon`)
	name: string,
	icon: string, -- emoji fallback
	detail: string,
	price: number, -- Robux, a fallback until the real price loads
}

-- A Volts pack in the Boosts store (Config.VOLT_PACKS).
export type VoltPackDef = {
	key: string,
	productId: number, -- Developer Product id (0 = not created yet)
	image: number, -- icon asset id (0 = use `icon`)
	name: string,
	icon: string, -- emoji fallback
	charges: number, -- worth this many bolts from the buyer's best zone
	price: number, -- Robux, a fallback until the real price loads
}

-- A lightning colour Bolt Colours owners can pick (Config.BOLT_COLOURS).
export type BoltColourDef = {
	name: string,
	color: Color3,
}

export type BottleDef = {
	name: string,
	capacity: number,
	price: number,
}

-- speedBonus: added to the walk speed inside storm zones only.
export type BootsDef = {
	name: string,
	speedBonus: number,
	price: number,
}

-- Server -> all clients: a bolt is about to land here.
export type StrikeWarning = {
	id: number,
	zoneId: string,
	position: Vector3,
	radius: number,
	landsAt: number, -- workspace:GetServerTimeNow() time
	ownerId: number?, -- Storm Chaser balloon bolt: only this UserId can catch it
	boltType: BoltType?, -- a rare bolt (nil = Normal)
	-- Ball lightning: the orb drifts in a straight line from `position` to
	-- orbTo (both on the ground) for orbSeconds, starting at landsAt
	orbTo: Vector3?,
	orbSeconds: number?,
}

-- Server -> one client (a Forecaster's owner): the next strike's ring, early.
-- The public StrikeWarning for the same position goes out at warnsAt.
export type Forecast = {
	id: number,
	zoneId: string,
	position: Vector3,
	radius: number,
	warnsAt: number, -- workspace:GetServerTimeNow() time of the public warning
}

-- Server -> all clients: the bolt landed. Lists who caught it (UserIds) and
-- who was inside but had a full bottle.
export type StrikeLanded = {
	id: number,
	zoneId: string,
	position: Vector3,
	value: number,
	catchers: { number },
	values: { number }, -- Volts each catcher's charge is worth before the assay (catchers' order)
	full: { number },
	assayed: { number }, -- catchers whose charge was high grade (worth double)
	tanked: { number }, -- full players whose charge went into their Chemist's tank
	lucky: { number }, -- Lucky Charges catchers whose roll doubled the charge
	ownerId: number?, -- Storm Chaser balloon bolt: only this UserId could catch it
	boltType: BoltType?, -- a rare bolt (nil = Normal); `values` include its multiplier
	boost: string?, -- Rainbow: the boost key (Config.BOOSTS) every catcher got
}

return nil
