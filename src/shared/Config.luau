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
	{ name = "Tempest Tank", capacity = 250, price = 40_000 },
	{ name = "Dynamo Drum", capacity = 600, price = 200_000 },
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
	{ name = "Coil Striders", speedBonus = 7, price = 35_000 },
	{ name = "Arc Runners", speedBonus = 8, price = 150_000 },
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

-- Worlds, in travel order. Each is its own map (src/server/World) in its
-- own style, built `offset` studs from the first, with its own hub, sell
-- station and zones. A portal at each hub leads to the next world (and
-- back); you can go through once you own its bottle. Volts, bottles and
-- boots are the same everywhere.
local WORLDS: { Types.WorldDef } = {
	{
		id = "Bay",
		displayName = "Barometer Bay",
		tagline = "Where every storm chaser starts",
		style = "WeatherLab",
		requiresBottle = 1,
		color = Color3.fromRGB(255, 214, 90),
		offset = Vector3.zero,
	},
	{
		id = "Voltcliff",
		displayName = "Voltcliff Works",
		tagline = "Copper coils, factory islands, bigger storms",
		style = "StormPunk",
		requiresBottle = 5, -- the Storm Cell
		color = Color3.fromRGB(90, 238, 255),
		-- far enough that the two 2048-stud seas don't meet
		offset = Vector3.new(5000, 0, 0),
	},
}

-- chargeSize is how many bottle units one caught strike fills. Later zones
-- fill more per strike, but Volts per unit (chargeValue / chargeSize) must
-- strictly rise from each zone to the next in progression order (world,
-- then requiresBottle, then order), so a full bottle is always worth more
-- in a bigger zone; and a zone's required bottle must hold at least 5 of
-- its strikes. Keep both when adding a zone (tools/harness/test_formulas).
local ZONES: { [string]: Types.ZoneDef } = {
	Shoreline = {
		id = "Shoreline",
		world = "Bay",
		displayName = "Shoreline",
		tagline = "Everyone catches the beach storms, 5 Volts",
		color = Color3.fromRGB(255, 220, 80),
		mode = "Shared",
		chargeValue = 5,
		chargeSize = 1,
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
		world = "Bay",
		displayName = "Mesa",
		tagline = "Closest scientist takes the bolt, 20 Volts",
		color = Color3.fromRGB(255, 120, 60),
		mode = "Single",
		chargeValue = 20,
		chargeSize = 2,
		strikeInterval = 1.2,
		order = 2,
		requiresBottle = 3, -- the Flask
		theme = "Canyon",
		width = 96,
		depth = 104,
		floor = 20,
	},
	Aurora = {
		id = "Aurora",
		world = "Bay",
		displayName = "Aurora Reef",
		tagline = "Premium members only, 1.5x your best zone",
		color = Color3.fromRGB(176, 120, 255), -- violet; its theme trims it in gold
		mode = "Shared",
		chargeValue = 0, -- unused: pays PREMIUM_VALUE_MULTIPLIER x each player's best zone
		chargeSize = 1, -- unused: a Premium zone fills like the player's best zone
		strikeInterval = 0.6,
		order = 3,
		requiresBottle = 1,
		premium = true, -- Roblox Premium members only (no Game Pass)
		theme = "Premium",
		width = 100,
		depth = 110,
		floor = 12,
	},
	-- Voltcliff Works (world 2), in StormPunk's own zone looks
	Yard = {
		id = "Yard",
		world = "Voltcliff",
		displayName = "Generator Yard",
		tagline = "Everyone catches the coil storms, 60 Volts",
		color = Color3.fromRGB(70, 160, 255), -- electric blue
		mode = "Shared",
		chargeValue = 60,
		chargeSize = 3,
		strikeInterval = 0.9,
		order = 1,
		requiresBottle = 5, -- the Storm Cell (the world's own entry rule)
		theme = "Default",
		width = 104,
		depth = 116,
		floor = 8,
	},
	Tidewire = {
		id = "Tidewire",
		world = "Voltcliff",
		displayName = "Tidewire Beach",
		tagline = "Everyone catches the tide storms, 150 Volts",
		color = Color3.fromRGB(80, 230, 150), -- sea green
		mode = "Shared",
		chargeValue = 150,
		chargeSize = 5,
		strikeInterval = 0.8,
		order = 2,
		requiresBottle = 6, -- the Tempest Tank
		theme = "Beach",
		width = 96,
		depth = 104,
		floor = 4,
	},
	Thunderhead = {
		id = "Thunderhead",
		world = "Voltcliff",
		displayName = "Thunderhead Mesa",
		tagline = "Closest scientist takes the bolt, 500 Volts",
		color = Color3.fromRGB(255, 80, 120), -- hot pink
		mode = "Single",
		chargeValue = 500,
		chargeSize = 8,
		strikeInterval = 1.2,
		order = 3,
		requiresBottle = 7, -- the Dynamo Drum
		theme = "Canyon",
		width = 100,
		depth = 110,
		floor = 20,
	},
}

-- Game Passes (the Boosts store's GAME PASSES tab; Systems/Passes and
-- Util/Passes). `id` is the pass's asset id from the Creator Dashboard (0 =
-- not made yet: the card says COMING SOON); `image` its icon's asset id
-- (0 = show `icon`). Both come from tools/store/store_ids.json. `price` is
-- Robux, shown only until Roblox's real price loads.
local PASSES: { Types.PassDef } = {
	{
		key = "DoubleVolts",
		id = 2048024542,
		image = 95848544228868,
		name = "2x Volts",
		icon = "⚡",
		detail = "Every sale pays double Volts",
		price = 249,
	},
	{
		key = "RemoteSell",
		id = 2046141229,
		image = 136457008950452,
		name = "Remote Sell",
		icon = "📡",
		detail = "A SELL button that works anywhere",
		price = 199,
	},
	{
		key = "BigBottles",
		id = 2045925293,
		image = 72710876564301,
		name = "Big Bottles",
		icon = "🧪",
		detail = "Every bottle holds 50% more",
		price = 149,
	},
	{
		key = "LuckyCharges",
		id = 2045049270,
		image = 121828277208800,
		name = "Lucky Charges",
		icon = "🍀",
		detail = "Each charge you catch has a 15% chance to be worth double",
		price = 149,
	},
	{
		key = "LabGrant",
		id = 2046189262,
		image = 139170195972752,
		name = "Lab Grant",
		icon = "🔬",
		detail = "Researchers set up instantly and gain field data 2x as fast",
		price = 199,
	},
	{
		key = "VIP",
		id = 2044617289,
		image = 107045645261408,
		name = "VIP",
		icon = "👑",
		detail = "Golden bottle and lightning, a VIP chat tag and title, and 10% more Volts",
		price = 399,
	},
	{
		key = "BoltColours",
		id = 2045751309,
		image = 137026123419252,
		name = "Bolt Colours",
		icon = "🌈",
		detail = "Choose the colour of the lightning that arcs into your bottle",
		price = 99,
	},
	{
		key = "JetBoots",
		id = 2045211315,
		image = 123712582846727,
		name = "Jet Boots",
		icon = "🚀",
		detail = "50% faster outside storm zones, with a jet trail. Zone speed is unchanged",
		price = 99,
	},
}

-- What the passes do (Util/Passes).
local PASS_VALUES = {
	doubleVolts = 2, -- 2x Volts: sale multiplier
	bigBottles = 1.5, -- Big Bottles: capacity multiplier (rounded down)
	luckyChance = 0.15, -- Lucky Charges: chance a caught charge is worth double
	remoteSellCooldown = 5, -- seconds between Remote Sells
	remoteSellChargeUp = 1.5, -- seconds the SELL button charges before it fires
	vipVolts = 1.1, -- VIP: sale multiplier (times 2x Volts if owned too)
	labGrantData = 2, -- Lab Grant: field data multiplier (and no set-up time)
	jetBoots = 1.5, -- Jet Boots: walk speed multiplier outside storm zones
}

-- VIP's gold: the bottle's glass and charge, and its lightning arcs.
local VIP_GOLD = Color3.fromRGB(255, 196, 40)

-- Bolt Colours: the lightning colours an owner can pick (the profile saves
-- the index; 0 = the default). All bright enough to read in a storm.
local BOLT_COLOURS: { Types.BoltColourDef } = {
	{ name = "Plasma Pink", color = Color3.fromRGB(255, 70, 200) },
	{ name = "Toxic Green", color = Color3.fromRGB(80, 255, 90) },
	{ name = "Solar Orange", color = Color3.fromRGB(255, 140, 30) },
	{ name = "Ion Violet", color = Color3.fromRGB(170, 90, 255) },
	{ name = "Arc Cyan", color = Color3.fromRGB(50, 240, 255) },
	{ name = "Ruby Red", color = Color3.fromRGB(255, 55, 70) },
	{ name = "Royal Blue", color = Color3.fromRGB(70, 120, 255) },
	{ name = "Frost White", color = Color3.fromRGB(235, 245, 255) },
}

-- Volts packs: Developer Products in the Boosts store's VOLTS tab, granted
-- by Systems/Receipts. A pack gives `charges` x the bolt value of the best
-- non-premium zone the player can enter (Util/Store), so it's worth the
-- same playtime however far they've got. `productId` is the Developer
-- Product id (0 = not made yet: the card says COMING SOON) and `image` its
-- icon, both from tools/store/store_ids.json. `price` is Robux, shown only
-- until Roblox's real price loads.
local VOLT_PACKS: { Types.VoltPackDef } = {
	{
		key = "PocketCharge",
		productId = 3720985702,
		image = 127085435030754,
		name = "Pocket Charge",
		icon = "🔋",
		charges = 200,
		price = 49,
	},
	{
		key = "StormJar",
		productId = 3720985707,
		image = 134743613951662,
		name = "Storm Jar",
		icon = "⚡",
		charges = 1_000,
		price = 199,
	},
	{
		key = "ThunderCrate",
		productId = 3720985721,
		image = 78950177669740,
		name = "Thunder Crate",
		icon = "📦",
		charges = 6_000,
		price = 899,
	},
	{
		key = "LightningVault",
		productId = 3720985735,
		image = 94510144428546,
		name = "Lightning Vault",
		icon = "🏦",
		charges = 40_000,
		price = 3_999,
	},
}

-- Offers, the free 2x Volts trial and purchases (Controllers/Offers,
-- Systems/Store, Systems/Receipts, Util/Store).
local STORE = {
	offerFirstAfter = 180, -- seconds into a session before any offer shows
	offerGap = 300, -- seconds between two offers
	offerFarFromSell = 60, -- studs: a full bottle this far from a sell station suggests Remote Sell
	trialAfterSales = 3, -- the free trial is offered from this many sales into a session
	trialSeconds = 180, -- how long the free 2x Volts trial lasts
	purchaseHistory = 100, -- Volts pack purchase ids each profile remembers
	-- for "about N minutes of catching" on a pack: bolts a steady player
	-- catches a minute, selling trips included (an estimate: tune it)
	catchesPerMinute = 10,
}

return table.freeze({
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

	-- Premium zones pay this many times the best other zone the player can
	-- enter, so they're worth a visit at every stage (Progression.boltValue)
	PREMIUM_VALUE_MULTIPLIER = 1.5,

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
	WORLDS = table.freeze(WORLDS),
	ZONES = table.freeze(ZONES),
	PASSES = table.freeze(PASSES),
	PASS_VALUES = table.freeze(PASS_VALUES),
	VIP_GOLD = VIP_GOLD,
	BOLT_COLOURS = table.freeze(BOLT_COLOURS),
	VOLT_PACKS = table.freeze(VOLT_PACKS),
	STORE = table.freeze(STORE),

	-- Placeholder sounds (built into Roblox). Swap for Creator Store sounds.
	SOUNDS = table.freeze({
		STRIKE = "rbxasset://sounds/collide.wav",
		CATCH = "rbxasset://sounds/electronicpingshort.wav",
		SELL = "rbxasset://sounds/electronicpingshort.wav",
	}),
})
