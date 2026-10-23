--!strict
-- The AFK Lounge: stand in it and earn Volts at a steady rate,
-- Config.AFK.rateFraction of your best grinding (premiumRateFraction for
-- Roblox Premium members), worked out by Util/Afk.rate from your bottle,
-- boots, best zone and everything that multiplies a sale.
--
-- Like Selling, it's a server position check (never Touched): every second,
-- anyone inside a box tagged AfkZone (Kit.afkZone) counts. After
-- Config.AFK.enterSeconds inside they're AFK; the rate is worked out again
-- every recomputeSeconds (a boost running out, a purchase, a Server Storm,
-- a new Premium membership) and paid in whole Volts every payEverySeconds,
-- the fraction carried over. Leaving the box stops it straight away (what
-- was earned so far is paid). Boosts keep counting down while AFK: they're
-- being used. The state goes in the snapshot (Sync.afk) for the AFK screen.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local AfkRules = require(ReplicatedStorage.Shared.Util.Afk)
local Progression = require(ReplicatedStorage.Shared.Util.Progression)
local Volumes = require(ReplicatedStorage.Shared.Util.Volumes)
local Analytics = require(script.Parent.Analytics)
local Passes = require(script.Parent.Passes)
local PlayerData = require(script.Parent.PlayerData)
local Sync = require(script.Parent.Sync)

local AFK = Config.AFK
local CHECK_INTERVAL = 1

type Session = {
	insideSince: number, -- os.clock()
	active: boolean,
	perSecond: number,
	carry: number, -- Volts earned but not paid yet (under 1 after a payment)
	lastRecompute: number,
	lastPay: number,
}

local sessions: { [Player]: Session } = {}

local Afk = {}

local function livingRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	return root
end

-- Is this position in the AFK Lounge?
function Afk.isInLounge(position: Vector3): boolean
	for _, instance in CollectionService:GetTagged(AfkRules.TAG) do
		if
			instance:IsA("BasePart")
			and instance:IsDescendantOf(workspace)
			and Volumes.contains(instance, position)
		then
			return true
		end
	end
	return false
end

-- Works the rate out again and puts it in the snapshot.
local function recompute(player: Player, session: Session, profile: Types.Profile)
	local perSecond, breakdown = AfkRules.rate(
		{ bottleTier = profile.bottleTier, bootTier = profile.bootTier },
		Passes.saleEffects(player),
		Progression.playerIsPremium(player)
	)
	session.perSecond = perSecond
	session.lastRecompute = os.clock()
	local state = Sync.afk[player]
	if not state then
		return
	end
	state.perHour = breakdown.perHour
	state.fraction = breakdown.fraction
	state.premium = breakdown.premium
	state.zone = if breakdown.zone then breakdown.zone.displayName else ""
	state.bottle = breakdown.bottle
	state.baseCapacity = breakdown.baseCapacity
	state.capacity = breakdown.capacity
	state.chargeSize = breakdown.chargeSize
	state.strikes = breakdown.strikes
	state.fillSeconds = breakdown.fillSeconds
	state.bag = breakdown.bag
	state.multipliers = breakdown.multipliers
	state.luck = breakdown.luck
	state.bigBottles = breakdown.bigBottles
	Sync.markDirty(player)
end

-- Pays what's been earned since the last payment, in whole Volts.
local function pay(player: Player, session: Session, profile: Types.Profile)
	local now = os.clock()
	local amount = session.carry + session.perSecond * (now - session.lastPay)
	session.lastPay = now
	local whole = math.floor(amount)
	session.carry = amount - whole
	if whole <= 0 then
		return
	end
	profile.volts += whole
	profile.totalVolts += whole
	local state = Sync.afk[player]
	if state then
		state.earned += whole
	end
	Sync.markDirty(player)
	Analytics.afkEarned(player, whole)
end

local function stop(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	local profile = PlayerData.get(player)
	if session.active and profile then
		pay(player, session, profile)
	end
	sessions[player] = nil
	Sync.afk[player] = nil
	Sync.markDirty(player)
end

local function enter(player: Player)
	local now = os.clock()
	sessions[player] = {
		insideSince = now,
		active = false,
		perSecond = 0,
		carry = 0,
		lastRecompute = 0,
		lastPay = now,
	}
	Sync.afk[player] = {
		active = false,
		startsAt = workspace:GetServerTimeNow() + AFK.enterSeconds,
		earned = 0,
		perHour = 0,
		fraction = AFK.rateFraction,
		premium = false,
		zone = "",
		bottle = "",
		baseCapacity = 0,
		capacity = 0,
		chargeSize = 1,
		strikes = 0,
		fillSeconds = 0,
		bag = 0,
		multipliers = {},
		luck = 0,
		bigBottles = false,
	}
	Sync.markDirty(player)
end

local function check(player: Player)
	local profile = PlayerData.get(player)
	local root = livingRoot(player)
	local inside = profile ~= nil and root ~= nil and Afk.isInLounge(root.Position)
	local session = sessions[player]
	if not inside or not profile then
		stop(player)
		return
	end
	if not session then
		enter(player)
		return
	end
	local now = os.clock()
	if not session.active then
		if now - session.insideSince < AFK.enterSeconds then
			return
		end
		session.active = true
		session.lastPay = now
		local state = Sync.afk[player]
		if state then
			state.active = true
			state.startsAt = workspace:GetServerTimeNow()
		end
		recompute(player, session, profile)
		return
	end
	if now - session.lastRecompute >= AFK.recomputeSeconds then
		recompute(player, session, profile)
	end
	if now - session.lastPay >= AFK.payEverySeconds then
		pay(player, session, profile)
	end
end

function Afk.isAfk(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and session.active
end

function Afk.start()
	if #CollectionService:GetTagged(AfkRules.TAG) == 0 then
		warn(`[Afk] no part tagged "{AfkRules.TAG}"; the AFK Lounge is off`)
	end
	-- a new Premium membership changes the rate straight away
	Players.PlayerMembershipChanged:Connect(function(player)
		local session, profile = sessions[player], PlayerData.get(player)
		if session and session.active and profile then
			recompute(player, session, profile)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
		Sync.afk[player] = nil
	end)
	while true do
		task.wait(CHECK_INTERVAL)
		for _, player in Players:GetPlayers() do
			check(player)
		end
	end
end

return Afk
