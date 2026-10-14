--!strict
-- Step on the Power Plant pad to turn charges into Volts. The server sees
-- the touch itself; there's no "sell" remote for a client to spam.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Map = require(script.Parent.Map)
local PlayerData = require(script.Parent.PlayerData)
local Sync = require(script.Parent.Sync)

local lastSell: { [Player]: number } = {}

local Selling = {}

-- Is the player's root actually over the pad (not just a flung limb)?
local function standingOn(root: BasePart, pad: BasePart): boolean
	local localPos = pad.CFrame:PointToObjectSpace(root.Position)
	local margin = 4
	return math.abs(localPos.X) <= pad.Size.X / 2 + margin
		and math.abs(localPos.Z) <= pad.Size.Z / 2 + margin
		and localPos.Y >= -2
		and localPos.Y <= 10
end

local function trySell(soldRemote: RemoteEvent, pad: BasePart, hit: BasePart)
	local character = hit.Parent
	if not character then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end
	local now = os.clock()
	if now - (lastSell[player] or 0) < Config.SELL_COOLDOWN then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") or not standingOn(root, pad) then
		return
	end
	local profile = PlayerData.get(player)
	if not profile or profile.chargeCount <= 0 then
		return
	end
	lastSell[player] = now

	local earned = profile.chargeValue
	local count = profile.chargeCount
	profile.volts += earned
	profile.totalVolts += earned
	profile.chargeCount = 0
	profile.chargeValue = 0
	Sync.markDirty(player)
	soldRemote:FireClient(player, earned, count)
end

function Selling.start()
	local pad = Map.sellPad()
	if not pad then
		warn("[Selling] no Workspace.Map.PowerPlant.SellPad part; selling disabled")
		return
	end
	local soldRemote = Net.get("Sold")
	pad.Touched:Connect(function(hit)
		trySell(soldRemote, pad, hit)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastSell[player] = nil
	end)
end

return Selling
