--!strict
-- Every tunable number in the game. Balance changes happen here.
-- NOTE: replicated to clients, so nothing secret goes here. The server uses
-- its own copy of this file and never trusts numbers sent by a client.

local Types = require(script.Parent.Types)

local BOTTLES: { Types.BottleDef } = {
	{ name = "Jar", capacity = 5, price = 0 },
	{ name = "Flask", capacity = 15, price = 250 },
	{ name = "Battery Pack", capacity = 40, price = 1_500 },
	{ name = "Storm Cell", capacity = 100, price = 8_000 },
}

local ZONES: { [string]: Types.ZoneDef } = {
	Shoreline = {
		id = "Shoreline",
		displayName = "Shoreline",
		tagline = "Everyone catches the beach storms, 5 Volts",
		color = Color3.fromRGB(255, 220, 80),
		mode = "Shared",
		chargeValue = 5,
		strikeInterval = 0.8,
		order = 1,
		theme = "Beach",
		width = 112,
		depth = 132,
		floor = 4,
	},
	Mesa = {
		id = "Mesa",
		displayName = "Mesa",
		tagline = "Closest scientist takes the bolt, 20 Volts",
		color = Color3.fromRGB(255, 120, 60),
		mode = "Single",
		chargeValue = 20,
		strikeInterval = 1.2,
		order = 2,
		theme = "Canyon",
		width = 96,
		depth = 104,
		floor = 20,
	},
}

return table.freeze({
	-- Which world style MapBuilder builds (src/server/World/Styles/<name>).
	WORLD_STYLE = "WeatherLab",

	-- Saving
	AUTOSAVE_INTERVAL = 60, -- seconds between autosaves per player

	-- Storm cycle (seconds)
	FIRST_STORM_DELAY = 8, -- calm time when a server starts
	STORM_DURATION = 90,
	CALM_DURATION = 20,

	-- Strikes
	WARNING_TIME = 1.5, -- seconds between the warning circle and the bolt
	STRIKE_RADIUS = 8, -- studs; stand within this of the centre to catch
	STRIKE_MAX_HEIGHT_ABOVE = 8, -- studs; you can catch mid-jump, but not from below a cliff
	STRIKE_INTERVAL_JITTER = 0.3, -- +/-30% randomness on strike timing

	-- Movement: you move faster between zones so travel isn't a chore
	WALK_SPEED_IN_ZONE = 16, -- Roblox default
	WALK_SPEED_OUTSIDE = 30,

	-- Selling
	SELL_COOLDOWN = 1, -- seconds between sells per player

	BOTTLES = table.freeze(BOTTLES),
	ZONES = table.freeze(ZONES),

	-- Placeholder sounds (built into Roblox). Swap for Creator Store sounds.
	SOUNDS = table.freeze({
		STRIKE = "rbxasset://sounds/collide.wav",
		CATCH = "rbxasset://sounds/electronicpingshort.wav",
		SELL = "rbxasset://sounds/electronicpingshort.wav",
	}),
})
