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
	chargeCount: number, -- charges in the bottle (limited by capacity)
	chargeValue: number, -- Volts those charges sell for
	researchers: { [string]: ResearcherSave }, -- hired researchers by role id
	tankCount: number, -- Chemist's overflow tank: charges held
	tankValue: number, -- Volts those charges sell for
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
}

export type StormPhase = "Storm" | "Calm"

-- endsAt is in workspace:GetServerTimeNow() time, so every client's timer agrees.
export type StormState = {
	phase: StormPhase,
	endsAt: number,
}

-- "Shared": everyone inside the circle catches it.
-- "Single": only the closest player inside the circle catches it.
export type ZoneMode = "Shared" | "Single"

export type ZoneDef = {
	id: string, -- must match the part name in Workspace.Map.Zones
	displayName: string,
	tagline: string, -- shown on the zone sign and banner
	color: Color3, -- border, sign and warning circle colour
	mode: ZoneMode,
	chargeValue: number, -- Volts per caught charge
	strikeInterval: number, -- average seconds between strikes during a storm
	order: number, -- position along the zone spiral (1 = closest to the hub)

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
	full: { number },
	assayed: { number }, -- catchers whose charge was high grade (worth double)
	tanked: { number }, -- full players whose charge went into their Chemist's tank
	ownerId: number?, -- Storm Chaser balloon bolt: only this UserId could catch it
}

return nil
