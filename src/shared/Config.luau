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
	{ name = "Rune Cell", capacity = 1_500, price = 1_000_000 },
	{ name = "Storm Core", capacity = 4_000, price = 5_000_000 },
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
	{ name = "Sky Treads", speedBonus = 9, price = 600_000 },
	{ name = "Cloud Walkers", speedBonus = 10, price = 3_000_000 },
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
	{
		id = "Stormspire",
		displayName = "Stormspire Isles",
		tagline = "Floating isles, rune bridges, the wildest storms",
		style = "SkyIsles",
		requiresBottle = 7, -- the Dynamo Drum
		color = Color3.fromRGB(190, 140, 255),
		offset = Vector3.new(10000, 0, 0),
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
	-- Stormspire Isles (world 3), in SkyIsles' own zone looks
	Spire = {
		id = "Spire",
		world = "Stormspire",
		displayName = "Rune Spire",
		tagline = "Everyone catches the rune storms, 1,200 Volts",
		color = Color3.fromRGB(150, 110, 255), -- rune violet
		mode = "Shared",
		chargeValue = 1_200,
		chargeSize = 13,
		strikeInterval = 0.9,
		order = 1,
		requiresBottle = 7, -- the Dynamo Drum (the world's own entry rule)
		theme = "Default",
		width = 104,
		depth = 116,
		floor = 12,
	},
	Cloudshore = {
		id = "Cloudshore",
		world = "Stormspire",
		displayName = "Cloudshore",
		tagline = "Everyone catches the cloud storms, 3,000 Volts",
		color = Color3.fromRGB(255, 205, 70), -- sun gold
		mode = "Shared",
		chargeValue = 3_000,
		chargeSize = 21,
		strikeInterval = 0.8,
		order = 2,
		requiresBottle = 8, -- the Rune Cell
		theme = "Beach",
		width = 112,
		depth = 132,
		floor = 4,
	},
	Ember = {
		id = "Ember",
		world = "Stormspire",
		displayName = "Ember Mesa",
		tagline = "Closest scientist takes the bolt, 10,000 Volts",
		color = Color3.fromRGB(255, 130, 50), -- ember orange
		mode = "Single",
		chargeValue = 10_000,
		chargeSize = 34,
		strikeInterval = 1.2,
		order = 3,
		requiresBottle = 9, -- the Storm Core
		theme = "Canyon",
		width = 96,
		depth = 104,
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

-- Timed boosts (Util/Boosts, Systems/Boosts): each switches a Game Pass's
-- effect on for a while. Time stacks up to BOOST_CAP and only counts down
-- while the player is in the game.
local BOOSTS: { Types.BoostDef } = {
	{ key = "DoubleVolts", pass = "DoubleVolts", name = "2x Volts", icon = "⚡" },
	{ key = "Lucky", pass = "LuckyCharges", name = "Lucky", icon = "🍀" },
	{ key = "BigBottles", pass = "BigBottles", name = "Big Bottles", icon = "🧪" },
}

-- Boosts you can buy (Developer Products, the store's BOOSTS tab): FOR ME
-- adds one to your own boosts, GIFT sends it to anyone the way passes are
-- gifted (Systems/Gifts). `boosts` is what one gives (BOOSTS keys and
-- minutes); bought or gifted time adds in full, past BOOST_CAP. The Server
-- Storm gives everyone in the server 2x Volts instead (SERVER_STORM) and is
-- FOR ME only. Product ids (0 = not made yet: COMING SOON) and icons from
-- tools/store/store_ids.json; `price` is Robux, shown only until Roblox's
-- real price loads.
local BOOST_PRODUCTS: { Types.BoostProductDef } = {
	{
		key = "DoubleVoltsBoost",
		productId = 3721137662,
		image = 101516275083716,
		name = "2x Volts Boost",
		icon = "⚡",
		detail = "Every sale pays double for 30 minutes",
		price = 49,
		boosts = { { key = "DoubleVolts", minutes = 30 } },
	},
	{
		key = "LuckyBoost",
		productId = 3721137679,
		image = 96996679069158,
		name = "Lucky Boost",
		icon = "🍀",
		detail = "15% of caught charges are worth double for 30 minutes",
		price = 49,
		boosts = { { key = "Lucky", minutes = 30 } },
	},
	{
		key = "BigBottlesBoost",
		productId = 3721137685,
		image = 73734835193406,
		name = "Big Bottles Boost",
		icon = "🧪",
		detail = "Every bottle holds 50% more for 30 minutes",
		price = 49,
		boosts = { { key = "BigBottles", minutes = 30 } },
	},
	{
		key = "BoostBundle",
		productId = 3721137691,
		image = 84026702746532,
		name = "Boost Bundle",
		icon = "🎁",
		detail = "2x Volts, Lucky and Big Bottles, all for 1 hour",
		price = 149,
		boosts = {
			{ key = "DoubleVolts", minutes = 60 },
			{ key = "Lucky", minutes = 60 },
			{ key = "BigBottles", minutes = 60 },
		},
	},
	{
		key = "ServerStorm",
		productId = 3721137706,
		image = 128152813396668,
		name = "Server Storm",
		icon = "🌩️",
		detail = "2x Volts for EVERYONE in this server for 15 minutes",
		price = 199,
		serverStorm = true,
	},
}

-- The 7-day login streak (Systems/Rewards): one reward per UTC day, in a
-- row; missing a day starts again at day 1, and so does the day after day 7.
-- `charges` pays that many bolts from the player's best zone, so a reward is
-- worth the same playtime early or late (Util/Store.volts).
local DAILY_REWARDS: { Types.Reward } = {
	{ charges = 100 },
	{ boosts = { { key = "DoubleVolts", minutes = 10 } } },
	{ charges = 250 },
	{ boosts = { { key = "Lucky", minutes = 15 } } },
	{ charges = 500 },
	{ boosts = { { key = "DoubleVolts", minutes = 20 } } },
	{
		charges = 1_500,
		boosts = {
			{ key = "DoubleVolts", minutes = 30 },
			{ key = "BigBottles", minutes = 30 },
		},
	},
}

-- Playtime gifts: claimable this many minutes into every session.
local PLAYTIME_GIFTS: { Types.PlaytimeGift } = {
	{ minutes = 5, reward = { charges = 30 } },
	{ minutes = 10, reward = { charges = 60 } },
	{ minutes = 20, reward = { boosts = { { key = "Lucky", minutes = 10 } } } },
	{ minutes = 30, reward = { charges = 150 } },
	{ minutes = 45, reward = { boosts = { { key = "DoubleVolts", minutes = 10 } } } },
	{ minutes = 60, reward = { charges = 400 } },
}

-- Gifting passes (Systems/Gifts): nobody can buy a game pass for someone
-- else, so each pass has a "Gift: <pass>" Developer Product at the same
-- price (product key "Gift" .. pass key). Buying one unlocks the pass's
-- effect for the receiver in this game. Product ids (0 = not made yet) and
-- icons from tools/store/store_ids.json.
local GIFT_PASS_PRODUCTS: { [string]: number } = {
	DoubleVolts = 3721137563,
	RemoteSell = 3721137576,
	BigBottles = 3721137585,
	LuckyCharges = 3721137597,
	LabGrant = 3721137610,
	VIP = 3721137629,
	BoltColours = 3721137641,
	JetBoots = 3721137651,
}
local GIFT_ICONS: { [string]: number } = {
	GiftDoubleVolts = 112415607210263,
	GiftRemoteSell = 71157669116473,
	GiftBigBottles = 107201834217143,
	GiftLuckyCharges = 139857084073545,
	GiftLabGrant = 88822516045093,
	GiftVIP = 134876522989863,
	GiftBoltColours = 109747228299462,
	GiftJetBoots = 138738735787414,
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
	FORECAST_MAX_LEAD = 1.92, -- seconds; the top Forecaster perk at rank 6 (1.2 x 1.6). Public warnings wait this long
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

	-- The menu's Teleport panel: seconds between trips (walking through a
	-- portal has its own short cooldown in Systems/Travel)
	TELEPORT_COOLDOWN = 10,

	-- Researchers (Storm Society)
	RESEARCH_LEVELS = table.freeze({ 0, 40, 150, 400, 1000 }), -- field data needed for level 1..5
	RESEARCH_SETUP_TIME = 8, -- seconds a newly posted researcher needs before the perk works
	RESEARCH_DATA_WATCH = 1, -- data per strike landing in their zone
	RESEARCH_DATA_CATCH = 3, -- data per strike the owner caught
	-- Promoting researchers (Util/Research; tools/balance/prestige.py works
	-- these out from the zones, bottles and strikes and checks them):
	-- dataScale[rank + 1] multiplies RESEARCH_LEVELS at that rank (the last
	-- one repeats at the top rank), glintCost[rank] is what promotion to
	-- that rank costs, in Glints of its tier or higher, and each rank makes
	-- the perk perkBonusPerRank stronger.
	RESEARCH_PRESTIGE = table.freeze({
		dataScale = table.freeze({ 1.15, 1.8, 2.85, 3.7, 3.7, 4.5, 4.5 }),
		glintCost = table.freeze({ 45, 65, 130, 85, 165, 50 }),
		perkBonusPerRank = 0.10,
	}),

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
	BOOSTS = table.freeze(BOOSTS),
	BOOST_CAP = 2 * 60 * 60, -- seconds reward boosts can stack up to (bought time adds in full)
	BOOST_PRODUCTS = table.freeze(BOOST_PRODUCTS),
	-- a Server Storm (Systems/Boosts): everyone in the server sells for this
	-- much more (times passes and boosts); each purchase adds `minutes`, up
	-- to `maxMinutes` left. It isn't saved: it belongs to the server.
	SERVER_STORM = table.freeze({
		minutes = 15,
		maxMinutes = 60,
		multiplier = 2,
	}),
	DAILY_REWARDS = table.freeze(DAILY_REWARDS),
	PLAYTIME_GIFTS = table.freeze(PLAYTIME_GIFTS),
	-- a boost reward for a pass the player owns pays Volts instead: this many
	-- charges per minute of boost (about a minute of catching)
	REWARD_SWAP_CHARGES = 10,

	-- The group that owns the game (Systems/Group): members get GROUP_BONUS
	-- more Volts on every sale. To use another group, change GROUP_ID (and
	-- GROUP_NAME, which the REWARDS panel shows).
	GROUP_ID = 7889739,
	GROUP_NAME = "Super Studio",
	GROUP_BONUS = 0.10,
	GROUP_COLOR = Color3.fromRGB(80, 200, 255), -- the [Member] chat tag

	-- The AFK Lounge (Systems/Afk, Util/Afk): standing in it pays this
	-- fraction of the player's best grinding rate (passes, boosts, the group
	-- and a Server Storm all count). The grinding rate in Util/Afk is already
	-- higher than real play, so 10% is clearly worse than playing.
	AFK = table.freeze({
		rateFraction = 0.10, -- 90% less than grinding
		premiumRateFraction = 0.15, -- Roblox Premium members
		enterSeconds = 10, -- seconds inside before AFK starts
		payEverySeconds = 60,
		recomputeSeconds = 15,
		-- Roblox disconnects after about 20 idle minutes. While AFK the client
		-- answers Idled with VirtualUser; at this much idle time (or if that
		-- fails) the server moves you to a fresh server, back in the lounge.
		idleRejoinMinutes = 17,
		rejoinRetrySeconds = 30, -- a failed move is tried once more after this
	}),

	GIFT_PASS_PRODUCTS = table.freeze(GIFT_PASS_PRODUCTS),
	GIFT_ICONS = table.freeze(GIFT_ICONS),
	GIFTS = table.freeze({
		intentSeconds = 300, -- how long "who it's for" is remembered before buying
		inboxCap = 100, -- undelivered gifts one player can have waiting
		receivedCap = 200, -- delivered gift ids each profile remembers (no doubles)
	}),

	-- Placeholder sounds (built into Roblox). Swap for Creator Store sounds.
	SOUNDS = table.freeze({
		STRIKE = "rbxasset://sounds/collide.wav",
		CATCH = "rbxasset://sounds/electronicpingshort.wav",
		SELL = "rbxasset://sounds/electronicpingshort.wav",
	}),
})
