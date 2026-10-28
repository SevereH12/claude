--!strict
-- The new-player tutorial (the rules: Util/Tutorial; the step cards, paths
-- and pointers: Controllers/Tutorial). The step is saved in the profile
-- (profile.tutorialStep) and sent in the snapshot; this module moves it on
-- when something happens:
--   Movement calls Tutorial.entered (in a zone), Strikes Tutorial.caught
--   (which also notices a full bottle), Selling Tutorial.sold and Shop
--   Tutorial.boughtBottle.
-- Finishing pays Config.TUTORIAL.rewardCharges charges (Systems/Rewards, so
-- it celebrates like any reward) and tells the client "finished" on the
-- Tutorial remote. Old players (a Vial or better, or ascended) never see it.
--
-- The Tutorial remote, client -> server: "skip" (after the client asked
-- "Skip the tutorial?"): rate-limited, and only a string is accepted.
-- Studio's TEST panel restarts it (Tutorial.restart, Systems/DevCommands).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Util.Formulas)
local Net = require(ReplicatedStorage.Shared.Net)
local TutorialRules = require(ReplicatedStorage.Shared.Util.Tutorial)
local Types = require(ReplicatedStorage.Shared.Types)
local Passes = require(script.Parent.Passes)
local PlayerData = require(script.Parent.PlayerData)
local Sync = require(script.Parent.Sync)

local Tutorial = {}

local remote: RemoteEvent
-- Lib/RateLimit and Systems/Rewards (which uses it), required in init:
-- Selling, Shop and Strikes require this module, and the harness can't load
-- RateLimit (it hooks PlayerRemoving when it loads)
local allow: (Player, string, number, number) -> boolean
local giveReward: (Player, Types.Profile, Types.Reward, string) -> ()
local caught: { [Player]: number } = {} -- step 2's catches this visit

-- Runs one event through the rules and saves the new step.
local function handle(player: Player, event: TutorialRules.Event)
	local profile = PlayerData.get(player)
	if not profile or not TutorialRules.isActive(profile.tutorialStep) then
		return
	end
	local before = profile.tutorialStep
	local after = TutorialRules.advance({ step = before, caught = caught[player] or 0 }, event)
	if event == "caught" and after.caught ~= (caught[player] or 0) then
		remote:FireClient(player, "caught", after.caught) -- the card's count
	end
	caught[player] = after.caught
	if after.step == before then
		return
	end
	if after.step == TutorialRules.FINISHED then
		profile.tutorialStep = TutorialRules.DONE
		caught[player] = nil
		giveReward(player, profile, { charges = Config.TUTORIAL.rewardCharges }, "Tutorial")
		remote:FireClient(player, "finished")
		print(`[Tutorial] {player.Name} finished the tutorial`)
	else
		profile.tutorialStep = after.step
	end
	Sync.markDirty(player)
end

function Tutorial.entered(player: Player, zone: Types.ZoneDef?)
	if zone then
		handle(player, "zone")
	end
end

-- A bolt went in the player's bottle (or tank); a full bottle moves on too.
function Tutorial.caught(player: Player)
	handle(player, "caught")
	local profile = PlayerData.get(player)
	if
		profile
		and TutorialRules.isActive(profile.tutorialStep)
		and Formulas.isFull(profile.chargeCount, Passes.capacity(player, profile))
	then
		handle(player, "full")
	end
end

function Tutorial.sold(player: Player)
	handle(player, "sold")
end

function Tutorial.boughtBottle(player: Player)
	handle(player, "bottle")
end

-- Studio TEST button: back to step 1 (whatever bottle they have: step 4
-- then asks for the next one).
function Tutorial.restart(player: Player)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	local progress = TutorialRules.restart()
	profile.tutorialStep = progress.step
	caught[player] = progress.caught
	Sync.markDirty(player)
end

local function onRemote(player: Player, action: unknown)
	if not allow(player, "Tutorial", 2, 4) or typeof(action) ~= "string" then
		return
	end
	if action ~= "skip" then
		return
	end
	local profile = PlayerData.get(player)
	if not profile or not TutorialRules.isActive(profile.tutorialStep) then
		return
	end
	profile.tutorialStep = TutorialRules.skip({ step = profile.tutorialStep, caught = 0 }).step
	caught[player] = nil
	Sync.markDirty(player)
	print(`[Tutorial] {player.Name} skipped the tutorial`)
end

function Tutorial.init()
	allow = require(ServerScriptService.Server.Lib.RateLimit).allow
	giveReward = require(script.Parent.Rewards).give
	remote = Net.get("Tutorial")
	remote.OnServerEvent:Connect(onRemote)
	-- old players (and anything odd) never see it
	PlayerData.Loaded:Connect(function(player: Player, profile: Types.Profile)
		profile.tutorialStep = TutorialRules.loadStep(profile)
		Sync.markDirty(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		caught[player] = nil
	end)
end

return Tutorial
