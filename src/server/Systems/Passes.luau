--!strict
-- Who owns which Game Pass (Config.PASSES), and the pass effects other
-- systems ask for (the maths is in Shared/Util/Passes).
--
-- On join, every pass with an id is checked with UserOwnsGamePassAsync
-- (pcall, one retry) and cached. A pass bought in game is granted straight
-- away from the server's PromptGamePassPurchaseFinished; that has been seen
-- to report wasPurchased = false after a real purchase, so a false is
-- re-checked once, 2 seconds later. Never because a client says so.
--
-- Passes someone gifted (Systems/Gifts: profile.giftedPasses) count as
-- owned too, so every effect works for them.
--
-- Everyone can see what a player owns: player attributes Pass_<key> = true.
-- The owner also gets the set in their snapshot (Sync).
--
-- Studio testing: the TEST panel's "Pretend owns <pass>" toggles
-- (Systems/DevCommands) count as owning the pass, in Studio only, like
-- Pretend Premium.
--
-- Pass effects also come from timed boosts (Systems/Boosts: rewards, the
-- free trial, bought and gifted boosts): capacity, payout and luck below
-- apply owned passes plus running boosts, so every place that uses them
-- gets both. Sales also multiply by the group bonus and a Server Storm.
--
-- Also this session's store numbers (Sync.store, in the snapshot): what 2x
-- Volts boosts have paid, and what 2x Volts would have paid. Lost on leaving.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Util.Formulas)
local PassRules = require(ReplicatedStorage.Shared.Util.Passes)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local StormLogRules = require(ReplicatedStorage.Shared.Util.StormLog)
local Types = require(ReplicatedStorage.Shared.Types)
local Weather = require(ReplicatedStorage.Shared.Util.Weather)
local Boosts = require(script.Parent.Boosts)
local Group = require(script.Parent.Group)
local PlayerData = require(script.Parent.PlayerData)
local Sync = require(script.Parent.Sync)

local RETRY_WAIT = 1 -- seconds before the one retry of an ownership check
local RECHECK_DELAY = 2 -- seconds before re-checking a "not purchased"

local Passes = {}

Passes.ATTRIBUTE = PassRules.ATTRIBUTE -- .. key: true when the player owns it
Passes.PRETEND = "PretendPass_" -- .. key: the Studio toggle is on

-- Fires when a player buys a pass in game (not for passes they already
-- owned when they joined, or Studio toggles).
Passes.Purchased = Signal.new() :: Signal.Signal<Player, Types.PassDef>

local bought: { [Player]: PassRules.Owned } = {} -- real ownership
local pretend: { [Player]: PassRules.Owned } = {} -- Studio toggles

local function byId(id: number): Types.PassDef?
	for _, pass in Config.PASSES do
		if pass.id ~= 0 and pass.id == id then
			return pass
		end
	end
	return nil
end

-- Does Roblox say they own it? nil if it couldn't tell (twice).
local function ownsAsync(player: Player, id: number): boolean?
	for attempt = 1, 2 do
		local ok, result = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
		end)
		if ok then
			return result == true
		end
		if attempt == 1 then
			task.wait(RETRY_WAIT)
		else
			warn(`[Passes] couldn't check pass {id} for {player.Name}: {result}`)
		end
	end
	return nil
end

-- Recomputes what the player owns (bought, gifted, Studio toggles) and
-- tells everyone. Systems/Gifts calls it when a gift arrives.
function Passes.refresh(player: Player)
	if not player.Parent then
		return
	end
	local set: PassRules.Owned = {}
	for key in bought[player] or {} do
		set[key] = true
	end
	local profile = PlayerData.get(player)
	for key in if profile then profile.giftedPasses else {} do
		set[key] = true
	end
	if RunService:IsStudio() then
		for key in pretend[player] or {} do
			set[key] = true
		end
	end
	Sync.passes[player] = set -- both, read by owned() and sent in the snapshot
	for _, pass in Config.PASSES do
		player:SetAttribute(Passes.ATTRIBUTE .. pass.key, if set[pass.key] then true else nil)
	end
	Sync.markDirty(player)
end

-- `purchased`: bought just now (not an ownership check on joining).
local function grant(player: Player, pass: Types.PassDef, purchased: boolean)
	local set = bought[player]
	if not set or set[pass.key] then
		return
	end
	set[pass.key] = true
	Passes.refresh(player)
	print(`[Passes] {player.Name} owns {pass.name}`)
	if purchased then
		Passes.Purchased:Fire(player, pass)
	end
end

local function onPlayerAdded(player: Player)
	bought[player] = {}
	Passes.refresh(player)
	for _, pass in Config.PASSES do
		if pass.id ~= 0 then
			task.spawn(function()
				if ownsAsync(player, pass.id) then
					grant(player, pass, false)
				end
			end)
		end
	end
end

local function onPurchaseFinished(player: Player, id: number, wasPurchased: boolean)
	local pass = byId(id)
	if not pass then
		return
	end
	if wasPurchased then
		grant(player, pass, true)
		return
	end
	task.delay(RECHECK_DELAY, function()
		if player.Parent and ownsAsync(player, id) then
			grant(player, pass, true)
		end
	end)
end

-- The set of pass keys the player owns (don't change it).
function Passes.owned(player: Player): PassRules.Owned
	return Sync.passes[player] or {}
end

function Passes.owns(player: Player, key: string): boolean
	return Passes.owned(player)[key] == true
end

-- The effects to apply: owned passes plus running boosts.
local function effects(player: Player): PassRules.Owned
	return PassRules.withBoosts(Passes.owned(player), Boosts.left(player))
end

-- The player's bottle capacity (Big Bottles, pass or boost, included).
function Passes.capacity(player: Player, profile: Types.Profile): number
	return PassRules.capacity(Formulas.capacity(profile.bottleTier), effects(player))
end

-- This session's store numbers for the player (created on first use).
function Passes.storeSession(player: Player): Types.StoreSession
	local session = Sync.store[player]
	if not session then
		session = { boostEarned = 0, missedDouble = 0 }
		Sync.store[player] = session
	end
	return session
end

-- Owned passes plus what multiplies sales like one: the group bonus, a
-- Server Storm and a Server Surge (Systems/Boosts), any scheduled event on now
-- (Config.EVENTS, Util/Weather), the Storm Log's finished pages and the
-- player's Ascension level.
local function withBonuses(player: Player): PassRules.Owned
	local owned = Passes.owned(player)
	local profile = PlayerData.get(player)
	if profile then
		owned = StormLogRules.withPages(
			owned,
			StormLogRules.found(profile.stats.lifetime, profile.researchers)
		)
		owned = PassRules.withAscension(owned, profile.ascension)
	end
	local member, storm, surge = Group.isMember(player), Boosts.stormOn(), Boosts.surgeOn()
	local events = Weather.liveEvents()
	if not member and not storm and not surge and #events == 0 then
		return owned
	end
	local set = table.clone(owned)
	set[PassRules.GROUP] = if member then true else nil
	set[PassRules.SERVER_STORM] = if storm then true else nil
	set[PassRules.SERVER_SURGE] = if surge then true else nil
	for _, on in events do
		set[PassRules.EVENT .. on.event.name] = true
	end
	return set
end

-- Everything that multiplies a sale, as one set: owned passes, running
-- boosts, the group bonus, a Server Storm and the Storm Log (what
-- Passes.payout applies).
-- Systems/Afk works its rate out from this.
function Passes.saleEffects(player: Player): PassRules.Owned
	return PassRules.withBoosts(withBonuses(player), Boosts.left(player))
end

-- What selling a bottle worth `value` pays (passes, VIP, the group bonus,
-- boosts, a Server Storm), and what 2x Volts would have added. Keeps this
-- session's tallies.
function Passes.payout(player: Player, value: number): (number, number)
	local earned, missed, boostExtra =
		PassRules.saleBreakdown(value, withBonuses(player), Boosts.left(player))
	local session = Passes.storeSession(player)
	session.missedDouble += missed
	session.boostEarned += boostExtra
	return earned, missed
end

-- The chance a caught charge is worth double (Lucky Charges, pass or boost).
function Passes.luckChance(player: Player): number
	return PassRules.luckChance(effects(player))
end

-- Studio TEST toggle: pretend to own (or not) a pass. Ignored outside Studio.
function Passes.setPretend(player: Player, key: string, on: boolean)
	if not RunService:IsStudio() or not PassRules.def(key) then
		return
	end
	local set = pretend[player] or {}
	pretend[player] = set
	set[key] = if on then true else nil
	player:SetAttribute(Passes.PRETEND .. key, if on then true else nil)
	Passes.refresh(player)
end

function Passes.init()
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(onPurchaseFinished)
	-- gifted passes come with the profile
	PlayerData.Loaded:Connect(Passes.refresh)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		bought[player] = nil
		pretend[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return Passes
