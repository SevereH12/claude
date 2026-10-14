--!strict
-- Shared type definitions. Types that cross the client/server boundary
-- (remote payloads, profile schema) live here so both sides agree.

-- What gets saved to the DataStore for each player.
export type Profile = {
	version: number,
	coins: number,
	totalCoins: number,
	rebirths: number,
	upgrades: { [string]: number }, -- upgrade id -> level
}

-- What the server sends the client whenever the player's state changes.
export type Snapshot = {
	coins: number,
	totalCoins: number,
	rebirths: number,
	upgrades: { [string]: number },
}

export type UpgradeDef = {
	id: string,
	name: string,
	description: string,
	basePrice: number,
	priceGrowth: number, -- each level costs this much more (1.15 = +15%)
	maxLevel: number,
	order: number, -- position in the shop list
}

return nil
