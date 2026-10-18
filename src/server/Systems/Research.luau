--!strict
-- Researchers: hiring, posting, set-up timers, field data and levels.
-- A researcher only exists as saved data here; perks (later parts) ask
-- Research.active() whether one is working for a player right now.
-- HireResearcher / PostResearcher are client requests: rate limit, type
-- checks, then every rule re-checked on the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local ResearchMath = require(ReplicatedStorage.Shared.Util.Research)
local Progression = require(ReplicatedStorage.Shared.Util.Progression)
local ResearchSites = require(ReplicatedStorage.Shared.Util.ResearchSites)
local Types = require(ReplicatedStorage.Shared.Types)
local Zones = require(ReplicatedStorage.Shared.Util.Zones)
local Formulas = require(ReplicatedStorage.Shared.Util.Formulas)
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

local function startSetup(player: Player, roleId: string, post: string)
	local timers = Sync.setupUntil[player]
	if not timers then
		timers = {}
		Sync.setupUntil[player] = timers
	end
	timers[roleId] = if post == "Office"
		then nil
		else workspace:GetServerTimeNow() + Config.RESEARCH_SETUP_TIME
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
	profile.researchers[roleId] = { level = 1, data = 0, post = "Office" }
	changed(player)
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
	-- researchers can only be posted to zones the player has unlocked
	local zone = Config.ZONES[post]
	if zone and not Progression.canEnter(profile, zone, Progression.playerIsPremium(player)) then
		return
	end
	save.post = post
	startSetup(player, roleId, post)
	changed(player)
end

local function onLoaded(player: Player, profile: Types.Profile)
	for roleId, save in profile.researchers do
		-- a saved post naming a zone that no longer exists falls back to the Office
		if not ResearchMath.isValidPost(save.post) then
			save.post = "Office"
		end
		startSetup(player, roleId, save.post)
	end
	changed(player)
end

-- The researcher's level if they are posted to the zone the player is
-- standing in and have finished setting up, otherwise nil.
function Research.active(player: Player, roleId: string): number?
	local profile = PlayerData.get(player)
	local save = if profile then profile.researchers[roleId] else nil
	if not save or save.post == "Office" then
		return nil
	end
	local timers = Sync.setupUntil[player]
	local readyAt = if timers then timers[roleId] else nil
	if readyAt and workspace:GetServerTimeNow() < readyAt then
		return nil
	end
	local root = liveRoot(player)
	local zone = if root then Zones.at(root.Position) else nil
	if not zone or zone.id ~= save.post then
		return nil
	end
	return save.level
end

-- Called once per landed strike. Every researcher posted to that zone watches
-- it for their owner: +1 data, or +3 if the owner caught it.
function Research.onStrikeLanded(zoneId: string, catchers: { number })
	local caughtBy: { [number]: boolean } = {}
	for _, userId in catchers do
		caughtBy[userId] = true
	end
	for _, player in Players:GetPlayers() do
		local profile = PlayerData.get(player)
		if profile then
			local gained = false
			for _, save in profile.researchers do
				if save.post == zoneId then
					save.data += if caughtBy[player.UserId]
						then Config.RESEARCH_DATA_CATCH
						else Config.RESEARCH_DATA_WATCH
					save.level = math.max(save.level, ResearchMath.levelFor(save.data))
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
	local room = Formulas.capacity(profile.bottleTier) - profile.chargeCount
	if room <= 0 then
		return
	end
	local moved = math.min(room, profile.tankCount)
	local value = profile.tankValue * moved / profile.tankCount
	profile.chargeCount += moved
	profile.chargeValue += value
	profile.tankCount -= moved
	profile.tankValue = if profile.tankCount == 0 then 0 else profile.tankValue - value
	Sync.markDirty(player)
end

-- Storm Chaser: while active during a storm, a balloon bolt every N seconds.
local function balloonTick(player: Player, now: number)
	local level = Research.active(player, "StormChaser")
	if not level or not StormCycle.isStorming() then
		balloonAt[player] = nil
		return
	end
	local dueAt = balloonAt[player]
	if not dueAt then
		balloonAt[player] = now + ResearchMath.balloonInterval(level)
		return
	end
	if now < dueAt then
		return
	end
	-- required here: Strikes requires this module
	local Strikes = (require :: any)(script.Parent.Strikes)
	if Strikes.spawnFor(player) then
		balloonAt[player] = now + ResearchMath.balloonInterval(level)
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
	PlayerData.Loaded:Connect(onLoaded)
end

return Research
