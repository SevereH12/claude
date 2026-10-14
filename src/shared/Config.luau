--!strict
-- Tunable gameplay values. Change balance here.
-- NOTE: replicated to clients, so nothing secret goes here. The server uses
-- its own copy of this file and never trusts numbers sent by a client.

local Types = require(script.Parent.Types)

local UPGRADES: { [string]: Types.UpgradeDef } = {
	ClickPower = {
		id = "ClickPower",
		name = "Click Power",
		description = "+1 coin per click",
		basePrice = 10,
		priceGrowth = 1.15,
		maxLevel = 500,
		order = 1,
	},
	AutoClicker = {
		id = "AutoClicker",
		name = "Auto Clicker",
		description = "+1 coin every second",
		basePrice = 50,
		priceGrowth = 1.18,
		maxLevel = 500,
		order = 2,
	},
	GoldenHands = {
		id = "GoldenHands",
		name = "Golden Hands",
		description = "+10% to all coins",
		basePrice = 500,
		priceGrowth = 1.6,
		maxLevel = 50,
		order = 3,
	},
}

return table.freeze({
	-- Saving
	AUTOSAVE_INTERVAL = 60, -- seconds between autosaves per player

	-- Clicking
	BASE_CLICK_VALUE = 1,
	MAX_CLICKS_PER_SECOND = 15, -- server-side cap; extra clicks are dropped
	CLICK_BURST = 20,

	-- Upgrades
	UPGRADES = table.freeze(UPGRADES),
	AUTO_CLICKER_PER_LEVEL = 1, -- coins per second per Auto Clicker level
	GOLDEN_HANDS_BONUS = 0.1, -- +10% per level

	-- Rebirth: resets coins and upgrades, gives a permanent multiplier
	REBIRTH_BASE_COST = 10_000,
	REBIRTH_COST_GROWTH = 3,
	REBIRTH_MULTIPLIER = 0.5, -- +50% coins per rebirth
})
