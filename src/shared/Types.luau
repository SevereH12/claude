--!strict
-- Shared type definitions. Types that cross the client/server boundary
-- (remote payloads, profile schema) live here so both sides agree.

-- What gets saved to the DataStore for each player.
export type Profile = {
	version: number,
	volts: number,
	totalVolts: number, -- lifetime earnings (for stats/leaderboards later)
	bottleTier: number, -- index into Config.BOTTLES
	chargeCount: number, -- charges in the bottle (limited by capacity)
	chargeValue: number, -- Volts those charges sell for
}

-- Sent to the owning client whenever their state changes.
export type Snapshot = {
	volts: number,
	totalVolts: number,
	bottleTier: number,
	chargeCount: number,
	chargeValue: number,
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
	mode: ZoneMode,
	chargeValue: number, -- Volts per caught charge
	strikeInterval: number, -- average seconds between strikes during a storm
	order: number,
}

export type BottleDef = {
	name: string,
	capacity: number,
	price: number,
}

-- Server -> all clients: a bolt is about to land here.
export type StrikeWarning = {
	id: number,
	zoneId: string,
	position: Vector3,
	radius: number,
	landsAt: number, -- workspace:GetServerTimeNow() time
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
}

return nil
