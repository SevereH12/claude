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
}

-- A hired researcher. post is "Office" or a zone id.
export type ResearcherSave = {
	level: number,
	data: number,
	post: string,
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

-- A reward: `charges` pays that many bolts from the player's best zone
-- (Util/Store.volts); `boosts` adds timed boosts.
export type RewardBoost = { key: string, minutes: number }
export type Reward = { charges: number?, boosts: { RewardBoost }? }

-- A playtime gift: claimable `minutes` into a session.
export type PlaytimeGift = { minutes: number, reward: Reward }

-- What a claimed reward gave (the Rewarded remote): Volts, boosts, and the
-- boosts swapped for Volts because the player owns that pass.
export type Rewarded = { volts: number, boosts: { RewardBoost }, swapped: { string } }

export type StormPhase = "Storm" | "Calm"

-- endsAt is in workspace:GetServerTimeNow() time, so every client's timer agrees.
export type StormState = {
	phase: StormPhase,
	endsAt: number,
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
}

return nil
