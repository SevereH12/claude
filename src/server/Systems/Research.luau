--!strict
-- Researchers: hiring, posting, set-up timers, field data, levels, ranks
-- and Glints. A researcher only exists as saved data here; perks ask
-- Research.active() whether one is working for a player right now (and at
-- what level and rank). HireResearcher / PostResearcher / PromoteResearcher
-- are client requests: rate limit, type checks, then every rule re-checked
-- on the server. A researcher can only be posted to zones of their rank's
-- tier or lower; each bolt the player catches gives a Glint of that zone's
-- tier; promotion (at the Research Office, Util/Research.canPromote) spends
-- Glints and resets them to level 1 a rank higher.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local PassRules = require(ReplicatedStorage.Shared.Util.Passes)
local ResearchMath = require(ReplicatedStorage.Shared.Util.Research)
local Progression = require(ReplicatedStorage.Shared.Util.Progression)
local ResearchSites = require(ReplicatedStorage.Shared.Util.ResearchSites)
local Types = require(ReplicatedStorage.Shared.Types)
local Zones = require(ReplicatedStorage.Shared.Util.Zones)
local Analytics = require(script.Parent.Analytics)
local Passes = require(script.Parent.Passes)
local PlayerData = require(script.Parent.PlayerData)
local StormCycle = require(script.Parent.StormCycle)
local Sync = require(script.Parent.Sync)
local RateLimit = require(ServerScriptService.Server.Lib.RateLimit)

local CHECK_INTERVAL = 0.15

local balloonAt: { [Player]: number } = {} -- os.clock() when the next balloon bolt is due

local Research = {}

local function liveRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Every client reads these to know who has which researcher where.
local function refreshAttributes(player: Player)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	for _, def in Config.RESEARCHERS do
		local save = profile.researchers[def.id]
		player:SetAttribute(`Research_{def.id}`, if save then `{save.post}:{save.level}` else nil)
	end
end

-- A researcher posted to a zone needs RESEARCH_SETUP_TIME before their perk
-- works (none with the Lab Grant pass).
local function startSetup(player: Player, roleId: string, post: string)
	local timers = Sync.setupUntil[player]
	if not timers then
		timers = {}
		Sync.setupUntil[player] = timers
	end
	local seconds = PassRules.setupTime(Config.RESEARCH_SETUP_TIME, Passes.owned(player))
	timers[roleId] = if post == "Office" or seconds <= 0
		then nil
		else workspace:GetServerTimeNow() + seconds
end

local function changed(player: Player)
	refreshAttributes(player)
	Sync.markDirty(player)
end

local function onHire(player: Player, roleId: unknown)
	if not RateLimit.allow(player, "HireResearcher", 2, 4) then
		return
	end
	if typeof(roleId) ~= "string" then
		return
	end
	local profile = PlayerData.get(player)
	local root = liveRoot(player)
	if not profile or not root or not ResearchSites.inOffice(root.Position) then
		return
	end
	-- researchers are hired in order, once each
	local index = 0
	for i, def in Config.RESEARCHERS do
		if def.id == roleId then
			index = i
		end
	end
	if index == 0 or profile.researchers[roleId] then
		return
	end
	if index > 1 and not profile.researchers[Config.RESEARCHERS[index - 1].id] then
		return
	end
	local def = Config.RESEARCHERS[index]
	if profile.volts < def.price then -- price from the server's catalog
		return
	end
	profile.volts -= def.price
	profile.researchers[roleId] = { level = 1, data = 0, post = "Office", rank = 0 }
	changed(player)
	Analytics.hired(player, def)
end

local function onPost(player: Player, roleId: unknown, post: unknown)
	if not RateLimit.allow(player, "PostResearcher", 3, 6) then
		return
	end
	if typeof(roleId) ~= "string" or typeof(post) ~= "string" then
		return
	end
	if not ResearchMath.isValidPost(post) then
		return
	end
	local profile = PlayerData.get(player)
	local save = if profile then profile.researchers[roleId] else nil
	if not profile or not save or save.post == post then
		return
	end
	-- researchers can only be posted to zones the player has unlocked, and
	-- of their rank's tier or lower ("Needs rank 3": the client shows it)
	local zone = Config.ZONES[post]
	if zone and not Progression.canEnter(profile, zone, Progression.playerIsPremium(player)) then
		return
	end
	if zone and not ResearchMath.canPost(save.rank, zone) then
		return
	end
	save.post = post
	startSetup(player, roleId, post)
	changed(player)
end

-- Promotes a level-5 researcher at the Research Office: spends the Glints,
-- then level 1, no data, one rank higher.
local function onPromote(player: Player, roleId: unknown)
	if not RateLimit.allow(player, "PromoteResearcher", 1, 3) then
		return
	end
	if typeof(roleId) ~= "string" then
		return
	end
	local profile = PlayerData.get(player)
	local save = if profile then profile.researchers[roleId] else nil
	local root = liveRoot(player)
	if not profile or not save or not root or not ResearchSites.inOffice(root.Position) then
		return
	end
	if not ResearchMath.canPromote(save, profile.glints) then
		return
	end
	local spent = ResearchMath.spendGlints(profile.glints, save.rank + 1)
	if not spent then
		return
	end
	profile.glints = spent
	save.rank += 1
	save.level = 1
	save.data = 0
	print(`[Research] {player.Name} promoted {roleId} to rank {save.rank}`)
	changed(player)
end

-- Adds Glints of a zone's tier (Studio TEST and the catch hook).
function Research.addGlints(player: Player, tier: number, count: number)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	for t = 0, math.max(tier, ResearchMath.maxRank()) do
		profile.glints[t + 1] = profile.glints[t + 1] or 0 -- saved as a list: no holes
	end
	profile.glints[tier + 1] += count
	Sync.markDirty(player)
end

-- Studio TEST: field data for every researcher (levels follow).
function Research.addData(player: Player, amount: number)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	for _, save in profile.researchers do
		save.data += amount
		save.level = math.max(save.level, ResearchMath.levelFor(save.data, save.rank))
	end
	changed(player)
end

local function onLoaded(player: Player, profile: Types.Profile)
	for roleId, save in profile.researchers do
		-- a saved post naming a zone that no longer exists falls back to the Office
		if not ResearchMath.isValidPost(save.post) then
			save.post = "Office"
		end
		save.rank = save.rank or 0
		startSetup(player, roleId, save.post)
	end
	changed(player)
	-- Lab Grant bought (or its Studio toggle turned on) mid-setup: every
	-- researcher is ready at once
	player:GetAttributeChangedSignal(Passes.ATTRIBUTE .. "LabGrant"):Connect(function()
		if Passes.owns(player, "LabGrant") and Sync.setupUntil[player] then
			table.clear(Sync.setupUntil[player])
			changed(player)
		end
	end)
end

-- The researcher's level and rank if they are posted to the zone the player
-- is standing in and have finished setting up, otherwise nil.
function Research.active(player: Player, roleId: string): (number?, number)
	local profile = PlayerData.get(player)
	local save = if profile then profile.researchers[roleId] else nil
	if not save or save.post == "Office" then
		return nil, 0
	end
	local timers = Sync.setupUntil[player]
	local readyAt = if timers then timers[roleId] else nil
	if readyAt and workspace:GetServerTimeNow() < readyAt then
		return nil, 0
	end
	local root = liveRoot(player)
	local zone = if root then Zones.at(root.Position) else nil
	if not zone or zone.id ~= save.post then
		return nil, 0
	end
	return save.level, save.rank
end

-- Called once per landed strike. Every researcher posted to that zone watches
-- it for their owner: +1 data, or +3 if the owner caught it (double with
-- the Lab Grant pass). Everyone who caught it (bottle or tank, a balloon
-- bolt too) gets a Glint of the zone's tier.
function Research.onStrikeLanded(zoneId: string, catchers: { number })
	local caughtBy: { [number]: boolean } = {}
	for _, userId in catchers do
		caughtBy[userId] = true
	end
	local zone = Config.ZONES[zoneId]
	for _, player in Players:GetPlayers() do
		local profile = PlayerData.get(player)
		if profile and zone and caughtBy[player.UserId] then
			Research.addGlints(player, ResearchMath.zoneTier(zone), 1)
		end
		if profile then
			local gained = false
			local owned = Passes.owned(player)
			for _, save in profile.researchers do
				if save.post == zoneId then
					save.data += PassRules.fieldData(
						if caughtBy[player.UserId]
							then Config.RESEARCH_DATA_CATCH
							else Config.RESEARCH_DATA_WATCH,
						owned
					)
					save.level = math.max(save.level, ResearchMath.levelFor(save.data, save.rank))
					gained = true
				end
			end
			if gained then
				-- level-ups reach the client as a change in Research_<RoleId>
				changed(player)
			end
		end
	end
end

-- Chemist: standing at the camp of the zone she is posted to, with room in
-- your bottle, empties her tank into it. A position check like Selling's.
local function emptyTank(player: Player, profile: Types.Profile)
	local save = profile.researchers.Chemist
	if not save or save.post == "Office" or profile.tankCount <= 0 then
		return
	end
	local setup = Sync.setupUntil[player]
	local readyAt = setup and setup.Chemist
	if readyAt and workspace:GetServerTimeNow() < readyAt then
		return
	end
	local root = liveRoot(player)
	if not root or ResearchSites.campAt(root.Position) ~= save.post then
		return
	end
	local room = Passes.capacity(player, profile) - profile.chargeCount
	if room <= 0 then
		return
	end
	-- units and their Volts move together: all of it, or that fraction
	local moved = math.min(room, profile.tankCount)
	local value = if moved == profile.tankCount
		then profile.tankValue
		else math.floor(profile.tankValue * moved / profile.tankCount)
	profile.chargeCount += moved
	profile.chargeValue += value
	profile.tankCount -= moved
	profile.tankValue = if profile.tankCount == 0 then 0 else profile.tankValue - value
	Sync.markDirty(player)
end

-- Storm Chaser: while active during a storm, a balloon bolt every N seconds.
local function balloonTick(player: Player, now: number)
	local level, rank = Research.active(player, "StormChaser")
	if not level or not StormCycle.isStorming() then
		balloonAt[player] = nil
		return
	end
	local dueAt = balloonAt[player]
	if not dueAt then
		balloonAt[player] = now + ResearchMath.balloonInterval(level, rank)
		return
	end
	if now < dueAt then
		return
	end
	-- required here: Strikes requires this module
	local Strikes = (require :: any)(script.Parent.Strikes)
	if Strikes.spawnFor(player) then
		balloonAt[player] = now + ResearchMath.balloonInterval(level, rank)
	else
		balloonAt[player] = now + 1 -- no room or one still in flight; try again soon
	end
end

function Research.start()
	task.delay(5, function()
		if #ResearchSites.offices() == 0 then
			warn(
				"[Research] no ResearchOffice in the map, so nobody can hire researchers. "
					.. "Click Update Game to rebuild the map."
			)
		end
	end)
	while true do
		task.wait(CHECK_INTERVAL)
		local now = os.clock()
		for _, player in Players:GetPlayers() do
			local profile = PlayerData.get(player)
			if profile then
				emptyTank(player, profile)
				balloonTick(player, now)
			end
		end
	end
end

function Research.init()
	Players.PlayerRemoving:Connect(function(player)
		balloonAt[player] = nil
	end)
	Net.get("HireResearcher").OnServerEvent:Connect(onHire)
	Net.get("PostResearcher").OnServerEvent:Connect(onPost)
	Net.get("PromoteResearcher").OnServerEvent:Connect(onPromote)
	PlayerData.Loaded:Connect(onLoaded)
end

return Research
