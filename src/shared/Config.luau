--!strict
-- Every tunable number in the game. Balance changes happen here.
-- NOTE: replicated to clients, so nothing secret goes here. The server uses
-- its own copy of this file and never trusts numbers sent by a client.

local Types = require(script.Parent.Types)

-- Tier indexes are saved, so new tiers are only ever appended; inserting
-- one means a PlayerData migration that moves saved tiers up (Vial did).
local BOTTLES: { Types.BottleDef } = {
	{ name = "Jar", capacity = 5, price = 0 },
	{ name = "Vial", capacity = 10, price = 80 },
	{ name = "Flask", capacity = 15, price = 250 },
	{ name = "Battery Pack", capacity = 40, price = 1_500 },
	{ name = "Storm Cell", capacity = 100, price = 8_000 },
}

-- In-zone walk speed is WALK_SPEED_IN_ZONE + speedBonus. Keep every tier
-- below WALK_SPEED_OUTSIDE: boots only matter inside storm zones, where
-- speed decides who reaches a bolt first.
local BOOTS: { Types.BootsDef } = {
	{ name = "Rain Boots", speedBonus = 0, price = 0 }, -- everyone starts with these
	{ name = "Puddle Jumpers", speedBonus = 2, price = 300 },
	{ name = "Squall Skippers", speedBonus = 3, price = 900 },
	{ name = "Gale Striders", speedBonus = 4, price = 2_000 },
	{ name = "Thunder Treads", speedBonus = 6, price = 10_000 },
}

local RESEARCHERS: { Types.ResearcherDef } = {
	{
		id = "Forecaster",
		name = "Dr. Isobar",
		role = "Forecaster",
		price = 400,
		perk = "Early Warning: see the next strike's ring {v}s early",
		values = { 0.4, 0.6, 0.8, 1.0, 1.2 },
	},
	{
		id = "RodTech",
		name = "Ohmar",
		role = "Rod Tech",
		price = 1_500,
		perk = "Grounding Rod: +{v} studs catch radius",
		values = { 1, 1.5, 2, 2.5, 3 },
	},
	{
		id = "Analyst",
		name = "Prof. Kilowatt",
		role = "Analyst",
		price = 5_000,
		perk = "Charge Assay: {v}% of charges are worth double",
		values = { 10, 15, 20, 25, 30 },
	},
	{
		id = "Chemist",
		name = "Dr. Fizz",
		role = "Chemist",
		price = 12_000,
		perk = "Overflow Tank: a full bottle spills {v} charges into her tank",
		values = { 3, 6, 9, 12, 15 },
	},
	{
		id = "StormChaser",
		name = "Gale",
		role = "Storm Chaser",
		price = 30_000,
		perk = "Weather Balloon: a bolt only you can catch every {v}s",
		values = { 30, 24, 19, 15, 12 },
	},
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
		requiresBottle = 1, -- open to everyone
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
		requiresBottle = 3, -- the Flask
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
	FORECAST_MAX_LEAD = 1.2, -- seconds; the top Forecaster perk value. Public warnings wait this long
	BALLOON_MIN_DISTANCE = 12, -- studs from the owner; Storm Chaser bolts land this near
	BALLOON_MAX_DISTANCE = 20,
	STRIKE_INTERVAL_JITTER = 0.3, -- +/-30% randomness on strike timing

	-- Movement: you move faster between zones so travel isn't a chore.
	-- Boots add their speedBonus inside zones only (see BOOTS).
	WALK_SPEED_IN_ZONE = 16, -- Roblox default
	WALK_SPEED_OUTSIDE = 30,

	-- Selling
	SELL_COOLDOWN = 1, -- seconds between sells per player

	-- Researchers (Storm Society)
	RESEARCH_LEVELS = table.freeze({ 0, 40, 150, 400, 1000 }), -- field data needed for level 1..5
	RESEARCH_SETUP_TIME = 8, -- seconds a newly posted researcher needs before the perk works
	RESEARCH_DATA_WATCH = 1, -- data per strike landing in their zone
	RESEARCH_DATA_CATCH = 3, -- data per strike the owner caught

	RESEARCHERS = table.freeze(RESEARCHERS),
	BOTTLES = table.freeze(BOTTLES),
	BOOTS = table.freeze(BOOTS),
	ZONES = table.freeze(ZONES),

	-- Placeholder sounds (built into Roblox). Swap for Creator Store sounds.
	SOUNDS = table.freeze({
		STRIKE = "rbxasset://sounds/collide.wav",
		CATCH = "rbxasset://sounds/electronicpingshort.wav",
		SELL = "rbxasset://sounds/electronicpingshort.wav",
	}),
})
