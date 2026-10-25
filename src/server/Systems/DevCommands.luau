--!strict
-- TEMPORARY test tool: the client's TEST buttons (Controllers/DevCommands)
-- send DevCommand: "volts" sets that player's Volts, "premium" turns
-- Pretend Premium on or off, "pass" pretends to own a Game Pass, and
-- "nextDay", "playtime" and "clearBoosts" test rewards (a day later, +5
-- minutes of play, no boosts and no Server Storm), "group" pretends to be a
-- group member, "testGift" puts a gift of a pass you don't have (or, with
-- true, a 2x Volts Boost) in your own inbox, and "serverStorm" starts a
-- Server Storm as if you bought one, "researchData" gives every
-- researcher 500 field data and "glints" 100 Glints of the tier of the zone
-- you're in (or your best zone), "goldenBolt" drops a golden bolt where you
-- stand, "supercell" starts a Supercell in 30 s and "event" (true/false)
-- pretends the first scheduled event is on, and "serverGoal" fills a
-- quarter of the server goal as if you sold it. The repo and client code are public, so this
-- is the lock: it only obeys in Studio play tests or, in a live server, the
-- user who owns the place; everything but "volts" is Studio only. To remove it:
-- delete this file and Controllers/DevCommands.luau, and take "DevCommand"
-- out of Shared/Remotes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Progression = require(ReplicatedStorage.Shared.Util.Progression)
local ResearchMath = require(ReplicatedStorage.Shared.Util.Research)
local Weather = require(ReplicatedStorage.Shared.Util.Weather)
local Zones = require(ReplicatedStorage.Shared.Util.Zones)
local Boosts = require(script.Parent.Boosts)
local Gifts = require(script.Parent.Gifts)
local Group = require(script.Parent.Group)
local Passes = require(script.Parent.Passes)
local PlayerData = require(script.Parent.PlayerData)
local Research = require(script.Parent.Research)
local Rewards = require(script.Parent.Rewards)
local ServerGoal = require(script.Parent.ServerGoal)
local StormCycle = require(script.Parent.StormCycle)
local Strikes = require(script.Parent.Strikes)
local Sync = require(script.Parent.Sync)
local RateLimit = require(ServerScriptService.Server.Lib.RateLimit)

local INFINITE_VOLTS = 1e12
local PLAYTIME_STEP = 5 * 60 -- seconds "+5 min playtime" adds

local DevCommands = {}

local function isOwner(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	-- a group-owned place has a group id here, so only Studio works there
	return game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId
end

local function setVolts(player: Player, amount: unknown)
	local volts = INFINITE_VOLTS
	if amount ~= nil then
		if
			typeof(amount) ~= "number"
			or amount ~= amount
			or amount < 0
			or amount > INFINITE_VOLTS
		then
			return
		end
		volts = math.floor(amount)
	end
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	profile.volts = volts
	Sync.markDirty(player)
	print(`[DevCommands] {player.Name} set Volts to {volts}`)
end

-- Lets a tester without Premium try the Premium zone. Progression also
-- ignores the attribute outside Studio.
local function setPretendPremium(player: Player, on: unknown)
	if not RunService:IsStudio() or typeof(on) ~= "boolean" then
		return
	end
	player:SetAttribute(Progression.PRETEND_PREMIUM, on)
	Sync.markDirty(player)
	print(`[DevCommands] {player.Name} Pretend Premium {if on then "on" else "off"}`)
end

-- "Pretend owns <pass>": Passes.setPretend ignores it outside Studio.
local function setPretendPass(player: Player, key: unknown, on: unknown)
	if not RunService:IsStudio() or typeof(key) ~= "string" or typeof(on) ~= "boolean" then
		return
	end
	Passes.setPretend(player, key, on)
	print(`[DevCommands] {player.Name} Pretend owns {key} {if on then "on" else "off"}`)
end

local function onCommand(player: Player, name: unknown, value: unknown, extra: unknown)
	if not RateLimit.allow(player, "DevCommand", 2, 4) or not isOwner(player) then
		return
	end
	if name == "volts" then
		setVolts(player, value)
	elseif name == "premium" then
		setPretendPremium(player, value)
	elseif name == "pass" then
		setPretendPass(player, value, extra)
	elseif not RunService:IsStudio() then
		return
	elseif name == "nextDay" then
		Rewards.nextDay(player)
		print(`[DevCommands] {player.Name}: a day later`)
	elseif name == "playtime" then
		Rewards.addPlaytime(player, PLAYTIME_STEP)
		print(`[DevCommands] {player.Name}: +5 min playtime`)
	elseif name == "clearBoosts" then
		Boosts.clear(player)
		Boosts.endStorm()
		Boosts.endSurge()
		print(`[DevCommands] {player.Name}: boosts cleared`)
	elseif name == "testGift" then
		Gifts.testGift(player, value == true)
		print(`[DevCommands] {player.Name}: a test gift is on its way`)
	elseif name == "serverStorm" then
		Boosts.startStorm(player)
	elseif name == "researchData" then
		Research.addData(player, 500)
		print(`[DevCommands] {player.Name}: +500 data to every researcher`)
	elseif name == "glints" then
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local profile = PlayerData.get(player)
		local zone = if root and root:IsA("BasePart") then Zones.at(root.Position) else nil
		zone = zone or (if profile then Progression.bestZone(profile) else nil)
		local tier = if zone then ResearchMath.zoneTier(zone) else 0
		Research.addGlints(player, tier, 100)
		print(`[DevCommands] {player.Name}: +100 tier {tier} Glints`)
	elseif name == "goldenBolt" then
		local ok = Strikes.forceAt(player, "Golden")
		print(
			`[DevCommands] {player.Name}: golden bolt {if ok
				then "coming"
				else "needs you in a zone"}`
		)
	elseif name == "supercell" then
		StormCycle.supercellIn(Config.SUPERCELL.warningSeconds)
		print(`[DevCommands] {player.Name}: Supercell in {Config.SUPERCELL.warningSeconds}s`)
	elseif name == "serverGoal" then
		ServerGoal.testFill(player, 0.25)
		print(`[DevCommands] {player.Name}: +25% server goal`)
	elseif name == "event" and typeof(value) == "boolean" then
		workspace:SetAttribute(Weather.PRETEND_EVENT, value)
		Sync.markDirty(player)
		print(`[DevCommands] {player.Name}: pretend event {if value then "on" else "off"}`)
	elseif name == "group" and typeof(value) == "boolean" then
		Group.setPretend(player, value)
		print(`[DevCommands] {player.Name} Pretend group member {if value then "on" else "off"}`)
	end
end

function DevCommands.init()
	Net.get("DevCommand").OnServerEvent:Connect(onCommand)
end

return DevCommands
