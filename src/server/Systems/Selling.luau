--!strict
-- Selling: stand at a sell station and your charges turn into Volts.
--
-- Each station has an invisible box tagged "SellArea" (CollectionService)
-- over its pad. The server checks every player's position several times a
-- second; anyone inside a SellArea with charges sells. This deliberately
-- does NOT use Touched: touch events depend on the player's client
-- reporting the contact, which can silently stop working (streaming,
-- replaced parts, touch replication). Position checks on the server can't.
-- The only sell remote is RemoteSell, for owners of the Remote Sell pass
-- (Systems/RemoteSell): it pays through Selling.payOut, like a station.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Types = require(ReplicatedStorage.Shared.Types)
local Volumes = require(ReplicatedStorage.Shared.Util.Volumes)
local Analytics = require(script.Parent.Analytics)
local Map = require(script.Parent.Map)
local Passes = require(script.Parent.Passes)
local PlayerData = require(script.Parent.PlayerData)
local ServerGoal = require(script.Parent.ServerGoal)
local Sync = require(script.Parent.Sync)

local SELL_TAG = "SellArea"
local CHECK_INTERVAL = 0.15
-- Maps built before SellArea existed only have a pad: sell above it.
local LEGACY_PAD_HEIGHT = 12
local LEGACY_PAD_MARGIN = 2

local lastSell: { [Player]: number } = {}
local soldRemote: RemoteEvent

local Selling = {}

local function sellAreas(): { BasePart }
	local areas: { BasePart } = {}
	for _, instance in CollectionService:GetTagged(SELL_TAG) do
		if instance:IsA("BasePart") and instance:IsDescendantOf(workspace) then
			table.insert(areas, instance)
		end
	end
	return areas
end

-- Is this position at a sell station?
function Selling.isAtStation(position: Vector3): boolean
	local areas = sellAreas()
	for _, area in areas do
		if Volumes.contains(area, position) then
			return true
		end
	end
	if #areas == 0 then
		local pad = Map.sellPad()
		if pad and Volumes.aboveTop(pad, position, LEGACY_PAD_HEIGHT, LEGACY_PAD_MARGIN) then
			return true
		end
	end
	return false
end

local function livingRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	return root
end

-- Turns everything in the bottle into Volts (2x Volts, VIP and the free
-- trial included). Every sale, at a station or remote, goes through here.
-- The Sold pop-up also gets what 2x Volts would have added (Controllers/
-- Offers uses it).
function Selling.payOut(player: Player, profile: Types.Profile)
	local earned, missed = Passes.payout(player, profile.chargeValue)
	local count = profile.chargeCount
	profile.volts += earned
	profile.totalVolts += earned
	profile.chargeCount = 0
	profile.chargeValue = 0
	Sync.markDirty(player)
	Analytics.sold(player, earned)
	ServerGoal.add(player, earned) -- every sale fills the server goal
	soldRemote:FireClient(player, earned, count, missed)
end

-- The station path: alive, inside a SellArea, with charges.
local function sellAtStation(player: Player)
	local profile = PlayerData.get(player)
	if not profile or profile.chargeCount <= 0 then
		return
	end
	local now = os.clock()
	if now - (lastSell[player] or 0) < Config.SELL_COOLDOWN then
		return
	end
	local root = livingRoot(player)
	if not root or not Selling.isAtStation(root.Position) then
		return
	end
	lastSell[player] = now
	Selling.payOut(player, profile)
end

-- Is this player alive (a character with health)?
function Selling.isAlive(player: Player): boolean
	return livingRoot(player) ~= nil
end

function Selling.init()
	soldRemote = Net.get("Sold")
end

function Selling.start()
	if #sellAreas() == 0 and not Map.sellPad() then
		warn(
			`[Selling] no part tagged "{SELL_TAG}" and no Map.PowerPlant.SellPad; selling disabled`
		)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastSell[player] = nil
	end)
	while true do
		task.wait(CHECK_INTERVAL)
		for _, player in Players:GetPlayers() do
			sellAtStation(player)
		end
	end
end

return Selling
