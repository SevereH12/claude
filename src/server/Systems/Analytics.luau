--!strict
-- Retention and progression stats for the Creator Dashboard. This is the
-- only code that calls AnalyticsService: other systems call the small
-- functions below. Roblox totals the events; the only per-player thing we
-- keep is profile.onboardStep, so no onboarding step is ever sent twice.
-- Every call is wrapped in pcall: analytics can never break gameplay.
--
--   Funnel "Onboarding": steps 1-7 (ONBOARDING below), in order, once each.
--   Progression: "Bottles" and "Boots" when bought, "Zones" when a bottle
--     unlocks a zone.
--   Custom events on leaving: "SessionMinutes" (minutes played) and "Left"
--     (1), both with CustomField01 = where they left (whereIs), 02 =
--     "Bottle <n>", 03 = "Storm" or "Calm". Small fixed sets, well under
--     the 8,000 combinations Roblox allows.
--   Economy "Volts": earned at the sell station (Source), spent on bottles,
--     boots and researchers (Sink), bought in Volts packs (Source, IAP).
--   Funnel "Store": opened Boosts -> tapped a card -> purchase window
--     opened -> bought, one funnel session per store visit (STORE_STEPS).
--   Custom events: "OfferShown" and "OfferTapped" (CustomField01 = the
--     offer key), "TrialStarted" (1) and "TrialEnded" (Volts it earned),
--     "DailyClaimed" (streak day), "PlaytimeGift" (minutes), "GroupJoined".
--   Economy: Volts from rewards (Source, TimedReward) and the AFK Lounge
--     (Source, Gameplay, "AFK"). Custom events "AfkMinutes" (minutes AFK,
--     when it ends or the player leaves) and "AfkRejoin" (1).
--   Custom events "GiftSent" (the giver) and "GiftReceived" (the receiver),
--     CustomField01 = the product key ("GiftVIP", "LuckyBoost"), and
--     "ServerStorm" (the storm's minutes left after the purchase). Robux
--     purchases are counted by Roblox, so only Volts are economy events.
--   Custom event "Error" (Systems/Errors): CustomField01 = the error's
--     fingerprint, 02 = "server" or "client"; once per fingerprint per server.

local AnalyticsService = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Util.Formulas)
local Portals = require(ReplicatedStorage.Shared.Util.Portals)
local Progression = require(ReplicatedStorage.Shared.Util.Progression)
local ResearchSites = require(ReplicatedStorage.Shared.Util.ResearchSites)
local Types = require(ReplicatedStorage.Shared.Types)
local Zones = require(ReplicatedStorage.Shared.Util.Zones)
local PlayerData = require(script.Parent.PlayerData)
local StormCycle = require(script.Parent.StormCycle)
local Sync = require(script.Parent.Sync)

local ONBOARDING = {
	"Joined",
	"Entered a zone",
	"First catch",
	"First sell",
	"First upgrade",
	"Entered a second zone",
	"Hired a researcher",
}
local STORE_STEPS = {
	"Opened Boosts",
	"Tapped a card",
	"Purchase window opened",
	"Bought",
}
local CURRENCY = "Volts"
-- Each hub is built round its world's offset; the styles' hub radius is 60
-- (WeatherLab) and 52 (StormPunk), so anything this close counts as the hub.
local HUB_RADIUS = 64
-- "Entered a second zone" is any zone but the first one on the spiral
local FIRST_ZONE = Formulas.sortedZones()[1].id

type Session = {
	joinedAt: number,
	profile: Types.Profile, -- kept so the bottle tier is known after PlayerData lets go
	reached: { [number]: boolean }, -- steps done this session, maybe ahead of the funnel
}

local Analytics = {}

local sessions: { [Player]: Session } = {}
local seas: { BasePart } = {}
local storeVisits: { [Player]: string } = {} -- the current store visit's funnel session id

local function fields(where: string, bottle: string, phase: string): { [string]: string }
	return {
		[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = where,
		[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = bottle,
		[Enum.AnalyticsCustomFieldKeys.CustomField03.Name] = phase,
	}
end

-- Runs one AnalyticsService call; a failure is a warning, never an error.
local function send(what: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		warn(`[Analytics] {what} failed: {err}`)
	end
end

-- Onboarding: mark `step` done and send every step the funnel has reached,
-- in order. A step done early (hiring before a second zone) waits for the
-- ones before it.
local function onboard(player: Player, step: number)
	local session = sessions[player]
	if not session or step <= session.profile.onboardStep then
		return
	end
	session.reached[step] = true
	local profile = session.profile
	if not session.reached[profile.onboardStep + 1] then
		return
	end
	while session.reached[profile.onboardStep + 1] do
		local n = profile.onboardStep + 1
		profile.onboardStep = n
		send(`onboarding step {n}`, function()
			AnalyticsService:LogOnboardingFunnelStepEvent(player, n, ONBOARDING[n])
		end)
	end
	Sync.markDirty(player)
end

local function progression(player: Player, path: string, level: number, name: string)
	send(`{path} progression`, function()
		AnalyticsService:LogProgressionCompleteEvent(player, path, level, name)
	end)
end

local function economy(
	player: Player,
	flow: Enum.AnalyticsEconomyFlowType,
	amount: number,
	transaction: string,
	sku: string
)
	local profile = PlayerData.get(player)
	if not profile or amount <= 0 then
		return
	end
	send(`economy {sku}`, function()
		AnalyticsService:LogEconomyEvent(
			player,
			flow,
			CURRENCY,
			amount,
			profile.volts,
			transaction,
			sku
		)
	end)
end

-- Is a body whose feet are at `position` under the sea? The seas are the
-- see-through "Sea" parts (World/Blocks.water), one per world.
local function underwater(position: Vector3): boolean
	if #seas == 0 then
		local map = workspace:FindFirstChild("Map")
		local parts = if map then map:GetDescendants() else {}
		for _, part in parts do
			if part:IsA("BasePart") and part.Name == "Sea" then
				table.insert(seas, part)
			end
		end
	end
	for _, sea in seas do
		local localPos = sea.CFrame:PointToObjectSpace(position)
		local half = sea.Size / 2
		if math.abs(localPos.X) <= half.X and math.abs(localPos.Z) <= half.Z then
			return localPos.Y < half.Y
		end
	end
	return false
end

-- Where a player is: a zone id, "Camp:<ZoneId>", "ResearchCenter",
-- "SellStation", "Water", "Hub", "Boardwalk", or "Respawning" with no
-- living character.
local function whereIs(player: Player): string
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return "Respawning"
	end
	local position = root.Position
	local zone = Zones.at(position)
	if zone then
		return zone.id
	end
	local camp = ResearchSites.campAt(position)
	if camp then
		return `Camp:{camp}`
	end
	if ResearchSites.inOffice(position) then
		return "ResearchCenter"
	end
	-- required here: Selling requires this module
	local Selling = (require :: any)(script.Parent.Selling)
	if Selling.isAtStation(position) then
		return "SellStation"
	end
	local feet = position - Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
	if underwater(feet) then
		return "Water"
	end
	local fromHub = position - Portals.worldOf(player).offset
	if Vector2.new(fromHub.X, fromHub.Z).Magnitude <= HUB_RADIUS then
		return "Hub"
	end
	return "Boardwalk"
end

-- Called by Movement every check with the zone the player is allowed to be
-- in (nil outside zones).
function Analytics.inZone(player: Player, zone: Types.ZoneDef?)
	if not zone then
		return
	end
	onboard(player, 2)
	if zone.id ~= FIRST_ZONE then
		onboard(player, 6)
	end
end

function Analytics.caught(player: Player)
	onboard(player, 3)
end

function Analytics.sold(player: Player, earned: number)
	onboard(player, 4)
	economy(player, Enum.AnalyticsEconomyFlowType.Source, earned, "Gameplay", "Sell")
end

-- After a bottle purchase: the new tier is the profile's, `oldTier` the one
-- before. Zones it unlocks are found by comparing canEnter before and after.
function Analytics.boughtBottle(player: Player, oldTier: number)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	local bottle = Config.BOTTLES[profile.bottleTier]
	onboard(player, 5)
	progression(player, "Bottles", profile.bottleTier, bottle.name)
	economy(player, Enum.AnalyticsEconomyFlowType.Sink, bottle.price, "Shop", bottle.name)
	local premium = Progression.playerIsPremium(player)
	local before = { bottleTier = oldTier, bootTier = profile.bootTier }
	for index, zone in Formulas.sortedZones() do
		if
			Progression.canEnter(profile, zone, premium)
			and not Progression.canEnter(before, zone, premium)
		then
			progression(player, "Zones", index, zone.displayName)
		end
	end
end

function Analytics.boughtBoots(player: Player)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	local boots = Config.BOOTS[profile.bootTier]
	onboard(player, 5)
	progression(player, "Boots", profile.bootTier, boots.name)
	economy(player, Enum.AnalyticsEconomyFlowType.Sink, boots.price, "Shop", boots.name)
end

function Analytics.hired(player: Player, def: Types.ResearcherDef)
	onboard(player, 7)
	economy(player, Enum.AnalyticsEconomyFlowType.Sink, def.price, "Shop", def.name)
end

-- Store funnel step 1-4 (STORE_STEPS). Opening the store starts a new
-- visit; the other steps belong to the current one (or start one).
function Analytics.storeStep(player: Player, step: number)
	local name = STORE_STEPS[step]
	if not name then
		return
	end
	local visit = storeVisits[player]
	if step == 1 or not visit then
		visit = HttpService:GenerateGUID(false)
		storeVisits[player] = visit
	end
	local id = visit :: string
	send(`store step {step}`, function()
		AnalyticsService:LogFunnelStepEvent(player, "Store", id, step, name)
	end)
end

-- "OfferShown" or "OfferTapped", with the offer key (a small fixed set).
function Analytics.offer(player: Player, eventName: string, key: string)
	send(eventName, function()
		AnalyticsService:LogCustomEvent(player, eventName, 1, {
			[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = key,
		})
	end)
end

-- "Error" (Systems/Errors): a new error fingerprint, CustomField01 = the
-- fingerprint, 02 = "server" or "client". Roblox ties every event to a
-- player, so a server error uses whoever is in the server (or waits for
-- the next player to join).
local pendingErrors: { { fingerprint: string, source: string } } = {}
local function sendError(player: Player, fingerprint: string, source: string)
	send("Error", function()
		AnalyticsService:LogCustomEvent(player, "Error", 1, {
			[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = fingerprint,
			[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = source,
		})
	end)
end

function Analytics.error(fingerprint: string, source: string, player: Player?)
	local who = player or Players:GetPlayers()[1]
	if who then
		sendError(who, fingerprint, source)
	elseif #pendingErrors < 50 then
		table.insert(pendingErrors, { fingerprint = fingerprint, source = source })
	end
end

local function sendPendingErrors(player: Player)
	local waiting = pendingErrors
	pendingErrors = {}
	for _, entry in waiting do
		sendError(player, entry.fingerprint, entry.source)
	end
end

function Analytics.trialStarted(player: Player)
	send("TrialStarted", function()
		AnalyticsService:LogCustomEvent(player, "TrialStarted", 1)
	end)
end

-- `earned`: the extra Volts the trial paid.
function Analytics.trialEnded(player: Player, earned: number)
	send("TrialEnded", function()
		AnalyticsService:LogCustomEvent(player, "TrialEnded", earned)
	end)
end

-- Rewards (Systems/Rewards): the daily streak and playtime gifts.
function Analytics.dailyClaimed(player: Player, day: number)
	send("DailyClaimed", function()
		AnalyticsService:LogCustomEvent(player, "DailyClaimed", day)
	end)
end

function Analytics.giftClaimed(player: Player, minutes: number)
	send("PlaytimeGift", function()
		AnalyticsService:LogCustomEvent(player, "PlaytimeGift", minutes)
	end)
end

function Analytics.groupJoined(player: Player)
	send("GroupJoined", function()
		AnalyticsService:LogCustomEvent(player, "GroupJoined", 1)
	end)
end

-- "GiftSent" or "GiftReceived" (Systems/Gifts), with the gift's product
-- key (a small fixed set).
function Analytics.gift(player: Player, eventName: string, productKey: string)
	send(eventName, function()
		AnalyticsService:LogCustomEvent(player, eventName, 1, {
			[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = productKey,
		})
	end)
end

-- A Server Storm bought (Systems/Receipts): `minutes` left after it.
function Analytics.serverStorm(player: Player, minutes: number)
	send("ServerStorm", function()
		AnalyticsService:LogCustomEvent(player, "ServerStorm", minutes)
	end)
	Analytics.storeStep(player, 4)
end

-- Volts a reward paid (`sku`: "Daily 3", "Gift 10 min").
-- AfkMinutes: minutes an AFK session earned for (sent when it ends or the
-- player leaves).
function Analytics.afkMinutes(player: Player, minutes: number)
	if minutes <= 0 then
		return
	end
	send("AfkMinutes", function()
		AnalyticsService:LogCustomEvent(player, "AfkMinutes", math.floor(minutes * 10 + 0.5) / 10)
	end)
end

-- AfkRejoin: the backup moved an idle AFK player to a fresh server.
function Analytics.afkRejoin(player: Player)
	send("AfkRejoin", function()
		AnalyticsService:LogCustomEvent(player, "AfkRejoin", 1)
	end)
end

function Analytics.afkEarned(player: Player, volts: number)
	economy(player, Enum.AnalyticsEconomyFlowType.Source, volts, "Gameplay", "AFK")
end

function Analytics.rewardVolts(player: Player, volts: number, sku: string)
	economy(player, Enum.AnalyticsEconomyFlowType.Source, volts, "TimedReward", sku)
end

-- A Volts pack bought with Robux (Systems/Receipts).
function Analytics.packBought(player: Player, pack: Types.VoltPackDef, volts: number)
	economy(player, Enum.AnalyticsEconomyFlowType.Source, volts, "IAP", pack.name)
	Analytics.storeStep(player, 4)
end

local function onLoaded(player: Player, profile: Types.Profile)
	local session: Session = { joinedAt = os.clock(), profile = profile, reached = {} }
	sessions[player] = session
	onboard(player, 1)
	-- done in an earlier session but not sent yet (the funnel was behind)
	if profile.bottleTier > 1 or profile.bootTier > 1 then
		onboard(player, 5)
	end
	if next(profile.researchers) then
		onboard(player, 7)
	end
end

local function onRemoving(player: Player)
	storeVisits[player] = nil
	local session = sessions[player]
	sessions[player] = nil
	if not session then
		return
	end
	local minutes = math.floor((os.clock() - session.joinedAt) / 6 + 0.5) / 10
	local found, place = pcall(whereIs, player)
	local where = if found then place else "Respawning"
	local bottle = `Bottle {session.profile.bottleTier}`
	local phase = if StormCycle.isStorming() then "Storm" else "Calm"
	send("SessionMinutes", function()
		AnalyticsService:LogCustomEvent(
			player,
			"SessionMinutes",
			minutes,
			fields(where, bottle, phase)
		)
	end)
	send("Left", function()
		AnalyticsService:LogCustomEvent(player, "Left", 1, fields(where, bottle, phase))
	end)
end

function Analytics.init()
	PlayerData.Loaded:Connect(onLoaded)
	Players.PlayerRemoving:Connect(onRemoving)
	Players.PlayerAdded:Connect(sendPendingErrors)
end

return Analytics
