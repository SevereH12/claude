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

-- Boots add speedBonus to your walk speed inside storm zones (never
-- between zones). Each zone's storm takes some back ("storm drag", worked
-- out by Util/Speed from these prices and the bottles' prices), so a
-- typical player walks into every zone at WALK_SPEED_IN_ZONE and every
-- pair bought there makes them faster again. In-zone speed stays between
-- ZONE_SPEED.min and ZONE_SPEED.max.
local BOOTS: { Types.BootsDef } = {
	{ name = "Rain Boots", speedBonus = 0, price = 0 }, -- everyone starts with these
	{ name = "Puddle Jumpers", speedBonus = 4, price = 300 },
	{ name = "Squall Skippers", speedBonus = 8, price = 900 },
	{ name = "Gale Striders", speedBonus = 12, price = 2_000 },
	{ name = "Thunder Treads", speedBonus = 16, price = 10_000 },
	{ name = "Coil Striders", speedBonus = 20, price = 35_000 },
	{ name = "Arc Runners", speedBonus = 24, price = 150_000 },
	{ name = "Sky Treads", speedBonus = 28, price = 600_000 },
	{ name = "Cloud Walkers", speedBonus = 32, price = 3_000_000 },
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

-- Daily and weekly quests (Util/Quests picks them, Systems/Quests pays
-- them). Each day a player gets `daily` quests and each week `weekly`,
-- picked from these templates by their userId and the date, so they're the
-- same all day. Amounts are for bottle tier 1; `perTier` adds that fraction
-- for each tier above (bigger bottles, bigger quests). "Volts" amounts are
-- minutes of the player's grinding rate in their best zone (Util/Afk), so
-- that quest takes the same time early or late. Rewards pay like the daily
-- streak (`charges` = bolts from the best zone, Util/Store.volts).
local QUEST_TEMPLATES: { Types.QuestTemplate } = {
	{ key = "Catch", daily = 120, weekly = 900, perTier = 0.15, reward = { charges = 150 } },
	{ key = "CatchZone", daily = 70, weekly = 500, perTier = 0.15, reward = { charges = 150 } },
	{
		key = "Sell",
		daily = 4,
		weekly = 30,
		reward = { boosts = { { key = "DoubleVolts", minutes = 10 } } },
	},
	{
		key = "Golden",
		daily = 1,
		weekly = 8,
		reward = { boosts = { { key = "Lucky", minutes = 10 } } },
	},
	{ key = "Volts", daily = 15, weekly = 120, reward = { charges = 200 } },
	{ key = "Play", daily = 20, weekly = 150, reward = { charges = 150 } },
	-- weekly only, and only for players who have hired a researcher
	{ key = "Promote", weekly = 1, reward = { charges = 200 } },
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

-- Rare bolts (Util/Weather picks one per strike; Systems/Strikes pays it).
-- `chance` is per strike; `multiplier` multiplies that catch's value (luck
-- and the assay still stack on top; the bottle space stays the same).
local BOLT_TYPES: { Types.BoltTypeDef } = {
	{
		key = "Golden",
		chance = 0.02,
		multiplier = 10,
		label = "GOLDEN",
		color = Color3.fromRGB(255, 200, 40),
	},
	{
		key = "Rainbow",
		chance = 0.004,
		multiplier = 25,
		label = "RAINBOW",
		color = Color3.fromRGB(255, 120, 220),
		boostMinutes = 5, -- plus this long of a random timed boost (Config.BOOSTS)
	},
	{
		key = "Ball",
		chance = 0.01,
		multiplier = 5,
		label = "BALL LIGHTNING",
		color = Color3.fromRGB(150, 230, 255),
	},
}

-- Scheduled events (Util/Weather): every sale pays `multiplier` times more
-- while one is on. A "Sat 00:00" style time repeats every week (UTC); a
-- number is a one-off Unix time.
local EVENTS: { Types.EventDef } = {
	{
		name = "Double Volts Weekend",
		startUtc = "Sat 00:00",
		endUtc = "Sun 23:59",
		multiplier = 2,
		banner = "2x Volts on every sale, all weekend!",
	},
}

-- The Storm Log (Util/StormLog, the LOG tab in RESEARCH): a collection book
-- worked out from the lifetime stat counters. Finishing a row (say every
-- bolt type in Mesa) pays its page's `rowReward` once; every finished page
-- adds `pageBonus` to all Volts for good, up to `maxBonus`.
local STORM_LOG_PAGES: { Types.StormLogPageDef } = {
	{ id = "Bolts", title = "BOLTS", icon = "⚡", rowReward = { charges = 250 } },
	{
		id = "Places",
		title = "PLACES",
		icon = "🗺",
		rowReward = { boosts = { { key = "DoubleVolts", minutes = 15 } } },
	},
	{ id = "Team", title = "TEAM", icon = "🔬", rowReward = { charges = 400 } },
	{
		id = "Weather",
		title = "WEATHER",
		icon = "🌀",
		rowReward = { charges = 300, boosts = { { key = "Lucky", minutes = 20 } } },
	},
}

-- Gameplay tips (Util/Hints, Systems/Hints, Controllers/Hints): after the
-- new-player tutorial, small one-time hints (a short toast and a gentle glow
-- on the right button) show each part of the game when it becomes useful.
-- Each shows once ever (saved as profile.hintsSeen). Rules for when one may
-- show: the tutorial is done, it's on in SETTINGS ("Gameplay tips"), no
-- panel or menu is open, the player isn't catching in a storm or AFK, at
-- least `firstDelay` seconds after joining (or finishing the tutorial) and
-- `gapSeconds` after the last hint. Then the first hint in this list whose
-- trigger is true (and that wasn't seen) shows.
--
-- Each hint:
--   id      saved in the profile: never rename one (a new id shows again)
--   when    its trigger, a condition name from Util/Hints.CONDITIONS
--   minutes (optional) and only after this many minutes in this visit
--   text    what it says (keep it short: it's a two-line toast).
--           {groupBonus}, {friendBonus} and {friendMax} are filled in.
--   open    (optional) tapping it opens: shop, shopBoots, research,
--           researchLog, rewards, quests, top, boosts, teleport, settings,
--           sell (Controllers/Hints)
--   glow    (optional) what glows while it shows: a menu tile ("SHOP",
--           "RESEARCH", "TELEPORT", "BOOSTS", "REWARDS", "SETTINGS"; the
--           MENU button glows until the menu is open) or a HUD piece
--           ("RemoteSell", "ServerGoal")
local HINTS: { Types.HintDef } = {
	-- things that are happening right now come first
	{
		id = "remoteSell",
		when = "remoteSellFull",
		text = "Your bottle's full: Remote Sell sells it from anywhere!",
		open = "sell",
		glow = "RemoteSell",
	},
	{
		id = "ascend",
		when = "canAscend",
		text = "You can Ascend! Start again for +50% Volts for good.",
		open = "shop",
		glow = "SHOP",
	},
	{
		id = "portal",
		when = "worldOpen",
		text = "A portal at the hub is open: a whole new world awaits!",
		open = "teleport",
		glow = "TELEPORT",
	},
	{
		id = "newZone",
		when = "zoneOpen",
		text = "A new zone is open past its gate. Bigger zones pay more per bolt!",
		open = "teleport",
		glow = "TELEPORT",
	},
	{
		id = "rareBolt",
		when = "sawRareBolt",
		text = "Gold, rainbow and orb bolts pay up to 25x. Race to their rings!",
	},
	{
		id = "supercell",
		when = "sawSupercell",
		text = "Supercells come about once an hour: double strikes, more gold bolts.",
	},
	{
		id = "event",
		when = "eventOn",
		text = "An event is on: every sale pays more. Its chip is under the goal.",
	},
	-- progress
	{
		id = "boots",
		when = "bootsAffordable",
		text = "Boots make you faster in storms, and each zone's storm drag slows you.",
		open = "shopBoots",
		glow = "SHOP",
	},
	{
		id = "hireResearcher",
		when = "canHire",
		text = "Researchers help you catch. Hire one at the Research Center.",
		open = "research",
		glow = "RESEARCH",
	},
	{
		id = "postResearcher",
		when = "unposted",
		text = "Post a researcher in a zone (📍 POST) to gather data there.",
		open = "research",
		glow = "RESEARCH",
	},
	{
		id = "glints",
		when = "hasGlints",
		text = "Every bolt you catch gives Glints: see them at the top of RESEARCH.",
		open = "research",
		glow = "RESEARCH",
	},
	{
		id = "promote",
		when = "researcherLevel5",
		text = "A level 5 researcher can be promoted with Glints: a rank up!",
		open = "research",
		glow = "RESEARCH",
	},
	{
		id = "stormLog",
		when = "logStarted",
		text = "The Storm Log (RESEARCH › LOG) collects every bolt, place and storm.",
		open = "researchLog",
		glow = "RESEARCH",
	},
	-- rewards and the rest, as the visit goes on
	{
		id = "dailyStreak",
		when = "claimedDaily",
		text = "Come back tomorrow: the daily reward grows for 7 days in a row.",
		open = "rewards",
		glow = "REWARDS",
	},
	{
		id = "playtimeGifts",
		when = "always",
		minutes = 3,
		text = "Free gifts unlock as you play each day. They wait in REWARDS.",
		open = "rewards",
		glow = "REWARDS",
	},
	{
		id = "serverGoal",
		when = "hasSold",
		minutes = 4,
		text = "Every sale fills the server goal. A full one starts a 2x Surge!",
		glow = "ServerGoal",
	},
	{
		id = "quests",
		when = "always",
		minutes = 6,
		text = "Quests pay extra, and one free reroll a day swaps one you don't like.",
		open = "quests",
		glow = "REWARDS",
	},
	{
		id = "friendsBoost",
		when = "hasFriends",
		text = "Friends in your server give +{friendBonus}% Volts each (up to {friendMax}).",
	},
	{
		id = "boosts",
		when = "hasSold",
		minutes = 9,
		text = "Boosts give 2x Volts, luck or bigger bottles for a while.",
		open = "boosts",
		glow = "BOOSTS",
	},
	{
		id = "teleport",
		when = "zoneOpen",
		minutes = 11,
		text = "TELEPORT jumps you to any zone or world you've unlocked.",
		open = "teleport",
		glow = "TELEPORT",
	},
	{
		id = "afkLounge",
		when = "always",
		minutes = 14,
		text = "Stepping away? The AFK Lounge pays Volts while you rest.",
		open = "teleport",
		glow = "TELEPORT",
	},
	{
		id = "leaderboards",
		when = "always",
		minutes = 18,
		text = "See where you rank on the leaderboards: REWARDS › TOP.",
		open = "top",
		glow = "REWARDS",
	},
	{
		id = "group",
		when = "notGroupMember",
		minutes = 22,
		text = "Group members get +{groupBonus}% Volts on every sale. Join in REWARDS.",
		open = "rewards",
		glow = "REWARDS",
	},
	{
		id = "invite",
		when = "always",
		minutes = 26,
		text = "Invite a friend (REWARDS › INVITE): you both get a reward.",
		open = "rewards",
		glow = "REWARDS",
	},
	{
		id = "settings",
		when = "always",
		minutes = 30,
		text = "Keys, sound, graphics and text size are all in ⚙️ SETTINGS.",
		open = "settings",
		glow = "SETTINGS",
	},
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
	BOLT_TYPES = table.freeze(BOLT_TYPES),
	-- Ball lightning: an orb that drifts across the zone for `seconds`; the
	-- first player (with room) within `touchRadius` studs of it catches it.
	-- The server checks every `checkEvery` seconds.
	BALL_LIGHTNING = table.freeze({
		seconds = 8,
		checkEvery = 0.2,
		touchRadius = 5,
		height = 3, -- studs above the ground the orb floats
		minTravel = 24, -- studs; the shortest drift
	}),
	-- Supercell (Systems/StormCycle): about every intervalMinutes (give or
	-- take jitterMinutes) a storm turns into a Supercell for `minutes`, with
	-- strikeMultiplier times the strikes and goldenMultiplier times the
	-- golden chance. A countdown shows warningSeconds before it starts.
	SUPERCELL = table.freeze({
		intervalMinutes = 60,
		jitterMinutes = 15,
		minutes = 3,
		warningSeconds = 30,
		strikeMultiplier = 2,
		goldenMultiplier = 5,
	}),
	EVENTS = table.freeze(EVENTS),

	-- Movement: you move faster between zones so travel isn't a chore.
	-- Boots add their speedBonus inside zones only, and each zone's storm
	-- drag takes some away (see BOOTS and Util/Speed).
	WALK_SPEED_IN_ZONE = 18, -- a little over the Roblox default (16); a typical player's speed on entering a zone
	WALK_SPEED_OUTSIDE = 30,
	-- In-zone speed never goes below min (no boots in a late zone) or above
	-- max (great boots in an early zone). Keep max below WALK_SPEED_OUTSIDE,
	-- so leaving a zone always speeds you up.
	ZONE_SPEED = table.freeze({ min = 10, max = 28 }),

	-- Premium zones pay this many times the best other zone the player can
	-- enter, so they're worth a visit at every stage (Progression.boltValue)
	PREMIUM_VALUE_MULTIPLIER = 1.5,

	-- Selling
	SELL_COOLDOWN = 1, -- seconds between sells per player

	-- The menu's Teleport panel: seconds between trips (walking through a
	-- portal has its own short cooldown in Systems/Travel)
	TELEPORT_COOLDOWN = 10,

	-- Movement checks (Util/AntiCheat, Systems/AntiCheat): the server looks
	-- at every player's position every `checkEvery` seconds. Moving further
	-- across the ground than walk speed x time x `slack` + `extraStuds`,
	-- measured over the last `windowSeconds`, is impossible: for
	-- `suspectSeconds` that player can't catch, touch ball lightning or
	-- sell at a station. Nobody is kicked (lag can look like a teleport).
	-- Moves the server makes (portals, teleports, the AFK Lounge, respawns,
	-- the zone lock) aren't checked for `graceSeconds`. After `logAfter`
	-- impossible moves a player shows in the admin panel's list.
	ANTI_CHEAT = table.freeze({
		checkEvery = 0.2,
		windowSeconds = 1,
		slack = 1.5,
		extraStuds = 6,
		suspectSeconds = 5,
		graceSeconds = 3,
		logAfter = 3,
	}),

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
		dataScale = table.freeze({ 0.95, 1.6, 2.9, 4.3, 4.9, 5.45, 5.45 }),
		glintCost = table.freeze({ 50, 65, 135, 85, 165, 30 }),
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
	-- The server goal (Systems/ServerGoal, the maths in Util/Weather): every
	-- Volt sold in this server (Remote Sell too, not the AFK Lounge) fills
	-- one meter. Its size is every present player's grinding rate (Util/Afk)
	-- added up, times `minutes`, so any server takes about that long. Filling
	-- it starts a Server Surge: `multiplier` x Volts for everyone for
	-- `surgeMinutes` (on top of any Server Storm). Each goal after that is
	-- `growth` times bigger, back to normal every `resetMinutes`. The goal never drops below what's filled plus `stuckMargin`,
	-- and is at least `minGoal` Volts. Tapping the meter shows the top
	-- `topCount` contributors.
	SERVER_GOAL = table.freeze({
		minutes = 15,
		surgeMinutes = 10,
		multiplier = 2,
		growth = 1.5,
		resetMinutes = 60,
		stuckMargin = 0.1,
		minGoal = 1000,
		topCount = 3,
		-- a player who has been in the AFK Lounge this long doesn't count
		-- toward the goal's size (they can't help fill it); leaving the
		-- lounge counts them again
		afkExcludeMinutes = 5,
	}),
	DAILY_REWARDS = table.freeze(DAILY_REWARDS),
	PLAYTIME_GIFTS = table.freeze(PLAYTIME_GIFTS),
	QUESTS = table.freeze({
		daily = 3, -- daily quests per player
		weekly = 1, -- weekly quests per player
		zoneChoices = 3, -- a "catch in a zone" quest names one of their best this many zones
		templates = table.freeze(QUEST_TEMPLATES),
		-- the weekly quest pays about five daily quests
		weeklyReward = { charges = 750, boosts = { { key = "DoubleVolts", minutes = 30 } } },
	}),
	STORM_LOG = table.freeze({
		pageBonus = 0.02, -- +2% Volts per finished page
		maxBonus = 0.08, -- never more than +8%
		pages = table.freeze(STORM_LOG_PAGES),
	}),
	-- Ascension (Util/Ascension, Systems/Ascension): own the top bottle and
	-- have baseCost x (level + 1) Volts to start again from the beginning,
	-- for +perLevel Volts on every sale for good (added up: level 3 = +150%).
	ASCENSION = table.freeze({
		baseCost = 10_000_000,
		perLevel = 0.5,
		confirmSeconds = 30, -- the confirm screen's token runs out after this
		-- what goes back to how a new player starts
		resetTo = table.freeze({
			volts = 0,
			bottleTier = 1,
			bootTier = 1,
			chargeCount = 0,
			chargeValue = 0,
			tankCount = 0,
			tankValue = 0,
		}),
	}),
	-- a boost reward for a pass the player owns pays Volts instead: this many
	-- charges per minute of boost (about a minute of catching)
	REWARD_SWAP_CHARGES = 10,

	-- The new-player tutorial (Util/Tutorial, Systems/Tutorial): walk to
	-- `zone`, catch `catches` bolts, fill the bottle and sell it, then buy
	-- the next bottle. Finishing pays `rewardCharges` charges (in Volts, like
	-- every reward: Util/Store.volts).
	TUTORIAL = table.freeze({
		zone = "Shoreline",
		catches = 3,
		rewardCharges = 50,
	}),
	-- Gameplay tips after the tutorial (the list and its rules: HINTS above)
	HINTS = table.freeze({
		gapSeconds = 90, -- at least this long between two hints
		firstDelay = 60, -- none this soon after joining or finishing the tutorial
		showSeconds = 8, -- how long the toast stays
		glowSeconds = 20, -- how long its button glows
		quietAfterCatch = 10, -- none this soon after a catch
		list = table.freeze(HINTS),
	}),
	-- Friends boost (Systems/Friends, Util/Passes): +perFriend Volts on every
	-- sale for each Roblox friend in your server, counting up to `max`.
	FRIENDS = table.freeze({
		perFriend = 0.05,
		max = 3,
	}),
	-- Invites (Systems/Invites, Util/Social): a brand-new player who joins
	-- from someone's invite gets `welcomeCharges` charges; the inviter gets a
	-- `inviterReward` (a BOOST_PRODUCTS key) in their gift inbox, at most
	-- `dailyCap` times a UTC day, and only when the new player's Roblox
	-- account is at least `minAccountAgeDays` old.
	INVITES = table.freeze({
		welcomeCharges = 100,
		inviterReward = "DoubleVoltsBoost",
		dailyCap = 5,
		minAccountAgeDays = 14, -- the new player's account must be this old for the inviter's reward
		-- the inviter is only paid once the new player has played this many
		-- minutes in all, or made their first sale (stops alt accounts)
		playMinutes = 10,
	}),
	-- Leaderboards (Systems/Leaderboards, Util/Leaderboards): one
	-- OrderedDataStore per board. Each player's values are written every
	-- `writeEverySeconds` (only if they changed) and when they leave; every
	-- server reads the top `top` every `readEverySeconds`. The board at
	-- world 1's spawn shows the first board's top `boardRows`.
	LEADERBOARDS = table.freeze({
		writeEverySeconds = 5 * 60,
		readEverySeconds = 2 * 60,
		top = 50,
		boardRows = 10,
		storePrefix = "StormBottler_LB_",
		boards = table.freeze({
			table.freeze({ key = "volts", title = "All-time Volts", icon = "⚡" }),
			table.freeze({ key = "bolts", title = "Bolts caught", icon = "🌩️" }),
			table.freeze({ key = "ascension", title = "Ascension", icon = "🌟" }),
			table.freeze({ key = "streak", title = "Longest streak", icon = "📅" }),
		}),
	}),
	-- Phone notifications (Systems/Notifications, Util/Notifications):
	-- Roblox experience notifications, sent through Open Cloud. They need
	-- setup on the Creator Dashboard (see README.md, "Leaderboards and
	-- notifications"): an API key saved as the secret `secretName`, and two
	-- notification strings whose asset ids go in `dailyReadyMessageId` and
	-- `streakEndingMessageId`. Until then nothing is sent (the log says so
	-- once). "Streak ends soon" goes `streakWarnHours` before the streak
	-- would break. Due items wait in the MemoryStore sorted map `mapName`;
	-- a server that claims one has it for `claimSeconds`.
	NOTIFICATIONS = table.freeze({
		secretName = "StormBottlerNotifyKey",
		dailyReadyMessageId = "332b647d-2679-1b4c-a3b1-0865dba8cbd8",
		streakEndingMessageId = "8b7f8585-ac71-ff4e-b1ed-eb10fc4af721",
		streakWarnHours = 3,
		sendEverySeconds = 60,
		batch = 50,
		claimSeconds = 5 * 60,
		mapName = "StormBottler_Notifications",
	}),

	-- The group that owns the game (Systems/Group): members get GROUP_BONUS
	-- more Volts on every sale. To use another group, change GROUP_ID (and
	-- GROUP_NAME, which the REWARDS panel shows).
	GROUP_ID = 7889739,
	GROUP_NAME = "Super Studio",
	GROUP_BONUS = 0.10,
	GROUP_COLOR = Color3.fromRGB(80, 200, 255), -- the [Member] chat tag
	OWNER_COLOR = Color3.fromRGB(120, 230, 140), -- the [Owner] chat tag (private servers)

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

	-- Sound (the sounds themselves: Shared/SoundBank, made by tools/audio).
	-- SOUND_MIX: each SoundGroup's volume before the player's sliders.
	-- (the mix: music under the effects, UI the quietest, storms big)
	SOUND_MIX = table.freeze({ Music = 0.32, Ambience = 0.55, SFX = 1, UI = 0.7 }),
	-- Background music per world and weather: Roblox's licensed partner
	-- tracks (APMOfficial, DistrokidOfficial; tools/audio/music_search.py,
	-- docs/audio/music-shortlist.md). Instrumental only: no lyrics. Each list
	-- plays shuffled (Controllers/Music).
	MUSIC = table.freeze({
		Bay = table.freeze({
			-- Cheerful Classroom Celebration Instrumental; Seaside Reflections; Magical Adventure (Light Vs)
			Calm = { 133196125967338, 88298878796645, 1838661059 },
			-- Night Run; Roller coaster?; Funk Drift
			Storm = { 9044545570, 92504170192114, 129146412554158 },
		}),
		Voltcliff = table.freeze({
			-- Follow The Footprints - Underscore; Time in Gears; Heavenly Clockwork
			Calm = { 9047610291, 9039374146, 1842365805 },
			-- Alarm Glock NO DRM KT; Macho Manhunt; Loco Motive NO ORCH
			Storm = { 122770769791748, 131880535514102, 101746788451393 },
		}),
		Stormspire = table.freeze({
			-- Watching the Garden Grow (a); Pizzicato Spritz (a); The Whimsical Waltz (c)
			Calm = { 9046598930, 9046599262, 9046601476 },
			-- Phantom Nova (Underscore Version); Aeon Driver (Underscore Version); The Great Dynasties (Underscore Version)
			Storm = { 116315815173589, 117596024497708, 135102649170289 },
		}),
	}),
	MUSIC_FADE = 3, -- seconds to crossfade on a weather or world change
	MUSIC_DUCK = 0.5, -- music volume (x) under big moments: about -6 dB
	MUSIC_DUCK_SECONDS = 1.5,
	-- ambience: the loops' volumes (x) in each weather, and how often a gust
	-- or a distant rumble comes in a storm
	AMBIENCE = table.freeze({
		calmVolume = 0.6,
		stormRainVolume = 1,
		stormCalmVolume = 0.15, -- the waves stay faintly under the rain
		eventEvery = { 6, 15 }, -- seconds between gusts and rumbles in a storm
		humRadius = 60, -- studs: the power plant's hum is heard this far away
	}),
	-- the strike's thunder comes later the further away it is
	THUNDER_STUDS_PER_SECOND = 340,
	THUNDER_MAX_DELAY = 1.5,
	-- Lightning on each player's screen (Controllers/StrikeFX, Util/StrikeFx).
	-- Other players' strikes further than drawDistance studs from your camera
	-- aren't drawn; past simpleDistance they're drawn simple (no branches,
	-- sparks or screen flash). A bolt flickers like a real restrike: full,
	-- down to `dim` brightness for dipFor seconds from dipAt, full again for
	-- `hold`, then fades over `fade` (Reduce flashing: just a calmFade).
	STRIKE_FX = table.freeze({
		drawDistance = 600,
		simpleDistance = 250,
		dim = 0.4,
		dipAt = 0.05,
		dipFor = 0.07,
		hold = 0.06,
		fade = 0.3,
		calmFade = 0.6,
	}),

	-- Admins (Systems/Admin, Util/Ops): the owner of the group (GROUP_ID),
	-- anyone in it at this rank or higher, and everyone in Studio play tests.
	ADMIN_RANK = 200,
	ADMIN = table.freeze({
		logStore = "AdminLog", -- DataStore: one key per UTC day, "day_2026-10-25"
		logPerDay = 1000, -- entries kept per day (the oldest go first)
		reasonLength = 200, -- characters in a kick or ban reason
		maxVolts = 1e12, -- the most Volts one "give" can add
		-- ban lengths the panel offers, in seconds (-1 = forever)
		banSeconds = { 3600, 86400, 7 * 86400, 30 * 86400, -1 },
		boostMinutes = { 15, 30, 60 }, -- boost lengths the panel offers
		rankRecheckSeconds = 300, -- how long a rank check is trusted
	}),

	-- Error reporting (Systems/Errors, Util/Ops): client errors come in
	-- through the ClientError remote, at most `perPlayer` a minute per player
	-- and `perServer` a minute for the whole server. The admin panel shows the
	-- last `recent` errors.
	ERRORS = table.freeze({
		perPlayer = 5,
		perServer = 300,
		recent = 20,
		messageLength = 300, -- characters kept from a message
		-- spam limits per server: errors remembered as "already sent to
		-- Analytics" (after that, new ones aren't sent), and new client
		-- errors sent to Analytics (a cheater can make up messages)
		maxReported = 500,
		maxClientReports = 50,
	}),

	-- Streaming (Lib/MapBuilder): phones only load the map near the player.
	-- minRadius is always loaded round you; targetRadius is how far it tries
	-- to load when there's memory to spare (studs).
	STREAMING = table.freeze({
		minRadius = 128,
		targetRadius = 512,
	}),
})
