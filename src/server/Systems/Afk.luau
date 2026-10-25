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
--
-- Staying connected: Roblox disconnects after about 20 idle minutes. While
-- AFK the client answers Players.LocalPlayer.Idled with VirtualUser
-- (Controllers/AfkUI). If that fails, or the idle time reaches
-- Config.AFK.idleRejoinMinutes, it sends AfkRejoin: only while the server
-- agrees they're AFK, this saves the profile and moves them to a fresh
-- server of this place (teleport data { afk = true }); there they're put
-- straight back in the lounge (session locking waits for this server's
-- save). A failed move is tried once more after rejoinRetrySeconds; after
-- that Roblox's idle kick happens. Stats: AfkMinutes (when AFK ends or the
-- player leaves) and AfkRejoin (Analytics).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TeleportService = game:GetService("TeleportService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local AfkRules = require(ReplicatedStorage.Shared.Util.Afk)
local Portals = require(ReplicatedStorage.Shared.Util.Portals)
local Progression = require(ReplicatedStorage.Shared.Util.Progression)
local Volumes = require(ReplicatedStorage.Shared.Util.Volumes)
local StatRules = require(ReplicatedStorage.Shared.Util.Stats)
local Analytics = require(script.Parent.Analytics)
local Passes = require(script.Parent.Passes)
local PlayerData = require(script.Parent.PlayerData)
local Stats = require(script.Parent.Stats)
local Sync = require(script.Parent.Sync)
local RateLimit = require(ServerScriptService.Server.Lib.RateLimit)

local AFK = Config.AFK
local CHECK_INTERVAL = 1
local ROOT_ABOVE = 3 -- a standing character's root is this far above the floor

type Session = {
	insideSince: number, -- os.clock()
	active: boolean,
	perSecond: number,
	carry: number, -- Volts earned but not paid yet (under 1 after a payment)
	lastRecompute: number,
	lastPay: number,
	activeAt: number, -- os.clock() when earning started
}

local sessions: { [Player]: Session } = {}
local rejoining: { [Player]: number } = {} -- AfkRejoin attempts made (1 or 2)

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
	Stats.add(player, StatRules.VOLTS_EARNED, whole)
end

-- AfkMinutes: how long this AFK session earned for.
local function logMinutes(session: Session, player: Player)
	if session.active then
		Analytics.afkMinutes(player, (os.clock() - session.activeAt) / 60)
	end
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
	logMinutes(session, player)
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
		activeAt = now,
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
		session.activeAt = now
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

-- Where someone arriving in the lounge stands: the middle of its floor,
-- facing the way in. nil when there's no lounge.
function Afk.loungeArrival(): CFrame?
	for _, instance in CollectionService:GetTagged(AfkRules.TAG) do
		if instance:IsA("BasePart") and instance:IsDescendantOf(workspace) then
			-- the box's bottom is 1 stud under the floor (Kit.afkZone)
			return instance.CFrame * CFrame.new(0, -instance.Size.Y / 2 + 1 + ROOT_ABOVE, 0)
		end
	end
	return nil
end

-- Puts the player in the lounge (the first world). Yields while the area
-- streams in. False when there's no lounge or no character.
function Afk.sendToLounge(player: Player): boolean
	local arrival = Afk.loungeArrival()
	local character = player.Character
	if not arrival or not character then
		return false
	end
	player:SetAttribute(Portals.WORLD_ATTRIBUTE, Config.WORLDS[1].id)
	pcall(player.RequestStreamAroundAsync, player, arrival.Position)
	character:PivotTo(arrival)
	return true
end

-- The backup: save, then move the player to a fresh server of this place,
-- back in the lounge there. Tried once more after rejoinRetrySeconds.
local function rejoin(player: Player)
	local attempt = (rejoining[player] or 0) + 1
	rejoining[player] = attempt
	if attempt == 1 then
		Analytics.afkRejoin(player)
	end
	PlayerData.saveNow(player)
	local options = Instance.new("TeleportOptions")
	options:SetTeleportData({ afk = true })
	local ok, err =
		pcall(TeleportService.TeleportAsync, TeleportService, game.PlaceId, { player }, options)
	if ok then
		return
	end
	if attempt < 2 then
		warn(
			`[Afk] moving {player.Name} to a fresh server failed ({err}); trying again in {AFK.rejoinRetrySeconds}s`
		)
		task.delay(AFK.rejoinRetrySeconds, function()
			if player.Parent and Afk.isAfk(player) then
				rejoin(player)
			end
		end)
	else
		warn(
			`[Afk] moving {player.Name} to a fresh server failed again ({err}); Roblox's idle kick will happen`
		)
	end
end

-- AfkRejoin from the client: rate-limited, and only while we agree they're AFK.
local function onRejoin(player: Player)
	if not RateLimit.allow(player, "AfkRejoin", 1 / 60, 2) or not Afk.isAfk(player) then
		return
	end
	if (rejoining[player] or 0) > 0 then
		return -- already on it
	end
	print(`[Afk] {player.Name} has been idle a long time: moving them to a fresh server`)
	task.spawn(rejoin, player)
end

-- Arrived from AfkRejoin (teleport data { afk = true }): straight back in
-- the lounge, where AFK starts again after enterSeconds.
local function onPlayerAdded(player: Player)
	local data = player:GetJoinData().TeleportData
	if typeof(data) ~= "table" or (data :: any).afk ~= true then
		return
	end
	local character = player.Character or player.CharacterAdded:Wait()
	if not character:WaitForChild("HumanoidRootPart", 10) then
		return
	end
	for _ = 1, 10 do
		if Afk.sendToLounge(player) then
			return
		end
		task.wait(1) -- the map may still be building
	end
end

function Afk.init()
	Net.get("AfkRejoin").OnServerEvent:Connect(onRejoin)
	TeleportService.TeleportInitFailed:Connect(function(player, result, message)
		if rejoining[player] == 1 and Afk.isAfk(player) then
			warn(
				`[Afk] teleport for {player.Name} failed to start ({result.Name}: {message}); trying again`
			)
			task.delay(AFK.rejoinRetrySeconds, function()
				if player.Parent and Afk.isAfk(player) then
					rejoin(player)
				end
			end)
		end
	end)
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
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local session = sessions[player]
		if session then
			logMinutes(session, player)
		end
		sessions[player] = nil
		rejoining[player] = nil
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
