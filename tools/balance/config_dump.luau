--!nocheck
-- Prints the game's Config (zones, bottles, boots, strikes, research) as
-- JSON for the balance tools (tools/balance/*.py).
--   lune run tools/balance/config_dump.luau
local serde = require("@lune/serde")
local World = require("../harness/World")

local Config = World.new("src"):require("ReplicatedStorage.Shared.Config")
local zones = {}
for id, zone in Config.ZONES do
	table.insert(zones, {
		id = id,
		name = zone.displayName,
		chargeValue = zone.chargeValue,
		chargeSize = zone.chargeSize,
		strikeInterval = zone.strikeInterval,
		width = zone.width,
		depth = zone.depth,
		requiresBottle = zone.requiresBottle,
		premium = zone.premium == true,
	})
end
local bottles, boots = {}, {}
for _, b in Config.BOTTLES do
	table.insert(bottles, { name = b.name, capacity = b.capacity, price = b.price })
end
for _, b in Config.BOOTS do
	table.insert(boots, { name = b.name, speedBonus = b.speedBonus })
end
print(serde.encode("json", {
	zones = zones,
	bottles = bottles,
	boots = boots,
	STRIKE_RADIUS = Config.STRIKE_RADIUS,
	WARNING_TIME = Config.WARNING_TIME,
	STORM_DURATION = Config.STORM_DURATION,
	CALM_DURATION = Config.CALM_DURATION,
	WALK_SPEED_IN_ZONE = Config.WALK_SPEED_IN_ZONE,
	RESEARCH_LEVELS = Config.RESEARCH_LEVELS,
	RESEARCH_PRESTIGE = Config.RESEARCH_PRESTIGE,
}))
